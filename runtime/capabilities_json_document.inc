static int weave_capabilities_serialize(
    weave_json_writer *writer, const void *opaque) {
    (void)opaque;
    static const char *const optimization_levels[] = {"O0", "O1", "O2", "O3", "Os", "Oz"};
    static const char *const cpu_selection[] = {"native", "cpu", "tune-cpu"};
    if (!weave_json_object_begin(writer) ||
        !weave_json_key(writer, "format") || !weave_json_string(writer, "weavec-capabilities-v1") ||
        !weave_json_key(writer, "schema_id") || !weave_json_string(writer, "urn:weavec:schema:capabilities:v1") ||
        !weave_json_key(writer, "schema_version") || !weave_json_int64(writer, 1) ||
        !weave_json_key(writer, "compiler") || !weave_json_object_begin(writer) ||
        !weave_json_key(writer, "name") || !weave_json_string(writer, "weavec") ||
        !weave_json_key(writer, "version") || !weave_json_string(writer, weave_compiler_version) ||
        !weave_json_key(writer, "public_variant") || !weave_json_string(writer, "final") ||
        !weave_json_object_end(writer) ||
        !weave_json_key(writer, "language") || !weave_json_object_begin(writer) ||
        !weave_json_key(writer, "name") || !weave_json_string(writer, "Weave") ||
        !weave_json_key(writer, "surface_version") || !weave_json_string(writer, "weave-surface-v1") ||
        !weave_json_key(writer, "grammar_id") || !weave_json_string(writer, "weave-surface-grammar-v1") ||
        !weave_json_key(writer, "syntax") || !weave_json_string(writer, "s-expression") ||
        !weave_json_key(writer, "case_sensitive") || !weave_capabilities_write_bool(writer, 1) ||
        !weave_json_key(writer, "wir_core_version") || !weave_json_int64(writer, 2) ||
        !weave_json_object_end(writer) ||
        !weave_json_key(writer, "protocols") || !weave_capabilities_write_protocols(writer) ||
        !weave_json_key(writer, "commands") || !weave_capabilities_write_commands(writer) ||
        !weave_json_key(writer, "targets") || !weave_json_object_begin(writer) ||
        !weave_json_key(writer, "default") || !weave_json_string(writer, WEAVEC_DEFAULT_TARGET) ||
        !weave_json_key(writer, "installed") || !weave_json_array_begin(writer) ||
        !weave_json_object_begin(writer) ||
        !weave_json_key(writer, "triple") || !weave_json_string(writer, WEAVEC_DEFAULT_TARGET) ||
        !weave_json_key(writer, "native") || !weave_capabilities_write_bool(writer, 1) ||
        !weave_json_key(writer, "cross_compilation") || !weave_capabilities_write_bool(writer, 0) ||
        !weave_json_key(writer, "runtime") || !weave_json_string(writer, "static-private-target-archive") ||
        !weave_json_key(writer, "optimization_levels") ||
        !weave_capabilities_write_string_slice(
            writer, optimization_levels, 0, WEAVE_CAP_ARRAY_LEN(optimization_levels)) ||
        !weave_json_key(writer, "cpu_selection") ||
        !weave_capabilities_write_string_slice(
            writer, cpu_selection, 0, WEAVE_CAP_ARRAY_LEN(cpu_selection)) ||
        !weave_json_object_end(writer) || !weave_json_array_end(writer) ||
        !weave_json_object_end(writer) ||
        !weave_json_key(writer, "features") || !weave_capabilities_write_features(writer) ||
        !weave_json_key(writer, "surface") || !weave_json_object_begin(writer) ||
        !weave_json_key(writer, "grammar_document") || !weave_json_string(writer, "docs/language-reference.md") ||
        !weave_json_key(writer, "canonical_document") || !weave_json_string(writer, "docs/canonical-surface.md") ||
        !weave_json_key(writer, "child_count_excludes_head") || !weave_capabilities_write_bool(writer, 1) ||
        !weave_json_key(writer, "types") ||
        !weave_capabilities_write_string_slice(
            writer, weave_cap_primitive_types, 0, WEAVE_CAP_ARRAY_LEN(weave_cap_primitive_types)) ||
        !weave_json_key(writer, "operators") || !weave_capabilities_write_operators(writer) ||
        !weave_json_key(writer, "casts") || !weave_capabilities_write_casts(writer) ||
        !weave_json_key(writer, "contextual_literals") || !weave_capabilities_write_literals(writer) ||
        !weave_json_key(writer, "forms") || !weave_capabilities_write_forms(writer) ||
        !weave_json_key(writer, "compatibility_families") || !weave_capabilities_write_families(writer) ||
        !weave_json_object_end(writer) || !weave_json_object_end(writer)) return 1;
    return 0;
}

int weave_rt_print_capabilities(void) {
    weave_json_writer writer;
    weave_json_writer_init(&writer, stdout);
    if (weave_capabilities_serialize(&writer, NULL) != 0 ||
        !weave_json_writer_finish(&writer) || fflush(stdout) != 0) return 1;
    return 0;
}
