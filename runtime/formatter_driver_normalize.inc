static int weave_fmt_plan_list(
    weave_fmt_context *context,
    int64_t list,
    weave_fmt_plan *plan) {
    memset(plan, 0, sizeof(*plan));
    int64_t head = node_first_child(context->tree, list);
    if (head == -1 || node_kind(context->tree, head) != node_ident()) {
        return 0;
    }
    plan->kind = WEAVE_FMT_PLAN_NORMAL;
    if (weave_fmt_node_text_equals(context, head, "new")) {
        const weave_fmt_struct *structure = weave_fmt_lookup_struct_node(
            context, weave_fmt_nth_child(context, list, 1));
        if (weave_fmt_constructor_is_canonicalizable(
                context, list, structure)) {
            plan->kind = WEAVE_FMT_PLAN_CONSTRUCTOR;
            plan->virtual_head = "new";
            plan->structure = structure;
        }
        return 1;
    }
    if (weave_fmt_node_text_equals(context, head, "call")) {
        plan->kind = WEAVE_FMT_PLAN_CALL;
        plan->virtual_head = "call";
        plan->signature = weave_fmt_lookup_signature_node(
            context, weave_fmt_nth_child(context, list, 1));
        return 1;
    }
    size_t base_length = 0;
    weave_fmt_type call_type = weave_fmt_parse_typed_suffix(
        context, head, &base_length);
    if (call_type != WEAVE_FMT_UNKNOWN && base_length == 4 &&
        memcmp(
            context->source + (size_t)node_text_start(context->tree, head),
            "call",
            4) == 0) {
        const weave_fmt_signature *signature = weave_fmt_lookup_signature_node(
            context, weave_fmt_nth_child(context, list, 1));
        // A confirmed matching signature is always safe to rewrite. An
        // unresolved signature is normally still safe (the callee is simply
        // declared in another source file, and cross-file typed calls are
        // meant to normalize), UNLESS this file also declares a struct: its
        // field accessors are synthesized during a later lowering pass and
        // never appear as a literal fn/extern declaration, so they can never
        // be found by the scan above. Since an unresolved name in such a
        // file could be exactly that unrewritable accessor, retain the
        // original typed spelling rather than guessing.
        if (signature != NULL) {
            if (signature->return_type == call_type) {
                plan->kind = WEAVE_FMT_PLAN_CALL;
                plan->virtual_head = "call";
                plan->signature = signature;
            }
        } else if (!context->has_struct_declarations) {
            plan->kind = WEAVE_FMT_PLAN_CALL;
            plan->virtual_head = "call";
            plan->signature = NULL;
        }
        return 1;
    }
    if (weave_fmt_node_text_equals(context, head, "op")) {
        plan->kind = WEAVE_FMT_PLAN_OPERATOR;
        plan->virtual_head = "op";
        int64_t name = weave_fmt_nth_child(context, list, 1);
        if (name != -1 &&
            (weave_fmt_node_text_equals(context, name, "and") ||
             weave_fmt_node_text_equals(context, name, "or") ||
             weave_fmt_node_text_equals(context, name, "not"))) {
            plan->encoded_type = WEAVE_FMT_BOOL;
            plan->comparison_or_boolean = 1;
        } else {
            int64_t left = weave_fmt_nth_child(context, list, 2);
            int64_t right = weave_fmt_nth_child(context, list, 3);
            plan->encoded_type = weave_fmt_infer_canonical_operand_type(
                context, left, right);
            if (name != -1 &&
                (weave_fmt_node_text_equals(context, name, "equal") ||
                 weave_fmt_node_text_equals(context, name, "not-equal") ||
                 weave_fmt_node_text_equals(context, name, "less-than") ||
                 weave_fmt_node_text_equals(context, name, "less-or-equal") ||
                 weave_fmt_node_text_equals(context, name, "greater-than") ||
                 weave_fmt_node_text_equals(context, name, "greater-or-equal"))) {
                plan->comparison_or_boolean = 1;
            }
        }
        return 1;
    }
    weave_fmt_type operand_type = WEAVE_FMT_UNKNOWN;
    int bool_result = 0;
    const char *operator_name = weave_fmt_operator_name(
        context, head, &operand_type, &bool_result);
    if (operator_name != NULL) {
        plan->kind = WEAVE_FMT_PLAN_OPERATOR;
        plan->virtual_head = "op";
        plan->virtual_second = operator_name;
        plan->encoded_type = operand_type;
        plan->comparison_or_boolean = bool_result;
        return 1;
    }
    if (weave_fmt_node_text_equals(context, head, "cast")) {
        plan->kind = WEAVE_FMT_PLAN_CAST;
        plan->virtual_head = "cast";
        return 1;
    }
    weave_fmt_type cast_source = WEAVE_FMT_UNKNOWN;
    weave_fmt_type cast_target = WEAVE_FMT_UNKNOWN;
    if (weave_fmt_parse_cast_head(
            context, head, &cast_source, &cast_target)) {
        plan->kind = WEAVE_FMT_PLAN_CAST;
        plan->virtual_head = "cast";
        plan->virtual_second = weave_fmt_type_name(cast_target);
        plan->encoded_type = cast_source;
        return 1;
    }
    return 1;
}

static int weave_fmt_can_unwrap_access(
    weave_fmt_context *context,
    int64_t list,
    int64_t head,
    int64_t *name_out) {
    if (weave_fmt_list_has_comments(context, list) ||
        weave_fmt_child_count(context, list) != 2) {
        return 0;
    }
    weave_fmt_binding_kind kind;
    if (weave_fmt_node_text_equals(context, head, "param_get")) {
        kind = WEAVE_FMT_BINDING_PARAM;
    } else if (weave_fmt_node_text_equals(context, head, "local_get")) {
        kind = WEAVE_FMT_BINDING_LOCAL;
    } else {
        return 0;
    }
    int64_t name = weave_fmt_nth_child(context, list, 1);
    if (weave_fmt_lookup_binding(context, name, kind) == WEAVE_FMT_UNKNOWN) {
        return 0;
    }
    *name_out = name;
    return 1;
}

static int weave_fmt_constant_replacement(
    weave_fmt_context *context,
    int64_t list,
    int64_t head,
    weave_fmt_type expected,
    int64_t *value_out,
    weave_fmt_type *cast_target_out,
    const char **literal_out) {
    *value_out = -1;
    *cast_target_out = WEAVE_FMT_UNKNOWN;
    *literal_out = NULL;
    if (weave_fmt_list_has_comments(context, list)) return 0;
    weave_fmt_type type = weave_fmt_constant_type(context, head);
    if (type == WEAVE_FMT_UNKNOWN) return 0;
    if (weave_fmt_node_text_equals(context, head, "const_null") &&
        weave_fmt_child_count(context, list) == 1 &&
        expected == WEAVE_FMT_PTR) {
        *literal_out = "null";
        return 1;
    }
    if (weave_fmt_child_count(context, list) != 2) return 0;
    int64_t value = weave_fmt_nth_child(context, list, 1);
    if (weave_fmt_node_text_equals(context, head, "const_bool") &&
        expected == WEAVE_FMT_BOOL &&
        (weave_fmt_node_text_equals(context, value, "true") ||
         weave_fmt_node_text_equals(context, value, "false"))) {
        *value_out = value;
        return 1;
    }
    if (weave_fmt_node_text_equals(context, head, "const_string_ptr") &&
        expected == WEAVE_FMT_PTR &&
        node_kind(context->tree, value) == node_string()) {
        *value_out = value;
        return 1;
    }
    if (!weave_fmt_type_is_numeric(type) ||
        node_kind(context->tree, value) != node_int()) {
        return 0;
    }
    if (expected == type) {
        *value_out = value;
        return 1;
    }
    if (expected == WEAVE_FMT_UNKNOWN &&
        weave_fmt_cast_pair_admitted(WEAVE_FMT_I32, type)) {
        *value_out = value;
        *cast_target_out = type;
        return 1;
    }
    return 0;
}

