// SPDX-License-Identifier: Apache-2.0
//
// Preserve the historical invariant that project input and protocol-output
// safety run before any incremental cache inspects or parses a manifest.

#ifndef WEAVEC_PROJECT_CACHE_OUTER_C
#define WEAVEC_PROJECT_CACHE_OUTER_C

static int weave_project_cache_preflight_manifest(
    int argc,
    char **argv,
    int *result) {
    if (argc < 2 || strcmp(argv[1], "build") != 0) return 0;

    weave_project_request request = {0};
    weave_project_error request_error = {0};
    if (!weave_project_parse_request(
            argc, argv, &request, &request_error) ||
        request.help || request.unknown_option != NULL ||
        request.source_count > 0) {
        free(request.output_paths);
        return 0;
    }

    char manifest_path[PATH_MAX];
    weave_project_error selection_error = {0};
    if (!weave_project_manifest_path(
            request.project, manifest_path, sizeof(manifest_path),
            &selection_error)) {
        free(request.output_paths);
        return 0;
    }

    size_t source_length = 0;
    unsigned char *source = weave_diag_read_file(
        manifest_path, &source_length);
    if (source == NULL) {
        free(request.output_paths);
        return 0;
    }

    size_t start = 0;
    size_t end = 0;
    weave_project_error error = {0};
    if (!weave_project_safety_utf8(
            source, source_length, &start, &end)) {
        error.code = "project.manifest.parse";
        error.message = "project manifest is not valid UTF-8";
    } else if (weave_project_safety_forbidden_nul(
                   source, source_length, &start, &end)) {
        error.code = "project.manifest.path";
        error.message = "project strings must not contain NUL";
    }
    free(source);

    if (error.code == NULL) {
        free(request.output_paths);
        return 0;
    }
    error.source = manifest_path;
    error.start = start;
    error.end = end;
    error.has_span = 1;
    *result = weave_project_publish_error(
        &error, request.diagnostics, request.trace, 2);
    free(request.output_paths);
    return 1;
}

static int weave_project_cache_has_internal_reporters(void) {
    const char *sources = getenv("WEAVEC_INTERNAL_PROJECT_SOURCES");
    const char *graph = getenv("WEAVEC_INTERNAL_PROJECT_GRAPH");
    return (sources != NULL && *sources != '\0') ||
        (graph != NULL && *graph != '\0');
}

// Name the argument that sent this build down the full protocol path, so a
// bypass report can say why the module cache did not run.
static const char *weave_project_cache_bypass_reason(int argc, char **argv) {
    for (int index = 2; index < argc; ++index) {
        if (weave_project_cache_protocol_argument(argv[index])) {
            return argv[index];
        }
    }
    return "internal-project-reporters";
}

// A requested --cache-report must always be published. Builds that ask for
// diagnostics, traces, indexes, manifests, contracts, or phase artifacts run
// through the full project protocol path, which does not use the module cache
// (see docs/incremental-project-builds.md). Report that as `bypassed` rather
// than writing nothing, which left the caller with no file and no diagnostic.
static int weave_project_cache_write_bypass_report(
    const char *path,
    const char *bypassed_by,
    int exit_code) {
    return weave_project_module_write_report(
        path, "", exit_code, NULL, 0, bypassed_by);
}

int weave_rt_build_main(int argc, char **argv) {
    weave_project_cache_options options = {0};
    if (!weave_project_cache_parse_options(argc, argv, &options)) {
        weave_project_cache_options_clear(&options);
        return 2;
    }

    int result = 0;
    if (weave_project_cache_requires_legacy_protocols(
            options.argc, options.argv) ||
        weave_project_cache_has_internal_reporters()) {
        result = weave_rt_build_main_project_cache_legacy(
            options.argc, options.argv);
        if (!weave_project_cache_write_bypass_report(
                options.report,
                weave_project_cache_bypass_reason(
                    options.argc, options.argv),
                result)) {
            fputs("weavec: cannot publish project cache report\n", stderr);
            if (result == 0) result = 2;
        }
        weave_project_cache_options_clear(&options);
        return result;
    }
    if (weave_project_cache_preflight_manifest(
            options.argc, options.argv, &result)) {
        weave_project_cache_options_clear(&options);
        return result;
    }
    weave_project_cache_options_clear(&options);
    return weave_rt_build_main_incremental_core(argc, argv);
}

#endif
