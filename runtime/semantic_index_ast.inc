static char *weave_si_copy(const char *value, size_t length) {
    if (value == NULL || length > SIZE_MAX - 1) {
        return NULL;
    }
    char *copy = (char *)malloc(length + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, value, length);
    copy[length] = '\0';
    return copy;
}

static int weave_si_grow(
    void **items,
    size_t *capacity,
    size_t count,
    size_t item_size) {
    if (count < *capacity) {
        return 1;
    }
    size_t next = *capacity == 0 ? 16 : *capacity * 2;
    if (next < *capacity || item_size > SIZE_MAX / next) {
        return 0;
    }
    void *grown = realloc(*items, next * item_size);
    if (grown == NULL) {
        return 0;
    }
    *items = grown;
    *capacity = next;
    return 1;
}

static int64_t weave_si_nth_child(void *tree, int64_t node, size_t ordinal) {
    int64_t child = node_first_child(tree, node);
    for (size_t index = 0; child >= 0 && index < ordinal; ++index) {
        child = node_next_sibling(tree, child);
    }
    return child;
}

static int weave_si_node_text_equals(
    const weave_si_source *source,
    int64_t node,
    const char *value) {
    if (node < 0 || node_kind(source->tree, node) != node_ident()) {
        return 0;
    }
    int64_t start = node_text_start(source->tree, node);
    int64_t length = node_text_len(source->tree, node);
    size_t expected = strlen(value);
    return start >= 0 && length >= 0 && (size_t)length == expected &&
        (size_t)start + expected <= source->length &&
        memcmp(source->bytes + start, value, expected) == 0;
}

static int weave_si_head_equals(
    const weave_si_source *source,
    int64_t node,
    const char *value) {
    return node >= 0 && node_kind(source->tree, node) == node_list() &&
        weave_si_node_text_equals(
            source, node_first_child(source->tree, node), value);
}

static int64_t weave_si_find_clause(
    const weave_si_source *source,
    int64_t declaration,
    const char *head) {
    int64_t child = node_first_child(source->tree, declaration);
    while (child >= 0) {
        if (weave_si_head_equals(source, child, head)) {
            return child;
        }
        child = node_next_sibling(source->tree, child);
    }
    return -1;
}

static size_t weave_si_form_end(
    const char *source,
    size_t length,
    size_t start,
    size_t fallback) {
    if (start >= length || source[start] != '(') {
        size_t end = start + fallback;
        return end > length ? length : end;
    }
    size_t depth = 0;
    int in_string = 0;
    int escaped = 0;
    int in_comment = 0;
    for (size_t index = start; index < length; ++index) {
        unsigned char ch = (unsigned char)source[index];
        if (in_comment) {
            if (ch == '\n') in_comment = 0;
            continue;
        }
        if (in_string) {
            if (escaped) escaped = 0;
            else if (ch == '\\') escaped = 1;
            else if (ch == '"') in_string = 0;
            continue;
        }
        if (ch == ';') in_comment = 1;
        else if (ch == '"') in_string = 1;
        else if (ch == '(') ++depth;
        else if (ch == ')') {
            if (depth == 0) break;
            --depth;
            if (depth == 0) return index + 1;
        }
    }
    return length;
}

static int weave_si_span(
    const weave_si_source *source,
    int64_t node,
    size_t *start,
    size_t *end) {
    if (node < 0) return 0;
    int64_t raw_start = node_text_start(source->tree, node);
    int64_t raw_length = node_text_len(source->tree, node);
    if (raw_start < 0 || raw_length < 0 ||
        (size_t)raw_start > source->length ||
        (size_t)raw_length > source->length - (size_t)raw_start) {
        return 0;
    }
    *start = (size_t)raw_start;
    *end = node_kind(source->tree, node) == node_list()
        ? weave_si_form_end(
              source->bytes,
              source->length,
              *start,
              (size_t)raw_length)
        : *start + (size_t)raw_length;
    return 1;
}

static char *weave_si_node_text(
    const weave_si_source *source,
    int64_t node) {
    if (node < 0) return NULL;
    int64_t start = node_text_start(source->tree, node);
    int64_t length = node_text_len(source->tree, node);
    if (start < 0 || length < 0 || (size_t)start > source->length ||
        (size_t)length > source->length - (size_t)start) {
        return NULL;
    }
    return weave_si_copy(source->bytes + start, (size_t)length);
}

static int weave_si_read_file(
    const char *path,
    char **bytes,
    size_t *length) {
    FILE *stream = fopen(path, "rb");
    if (stream == NULL) return 0;
    if (fseek(stream, 0, SEEK_END) != 0) {
        fclose(stream);
        return 0;
    }
    long size = ftell(stream);
    if (size < 0 || fseek(stream, 0, SEEK_SET) != 0) {
        fclose(stream);
        return 0;
    }
    char *data = (char *)malloc((size_t)size + 1);
    if (data == NULL) {
        fclose(stream);
        return 0;
    }
    size_t read_count = fread(data, 1, (size_t)size, stream);
    int ok = read_count == (size_t)size && fclose(stream) == 0;
    if (!ok) {
        free(data);
        return 0;
    }
    data[read_count] = '\0';
    *bytes = data;
    *length = read_count;
    return 1;
}

static int weave_si_add_module(
    weave_si_model *model,
    const weave_si_module *module,
    size_t *index) {
    if (!weave_si_grow(
            (void **)&model->modules,
            &model->module_capacity,
            model->module_count,
            sizeof(*model->modules))) {
        return 0;
    }
    *index = model->module_count;
    model->modules[model->module_count++] = *module;
    return 1;
}

static int weave_si_add_symbol(
    weave_si_model *model,
    const weave_si_symbol *symbol,
    size_t *index) {
    if (!weave_si_grow(
            (void **)&model->symbols,
            &model->symbol_capacity,
            model->symbol_count,
            sizeof(*model->symbols))) {
        return 0;
    }
    *index = model->symbol_count;
    model->symbols[model->symbol_count++] = *symbol;
    return 1;
}

static int weave_si_add_import(
    weave_si_model *model,
    const weave_si_import *item) {
    if (!weave_si_grow(
            (void **)&model->imports,
            &model->import_capacity,
            model->import_count,
            sizeof(*model->imports))) {
        return 0;
    }
    model->imports[model->import_count++] = *item;
    return 1;
}

static int weave_si_add_export(
    weave_si_model *model,
    const weave_si_export *item) {
    if (!weave_si_grow(
            (void **)&model->exports,
            &model->export_capacity,
            model->export_count,
            sizeof(*model->exports))) {
        return 0;
    }
    model->exports[model->export_count++] = *item;
    return 1;
}

static int weave_si_add_reference(
    weave_si_model *model,
    const weave_si_reference *item,
    size_t *index) {
    if (!weave_si_grow(
            (void **)&model->references,
            &model->reference_capacity,
            model->reference_count,
            sizeof(*model->references))) {
        return 0;
    }
    *index = model->reference_count;
    model->references[model->reference_count++] = *item;
    return 1;
}

static int weave_si_add_call_edge(
    weave_si_model *model,
    const weave_si_call_edge *item) {
    if (!weave_si_grow(
            (void **)&model->call_edges,
            &model->call_edge_capacity,
            model->call_edge_count,
            sizeof(*model->call_edges))) {
        return 0;
    }
    model->call_edges[model->call_edge_count++] = *item;
    return 1;
}

static size_t weave_si_find_module(
    const weave_si_model *model,
    const char *name) {
    for (size_t index = 0; index < model->module_count; ++index) {
        if (strcmp(model->modules[index].name, name) == 0) return index;
    }
    return WEAVE_SI_NONE;
}

static size_t weave_si_find_symbol(
    const weave_si_model *model,
    size_t module_index,
    const char *name) {
    for (size_t index = 0; index < model->symbol_count; ++index) {
        const weave_si_symbol *symbol = &model->symbols[index];
        if (symbol->module_index == module_index &&
            strcmp(symbol->name, name) == 0) {
            return index;
        }
    }
    return WEAVE_SI_NONE;
}

static int weave_si_is_exported(
    const weave_si_model *model,
    size_t module_index,
    const char *name) {
    for (size_t index = 0; index < model->export_count; ++index) {
        if (model->exports[index].module_index == module_index &&
            strcmp(model->exports[index].name, name) == 0) {
            return 1;
        }
    }
    return 0;
}

static char *weave_si_signature_callable(
    const weave_si_source *source,
    const char *kind,
    int64_t declaration,
    char **summary_out) {
    int64_t type_params = weave_si_find_clause(source, declaration, "type-params");
    int64_t params = weave_si_find_clause(source, declaration, "params");
    int64_t returns = weave_si_find_clause(source, declaration, "returns");
    weave_si_buffer canonical;
    weave_si_buffer summary;
    weave_si_buffer_init(&canonical);
    weave_si_buffer_init(&summary);
    weave_si_buffer_char(&canonical, '(');
    weave_si_buffer_cstr(&canonical, kind);
    if (type_params >= 0) {
        weave_si_buffer_cstr(&canonical, " (type-params");
        int64_t parameter = node_next_sibling(
            source->tree, node_first_child(source->tree, type_params));
        while (parameter >= 0) {
            char *name = weave_si_node_text(source, parameter);
            if (name != NULL) {
                weave_si_buffer_char(&canonical, ' ');
                weave_si_buffer_cstr(&canonical, name);
                free(name);
            }
            parameter = node_next_sibling(source->tree, parameter);
        }
        weave_si_buffer_char(&canonical, ')');
    }
    weave_si_buffer_cstr(&canonical, " (params");
    weave_si_buffer_char(&summary, '(');
    if (params >= 0 && weave_si_head_equals(source, params, "params")) {
        int64_t parameter = node_next_sibling(
            source->tree, node_first_child(source->tree, params));
        int first = 1;
        while (parameter >= 0) {
            if (node_kind(source->tree, parameter) == node_list()) {
                int64_t name_node = weave_si_nth_child(
                    source->tree, parameter, 0);
                int64_t type_node = weave_si_nth_child(
                    source->tree, parameter, 1);
                char *name = weave_si_node_text(source, name_node);
                char *type = weave_si_node_text(source, type_node);
                if (name != NULL && type != NULL) {
                    weave_si_buffer_cstr(&canonical, " (");
                    weave_si_buffer_cstr(&canonical, name);
                    weave_si_buffer_char(&canonical, ' ');
                    weave_si_buffer_cstr(&canonical, type);
                    weave_si_buffer_char(&canonical, ')');
                    if (!first) weave_si_buffer_cstr(&summary, ", ");
                    weave_si_buffer_cstr(&summary, name);
                    weave_si_buffer_char(&summary, ' ');
                    weave_si_buffer_cstr(&summary, type);
                    first = 0;
                }
                free(name);
                free(type);
            }
            parameter = node_next_sibling(source->tree, parameter);
        }
    }
    weave_si_buffer_cstr(&canonical, ") (returns ");
    char *return_type = NULL;
    if (returns >= 0 && weave_si_head_equals(source, returns, "returns")) {
        return_type = weave_si_node_text(
            source, weave_si_nth_child(source->tree, returns, 1));
    }
    if (return_type == NULL) return_type = weave_si_copy("unknown", 7);
    weave_si_buffer_cstr(&canonical, return_type != NULL ? return_type : "unknown");
    weave_si_buffer_cstr(&canonical, "))");
    weave_si_buffer_cstr(&summary, ") -> ");
    weave_si_buffer_cstr(&summary, return_type != NULL ? return_type : "unknown");
    free(return_type);
    if (canonical.failed || summary.failed) {
        free(canonical.data);
        free(summary.data);
        return NULL;
    }
    *summary_out = summary.data;
    return canonical.data;
}

static char *weave_si_signature_const(
    const weave_si_source *source,
    int64_t declaration,
    char **summary_out) {
    char *type = weave_si_node_text(
        source, weave_si_nth_child(source->tree, declaration, 2));
    if (type == NULL) type = weave_si_copy("unknown", 7);
    weave_si_buffer canonical;
    weave_si_buffer_init(&canonical);
    weave_si_buffer_cstr(&canonical, "(const ");
    weave_si_buffer_cstr(&canonical, type != NULL ? type : "unknown");
    weave_si_buffer_char(&canonical, ')');
    *summary_out = type != NULL ? weave_si_copy(type, strlen(type)) : NULL;
    free(type);
    return canonical.failed ? (free(canonical.data), (char *)NULL) : canonical.data;
}

static char *weave_si_signature_struct(
    const weave_si_source *source,
    int64_t declaration,
    char **summary_out) {
    weave_si_buffer canonical;
    weave_si_buffer summary;
    weave_si_buffer_init(&canonical);
    weave_si_buffer_init(&summary);
    weave_si_buffer_cstr(&canonical, "(struct");
    int64_t struct_params = weave_si_find_clause(
        source, declaration, "type-params");
    if (struct_params >= 0) {
        weave_si_buffer_cstr(&canonical, " (type-params");
        int64_t parameter = node_next_sibling(
            source->tree, node_first_child(source->tree, struct_params));
        while (parameter >= 0) {
            char *name = weave_si_node_text(source, parameter);
            if (name != NULL) {
                weave_si_buffer_char(&canonical, ' ');
                weave_si_buffer_cstr(&canonical, name);
                free(name);
            }
            parameter = node_next_sibling(source->tree, parameter);
        }
        weave_si_buffer_char(&canonical, ')');
    }
    weave_si_buffer_char(&summary, '{');
    int64_t field = node_next_sibling(
        source->tree,
        weave_si_nth_child(source->tree, declaration, 1));
    int first = 1;
    while (field >= 0) {
        if (weave_si_head_equals(source, field, "field")) {
            char *name = weave_si_node_text(
                source, weave_si_nth_child(source->tree, field, 1));
            char *type = weave_si_node_text(
                source, weave_si_nth_child(source->tree, field, 2));
            if (name != NULL && type != NULL) {
                weave_si_buffer_cstr(&canonical, " (field ");
                weave_si_buffer_cstr(&canonical, name);
                weave_si_buffer_char(&canonical, ' ');
                weave_si_buffer_cstr(&canonical, type);
                weave_si_buffer_char(&canonical, ')');
                if (!first) weave_si_buffer_cstr(&summary, ", ");
                weave_si_buffer_cstr(&summary, name);
                weave_si_buffer_cstr(&summary, ": ");
                weave_si_buffer_cstr(&summary, type);
                first = 0;
            }
            free(name);
            free(type);
        }
        field = node_next_sibling(source->tree, field);
    }
    weave_si_buffer_char(&canonical, ')');
    weave_si_buffer_char(&summary, '}');
    if (canonical.failed || summary.failed) {
        free(canonical.data);
        free(summary.data);
        return NULL;
    }
    *summary_out = summary.data;
    return canonical.data;
}

static char *weave_si_signature_field(
    const char *structure,
    const char *type,
    char **summary_out) {
    weave_si_buffer canonical;
    weave_si_buffer summary;
    weave_si_buffer_init(&canonical);
    weave_si_buffer_init(&summary);
    weave_si_buffer_cstr(&canonical, "(field ");
    weave_si_buffer_cstr(&canonical, structure);
    weave_si_buffer_char(&canonical, ' ');
    weave_si_buffer_cstr(&canonical, type);
    weave_si_buffer_char(&canonical, ')');
    weave_si_buffer_cstr(&summary, structure);
    weave_si_buffer_cstr(&summary, ".field: ");
    weave_si_buffer_cstr(&summary, type);
    if (canonical.failed || summary.failed) {
        free(canonical.data);
        free(summary.data);
        return NULL;
    }
    *summary_out = summary.data;
    return canonical.data;
}

static int weave_si_collect_symbol(
    weave_si_model *model,
    size_t source_index,
    size_t module_index,
    int64_t declaration,
    const char *kind,
    int is_callable) {
    weave_si_source *source = &model->sources[source_index];
    int64_t name_node = weave_si_nth_child(source->tree, declaration, 1);
    char *name = weave_si_node_text(source, name_node);
    size_t start = 0;
    size_t end = 0;
    if (name == NULL || !weave_si_span(source, declaration, &start, &end)) {
        free(name);
        return 0;
    }
    char *summary = NULL;
    char *signature = is_callable
        ? weave_si_signature_callable(source, kind, declaration, &summary)
        : strcmp(kind, "const") == 0
            ? weave_si_signature_const(source, declaration, &summary)
            : weave_si_signature_struct(source, declaration, &summary);
    if (signature == NULL || summary == NULL) {
        free(name);
        free(signature);
        free(summary);
        return 0;
    }
    weave_si_symbol symbol = {
        .module_index = module_index,
        .source_index = source_index,
        .kind = weave_si_copy(kind, strlen(kind)),
        .name = name,
        .signature = signature,
        .summary = summary,
        .start = start,
        .end = end,
        .is_public = strcmp(kind, "entry") == 0 || strcmp(kind, "extern") == 0,
        .is_callable = is_callable,
        .declaration_node = declaration,
    };
    if (symbol.kind == NULL) {
        free(symbol.name);
        free(symbol.signature);
        free(symbol.summary);
        return 0;
    }
    size_t symbol_index = WEAVE_SI_NONE;
    if (!weave_si_add_symbol(model, &symbol, &symbol_index)) {
        free(symbol.kind);
        free(symbol.name);
        free(symbol.signature);
        free(symbol.summary);
        return 0;
    }
    if (strcmp(kind, "struct") == 0) {
        int64_t field = node_next_sibling(source->tree, name_node);
        while (field >= 0) {
            if (weave_si_head_equals(source, field, "field")) {
                int64_t field_name_node = weave_si_nth_child(
                    source->tree, field, 1);
                int64_t type_node = weave_si_nth_child(
                    source->tree, field, 2);
                char *field_name = weave_si_node_text(source, field_name_node);
                char *field_type = weave_si_node_text(source, type_node);
                size_t field_start = 0;
                size_t field_end = 0;
                if (field_name == NULL || field_type == NULL ||
                    !weave_si_span(source, field, &field_start, &field_end)) {
                    free(field_name);
                    free(field_type);
                    return 0;
                }
                char *field_summary = NULL;
                char *field_signature = weave_si_signature_field(
                    name, field_type, &field_summary);
                free(field_type);
                weave_si_symbol field_symbol = {
                    .module_index = module_index,
                    .source_index = source_index,
                    .kind = weave_si_copy("field", 5),
                    .name = field_name,
                    .signature = field_signature,
                    .summary = field_summary,
                    .start = field_start,
                    .end = field_end,
                    .is_public = 0,
                    .is_callable = 0,
                    .declaration_node = field,
                };
                size_t ignored = WEAVE_SI_NONE;
                if (field_symbol.kind == NULL ||
                    field_symbol.signature == NULL ||
                    field_symbol.summary == NULL ||
                    !weave_si_add_symbol(model, &field_symbol, &ignored)) {
                    free(field_symbol.kind);
                    free(field_symbol.name);
                    free(field_symbol.signature);
                    free(field_symbol.summary);
                    return 0;
                }
            }
            field = node_next_sibling(source->tree, field);
        }
    }
    return 1;
}
