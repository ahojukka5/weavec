static int weave_si_collect_source_declarations(
    weave_si_model *model,
    size_t source_index) {
    weave_si_source *source = &model->sources[source_index];
    int64_t root = 0;
    int64_t head = node_first_child(source->tree, root);
    if (head < 0) return 0;
    weave_si_module module = {0};
    module.source_index = source_index;
    if (!weave_si_span(source, root, &module.start, &module.end)) {
        return 0;
    }
    module.exported_symbols = NULL;
    module.exported_count = 0;
    module.exported_capacity = 0;
    if (weave_si_node_text_equals(source, head, "module")) {
        int64_t name_node = node_next_sibling(source->tree, head);
        module.name = weave_si_node_text(source, name_node);
        size_t name_end = 0;
        if (module.name == NULL ||
            !weave_si_span(source, name_node, &module.name_start, &name_end)) {
            free(module.name);
            return 0;
        }
        module.name_length = name_end - module.name_start;
        module.explicit_module = 1;
    } else if (weave_si_node_text_equals(source, head, "program")) {
        char synthetic[64];
        int length = snprintf(synthetic, sizeof(synthetic), "legacy:%zu", source_index);
        if (length <= 0 || (size_t)length >= sizeof(synthetic)) return 0;
        module.name = weave_si_copy(synthetic, (size_t)length);
        module.name_start = 0;
        module.name_length = 0;
        module.explicit_module = 0;
    } else {
        return 0;
    }
    size_t module_index = WEAVE_SI_NONE;
    if (module.name == NULL ||
        !weave_si_add_module(model, &module, &module_index)) {
        free(module.name);
        return 0;
    }
    source->module_index = module_index;
    int64_t child = node_next_sibling(source->tree, head);
    while (child >= 0) {
        if (node_kind(source->tree, child) == node_list()) {
            if (weave_si_head_equals(source, child, "fn")) {
                if (!weave_si_collect_symbol(
                        model, source_index, module_index, child, "fn", 1)) {
                    return 0;
                }
            } else if (weave_si_head_equals(source, child, "entry")) {
                if (!weave_si_collect_symbol(
                        model, source_index, module_index, child, "entry", 1)) {
                    return 0;
                }
            } else if (weave_si_head_equals(source, child, "extern")) {
                if (!weave_si_collect_symbol(
                        model, source_index, module_index, child, "extern", 1)) {
                    return 0;
                }
            } else if (weave_si_head_equals(source, child, "const")) {
                if (!weave_si_collect_symbol(
                        model, source_index, module_index, child, "const", 0)) {
                    return 0;
                }
            } else if (weave_si_head_equals(source, child, "struct")) {
                if (!weave_si_collect_symbol(
                        model, source_index, module_index, child, "struct", 0)) {
                    return 0;
                }
            } else if (weave_si_head_equals(source, child, "enum")) {
                if (!weave_si_collect_symbol(
                        model, source_index, module_index, child, "enum", 0)) {
                    return 0;
                }
            } else if (weave_si_head_equals(source, child, "import")) {
                int64_t module_node = weave_si_nth_child(source->tree, child, 1);
                int64_t list_node = weave_si_nth_child(source->tree, child, 2);
                char *source_module = weave_si_node_text(source, module_node);
                size_t item_start = 0;
                size_t item_end = 0;
                if (source_module == NULL ||
                    !weave_si_span(source, child, &item_start, &item_end)) {
                    free(source_module);
                    return 0;
                }
                int64_t name_node = node_first_child(source->tree, list_node);
                while (name_node >= 0) {
                    char *name = weave_si_node_text(source, name_node);
                    size_t name_start = 0;
                    size_t name_end = 0;
                    if (name == NULL ||
                        !weave_si_span(source, name_node, &name_start, &name_end)) {
                        free(name);
                        free(source_module);
                        return 0;
                    }
                    weave_si_import item = {
                        .module_index = module_index,
                        .source_index = source_index,
                        .source_module = weave_si_copy(
                            source_module, strlen(source_module)),
                        .imported_name = name,
                        .imported_module_index = WEAVE_SI_NONE,
                        .symbol_index = WEAVE_SI_NONE,
                        .start = item_start,
                        .end = item_end,
                        .name_start = name_start,
                        .name_end = name_end,
                        .status = "missing-module",
                    };
                    if (item.source_module == NULL ||
                        !weave_si_add_import(model, &item)) {
                        free(item.source_module);
                        free(item.imported_name);
                        free(source_module);
                        return 0;
                    }
                    name_node = node_next_sibling(source->tree, name_node);
                }
                free(source_module);
            } else if (weave_si_head_equals(source, child, "export")) {
                size_t clause_start = 0;
                size_t clause_end = 0;
                if (!weave_si_span(
                        source, child, &clause_start, &clause_end)) {
                    return 0;
                }
                int64_t name_node = weave_si_nth_child(source->tree, child, 1);
                while (name_node >= 0) {
                    char *name = weave_si_node_text(source, name_node);
                    size_t start = 0;
                    size_t end = 0;
                    if (name == NULL ||
                        !weave_si_span(source, name_node, &start, &end)) {
                        free(name);
                        return 0;
                    }
                    weave_si_export item = {
                        .module_index = module_index,
                        .source_index = source_index,
                        .name = name,
                        .symbol_index = WEAVE_SI_NONE,
                        .start = clause_start,
                        .end = clause_end,
                        .name_start = start,
                        .name_end = end,
                        .status = "missing",
                    };
                    if (!weave_si_add_export(model, &item)) {
                        free(item.name);
                        return 0;
                    }
                    name_node = node_next_sibling(source->tree, name_node);
                }
            }
        }
        child = node_next_sibling(source->tree, child);
    }
    return 1;
}

static int weave_si_module_add_export(
    weave_si_module *module,
    size_t symbol_index) {
    if (module->exported_count == module->exported_capacity) {
        size_t next = module->exported_capacity == 0
            ? 8
            : module->exported_capacity * 2;
        size_t *grown = (size_t *)realloc(
            module->exported_symbols, next * sizeof(*grown));
        if (grown == NULL) return 0;
        module->exported_symbols = grown;
        module->exported_capacity = next;
    }
    module->exported_symbols[module->exported_count++] = symbol_index;
    return 1;
}

static int weave_si_resolve_interfaces(weave_si_model *model) {
    for (size_t index = 0; index < model->export_count; ++index) {
        weave_si_export *item = &model->exports[index];
        item->symbol_index = weave_si_find_symbol(
            model, item->module_index, item->name);
        if (item->symbol_index != WEAVE_SI_NONE) {
            item->status = "resolved";
            model->symbols[item->symbol_index].is_public = 1;
            if (!weave_si_module_add_export(
                    &model->modules[item->module_index],
                    item->symbol_index)) {
                return 0;
            }
        }
        weave_si_reference reference = {
            .source_index = item->source_index,
            .symbol_index = item->symbol_index,
            .start = item->name_start,
            .end = item->name_end,
            .role = "export",
            .status = item->symbol_index == WEAVE_SI_NONE
                ? "unresolved"
                : "resolved",
        };
        size_t ignored = WEAVE_SI_NONE;
        if (!weave_si_add_reference(model, &reference, &ignored)) return 0;
    }
    for (size_t index = 0; index < model->import_count; ++index) {
        weave_si_import *item = &model->imports[index];
        item->imported_module_index = weave_si_find_module(
            model, item->source_module);
        if (item->imported_module_index != WEAVE_SI_NONE) {
            item->symbol_index = weave_si_find_symbol(
                model, item->imported_module_index, item->imported_name);
            if (item->symbol_index == WEAVE_SI_NONE) {
                item->status = "missing-symbol";
            } else if (!weave_si_is_exported(
                           model,
                           item->imported_module_index,
                           item->imported_name)) {
                item->status = "private";
                item->symbol_index = WEAVE_SI_NONE;
            } else {
                item->status = "resolved";
            }
        }
        const char *reference_status = "unresolved";
        if (strcmp(item->status, "resolved") == 0) {
            reference_status = "resolved";
        } else if (strcmp(item->status, "private") == 0) {
            reference_status = "private";
        }
        weave_si_reference reference = {
            .source_index = item->source_index,
            .symbol_index = item->symbol_index,
            .start = item->name_start,
            .end = item->name_end,
            .role = "import",
            .status = reference_status,
        };
        size_t ignored = WEAVE_SI_NONE;
        if (!weave_si_add_reference(model, &reference, &ignored)) return 0;
    }
    return 1;
}
