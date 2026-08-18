static int weave_si_compute_interface_hashes(weave_si_model *model) {
    for (size_t module_index = 0;
         module_index < model->module_count;
         ++module_index) {
        weave_si_module *module = &model->modules[module_index];
        weave_si_sort_exported_symbols(model, module);
        weave_si_buffer input;
        weave_si_buffer_init(&input);
        weave_si_buffer_cstr(&input, "{\"module\":");
        weave_si_buffer_json_string(
            &input, module->name, strlen(module->name));
        weave_si_buffer_cstr(&input, ",\"exports\":[");
        for (size_t export_index = 0;
             export_index < module->exported_count;
             ++export_index) {
            if (export_index != 0) weave_si_buffer_char(&input, ',');
            const weave_si_symbol *symbol =
                &model->symbols[module->exported_symbols[export_index]];
            weave_si_buffer_cstr(&input, "{\"kind\":");
            weave_si_buffer_json_string(
                &input, symbol->kind, strlen(symbol->kind));
            weave_si_buffer_cstr(&input, ",\"name\":");
            weave_si_buffer_json_string(
                &input, symbol->name, strlen(symbol->name));
            weave_si_buffer_cstr(&input, ",\"signature\":");
            weave_si_buffer_json_string(
                &input, symbol->signature, strlen(symbol->signature));
            weave_si_buffer_char(&input, '}');
        }
        weave_si_buffer_cstr(&input, "]}");
        if (input.failed) {
            free(input.data);
            return 0;
        }
        weave_si_sha256_bytes(
            input.data, input.length, module->interface_sha256);
        free(input.data);
    }
    return 1;
}

static void weave_si_compute_source_set_hash(weave_si_model *model) {
    weave_si_sha256 context;
    unsigned char digest[32];
    static const char prefix[] = "weavec-source-set-v1\0";
    weave_si_sha256_init(&context);
    weave_si_sha256_update(&context, prefix, sizeof(prefix) - 1);
    for (size_t index = 0; index < model->source_count; ++index) {
        weave_si_source *source = &model->sources[index];
        char length[32];
        int written = snprintf(length, sizeof(length), "%zu", strlen(source->path));
        if (written > 0) {
            weave_si_sha256_update(&context, length, (size_t)written);
            weave_si_sha256_update(&context, ":", 1);
            weave_si_sha256_update(&context, source->path, strlen(source->path));
            weave_si_sha256_update(&context, "\0", 1);
        }
        written = snprintf(length, sizeof(length), "%zu", source->length);
        if (written > 0) {
            weave_si_sha256_update(&context, length, (size_t)written);
            weave_si_sha256_update(&context, ":", 1);
            weave_si_sha256_update(&context, source->bytes, source->length);
            weave_si_sha256_update(&context, "\0", 1);
        }
    }
    weave_si_sha256_finish(&context, digest);
    weave_si_hex(digest, model->source_set_sha256);
    weave_si_sha256_bytes("{}", 2, model->options_sha256);
}

static int weave_si_json_bool(weave_json_writer *writer, int value) {
    return weave_json_before_value(writer) &&
        weave_json_write_cstr(writer, value ? "true" : "false");
}

static int weave_si_json_id(
    weave_json_writer *writer,
    const char *prefix,
    size_t index) {
    char value[64];
    int length = snprintf(value, sizeof(value), "%s:%zu", prefix, index);
    return length > 0 && (size_t)length < sizeof(value) &&
        weave_json_string(writer, value);
}

static int weave_si_json_optional_id(
    weave_json_writer *writer,
    const char *prefix,
    size_t index) {
    return index == WEAVE_SI_NONE
        ? weave_json_null(writer)
        : weave_si_json_id(writer, prefix, index);
}

static int weave_si_write_span(
    weave_json_writer *writer,
    size_t source_index,
    size_t start,
    size_t end) {
    return weave_json_object_begin(writer) &&
        weave_json_key(writer, "source_id") &&
        weave_si_json_id(writer, "source", source_index) &&
        weave_json_key(writer, "start") &&
        weave_json_uint64(writer, (uint64_t)start) &&
        weave_json_key(writer, "end") &&
        weave_json_uint64(writer, (uint64_t)end) &&
        weave_json_object_end(writer);
}

static int weave_si_write_sources(
    weave_json_writer *writer,
    const weave_si_model *model) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t index = 0; index < model->source_count; ++index) {
        const weave_si_source *source = &model->sources[index];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") ||
            !weave_si_json_id(writer, "source", index) ||
            !weave_json_key(writer, "index") ||
            !weave_json_uint64(writer, (uint64_t)index) ||
            !weave_json_key(writer, "path") ||
            !weave_json_string(writer, source->path) ||
            !weave_json_key(writer, "sha256") ||
            !weave_json_string(writer, source->sha256) ||
            !weave_json_key(writer, "byte_length") ||
            !weave_json_uint64(writer, (uint64_t)source->length) ||
            !weave_json_object_end(writer)) {
            return 0;
        }
    }
    return weave_json_array_end(writer);
}

static int weave_si_write_modules(
    weave_json_writer *writer,
    const weave_si_model *model) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t index = 0; index < model->module_count; ++index) {
        const weave_si_module *module = &model->modules[index];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") ||
            !weave_si_json_id(writer, "module", index) ||
            !weave_json_key(writer, "name") ||
            !weave_json_string(writer, module->name) ||
            !weave_json_key(writer, "source_id") ||
            !weave_si_json_id(writer, "source", module->source_index) ||
            !weave_json_key(writer, "definition") ||
            !weave_si_write_span(
                writer, module->source_index, module->start, module->end) ||
            !weave_json_key(writer, "interface") ||
            !weave_json_object_begin(writer) ||
            !weave_json_key(writer, "hash_algorithm") ||
            !weave_json_string(writer, "sha256-weave-interface-v1") ||
            !weave_json_key(writer, "sha256") ||
            !weave_json_string(writer, module->interface_sha256) ||
            !weave_json_key(writer, "exports") ||
            !weave_json_array_begin(writer)) {
            return 0;
        }
        for (size_t export_index = 0;
             export_index < module->exported_count;
             ++export_index) {
            if (!weave_si_json_id(
                    writer,
                    "symbol",
                    module->exported_symbols[export_index])) {
                return 0;
            }
        }
        if (!weave_json_array_end(writer) ||
            !weave_json_object_end(writer) ||
            !weave_json_object_end(writer)) {
            return 0;
        }
    }
    return weave_json_array_end(writer);
}

static int weave_si_write_symbols(
    weave_json_writer *writer,
    const weave_si_model *model) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t index = 0; index < model->symbol_count; ++index) {
        const weave_si_symbol *symbol = &model->symbols[index];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") ||
            !weave_si_json_id(writer, "symbol", index) ||
            !weave_json_key(writer, "module_id") ||
            !weave_si_json_id(writer, "module", symbol->module_index) ||
            !weave_json_key(writer, "kind") ||
            !weave_json_string(writer, symbol->kind) ||
            !weave_json_key(writer, "name") ||
            !weave_json_string(writer, symbol->name) ||
            !weave_json_key(writer, "visibility") ||
            !weave_json_string(
                writer, symbol->is_public ? "public" : "private") ||
            !weave_json_key(writer, "definition") ||
            !weave_si_write_span(
                writer, symbol->source_index, symbol->start, symbol->end) ||
            !weave_json_key(writer, "signature") ||
            !weave_json_object_begin(writer) ||
            !weave_json_key(writer, "canonical") ||
            !weave_json_string(writer, symbol->signature) ||
            !weave_json_key(writer, "summary") ||
            !weave_json_string(writer, symbol->summary) ||
            !weave_json_object_end(writer) ||
            !weave_json_object_end(writer)) {
            return 0;
        }
    }
    return weave_json_array_end(writer);
}

static int weave_si_write_references(
    weave_json_writer *writer,
    const weave_si_model *model) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t index = 0; index < model->reference_count; ++index) {
        const weave_si_reference *reference = &model->references[index];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") ||
            !weave_si_json_id(writer, "reference", index) ||
            !weave_json_key(writer, "symbol_id") ||
            !weave_si_json_optional_id(
                writer, "symbol", reference->symbol_index) ||
            !weave_json_key(writer, "role") ||
            !weave_json_string(writer, reference->role) ||
            !weave_json_key(writer, "span") ||
            !weave_si_write_span(
                writer,
                reference->source_index,
                reference->start,
                reference->end) ||
            !weave_json_key(writer, "status") ||
            !weave_json_string(writer, reference->status) ||
            !weave_json_object_end(writer)) {
            return 0;
        }
    }
    return weave_json_array_end(writer);
}

static int weave_si_write_imports(
    weave_json_writer *writer,
    const weave_si_model *model) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t index = 0; index < model->import_count; ++index) {
        const weave_si_import *item = &model->imports[index];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") ||
            !weave_si_json_id(writer, "import", index) ||
            !weave_json_key(writer, "module_id") ||
            !weave_si_json_id(writer, "module", item->module_index) ||
            !weave_json_key(writer, "source_module") ||
            !weave_json_string(writer, item->source_module) ||
            !weave_json_key(writer, "imported_module_id") ||
            !weave_si_json_optional_id(
                writer, "module", item->imported_module_index) ||
            !weave_json_key(writer, "imported_name") ||
            !weave_json_string(writer, item->imported_name) ||
            !weave_json_key(writer, "local_name") ||
            !weave_json_string(writer, item->imported_name) ||
            !weave_json_key(writer, "symbol_id") ||
            !weave_si_json_optional_id(writer, "symbol", item->symbol_index) ||
            !weave_json_key(writer, "span") ||
            !weave_si_write_span(
                writer, item->source_index, item->start, item->end) ||
            !weave_json_key(writer, "status") ||
            !weave_json_string(writer, item->status) ||
            !weave_json_object_end(writer)) {
            return 0;
        }
    }
    return weave_json_array_end(writer);
}

static int weave_si_write_exports(
    weave_json_writer *writer,
    const weave_si_model *model) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t index = 0; index < model->export_count; ++index) {
        const weave_si_export *item = &model->exports[index];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") ||
            !weave_si_json_id(writer, "export", index) ||
            !weave_json_key(writer, "module_id") ||
            !weave_si_json_id(writer, "module", item->module_index) ||
            !weave_json_key(writer, "name") ||
            !weave_json_string(writer, item->name) ||
            !weave_json_key(writer, "symbol_id") ||
            !weave_si_json_optional_id(writer, "symbol", item->symbol_index) ||
            !weave_json_key(writer, "span") ||
            !weave_si_write_span(
                writer, item->source_index, item->start, item->end) ||
            !weave_json_key(writer, "status") ||
            !weave_json_string(writer, item->status) ||
            !weave_json_object_end(writer)) {
            return 0;
        }
    }
    return weave_json_array_end(writer);
}

static int weave_si_write_call_edges(
    weave_json_writer *writer,
    const weave_si_model *model) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t index = 0; index < model->call_edge_count; ++index) {
        const weave_si_call_edge *edge = &model->call_edges[index];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") ||
            !weave_si_json_id(writer, "call-edge", index) ||
            !weave_json_key(writer, "caller_symbol_id") ||
            !weave_si_json_optional_id(
                writer, "symbol", edge->caller_symbol_index) ||
            !weave_json_key(writer, "callee_symbol_id") ||
            !weave_si_json_optional_id(
                writer, "symbol", edge->callee_symbol_index) ||
            !weave_json_key(writer, "call_reference_id") ||
            !weave_si_json_id(writer, "reference", edge->reference_index) ||
            !weave_json_key(writer, "status") ||
            !weave_json_string(writer, edge->status) ||
            !weave_json_object_end(writer)) {
            return 0;
        }
    }
    return weave_json_array_end(writer);
}

static int weave_si_write_specializations(
    weave_json_writer *writer,
    const weave_si_model *model) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t index = 0; index < model->specialization_count; ++index) {
        const weave_si_specialization *item = &model->specializations[index];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") ||
            !weave_si_json_id(writer, "specialization", index) ||
            !weave_json_key(writer, "kind") ||
            !weave_json_string(writer, item->kind) ||
            !weave_json_key(writer, "generic_name") ||
            !weave_json_string(writer, item->generic_name) ||
            !weave_json_key(writer, "specialized_name") ||
            !weave_json_string(writer, item->specialized_name) ||
            !weave_json_key(writer, "arguments") ||
            !weave_json_array_begin(writer)) {
            return 0;
        }
        for (size_t arg = 0; arg < item->argument_count; ++arg) {
            if (!weave_json_string(writer, item->arguments[arg])) return 0;
        }
        if (!weave_json_array_end(writer) || !weave_json_object_end(writer)) {
            return 0;
        }
    }
    return weave_json_array_end(writer);
}

static int weave_si_write_matches(
    weave_json_writer *writer,
    const weave_si_model *model) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t index = 0; index < model->match_count; ++index) {
        const weave_si_match *item = &model->matches[index];
        if (!weave_json_object_begin(writer) ||
            !weave_json_key(writer, "id") ||
            !weave_si_json_id(writer, "match", index) ||
            !weave_json_key(writer, "enum_symbol_id") ||
            !weave_si_json_optional_id(
                writer, "symbol", item->enum_symbol_index) ||
            !weave_json_key(writer, "span") ||
            !weave_si_write_span(
                writer, item->source_index, item->start, item->end) ||
            !weave_json_key(writer, "exhaustive") ||
            !weave_si_json_bool(writer, item->exhaustive) ||
            !weave_json_key(writer, "wildcard") ||
            !weave_si_json_bool(writer, item->wildcard) ||
            !weave_json_key(writer, "arm_count") ||
            !weave_json_int64(writer, (int64_t)item->arm_count) ||
            !weave_json_object_end(writer)) {
            return 0;
        }
    }
    return weave_json_array_end(writer);
}

static int weave_si_write_document(
    FILE *stream,
    const weave_si_model *model) {
    weave_json_writer writer;
    weave_json_writer_init(&writer, stream);
    if (!weave_json_object_begin(&writer) ||
        !weave_json_key(&writer, "format") ||
        !weave_json_string(&writer, "weavec-semantic-index-v1") ||
        !weave_json_key(&writer, "schema_id") ||
        !weave_json_string(
            &writer, "urn:weavec:schema:semantic-index:v1") ||
        !weave_json_key(&writer, "schema_version") ||
        !weave_json_int64(&writer, 1) ||
        !weave_json_key(&writer, "compiler") ||
        !weave_json_object_begin(&writer) ||
        !weave_json_key(&writer, "name") ||
        !weave_json_string(&writer, "weavec") ||
        !weave_json_key(&writer, "version") ||
        !weave_json_string(&writer, weave_compiler_version) ||
        !weave_json_key(&writer, "public_variant") ||
        !weave_json_string(&writer, "final") ||
        !weave_json_object_end(&writer) ||
        !weave_json_key(&writer, "language") ||
        !weave_json_object_begin(&writer) ||
        !weave_json_key(&writer, "name") ||
        !weave_json_string(&writer, "Weave") ||
        !weave_json_key(&writer, "surface_version") ||
        !weave_json_string(&writer, "weave-surface-v1") ||
        !weave_json_key(&writer, "grammar_id") ||
        !weave_json_string(&writer, "weave-surface-grammar-v1") ||
        !weave_json_object_end(&writer) ||
        !weave_json_key(&writer, "analysis") ||
        !weave_json_object_begin(&writer) ||
        !weave_json_key(&writer, "status") ||
        !weave_json_string(&writer, model->status) ||
        !weave_json_key(&writer, "complete") ||
        !weave_si_json_bool(&writer, strcmp(model->status, "complete") == 0) ||
        !weave_json_key(&writer, "source_set_sha256") ||
        !weave_json_string(&writer, model->source_set_sha256) ||
        !weave_json_key(&writer, "options_sha256") ||
        !weave_json_string(&writer, model->options_sha256) ||
        !weave_json_key(&writer, "identity_policy") ||
        !weave_json_string(
            &writer, "supplied-source-order+utf8-byte-span") ||
        !weave_json_key(&writer, "ordering_policy") ||
        !weave_json_string(&writer, "weavec-semantic-index-order-v1") ||
        !weave_json_key(&writer, "diagnostics_complete") ||
        !weave_si_json_bool(&writer, 1)) {
        return 0;
    }
    if (strcmp(model->status, "incomplete") == 0) {
        if (!weave_json_key(&writer, "incomplete_reason") ||
            !weave_json_string(
                &writer,
                "read/write/type references are not emitted yet")) {
            return 0;
        }
    }
    if (!weave_json_object_end(&writer) ||
        !weave_json_key(&writer, "sources") ||
        !weave_si_write_sources(&writer, model) ||
        !weave_json_key(&writer, "modules") ||
        !weave_si_write_modules(&writer, model) ||
        !weave_json_key(&writer, "symbols") ||
        !weave_si_write_symbols(&writer, model) ||
        !weave_json_key(&writer, "references") ||
        !weave_si_write_references(&writer, model) ||
        !weave_json_key(&writer, "imports") ||
        !weave_si_write_imports(&writer, model) ||
        !weave_json_key(&writer, "exports") ||
        !weave_si_write_exports(&writer, model) ||
        !weave_json_key(&writer, "call_edges") ||
        !weave_si_write_call_edges(&writer, model) ||
        !weave_json_key(&writer, "specializations") ||
        !weave_si_write_specializations(&writer, model) ||
        !weave_json_key(&writer, "matches") ||
        !weave_si_write_matches(&writer, model) ||
        !weave_json_key(&writer, "diagnostics") ||
        !weave_json_object_begin(&writer) ||
        !weave_json_key(&writer, "format") ||
        !weave_json_string(&writer, "weavec-diagnostics-v1") ||
        !weave_json_key(&writer, "complete") ||
        !weave_si_json_bool(&writer, 1) ||
        !weave_json_key(&writer, "items") ||
        !weave_json_array_begin(&writer)) {
        return 0;
    }
    if (model->diagnostic_code != NULL) {
        if (!weave_json_object_begin(&writer) ||
            !weave_json_key(&writer, "code") ||
            !weave_json_string(&writer, model->diagnostic_code) ||
            !weave_json_key(&writer, "severity") ||
            !weave_json_string(&writer, "error") ||
            !weave_json_key(&writer, "message") ||
            !weave_json_string(&writer, model->diagnostic_message) ||
            !weave_json_key(&writer, "span") ||
            !weave_si_write_span(
                &writer,
                model->diagnostic_source,
                model->diagnostic_start,
                model->diagnostic_end) ||
            !weave_json_object_end(&writer)) {
            return 0;
        }
    }
    return weave_json_array_end(&writer) &&
        weave_json_object_end(&writer) &&
        weave_json_object_end(&writer) &&
        weave_json_writer_finish(&writer);
}

static int weave_si_publish_stream(
    FILE *stream,
    const void *opaque) {
    return weave_si_write_document(
        stream, (const weave_si_model *)opaque);
}

static int weave_si_publish(
    const char *path,
    const weave_si_model *model) {
    return weave_publish_document(
        path,
        "semantic-index output",
        0644,
        weave_si_publish_stream,
        model) == 0;
}
