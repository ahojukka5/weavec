static size_t weave_si_symbol_from_runtime(
    const weave_si_model *model,
    int32_t runtime_index) {
    if (runtime_index < 0 || runtime_index >= weave_surface_symbol_count) {
        return WEAVE_SI_NONE;
    }
    const weave_surface_symbol *runtime = &weave_surface_symbols[runtime_index];
    size_t module_index = WEAVE_SI_NONE;
    if (runtime->module_index >= 0 &&
        runtime->module_index < weave_surface_module_count) {
        module_index = weave_si_find_module(
            model, weave_surface_modules[runtime->module_index].name);
    }
    for (size_t index = 0; index < model->symbol_count; ++index) {
        const weave_si_symbol *symbol = &model->symbols[index];
        if (!symbol->is_callable) continue;
        if (module_index != WEAVE_SI_NONE && symbol->module_index != module_index) {
            continue;
        }
        if (strlen(symbol->name) == (size_t)runtime->name_length &&
            memcmp(symbol->name, runtime->name, (size_t)runtime->name_length) == 0) {
            return index;
        }
    }
    return WEAVE_SI_NONE;
}

static int weave_si_operator_head_text(const char *head) {
    static const char *const heads[] = {
        "+", "-", "*", "/", "mod",
        "=", "!=", "<", "<=", ">", ">=",
        "and", "or", "not",
        "bit-and", "bit-or", "bit-xor", "shift-left", "shift-right",
    };
    if (head == NULL) return 0;
    for (size_t index = 0; index < sizeof(heads) / sizeof(heads[0]); ++index) {
        if (strcmp(head, heads[index]) == 0) return 1;
    }
    return 0;
}

static int weave_si_wrapped_call_head(
    const weave_si_source *source,
    int64_t node) {
    static const char *const heads[] = {
        "call", "call_i32", "call_i64", "call_f32", "call_f64",
        "call_bool", "call_ptr", "call_void",
    };
    for (size_t index = 0; index < sizeof(heads) / sizeof(heads[0]); ++index) {
        if (weave_si_head_equals(source, node, heads[index])) return 1;
    }
    return 0;
}

static int weave_si_call_head(
    const weave_si_source *source,
    int64_t node) {
    if (weave_si_wrapped_call_head(source, node)) return 1;
    int64_t head = node_first_child(source->tree, node);
    if (head < 0 || node_kind(source->tree, head) != node_ident()) return 0;
    int64_t start = node_text_start(source->tree, head);
    int64_t length = node_text_len(source->tree, head);
    if (start < 0 || length <= 0) return 0;
    return weave_surface_symbol_return_type(source->bytes, start, length) != 0;
}

static int weave_si_collect_calls_in_node(
    weave_si_model *model,
    size_t source_index,
    size_t caller_symbol_index,
    int64_t node) {
    weave_si_source *source = &model->sources[source_index];
    if (node < 0) return 1;
    if (node_kind(source->tree, node) == node_list() &&
        weave_si_call_head(source, node)) {
        int64_t target_node = weave_si_wrapped_call_head(source, node)
            ? weave_si_nth_child(source->tree, node, 1)
            : node_first_child(source->tree, node);
        size_t start = 0;
        size_t end = 0;
        if (target_node >= 0 &&
            weave_si_span(source, target_node, &start, &end)) {
            int64_t raw_start = node_text_start(source->tree, target_node);
            int64_t raw_length = node_text_len(source->tree, target_node);
            int32_t runtime_index = -1;
            if (raw_start >= 0 && raw_length >= 0) {
                runtime_index = weave_surface_symbol_resolve(
                    source->bytes, raw_start, raw_length);
            }
            int32_t resolution = weave_surface_symbol_resolution_status();
            size_t symbol_index = weave_si_symbol_from_runtime(
                model, runtime_index);
            const char *status = "unresolved";
            if (runtime_index >= 0 && symbol_index != WEAVE_SI_NONE) {
                status = "resolved";
            } else if (resolution == WEAVEC_SURFACE_RESOLUTION_AMBIGUOUS) {
                status = "ambiguous";
            } else if (resolution == WEAVEC_SURFACE_RESOLUTION_PRIVATE) {
                status = "private";
            } else if (resolution == WEAVEC_SURFACE_RESOLUTION_NOT_IMPORTED) {
                status = "not-imported";
            }
            weave_si_reference reference = {
                .source_index = source_index,
                .symbol_index = symbol_index,
                .start = start,
                .end = end,
                .role = "call",
                .status = status,
            };
            size_t reference_index = WEAVE_SI_NONE;
            if (!weave_si_add_reference(
                    model, &reference, &reference_index)) {
                return 0;
            }
            weave_si_call_edge edge = {
                .caller_symbol_index = caller_symbol_index,
                .callee_symbol_index = symbol_index,
                .reference_index = reference_index,
                .status = status,
            };
            if (!weave_si_add_call_edge(model, &edge)) return 0;
        }
    }
    if (node_kind(source->tree, node) == node_list()) {
        int64_t child = node_first_child(source->tree, node);
        while (child >= 0) {
            if (!weave_si_collect_calls_in_node(
                    model,
                    source_index,
                    caller_symbol_index,
                    child)) {
                return 0;
            }
            child = node_next_sibling(source->tree, child);
        }
    }
    return 1;
}

static int weave_si_collect_calls(weave_si_model *model) {
    for (size_t source_index = 0;
         source_index < model->source_count;
         ++source_index) {
        weave_si_source *source = &model->sources[source_index];
        weave_si_module *module = &model->modules[source->module_index];
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
        for (size_t symbol_index = 0;
             symbol_index < model->symbol_count;
             ++symbol_index) {
            weave_si_symbol *symbol = &model->symbols[symbol_index];
            if (symbol->source_index != source_index ||
                (strcmp(symbol->kind, "fn") != 0 &&
                 strcmp(symbol->kind, "entry") != 0)) {
                continue;
            }
            if (!weave_si_collect_calls_in_node(
                    model,
                    source_index,
                    symbol_index,
                    symbol->declaration_node)) {
                return 0;
            }
        }
    }
    return 1;
}

static int weave_si_compare_export_symbols(
    const void *left_pointer,
    const void *right_pointer,
    void *model_pointer) {
    const weave_si_model *model = (const weave_si_model *)model_pointer;
    size_t left_index = *(const size_t *)left_pointer;
    size_t right_index = *(const size_t *)right_pointer;
    const weave_si_symbol *left = &model->symbols[left_index];
    const weave_si_symbol *right = &model->symbols[right_index];
    int compare = strcmp(left->name, right->name);
    if (compare == 0) compare = strcmp(left->kind, right->kind);
    if (compare == 0) compare = strcmp(left->signature, right->signature);
    return compare;
}

static void weave_si_sort_exported_symbols(
    weave_si_model *model,
    weave_si_module *module) {
    for (size_t outer = 1; outer < module->exported_count; ++outer) {
        size_t value = module->exported_symbols[outer];
        size_t inner = outer;
        while (inner > 0 &&
               weave_si_compare_export_symbols(
                   &value,
                   &module->exported_symbols[inner - 1],
                   model) < 0) {
            module->exported_symbols[inner] =
                module->exported_symbols[inner - 1];
            --inner;
        }
        module->exported_symbols[inner] = value;
    }
}

static int weave_si_reference_compare(
    const weave_si_reference *left,
    const weave_si_reference *right) {
    if (left->source_index != right->source_index) {
        return left->source_index < right->source_index ? -1 : 1;
    }
    if (left->start != right->start) return left->start < right->start ? -1 : 1;
    if (left->end != right->end) return left->end < right->end ? -1 : 1;
    int role = strcmp(left->role, right->role);
    if (role != 0) return role;
    if (left->symbol_index == right->symbol_index) return 0;
    if (left->symbol_index == WEAVE_SI_NONE) return -1;
    if (right->symbol_index == WEAVE_SI_NONE) return 1;
    return left->symbol_index < right->symbol_index ? -1 : 1;
}

static int weave_si_sort_references(weave_si_model *model) {
    size_t count = model->reference_count;
    size_t *old_to_new = (size_t *)malloc(count * sizeof(*old_to_new));
    size_t *old_index = (size_t *)malloc(count * sizeof(*old_index));
    if ((count != 0 && old_to_new == NULL) ||
        (count != 0 && old_index == NULL)) {
        free(old_to_new);
        free(old_index);
        return 0;
    }
    for (size_t index = 0; index < count; ++index) old_index[index] = index;
    for (size_t outer = 1; outer < count; ++outer) {
        weave_si_reference value = model->references[outer];
        size_t value_old = old_index[outer];
        size_t inner = outer;
        while (inner > 0 &&
               weave_si_reference_compare(
                   &value, &model->references[inner - 1]) < 0) {
            model->references[inner] = model->references[inner - 1];
            old_index[inner] = old_index[inner - 1];
            --inner;
        }
        model->references[inner] = value;
        old_index[inner] = value_old;
    }
    for (size_t index = 0; index < count; ++index) {
        old_to_new[old_index[index]] = index;
    }
    for (size_t index = 0; index < model->call_edge_count; ++index) {
        size_t old = model->call_edges[index].reference_index;
        if (old >= count) {
            free(old_to_new);
            free(old_index);
            return 0;
        }
        model->call_edges[index].reference_index = old_to_new[old];
    }
    free(old_to_new);
    free(old_index);
    return 1;
}

static int weave_si_call_edge_compare(
    const weave_si_call_edge *left,
    const weave_si_call_edge *right) {
    if (left->caller_symbol_index != right->caller_symbol_index) {
        return left->caller_symbol_index < right->caller_symbol_index ? -1 : 1;
    }
    if (left->reference_index != right->reference_index) {
        return left->reference_index < right->reference_index ? -1 : 1;
    }
    if (left->callee_symbol_index == right->callee_symbol_index) return 0;
    if (left->callee_symbol_index == WEAVE_SI_NONE) return -1;
    if (right->callee_symbol_index == WEAVE_SI_NONE) return 1;
    return left->callee_symbol_index < right->callee_symbol_index ? -1 : 1;
}

static int weave_si_specialization_compare(
    const weave_si_specialization *left,
    const weave_si_specialization *right) {
    int kind = strcmp(left->kind, right->kind);
    if (kind != 0) return kind;
    int generic = strcmp(left->generic_name, right->generic_name);
    if (generic != 0) return generic;
    return strcmp(left->specialized_name, right->specialized_name);
}

static void weave_si_sort_specializations(weave_si_model *model) {
    for (size_t outer = 1; outer < model->specialization_count; ++outer) {
        weave_si_specialization value = model->specializations[outer];
        size_t inner = outer;
        while (inner > 0 &&
               weave_si_specialization_compare(
                   &value, &model->specializations[inner - 1]) < 0) {
            model->specializations[inner] = model->specializations[inner - 1];
            --inner;
        }
        model->specializations[inner] = value;
    }
}

static int weave_si_match_compare(
    const weave_si_match *left,
    const weave_si_match *right) {
    if (left->source_index != right->source_index) {
        return left->source_index < right->source_index ? -1 : 1;
    }
    if (left->start != right->start) {
        return left->start < right->start ? -1 : 1;
    }
    if (left->end == right->end) return 0;
    return left->end < right->end ? -1 : 1;
}

static void weave_si_sort_matches(weave_si_model *model) {
    for (size_t outer = 1; outer < model->match_count; ++outer) {
        weave_si_match value = model->matches[outer];
        size_t inner = outer;
        while (inner > 0 &&
               weave_si_match_compare(
                   &value, &model->matches[inner - 1]) < 0) {
            model->matches[inner] = model->matches[inner - 1];
            --inner;
        }
        model->matches[inner] = value;
    }
}

static void weave_si_sort_call_edges(weave_si_model *model) {
    for (size_t outer = 1; outer < model->call_edge_count; ++outer) {
        weave_si_call_edge value = model->call_edges[outer];
        size_t inner = outer;
        while (inner > 0 &&
               weave_si_call_edge_compare(
                   &value, &model->call_edges[inner - 1]) < 0) {
            model->call_edges[inner] = model->call_edges[inner - 1];
            --inner;
        }
        model->call_edges[inner] = value;
    }
}
