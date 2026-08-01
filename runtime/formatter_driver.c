// SPDX-License-Identifier: Apache-2.0
//
// Parser-backed canonical surface formatter and atomic CLI driver.
//
// The formatter traverses the same S-expression tree used by the compiler. It
// owns layout, compatibility normalization, conservative local type context, and
// comment attachment. It never rewrites source with regular expressions.

#ifndef WEAVEC_FORMATTER_DRIVER_C
#define WEAVEC_FORMATTER_DRIVER_C

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

// The formatter is linked as its own translation unit directly into the
// weavec executable (see build.sh/selfhost.sh), not into runtime/portable.c,
// since it calls into the self-hosted parser and must never become part of
// the private target-program runtime. It still reuses the compiler's own
// admitted-cast registry rather than duplicating that table.
#include "json_writer.c"
#define WEAVE_CAP_ARRAY_LEN(values) (sizeof(values) / sizeof((values)[0]))
#include "capabilities_json_types.inc"
#include "capabilities_json_registry.inc"
#undef WEAVE_CAP_ARRAY_LEN

extern void *lex(const char *source, int64_t length);
extern void *parse(void *tokens);
extern void tokens_free(void *tokens);
extern void tree_free(void *tree);
extern int32_t node_kind(void *tree, int64_t index);
extern int64_t node_text_start(void *tree, int64_t index);
extern int64_t node_text_len(void *tree, int64_t index);
extern int64_t node_first_child(void *tree, int64_t index);
extern int64_t node_next_sibling(void *tree, int64_t index);
extern int64_t node_value(void *tree, int64_t index);
extern int32_t node_list(void);
extern int32_t node_ident(void);
extern int32_t node_string(void);
extern int32_t node_int(void);

typedef enum weave_fmt_type {
    WEAVE_FMT_UNKNOWN = 0,
    WEAVE_FMT_VOID,
    WEAVE_FMT_I32,
    WEAVE_FMT_I64,
    WEAVE_FMT_F32,
    WEAVE_FMT_F64,
    WEAVE_FMT_BOOL,
    WEAVE_FMT_PTR,
    WEAVE_FMT_QUBIT,
} weave_fmt_type;

typedef enum weave_fmt_binding_kind {
    WEAVE_FMT_BINDING_PARAM = 1,
    WEAVE_FMT_BINDING_LOCAL = 2,
} weave_fmt_binding_kind;

typedef struct weave_fmt_signature {
    size_t name_start;
    size_t name_length;
    weave_fmt_type return_type;
    weave_fmt_type *parameters;
    size_t parameter_count;
    int ambiguous;
} weave_fmt_signature;

typedef struct weave_fmt_binding {
    size_t name_start;
    size_t name_length;
    weave_fmt_type type;
    weave_fmt_binding_kind kind;
} weave_fmt_binding;

typedef struct weave_fmt_struct_field {
    size_t name_start;
    size_t name_length;
    weave_fmt_type type;
} weave_fmt_struct_field;

typedef struct weave_fmt_struct {
    size_t name_start;
    size_t name_length;
    weave_fmt_struct_field *fields;
    size_t field_count;
    int ambiguous;
} weave_fmt_struct;

typedef struct weave_fmt_writer {
    FILE *stream;
    int failed;
    int at_line_start;
} weave_fmt_writer;

typedef enum weave_fmt_plan_kind {
    WEAVE_FMT_PLAN_NORMAL = 0,
    WEAVE_FMT_PLAN_CALL,
    WEAVE_FMT_PLAN_OPERATOR,
    WEAVE_FMT_PLAN_CAST,
    WEAVE_FMT_PLAN_CONSTRUCTOR,
} weave_fmt_plan_kind;

typedef struct weave_fmt_plan {
    weave_fmt_plan_kind kind;
    const char *virtual_head;
    const char *virtual_second;
    weave_fmt_type encoded_type;
    const weave_fmt_signature *signature;
    const weave_fmt_struct *structure;
    int comparison_or_boolean;
} weave_fmt_plan;

typedef struct weave_fmt_context {
    const unsigned char *source;
    size_t source_length;
    void *tree;
    weave_fmt_writer writer;
    weave_fmt_signature *signatures;
    size_t signature_count;
    size_t signature_capacity;
    weave_fmt_binding *bindings;
    size_t binding_count;
    size_t binding_capacity;
    weave_fmt_struct *structs;
    size_t struct_count;
    size_t struct_capacity;
    weave_fmt_type current_return_type;
    int semantic_overflow;
    int has_struct_declarations;
} weave_fmt_context;


#include "formatter_driver_io.inc"
#include "formatter_driver_gaps.inc"
#include "formatter_driver_symbols.inc"
#include "formatter_driver_structs.inc"
#include "formatter_driver_types.inc"
#include "formatter_driver_plans.inc"
#include "formatter_driver_normalize.inc"
#include "formatter_driver_measure.inc"
#include "formatter_driver_emit_helpers.inc"
#include "formatter_driver_emit.inc"
#include "formatter_driver_cli.inc"

#endif
