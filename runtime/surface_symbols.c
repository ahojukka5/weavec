// SPDX-License-Identifier: Apache-2.0
//
// Storage for compiler-owned surface semantic facts. This file deliberately
// knows nothing about Weave syntax: the self-hosted frontend assigns type codes,
// decides which declarations and bindings exist, and performs all semantic
// validation. Host C only copies names so facts survive per-file parser teardown.

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#define WEAVEC_SURFACE_MAX_SYMBOLS 4096
#define WEAVEC_SURFACE_MAX_PARAMS 64
#define WEAVEC_SURFACE_MAX_LOCALS 4096

typedef struct {
    char *name;
    int64_t name_length;
    int32_t return_type;
    int32_t parameter_count;
    int32_t parameter_types[WEAVEC_SURFACE_MAX_PARAMS];
} weave_surface_symbol;

typedef struct {
    char *name;
    int64_t name_length;
    int32_t type;
} weave_surface_local;

static weave_surface_symbol weave_surface_symbols[WEAVEC_SURFACE_MAX_SYMBOLS];
static int32_t weave_surface_symbol_count;
static int32_t weave_surface_symbol_being_built = -1;
static weave_surface_local weave_surface_locals[WEAVEC_SURFACE_MAX_LOCALS];
static int32_t weave_surface_local_count;
static int32_t weave_surface_return_type;
static int32_t weave_surface_error;

static char *weave_surface_copy_slice(
    const char *source,
    int64_t start,
    int64_t length) {
    if (source == NULL || start < 0 || length <= 0 ||
        (uint64_t)length > (uint64_t)SIZE_MAX - 1) {
        return NULL;
    }
    char *copy = (char *)malloc((size_t)length + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, source + start, (size_t)length);
    copy[length] = '\0';
    return copy;
}

static int weave_surface_slice_equal(
    const char *stored,
    int64_t stored_length,
    const char *source,
    int64_t start,
    int64_t length) {
    if (stored == NULL || source == NULL || start < 0 || length < 0 ||
        stored_length != length) {
        return 0;
    }
    return memcmp(stored, source + start, (size_t)length) == 0;
}

void weave_surface_symbols_reset(void) {
    for (int32_t index = 0; index < weave_surface_symbol_count; ++index) {
        free(weave_surface_symbols[index].name);
        weave_surface_symbols[index].name = NULL;
    }
    for (int32_t index = 0; index < weave_surface_local_count; ++index) {
        free(weave_surface_locals[index].name);
        weave_surface_locals[index].name = NULL;
    }
    weave_surface_symbol_count = 0;
    weave_surface_symbol_being_built = -1;
    weave_surface_local_count = 0;
    weave_surface_return_type = 0;
    weave_surface_error = 0;
}

int32_t weave_surface_symbol_begin(
    const char *source,
    int64_t start,
    int64_t length,
    int32_t return_type) {
    if (return_type <= 0 ||
        weave_surface_symbol_count >= WEAVEC_SURFACE_MAX_SYMBOLS) {
        return -1;
    }
    for (int32_t index = 0; index < weave_surface_symbol_count; ++index) {
        if (weave_surface_slice_equal(
                weave_surface_symbols[index].name,
                weave_surface_symbols[index].name_length,
                source,
                start,
                length)) {
            return -2;
        }
    }
    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    int32_t index = weave_surface_symbol_count++;
    weave_surface_symbols[index].name = name;
    weave_surface_symbols[index].name_length = length;
    weave_surface_symbols[index].return_type = return_type;
    weave_surface_symbols[index].parameter_count = 0;
    weave_surface_symbol_being_built = index;
    return index;
}

int32_t weave_surface_symbol_add_parameter(int32_t type) {
    if (weave_surface_symbol_being_built < 0 || type <= 0) {
        return -1;
    }
    weave_surface_symbol *symbol =
        &weave_surface_symbols[weave_surface_symbol_being_built];
    if (symbol->parameter_count >= WEAVEC_SURFACE_MAX_PARAMS) {
        return -1;
    }
    symbol->parameter_types[symbol->parameter_count++] = type;
    return 0;
}

static int32_t weave_surface_symbol_find(
    const char *source,
    int64_t start,
    int64_t length) {
    for (int32_t index = 0; index < weave_surface_symbol_count; ++index) {
        if (weave_surface_slice_equal(
                weave_surface_symbols[index].name,
                weave_surface_symbols[index].name_length,
                source,
                start,
                length)) {
            return index;
        }
    }
    return -1;
}

int32_t weave_surface_symbol_return_type(
    const char *source,
    int64_t start,
    int64_t length) {
    int32_t index = weave_surface_symbol_find(source, start, length);
    return index < 0 ? 0 : weave_surface_symbols[index].return_type;
}

int32_t weave_surface_symbol_parameter_count(
    const char *source,
    int64_t start,
    int64_t length) {
    int32_t index = weave_surface_symbol_find(source, start, length);
    return index < 0 ? -1 : weave_surface_symbols[index].parameter_count;
}

int32_t weave_surface_symbol_parameter_type(
    const char *source,
    int64_t start,
    int64_t length,
    int32_t parameter_index) {
    int32_t index = weave_surface_symbol_find(source, start, length);
    if (index < 0 || parameter_index < 0 ||
        parameter_index >= weave_surface_symbols[index].parameter_count) {
        return 0;
    }
    return weave_surface_symbols[index].parameter_types[parameter_index];
}

void weave_surface_locals_reset(void) {
    for (int32_t index = 0; index < weave_surface_local_count; ++index) {
        free(weave_surface_locals[index].name);
        weave_surface_locals[index].name = NULL;
    }
    weave_surface_local_count = 0;
    weave_surface_return_type = 0;
}

int32_t weave_surface_local_add(
    const char *source,
    int64_t start,
    int64_t length,
    int32_t type) {
    if (type <= 0 || weave_surface_local_count >= WEAVEC_SURFACE_MAX_LOCALS) {
        return -1;
    }
    for (int32_t index = 0; index < weave_surface_local_count; ++index) {
        if (weave_surface_slice_equal(
                weave_surface_locals[index].name,
                weave_surface_locals[index].name_length,
                source,
                start,
                length)) {
            weave_surface_locals[index].type = type;
            return 0;
        }
    }
    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    int32_t index = weave_surface_local_count++;
    weave_surface_locals[index].name = name;
    weave_surface_locals[index].name_length = length;
    weave_surface_locals[index].type = type;
    return 0;
}

int32_t weave_surface_local_type(
    const char *source,
    int64_t start,
    int64_t length) {
    for (int32_t index = weave_surface_local_count - 1; index >= 0; --index) {
        if (weave_surface_slice_equal(
                weave_surface_locals[index].name,
                weave_surface_locals[index].name_length,
                source,
                start,
                length)) {
            return weave_surface_locals[index].type;
        }
    }
    return 0;
}

void weave_surface_set_return_type(int32_t type) {
    weave_surface_return_type = type;
}

int32_t weave_surface_get_return_type(void) {
    return weave_surface_return_type;
}

void weave_surface_set_error(void) {
    weave_surface_error = 1;
}

int32_t weave_surface_has_error(void) {
    return weave_surface_error;
}
