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
    if (WEAVE_FMT_BASE("add")) canonical = "add";
    else if (WEAVE_FMT_BASE("sub")) canonical = "subtract";
    else if (WEAVE_FMT_BASE("mul")) canonical = "multiply";
    else if (WEAVE_FMT_BASE("div")) canonical = "divide";
    else if (WEAVE_FMT_BASE("mod")) canonical = "remainder";
    else if (WEAVE_FMT_BASE("and")) {
        canonical = type == WEAVE_FMT_BOOL ? "and" : "bit-and";
        bool_result = type == WEAVE_FMT_BOOL;
    } else if (WEAVE_FMT_BASE("or")) {
        canonical = type == WEAVE_FMT_BOOL ? "or" : "bit-or";
        bool_result = type == WEAVE_FMT_BOOL;
    } else if (WEAVE_FMT_BASE("xor")) canonical = "bit-xor";
    else if (WEAVE_FMT_BASE("shl")) canonical = "shift-left";
    else if (WEAVE_FMT_BASE("shr")) canonical = "shift-right";
    else if (WEAVE_FMT_BASE("eq")) { canonical = "equal"; bool_result = 1; }
    else if (WEAVE_FMT_BASE("ne")) { canonical = "not-equal"; bool_result = 1; }
    else if (WEAVE_FMT_BASE("lt")) { canonical = "less-than"; bool_result = 1; }
    else if (WEAVE_FMT_BASE("le")) { canonical = "less-or-equal"; bool_result = 1; }
    else if (WEAVE_FMT_BASE("gt")) { canonical = "greater-than"; bool_result = 1; }
    else if (WEAVE_FMT_BASE("ge")) { canonical = "greater-or-equal"; bool_result = 1; }
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

static int weave_fmt_cast_pair_admitted(
    weave_fmt_type source,
    weave_fmt_type target) {
    const char *source_name = weave_fmt_type_name(source);
    const char *target_name = weave_fmt_type_name(target);
    if (source_name == NULL || target_name == NULL) return 0;
    for (size_t index = 0;
         index < sizeof(weave_cap_cast_pairs) / sizeof(weave_cap_cast_pairs[0]);
         ++index) {
        if (strcmp(weave_cap_cast_pairs[index].source, source_name) == 0 &&
            strcmp(weave_cap_cast_pairs[index].target, target_name) == 0) {
            return 1;
        }
    }
    return 0;
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

