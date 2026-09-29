// SPDX-License-Identifier: Apache-2.0
//
// Copied test and declaration names for one frontend compilation. The
// self-hosted frontend decides which names are tests, declarations, and
// exports. This storage only keeps those bytes across the per-file passes.

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct weave_test_fact {
    char *module_name;
    size_t module_len;
    char *name;
    size_t name_len;
    int64_t span_start;
    int32_t kind;
    int32_t exported;
} weave_test_fact;

static weave_test_fact *weave_test_facts;
static size_t weave_test_fact_count;
static size_t weave_test_fact_capacity;
static weave_test_fact *weave_test_exports;
static size_t weave_test_export_count;
static size_t weave_test_export_capacity;
static weave_test_fact *weave_test_locals;
static size_t weave_test_local_count;
static size_t weave_test_local_capacity;
static char *weave_test_module;
static size_t weave_test_module_len;

static char *weave_test_copy(const char *bytes, size_t length) {
    char *copy = (char *)malloc(length + 1);
    if (copy == NULL) {
        return NULL;
    }
    if (length > 0 && bytes != NULL) {
        memcpy(copy, bytes, length);
    }
    copy[length] = '\0';
    return copy;
}

static void weave_test_free_rows(
    weave_test_fact **rows,
    size_t *count,
    size_t *capacity) {
    if (*rows != NULL) {
        for (size_t index = 0; index < *count; ++index) {
            free((*rows)[index].module_name);
            free((*rows)[index].name);
        }
    }
    free(*rows);
    *rows = NULL;
    *count = 0;
    *capacity = 0;
}

static int weave_test_eq(
    const char *left,
    size_t left_len,
    const char *right,
    size_t right_len) {
    if (left_len != right_len) {
        return 0;
    }
    if (left_len == 0) {
        return 1;
    }
    return memcmp(left, right, left_len) == 0;
}

static int weave_test_grow(
    weave_test_fact **rows,
    size_t *capacity) {
    size_t next = *capacity == 0 ? 8 : *capacity * 2;
    weave_test_fact *grown = (weave_test_fact *)realloc(
        *rows, next * sizeof(*grown));
    if (grown == NULL) {
        return 0;
    }
    *rows = grown;
    *capacity = next;
    return 1;
}

static int32_t weave_test_set_module(const char *bytes, size_t length) {
    char *copy = weave_test_copy(bytes, length);
    if (copy == NULL) {
        return -1;
    }
    free(weave_test_module);
    weave_test_module = copy;
    weave_test_module_len = length;
    return 0;
}

void weave_test_semantics_reset(void) {
    weave_test_free_rows(
        &weave_test_facts, &weave_test_fact_count, &weave_test_fact_capacity);
    weave_test_free_rows(
        &weave_test_exports,
        &weave_test_export_count,
        &weave_test_export_capacity);
    weave_test_free_rows(
        &weave_test_locals,
        &weave_test_local_count,
        &weave_test_local_capacity);
    free(weave_test_module);
    weave_test_module = NULL;
    weave_test_module_len = 0;
}

int32_t weave_test_semantics_set_module_bytes(
    const char *bytes,
    int64_t start,
    int64_t length) {
    if (bytes == NULL || start < 0 || length < 0) {
        return -1;
    }
    return weave_test_set_module(bytes + start, (size_t)length);
}

int32_t weave_test_semantics_set_module_cstr(const char *text) {
    if (text == NULL) {
        return weave_test_set_module("", 0);
    }
    return weave_test_set_module(text, strlen(text));
}

static int32_t weave_test_add_row(
    weave_test_fact **rows,
    size_t *count,
    size_t *capacity,
    const char *bytes,
    int64_t start,
    int64_t length,
    int64_t span_start,
    int32_t kind,
    int32_t exported) {
    if (weave_test_module == NULL || bytes == NULL || start < 0 || length < 0) {
        return -1;
    }
    if (*count == *capacity && !weave_test_grow(rows, capacity)) {
        return -1;
    }
    char *module_name = weave_test_copy(
        weave_test_module, weave_test_module_len);
    char *name = weave_test_copy(bytes + start, (size_t)length);
    if (module_name == NULL || name == NULL) {
        free(module_name);
        free(name);
        return -1;
    }
    weave_test_fact *row = &(*rows)[*count];
    row->module_name = module_name;
    row->module_len = weave_test_module_len;
    row->name = name;
    row->name_len = (size_t)length;
    row->span_start = span_start;
    row->kind = kind;
    row->exported = exported;
    *count += 1;
    return 0;
}

int32_t weave_test_semantics_note_export(
    const char *bytes,
    int64_t start,
    int64_t length) {
    return weave_test_add_row(
        &weave_test_exports,
        &weave_test_export_count,
        &weave_test_export_capacity,
        bytes,
        start,
        length,
        0,
        0,
        1);
}

int32_t weave_test_semantics_export_noted(
    const char *bytes,
    int64_t start,
    int64_t length) {
    if (bytes == NULL || start < 0 || length < 0 || weave_test_module == NULL) {
        return 0;
    }
    for (size_t index = 0; index < weave_test_export_count; ++index) {
        weave_test_fact *row = &weave_test_exports[index];
        if (weave_test_eq(
                row->module_name,
                row->module_len,
                weave_test_module,
                weave_test_module_len) &&
            weave_test_eq(
                row->name, row->name_len, bytes + start, (size_t)length)) {
            return 1;
        }
    }
    return 0;
}

int32_t weave_test_semantics_add(
    const char *bytes,
    int64_t start,
    int64_t length,
    int64_t span_start,
    int32_t kind,
    int32_t exported) {
    return weave_test_add_row(
        &weave_test_facts,
        &weave_test_fact_count,
        &weave_test_fact_capacity,
        bytes,
        start,
        length,
        span_start,
        kind,
        exported);
}

int32_t weave_test_semantics_classify(
    const char *bytes,
    int64_t start,
    int64_t length,
    int64_t span_start) {
    if (bytes == NULL || start < 0 || length < 0 || weave_test_module == NULL) {
        return 0;
    }
    int32_t collision = 0;
    int32_t duplicate = 0;
    for (size_t index = 0; index < weave_test_fact_count; ++index) {
        weave_test_fact *row = &weave_test_facts[index];
        if (!weave_test_eq(
                row->module_name,
                row->module_len,
                weave_test_module,
                weave_test_module_len) ||
            !weave_test_eq(
                row->name, row->name_len, bytes + start, (size_t)length)) {
            continue;
        }
        if (row->kind == 1) {
            collision = 1;
        } else if (row->kind == 2 && row->span_start < span_start) {
            duplicate = 1;
        }
    }
    if (collision) {
        return 2;
    }
    if (duplicate) {
        return 1;
    }
    return 0;
}

int32_t weave_test_semantics_private_foreign(
    const char *bytes,
    int64_t start,
    int64_t length) {
    if (bytes == NULL || start < 0 || length < 0 || weave_test_module == NULL) {
        return 0;
    }
    for (size_t index = 0; index < weave_test_fact_count; ++index) {
        weave_test_fact *row = &weave_test_facts[index];
        if (row->kind != 1 || row->exported) {
            continue;
        }
        if (weave_test_eq(
                row->module_name,
                row->module_len,
                weave_test_module,
                weave_test_module_len)) {
            continue;
        }
        if (weave_test_eq(
                row->name, row->name_len, bytes + start, (size_t)length)) {
            return 1;
        }
    }
    return 0;
}

void weave_test_semantics_locals_reset(void) {
    weave_test_free_rows(
        &weave_test_locals,
        &weave_test_local_count,
        &weave_test_local_capacity);
}

int32_t weave_test_semantics_local_push(
    const char *bytes,
    int64_t start,
    int64_t length) {
    return weave_test_add_row(
        &weave_test_locals,
        &weave_test_local_count,
        &weave_test_local_capacity,
        bytes,
        start,
        length,
        0,
        0,
        0);
}

int32_t weave_test_semantics_local_contains(
    const char *bytes,
    int64_t start,
    int64_t length) {
    if (bytes == NULL || start < 0 || length < 0) {
        return 0;
    }
    for (size_t index = 0; index < weave_test_local_count; ++index) {
        weave_test_fact *row = &weave_test_locals[index];
        if (weave_test_eq(
                row->name, row->name_len, bytes + start, (size_t)length)) {
            return 1;
        }
    }
    return 0;
}
