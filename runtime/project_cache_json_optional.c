// SPDX-License-Identifier: Apache-2.0
//
// Failed incremental builds may leave later module decision slots uninitialized.
// Serialize those optional fields safely instead of turning a compile error into
// a process crash while publishing failure evidence.

#ifndef WEAVEC_PROJECT_CACHE_JSON_OPTIONAL_C
#define WEAVEC_PROJECT_CACHE_JSON_OPTIONAL_C

static int weave_project_cache_json_string_optional(
    FILE *stream,
    const char *value) {
    return weave_project_cache_json_string(
        stream, value != NULL ? value : "");
}

#endif
