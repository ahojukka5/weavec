// SPDX-License-Identifier: Apache-2.0
//
// Failed incremental builds may leave later module decision slots uninitialized.
// Serialize those optional fields safely instead of turning a compile error into
// a process crash while publishing failure evidence.

#ifndef WEAVEC_PROJECT_CACHE_JSON_OPTIONAL_C
#define WEAVEC_PROJECT_CACHE_JSON_OPTIONAL_C

#if defined(__APPLE__)
#undef WEAVEC_LINK_DEAD_STRIP
#define WEAVEC_LINK_DEAD_STRIP "-Wl,-dead_strip,-no_uuid"
#endif

static int weave_project_cache_json_string_optional(
    FILE *stream,
    const char *value) {
    return weave_project_cache_json_string(
        stream, value != NULL ? value : "");
}

#endif
