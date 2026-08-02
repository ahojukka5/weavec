// SPDX-License-Identifier: Apache-2.0
//
// Body-reference traversal for weavec-semantic-index-v1. Unknown low-level
// compatibility forms keep the graph explicitly incomplete rather than
// guessing identifier roles.

static int weave_si_collect_expression_references(
    weave_si_model *model,
    size_t source_index,
    size_t caller_symbol_index,
    int64_t node);

static int weave_si_collect_children_from(
    weave_si_model *model,
    size_t source_index,
    size_t caller_symbol_index,
    int64_t list,
    size_t first_ordinal) {
    weave_si_source *source = &model->sources[source_index];
    int64_t child = weave_si_nth_child(source->tree, list, first_ordinal);
    while (child >= 0) {
        if (!weave_si_collect_expression_references(
                model, source_index, caller_symbol_index, child)) {
            return 0;
        }
        child = node_next_sibling(source->tree, child);
    }
    return 1;
}

static int weave_si_collect_nested_lists_from(
    weave_si_model *model,
    size_t source_index,
    size_t caller_symbol_index,
    int64_t list,
    size_t first_ordinal) {
    weave_si_source *source = &model->sources[source_index];
    int64_t child = weave_si_nth_child(source->tree, list, first_ordinal);
    while (child >= 0) {
        if (node_kind(source->tree, child) == node_list() &&
            !weave_si_collect_expression_references(
                model, source_index, caller_symbol_index, child)) {
            return 0;
        }
        child = node_next_sibling(source->tree, child);
    }
    return 1;
}

static int weave_si_collect_field_reference(
    weave_si_model *model,
    size_t source_index,
    size_t caller_symbol_index,
    int64_t receiver,
    int64_t field_node,
    const char *role) {
    char *receiver_type = weave_si_expression_type(
        model, source_index, caller_symbol_index, receiver);
    char *field = weave_si_node_text(&model->sources[source_index], field_node);
    size_t symbol_index = WEAVE_SI_NONE;
    if (receiver_type != NULL && field != NULL &&
        caller_symbol_index < model->symbol_count) {
        symbol_index = weave_si_find_field_symbol(
            model,
            model->symbols[caller_symbol_index].module_index,
            receiver_type,
            field);
    }
    const char *status = symbol_index == WEAVE_SI_NONE
        ? "unresolved"
        : "resolved";
    int result = weave_si_add_node_reference(
        model, source_index, field_node, symbol_index, role, status);
    free(receiver_type);
    free(field);
    return result;
}

static int weave_si_collect_expression_references(
    weave_si_model *model,
    size_t source_index,
    size_t caller_symbol_index,
    int64_t node) {
    weave_si_source *source = &model->sources[source_index];
    if (node < 0) return 1;
    if (node_kind(source->tree, node) == node_ident()) {
        char *name = weave_si_node_text(source, node);
        int skip = name != NULL &&
            (strcmp(name, "true") == 0 || strcmp(name, "false") == 0 ||
             strcmp(name, "null") == 0);
        free(name);
        return skip ? 1 : weave_si_add_value_reference(
            model, source_index, caller_symbol_index, node, "read");
    }
    if (node_kind(source->tree, node) != node_list()) return 1;
    int64_t head_node = weave_si_nth_child(source->tree, node, 0);
    char *head = weave_si_node_text(source, head_node);
    if (head == NULL) return 0;
    int result = 1;
    if (strcmp(head, "let") == 0) {
        result = weave_si_add_type_reference(
            model,
            source_index,
            model->symbols[caller_symbol_index].module_index,
            weave_si_nth_child(source->tree, node, 2)) &&
            weave_si_collect_expression_references(
                model,
                source_index,
                caller_symbol_index,
                weave_si_nth_child(source->tree, node, 3));
    } else if (strcmp(head, "set") == 0 ||
               strcmp(head, "local_set") == 0 ||
               strcmp(head, "global_set") == 0) {
        result = weave_si_add_value_reference(
            model,
            source_index,
            caller_symbol_index,
            weave_si_nth_child(source->tree, node, 1),
            "write") &&
            weave_si_collect_children_from(
                model, source_index, caller_symbol_index, node, 2);
    } else if (strcmp(head, "param_get") == 0 ||
               strcmp(head, "local_get") == 0 ||
               strcmp(head, "global_get") == 0) {
        result = weave_si_add_value_reference(
            model,
            source_index,
            caller_symbol_index,
            weave_si_nth_child(source->tree, node, 1),
            "read");
    } else if (strcmp(head, "call") == 0 ||
               strncmp(head, "call_", 5) == 0) {
        result = weave_si_collect_children_from(
            model, source_index, caller_symbol_index, node, 2);
    } else if (strcmp(head, "op") == 0) {
        result = weave_si_collect_children_from(
            model, source_index, caller_symbol_index, node, 2);
    } else if (strcmp(head, "cast") == 0) {
        result = weave_si_add_type_reference(
            model,
            source_index,
            model->symbols[caller_symbol_index].module_index,
            weave_si_nth_child(source->tree, node, 1)) &&
            weave_si_collect_expression_references(
                model,
                source_index,
                caller_symbol_index,
                weave_si_nth_child(source->tree, node, 2));
    } else if (strcmp(head, "new") == 0) {
        int64_t type_node = weave_si_nth_child(source->tree, node, 1);
        char *structure = weave_si_node_text(source, type_node);
        result = weave_si_add_type_reference(
            model,
            source_index,
            model->symbols[caller_symbol_index].module_index,
            type_node);
        int64_t clause = weave_si_nth_child(source->tree, node, 2);
        while (result && clause >= 0) {
            int64_t field_node = weave_si_nth_child(source->tree, clause, 0);
            char *field = weave_si_node_text(source, field_node);
            size_t field_index = structure == NULL || field == NULL
                ? WEAVE_SI_NONE
                : weave_si_find_field_symbol(
                    model,
                    model->symbols[caller_symbol_index].module_index,
                    structure,
                    field);
            result = weave_si_add_node_reference(
                model,
                source_index,
                field_node,
                field_index,
                "write",
                field_index == WEAVE_SI_NONE ? "unresolved" : "resolved") &&
                weave_si_collect_children_from(
                    model, source_index, caller_symbol_index, clause, 1);
            free(field);
            clause = node_next_sibling(source->tree, clause);
        }
        free(structure);
    } else if (strcmp(head, "field-get") == 0 ||
               strcmp(head, "field-set") == 0) {
        int64_t receiver = weave_si_nth_child(source->tree, node, 1);
        int64_t field_node = weave_si_nth_child(source->tree, node, 2);
        result = weave_si_collect_expression_references(
            model, source_index, caller_symbol_index, receiver) &&
            weave_si_collect_field_reference(
                model,
                source_index,
                caller_symbol_index,
                receiver,
                field_node,
                strcmp(head, "field-get") == 0 ? "read" : "write");
        if (result && strcmp(head, "field-set") == 0) {
            result = weave_si_collect_expression_references(
                model,
                source_index,
                caller_symbol_index,
                weave_si_nth_child(source->tree, node, 3));
        }
    } else if (strcmp(head, "qgate") == 0) {
        result = weave_si_collect_children_from(
            model, source_index, caller_symbol_index, node, 2);
    } else if (strcmp(head, "qmeasure") == 0) {
        result = weave_si_collect_expression_references(
            model,
            source_index,
            caller_symbol_index,
            weave_si_nth_child(source->tree, node, 1));
    } else if (weave_si_structural_body_head(head) ||
               weave_si_typed_compatibility_head(head)) {
        result = weave_si_collect_children_from(
            model, source_index, caller_symbol_index, node, 1);
    } else if (strcmp(head, "return_void") == 0 ||
               strcmp(head, "pure") == 0 ||
               strcmp(head, "no_alloc") == 0 ||
               strcmp(head, "deterministic") == 0) {
        result = 1;
    } else {
        weave_si_mark_body_incomplete(model);
        result = weave_si_collect_nested_lists_from(
            model, source_index, caller_symbol_index, node, 1);
    }
    free(head);
    return result;
}

static int weave_si_collect_declaration_type_references(
    weave_si_model *model) {
    for (size_t index = 0; index < model->symbol_count; ++index) {
        weave_si_symbol *symbol = &model->symbols[index];
        if (weave_si_is_kind(symbol, "field")) continue;
        weave_si_source *source = &model->sources[symbol->source_index];
        int64_t declaration = symbol->declaration_node;
        if (weave_si_is_kind(symbol, "fn") ||
            weave_si_is_kind(symbol, "entry") ||
            weave_si_is_kind(symbol, "extern")) {
            int64_t params = weave_si_nth_child(source->tree, declaration, 2);
            if (params >= 0 && weave_si_head_equals(source, params, "params")) {
                int64_t parameter = node_next_sibling(
                    source->tree, node_first_child(source->tree, params));
                while (parameter >= 0) {
                    if (node_kind(source->tree, parameter) == node_list() &&
                        !weave_si_add_type_reference(
                            model,
                            symbol->source_index,
                            symbol->module_index,
                            weave_si_nth_child(source->tree, parameter, 1))) {
                        return 0;
                    }
                    parameter = node_next_sibling(source->tree, parameter);
                }
            }
            int64_t returns = weave_si_nth_child(source->tree, declaration, 3);
            if (returns >= 0 && weave_si_head_equals(source, returns, "returns") &&
                !weave_si_add_type_reference(
                    model,
                    symbol->source_index,
                    symbol->module_index,
                    weave_si_nth_child(source->tree, returns, 1))) {
                return 0;
            }
        } else if (weave_si_is_kind(symbol, "const")) {
            if (!weave_si_add_type_reference(
                    model,
                    symbol->source_index,
                    symbol->module_index,
                    weave_si_nth_child(source->tree, declaration, 2))) {
                return 0;
            }
        } else if (weave_si_is_kind(symbol, "struct")) {
            int64_t field = weave_si_nth_child(source->tree, declaration, 2);
            while (field >= 0) {
                if (weave_si_head_equals(source, field, "field") &&
                    !weave_si_add_type_reference(
                        model,
                        symbol->source_index,
                        symbol->module_index,
                        weave_si_nth_child(source->tree, field, 2))) {
                    return 0;
                }
                field = node_next_sibling(source->tree, field);
            }
        }
    }
    return 1;
}

static int weave_si_collect_body_references(weave_si_model *model) {
    for (size_t symbol_index = 0;
         symbol_index < model->symbol_count;
         ++symbol_index) {
        weave_si_symbol *symbol = &model->symbols[symbol_index];
        if ((!weave_si_is_kind(symbol, "fn") &&
             !weave_si_is_kind(symbol, "entry")) ||
            !symbol->is_callable) {
            continue;
        }
        weave_si_source *source = &model->sources[symbol->source_index];
        weave_si_module *module = &model->modules[symbol->module_index];
        if (module->explicit_module) {
            if (weave_surface_module_select(
                    source->bytes,
                    (int64_t)module->name_start,
                    (int64_t)module->name_length) < 0) {
                return 0;
            }
        } else if (weave_surface_module_use_legacy() != 0) {
            return 0;
        }
        int64_t child = weave_si_nth_child(
            source->tree, symbol->declaration_node, 4);
        while (child >= 0) {
            if (!weave_si_collect_expression_references(
                    model,
                    symbol->source_index,
                    symbol_index,
                    child)) {
                return 0;
            }
            child = node_next_sibling(source->tree, child);
        }
    }
    return 1;
}

static int weave_si_collect_calls(weave_si_model *model) {
    model->body_references_complete = 1;
    if (!weave_si_collect_declaration_type_references(model) ||
        !weave_si_collect_calls_base(model) ||
        !weave_si_collect_body_references(model)) {
        return 0;
    }
    for (size_t index = 0; index < model->reference_count; ++index) {
        if (strcmp(model->references[index].status, "resolved") != 0) {
            weave_si_mark_body_incomplete(model);
            break;
        }
    }
    return 1;
}
