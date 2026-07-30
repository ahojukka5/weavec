// SPDX-License-Identifier: Apache-2.0
//
// Private first-error transport from the self-hosted frontend subprocess to the
// public diagnostics serializer. The transport is fixed-layout and versioned;
// language meaning remains in the self-hosted observer that supplies its fields.

#ifndef WEAVEC_SEMANTIC_DIAGNOSTIC_TRANSPORT_C
#define WEAVEC_SEMANTIC_DIAGNOSTIC_TRANSPORT_C

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#ifndef WEAVEC_SEMANTIC_DIAGNOSTIC_ENV
#define WEAVEC_SEMANTIC_DIAGNOSTIC_ENV \
    "WEAVEC_INTERNAL_SEMANTIC_DIAGNOSTIC"
#endif

#define WEAVE_SEMANTIC_DIAGNOSTIC_MAGIC UINT32_C(0x57445331)
#define WEAVE_SEMANTIC_DIAGNOSTIC_VERSION UINT32_C(1)

#define WEAVE_SEMANTIC_HAS_EXPECTED_TYPE UINT32_C(1)
#define WEAVE_SEMANTIC_HAS_ACTUAL_TYPE UINT32_C(2)
#define WEAVE_SEMANTIC_HAS_ARGUMENT_INDEX UINT32_C(4)
#define WEAVE_SEMANTIC_HAS_COUNTS UINT32_C(8)
#define WEAVE_SEMANTIC_HAS_OPERAND_ROLE UINT32_C(16)
#define WEAVE_SEMANTIC_HAS_SYMBOL UINT32_C(32)
#define WEAVE_SEMANTIC_HAS_REPAIR UINT32_C(64)

typedef struct weave_semantic_diagnostic {
    uint32_t magic;
    uint32_t version;
    uint32_t flags;
    uint32_t reserved;
    uint64_t start_byte;
    uint64_t end_byte;
    uint64_t replacement_start_byte;
    uint64_t replacement_end_byte;
    int32_t argument_index;
    int32_t expected_count;
    int32_t actual_count;
    int32_t reserved_count;
    char code[96];
    char source[PATH_MAX];
    char expected_type[32];
    char actual_type[32];
    char operand_role[32];
    char symbol[256];
    char replacement[4096];
    char repair_confidence[32];
} weave_semantic_diagnostic;

typedef struct weave_semantic_saved_env {
    int active;
    int was_set;
    char *value;
} weave_semantic_saved_env;

static int weave_semantic_begin_env(
    const char *path,
    weave_semantic_saved_env *saved) {
    memset(saved, 0, sizeof(*saved));
    const char *previous = getenv(WEAVEC_SEMANTIC_DIAGNOSTIC_ENV);
    if (previous != NULL) {
        saved->value = strdup(previous);
        if (saved->value == NULL) {
            return 0;
        }
        saved->was_set = 1;
    }
    if (setenv(WEAVEC_SEMANTIC_DIAGNOSTIC_ENV, path, 1) != 0) {
        free(saved->value);
        memset(saved, 0, sizeof(*saved));
        return 0;
    }
    saved->active = 1;
    return 1;
}

static void weave_semantic_end_env(weave_semantic_saved_env *saved) {
    if (!saved->active) {
        free(saved->value);
        memset(saved, 0, sizeof(*saved));
        return;
    }
    if (saved->was_set && saved->value != NULL) {
        (void)setenv(WEAVEC_SEMANTIC_DIAGNOSTIC_ENV, saved->value, 1);
    } else {
        (void)unsetenv(WEAVEC_SEMANTIC_DIAGNOSTIC_ENV);
    }
    free(saved->value);
    memset(saved, 0, sizeof(*saved));
}

static int weave_semantic_read_path(
    const char *path,
    weave_semantic_diagnostic *diagnostic) {
    if (path == NULL || *path == '\0' || diagnostic == NULL) {
        return 0;
    }
    FILE *stream = fopen(path, "rb");
    if (stream == NULL) {
        return 0;
    }
    weave_semantic_diagnostic value = {0};
    size_t count = fread(&value, 1, sizeof(value), stream);
    int extra = fgetc(stream);
    int failed = ferror(stream);
    if (fclose(stream) != 0) {
        failed = 1;
    }
    if (failed || count != sizeof(value) || extra != EOF ||
        value.magic != WEAVE_SEMANTIC_DIAGNOSTIC_MAGIC ||
        value.version != WEAVE_SEMANTIC_DIAGNOSTIC_VERSION ||
        value.code[0] == '\0' || value.source[0] == '\0' ||
        value.start_byte > value.end_byte) {
        return 0;
    }
    value.code[sizeof(value.code) - 1] = '\0';
    value.source[sizeof(value.source) - 1] = '\0';
    value.expected_type[sizeof(value.expected_type) - 1] = '\0';
    value.actual_type[sizeof(value.actual_type) - 1] = '\0';
    value.operand_role[sizeof(value.operand_role) - 1] = '\0';
    value.symbol[sizeof(value.symbol) - 1] = '\0';
    value.replacement[sizeof(value.replacement) - 1] = '\0';
    value.repair_confidence[sizeof(value.repair_confidence) - 1] = '\0';
    *diagnostic = value;
    return 1;
}

static int weave_semantic_read_env(
    weave_semantic_diagnostic *diagnostic) {
    return weave_semantic_read_path(
        getenv(WEAVEC_SEMANTIC_DIAGNOSTIC_ENV), diagnostic);
}

#endif
