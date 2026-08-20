static void weave_fmt_add_binding(
    weave_fmt_context *context,
    int64_t name,
    weave_fmt_type type,
    weave_fmt_binding_kind kind) {
    if (name == -1 || node_kind(context->tree, name) != node_ident()) return;
    int64_t start_raw = node_text_start(context->tree, name);
    int64_t length_raw = node_text_len(context->tree, name);
    if (start_raw < 0 || length_raw <= 0) return;
    if (!weave_fmt_reserve_bindings(context, context->binding_count + 1)) {
        return;
    }
    context->bindings[context->binding_count++] = (weave_fmt_binding){
        .name_start = (size_t)start_raw,
        .name_length = (size_t)length_raw,
        .type = type,
        .kind = kind,
    };
}

static weave_fmt_type weave_fmt_lookup_binding(
    const weave_fmt_context *context,
    int64_t name,
    weave_fmt_binding_kind required_kind) {
    if (name == -1 || node_kind(context->tree, name) != node_ident()) {
        return WEAVE_FMT_UNKNOWN;
    }
    int64_t start_raw = node_text_start(context->tree, name);
    int64_t length_raw = node_text_len(context->tree, name);
    if (start_raw < 0 || length_raw <= 0) return WEAVE_FMT_UNKNOWN;
    size_t start = (size_t)start_raw;
    size_t length = (size_t)length_raw;
    for (size_t reverse = context->binding_count; reverse != 0; --reverse) {
        const weave_fmt_binding *binding = &context->bindings[reverse - 1];
        if ((required_kind == 0 || binding->kind == required_kind) &&
            weave_fmt_name_spans_equal(
                context,
                binding->name_start,
                binding->name_length,
                start,
                length)) {
            return binding->type;
        }
    }
    return WEAVE_FMT_UNKNOWN;
}

static weave_fmt_type weave_fmt_parse_typed_suffix(
    const weave_fmt_context *context,
    int64_t head,
    size_t *base_length) {
    int64_t start_raw = node_text_start(context->tree, head);
    int64_t length_raw = node_text_len(context->tree, head);
    if (start_raw < 0 || length_raw <= 0) return WEAVE_FMT_UNKNOWN;
    size_t start = (size_t)start_raw;
    size_t length = (size_t)length_raw;
    static const struct {
        const char *suffix;
        weave_fmt_type type;
    } suffixes[] = {
        {"_bool", WEAVE_FMT_BOOL},
        {"_i32", WEAVE_FMT_I32},
        {"_i64", WEAVE_FMT_I64},
        {"_f32", WEAVE_FMT_F32},
        {"_f64", WEAVE_FMT_F64},
        {"_ptr", WEAVE_FMT_PTR},
        {"_void", WEAVE_FMT_VOID},
    };
    for (size_t index = 0; index < sizeof(suffixes) / sizeof(suffixes[0]); ++index) {
        size_t suffix_length = strlen(suffixes[index].suffix);
        if (length > suffix_length &&
            memcmp(
                context->source + start + length - suffix_length,
                suffixes[index].suffix,
                suffix_length) == 0) {
            *base_length = length - suffix_length;
            return suffixes[index].type;
        }
    }
    return WEAVE_FMT_UNKNOWN;
}

static const char *weave_fmt_operator_name(
    const weave_fmt_context *context,
    int64_t head,
    weave_fmt_type *operand_type,
    int *comparison_or_boolean) {
    size_t base_length = 0;
    weave_fmt_type type = weave_fmt_parse_typed_suffix(
        context, head, &base_length);
    if (type == WEAVE_FMT_UNKNOWN || type == WEAVE_FMT_VOID) return NULL;
    int64_t start_raw = node_text_start(context->tree, head);
    if (start_raw < 0) return NULL;
    size_t start = (size_t)start_raw;
    const char *canonical = NULL;
    int bool_result = 0;
#define WEAVE_FMT_BASE(text) \
    (base_length == sizeof(text) - 1 && \
     memcmp(context->source + start, text, sizeof(text) - 1) == 0)
    if (WEAVE_FMT_BASE("add")) canonical = "+";
    else if (WEAVE_FMT_BASE("sub")) canonical = "-";
    else if (WEAVE_FMT_BASE("mul")) canonical = "*";
    else if (WEAVE_FMT_BASE("div")) canonical = "/";
    else if (WEAVE_FMT_BASE("mod")) canonical = "mod";
    else if (WEAVE_FMT_BASE("and")) {
        canonical = type == WEAVE_FMT_BOOL ? "and" : "bit-and";
        bool_result = type == WEAVE_FMT_BOOL;
    } else if (WEAVE_FMT_BASE("or")) {
        canonical = type == WEAVE_FMT_BOOL ? "or" : "bit-or";
        bool_result = type == WEAVE_FMT_BOOL;
    } else if (WEAVE_FMT_BASE("xor")) canonical = "bit-xor";
    else if (WEAVE_FMT_BASE("shl")) canonical = "shift-left";
    else if (WEAVE_FMT_BASE("shr")) canonical = "shift-right";
    else if (WEAVE_FMT_BASE("eq")) { canonical = "="; bool_result = 1; }
    else if (WEAVE_FMT_BASE("ne")) { canonical = "!="; bool_result = 1; }
    else if (WEAVE_FMT_BASE("lt")) { canonical = "<"; bool_result = 1; }
    else if (WEAVE_FMT_BASE("le")) { canonical = "<="; bool_result = 1; }
    else if (WEAVE_FMT_BASE("gt")) { canonical = ">"; bool_result = 1; }
    else if (WEAVE_FMT_BASE("ge")) { canonical = ">="; bool_result = 1; }
    else if (WEAVE_FMT_BASE("not") && type == WEAVE_FMT_BOOL) {
        canonical = "not";
        bool_result = 1;
    }
#undef WEAVE_FMT_BASE
    if (canonical == NULL) return NULL;
    *operand_type = type;
    *comparison_or_boolean = bool_result;
    return canonical;
}

static const char *weave_fmt_compact_operator_from_name(
    const weave_fmt_context *context,
    int64_t name) {
    if (name == -1) return NULL;
    if (weave_fmt_node_text_equals(context, name, "add") ||
        weave_fmt_node_text_equals(context, name, "+")) return "+";
    if (weave_fmt_node_text_equals(context, name, "sub") ||
        weave_fmt_node_text_equals(context, name, "-")) return "-";
    if (weave_fmt_node_text_equals(context, name, "mul") ||
        weave_fmt_node_text_equals(context, name, "*")) return "*";
    if (weave_fmt_node_text_equals(context, name, "div") ||
        weave_fmt_node_text_equals(context, name, "/")) return "/";
    if (weave_fmt_node_text_equals(context, name, "mod")) return "mod";
    if (weave_fmt_node_text_equals(context, name, "equal") ||
        weave_fmt_node_text_equals(context, name, "=")) return "=";
    if (weave_fmt_node_text_equals(context, name, "not-equal") ||
        weave_fmt_node_text_equals(context, name, "!=")) return "!=";
    if (weave_fmt_node_text_equals(context, name, "less-than") ||
        weave_fmt_node_text_equals(context, name, "<")) return "<";
    if (weave_fmt_node_text_equals(context, name, "less-or-equal") ||
        weave_fmt_node_text_equals(context, name, "<=")) return "<=";
    if (weave_fmt_node_text_equals(context, name, "greater-than") ||
        weave_fmt_node_text_equals(context, name, ">")) return ">";
    if (weave_fmt_node_text_equals(context, name, "greater-or-equal") ||
        weave_fmt_node_text_equals(context, name, ">=")) return ">=";
    if (weave_fmt_node_text_equals(context, name, "and")) return "and";
    if (weave_fmt_node_text_equals(context, name, "or")) return "or";
    if (weave_fmt_node_text_equals(context, name, "not")) return "not";
    if (weave_fmt_node_text_equals(context, name, "bit-and")) return "bit-and";
    if (weave_fmt_node_text_equals(context, name, "bit-or")) return "bit-or";
    if (weave_fmt_node_text_equals(context, name, "bit-xor")) return "bit-xor";
    if (weave_fmt_node_text_equals(context, name, "shift-left")) return "shift-left";
    if (weave_fmt_node_text_equals(context, name, "shift-right")) {
        return "shift-right";
    }
    return NULL;
}

static int weave_fmt_is_compact_operator_head(
    const weave_fmt_context *context,
    int64_t head) {
    static const char *const heads[] = {
        "+", "-", "*", "/", "mod",
        "=", "!=", "<", "<=", ">", ">=",
        "and", "or", "not",
        "bit-and", "bit-or", "bit-xor", "shift-left", "shift-right",
    };
    for (size_t index = 0; index < sizeof(heads) / sizeof(heads[0]); ++index) {
        if (weave_fmt_node_text_equals(context, head, heads[index])) return 1;
    }
    return 0;
}

static int weave_fmt_compact_operator_is_bool_result(const char *head) {
    return strcmp(head, "and") == 0 ||
        strcmp(head, "or") == 0 ||
        strcmp(head, "not") == 0 ||
        strcmp(head, "=") == 0 ||
        strcmp(head, "!=") == 0 ||
        strcmp(head, "<") == 0 ||
        strcmp(head, "<=") == 0 ||
        strcmp(head, ">") == 0 ||
        strcmp(head, ">=") == 0;
}

static int weave_fmt_list_headed(
    const weave_fmt_context *context,
    int64_t node,
    const char *head) {
    if (node == -1 || node_kind(context->tree, node) != node_list()) return 0;
    return weave_fmt_node_text_equals(
        context, node_first_child(context->tree, node), head);
}

static int64_t weave_fmt_named_body(
    const weave_fmt_context *context,
    int64_t node,
    const char *head) {
    if (!weave_fmt_list_headed(context, node, head)) return -1;
    return weave_fmt_nth_child(context, node, 1);
}

static int weave_fmt_do_is_empty(
    const weave_fmt_context *context,
    int64_t node) {
    return weave_fmt_list_headed(context, node, "do") &&
        weave_fmt_child_count(context, node) <= 1;
}

static int64_t weave_fmt_unwrap_do_single(
    const weave_fmt_context *context,
    int64_t node) {
    if (!weave_fmt_list_headed(context, node, "do")) return node;
    if (weave_fmt_child_count(context, node) == 2) {
        return weave_fmt_nth_child(context, node, 1);
    }
    return node;
}

static int weave_fmt_compact_operator_is_boolean_logic(const char *head) {
    return strcmp(head, "and") == 0 ||
        strcmp(head, "or") == 0 ||
        strcmp(head, "not") == 0;
}

static int32_t weave_fmt_semantic_type_ref(weave_fmt_type type) {
    switch (type) {
        case WEAVE_FMT_I32: return surface_type_i32();
        case WEAVE_FMT_I64: return surface_type_i64();
        case WEAVE_FMT_F32: return surface_type_f32();
        case WEAVE_FMT_F64: return surface_type_f64();
        default: return 0;
    }
}

static int weave_fmt_cast_pair_admitted(
    weave_fmt_type source,
    weave_fmt_type target) {
    int32_t source_type = weave_fmt_semantic_type_ref(source);
    int32_t target_type = weave_fmt_semantic_type_ref(target);
    if (source_type == 0 || target_type == 0) return 0;
    return sop_cast_pair_supported(source_type, target_type) != 0;
}

static int weave_fmt_parse_cast_head(
    const weave_fmt_context *context,
    int64_t head,
    weave_fmt_type *source_type,
    weave_fmt_type *target_type) {
    int64_t start_raw = node_text_start(context->tree, head);
    int64_t length_raw = node_text_len(context->tree, head);
    if (start_raw < 0 || length_raw <= 0) return 0;
    size_t start = (size_t)start_raw;
    size_t length = (size_t)length_raw;
    if (length < 10 || memcmp(context->source + start, "cast_", 5) != 0) {
        return 0;
    }
    const unsigned char *body = context->source + start + 5;
    size_t body_length = length - 5;
    const unsigned char *separator = NULL;
    for (size_t index = 0; index + 4 <= body_length; ++index) {
        if (memcmp(body + index, "_to_", 4) == 0) {
            separator = body + index;
            break;
        }
    }
    if (separator == NULL) return 0;
    size_t source_length = (size_t)(separator - body);
    size_t target_length = body_length - source_length - 4;
    weave_fmt_type source = WEAVE_FMT_UNKNOWN;
    weave_fmt_type target = WEAVE_FMT_UNKNOWN;
#define WEAVE_FMT_TYPE_TOKEN(pointer, token_length, literal, value) \
    if ((token_length) == sizeof(literal) - 1 && \
        memcmp((pointer), literal, sizeof(literal) - 1) == 0) value
    WEAVE_FMT_TYPE_TOKEN(body, source_length, "i32", source = WEAVE_FMT_I32;)
    else WEAVE_FMT_TYPE_TOKEN(body, source_length, "i64", source = WEAVE_FMT_I64;)
    else WEAVE_FMT_TYPE_TOKEN(body, source_length, "f32", source = WEAVE_FMT_F32;)
    else WEAVE_FMT_TYPE_TOKEN(body, source_length, "f64", source = WEAVE_FMT_F64;)
    const unsigned char *target_pointer = separator + 4;
    WEAVE_FMT_TYPE_TOKEN(target_pointer, target_length, "i32", target = WEAVE_FMT_I32;)
    else WEAVE_FMT_TYPE_TOKEN(target_pointer, target_length, "i64", target = WEAVE_FMT_I64;)
    else WEAVE_FMT_TYPE_TOKEN(target_pointer, target_length, "f32", target = WEAVE_FMT_F32;)
    else WEAVE_FMT_TYPE_TOKEN(target_pointer, target_length, "f64", target = WEAVE_FMT_F64;)
#undef WEAVE_FMT_TYPE_TOKEN
    if (!weave_fmt_cast_pair_admitted(source, target)) return 0;
    *source_type = source;
    *target_type = target;
    return 1;
}
