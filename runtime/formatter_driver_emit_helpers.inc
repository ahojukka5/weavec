static int weave_fmt_format_node(
    weave_fmt_context *context,
    int64_t node,
    size_t indentation,
    weave_fmt_type expected,
    int force_inline);

static int weave_fmt_emit_casted_integer(
    weave_fmt_context *context,
    int64_t value,
    weave_fmt_type target,
    size_t indentation,
    int force_inline) {
    (void)indentation;
    (void)force_inline;
    const char *type_name = weave_fmt_type_name(target);
    return type_name != NULL &&
        weave_fmt_write_cstr(context, "(cast ") &&
        weave_fmt_write_cstr(context, type_name) &&
        weave_fmt_write_char(context, ' ') &&
        weave_fmt_write_atom(context, value) &&
        weave_fmt_write_char(context, ')');
}

static int weave_fmt_prepare_function_scope(
    weave_fmt_context *context,
    int64_t list,
    size_t *saved_binding_count,
    weave_fmt_type *saved_return_type) {
    *saved_binding_count = context->binding_count;
    *saved_return_type = context->current_return_type;
    context->binding_count = 0;
    int64_t params = weave_fmt_nth_child(context, list, 2);
    int64_t returns = weave_fmt_nth_child(context, list, 3);
    context->current_return_type = weave_fmt_type_from_text(
        context, weave_fmt_nth_child(context, returns, 1));
    int64_t parameter = weave_fmt_nth_child(context, params, 1);
    while (parameter != -1) {
        int64_t name = weave_fmt_nth_child(context, parameter, 0);
        int64_t type = weave_fmt_nth_child(context, parameter, 1);
        weave_fmt_add_binding(
            context,
            name,
            weave_fmt_type_from_text(context, type),
            WEAVE_FMT_BINDING_PARAM);
        parameter = node_next_sibling(context->tree, parameter);
    }
    return 1;
}

static void weave_fmt_restore_function_scope(
    weave_fmt_context *context,
    size_t saved_binding_count,
    weave_fmt_type saved_return_type) {
    context->binding_count = saved_binding_count;
    context->current_return_type = saved_return_type;
}

static int weave_fmt_format_operator_child(
    weave_fmt_context *context,
    int64_t list,
    const weave_fmt_plan *plan,
    int64_t child,
    size_t actual_index,
    size_t indentation,
    int force_inline) {
    size_t operand_index = plan->virtual_second != NULL
        ? actual_index : (actual_index == 0 ? SIZE_MAX : actual_index - 1);
    if (operand_index == SIZE_MAX) {
        return weave_fmt_format_node(
            context, child, indentation, WEAVE_FMT_UNKNOWN, force_inline);
    }
    if (plan->encoded_type == WEAVE_FMT_BOOL ||
        plan->encoded_type == WEAVE_FMT_PTR) {
        return weave_fmt_format_node(
            context,
            child,
            indentation,
            plan->encoded_type,
            force_inline);
    }

    int64_t left = plan->virtual_second != NULL
        ? weave_fmt_nth_child(context, list, 1)
        : weave_fmt_nth_child(context, list, 2);
    int64_t right = plan->virtual_second != NULL
        ? weave_fmt_nth_child(context, list, 2)
        : weave_fmt_nth_child(context, list, 3);
    weave_fmt_type left_seed = weave_fmt_seed_type(context, left);
    weave_fmt_type right_seed = weave_fmt_seed_type(context, right);
    size_t anchor = SIZE_MAX;
    if (left_seed != WEAVE_FMT_UNKNOWN) anchor = 0;
    else if (right_seed != WEAVE_FMT_UNKNOWN) anchor = 1;
    else if (plan->encoded_type != WEAVE_FMT_I32 &&
             plan->encoded_type != WEAVE_FMT_BOOL) anchor = 0;

    if (operand_index == anchor) {
        if (node_kind(context->tree, child) == node_int() &&
            plan->encoded_type != WEAVE_FMT_I32 &&
            plan->encoded_type != WEAVE_FMT_BOOL &&
            weave_fmt_cast_pair_admitted(WEAVE_FMT_I32, plan->encoded_type)) {
            return weave_fmt_emit_casted_integer(
                context,
                child,
                plan->encoded_type,
                indentation,
                force_inline);
        }
        return weave_fmt_format_node(
            context, child, indentation, WEAVE_FMT_UNKNOWN, force_inline);
    }
    return weave_fmt_format_node(
        context,
        child,
        indentation,
        plan->encoded_type,
        force_inline);
}

