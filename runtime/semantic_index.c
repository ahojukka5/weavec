// SPDX-License-Identifier: Apache-2.0
//
// Compiler-owned semantic-index driver. The self-hosted frontend remains the
// authority for validation and name resolution; this file retains source spans,
// serializes compiler facts, and records call relationships from the same parser
// tree used by compilation.

#ifndef WEAVEC_SEMANTIC_INDEX_C
#define WEAVEC_SEMANTIC_INDEX_C

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

extern void *lex(const char *source, int64_t length);
extern void *parse(void *tokens);
extern void tokens_free(void *tokens);
extern void tree_free(void *tree);
extern int32_t node_kind(void *tree, int64_t index);
extern int64_t node_text_start(void *tree, int64_t index);
extern int64_t node_text_len(void *tree, int64_t index);
extern int64_t node_first_child(void *tree, int64_t index);
extern int64_t node_next_sibling(void *tree, int64_t index);
extern int32_t node_list(void);
extern int32_t node_ident(void);
extern int32_t lower_sources(
    int32_t argc,
    char **argv,
    const char *output_path,
    int64_t first_input_index);

typedef struct weave_si_sha256 {
    uint32_t state[8];
    uint64_t bits;
    unsigned char block[64];
    size_t used;
} weave_si_sha256;

typedef struct weave_si_buffer {
    char *data;
    size_t length;
    size_t capacity;
    int failed;
} weave_si_buffer;

typedef struct weave_si_source {
    const char *path;
    char *bytes;
    size_t length;
    void *tokens;
    void *tree;
    char sha256[65];
    size_t module_index;
} weave_si_source;

typedef struct weave_si_module {
    size_t source_index;
    char *name;
    size_t name_start;
    size_t name_length;
    size_t start;
    size_t end;
    int explicit_module;
    char interface_sha256[65];
    size_t *exported_symbols;
    size_t exported_count;
    size_t exported_capacity;
} weave_si_module;

typedef struct weave_si_symbol {
    size_t module_index;
    size_t source_index;
    char *kind;
    char *name;
    char *signature;
    char *summary;
    size_t start;
    size_t end;
    int is_public;
    int is_callable;
    int64_t declaration_node;
} weave_si_symbol;

typedef struct weave_si_import {
    size_t module_index;
    size_t source_index;
    char *source_module;
    char *imported_name;
    size_t imported_module_index;
    size_t symbol_index;
    size_t start;
    size_t end;
    size_t name_start;
    size_t name_end;
    const char *status;
} weave_si_import;

typedef struct weave_si_export {
    size_t module_index;
    size_t source_index;
    char *name;
    size_t symbol_index;
    size_t start;
    size_t end;
    size_t name_start;
    size_t name_end;
    const char *status;
} weave_si_export;

typedef struct weave_si_reference {
    size_t source_index;
    size_t symbol_index;
    size_t start;
    size_t end;
    const char *role;
    const char *status;
} weave_si_reference;

typedef struct weave_si_call_edge {
    size_t caller_symbol_index;
    size_t callee_symbol_index;
    size_t reference_index;
    const char *status;
} weave_si_call_edge;

typedef struct weave_si_model {
    weave_si_source *sources;
    size_t source_count;
    weave_si_module *modules;
    size_t module_count;
    size_t module_capacity;
    weave_si_symbol *symbols;
    size_t symbol_count;
    size_t symbol_capacity;
    weave_si_import *imports;
    size_t import_count;
    size_t import_capacity;
    weave_si_export *exports;
    size_t export_count;
    size_t export_capacity;
    weave_si_reference *references;
    size_t reference_count;
    size_t reference_capacity;
    weave_si_call_edge *call_edges;
    size_t call_edge_count;
    size_t call_edge_capacity;
    char source_set_sha256[65];
    char options_sha256[65];
    int body_references_complete;
    const char *status;
    const char *diagnostic_code;
    const char *diagnostic_message;
    size_t diagnostic_source;
    size_t diagnostic_start;
    size_t diagnostic_end;
} weave_si_model;

#define WEAVE_SI_NONE ((size_t)-1)

#include "semantic_index_hash.inc"
#include "semantic_index_ast.inc"
#include "semantic_index_collect.inc"
#define weave_si_collect_calls weave_si_collect_calls_base
#include "semantic_index_calls.inc"
#undef weave_si_collect_calls
#include "semantic_index_body_lookup.inc"
#include "semantic_index_body_collect.inc"
#define weave_si_publish weave_si_publish_base
#include "semantic_index_emit.inc"
#undef weave_si_publish

static int weave_si_publish(
    const char *path,
    const weave_si_model *model) {
    weave_si_model document = *model;
    if (strcmp(document.status, "incomplete") == 0 &&
        document.body_references_complete) {
        document.status = "complete";
    }
    return weave_si_publish_base(path, &document);
}

#include "semantic_index_driver.inc"

#endif
