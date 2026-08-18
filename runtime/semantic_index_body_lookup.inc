// SPDX-License-Identifier: Apache-2.0
//
// Lookup and type helpers for compiler-owned body references. The ordinary
// frontend has already validated these parser trees; this layer only maps
// validated source relationships into the semantic-index data model.

static int weave_si_is_kind(
    const weave_si_symbol *symbol,
    const char *kind) {
    return strcmp(symbol->kind, kind) == 0;
}

static int weave_si_module_is_legacy(
    const weave_si_model *model,
    size_t module_index) {
    return module_index < model->module_count &&
        !model->modules[module_index].explicit_module;
}

static size_t weave_si_find_visible_top_symbol(
    const weave_si_model *model,
    size_t module_index,
    const char *name,
    const char *kind) {
    if (name == NULL || kind == NULL) return WEAVE_SI_NONE;
    for (size_t index = 0; index < model->symbol_count; ++index) {
        const weave_si_symbol *symbol = &model->symbols[index];
        if (symbol->module_index == module_index &&
            weave_si_is_kind(symbol, kind) &&
            strcmp(symbol->name, name) == 0) {
            return index;
        }
    }
    for (size_t index = 0; index < model->import_count; ++index) {
        const weave_si_import *item = &model->imports[index];
        if (item->module_index == module_index &&
            strcmp(item->status, "resolved") == 0 &&
            strcmp(item->imported_name, name) == 0 &&
            item->symbol_index != WEAVE_SI_NONE &&
            weave_si_is_kind(&model->symbols[item->symbol_index], kind)) {
            return item->symbol_index;
        }
    }
    // Program-form files share one namespace, matching the frontend.
    if (weave_si_module_is_legacy(model, module_index)) {
        for (size_t index = 0; index < model->symbol_count; ++index) {
            const weave_si_symbol *symbol = &model->symbols[index];
            if (symbol->module_index != module_index &&
                weave_si_module_is_legacy(model, symbol->module_index) &&
                weave_si_is_kind(symbol, kind) &&
                strcmp(symbol->name, name) == 0) {
                return index;
            }
        }
    }
    return WEAVE_SI_NONE;
}

static size_t weave_si_find_field_symbol(
    const weave_si_model *model,
    size_t module_index,
    const char *structure,
    const char *field) {
    size_t structure_index = weave_si_find_visible_top_symbol(
        model, module_index, structure, "struct");
    if (structure_index == WEAVE_SI_NONE) return WEAVE_SI_NONE;
    size_t owner_module = model->symbols[structure_index].module_index;
    size_t length = strlen(structure);
    for (size_t index = 0; index < model->symbol_count; ++index) {
        const weave_si_symbol *symbol = &model->symbols[index];
        if (symbol->module_index != owner_module ||
            !weave_si_is_kind(symbol, "field") ||
            strcmp(symbol->name, field) != 0 ||
            strncmp(symbol->signature, "(field ", 7) != 0) {
            continue;
        }
        const char *owner = symbol->signature + 7;
        if (strncmp(owner, structure, length) == 0 && owner[length] == ' ') {
            return index;
        }
    }
    return WEAVE_SI_NONE;
}

static int weave_si_builtin_type(const char *name) {
    static const char *const types[] = {
        "i32", "i64", "f32", "f64", "bool", "ptr", "void", "Qubit",
    };
    for (size_t index = 0; index < sizeof(types) / sizeof(types[0]); ++index) {
        if (strcmp(name, types[index]) == 0) return 1;
    }
    return 0;
}

static int weave_si_string_ends_with(
    const char *value,
    const char *suffix) {
    size_t value_length = strlen(value);
    size_t suffix_length = strlen(suffix);
    return value_length >= suffix_length &&
        memcmp(
            value + value_length - suffix_length,
            suffix,
            suffix_length) == 0;
}

static int weave_si_typed_compatibility_head(const char *head) {
    static const char *const suffixes[] = {
        "_i32", "_i64", "_f32", "_f64", "_bool", "_ptr", "_void",
    };
    if (strncmp(head, "cast_", 5) == 0) return 1;
    for (size_t index = 0;
         index < sizeof(suffixes) / sizeof(suffixes[0]);
         ++index) {
        if (weave_si_string_ends_with(head, suffixes[index])) return 1;
    }
    return 0;
}

static int weave_si_structural_body_head(const char *head) {
    static const char *const heads[] = {
        "do", "if", "condition", "then", "else", "while", "return",
        "requires", "ensures", "params", "returns",
        "type-params", "type-app", "type-args",
        "variant", "variant-tag", "variant-payload",
        "match", "case", "try",
        "for", "range", "break", "continue",
    };
    for (size_t index = 0; index < sizeof(heads) / sizeof(heads[0]); ++index) {
        if (strcmp(head, heads[index]) == 0) return 1;
    }
    return 0;
}

static void weave_si_mark_body_incomplete(weave_si_model *model) {
    model->body_references_complete = 0;
}

static int weave_si_add_node_reference(
    weave_si_model *model,
    size_t source_index,
    int64_t node,
    size_t symbol_index,
    const char *role,
    const char *status) {
    weave_si_source *source = &model->sources[source_index];
    size_t start = 0;
    size_t end = 0;
    if (!weave_si_span(source, node, &start, &end)) return 0;
    weave_si_reference reference = {
        .source_index = source_index,
        .symbol_index = symbol_index,
        .start = start,
        .end = end,
        .role = role,
        .status = status,
    };
    size_t ignored = WEAVE_SI_NONE;
    return weave_si_add_reference(model, &reference, &ignored);
}

static size_t weave_si_find_nominal_type(
    const weave_si_model *model,
    size_t module_index,
    const char *name) {
    size_t found = weave_si_find_visible_top_symbol(
        model, module_index, name, "struct");
    if (found != WEAVE_SI_NONE) return found;
    return weave_si_find_visible_top_symbol(
        model, module_index, name, "enum");
}

static size_t weave_si_find_variant_symbol(
    const weave_si_model *model,
    size_t module_index,
    const char *enumeration,
    const char *constructor) {
    size_t enum_index = weave_si_find_visible_top_symbol(
        model, module_index, enumeration, "enum");
    if (enum_index == WEAVE_SI_NONE || enumeration == NULL ||
        constructor == NULL) {
        return WEAVE_SI_NONE;
    }
    size_t owner_module = model->symbols[enum_index].module_index;
    size_t prefix_len = strlen(enumeration);
    for (size_t index = 0; index < model->symbol_count; ++index) {
        const weave_si_symbol *symbol = &model->symbols[index];
        if (symbol->module_index != owner_module ||
            !weave_si_is_kind(symbol, "variant") ||
            strcmp(symbol->name, constructor) != 0 ||
            symbol->signature == NULL) {
            continue;
        }
        if (strncmp(symbol->signature, "(variant ", 9) == 0 &&
            strncmp(symbol->signature + 9, enumeration, prefix_len) == 0 &&
            symbol->signature[9 + prefix_len] == ' ') {
            return index;
        }
    }
    return WEAVE_SI_NONE;
}

static int weave_si_type_param_named(
    const weave_si_source *source,
    int64_t declaration,
    const char *name) {
    int64_t clause = weave_si_find_clause(source, declaration, "type-params");
    if (clause < 0 || name == NULL) return 0;
    int64_t parameter = node_next_sibling(
        source->tree, node_first_child(source->tree, clause));
    while (parameter >= 0) {
        char *candidate = weave_si_node_text(source, parameter);
        int match = candidate != NULL && strcmp(candidate, name) == 0;
        free(candidate);
        if (match) return 1;
        parameter = node_next_sibling(source->tree, parameter);
    }
    return 0;
}

static int weave_si_add_type_reference(
    weave_si_model *model,
    size_t source_index,
    size_t module_index,
    int64_t type_node) {
    weave_si_source *source = &model->sources[source_index];
    if (type_node < 0) return 1;
    if (node_kind(source->tree, type_node) == node_list()) {
        if (weave_si_head_equals(source, type_node, "type-app") ||
            weave_si_head_equals(source, type_node, "type-args") ||
            weave_si_head_equals(source, type_node, "type-params")) {
            int64_t child = weave_si_nth_child(source->tree, type_node, 1);
            while (child >= 0) {
                if (!weave_si_add_type_reference(
                        model, source_index, module_index, child)) {
                    return 0;
                }
                child = node_next_sibling(source->tree, child);
            }
            return 1;
        }
        return 1;
    }
    char *name = weave_si_node_text(source, type_node);
    if (name == NULL) return 0;
    size_t symbol_index = weave_si_find_nominal_type(
        model, module_index, name);
    int type_param = 0;
    if (symbol_index == WEAVE_SI_NONE) {
        for (size_t index = 0; index < model->symbol_count; ++index) {
            const weave_si_symbol *symbol = &model->symbols[index];
            if (symbol->module_index == module_index &&
                (weave_si_is_kind(symbol, "fn") ||
                 weave_si_is_kind(symbol, "struct") ||
                 weave_si_is_kind(symbol, "enum")) &&
                weave_si_type_param_named(
                    &model->sources[symbol->source_index],
                    symbol->declaration_node,
                    name)) {
                type_param = 1;
                break;
            }
        }
    }
    const char *status = symbol_index != WEAVE_SI_NONE ||
        weave_si_builtin_type(name) || type_param
        ? "resolved" : "unresolved";
    int result = weave_si_add_node_reference(
        model, source_index, type_node, symbol_index, "type", status);
    free(name);
    return result;
}

static char *weave_si_find_local_type_in_node(
    const weave_si_source *source,
    int64_t node,
    const char *name,
    size_t use_start,
    size_t *best_start) {
    if (node < 0 || node_kind(source->tree, node) != node_list()) return NULL;
    char *result = NULL;
    int64_t name_node = -1;
    int64_t type_node = -1;
    const char *fallback = NULL;
    if (weave_si_head_equals(source, node, "let")) {
        name_node = weave_si_nth_child(source->tree, node, 1);
        if (weave_si_nth_child(source->tree, node, 3) >= 0) {
            type_node = weave_si_nth_child(source->tree, node, 2);
        } else {
            fallback = "inferred";
        }
    } else if (weave_si_head_equals(source, node, "case") &&
               weave_si_nth_child(source->tree, node, 3) >= 0) {
        name_node = weave_si_nth_child(source->tree, node, 2);
        fallback = "unknown";
    } else if (weave_si_head_equals(source, node, "range")) {
        name_node = weave_si_nth_child(source->tree, node, 1);
        fallback = "i32";
    } else if (weave_si_head_equals(source, node, "qmeasure")) {
        name_node = weave_si_nth_child(source->tree, node, 2);
        fallback = "bool";
    }
    if (name_node >= 0) {
        char *candidate = weave_si_node_text(source, name_node);
        size_t start = 0;
        size_t end = 0;
        size_t form_start = 0;
        size_t form_end = 0;
        int in_scope = 0;
        if (candidate != NULL && strcmp(candidate, name) == 0 &&
            weave_si_span(source, name_node, &start, &end) &&
            weave_si_span(source, node, &form_start, &form_end)) {
            in_scope = weave_si_head_equals(source, node, "case")
                ? end <= use_start && start >= *best_start
                : form_end <= use_start && start >= *best_start;
        }
        if (in_scope) {
            if (type_node >= 0) {
                result = weave_si_node_text(source, type_node);
            } else if (fallback != NULL) {
                result = weave_si_copy(fallback, strlen(fallback));
            }
            if (result != NULL) *best_start = start;
        }
        free(candidate);
    }
    int64_t child = node_first_child(source->tree, node);
    while (child >= 0) {
        char *nested = weave_si_find_local_type_in_node(
            source, child, name, use_start, best_start);
        if (nested != NULL) {
            free(result);
            result = nested;
        }
        child = node_next_sibling(source->tree, child);
    }
    return result;
}

static char *weave_si_find_binding_type(
    const weave_si_model *model,
    size_t caller_symbol_index,
    const char *name,
    size_t use_start) {
    if (caller_symbol_index == WEAVE_SI_NONE ||
        caller_symbol_index >= model->symbol_count) {
        return NULL;
    }
    const weave_si_symbol *caller = &model->symbols[caller_symbol_index];
    const weave_si_source *source = &model->sources[caller->source_index];
    if (strcmp(name, "result") == 0) {
        const char *arrow = strstr(caller->summary, " -> ");
        if (arrow != NULL) {
            return weave_si_copy(arrow + 4, strlen(arrow + 4));
        }
    }
    int64_t params = weave_si_find_clause(
        source, caller->declaration_node, "params");
    if (params >= 0 && weave_si_head_equals(source, params, "params")) {
        int64_t parameter = node_next_sibling(
            source->tree, node_first_child(source->tree, params));
        while (parameter >= 0) {
            if (node_kind(source->tree, parameter) == node_list()) {
                int64_t name_node = weave_si_nth_child(
                    source->tree, parameter, 0);
                char *candidate = weave_si_node_text(source, name_node);
                if (candidate != NULL && strcmp(candidate, name) == 0) {
                    free(candidate);
                    return weave_si_node_text(
                        source,
                        weave_si_nth_child(source->tree, parameter, 1));
                }
                free(candidate);
            }
            parameter = node_next_sibling(source->tree, parameter);
        }
    }
    size_t best_start = 0;
    char *result = NULL;
    int64_t child = weave_si_find_clause(
        source, caller->declaration_node, "do");
    if (child < 0) {
        child = weave_si_nth_child(
            source->tree, caller->declaration_node, 4);
    }
    while (child >= 0) {
        char *nested = weave_si_find_local_type_in_node(
            source, child, name, use_start, &best_start);
        if (nested != NULL) {
            free(result);
            result = nested;
        }
        child = node_next_sibling(source->tree, child);
    }
    return result;
}

static size_t weave_si_resolve_value_name(
    const weave_si_model *model,
    size_t caller_symbol_index,
    const char *name) {
    if (caller_symbol_index == WEAVE_SI_NONE ||
        caller_symbol_index >= model->symbol_count) {
        return WEAVE_SI_NONE;
    }
    return weave_si_find_visible_top_symbol(
        model,
        model->symbols[caller_symbol_index].module_index,
        name,
        "const");
}

static int weave_si_add_value_reference(
    weave_si_model *model,
    size_t source_index,
    size_t caller_symbol_index,
    int64_t node,
    const char *role) {
    weave_si_source *source = &model->sources[source_index];
    char *name = weave_si_node_text(source, node);
    size_t start = 0;
    size_t end = 0;
    if (name == NULL || !weave_si_span(source, node, &start, &end)) {
        free(name);
        return 0;
    }
    char *binding_type = weave_si_find_binding_type(
        model, caller_symbol_index, name, start);
    size_t symbol_index = binding_type == NULL
        ? weave_si_resolve_value_name(model, caller_symbol_index, name)
        : WEAVE_SI_NONE;
    const char *status = binding_type != NULL ||
        symbol_index != WEAVE_SI_NONE || strcmp(name, "result") == 0
        ? "resolved"
        : "unresolved";
    weave_si_reference reference = {
        .source_index = source_index,
        .symbol_index = symbol_index,
        .start = start,
        .end = end,
        .role = role,
        .status = status,
    };
    size_t ignored = WEAVE_SI_NONE;
    free(binding_type);
    free(name);
    return weave_si_add_reference(model, &reference, &ignored);
}

static char *weave_si_symbol_value_type(const weave_si_symbol *symbol) {
    if (weave_si_is_kind(symbol, "const")) {
        return weave_si_copy(symbol->summary, strlen(symbol->summary));
    }
    const char *arrow = strstr(symbol->summary, " -> ");
    return arrow == NULL ? NULL : weave_si_copy(arrow + 4, strlen(arrow + 4));
}

static char *weave_si_field_value_type(const weave_si_symbol *symbol) {
    if (!weave_si_is_kind(symbol, "field") ||
        strncmp(symbol->signature, "(field ", 7) != 0) {
        return NULL;
    }
    const char *space = strchr(symbol->signature + 7, ' ');
    const char *end = strrchr(symbol->signature, ')');
    if (space == NULL || end == NULL || end <= space + 1) return NULL;
    return weave_si_copy(space + 1, (size_t)(end - space - 1));
}

static char *weave_si_expression_type(
    const weave_si_model *model,
    size_t source_index,
    size_t caller_symbol_index,
    int64_t node) {
    const weave_si_source *source = &model->sources[source_index];
    if (node < 0) return NULL;
    if (node_kind(source->tree, node) == node_ident()) {
        char *name = weave_si_node_text(source, node);
        int64_t raw_start = node_text_start(source->tree, node);
        char *binding = name == NULL || raw_start < 0
            ? NULL
            : weave_si_find_binding_type(
                model, caller_symbol_index, name, (size_t)raw_start);
        if (binding != NULL) {
            free(name);
            return binding;
        }
        size_t symbol_index = name == NULL
            ? WEAVE_SI_NONE
            : weave_si_resolve_value_name(model, caller_symbol_index, name);
        free(name);
        return symbol_index == WEAVE_SI_NONE
            ? NULL
            : weave_si_symbol_value_type(&model->symbols[symbol_index]);
    }
    if (node_kind(source->tree, node) != node_list()) return NULL;
    int64_t head_node = weave_si_nth_child(source->tree, node, 0);
    char *head = weave_si_node_text(source, head_node);
    if (head == NULL) return NULL;
    char *result = NULL;
    if (strcmp(head, "param_get") == 0 ||
        strcmp(head, "local_get") == 0 ||
        strcmp(head, "global_get") == 0) {
        int64_t value_node = weave_si_nth_child(source->tree, node, 1);
        char *name = weave_si_node_text(source, value_node);
        int64_t raw_start = node_text_start(source->tree, value_node);
        result = name == NULL || raw_start < 0
            ? NULL
            : weave_si_find_binding_type(
                model, caller_symbol_index, name, (size_t)raw_start);
        if (result == NULL && name != NULL) {
            size_t symbol_index = weave_si_resolve_value_name(
                model, caller_symbol_index, name);
            if (symbol_index != WEAVE_SI_NONE) {
                result = weave_si_symbol_value_type(
                    &model->symbols[symbol_index]);
            }
        }
        free(name);
    } else if (strcmp(head, "new") == 0 || strcmp(head, "cast") == 0) {
        result = weave_si_node_text(
            source, weave_si_nth_child(source->tree, node, 1));
    } else if (strcmp(head, "field-get") == 0) {
        int64_t receiver = weave_si_nth_child(source->tree, node, 1);
        int64_t field_node = weave_si_nth_child(source->tree, node, 2);
        char *receiver_type = weave_si_expression_type(
            model, source_index, caller_symbol_index, receiver);
        char *field = weave_si_node_text(source, field_node);
        if (receiver_type != NULL && field != NULL &&
            caller_symbol_index < model->symbol_count) {
            size_t field_index = weave_si_find_field_symbol(
                model,
                model->symbols[caller_symbol_index].module_index,
                receiver_type,
                field);
            if (field_index != WEAVE_SI_NONE) {
                result = weave_si_field_value_type(&model->symbols[field_index]);
            }
        }
        free(receiver_type);
        free(field);
    } else if (weave_si_call_head(source, node)) {
        int64_t target = weave_si_nth_child(source->tree, node, 1);
        int64_t raw_start = node_text_start(source->tree, target);
        int64_t raw_length = node_text_len(source->tree, target);
        int32_t runtime_index = raw_start < 0 || raw_length < 0
            ? -1
            : weave_surface_symbol_resolve(
                source->bytes, raw_start, raw_length);
        size_t symbol_index = weave_si_symbol_from_runtime(
            model, runtime_index);
        if (symbol_index != WEAVE_SI_NONE) {
            result = weave_si_symbol_value_type(&model->symbols[symbol_index]);
        }
    }
    free(head);
    return result;
}
