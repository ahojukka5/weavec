// SPDX-License-Identifier: Apache-2.0
//
// Preflight safety for project mode. This wrapper runs before the project parser
// can publish diagnostics or traces, so no requested output may overwrite the
// selected manifest even when that manifest is malformed.

#ifndef WEAVEC_PROJECT_SAFETY_C
#define WEAVEC_PROJECT_SAFETY_C

static int weave_project_safety_forbidden_nul(
    const unsigned char *data,
    size_t length,
    size_t *start_out,
    size_t *end_out) {
    int in_string = 0;
    for (size_t i = 0; i < length; ++i) {
        unsigned char ch = data[i];
        if (ch == 0) {
            *start_out = i;
            *end_out = i + 1;
            return 1;
        }
        if (!in_string) {
            if (ch == '"') in_string = 1;
            if (ch == ';') {
                while (i + 1 < length && data[i + 1] != '\n') ++i;
            }
            continue;
        }
        if (ch == '"') {
            in_string = 0;
            continue;
        }
        if (ch != '\\' || i + 1 >= length) continue;
        unsigned char escaped = data[++i];
        if (escaped != 'u' || i + 4 >= length) continue;
        if (data[i + 1] == '0' && data[i + 2] == '0' &&
            data[i + 3] == '0' && data[i + 4] == '0') {
            *start_out = i - 1;
            *end_out = i + 5;
            return 1;
        }
        i += 4;
    }
    return 0;
}

static const char *weave_project_safety_output_path(
    const weave_project_request *request,
    const weave_project_manifest *manifest,
    char *resolved,
    size_t resolved_size) {
    if (request->output != NULL) return request->output;
    int written = snprintf(
        resolved,
        resolved_size,
        "%s%s%s",
        manifest->directory,
        strcmp(manifest->directory, "/") == 0 ? "" : "/",
        manifest->output);
    return written >= 0 && (size_t)written < resolved_size ? resolved : NULL;
}

static int weave_project_safety_alias_error(
    const weave_project_request *request,
    const char *manifest_path,
    const char *conflict) {
    weave_project_error error = {
        .code = "driver.output-aliases-project-manifest",
        .message = "an output path aliases the selected project manifest",
        .source = conflict,
    };
    const char *diagnostics = request->diagnostics;
    const char *trace = request->trace;
    if (diagnostics != NULL &&
        weave_path_safety_aliases(diagnostics, manifest_path)) {
        diagnostics = NULL;
    }
    if (trace != NULL && weave_path_safety_aliases(trace, manifest_path)) {
        trace = NULL;
    }
    return weave_project_publish_error(&error, diagnostics, trace, 2);
}

int weave_rt_build_main(int argc, char **argv) {
    if (argc < 2 || strcmp(argv[1], "build") != 0) {
        return weave_rt_build_main_project_legacy(argc, argv);
    }

    weave_project_request request = {0};
    weave_project_error request_error = {0};
    if (!weave_project_parse_request(argc, argv, &request, &request_error) ||
        request.help || request.unknown_option != NULL ||
        request.source_count > 0) {
        free(request.output_paths);
        return weave_rt_build_main_project_legacy(argc, argv);
    }

    char manifest_path[PATH_MAX];
    weave_project_error selection_error = {0};
    if (!weave_project_manifest_path(
            request.project, manifest_path, sizeof(manifest_path),
            &selection_error)) {
        free(request.output_paths);
        return weave_rt_build_main_project_legacy(argc, argv);
    }

    const char *conflict = NULL;
    if (weave_project_outputs_alias_manifest(
            &request, manifest_path, &conflict)) {
        int result = weave_project_safety_alias_error(
            &request, manifest_path, conflict);
        free(request.output_paths);
        return result;
    }

    size_t source_length = 0;
    unsigned char *source = weave_diag_read_file(manifest_path, &source_length);
    if (source != NULL) {
        size_t start = 0;
        size_t end = 0;
        if (weave_project_safety_forbidden_nul(
                source, source_length, &start, &end)) {
            weave_project_error error = {
                .code = "project.manifest.path",
                .message = "project strings must not contain NUL",
                .source = manifest_path,
                .start = start,
                .end = end,
                .has_span = 1,
            };
            int result = weave_project_publish_error(
                &error, request.diagnostics, request.trace, 2);
            free(source);
            free(request.output_paths);
            return result;
        }
        free(source);
    }

    weave_project_manifest manifest = {0};
    weave_project_error parse_error = {0};
    if (weave_project_load(manifest_path, &manifest, &parse_error)) {
        char resolved[PATH_MAX];
        const char *output = weave_project_safety_output_path(
            &request, &manifest, resolved, sizeof(resolved));
        if (output != NULL &&
            weave_path_safety_aliases(output, manifest.path)) {
            int result = weave_project_safety_alias_error(
                &request, manifest.path, output);
            weave_project_manifest_clear(&manifest);
            free(request.output_paths);
            return result;
        }
    }
    weave_project_manifest_clear(&manifest);
    free(request.output_paths);
    return weave_rt_build_main_project_legacy(argc, argv);
}

#endif
