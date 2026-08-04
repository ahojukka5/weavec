// SPDX-License-Identifier: Apache-2.0
//
// Select one source body for per-module WIR emission while keeping every source
// in the frontend interface-validation pass.

#ifndef WEAVEC_PROJECT_CACHE_SELECTION_C
#define WEAVEC_PROJECT_CACHE_SELECTION_C

#define WEAVE_PROJECT_BODY_SOURCE_ENV "WEAVEC_INTERNAL_BODY_SOURCE_INDEX"

int weave_rt_emit_current_source_body(void) {
    const char *selected = getenv(WEAVE_PROJECT_BODY_SOURCE_ENV);
    if (selected == NULL || *selected == '\0') return 1;

    char *end = NULL;
    errno = 0;
    long long value = strtoll(selected, &end, 10);
    if (errno != 0 || end == selected || *end != '\0' || value < 0) {
        return 0;
    }
    return weave_source_location_source_index == (int64_t)value;
}

#endif
