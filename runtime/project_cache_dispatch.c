// SPDX-License-Identifier: Apache-2.0
//
// Keep protocol and evidence publication entirely on the established project
// driver path. Incremental cache reporting is intentionally separate from public
// diagnostics, traces, semantic indexes, manifests, contracts, and phase dumps.

#ifndef WEAVEC_PROJECT_CACHE_DISPATCH_C
#define WEAVEC_PROJECT_CACHE_DISPATCH_C

static int weave_project_cache_protocol_argument(const char *argument) {
    return strncmp(argument, "--diagnostics", 13) == 0 ||
        strncmp(argument, "--trace", 7) == 0 ||
        strncmp(argument, "--semantic-index", 16) == 0 ||
        strncmp(argument, "--manifest", 10) == 0 ||
        strncmp(argument, "--build-manifest", 16) == 0 ||
        strncmp(argument, "--audit", 7) == 0 ||
        strncmp(argument, "--contracts", 11) == 0 ||
        strncmp(argument, "--emit-", 7) == 0;
}

static int weave_project_cache_requires_legacy_protocols(
    int argc,
    char **argv) {
    for (int index = 2; index < argc; ++index) {
        if (weave_project_cache_protocol_argument(argv[index])) return 1;
    }
    return 0;
}

static int weave_project_cache_dispatch(int argc, char **argv) {
    if (weave_project_cache_requires_legacy_protocols(argc, argv)) {
        return weave_rt_build_main_project_cache_legacy(argc, argv);
    }
    return weave_rt_build_main_project_whole_cache(argc, argv);
}

#endif
