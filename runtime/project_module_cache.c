// SPDX-License-Identifier: Apache-2.0
//
// Interface-hash incremental compilation for executable projects. The complete
// source set is validated first, then one WIR/object unit is built per module and
// reused only when implementation and imported-interface keys match exactly.

#ifndef WEAVEC_PROJECT_MODULE_CACHE_C
#define WEAVEC_PROJECT_MODULE_CACHE_C

#define WEAVE_PROJECT_MODULE_CACHE_FORMAT "weavec-project-module-cache-v1"

typedef struct weave_project_module_config {
    const char *target;
    const char *runtime_override;
    const char *optimizer;
    const char *codegen;
    const char *linker;
    const char *objdump;
    const char *optimization;
    const char *cpu;
    const char *tune_cpu;
} weave_project_module_config;

typedef struct weave_project_module_decision {
    const char *name;
    const char *logical_path;
    char interface_sha256[65];
    char key[65];
    char object[PATH_MAX];
    const char *decision;
    const char *reason;
} weave_project_module_decision;

static int weave_project_module_parse_config(
    const weave_project_cache_options *options,
    weave_project_module_config *config) {
    config->target = WEAVEC_DEFAULT_TARGET;
    config->runtime_override = NULL;
    config->optimizer = getenv("WEAVEC_OPTIMIZER");
    if (config->optimizer == NULL || *config->optimizer == '\0') {
        config->optimizer = getenv("WEAVEC_CODEGEN");
    }
    config->codegen = getenv("WEAVEC_TARGET_CODEGEN");
    if (config->codegen == NULL || *config->codegen == '\0') {
        config->codegen = getenv("WEAVEC_LLC");
    }
    config->linker = getenv("WEAVEC_LINKER");
    config->objdump = getenv("WEAVEC_OBJDUMP");
    config->optimization = "-O2";
    config->cpu = NULL;
    config->tune_cpu = NULL;
    if (config->optimizer == NULL || *config->optimizer == '\0') {
        config->optimizer = WEAVEC_DEFAULT_OPTIMIZER;
    }
    if (config->codegen == NULL || *config->codegen == '\0') {
        config->codegen = WEAVEC_DEFAULT_CODEGEN;
    }
    if (config->linker == NULL || *config->linker == '\0') {
        config->linker = WEAVEC_DEFAULT_LINKER;
    }
    if (config->objdump == NULL || *config->objdump == '\0') {
        config->objdump = WEAVEC_DEFAULT_OBJDUMP;
    }

    for (int i = 2; i < options->argc; ++i) {
        const char *argument = options->argv[i];
        if (strcmp(argument, "--project") == 0 ||
            strcmp(argument, "-o") == 0 ||
            strcmp(argument, "--output") == 0) {
            if (++i >= options->argc) return 0;
        } else if (strncmp(argument, "--project=", 10) == 0 ||
                   strncmp(argument, "--output=", 9) == 0) {
            continue;
        } else if (strcmp(argument, "--target") == 0) {
            if (++i >= options->argc) return 0;
            config->target = options->argv[i];
        } else if (strcmp(argument, "--runtime") == 0) {
            if (++i >= options->argc) return 0;
            config->runtime_override = options->argv[i];
        } else if (strcmp(argument, "--optimizer") == 0 ||
                   strcmp(argument, "--codegen") == 0) {
            if (++i >= options->argc) return 0;
            config->optimizer = options->argv[i];
        } else if (strcmp(argument, "--target-codegen") == 0 ||
                   strcmp(argument, "--llc") == 0) {
            if (++i >= options->argc) return 0;
            config->codegen = options->argv[i];
        } else if (strcmp(argument, "--linker") == 0) {
            if (++i >= options->argc) return 0;
            config->linker = options->argv[i];
        } else if (strcmp(argument, "--objdump") == 0) {
            if (++i >= options->argc) return 0;
            config->objdump = options->argv[i];
        } else if (strcmp(argument, "--cpu") == 0 ||
                   strcmp(argument, "--march") == 0) {
            if (++i >= options->argc) return 0;
            config->cpu = options->argv[i];
        } else if (strncmp(argument, "--march=", 8) == 0) {
            config->cpu = argument + 8;
        } else if (strcmp(argument, "--tune-cpu") == 0 ||
                   strcmp(argument, "--mtune") == 0) {
            if (++i >= options->argc) return 0;
            config->tune_cpu = options->argv[i];
        } else if (strncmp(argument, "--mtune=", 8) == 0) {
            config->tune_cpu = argument + 8;
        } else if (strcmp(argument, "--native") == 0) {
            config->cpu = "native";
            config->tune_cpu = "native";
        } else if (optimization_option(argument)) {
            config->optimization = argument;
        } else if (strcmp(argument, "--keep-temporaries") == 0 ||
                   strcmp(argument, "--strict-contracts") == 0) {
            continue;
        } else if (argument[0] == '-') {
            return 0;
        }
    }
    return config->target != NULL && *config->target != '\0' &&
        config->optimizer != NULL && *config->optimizer != '\0' &&
        config->codegen != NULL && *config->codegen != '\0' &&
        config->linker != NULL && *config->linker != '\0' &&
        (config->cpu == NULL || *config->cpu != '\0') &&
        (config->tune_cpu == NULL || *config->tune_cpu != '\0');
}

static weave_si_module *weave_project_module_model_find(
    weave_si_model *model,
    const char *name) {
    for (size_t i = 0; i < model->module_count; ++i) {
        if (strcmp(model->modules[i].name, name) == 0) {
            return &model->modules[i];
        }
    }
    return NULL;
}

static int weave_project_module_validate(
    const weave_project_source_registry *registry,
    const weave_project_graph *graph,
    weave_si_model *model,
    char ***ordered_sources_out) {
    char **sources = calloc(graph->order_count, sizeof(*sources));
    if (sources == NULL) return 0;
    for (size_t i = 0; i < graph->order_count; ++i) {
        sources[i] = registry->items[graph->order[i]].physical_path;
    }

    memset(model, 0, sizeof(*model));
    model->status = "failed";
    model->diagnostic_code = "WEAVEC-SEMANTIC-INDEX-FAILED";
    model->diagnostic_message = "semantic analysis failed";
    int loaded = weave_si_load_sources(
        model, (int)graph->order_count, sources);
    int valid = loaded > 0 &&
        weave_si_validate_frontend((int)graph->order_count, sources) == 0 &&
        weave_si_build_model(model);
    if (!valid) {
        weave_si_free_model(model);
        free(sources);
        return 0;
    }
    *ordered_sources_out = sources;
    return 1;
}

static void weave_project_module_hash_optional(
    weave_si_sha256 *hash,
    const char *name,
    const char *value) {
    const char *actual = value != NULL ? value : "";
    weave_project_cache_hash_field(
        hash, name, actual, strlen(actual));
}

static int weave_project_module_key(
    const weave_project_manifest *manifest,
    const weave_project_source_registry *registry,
    const weave_project_graph *graph,
    weave_si_model *model,
    size_t registry_index,
    const weave_project_module_config *config,
    const char *runtime,
    char output[65]) {
    const weave_project_source *source = &registry->items[registry_index];
    weave_si_module *module = weave_project_module_model_find(
        model, source->module_name);
    if (module == NULL) return 0;

    weave_si_sha256 hash;
    weave_si_sha256_init(&hash);
    weave_project_cache_hash_field(
        &hash, "format", WEAVE_PROJECT_MODULE_CACHE_FORMAT,
        strlen(WEAVE_PROJECT_MODULE_CACHE_FORMAT));
    weave_project_module_hash_optional(
        &hash, "compiler-version", weave_compiler_version);
    weave_project_module_hash_optional(&hash, "target", config->target);
    weave_project_module_hash_optional(
        &hash, "optimizer", config->optimizer);
    weave_project_module_hash_optional(&hash, "codegen", config->codegen);
    weave_project_module_hash_optional(&hash, "linker", config->linker);
    weave_project_module_hash_optional(
        &hash, "optimization", config->optimization);
    weave_project_module_hash_optional(&hash, "cpu", config->cpu);
    weave_project_module_hash_optional(
        &hash, "tune-cpu", config->tune_cpu);
    weave_project_cache_hash_field(
        &hash, "project-kind", manifest->kind, strlen(manifest->kind));
    weave_project_cache_hash_field(
        &hash, "module", source->module_name,
        strlen(source->module_name));
    weave_project_cache_hash_field(
        &hash, "logical-path", source->logical_path,
        strlen(source->logical_path));
    weave_project_cache_hash_field(
        &hash, "interface-sha256", module->interface_sha256, 64);
    if (!weave_project_cache_hash_file(
            &hash, "source", source->physical_path)) {
        return 0;
    }
    if (!weave_project_cache_hash_file(&hash, "runtime", runtime)) {
        return 0;
    }

    const weave_project_graph_node *node = &graph->nodes[registry_index];
    for (size_t edge_index = 0;
         edge_index < node->edge_count;
         ++edge_index) {
        size_t target = node->edges[edge_index].target;
        const char *target_name = registry->items[target].module_name;
        weave_si_module *imported = weave_project_module_model_find(
            model, target_name);
        if (imported == NULL) return 0;
        weave_project_cache_hash_field(
            &hash, "import-module", target_name, strlen(target_name));
        weave_project_cache_hash_field(
            &hash, "import-interface-sha256",
            imported->interface_sha256, 64);
    }

    unsigned char digest[32];
    weave_si_sha256_finish(&hash, digest);
    weave_si_hex(digest, output);
    return 1;
}

static int weave_project_module_temp_path(
    const char *directory,
    size_t position,
    const char *suffix,
    char output[PATH_MAX]) {
    return snprintf(
        output, PATH_MAX, "%s/module-%04zu.%s",
        directory, position, suffix) < PATH_MAX;
}

static int weave_project_module_emit_wir(
    const char *compiler,
    char **sources,
    size_t source_count,
    size_t selected_position,
    const char *wir_path) {
    char selected[32];
    if (snprintf(
            selected, sizeof(selected), "%zu",
            selected_position) >= (int)sizeof(selected)) {
        return 1;
    }
    char **frontend = calloc(source_count + 4, sizeof(*frontend));
    if (frontend == NULL) return 1;
    frontend[0] = (char *)compiler;
    frontend[1] = (char *)"--frontend";
    frontend[2] = (char *)wir_path;
    for (size_t i = 0; i < source_count; ++i) {
        frontend[3 + i] = sources[i];
    }
    frontend[3 + source_count] = NULL;

    const char *existing = getenv(WEAVE_PROJECT_BODY_SOURCE_ENV);
    char *saved = existing != NULL ? strdup(existing) : NULL;
    (void)setenv(WEAVE_PROJECT_BODY_SOURCE_ENV, selected, 1);
    int result = lower_sources(
        (int32_t)(source_count + 3), frontend,
        wir_path, 3);
    if (saved != NULL) {
        (void)setenv(WEAVE_PROJECT_BODY_SOURCE_ENV, saved, 1);
    } else {
        (void)unsetenv(WEAVE_PROJECT_BODY_SOURCE_ENV);
    }
    free(saved);
    free(frontend);
    return result;
}

static int weave_project_module_compile(
    const char *compiler,
    char **sources,
    size_t source_count,
    size_t selected_position,
    const weave_project_module_config *config,
    const char *directory,
    const char *object_path) {
    char wir[PATH_MAX];
    char raw_llvm[PATH_MAX];
    char optimized_llvm[PATH_MAX];
    if (!weave_project_module_temp_path(
            directory, selected_position, "wir", wir) ||
        !weave_project_module_temp_path(
            directory, selected_position, "ll", raw_llvm) ||
        !weave_project_module_temp_path(
            directory, selected_position, "optimized.ll", optimized_llvm)) {
        return 1;
    }
    unlink(wir);
    unlink(raw_llvm);
    unlink(optimized_llvm);
    unlink(object_path);

    int status = weave_project_module_emit_wir(
        compiler, sources, source_count,
        selected_position, wir);
    if (status != 0) return status;

    char *backend[] = {
        (char *)compiler,
        (char *)"--backend",
        wir,
        raw_llvm,
        NULL,
    };
    status = weave_run_process(backend);
    if (status != 0) return status;

    weave_llvm_config llvm = {
        .optimizer = config->optimizer,
        .codegen = config->codegen,
        .objdump = config->objdump,
        .optimization = config->optimization,
        .cpu = config->cpu,
        .tune_cpu = config->tune_cpu,
    };
    status = weave_llvm_optimize_ir(
        &llvm, raw_llvm, optimized_llvm, NULL);
    if (status != 0) return status;
    return weave_llvm_emit_object(
        &llvm, optimized_llvm, object_path, NULL);
}

static int weave_project_module_link(
    const weave_project_module_config *config,
    const char *runtime,
    const char *output,
    weave_project_module_decision *decisions,
    size_t count) {
    char temporary[PATH_MAX];
    if (snprintf(
            temporary, sizeof(temporary),
            "%s.tmp.XXXXXX", output) >= (int)sizeof(temporary)) {
        return 1;
    }
    int descriptor = mkstemp(temporary);
    if (descriptor < 0) return 1;
    close(descriptor);
    unlink(temporary);

    size_t capacity = count + 10;
    char **arguments = calloc(capacity, sizeof(*arguments));
    if (arguments == NULL) return 1;
    size_t used = 0;
    arguments[used++] = (char *)config->linker;
    arguments[used++] = (char *)"-ffunction-sections";
    arguments[used++] = (char *)"-fdata-sections";
    for (size_t i = 0; i < count; ++i) {
        arguments[used++] = decisions[i].object;
    }
    arguments[used++] = (char *)runtime;
    arguments[used++] = (char *)WEAVEC_LINK_DEAD_STRIP;
    arguments[used++] = (char *)"-o";
    arguments[used++] = temporary;
    arguments[used] = NULL;

    int status = weave_run_process(arguments);
    free(arguments);
    if (status != 0) {
        unlink(temporary);
        return status;
    }
    if (rename(temporary, output) != 0) {
        unlink(temporary);
        return 1;
    }
    return 0;
}

static int weave_project_module_write_report(
    const char *path,
    const char *cache_root,
    int exit_code,
    weave_project_module_decision *decisions,
    size_t count) {
    if (path == NULL) return 1;
    char temporary[PATH_MAX];
    if (snprintf(
            temporary, sizeof(temporary),
            "%s.tmp-XXXXXX", path) >= (int)sizeof(temporary)) {
        return 0;
    }
    int descriptor = mkstemp(temporary);
    if (descriptor < 0) return 0;
    FILE *stream = fdopen(descriptor, "wb");
    if (stream == NULL) {
        close(descriptor);
        unlink(temporary);
        return 0;
    }
    int ok = fputs("{\"format\":", stream) >= 0 &&
        weave_project_cache_json_string(
            stream, WEAVE_PROJECT_MODULE_CACHE_FORMAT) &&
        fputs(",\"status\":", stream) >= 0 &&
        weave_project_cache_json_string(
            stream, exit_code == 0 ? "succeeded" : "failed") &&
        fputs(",\"cache_dir\":", stream) >= 0 &&
        weave_project_cache_json_string(stream, cache_root) &&
        fprintf(stream, ",\"exit_code\":%d,\"modules\":[", exit_code) >= 0;
    for (size_t i = 0; ok && i < count; ++i) {
        if (i > 0 && fputc(',', stream) == EOF) ok = 0;
        ok = ok && fputs("{\"name\":", stream) >= 0 &&
            weave_project_cache_json_string(stream, decisions[i].name) &&
            fputs(",\"source\":", stream) >= 0 &&
            weave_project_cache_json_string(
                stream, decisions[i].logical_path) &&
            fputs(",\"interface_sha256\":", stream) >= 0 &&
            weave_project_cache_json_string(
                stream, decisions[i].interface_sha256) &&
            fputs(",\"key\":", stream) >= 0 &&
            weave_project_cache_json_string(stream, decisions[i].key) &&
            fputs(",\"decision\":", stream) >= 0 &&
            weave_project_cache_json_string(
                stream, decisions[i].decision) &&
            fputs(",\"reason\":", stream) >= 0 &&
            weave_project_cache_json_string(
                stream, decisions[i].reason) &&
            fputc('}', stream) != EOF;
    }
    ok = ok && fputs("]}\n", stream) >= 0;
    if (ok && fflush(stream) != 0) ok = 0;
    if (ok && fsync(fileno(stream)) != 0) ok = 0;
    if (fclose(stream) != 0) ok = 0;
    if (ok && rename(temporary, path) != 0) ok = 0;
    if (!ok) unlink(temporary);
    return ok;
}

static void weave_project_module_cleanup_directory(
    const char *directory,
    size_t count) {
    for (size_t i = 0; i < count; ++i) {
        char path[PATH_MAX];
        if (weave_project_module_temp_path(directory, i, "wir", path)) {
            unlink(path);
        }
        if (weave_project_module_temp_path(directory, i, "ll", path)) {
            unlink(path);
        }
        if (weave_project_module_temp_path(
                directory, i, "optimized.ll", path)) {
            unlink(path);
        }
        if (weave_project_module_temp_path(directory, i, "o", path)) {
            unlink(path);
        }
    }
    rmdir(directory);
}

static int weave_project_module_build(
    int original_argc,
    char **original_argv,
    weave_project_cache_options *options) {
    weave_project_request request = {0};
    weave_project_error request_error = {0};
    if (!weave_project_parse_request(
            options->argc, options->argv,
            &request, &request_error) ||
        request.help || request.unknown_option != NULL ||
        request.source_count > 0 ||
        weave_project_cache_extra_outputs(&request, options)) {
        free(request.output_paths);
        return weave_rt_build_main_project_module_legacy(
            original_argc, original_argv);
    }

    weave_project_manifest manifest = {0};
    weave_project_error manifest_error = {0};
    if (!weave_project_load(
            request.project, &manifest, &manifest_error) ||
        strcmp(manifest.kind, "executable") != 0) {
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return weave_rt_build_main_project_module_legacy(
            original_argc, original_argv);
    }

    weave_project_source_registry registry = {0};
    weave_project_source_error source_error = {0};
    weave_project_graph graph = {0};
    int prepared = weave_project_discover_sources(
        &request, &manifest, &registry, &source_error);
    if (prepared) {
        prepared = weave_project_graph_build(
            &manifest, &registry, &graph, &source_error);
    }
    char output[PATH_MAX] = {0};
    if (prepared) {
        prepared = weave_project_resolve_output(
            &request, &manifest, output,
            sizeof(output), &source_error);
    }
    if (!prepared ||
        !weave_project_cache_safe_output(
            &manifest, &registry, output) ||
        !weave_project_cache_safe_report(
            options, &manifest, &registry, output)) {
        weave_project_graph_clear(&graph);
        weave_project_source_registry_clear(&registry);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return weave_rt_build_main_project_module_legacy(
            original_argc, original_argv);
    }

    weave_project_module_config config = {0};
    if (!weave_project_module_parse_config(options, &config) ||
        strcmp(config.target, WEAVEC_DEFAULT_TARGET) != 0) {
        weave_project_graph_clear(&graph);
        weave_project_source_registry_clear(&registry);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return weave_rt_build_main_project_module_legacy(
            original_argc, original_argv);
    }

    char compiler[PATH_MAX];
    char runtime[PATH_MAX];
    if (!resolve_executable(
            options->argv[0], compiler, sizeof(compiler)) ||
        !locate_runtime(
            config.runtime_override, compiler, config.target,
            runtime, sizeof(runtime))) {
        weave_project_graph_clear(&graph);
        weave_project_source_registry_clear(&registry);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return weave_rt_build_main_project_module_legacy(
            original_argc, original_argv);
    }

    weave_si_model model;
    char **ordered_sources = NULL;
    if (!weave_project_module_validate(
            &registry, &graph, &model, &ordered_sources)) {
        weave_project_graph_clear(&graph);
        weave_project_source_registry_clear(&registry);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return weave_rt_build_main_project_module_legacy(
            original_argc, original_argv);
    }

    char cache_root[PATH_MAX];
    char module_root[PATH_MAX];
    int cache_ready = weave_project_cache_resolve_root(
            options, &manifest, cache_root) &&
        snprintf(
            module_root, sizeof(module_root), "%s/modules",
            cache_root) < (int)sizeof(module_root);
    if (cache_ready && options->clean) {
        cache_ready = weave_project_cache_remove_tree(cache_root);
    }
    if (cache_ready && !options->no_cache) {
        cache_ready = weave_project_cache_mkdirs(module_root);
    }

    const char *tmp_root = getenv("TMPDIR");
    if (tmp_root == NULL || *tmp_root == '\0') tmp_root = "/tmp";
    char directory[PATH_MAX];
    int temporary_ready = snprintf(
            directory, sizeof(directory),
            "%s/weavec-project-modules-XXXXXX", tmp_root) <
            (int)sizeof(directory) &&
        mkdtemp(directory) != NULL;

    size_t count = graph.order_count;
    weave_project_module_decision *decisions = calloc(
        count, sizeof(*decisions));
    int result = temporary_ready && decisions != NULL ? 0 : 1;
    for (size_t position = 0;
         result == 0 && position < count;
         ++position) {
        size_t registry_index = graph.order[position];
        const weave_project_source *source =
            &registry.items[registry_index];
        weave_si_module *module = weave_project_module_model_find(
            &model, source->module_name);
        weave_project_module_decision *decision = &decisions[position];
        decision->name = source->module_name;
        decision->logical_path = source->logical_path;
        if (module == NULL ||
            snprintf(
                decision->interface_sha256,
                sizeof(decision->interface_sha256), "%s",
                module->interface_sha256) >=
                (int)sizeof(decision->interface_sha256) ||
            !weave_project_module_key(
                &manifest, &registry, &graph, &model,
                registry_index, &config, runtime,
                decision->key) ||
            !weave_project_module_temp_path(
                directory, position, "o", decision->object)) {
            result = 1;
            break;
        }

        int restored = !options->no_cache && cache_ready &&
            weave_project_cache_restore(
                module_root, decision->key, decision->object);
        if (restored) {
            decision->decision = "reused";
            decision->reason = "implementation-and-import-interfaces-match";
            continue;
        }

        decision->decision = "rebuilt";
        decision->reason = options->no_cache
            ? "cache-disabled"
            : options->clean
                ? "clean-build"
                : "cache-miss-or-invalid";
        result = weave_project_module_compile(
            compiler, ordered_sources, count, position,
            &config, directory, decision->object);
        if (result == 0 && !options->no_cache && cache_ready &&
            !weave_project_cache_store(
                module_root, decision->key, decision->object)) {
            decision->reason = "cache-store-failed";
        }
    }

    if (result == 0) {
        result = weave_project_module_link(
            &config, runtime, output, decisions, count);
    }
    if (!weave_project_module_write_report(
            options->report,
            cache_ready ? module_root : "",
            result, decisions, count) && result == 0) {
        result = 2;
    }

    if (temporary_ready) {
        weave_project_module_cleanup_directory(directory, count);
    }
    free(decisions);
    free(ordered_sources);
    weave_si_free_model(&model);
    weave_project_graph_clear(&graph);
    weave_project_source_registry_clear(&registry);
    weave_project_manifest_clear(&manifest);
    free(request.output_paths);
    return result;
}

int weave_rt_build_main(int argc, char **argv) {
    weave_project_cache_options options = {0};
    if (!weave_project_cache_parse_options(argc, argv, &options)) {
        weave_project_cache_options_clear(&options);
        return 2;
    }
    int result = options.argc >= 2 &&
            strcmp(options.argv[1], "build") == 0
        ? weave_project_module_build(argc, argv, &options)
        : weave_rt_build_main_project_module_legacy(argc, argv);
    weave_project_cache_options_clear(&options);
    return result;
}

#endif
