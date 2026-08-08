// SPDX-License-Identifier: Apache-2.0
//
// Project-mode orchestration and opaque fact access. Public project protocol
// schemas are owned by src/protocol/project.weave. This native layer resolves
// project files, exposes facts to Weave, and performs only schema-agnostic file
// publication mechanics for the older semantic-index serializer.

#ifndef WEAVEC_PROJECT_PROTOCOLS_C
#define WEAVEC_PROJECT_PROTOCOLS_C

typedef struct weave_project_protocol_context {
    int active;
    int manifest_loaded;
    int sources_loaded;
    int graph_loaded;
    int output_resolved;
    const char *selection;
    const char *resolution_phase;
    weave_project_manifest manifest;
    weave_project_source_registry registry;
    weave_project_graph graph;
    char resolved_output[PATH_MAX];
} weave_project_protocol_context;

static weave_project_protocol_context *weave_project_protocol_active_context = NULL;

extern void protocol_write_active_project(void *writer);

static void weave_project_protocol_context_clear(
    weave_project_protocol_context *context) {
    weave_project_graph_clear(&context->graph);
    weave_project_source_registry_clear(&context->registry);
    weave_project_manifest_clear(&context->manifest);
    memset(context, 0, sizeof(*context));
}

static int weave_project_protocol_is_project_build(
    int argc,
    char **argv,
    weave_project_request *request) {
    if (argc < 2 || strcmp(argv[1], "build") != 0) return 0;
    weave_project_error error = {0};
    if (!weave_project_parse_request(argc, argv, request, &error)) return 0;
    return !request->help && request->unknown_option == NULL &&
        request->source_count == 0;
}

static void weave_project_protocol_prepare_build(
    int argc,
    char **argv,
    weave_project_protocol_context *context) {
    weave_project_request request = {0};
    if (!weave_project_protocol_is_project_build(argc, argv, &request)) {
        free(request.output_paths);
        return;
    }

    context->active = 1;
    context->selection = request.project;
    context->resolution_phase = "project-manifest";

    weave_project_error manifest_error = {0};
    if (!weave_project_load(
            request.project, &context->manifest, &manifest_error)) {
        free(request.output_paths);
        return;
    }
    context->manifest_loaded = 1;

    context->resolution_phase = "project-sources";
    weave_project_source_error source_error = {0};
    if (!weave_project_discover_sources(
            &request,
            &context->manifest,
            &context->registry,
            &source_error)) {
        free(request.output_paths);
        return;
    }
    context->sources_loaded = 1;

    context->resolution_phase = "project-graph";
    if (!weave_project_graph_build(
            &context->manifest,
            &context->registry,
            &context->graph,
            &source_error)) {
        free(request.output_paths);
        return;
    }
    context->graph_loaded = 1;

    if (weave_project_resolve_output(
            &request,
            &context->manifest,
            context->resolved_output,
            sizeof(context->resolved_output),
            &source_error)) {
        context->output_resolved = 1;
        context->resolution_phase = "complete";
    }
    free(request.output_paths);
}

// Opaque fact accessors used by src/protocol/project.weave. These functions own
// no field names, JSON shape, ordering, or compatibility policy.
void *weave_host_project_protocol_active(void) {
    return weave_project_protocol_active_context;
}

const char *weave_host_project_resolution_phase(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? context->resolution_phase : NULL;
}

const char *weave_host_project_selection(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? context->selection : NULL;
}

int weave_host_project_manifest_loaded(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? context->manifest_loaded : 0;
}

const char *weave_host_project_manifest_name(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? context->manifest.name : NULL;
}

const char *weave_host_project_manifest_kind(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? context->manifest.kind : NULL;
}

const char *weave_host_project_manifest_path(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? context->manifest.path : NULL;
}

const char *weave_host_project_manifest_directory(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? context->manifest.directory : NULL;
}

const char *weave_host_project_manifest_entry(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? context->manifest.entry : NULL;
}

const char *weave_host_project_manifest_output(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? context->manifest.output : NULL;
}

long long weave_host_project_source_root_count(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? (long long)context->manifest.source_root_count : 0;
}

const char *weave_host_project_source_root_at(void *opaque, long long index) {
    const weave_project_protocol_context *context = opaque;
    if (context == NULL || index < 0 ||
        (size_t)index >= context->manifest.source_root_count) return NULL;
    return context->manifest.source_roots[index];
}

long long weave_host_project_test_root_count(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? (long long)context->manifest.test_root_count : 0;
}

const char *weave_host_project_test_root_at(void *opaque, long long index) {
    const weave_project_protocol_context *context = opaque;
    if (context == NULL || index < 0 ||
        (size_t)index >= context->manifest.test_root_count) return NULL;
    return context->manifest.test_roots[index];
}

int weave_host_project_output_resolved(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? context->output_resolved : 0;
}

const char *weave_host_project_resolved_output(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL && context->output_resolved
        ? context->resolved_output : NULL;
}

int weave_host_project_sources_loaded(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? context->sources_loaded : 0;
}

long long weave_host_project_source_count(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? (long long)context->registry.count : 0;
}

static const weave_project_source *weave_project_protocol_source_at(
    const weave_project_protocol_context *context,
    long long index) {
    if (context == NULL || index < 0 ||
        (size_t)index >= context->registry.count) return NULL;
    return &context->registry.items[index];
}

const char *weave_host_project_source_module(void *opaque, long long index) {
    const weave_project_source *source = weave_project_protocol_source_at(
        opaque, index);
    return source != NULL ? source->module_name : NULL;
}

const char *weave_host_project_source_logical_path(void *opaque, long long index) {
    const weave_project_source *source = weave_project_protocol_source_at(
        opaque, index);
    return source != NULL ? source->logical_path : NULL;
}

const char *weave_host_project_source_physical_path(void *opaque, long long index) {
    const weave_project_source *source = weave_project_protocol_source_at(
        opaque, index);
    return source != NULL ? source->physical_path : NULL;
}

int weave_host_project_graph_loaded(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? context->graph_loaded : 0;
}

long long weave_host_project_graph_order_count(void *opaque) {
    const weave_project_protocol_context *context = opaque;
    return context != NULL ? (long long)context->graph.order_count : 0;
}

long long weave_host_project_graph_order_source_index(
    void *opaque,
    long long order_index) {
    const weave_project_protocol_context *context = opaque;
    if (context == NULL || order_index < 0 ||
        (size_t)order_index >= context->graph.order_count) return -1;
    return (long long)context->graph.order[order_index];
}

long long weave_host_project_graph_edge_count(
    void *opaque,
    long long source_index) {
    const weave_project_protocol_context *context = opaque;
    if (context == NULL || source_index < 0 ||
        (size_t)source_index >= context->registry.count) return 0;
    return (long long)context->graph.nodes[source_index].edge_count;
}

long long weave_host_project_graph_edge_target_source_index(
    void *opaque,
    long long source_index,
    long long edge_index) {
    const weave_project_protocol_context *context = opaque;
    if (context == NULL || source_index < 0 || edge_index < 0 ||
        (size_t)source_index >= context->registry.count) return -1;
    const weave_project_graph_node *node = &context->graph.nodes[source_index];
    if ((size_t)edge_index >= node->edge_count) return -1;
    return (long long)node->edges[edge_index].target;
}

int weave_rt_build_main(int argc, char **argv) {
    weave_project_protocol_context context = {0};
    weave_project_protocol_prepare_build(argc, argv, &context);
    weave_project_protocol_active_context = context.active ? &context : NULL;
    int result = weave_rt_build_main_project_protocol_legacy(argc, argv);
    weave_project_protocol_active_context = NULL;
    weave_project_protocol_context_clear(&context);
    return result;
}

// Project-mode capability facts are part of the Weave-owned capability document.
int weave_rt_print_capabilities(void) {
    return weave_rt_print_capabilities_project_legacy();
}

// The semantic-index serializer predates #166. Preserve its existing project
// attachment using a schema-agnostic merge of two complete JSON objects. The
// appended object's field name and value are both produced by project.weave.
typedef struct weave_project_object_merge {
    const unsigned char *base;
    size_t base_length;
    const unsigned char *fragment;
    size_t fragment_length;
} weave_project_object_merge;

static size_t weave_project_trim_json_end(
    const unsigned char *bytes,
    size_t length) {
    while (length > 0 &&
           (bytes[length - 1] == '\n' || bytes[length - 1] == '\r' ||
            bytes[length - 1] == ' ' || bytes[length - 1] == '\t')) {
        --length;
    }
    return length;
}

static int weave_project_protocol_render_fragment(
    weave_project_protocol_context *context,
    unsigned char **bytes_out,
    size_t *length_out) {
    FILE *stream = tmpfile();
    if (stream == NULL) return 0;
    weave_json_writer writer;
    weave_json_writer_init(&writer, stream);
    weave_project_protocol_context *saved = weave_project_protocol_active_context;
    weave_project_protocol_active_context = context;
    int ok = weave_json_object_begin(&writer);
    if (ok) protocol_write_active_project(&writer);
    ok = ok && weave_json_object_end(&writer) &&
        weave_json_writer_finish(&writer) && fflush(stream) == 0 &&
        fseek(stream, 0, SEEK_END) == 0;
    weave_project_protocol_active_context = saved;
    long end = ok ? ftell(stream) : -1;
    if (end < 0 || fseek(stream, 0, SEEK_SET) != 0) ok = 0;
    unsigned char *bytes = NULL;
    if (ok) {
        bytes = malloc((size_t)end + 1);
        if (bytes == NULL) {
            ok = 0;
        } else if (fread(bytes, 1, (size_t)end, stream) != (size_t)end) {
            ok = 0;
        } else {
            bytes[end] = '\0';
        }
    }
    if (fclose(stream) != 0) ok = 0;
    if (!ok) {
        free(bytes);
        return 0;
    }
    *bytes_out = bytes;
    *length_out = (size_t)end;
    return 1;
}

static int weave_project_protocol_publish_merged_object(
    FILE *stream,
    const void *opaque) {
    const weave_project_object_merge *document = opaque;
    size_t base_length = weave_project_trim_json_end(
        document->base, document->base_length);
    size_t fragment_length = weave_project_trim_json_end(
        document->fragment, document->fragment_length);
    if (base_length < 2 || fragment_length < 2 ||
        document->base[0] != '{' || document->base[base_length - 1] != '}' ||
        document->fragment[0] != '{' ||
        document->fragment[fragment_length - 1] != '}') {
        return 1;
    }
    --base_length;
    --fragment_length;
    if (fwrite(document->base, 1, base_length, stream) != base_length ||
        fputc(',', stream) == EOF ||
        fwrite(document->fragment + 1, 1, fragment_length - 1, stream) !=
            fragment_length - 1 ||
        fputs("}\n", stream) == EOF) {
        return 1;
    }
    return 0;
}

static int weave_project_protocol_merge_file(
    const char *path,
    weave_project_protocol_context *context) {
    if (path == NULL || access(path, F_OK) != 0) return 0;
    size_t base_length = 0;
    unsigned char *base = weave_diag_read_file(path, &base_length);
    if (base == NULL) return 1;
    unsigned char *fragment = NULL;
    size_t fragment_length = 0;
    if (!weave_project_protocol_render_fragment(
            context, &fragment, &fragment_length)) {
        free(base);
        return 1;
    }
    weave_project_object_merge document = {
        .base = base,
        .base_length = base_length,
        .fragment = fragment,
        .fragment_length = fragment_length,
    };
    int result = weave_publish_document(
        path,
        "project protocol",
        0644,
        weave_project_protocol_publish_merged_object,
        &document);
    free(fragment);
    free(base);
    return result;
}

typedef struct weave_project_analyze_request {
    const char *project;
    const char *output;
    int source_count;
    int invalid;
} weave_project_analyze_request;

static weave_project_analyze_request weave_project_protocol_parse_analyze(
    int argc,
    char **argv) {
    weave_project_analyze_request request = {0};
    for (int index = 2; index < argc; ++index) {
        const char *arg = argv[index];
        if (strcmp(arg, "--project") == 0) {
            if (++index >= argc || request.project != NULL) {
                request.invalid = 1;
                break;
            }
            request.project = argv[index];
        } else if (strncmp(arg, "--project=", 10) == 0) {
            if (arg[10] == '\0' || request.project != NULL) {
                request.invalid = 1;
                break;
            }
            request.project = arg + 10;
        } else if (strcmp(arg, "--semantic-index-json") == 0) {
            if (++index >= argc || request.output != NULL) {
                request.invalid = 1;
                break;
            }
            request.output = argv[index];
        } else if (arg[0] == '-') {
            request.invalid = 1;
            break;
        } else {
            ++request.source_count;
        }
    }
    return request;
}

static int weave_project_protocol_absolute_path(
    const char *path,
    char *output,
    size_t output_size) {
    if (path == NULL || *path == '\0') return 0;
    if (path[0] == '/') {
        int written = snprintf(output, output_size, "%s", path);
        return written >= 0 && (size_t)written < output_size;
    }
    char directory[PATH_MAX];
    if (getcwd(directory, sizeof(directory)) == NULL) return 0;
    return weave_project_join_path(
        output, output_size, directory, path);
}

static int weave_project_protocol_analyze_project(
    int argc,
    char **argv,
    const weave_project_analyze_request *request) {
    (void)argc;
    weave_project_protocol_context context = {
        .active = 1,
        .selection = request->project,
        .resolution_phase = "project-manifest",
    };
    weave_project_error manifest_error = {0};
    if (!weave_project_load(
            request->project,
            &context.manifest,
            &manifest_error)) {
        int result = weave_project_publish_error(
            &manifest_error, NULL, NULL, 2);
        weave_project_protocol_context_clear(&context);
        return result;
    }
    context.manifest_loaded = 1;

    weave_project_request source_request = {0};
    const char *output_paths[1] = {request->output};
    source_request.project = request->project;
    source_request.output_paths = output_paths;
    source_request.output_path_count = request->output != NULL ? 1 : 0;

    context.resolution_phase = "project-sources";
    weave_project_source_error source_error = {0};
    if (!weave_project_discover_sources(
            &source_request,
            &context.manifest,
            &context.registry,
            &source_error)) {
        int result = weave_project_publish_source_error(
            &source_error, NULL, NULL, 2);
        weave_project_protocol_context_clear(&context);
        return result;
    }
    context.sources_loaded = 1;

    context.resolution_phase = "project-graph";
    if (!weave_project_graph_build(
            &context.manifest,
            &context.registry,
            &context.graph,
            &source_error)) {
        int result = weave_project_publish_source_error(
            &source_error, NULL, NULL, 2);
        weave_project_protocol_context_clear(&context);
        return result;
    }
    context.graph_loaded = 1;
    context.resolution_phase = "complete";

    char output[PATH_MAX];
    if (!weave_project_protocol_absolute_path(
            request->output, output, sizeof(output))) {
        fputs("weavec: semantic-index output path is invalid\n", stderr);
        weave_project_protocol_context_clear(&context);
        return 2;
    }
    if (weave_path_safety_aliases(output, context.manifest.path)) {
        fputs("weavec: semantic-index output aliases weave.project\n", stderr);
        weave_project_protocol_context_clear(&context);
        return 2;
    }
    for (size_t index = 0; index < context.registry.count; ++index) {
        if (weave_path_safety_aliases(
                output, context.registry.items[index].physical_path)) {
            fputs("weavec: semantic-index output aliases a project source\n", stderr);
            weave_project_protocol_context_clear(&context);
            return 2;
        }
    }

    size_t argument_capacity = context.graph.order_count + 5;
    char **analyze = calloc(argument_capacity, sizeof(*analyze));
    if (analyze == NULL) {
        weave_project_protocol_context_clear(&context);
        return 1;
    }
    int analyze_argc = 0;
    analyze[analyze_argc++] = argv[0];
    analyze[analyze_argc++] = "analyze";
    for (size_t index = 0; index < context.graph.order_count; ++index) {
        analyze[analyze_argc++] =
            context.registry.items[context.graph.order[index]].logical_path;
    }
    analyze[analyze_argc++] = "--semantic-index-json";
    analyze[analyze_argc++] = output;
    analyze[analyze_argc] = NULL;

    char original_directory[PATH_MAX];
    if (getcwd(original_directory, sizeof(original_directory)) == NULL ||
        chdir(context.manifest.directory) != 0) {
        free(analyze);
        weave_project_protocol_context_clear(&context);
        return 1;
    }
    weave_project_protocol_active_context = &context;
    int result = weave_rt_semantic_index_main_project_legacy(
        analyze_argc, analyze);
    weave_project_protocol_active_context = NULL;
    int restore_failed = chdir(original_directory) != 0;
    free(analyze);

    if (!restore_failed && access(output, F_OK) == 0 &&
        weave_project_protocol_merge_file(output, &context) != 0) {
        result = 1;
    }
    weave_project_protocol_context_clear(&context);
    return restore_failed ? 1 : result;
}

int weave_rt_semantic_index_main(int argc, char **argv) {
    if (argc < 2 || strcmp(argv[1], "analyze") != 0) {
        return weave_rt_semantic_index_main_project_legacy(argc, argv);
    }
    weave_project_analyze_request request =
        weave_project_protocol_parse_analyze(argc, argv);
    if (request.invalid || request.source_count > 0) {
        return weave_rt_semantic_index_main_project_legacy(argc, argv);
    }
    if (request.output == NULL) {
        fputs(
            "usage: weavec analyze [--project <directory-or-manifest>] "
            "--semantic-index-json <index.json>\n",
            stderr);
        return 2;
    }
    return weave_project_protocol_analyze_project(argc, argv, &request);
}

#endif
