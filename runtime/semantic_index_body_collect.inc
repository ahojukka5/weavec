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
        int inferred = weave_si_nth_child(source->tree, node, 3) < 0;
        result = 1;
        if (!inferred) {
            result = weave_si_add_type_reference(
                model,
                source_index,
                model->symbols[caller_symbol_index].module_index,
                weave_si_nth_child(source->tree, node, 2));
        }
        result = result && weave_si_collect_expression_references(
            model,
            source_index,
            caller_symbol_index,
            weave_si_nth_child(source->tree, node, inferred ? 2 : 3));
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
    } else if (strcmp(head, "variant") == 0 ||
               strcmp(head, "variant-tag") == 0 ||
               strcmp(head, "variant-payload") == 0) {
        int64_t enum_node = weave_si_nth_child(source->tree, node, 1);
        char *enumeration = weave_si_node_text(source, enum_node);
        result = weave_si_add_type_reference(
            model,
            source_index,
            model->symbols[caller_symbol_index].module_index,
            enum_node);
        if (result && strcmp(head, "variant") == 0) {
            int64_t ctor_at = 2;
            int64_t maybe_args = weave_si_nth_child(source->tree, node, 2);
            if (maybe_args >= 0 &&
                weave_si_head_equals(source, maybe_args, "type-args")) {
                result = weave_si_add_type_reference(
                    model,
                    source_index,
                    model->symbols[caller_symbol_index].module_index,
                    maybe_args);
                ctor_at = 3;
            }
            int64_t ctor_node = weave_si_nth_child(
                source->tree, node, ctor_at);
            char *ctor = weave_si_node_text(source, ctor_node);
            size_t ctor_index = enumeration == NULL || ctor == NULL
                ? WEAVE_SI_NONE
                : weave_si_find_variant_symbol(
                    model,
                    model->symbols[caller_symbol_index].module_index,
                    enumeration,
                    ctor);
            result = result && weave_si_add_node_reference(
                model,
                source_index,
                ctor_node,
                ctor_index,
                "construct",
                ctor_index == WEAVE_SI_NONE ? "unresolved" : "resolved") &&
                weave_si_collect_children_from(
                    model,
                    source_index,
                    caller_symbol_index,
                    node,
                    ctor_at + 1);
            free(ctor);
        } else if (result && strcmp(head, "variant-payload") == 0) {
            int64_t ctor_node = weave_si_nth_child(source->tree, node, 2);
            char *ctor = weave_si_node_text(source, ctor_node);
            size_t ctor_index = enumeration == NULL || ctor == NULL
                ? WEAVE_SI_NONE
                : weave_si_find_variant_symbol(
                    model,
                    model->symbols[caller_symbol_index].module_index,
                    enumeration,
                    ctor);
            result = weave_si_add_node_reference(
                model,
                source_index,
                ctor_node,
                ctor_index,
                "construct",
                ctor_index == WEAVE_SI_NONE ? "unresolved" : "resolved") &&
                weave_si_collect_expression_references(
                    model,
                    source_index,
                    caller_symbol_index,
                    weave_si_nth_child(source->tree, node, 3));
            free(ctor);
        } else if (result) {
            result = weave_si_collect_expression_references(
                model,
                source_index,
                caller_symbol_index,
                weave_si_nth_child(source->tree, node, 2));
        }
        free(enumeration);
    } else if (strcmp(head, "match") == 0) {
        int64_t enum_node = weave_si_nth_child(source->tree, node, 1);
        char *enumeration = weave_si_node_text(source, enum_node);
        size_t enum_index = enumeration == NULL
            ? WEAVE_SI_NONE
            : weave_si_find_visible_top_symbol(
                model,
                model->symbols[caller_symbol_index].module_index,
                enumeration,
                "enum");
        result = weave_si_add_type_reference(
            model,
            source_index,
            model->symbols[caller_symbol_index].module_index,
            enum_node) &&
            weave_si_collect_expression_references(
                model,
                source_index,
                caller_symbol_index,
                weave_si_nth_child(source->tree, node, 2));
        int wildcard = 0;
        size_t arm_count = 0;
        size_t covered = 0;
        size_t declared = 0;
        if (enum_index != WEAVE_SI_NONE) {
            for (size_t index = 0; index < model->symbol_count; ++index) {
                if (model->symbols[index].module_index ==
                        model->symbols[enum_index].module_index &&
                    weave_si_is_kind(&model->symbols[index], "variant") &&
                    model->symbols[index].signature != NULL &&
                    strstr(
                        model->symbols[index].signature,
                        enumeration) != NULL) {
                    declared++;
                }
            }
        }
        int64_t arm = weave_si_nth_child(source->tree, node, 3);
        while (result && arm >= 0) {
            arm_count++;
            int64_t ctor_node = weave_si_nth_child(source->tree, arm, 1);
            char *ctor = weave_si_node_text(source, ctor_node);
            int is_wild = ctor != NULL && strcmp(ctor, "_") == 0;
            if (is_wild) {
                wildcard = 1;
                result = weave_si_add_node_reference(
                    model,
                    source_index,
                    ctor_node,
                    WEAVE_SI_NONE,
                    "pattern",
                    "resolved");
            } else {
                size_t ctor_index = enumeration == NULL || ctor == NULL
                    ? WEAVE_SI_NONE
                    : weave_si_find_variant_symbol(
                        model,
                        model->symbols[caller_symbol_index].module_index,
                        enumeration,
                        ctor);
                if (ctor_index != WEAVE_SI_NONE) covered++;
                result = weave_si_add_node_reference(
                    model,
                    source_index,
                    ctor_node,
                    ctor_index,
                    "pattern",
                    ctor_index == WEAVE_SI_NONE
                        ? "unresolved" : "resolved");
            }
            int64_t body = weave_si_nth_child(
                source->tree,
                arm,
                weave_si_nth_child(source->tree, arm, 3) >= 0 ? 3 : 2);
            result = result && weave_si_collect_expression_references(
                model, source_index, caller_symbol_index, body);
            free(ctor);
            arm = node_next_sibling(source->tree, arm);
        }
        size_t start = 0;
        size_t end = 0;
        if (result && weave_si_span(source, node, &start, &end)) {
            weave_si_match fact = {
                .source_index = source_index,
                .start = start,
                .end = end,
                .enum_symbol_index = enum_index,
                .wildcard = wildcard,
                .exhaustive = wildcard ||
                    (declared > 0 && covered >= declared),
                .arm_count = arm_count,
            };
            result = weave_si_add_match(model, &fact);
        }
        free(enumeration);
    } else if (strcmp(head, "for") == 0) {
        int64_t range = weave_si_nth_child(source->tree, node, 1);
        int64_t body = weave_si_nth_child(source->tree, node, 2);
        result = weave_si_collect_expression_references(
            model, source_index, caller_symbol_index,
            weave_si_nth_child(source->tree, range, 2)) &&
            weave_si_collect_expression_references(
                model, source_index, caller_symbol_index,
                weave_si_nth_child(source->tree, range, 3)) &&
            weave_si_collect_expression_references(
                model, source_index, caller_symbol_index, body);
    } else if (strcmp(head, "range") == 0 ||
               strcmp(head, "break") == 0 ||
               strcmp(head, "continue") == 0) {
        result = 1;
    } else if (strcmp(head, "try") == 0) {
        result = weave_si_collect_children_from(
            model, source_index, caller_symbol_index, node, 1);
    } else if (strcmp(head, "type-app") == 0 ||
               strcmp(head, "type-args") == 0) {
        result = weave_si_add_type_reference(
            model,
            source_index,
            model->symbols[caller_symbol_index].module_index,
            node);
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
            int64_t params = weave_si_find_clause(source, declaration, "params");
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
            int64_t returns = weave_si_find_clause(source, declaration, "returns");
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
        } else if (weave_si_is_kind(symbol, "enum")) {
            int64_t child = weave_si_nth_child(source->tree, declaration, 2);
            while (child >= 0) {
                if (weave_si_head_equals(source, child, "variant") &&
                    weave_si_nth_child(source->tree, child, 2) >= 0 &&
                    !weave_si_add_type_reference(
                        model,
                        symbol->source_index,
                        symbol->module_index,
                        weave_si_nth_child(source->tree, child, 2))) {
                    return 0;
                }
                child = node_next_sibling(source->tree, child);
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
        int64_t child = weave_si_find_clause(
            source, symbol->declaration_node, "do");
        if (child < 0) {
            child = weave_si_nth_child(
                source->tree, symbol->declaration_node, 4);
        }
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

static int weave_si_record_specialization(
    weave_si_model *model,
    const char *kind,
    const char *generic_name,
    const char *specialized_name,
    int32_t spec_index,
    int32_t (*arg_count_fn)(int32_t),
    int32_t (*arg_type_fn)(int32_t, int32_t)) {
    if (generic_name == NULL || specialized_name == NULL) return 0;
    int32_t argc = arg_count_fn(spec_index);
    if (argc < 0) argc = 0;
    char **arguments = NULL;
    if (argc > 0) {
        arguments = (char **)calloc((size_t)argc, sizeof(*arguments));
        if (arguments == NULL) return 0;
        for (int32_t arg = 0; arg < argc; ++arg) {
            int32_t type = arg_type_fn(spec_index, arg);
            char *display = weave_semantic_type_display(type);
            arguments[arg] = display != NULL && display[0] != '\0'
                ? weave_si_copy(display, strlen(display))
                : weave_si_copy("unknown", 7);
            if (arguments[arg] == NULL) {
                for (int32_t prior = 0; prior < arg; ++prior) {
                    free(arguments[prior]);
                }
                free(arguments);
                return 0;
            }
        }
    }
    weave_si_specialization item = {
        .kind = weave_si_copy(kind, strlen(kind)),
        .generic_name = weave_si_copy(generic_name, strlen(generic_name)),
        .specialized_name = weave_si_copy(
            specialized_name, strlen(specialized_name)),
        .arguments = arguments,
        .argument_count = (size_t)argc,
    };
    if (item.kind == NULL ||
        item.generic_name == NULL ||
        item.specialized_name == NULL ||
        !weave_si_add_specialization(model, &item)) {
        free(item.kind);
        free(item.generic_name);
        free(item.specialized_name);
        if (arguments != NULL) {
            for (int32_t arg = 0; arg < argc; ++arg) free(arguments[arg]);
            free(arguments);
        }
        return 0;
    }
    return 1;
}

static int weave_si_collect_specializations(weave_si_model *model) {
    int32_t fn_count = weave_surface_spec_count();
    for (int32_t index = 0; index < fn_count; ++index) {
        if (!weave_si_record_specialization(
                model,
                "fn",
                weave_surface_spec_generic_name(index),
                weave_surface_spec_name(index),
                index,
                weave_surface_spec_arg_count,
                weave_surface_spec_arg_type)) {
            return 0;
        }
    }
    int32_t enum_count = weave_surface_enum_spec_count();
    for (int32_t index = 0; index < enum_count; ++index) {
        if (!weave_si_record_specialization(
                model,
                "enum",
                weave_surface_enum_spec_generic_name(index),
                weave_surface_enum_spec_name(index),
                index,
                weave_surface_enum_spec_arg_count,
                weave_surface_enum_spec_arg_type)) {
            return 0;
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
