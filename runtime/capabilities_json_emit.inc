static int weave_capabilities_write_string_slice(
    weave_json_writer *writer, const char *const *values,
    size_t start, size_t count) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t i = 0; i < count; ++i) {
        if (!weave_json_string(writer, values[start + i])) return 0;
    }
    return weave_json_array_end(writer);
}

static int weave_capabilities_write_protocols(weave_json_writer *writer) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t i = 0; i < WEAVE_CAP_ARRAY_LEN(weave_cap_protocols); ++i) {
        const weave_capability_protocol *item = &weave_cap_protocols[i];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") || !weave_json_string(writer, item->id) ||
            !weave_json_key(writer, "version") || !weave_json_int64(writer, item->version) ||
            !weave_json_key(writer, "kind") || !weave_json_string(writer, item->kind) ||
            !weave_json_object_end(writer)) return 0;
    }
    return weave_json_array_end(writer);
}

static int weave_capabilities_write_commands(weave_json_writer *writer) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t i = 0; i < WEAVE_CAP_ARRAY_LEN(weave_cap_commands); ++i) {
        const weave_capability_command *item = &weave_cap_commands[i];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "name") || !weave_json_string(writer, item->name) ||
            !weave_json_key(writer, "spelling") || !weave_json_string(writer, item->spelling) ||
            !weave_json_key(writer, "audience") || !weave_json_string(writer, item->audience) ||
            !weave_json_key(writer, "status") || !weave_json_string(writer, item->status) ||
            !weave_json_key(writer, "protocols") ||
            !weave_capabilities_write_string_slice(
                writer, weave_cap_command_protocols,
                item->protocol_start, item->protocol_count) ||
            !weave_json_object_end(writer)) return 0;
    }
    return weave_json_array_end(writer);
}

static int weave_capabilities_write_features(weave_json_writer *writer) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t i = 0; i < WEAVE_CAP_ARRAY_LEN(weave_cap_features); ++i) {
        const weave_capability_feature *item = &weave_cap_features[i];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") || !weave_json_string(writer, item->id) ||
            !weave_json_key(writer, "status") || !weave_json_string(writer, item->status) ||
            !weave_json_key(writer, "issue")) return 0;
        if (item->issue == 0 ? !weave_json_null(writer)
                             : !weave_json_int64(writer, item->issue)) return 0;
        if (!weave_json_object_end(writer)) return 0;
    }
    return weave_json_array_end(writer);
}

static int weave_capabilities_write_operators(weave_json_writer *writer) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t i = 0; i < WEAVE_CAP_ARRAY_LEN(weave_cap_operator_groups); ++i) {
        const weave_capability_operator_group *item = &weave_cap_operator_groups[i];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") || !weave_json_string(writer, item->id) ||
            !weave_json_key(writer, "names") ||
            !weave_capabilities_write_string_slice(
                writer, weave_cap_operator_names, item->name_start, item->name_count) ||
            !weave_json_key(writer, "types") ||
            !weave_capabilities_write_string_slice(
                writer, weave_cap_operator_types, item->type_start, item->type_count) ||
            !weave_json_key(writer, "arity") || !weave_json_int64(writer, item->arity) ||
            !weave_json_key(writer, "result") || !weave_json_string(writer, item->result_type) ||
            !weave_json_object_end(writer)) return 0;
    }
    return weave_json_array_end(writer);
}

static int weave_capabilities_write_casts(weave_json_writer *writer) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t i = 0; i < WEAVE_CAP_ARRAY_LEN(weave_cap_cast_pairs); ++i) {
        const weave_capability_cast_pair *item = &weave_cap_cast_pairs[i];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "source") || !weave_json_string(writer, item->source) ||
            !weave_json_key(writer, "target") || !weave_json_string(writer, item->target) ||
            !weave_json_object_end(writer)) return 0;
    }
    return weave_json_array_end(writer);
}

static int weave_capabilities_write_literals(weave_json_writer *writer) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t i = 0; i < WEAVE_CAP_ARRAY_LEN(weave_cap_literal_kinds); ++i) {
        const weave_capability_literal_kind *item = &weave_cap_literal_kinds[i];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "kind") || !weave_json_string(writer, item->kind) ||
            !weave_json_key(writer, "types") ||
            !weave_capabilities_write_string_slice(
                writer, weave_cap_literal_types, item->type_start, item->type_count) ||
            !weave_json_key(writer, "contexts") ||
            !weave_capabilities_write_string_slice(
                writer, weave_cap_literal_contexts,
                item->context_start, item->context_count) ||
            !weave_json_object_end(writer)) return 0;
    }
    return weave_json_array_end(writer);
}

static int weave_capabilities_write_roles(
    weave_json_writer *writer, size_t start, size_t count) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t i = 0; i < count; ++i) {
        const weave_capability_role *item = &weave_cap_roles[start + i];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "name") || !weave_json_string(writer, item->name) ||
            !weave_json_key(writer, "position") || !weave_json_int64(writer, item->position) ||
            !weave_json_key(writer, "cardinality") || !weave_json_string(writer, item->cardinality) ||
            !weave_json_key(writer, "kind") || !weave_json_string(writer, item->kind) ||
            !weave_json_object_end(writer)) return 0;
    }
    return weave_json_array_end(writer);
}

static int weave_capabilities_write_forms(weave_json_writer *writer) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t i = 0; i < WEAVE_CAP_ARRAY_LEN(weave_cap_forms); ++i) {
        const weave_capability_form *item = &weave_cap_forms[i];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "head") || !weave_json_string(writer, item->head) ||
            !weave_json_key(writer, "status") || !weave_json_string(writer, item->status) ||
            !weave_json_key(writer, "arity") || !weave_json_object_begin(writer) ||
            !weave_json_key(writer, "min_children") || !weave_json_int64(writer, item->min_children) ||
            !weave_json_key(writer, "max_children")) return 0;
        if (item->max_children < 0 ? !weave_json_null(writer)
                                   : !weave_json_int64(writer, item->max_children)) return 0;
        if (!weave_json_object_end(writer) ||
            !weave_json_key(writer, "type_information") || !weave_json_string(writer, item->type_information) ||
            !weave_json_key(writer, "feature") || !weave_json_nullable_string(writer, item->feature) ||
            !weave_json_key(writer, "canonical_replacement") || !weave_json_nullable_string(writer, item->canonical_replacement) ||
            !weave_json_key(writer, "roles") ||
            !weave_capabilities_write_roles(writer, item->role_start, item->role_count) ||
            !weave_json_object_end(writer)) return 0;
    }
    return weave_json_array_end(writer);
}

static int weave_capabilities_write_families(weave_json_writer *writer) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t i = 0; i < WEAVE_CAP_ARRAY_LEN(weave_cap_families); ++i) {
        const weave_capability_family *item = &weave_cap_families[i];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") || !weave_json_string(writer, item->id) ||
            !weave_json_key(writer, "status") || !weave_json_string(writer, item->status) ||
            !weave_json_key(writer, "head_pattern") || !weave_json_string(writer, item->head_pattern) ||
            !weave_json_key(writer, "canonical_replacement") || !weave_json_nullable_string(writer, item->canonical_replacement) ||
            !weave_json_key(writer, "type_information") || !weave_json_string(writer, item->type_information) ||
            !weave_json_key(writer, "grammar_reference") || !weave_json_string(writer, item->grammar_reference) ||
            !weave_json_key(writer, "members") ||
            !weave_capabilities_write_string_slice(
                writer, weave_cap_family_members,
                item->member_start, item->member_count) ||
            !weave_json_object_end(writer)) return 0;
    }
    return weave_json_array_end(writer);
}
