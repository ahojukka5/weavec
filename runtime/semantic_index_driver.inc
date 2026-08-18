static void weave_si_free_model(weave_si_model *model) {
    for (size_t index = 0; index < model->source_count; ++index) {
        if (model->sources[index].tree != NULL) {
            tree_free(model->sources[index].tree);
        }
        if (model->sources[index].tokens != NULL) {
            tokens_free(model->sources[index].tokens);
        }
        free(model->sources[index].bytes);
    }
    for (size_t index = 0; index < model->module_count; ++index) {
        free(model->modules[index].name);
        free(model->modules[index].exported_symbols);
    }
    for (size_t index = 0; index < model->symbol_count; ++index) {
        free(model->symbols[index].kind);
        free(model->symbols[index].name);
        free(model->symbols[index].signature);
        free(model->symbols[index].summary);
    }
    for (size_t index = 0; index < model->import_count; ++index) {
        free(model->imports[index].source_module);
        free(model->imports[index].imported_name);
    }
    for (size_t index = 0; index < model->export_count; ++index) {
        free(model->exports[index].name);
    }
    for (size_t index = 0; index < model->specialization_count; ++index) {
        free(model->specializations[index].kind);
        free(model->specializations[index].generic_name);
        free(model->specializations[index].specialized_name);
        if (model->specializations[index].arguments != NULL) {
            for (size_t arg = 0;
                 arg < model->specializations[index].argument_count;
                 ++arg) {
                free(model->specializations[index].arguments[arg]);
            }
            free(model->specializations[index].arguments);
        }
    }
    free(model->sources);
    free(model->modules);
    free(model->symbols);
    free(model->imports);
    free(model->exports);
    free(model->references);
    free(model->call_edges);
    free(model->specializations);
    free(model->matches);
    memset(model, 0, sizeof(*model));
}

static int weave_si_validate_frontend(
    int source_count,
    char **sources) {
    const char *tmp_root = getenv("TMPDIR");
    if (tmp_root == NULL || *tmp_root == '\0') tmp_root = "/tmp";
    char wir_path[PATH_MAX];
    if (snprintf(
            wir_path,
            sizeof(wir_path),
            "%s/weavec-semantic-index.XXXXXX",
            tmp_root) >= (int)sizeof(wir_path)) {
        return 1;
    }
    int fd = mkstemp(wir_path);
    if (fd < 0) return 1;
    close(fd);
    unlink(wir_path);
    char **frontend = (char **)calloc(
        (size_t)source_count + 4, sizeof(*frontend));
    if (frontend == NULL) return 1;
    frontend[0] = (char *)"weavec";
    frontend[1] = (char *)"--frontend";
    frontend[2] = wir_path;
    for (int index = 0; index < source_count; ++index) {
        frontend[3 + index] = sources[index];
    }
    int status = lower_sources(
        source_count + 3, frontend, wir_path, 3);
    unlink(wir_path);
    free(frontend);
    return status;
}

static int weave_si_load_sources(
    weave_si_model *model,
    int source_count,
    char **sources) {
    model->sources = (weave_si_source *)calloc(
        (size_t)source_count, sizeof(*model->sources));
    if (model->sources == NULL) return 0;
    model->source_count = (size_t)source_count;
    for (int index = 0; index < source_count; ++index) {
        weave_si_source *source = &model->sources[index];
        source->path = sources[index];
        source->module_index = WEAVE_SI_NONE;
        if (!weave_si_read_file(
                source->path, &source->bytes, &source->length)) {
            fprintf(
                stderr,
                "weavec: cannot read semantic-index source %s: %s\n",
                source->path,
                strerror(errno));
            return 0;
        }
        weave_si_sha256_bytes(
            source->bytes, source->length, source->sha256);
    }
    weave_si_compute_source_set_hash(model);
    for (int index = 0; index < source_count; ++index) {
        weave_si_source *source = &model->sources[index];
        source->tokens = lex(source->bytes, (int64_t)source->length);
        if (source->tokens == NULL) {
            model->diagnostic_source = (size_t)index;
            model->diagnostic_message = "source tokenization failed";
            return -1;
        }
        source->tree = parse(source->tokens);
        if (source->tree == NULL) {
            model->diagnostic_source = (size_t)index;
            model->diagnostic_message = "source parsing failed";
            return -1;
        }
    }
    return 1;
}

static int weave_si_build_model(weave_si_model *model) {
    for (size_t index = 0; index < model->source_count; ++index) {
        if (!weave_si_collect_source_declarations(model, index)) return 0;
    }
    if (!weave_si_resolve_interfaces(model)) return 0;
    if (!weave_si_collect_specializations(model)) return 0;
    if (!weave_si_collect_calls(model)) return 0;
    if (!weave_si_sort_references(model)) return 0;
    weave_si_sort_call_edges(model);
    weave_si_sort_specializations(model);
    weave_si_sort_matches(model);
    if (!weave_si_compute_interface_hashes(model)) return 0;
    return 1;
}

static void weave_si_clear_graph(weave_si_model *model) {
    for (size_t index = 0; index < model->module_count; ++index) {
        free(model->modules[index].name);
        free(model->modules[index].exported_symbols);
    }
    for (size_t index = 0; index < model->symbol_count; ++index) {
        free(model->symbols[index].kind);
        free(model->symbols[index].name);
        free(model->symbols[index].signature);
        free(model->symbols[index].summary);
    }
    for (size_t index = 0; index < model->import_count; ++index) {
        free(model->imports[index].source_module);
        free(model->imports[index].imported_name);
    }
    for (size_t index = 0; index < model->export_count; ++index) {
        free(model->exports[index].name);
    }
    for (size_t index = 0; index < model->specialization_count; ++index) {
        free(model->specializations[index].kind);
        free(model->specializations[index].generic_name);
        free(model->specializations[index].specialized_name);
        if (model->specializations[index].arguments != NULL) {
            for (size_t arg = 0;
                 arg < model->specializations[index].argument_count;
                 ++arg) {
                free(model->specializations[index].arguments[arg]);
            }
            free(model->specializations[index].arguments);
        }
    }
    free(model->modules);
    free(model->symbols);
    free(model->imports);
    free(model->exports);
    free(model->references);
    free(model->call_edges);
    free(model->specializations);
    free(model->matches);
    model->modules = NULL;
    model->symbols = NULL;
    model->imports = NULL;
    model->exports = NULL;
    model->references = NULL;
    model->call_edges = NULL;
    model->specializations = NULL;
    model->matches = NULL;
    model->module_count = model->module_capacity = 0;
    model->symbol_count = model->symbol_capacity = 0;
    model->import_count = model->import_capacity = 0;
    model->export_count = model->export_capacity = 0;
    model->reference_count = model->reference_capacity = 0;
    model->call_edge_count = model->call_edge_capacity = 0;
    model->specialization_count = model->specialization_capacity = 0;
    model->match_count = model->match_capacity = 0;
}

static void weave_si_usage(void) {
    fputs(
        "usage: weavec analyze <input.weave> [input2.weave ...] "
        "--semantic-index-json <index.json>\n",
        stderr);
}

int weave_rt_semantic_index_main(int argc, char **argv) {
    if (argc < 5 || strcmp(argv[1], "analyze") != 0 ||
        strcmp(argv[argc - 2], "--semantic-index-json") != 0 ||
        argv[argc - 1][0] == '\0') {
        weave_si_usage();
        return 2;
    }
    int source_count = argc - 4;
    char **sources = &argv[2];
    const char *output = argv[argc - 1];
    for (int index = 0; index < source_count; ++index) {
        if (strcmp(sources[index], output) == 0) {
            fputs(
                "weavec: semantic-index output must differ from every source\n",
                stderr);
            return 2;
        }
    }
    weave_si_model model;
    memset(&model, 0, sizeof(model));
    model.status = "failed";
    model.diagnostic_code = "WEAVEC-SEMANTIC-INDEX-FAILED";
    model.diagnostic_message = "semantic analysis failed";
    model.diagnostic_source = 0;
    model.diagnostic_start = 0;
    model.diagnostic_end = 0;
    int load_status = weave_si_load_sources(&model, source_count, sources);
    if (load_status == 0) {
        weave_si_free_model(&model);
        return 1;
    }
    int frontend_status = load_status > 0
        ? weave_si_validate_frontend(source_count, sources)
        : 1;
    if (frontend_status == 0 && weave_si_build_model(&model)) {
        model.status = "incomplete";
        model.diagnostic_code = NULL;
        model.diagnostic_message = NULL;
    } else {
        weave_si_clear_graph(&model);
    }
    int published = weave_si_publish(output, &model);
    int result = frontend_status == 0 &&
        strcmp(model.status, "failed") != 0 && published ? 0 : 1;
    weave_si_free_model(&model);
    return result;
}
