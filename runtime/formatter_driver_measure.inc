static weave_fmt_type weave_fmt_expected_for_normal_child(
    weave_fmt_context *context,
    int64_t list,
    int64_t head,
    size_t actual_index) {
    if (weave_fmt_node_text_equals(context, head, "let") && actual_index == 2) {
        return weave_fmt_type_from_text(
            context, weave_fmt_nth_child(context, list, 2));
    }
    if (weave_fmt_node_text_equals(context, head, "set") && actual_index == 1) {
        return weave_fmt_lookup_binding(
            context, weave_fmt_nth_child(context, list, 1), 0);
    }
    if (weave_fmt_node_text_equals(context, head, "return") && actual_index == 0) {
        return context->current_return_type;
    }
    if ((weave_fmt_node_text_equals(context, head, "condition") ||
         weave_fmt_node_text_equals(context, head, "requires") ||
         weave_fmt_node_text_equals(context, head, "ensures")) &&
        actual_index == 0) {
        return WEAVE_FMT_BOOL;
    }
    if (weave_fmt_node_text_equals(context, head, "const") && actual_index == 2) {
        return weave_fmt_type_from_text(
            context, weave_fmt_nth_child(context, list, 2));
    }
    if (weave_fmt_node_text_equals(context, head, "qgate") && actual_index >= 1) {
        return WEAVE_FMT_QUBIT;
    }
    if (weave_fmt_node_text_equals(context, head, "qmeasure") && actual_index == 0) {
        return WEAVE_FMT_QUBIT;
    }
    return WEAVE_FMT_UNKNOWN;
}

static weave_fmt_type weave_fmt_expected_for_child(
    weave_fmt_context *context,
    int64_t list,
    const weave_fmt_plan *plan,
    int64_t head,
    size_t actual_index) {
    if (plan->kind == WEAVE_FMT_PLAN_CALL) {
        if (actual_index == 0 || plan->signature == NULL) return WEAVE_FMT_UNKNOWN;
        size_t parameter_index = actual_index - 1;
        return parameter_index < plan->signature->parameter_count
            ? plan->signature->parameters[parameter_index]
            : WEAVE_FMT_UNKNOWN;
    }
    if (plan->kind == WEAVE_FMT_PLAN_OPERATOR) {
        size_t operand_index = plan->virtual_second != NULL
            ? actual_index : (actual_index == 0 ? SIZE_MAX : actual_index - 1);
        if (operand_index == SIZE_MAX) return WEAVE_FMT_UNKNOWN;
        return plan->encoded_type;
    }
    if (plan->kind == WEAVE_FMT_PLAN_CAST) {
        return WEAVE_FMT_UNKNOWN;
    }
    return weave_fmt_expected_for_normal_child(
        context, list, head, actual_index);
}

static int weave_fmt_measure_node(
    weave_fmt_context *context,
    int64_t node,
    weave_fmt_type expected,
    size_t limit);

static int weave_fmt_measure_virtual(const char *text, size_t *width, size_t limit) {
    size_t length = strlen(text);
    if (*width > limit || length > limit - *width) return 0;
    *width += length;
    return 1;
}

static int weave_fmt_list_requires_multiline(
    weave_fmt_context *context,
    int64_t list,
    int64_t head) {
    if (weave_fmt_node_text_equals(context, head, "program") ||
        weave_fmt_node_text_equals(context, head, "fn") ||
        weave_fmt_node_text_equals(context, head, "entry") ||
        weave_fmt_node_text_equals(context, head, "struct") ||
        weave_fmt_node_text_equals(context, head, "if") ||
        weave_fmt_node_text_equals(context, head, "while")) {
        return 1;
    }
    return weave_fmt_node_text_equals(context, head, "do") &&
        weave_fmt_child_count(context, list) > 2;
}

static int weave_fmt_measure_list(
    weave_fmt_context *context,
    int64_t list,
    weave_fmt_type expected,
    size_t limit) {
    (void)expected;
    int64_t head = node_first_child(context->tree, list);
    if (head == -1 || node_kind(context->tree, head) != node_ident() ||
        weave_fmt_list_has_comments(context, list) ||
        weave_fmt_list_requires_multiline(context, list, head)) {
        return -1;
    }
    int64_t access_name = -1;
    if (weave_fmt_can_unwrap_access(context, list, head, &access_name)) {
        return weave_fmt_measure_node(context, access_name, WEAVE_FMT_UNKNOWN, limit);
    }
    int64_t replacement_value = -1;
    weave_fmt_type cast_target = WEAVE_FMT_UNKNOWN;
    const char *literal = NULL;
    if (weave_fmt_constant_replacement(
            context,
            list,
            head,
            expected,
            &replacement_value,
            &cast_target,
            &literal)) {
        if (literal != NULL) return (int)strlen(literal);
        int value_width = weave_fmt_measure_node(
            context, replacement_value, WEAVE_FMT_UNKNOWN, limit);
        if (value_width < 0) return -1;
        if (cast_target == WEAVE_FMT_UNKNOWN) return value_width;
        const char *type_name = weave_fmt_type_name(cast_target);
        size_t width = 7 + strlen(type_name) + 1 + (size_t)value_width + 1;
        return width <= limit ? (int)width : -1;
    }

    weave_fmt_plan plan;
    if (!weave_fmt_plan_list(context, list, &plan)) return -1;
    size_t width = 1;
    if (plan.kind == WEAVE_FMT_PLAN_NORMAL) {
        int head_width = weave_fmt_measure_node(
            context, head, WEAVE_FMT_UNKNOWN, limit - width);
        if (head_width < 0) return -1;
        width += (size_t)head_width;
    } else if (!weave_fmt_measure_virtual(plan.virtual_head, &width, limit)) {
        return -1;
    }
    if (plan.virtual_second != NULL) {
        if (width == limit) return -1;
        ++width;
        if (!weave_fmt_measure_virtual(plan.virtual_second, &width, limit)) {
            return -1;
        }
    }

    int64_t child = node_next_sibling(context->tree, head);
    size_t actual_index = 0;
    while (child != -1) {
        if (width == limit) return -1;
        ++width;
        weave_fmt_type child_expected = weave_fmt_expected_for_child(
            context, list, &plan, head, actual_index);
        int child_width = weave_fmt_measure_node(
            context, child, child_expected, limit - width);
        if (child_width < 0 || (size_t)child_width > limit - width) return -1;
        width += (size_t)child_width;
        ++actual_index;
        child = node_next_sibling(context->tree, child);
    }
    if (width == limit) return -1;
    ++width;
    return (int)width;
}

static int weave_fmt_measure_node(
    weave_fmt_context *context,
    int64_t node,
    weave_fmt_type expected,
    size_t limit) {
    if (node == -1 || limit == 0) return -1;
    int32_t kind = node_kind(context->tree, node);
    if (kind == node_list()) {
        return weave_fmt_measure_list(context, node, expected, limit);
    }
    if (kind == node_string()) {
        int64_t length = node_text_len(context->tree, node);
        return length >= 0 && (uint64_t)length + 2 <= limit
            ? (int)length + 2 : -1;
    }
    if (kind == node_int()) {
        char buffer[32];
        int length = snprintf(
            buffer, sizeof(buffer), "%lld", (long long)node_value(context->tree, node));
        return length > 0 && (size_t)length <= limit ? length : -1;
    }
    int64_t length = node_text_len(context->tree, node);
    return length >= 0 && (uint64_t)length <= limit ? (int)length : -1;
}

