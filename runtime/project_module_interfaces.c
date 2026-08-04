// SPDX-License-Identifier: Apache-2.0
//
// Add compiler-validated callable interfaces to selected-body WIR units. This
// wrapper is used only by the incremental project compiler; the public frontend
// and backend retain their existing validation behavior.

#ifndef WEAVEC_PROJECT_MODULE_INTERFACES_C
#define WEAVEC_PROJECT_MODULE_INTERFACES_C

static int weave_project_module_write_all(
    int descriptor,
    const void *data,
    size_t length) {
    const unsigned char *bytes = data;
    size_t offset = 0;
    while (offset < length) {
        ssize_t written = write(
            descriptor, bytes + offset, length - offset);
        if (written < 0) {
            if (errno == EINTR) continue;
            return 0;
        }
        offset += (size_t)written;
    }
    return 1;
}

static int weave_project_module_selected_source(size_t *selected) {
    const char *value = getenv(WEAVE_PROJECT_BODY_SOURCE_ENV);
    if (value == NULL || *value == '\0') return 0;
    char *end = NULL;
    errno = 0;
    unsigned long long parsed = strtoull(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' ||
        parsed > (unsigned long long)SIZE_MAX) {
        return 0;
    }
    *selected = (size_t)parsed;
    return 1;
}

static int64_t weave_project_module_symbol_name_node(
    const weave_si_model *model,
    const weave_si_symbol *symbol) {
    if (symbol->source_index >= model->source_count ||
        symbol->declaration_node < 0) {
        return -1;
    }
    void *tree = model->sources[symbol->source_index].tree;
    int64_t head = node_first_child(tree, symbol->declaration_node);
    return head < 0 ? -1 : node_next_sibling(tree, head);
}

static int weave_project_module_emit_symbol_name(
    int descriptor,
    const weave_si_model *model,
    const weave_si_symbol *symbol) {
    int64_t name_node = weave_project_module_symbol_name_node(model, symbol);
    if (name_node < 0 || symbol->source_index >= model->source_count) {
        return 0;
    }
    const weave_si_source *source = &model->sources[symbol->source_index];
    int64_t start = node_text_start(source->tree, name_node);
    int64_t length = node_text_len(source->tree, name_node);
    if (start < 0 || length <= 0 ||
        (uint64_t)start > (uint64_t)source->length ||
        (uint64_t)length > (uint64_t)source->length - (uint64_t)start) {
        return 0;
    }
    return weave_project_module_write_all(
        descriptor, source->bytes + start, (size_t)length);
}

static int weave_project_module_emit_callable_interfaces(
    int descriptor,
    const weave_si_model *model,
    size_t selected_source) {
    for (size_t index = 0; index < model->symbol_count; ++index) {
        const weave_si_symbol *symbol = &model->symbols[index];
        if (!symbol->is_public || !symbol->is_callable ||
            symbol->module_index >= model->module_count ||
            model->modules[symbol->module_index].source_index ==
                selected_source ||
            symbol->signature == NULL) {
            continue;
        }
        const char *suffix = strchr(symbol->signature, ' ');
        if (suffix == NULL) return 0;

        static const char prefix[] = "    (extern ";
        static const char newline[] = "\n";
        if (!weave_project_module_write_all(
                descriptor, prefix, sizeof(prefix) - 1) ||
            !weave_project_module_emit_symbol_name(
                descriptor, model, symbol) ||
            !weave_project_module_write_all(
                descriptor, suffix, strlen(suffix)) ||
            !weave_project_module_write_all(
                descriptor, newline, sizeof(newline) - 1)) {
            return 0;
        }
    }
    return 1;
}

static int weave_project_module_inject_interfaces(
    const char *path,
    weave_si_model *model,
    size_t selected_source) {
    size_t length = 0;
    unsigned char *document = weave_diag_read_file(path, &length);
    static const char footer[] = "  )\n)\n";
    if (document == NULL || length < sizeof(footer) - 1 ||
        memcmp(
            document + length - (sizeof(footer) - 1),
            footer, sizeof(footer) - 1) != 0) {
        free(document);
        return 0;
    }

    char temporary[PATH_MAX];
    if (snprintf(
            temporary, sizeof(temporary),
            "%s.interfaces-XXXXXX", path) >= (int)sizeof(temporary)) {
        free(document);
        return 0;
    }
    int descriptor = mkstemp(temporary);
    if (descriptor < 0) {
        free(document);
        return 0;
    }

    size_t prefix_length = length - (sizeof(footer) - 1);
    int ok = weave_project_module_write_all(
            descriptor, document, prefix_length) &&
        weave_project_module_emit_callable_interfaces(
            descriptor, model, selected_source) &&
        weave_project_module_write_all(
            descriptor, footer, sizeof(footer) - 1) &&
        fsync(descriptor) == 0;
    free(document);
    if (close(descriptor) != 0) ok = 0;
    if (ok && rename(temporary, path) != 0) ok = 0;
    if (!ok) unlink(temporary);
    return ok;
}

static int weave_project_module_lower_sources(
    int32_t argc,
    char **argv,
    const char *output_path,
    int64_t first_input_index) {
    int status = lower_sources(
        argc, argv, output_path, first_input_index);
    if (status != 0) return status;

    size_t selected = 0;
    if (!weave_project_module_selected_source(&selected)) return 0;
    if (first_input_index < 0 || first_input_index > argc) return 1;
    int source_count = argc - (int)first_input_index;
    if (source_count <= 0 || selected >= (size_t)source_count) return 1;

    weave_si_model model;
    memset(&model, 0, sizeof(model));
    model.status = "failed";
    model.diagnostic_code = "WEAVEC-SEMANTIC-INDEX-FAILED";
    model.diagnostic_message = "semantic analysis failed";
    int loaded = weave_si_load_sources(
        &model, source_count, &argv[first_input_index]);
    int valid = loaded > 0 && weave_si_build_model(&model);
    int injected = valid && weave_project_module_inject_interfaces(
        output_path, &model, selected);
    weave_si_free_model(&model);
    if (!injected) {
        unlink(output_path);
        fputs(
            "weavec: cannot publish selected module interfaces\n",
            stderr);
        return 1;
    }
    return 0;
}

#endif
