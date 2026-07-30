// SPDX-License-Identifier: Apache-2.0
//
// Enable the private semantic sidecar only around diagnostics-enabled builds.
// The wrapped diagnostics facade remains responsible for stable exits, stderr,
// and transactional publication.

#ifndef WEAVEC_SEMANTIC_DIAGNOSTIC_WRAPPER_C
#define WEAVEC_SEMANTIC_DIAGNOSTIC_WRAPPER_C

static int weave_semantic_has_diagnostics_option(int argc, char **argv) {
    for (int index = 2; index < argc; ++index) {
        if (strcmp(argv[index], "--diagnostics-json") == 0) {
            return 1;
        }
    }
    return 0;
}

int weave_rt_build_main_diagnostics_legacy(int argc, char **argv) {
    if (!weave_semantic_has_diagnostics_option(argc, argv)) {
        return weave_rt_build_main_diagnostics_core(argc, argv);
    }

    const char *root = getenv("TMPDIR");
    if (root == NULL || *root == '\0') {
        root = "/tmp";
    }
    char path[PATH_MAX];
    if (snprintf(
            path, sizeof(path), "%s/weavec-semantic-diagnostic-XXXXXX",
            root) >= (int)sizeof(path)) {
        return weave_rt_build_main_diagnostics_core(argc, argv);
    }
    int fd = mkstemp(path);
    if (fd < 0) {
        return weave_rt_build_main_diagnostics_core(argc, argv);
    }
    close(fd);
    unlink(path);

    weave_semantic_saved_env saved = {0};
    if (!weave_semantic_begin_env(path, &saved)) {
        unlink(path);
        return weave_rt_build_main_diagnostics_core(argc, argv);
    }
    int result = weave_rt_build_main_diagnostics_core(argc, argv);
    weave_semantic_end_env(&saved);
    unlink(path);
    return result;
}

#endif
