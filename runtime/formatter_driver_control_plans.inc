static int64_t weave_fmt_control_first_stmt(
    weave_fmt_context *context,
    int64_t body) {
    if (body == -1) return -1;
    if (weave_fmt_list_headed(context, body, "do")) {
        return weave_fmt_nth_child(context, body, 1);
    }
    return body;
}

static int weave_fmt_plan_compact_control(
    weave_fmt_context *context,
    int64_t list,
    int64_t head,
    weave_fmt_plan *plan) {
    if (weave_fmt_node_text_equals(context, head, "when")) {
        memset(plan, 0, sizeof(*plan));
        plan->kind = WEAVE_FMT_PLAN_CONTROL;
        plan->virtual_head = "when";
        plan->control_cond = weave_fmt_nth_child(context, list, 1);
        plan->control_then = weave_fmt_nth_child(context, list, 2);
        plan->control_else = -1;
        plan->control_variadic = 1;
        return 1;
    }
    if (weave_fmt_node_text_equals(context, head, "while") &&
        !weave_fmt_list_headed(
            context, weave_fmt_nth_child(context, list, 1), "condition")) {
        memset(plan, 0, sizeof(*plan));
        plan->kind = WEAVE_FMT_PLAN_CONTROL;
        plan->virtual_head = "while";
        plan->control_cond = weave_fmt_nth_child(context, list, 1);
        plan->control_then = weave_fmt_nth_child(context, list, 2);
        plan->control_else = -1;
        plan->control_variadic = 1;
        return 1;
    }
    if (weave_fmt_node_text_equals(context, head, "if") &&
        !weave_fmt_list_headed(
            context, weave_fmt_nth_child(context, list, 1), "condition") &&
        weave_fmt_child_count(context, list) == 4) {
        memset(plan, 0, sizeof(*plan));
        plan->kind = WEAVE_FMT_PLAN_CONTROL;
        plan->virtual_head = "if";
        plan->control_cond = weave_fmt_nth_child(context, list, 1);
        plan->control_then = weave_fmt_nth_child(context, list, 2);
        plan->control_else = weave_fmt_nth_child(context, list, 3);
        plan->control_variadic = 0;
        return 1;
    }
    return 0;
}

static int weave_fmt_plan_list(
    weave_fmt_context *context,
    int64_t list,
    weave_fmt_plan *plan) {
    int64_t head = node_first_child(context->tree, list);
    if (head == -1 || node_kind(context->tree, head) != node_ident()) {
        return 0;
    }
    if (weave_fmt_plan_compact_control(context, list, head, plan)) {
        return 1;
    }
    if (!weave_fmt_plan_list_legacy(context, list, plan)) {
        return 0;
    }
    if (plan->kind == WEAVE_FMT_PLAN_CONTROL && plan->control_variadic) {
        plan->control_then = weave_fmt_control_first_stmt(
            context, plan->control_then);
    }
    return 1;
}
