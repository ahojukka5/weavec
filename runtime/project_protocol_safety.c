// SPDX-License-Identifier: Apache-2.0
//
// Preserve project input files when the protocol facade observes a rejected
// build. The existing project-safety wrapper owns the diagnostic; this outer
// guard only prevents the additive post-processor from reopening an aliased
// manifest after that rejection.

#ifndef WEAVEC_PROJECT_PROTOCOL_SAFETY_C
#define WEAVEC_PROJECT_PROTOCOL_SAFETY_C

static int weave_project_protocol_manifest_alias(
    int argc,
    char **argv) {
    if (argc < 2 || strcmp(argv[1], "build") != 0) return 0;

    weave_project_request request = {0};
    weave_project_error request_error = {0};
    if (!weave_project_parse_request(
            argc,
            argv,
            &request,
            &request_error) ||
        request.help ||
        request.unknown_option != NULL ||
        request.source_count > 0) {
        free(request.output_paths);
        return 0;
    }

    char manifest_path[PATH_MAX];
    weave_project_error selection_error = {0};
    if (!weave_project_manifest_path(
            request.project,
            manifest_path,
            sizeof(manifest_path),
            &selection_error)) {
        free(request.output_paths);
        return 0;
    }

    const char *conflict = NULL;
    int aliases = weave_project_outputs_alias_manifest(
        &request,
        manifest_path,
        &conflict);
    free(request.output_paths);
    return aliases;
}

int weave_rt_build_main(int argc, char **argv) {
    if (weave_project_protocol_manifest_alias(argc, argv)) {
        return weave_rt_build_main_project_protocol_legacy(argc, argv);
    }
    return weave_rt_build_main_project_facts_legacy(argc, argv);
}

#endif
