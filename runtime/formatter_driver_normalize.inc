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
    if (weave_fmt_node_text_equals(context, head, "if") &&
        weave_fmt_list_headed(
            context, weave_fmt_nth_child(context, list, 1), "condition")) {
        int64_t cond = weave_fmt_named_body(
            context, weave_fmt_nth_child(context, list, 1), "condition");
        int64_t then_body = weave_fmt_unwrap_do_single(
            context,
            weave_fmt_named_body(
                context, weave_fmt_nth_child(context, list, 2), "then"));
        int64_t else_clause = weave_fmt_nth_child(context, list, 3);
        int64_t else_body = -1;
        if (else_clause != -1) {
            else_body = weave_fmt_unwrap_do_single(
                context, weave_fmt_named_body(context, else_clause, "else"));
            if (weave_fmt_do_is_empty(context, else_body) ||
                (weave_fmt_list_headed(context, else_clause, "else") &&
                 weave_fmt_named_body(context, else_clause, "else") != -1 &&
                 weave_fmt_do_is_empty(
                     context,
                     weave_fmt_named_body(context, else_clause, "else")))) {
                else_body = -1;
            }
            if (else_body != -1 &&
                weave_fmt_list_headed(context, else_clause, "else") &&
                weave_fmt_do_is_empty(
                    context,
                    weave_fmt_named_body(context, else_clause, "else"))) {
                else_body = -1;
            }
        }
        if (else_body == -1 || weave_fmt_do_is_empty(context, else_body)) {
            plan->kind = WEAVE_FMT_PLAN_CONTROL;
            plan->virtual_head = "when";
            plan->control_cond = cond;
            plan->control_then = then_body;
            plan->control_else = -1;
            plan->control_variadic = weave_fmt_list_headed(
                context, then_body, "do");
            return 1;
        }
        plan->kind = WEAVE_FMT_PLAN_CONTROL;
        plan->virtual_head = "if";
        plan->control_cond = cond;
        plan->control_then = then_body;
        plan->control_else = else_body;
        plan->control_variadic = 0;
        return 1;
    }
    if (weave_fmt_node_text_equals(context, head, "while") &&
        weave_fmt_list_headed(
            context, weave_fmt_nth_child(context, list, 1), "condition")) {
        int64_t cond = weave_fmt_named_body(
            context, weave_fmt_nth_child(context, list, 1), "condition");
        int64_t body = weave_fmt_nth_child(context, list, 2);
        plan->kind = WEAVE_FMT_PLAN_CONTROL;
        plan->virtual_head = "while";
        plan->control_cond = cond;
        plan->control_then = weave_fmt_list_headed(context, body, "do")
            ? body
            : body;
        plan->control_else = -1;
        plan->control_variadic = 1;
        return 1;
    }
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
        plan->callee_node = weave_fmt_nth_child(context, list, 1);
        plan->skip_name_child = 1;
        plan->signature = weave_fmt_lookup_signature_node(
            context, plan->callee_node);
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
                plan->callee_node = weave_fmt_nth_child(context, list, 1);
                plan->skip_name_child = 1;
                plan->signature = signature;
            }
        } else if (!context->has_struct_declarations) {
            plan->kind = WEAVE_FMT_PLAN_CALL;
            plan->callee_node = weave_fmt_nth_child(context, list, 1);
            plan->skip_name_child = 1;
            plan->signature = NULL;
        }
        return 1;
    }
    if (weave_fmt_node_text_equals(context, head, "op")) {
        int64_t name = weave_fmt_nth_child(context, list, 1);
        const char *compact = weave_fmt_compact_operator_from_name(context, name);
        if (compact != NULL) {
            plan->kind = WEAVE_FMT_PLAN_OPERATOR;
            plan->virtual_head = compact;
            plan->skip_name_child = 1;
            if (weave_fmt_compact_operator_is_boolean_logic(compact)) {
                plan->encoded_type = WEAVE_FMT_BOOL;
                plan->comparison_or_boolean = 1;
            } else {
                plan->encoded_type = weave_fmt_infer_canonical_operand_type(
                    context,
                    weave_fmt_nth_child(context, list, 2),
                    weave_fmt_nth_child(context, list, 3));
                plan->comparison_or_boolean =
                    weave_fmt_compact_operator_is_bool_result(compact);
            }
        }
        return 1;
    }
    if (weave_fmt_is_compact_operator_head(context, head)) {
        const char *compact = weave_fmt_compact_operator_from_name(context, head);
        plan->kind = WEAVE_FMT_PLAN_OPERATOR;
        plan->virtual_head = compact;
        plan->skip_name_child = 0;
        if (weave_fmt_compact_operator_is_boolean_logic(compact)) {
            plan->encoded_type = WEAVE_FMT_BOOL;
            plan->comparison_or_boolean = 1;
        } else {
            plan->encoded_type = weave_fmt_infer_canonical_operand_type(
                context,
                weave_fmt_nth_child(context, list, 1),
                weave_fmt_nth_child(context, list, 2));
            plan->comparison_or_boolean =
                weave_fmt_compact_operator_is_bool_result(compact);
        }
        return 1;
    }
    weave_fmt_type operand_type = WEAVE_FMT_UNKNOWN;
    int bool_result = 0;
    const char *operator_name = weave_fmt_operator_name(
        context, head, &operand_type, &bool_result);
    if (operator_name != NULL) {
        plan->kind = WEAVE_FMT_PLAN_OPERATOR;
        plan->virtual_head = operator_name;
        plan->skip_name_child = 0;
        plan->encoded_type = operand_type;
        plan->comparison_or_boolean = bool_result;
        return 1;
    }
    if (weave_fmt_lookup_signature_node(context, head) != NULL) {
        plan->kind = WEAVE_FMT_PLAN_CALL;
        plan->callee_node = head;
        plan->skip_name_child = 0;
        plan->signature = weave_fmt_lookup_signature_node(context, head);
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

