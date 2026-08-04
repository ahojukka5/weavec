// SPDX-License-Identifier: Apache-2.0
//
// Compiler-owned project protocol facade. The existing project resolver remains
// the semantic authority. This final wrapper observes the same manifest, source
// registry, and module graph and adds those facts to public JSON protocols.

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

typedef struct weave_project_protocol_document {
    const unsigned char *base;
    size_t base_length;
    const unsigned char *project;
    size_t project_length;
    const char *replacement_phase;
} weave_project_protocol_document;

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

static int weave_project_protocol_write_string_array(
    weave_json_writer *writer,
    char **values,
    size_t count) {
    if (!weave_json_array_begin(writer)) return 0;
    for (size_t index = 0; index < count; ++index) {
        if (!weave_json_string(writer, values[index])) return 0;
    }
    return weave_json_array_end(writer);
}

static int weave_project_protocol_write_project(
    weave_json_writer *writer,
    const weave_project_protocol_context *context) {
    if (!weave_json_object_begin(writer) ||
        !weave_json_key(writer, "format") ||
        !weave_json_string(writer, "weavec-project-facts-v1") ||
        !weave_json_key(writer, "complete") ||
        !weave_diagnostics_bool(
            writer,
            context->resolution_phase != NULL &&
                strcmp(context->resolution_phase, "complete") == 0) ||
        !weave_json_key(writer, "resolution_phase") ||
        !weave_json_string(
            writer,
            context->resolution_phase != NULL
                ? context->resolution_phase
                : "project-manifest") ||
        !weave_json_key(writer, "selection") ||
        !weave_json_nullable_string(writer, context->selection) ||
        !weave_json_key(writer, "name")) {
        return 0;
    }

    if (!context->manifest_loaded) {
        return weave_json_null(writer) &&
            weave_json_key(writer, "kind") &&
            weave_json_null(writer) &&
            weave_json_key(writer, "manifest") &&
            weave_json_null(writer) &&
            weave_json_key(writer, "root") &&
            weave_json_null(writer) &&
            weave_json_key(writer, "source_roots") &&
            weave_json_array_begin(writer) &&
            weave_json_array_end(writer) &&
            weave_json_key(writer, "test_roots") &&
            weave_json_array_begin(writer) &&
            weave_json_array_end(writer) &&
            weave_json_key(writer, "entry_module") &&
            weave_json_null(writer) &&
            weave_json_key(writer, "output") &&
            weave_json_null(writer) &&
            weave_json_key(writer, "resolved_output") &&
            weave_json_null(writer) &&
            weave_json_key(writer, "sources") &&
            weave_json_array_begin(writer) &&
            weave_json_array_end(writer) &&
            weave_json_key(writer, "module_order") &&
            weave_json_array_begin(writer) &&
            weave_json_array_end(writer) &&
            weave_json_key(writer, "module_graph") &&
            weave_json_array_begin(writer) &&
            weave_json_array_end(writer) &&
            weave_json_object_end(writer);
    }

    if (!weave_json_string(writer, context->manifest.name) ||
        !weave_json_key(writer, "kind") ||
        !weave_json_string(writer, context->manifest.kind) ||
        !weave_json_key(writer, "manifest") ||
        !weave_json_object_begin(writer) ||
        !weave_json_key(writer, "logical_path") ||
        !weave_json_string(writer, WEAVE_PROJECT_MANIFEST_NAME) ||
        !weave_json_key(writer, "physical_path") ||
        !weave_json_string(writer, context->manifest.path) ||
        !weave_json_object_end(writer) ||
        !weave_json_key(writer, "root") ||
        !weave_json_object_begin(writer) ||
        !weave_json_key(writer, "physical_path") ||
        !weave_json_string(writer, context->manifest.directory) ||
        !weave_json_object_end(writer) ||
        !weave_json_key(writer, "source_roots") ||
        !weave_project_protocol_write_string_array(
            writer,
            context->manifest.source_roots,
            context->manifest.source_root_count) ||
        !weave_json_key(writer, "test_roots") ||
        !weave_project_protocol_write_string_array(
            writer,
            context->manifest.test_roots,
            context->manifest.test_root_count) ||
        !weave_json_key(writer, "entry_module")) {
        return 0;
    }

    if (strcmp(context->manifest.kind, "executable") == 0) {
        if (!weave_json_string(writer, context->manifest.entry)) return 0;
    } else if (!weave_json_null(writer)) {
        return 0;
    }

    if (!weave_json_key(writer, "output") ||
        !weave_json_string(writer, context->manifest.output) ||
        !weave_json_key(writer, "resolved_output")) {
        return 0;
    }
    if (context->output_resolved) {
        if (!weave_json_string(writer, context->resolved_output)) return 0;
    } else if (!weave_json_null(writer)) {
        return 0;
    }

    if (!weave_json_key(writer, "sources") ||
        !weave_json_array_begin(writer)) {
        return 0;
    }
    if (context->sources_loaded) {
        for (size_t index = 0; index < context->registry.count; ++index) {
            const weave_project_source *source =
                &context->registry.items[index];
            if (!weave_json_object_begin(writer) ||
                !weave_json_key(writer, "module") ||
                !weave_json_string(writer, source->module_name) ||
                !weave_json_key(writer, "logical_path") ||
                !weave_json_string(writer, source->logical_path) ||
                !weave_json_key(writer, "physical_path") ||
                !weave_json_string(writer, source->physical_path) ||
                !weave_json_object_end(writer)) {
                return 0;
            }
        }
    }
    if (!weave_json_array_end(writer) ||
        !weave_json_key(writer, "module_order") ||
        !weave_json_array_begin(writer)) {
        return 0;
    }
    if (context->graph_loaded) {
        for (size_t index = 0; index < context->graph.order_count; ++index) {
            size_t source_index = context->graph.order[index];
            if (!weave_json_string(
                    writer,
                    context->registry.items[source_index].module_name)) {
                return 0;
            }
        }
    }
    if (!weave_json_array_end(writer) ||
        !weave_json_key(writer, "module_graph") ||
        !weave_json_array_begin(writer)) {
        return 0;
    }
    if (context->graph_loaded) {
        for (size_t order_index = 0;
             order_index < context->graph.order_count;
             ++order_index) {
            size_t source_index = context->graph.order[order_index];
            const weave_project_graph_node *node =
                &context->graph.nodes[source_index];
            if (!weave_json_object_begin(writer) ||
                !weave_json_key(writer, "module") ||
                !weave_json_string(
                    writer,
                    context->registry.items[source_index].module_name) ||
                !weave_json_key(writer, "source") ||
                !weave_json_string(
                    writer,
                    context->registry.items[source_index].logical_path) ||
                !weave_json_key(writer, "imports") ||
                !weave_json_array_begin(writer)) {
                return 0;
            }
            for (size_t edge_index = 0;
                 edge_index < node->edge_count;
                 ++edge_index) {
                if (!weave_json_string(
                        writer,
                        context->registry.items[
                            node->edges[edge_index].target].module_name)) {
                    return 0;
                }
            }
            if (!weave_json_array_end(writer) ||
                !weave_json_object_end(writer)) {
                return 0;
            }
        }
    }
    return weave_json_array_end(writer) &&
        weave_json_object_end(writer);
}

static int weave_project_protocol_render_project(
    const weave_project_protocol_context *context,
    unsigned char **bytes_out,
    size_t *length_out) {
    FILE *stream = tmpfile();
    if (stream == NULL) return 0;
    weave_json_writer writer;
    weave_json_writer_init(&writer, stream);
    int ok = weave_project_protocol_write_project(&writer, context) &&
        weave_json_writer_finish(&writer) &&
        fflush(stream) == 0 &&
        fseek(stream, 0, SEEK_END) == 0;
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
    size_t length = (size_t)end;
    while (length > 0 &&
           (bytes[length - 1] == '\n' ||
            bytes[length - 1] == '\r' ||
            bytes[length - 1] == ' ' ||
            bytes[length - 1] == '\t')) {
        --length;
    }
    *bytes_out = bytes;
    *length_out = length;
    return 1;
}

static const char *weave_project_protocol_phase_for_code(
    const unsigned char *bytes,
    size_t length,
    const char *fallback) {
    const char *text = (const char *)bytes;
    if (length == 0) return fallback;
    if (strstr(text, "\"code\": \"project.manifest.") != NULL ||
        strstr(
            text,
            "\"code\": \"driver.output-aliases-project-manifest\"") != NULL) {
        return "project-manifest";
    }
    if (strstr(text, "\"code\": \"project.source.") != NULL ||
        strstr(
            text,
            "\"code\": \"driver.output-aliases-project-source\"") != NULL) {
        return "project-sources";
    }
    if (strstr(text, "\"code\": \"project.graph.") != NULL ||
        strstr(text, "\"code\": \"project.entry.") != NULL ||
        strstr(text, "\"code\": \"project.library.") != NULL) {
        return "project-graph";
    }
    return fallback;
}

static int weave_project_protocol_write_replaced(
    FILE *stream,
    const unsigned char *bytes,
    size_t length,
    const char *replacement_phase) {
    static const char needle[] = "\"phase\": \"driver\"";
    const size_t needle_length = sizeof(needle) - 1;
    size_t offset = 0;
    while (offset < length) {
        size_t match = offset;
        while (match + needle_length <= length &&
               memcmp(bytes + match, needle, needle_length) != 0) {
            ++match;
        }
        if (match + needle_length > length) {
            return fwrite(bytes + offset, 1, length - offset, stream) ==
                length - offset;
        }
        if (fwrite(bytes + offset, 1, match - offset, stream) !=
                match - offset ||
            fprintf(
                stream,
                "\"phase\": \"%s\"",
                replacement_phase) < 0) {
            return 0;
        }
        offset = match + needle_length;
    }
    return 1;
}

static int weave_project_protocol_publish_augmented(
    FILE *stream,
    const void *opaque) {
    const weave_project_protocol_document *document = opaque;
    size_t base_length = document->base_length;
    while (base_length > 0 &&
           (document->base[base_length - 1] == '\n' ||
            document->base[base_length - 1] == '\r' ||
            document->base[base_length - 1] == ' ' ||
            document->base[base_length - 1] == '\t')) {
        --base_length;
    }
    if (base_length == 0 || document->base[base_length - 1] != '}') {
        return 1;
    }
    --base_length;
    int ok = document->replacement_phase != NULL
        ? weave_project_protocol_write_replaced(
              stream,
              document->base,
              base_length,
              document->replacement_phase)
        : fwrite(document->base, 1, base_length, stream) == base_length;
    if (!ok ||
        fputs(",\n  \"project\": ", stream) == EOF ||
        fwrite(
            document->project,
            1,
            document->project_length,
            stream) != document->project_length ||
        fputs("\n}\n", stream) == EOF) {
        return 1;
    }
    return 0;
}

static int weave_project_protocol_augment_file(
    const char *path,
    const weave_project_protocol_context *context,
    int replace_driver_phase) {
    if (path == NULL || *path == '\0') return 0;
    size_t base_length = 0;
    unsigned char *base = weave_diag_read_file(path, &base_length);
    if (base == NULL) return 1;

    unsigned char *project = NULL;
    size_t project_length = 0;
    if (!weave_project_protocol_render_project(
            context,
            &project,
            &project_length)) {
        free(base);
        return 1;
    }

    const char *phase = NULL;
    if (replace_driver_phase) {
        phase = weave_project_protocol_phase_for_code(
            base,
            base_length,
            context->resolution_phase != NULL
                ? context->resolution_phase
                : "project-manifest");
    }
    weave_project_protocol_document document = {
        .base = base,
        .base_length = base_length,
        .project = project,
        .project_length = project_length,
        .replacement_phase = phase,
    };
    int result = weave_publish_document(
        path,
        "project protocol",
        0644,
        weave_project_protocol_publish_augmented,
        &document);
    free(project);
    free(base);
    return result;
}

static const char *weave_project_protocol_option_value(
    int argc,
    char **argv,
    const char *name) {
    for (int index = 2; index + 1 < argc; ++index) {
        if (strcmp(argv[index], name) == 0) return argv[index + 1];
    }
    return NULL;
}

int weave_rt_build_main(int argc, char **argv) {
    weave_project_protocol_context context = {0};
    weave_project_protocol_prepare_build(argc, argv, &context);
    int result = weave_rt_build_main_project_protocol_legacy(argc, argv);
    if (!context.active) return result;

    const char *manifest = weave_project_protocol_option_value(
        argc, argv, "--manifest-json");
    const char *diagnostics = weave_project_protocol_option_value(
        argc, argv, "--diagnostics-json");
    const char *trace = weave_project_protocol_option_value(
        argc, argv, "--trace-json");

    int publication_failed = 0;
    if (manifest != NULL && access(manifest, F_OK) == 0) {
        publication_failed |= weave_project_protocol_augment_file(
            manifest, &context, 0) != 0;
    }
    if (diagnostics != NULL && access(diagnostics, F_OK) == 0) {
        publication_failed |= weave_project_protocol_augment_file(
            diagnostics, &context, 1) != 0;
    }
    if (trace != NULL && access(trace, F_OK) == 0) {
        publication_failed |= weave_project_protocol_augment_file(
            trace, &context, result != 0) != 0;
    }

    weave_project_protocol_context_clear(&context);
    if (publication_failed && result == 0) return WEAVEC_EXIT_PUBLISH;
    return result;
}

typedef struct weave_project_capability_document {
    const unsigned char *base;
    size_t base_length;
} weave_project_capability_document;

static int weave_project_protocol_publish_capabilities(
    FILE *stream,
    const void *opaque) {
    const weave_project_capability_document *document = opaque;
    size_t length = document->base_length;
    while (length > 0 &&
           (document->base[length - 1] == '\n' ||
            document->base[length - 1] == '\r' ||
            document->base[length - 1] == ' ' ||
            document->base[length - 1] == '\t')) {
        --length;
    }
    if (length == 0 || document->base[length - 1] != '}') return 1;
    --length;
    if (fwrite(document->base, 1, length, stream) != length) return 1;
    return fputs(
        ",\n"
        "  \"project_mode\": {\n"
        "    \"feature\": {\n"
        "      \"id\": \"project-builds\",\n"
        "      \"status\": \"experimental\",\n"
        "      \"issue\": 123\n"
        "    },\n"
        "    \"protocol\": {\n"
        "      \"id\": \"weavec-project-facts-v1\",\n"
        "      \"field\": \"project\",\n"
        "      \"extends\": [\n"
        "        \"weavec-build-manifest-v1\",\n"
        "        \"weavec-diagnostics-v1\",\n"
        "        \"weavec-compilation-trace-v1\",\n"
        "        \"weavec-semantic-index-v1\"\n"
        "      ]\n"
        "    },\n"
        "    \"commands\": [\n"
        "      \"build [--project <directory-or-manifest>]\",\n"
        "      \"analyze [--project <directory-or-manifest>] "
            "--semantic-index-json <path>\"\n"
        "    ],\n"
        "    \"manifest\": {\n"
        "      \"name\": \"weave.project\",\n"
        "      \"version\": 1,\n"
        "      \"kinds\": [\"executable\", \"library\"]\n"
        "    },\n"
        "    \"path_policy\": {\n"
        "      \"logical_project_paths\": \"relocation-stable\",\n"
        "      \"physical_paths\": \"observational\"\n"
        "    }\n"
        "  }\n"
        "}\n",
        stream) == EOF
        ? 1
        : 0;
}

int weave_rt_print_capabilities(void) {
    FILE *temporary = tmpfile();
    if (temporary == NULL) return 1;
    int saved = dup(STDOUT_FILENO);
    if (saved < 0 || dup2(fileno(temporary), STDOUT_FILENO) < 0) {
        if (saved >= 0) close(saved);
        fclose(temporary);
        return 1;
    }
    int result = weave_rt_print_capabilities_project_legacy();
    fflush(stdout);
    int restore_failed = dup2(saved, STDOUT_FILENO) < 0;
    close(saved);
    if (result != 0 || restore_failed ||
        fseek(temporary, 0, SEEK_END) != 0) {
        fclose(temporary);
        return 1;
    }
    long end = ftell(temporary);
    if (end < 0 || fseek(temporary, 0, SEEK_SET) != 0) {
        fclose(temporary);
        return 1;
    }
    unsigned char *base = malloc((size_t)end + 1);
    if (base == NULL ||
        fread(base, 1, (size_t)end, temporary) != (size_t)end) {
        free(base);
        fclose(temporary);
        return 1;
    }
    fclose(temporary);
    base[end] = '\0';
    weave_project_capability_document document = {
        .base = base,
        .base_length = (size_t)end,
    };
    int published = weave_project_protocol_publish_capabilities(
        stdout, &document);
    free(base);
    return published != 0 || fflush(stdout) != 0 ? 1 : 0;
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
        fputs(
            "weavec: semantic-index output path is invalid\n",
            stderr);
        weave_project_protocol_context_clear(&context);
        return 2;
    }
    if (weave_path_safety_aliases(output, context.manifest.path)) {
        fputs(
            "weavec: semantic-index output aliases weave.project\n",
            stderr);
        weave_project_protocol_context_clear(&context);
        return 2;
    }
    for (size_t index = 0; index < context.registry.count; ++index) {
        if (weave_path_safety_aliases(
                output,
                context.registry.items[index].physical_path)) {
            fputs(
                "weavec: semantic-index output aliases a project source\n",
                stderr);
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
            context.registry.items[
                context.graph.order[index]].logical_path;
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
    int result = weave_rt_semantic_index_main_project_legacy(
        analyze_argc, analyze);
    int restore_failed = chdir(original_directory) != 0;
    free(analyze);

    if (!restore_failed && access(output, F_OK) == 0 &&
        weave_project_protocol_augment_file(
            output, &context, 0) != 0) {
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
    return weave_project_protocol_analyze_project(
        argc, argv, &request);
}

#endif
