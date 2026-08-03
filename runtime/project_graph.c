// SPDX-License-Identifier: Apache-2.0
//
// Deterministic module-graph resolution and entry selection for manifest builds.
// The graph layer validates project membership before handing the complete,
// dependency-ordered source set to the existing compiler-authoritative frontend.

#ifndef WEAVEC_PROJECT_GRAPH_C
#define WEAVEC_PROJECT_GRAPH_C

#define WEAVE_PROJECT_GRAPH_ENV "WEAVEC_INTERNAL_PROJECT_GRAPH"

typedef struct weave_project_graph_edge {
    size_t target;
    size_t start;
    size_t end;
} weave_project_graph_edge;

typedef struct weave_project_graph_node {
    weave_project_graph_edge *edges;
    size_t edge_count;
    size_t edge_capacity;
    size_t entry_count;
    size_t entry_start;
    size_t entry_end;
} weave_project_graph_node;

typedef struct weave_project_graph {
    weave_project_graph_node *nodes;
    size_t *order;
    size_t count;
    size_t order_count;
} weave_project_graph;

static void weave_project_graph_clear(weave_project_graph *graph) {
    if (graph->nodes != NULL) {
        for (size_t i = 0; i < graph->count; ++i) {
            free(graph->nodes[i].edges);
        }
    }
    free(graph->nodes);
    free(graph->order);
    memset(graph, 0, sizeof(*graph));
}

static size_t weave_project_graph_find_module(
    const weave_project_source_registry *registry,
    const char *module_name) {
    for (size_t i = 0; i < registry->count; ++i) {
        if (strcmp(registry->items[i].module_name, module_name) == 0) {
            return i;
        }
    }
    return SIZE_MAX;
}

static int weave_project_graph_append_edge(
    weave_project_graph_node *node,
    weave_project_graph_edge edge) {
    for (size_t i = 0; i < node->edge_count; ++i) {
        if (node->edges[i].target == edge.target) return 1;
    }
    if (node->edge_count == node->edge_capacity) {
        size_t capacity = node->edge_capacity == 0 ? 4 : node->edge_capacity * 2;
        if (capacity < node->edge_capacity ||
            capacity > SIZE_MAX / sizeof(*node->edges)) {
            return 0;
        }
        weave_project_graph_edge *grown = realloc(
            node->edges, capacity * sizeof(*node->edges));
        if (grown == NULL) return 0;
        node->edges = grown;
        node->edge_capacity = capacity;
    }
    node->edges[node->edge_count++] = edge;
    return 1;
}

static void weave_project_graph_sort_edges(
    weave_project_graph_node *node,
    const weave_project_source_registry *registry) {
    for (size_t i = 1; i < node->edge_count; ++i) {
        weave_project_graph_edge value = node->edges[i];
        size_t j = i;
        while (j > 0 && strcmp(
                registry->items[node->edges[j - 1].target].module_name,
                registry->items[value.target].module_name) > 0) {
            node->edges[j] = node->edges[j - 1];
            --j;
        }
        node->edges[j] = value;
    }
}

static int weave_project_graph_parse_source(
    const weave_project_source_registry *registry,
    size_t source_index,
    weave_project_graph_node *node,
    weave_project_source_error *error) {
    const weave_project_source *source = &registry->items[source_index];
    size_t length = 0;
    unsigned char *raw = weave_diag_read_file(source->physical_path, &length);
    if (raw == NULL) {
        return weave_project_source_failf(
            error, "project.source.read", source->logical_path,
            source->physical_path, 0, 0, 0,
            "cannot read project source %s while resolving its module graph",
            source->logical_path);
    }

    void *tokens = lex((const char *)raw, (int64_t)length);
    void *tree = tokens == NULL ? NULL : parse(tokens);
    if (tokens == NULL || tree == NULL || node_kind(tree, 0) != node_list()) {
        if (tree != NULL) tree_free(tree);
        if (tokens != NULL) tokens_free(tokens);
        free(raw);
        return weave_project_source_failf(
            error, "project.source.parse", source->logical_path,
            source->physical_path, 0, 0, 0,
            "cannot parse project source %s while resolving its module graph",
            source->logical_path);
    }

    int64_t root_head = node_first_child(tree, 0);
    int64_t module_name = node_next_sibling(tree, root_head);
    int64_t clause = node_next_sibling(tree, module_name);
    int ok = 1;
    while (ok && clause != -1) {
        if (node_kind(tree, clause) == node_list()) {
            int64_t head = node_first_child(tree, clause);
            if (weave_project_node_text_equals(
                    (const char *)raw, length, tree, head, "import")) {
                int64_t imported_module = node_next_sibling(tree, head);
                if (imported_module != -1 &&
                    node_kind(tree, imported_module) == node_ident()) {
                    size_t start = 0;
                    size_t end = 0;
                    char *name = weave_project_node_text(
                        (const char *)raw, length, tree, imported_module,
                        &start, &end);
                    if (name == NULL) {
                        ok = weave_project_source_fail(
                            error, "driver.out-of-memory",
                            "out of memory while resolving project imports",
                            source->logical_path, source->physical_path,
                            0, 0, 0);
                    } else {
                        size_t target = weave_project_graph_find_module(
                            registry, name);
                        if (target == SIZE_MAX) {
                            ok = weave_project_source_failf(
                                error, "project.graph.missing-module",
                                source->logical_path, source->physical_path,
                                start, end, 1,
                                "module %s imports missing project module %s",
                                source->module_name, name);
                        } else {
                            weave_project_graph_edge edge = {
                                .target = target,
                                .start = start,
                                .end = end,
                            };
                            if (!weave_project_graph_append_edge(node, edge)) {
                                ok = weave_project_source_fail(
                                    error, "driver.out-of-memory",
                                    "out of memory while recording project imports",
                                    source->logical_path, source->physical_path,
                                    start, end, 1);
                            }
                        }
                        free(name);
                    }
                }
            } else if (weave_project_node_text_equals(
                           (const char *)raw, length, tree, head, "entry")) {
                size_t start = 0;
                size_t end = 0;
                if (!weave_project_node_span(
                        tree, clause, length, &start, &end)) {
                    start = source->module_start;
                    end = source->module_end;
                }
                if (node->entry_count == 0) {
                    node->entry_start = start;
                    node->entry_end = end;
                }
                ++node->entry_count;
            }
        }
        clause = node_next_sibling(tree, clause);
    }

    tree_free(tree);
    tokens_free(tokens);
    free(raw);
    if (ok) weave_project_graph_sort_edges(node, registry);
    return ok;
}

static int weave_project_graph_visit(
    size_t source_index,
    const weave_project_source_registry *registry,
    weave_project_graph *graph,
    unsigned char *state,
    weave_project_source_error *error) {
    state[source_index] = 1;
    weave_project_graph_node *node = &graph->nodes[source_index];
    for (size_t i = 0; i < node->edge_count; ++i) {
        weave_project_graph_edge edge = node->edges[i];
        if (state[edge.target] == 1) {
            const weave_project_source *source = &registry->items[source_index];
            return weave_project_source_failf(
                error, "project.graph.import-cycle",
                source->logical_path, source->physical_path,
                edge.start, edge.end, 1,
                "module %s imports %s through a project module cycle",
                source->module_name,
                registry->items[edge.target].module_name);
        }
        if (state[edge.target] == 0 &&
            !weave_project_graph_visit(
                edge.target, registry, graph, state, error)) {
            return 0;
        }
    }
    state[source_index] = 2;
    graph->order[graph->order_count++] = source_index;
    return 1;
}

static int weave_project_graph_build(
    const weave_project_manifest *manifest,
    const weave_project_source_registry *registry,
    weave_project_graph *graph,
    weave_project_source_error *error) {
    graph->count = registry->count;
    graph->nodes = calloc(graph->count, sizeof(*graph->nodes));
    graph->order = calloc(graph->count, sizeof(*graph->order));
    if (graph->nodes == NULL || graph->order == NULL) {
        return weave_project_source_fail(
            error, "driver.out-of-memory",
            "out of memory while constructing the project module graph",
            manifest->path, manifest->path, 0, 0, 0);
    }

    for (size_t i = 0; i < registry->count; ++i) {
        if (!weave_project_graph_parse_source(
                registry, i, &graph->nodes[i], error)) {
            return 0;
        }
    }

    size_t *roots = calloc(registry->count, sizeof(*roots));
    unsigned char *state = calloc(registry->count, sizeof(*state));
    if (roots == NULL || state == NULL) {
        free(roots);
        free(state);
        return weave_project_source_fail(
            error, "driver.out-of-memory",
            "out of memory while ordering project modules",
            manifest->path, manifest->path, 0, 0, 0);
    }
    for (size_t i = 0; i < registry->count; ++i) roots[i] = i;
    for (size_t i = 1; i < registry->count; ++i) {
        size_t value = roots[i];
        size_t j = i;
        while (j > 0 && strcmp(
                registry->items[roots[j - 1]].module_name,
                registry->items[value].module_name) > 0) {
            roots[j] = roots[j - 1];
            --j;
        }
        roots[j] = value;
    }

    int ok = 1;
    for (size_t i = 0; ok && i < registry->count; ++i) {
        if (state[roots[i]] == 0) {
            ok = weave_project_graph_visit(
                roots[i], registry, graph, state, error);
        }
    }
    free(roots);
    free(state);
    if (!ok) return 0;

    if (strcmp(manifest->kind, "executable") == 0) {
        size_t entry = weave_project_graph_find_module(registry, manifest->entry);
        if (entry == SIZE_MAX) {
            return weave_project_source_failf(
                error, "project.entry.missing-module",
                manifest->path, manifest->path, 0, 0, 0,
                "project entry module %s is not declared by any project source",
                manifest->entry);
        }
        if (graph->nodes[entry].entry_count == 0) {
            const weave_project_source *source = &registry->items[entry];
            return weave_project_source_failf(
                error, "project.entry.missing-declaration",
                source->logical_path, source->physical_path,
                source->module_start, source->module_end, 1,
                "project entry module %s has no entry declaration",
                manifest->entry);
        }
        if (graph->nodes[entry].entry_count > 1) {
            const weave_project_source *source = &registry->items[entry];
            return weave_project_source_failf(
                error, "project.entry.duplicate-declaration",
                source->logical_path, source->physical_path,
                graph->nodes[entry].entry_start,
                graph->nodes[entry].entry_end, 1,
                "project entry module %s has multiple entry declarations",
                manifest->entry);
        }
        for (size_t i = 0; i < registry->count; ++i) {
            if (i != entry && graph->nodes[i].entry_count > 0) {
                const weave_project_source *source = &registry->items[i];
                return weave_project_source_failf(
                    error, "project.entry.unselected-declaration",
                    source->logical_path, source->physical_path,
                    graph->nodes[i].entry_start,
                    graph->nodes[i].entry_end, 1,
                    "module %s declares an entry but the project selects %s",
                    source->module_name, manifest->entry);
            }
        }
    } else {
        for (size_t i = 0; i < registry->count; ++i) {
            if (graph->nodes[i].entry_count > 0) {
                const weave_project_source *source = &registry->items[i];
                return weave_project_source_failf(
                    error, "project.entry.library-declaration",
                    source->logical_path, source->physical_path,
                    graph->nodes[i].entry_start,
                    graph->nodes[i].entry_end, 1,
                    "library project module %s must not declare an entry",
                    source->module_name);
            }
        }
    }
    return 1;
}

static int weave_project_publish_internal_graph(
    const weave_project_manifest *manifest,
    const weave_project_source_registry *registry,
    const weave_project_graph *graph,
    weave_project_source_error *error) {
    const char *path = getenv(WEAVE_PROJECT_GRAPH_ENV);
    if (path == NULL || *path == '\0') return 1;
    if (weave_path_safety_aliases(path, manifest->path)) {
        return weave_project_source_fail(
            error, "driver.internal-output-alias",
            "internal project graph aliases the project manifest",
            path, path, 0, 0, 0);
    }
    for (size_t i = 0; i < registry->count; ++i) {
        if (weave_path_safety_aliases(path, registry->items[i].physical_path)) {
            return weave_project_source_fail(
                error, "driver.internal-output-alias",
                "internal project graph aliases a project source",
                registry->items[i].logical_path,
                registry->items[i].physical_path, 0, 0, 0);
        }
    }
    FILE *stream = fopen(path, "wb");
    if (stream == NULL) {
        return weave_project_source_fail(
            error, "driver.internal-output-write",
            "cannot write internal project module graph",
            path, path, 0, 0, 0);
    }
    int ok = 1;
    for (size_t i = 0; ok && i < graph->order_count; ++i) {
        size_t index = graph->order[i];
        ok = fprintf(
            stream, "%s\t%s\n",
            registry->items[index].module_name,
            registry->items[index].logical_path) >= 0;
    }
    if (fclose(stream) != 0) ok = 0;
    if (!ok) {
        (void)unlink(path);
        return weave_project_source_fail(
            error, "driver.internal-output-write",
            "cannot finish internal project module graph",
            path, path, 0, 0, 0);
    }
    return 1;
}

static int weave_project_resolve_output(
    const weave_project_request *request,
    const weave_project_manifest *manifest,
    char *output,
    size_t output_size,
    weave_project_source_error *error) {
    int ok = request->output != NULL
        ? snprintf(output, output_size, "%s", request->output) < (int)output_size
        : weave_project_join_path(
              output, output_size, manifest->directory, manifest->output);
    if (!ok) {
        return weave_project_source_fail(
            error, "project.manifest.output",
            "resolved project output path is too long",
            manifest->path, manifest->path, 0, 0, 0);
    }
    return 1;
}

static int weave_project_arg_is_output(const char *arg) {
    return strcmp(arg, "-o") == 0 || strcmp(arg, "--output") == 0;
}

static int weave_project_arg_is_project(const char *arg) {
    return strcmp(arg, "--project") == 0 ||
        strncmp(arg, "--project=", 10) == 0;
}

static int weave_project_arg_is_emit_wir(const char *arg) {
    return strcmp(arg, "--emit-wir") == 0;
}

static int weave_project_arg_is_linker(const char *arg) {
    return strcmp(arg, "--linker") == 0;
}

static int weave_project_write_library_linker(
    char *path,
    size_t path_size) {
    const char *tmp = getenv("TMPDIR");
    if (tmp == NULL || *tmp == '\0') tmp = "/tmp";
    if (snprintf(path, path_size, "%s/weavec-project-linker-XXXXXX", tmp) >=
        (int)path_size) {
        return 0;
    }
    int fd = mkstemp(path);
    if (fd < 0) return 0;
    const char script[] =
        "#!/bin/sh\n"
        "out=\n"
        "while [ \"$#\" -gt 0 ]; do\n"
        "  if [ \"$1\" = -o ] && [ \"$#\" -ge 2 ]; then\n"
        "    out=$2\n"
        "    shift 2\n"
        "  else\n"
        "    shift\n"
        "  fi\n"
        "done\n"
        "[ -n \"$out\" ] || exit 2\n"
        ": > \"$out\"\n";
    size_t length = sizeof(script) - 1;
    ssize_t written = write(fd, script, length);
    int ok = written == (ssize_t)length && fchmod(fd, 0700) == 0;
    if (close(fd) != 0) ok = 0;
    if (!ok) unlink(path);
    return ok;
}

static int weave_project_run_build(
    int argc,
    char **argv,
    const weave_project_manifest *manifest,
    const weave_project_source_registry *registry,
    const weave_project_graph *graph,
    const char *resolved_output,
    weave_project_source_error *error) {
    int library = strcmp(manifest->kind, "library") == 0;
    for (int i = 2; library && i < argc; ++i) {
        if (weave_project_arg_is_emit_wir(argv[i])) {
            return weave_project_source_fail(
                error, "project.library.emit-wir-conflict",
                "library project output is already the normalized WIR bundle; --emit-wir is ambiguous",
                manifest->path, manifest->path, 0, 0, 0);
        }
    }

    size_t capacity = (size_t)argc + registry->count + 12;
    char **build_argv = calloc(capacity, sizeof(*build_argv));
    if (build_argv == NULL) {
        return weave_project_source_fail(
            error, "driver.out-of-memory",
            "out of memory while preparing the project build",
            manifest->path, manifest->path, 0, 0, 0);
    }

    int build_argc = 0;
    build_argv[build_argc++] = argv[0];
    build_argv[build_argc++] = "build";
    for (size_t i = 0; i < graph->order_count; ++i) {
        build_argv[build_argc++] =
            registry->items[graph->order[i]].physical_path;
    }
    for (int i = 2; i < argc; ++i) {
        const char *arg = argv[i];
        if (weave_project_arg_is_project(arg)) {
            if (strcmp(arg, "--project") == 0) ++i;
            continue;
        }
        if (weave_project_arg_is_output(arg)) {
            ++i;
            continue;
        }
        if (strncmp(arg, "--output=", 9) == 0) continue;
        if (library && weave_project_arg_is_emit_wir(arg)) {
            ++i;
            continue;
        }
        if (library && weave_project_arg_is_linker(arg)) {
            ++i;
            continue;
        }
        build_argv[build_argc++] = argv[i];
    }

    char linker_path[PATH_MAX] = {0};
    char dummy_output[PATH_MAX] = {0};
    int result = 0;
    if (!library) {
        build_argv[build_argc++] = "-o";
        build_argv[build_argc++] = (char *)resolved_output;
    } else {
        const char *tmp = getenv("TMPDIR");
        if (tmp == NULL || *tmp == '\0') tmp = "/tmp";
        if (snprintf(
                dummy_output, sizeof(dummy_output),
                "%s/weavec-project-library-XXXXXX", tmp) >=
            (int)sizeof(dummy_output)) {
            free(build_argv);
            return weave_project_source_fail(
                error, "project.library.temporary-path",
                "temporary library build path is too long",
                manifest->path, manifest->path, 0, 0, 0);
        }
        int dummy_fd = mkstemp(dummy_output);
        if (dummy_fd < 0) {
            free(build_argv);
            return weave_project_source_fail(
                error, "project.library.temporary-output",
                "cannot create temporary library link output",
                manifest->path, manifest->path, 0, 0, 0);
        }
        close(dummy_fd);
        unlink(dummy_output);
        if (!weave_project_write_library_linker(
                linker_path, sizeof(linker_path))) {
            free(build_argv);
            return weave_project_source_fail(
                error, "project.library.temporary-linker",
                "cannot create the private library link adapter",
                manifest->path, manifest->path, 0, 0, 0);
        }
        build_argv[build_argc++] = "-o";
        build_argv[build_argc++] = dummy_output;
        build_argv[build_argc++] = "--emit-wir";
        build_argv[build_argc++] = (char *)resolved_output;
        build_argv[build_argc++] = "--linker";
        build_argv[build_argc++] = linker_path;
    }
    build_argv[build_argc] = NULL;

    result = weave_rt_build_main_project_legacy(build_argc, build_argv);
    if (library) {
        unlink(dummy_output);
        unlink(linker_path);
    }
    free(build_argv);
    return result;
}

int weave_rt_build_main(int argc, char **argv) {
    if (argc < 2 || strcmp(argv[1], "build") != 0) {
        return weave_rt_build_main_source_discovery_legacy(argc, argv);
    }

    weave_project_request request = {0};
    weave_project_error manifest_error = {0};
    if (!weave_project_parse_request(argc, argv, &request, &manifest_error) ||
        request.help || request.unknown_option != NULL ||
        request.source_count > 0) {
        free(request.output_paths);
        return weave_rt_build_main_source_discovery_legacy(argc, argv);
    }

    weave_project_manifest manifest = {0};
    if (!weave_project_load(request.project, &manifest, &manifest_error)) {
        int result = weave_project_publish_error(
            &manifest_error, request.diagnostics, request.trace, 2);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return result;
    }

    weave_project_source_registry registry = {0};
    weave_project_source_error source_error = {0};
    weave_project_graph graph = {0};
    int ok = weave_project_discover_sources(
        &request, &manifest, &registry, &source_error);
    if (ok) {
        ok = weave_project_publish_internal_sources(
            &manifest, &registry, &source_error);
    }
    if (ok) {
        ok = weave_project_graph_build(
            &manifest, &registry, &graph, &source_error);
    }
    if (ok) {
        ok = weave_project_publish_internal_graph(
            &manifest, &registry, &graph, &source_error);
    }

    char resolved_output[PATH_MAX];
    if (ok) {
        ok = weave_project_resolve_output(
            &request, &manifest, resolved_output,
            sizeof(resolved_output), &source_error);
    }

    int result = 0;
    if (!ok) {
        const char *diagnostics = NULL;
        const char *trace = NULL;
        weave_project_safe_protocol_outputs(
            &request, &source_error, &diagnostics, &trace);
        result = weave_project_publish_source_error(
            &source_error, diagnostics, trace, 2);
    } else {
        result = weave_project_run_build(
            argc, argv, &manifest, &registry, &graph,
            resolved_output, &source_error);
        if (source_error.code != NULL) {
            const char *diagnostics = NULL;
            const char *trace = NULL;
            weave_project_safe_protocol_outputs(
                &request, &source_error, &diagnostics, &trace);
            result = weave_project_publish_source_error(
                &source_error, diagnostics, trace, 2);
        }
    }

    weave_project_graph_clear(&graph);
    weave_project_source_registry_clear(&registry);
    weave_project_manifest_clear(&manifest);
    free(request.output_paths);
    return result;
}

#endif
