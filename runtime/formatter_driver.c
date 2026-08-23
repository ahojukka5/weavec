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
// the private target-program runtime. Language-level cast admission remains
// owned by the self-hosted frontend; this native formatter only asks that
// existing Weave policy whether a compatibility spelling is canonicalizable.
extern int32_t surface_type_i32(void);
extern int32_t surface_type_i64(void);
extern int32_t surface_type_f32(void);
extern int32_t surface_type_f64(void);
extern int32_t sop_cast_pair_supported(int32_t source, int32_t target);

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
    WEAVE_FMT_PLAN_CONTROL,
} weave_fmt_plan_kind;

typedef struct weave_fmt_plan {
    weave_fmt_plan_kind kind;
    const char *virtual_head;
    const char *virtual_second;
    int64_t callee_node;
    int skip_name_child;
    weave_fmt_type encoded_type;
    const weave_fmt_signature *signature;
    const weave_fmt_struct *structure;
    int comparison_or_boolean;
    int64_t control_cond;
    int64_t control_then;
    int64_t control_else;
    int control_variadic;
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

enum { WEAVE_FMT_COLUMN_LIMIT = 80 };

static size_t weave_fmt_column_budget(size_t indentation) {
    return WEAVE_FMT_COLUMN_LIMIT > indentation
        ? (size_t)WEAVE_FMT_COLUMN_LIMIT - indentation
        : 1;
}


#include "formatter_driver_io.inc"
#include "formatter_driver_gaps.inc"
#include "formatter_driver_symbols.inc"
#include "formatter_driver_structs.inc"
#include "formatter_driver_types.inc"
#include "formatter_driver_plans.inc"
#define weave_fmt_plan_list weave_fmt_plan_list_legacy
#include "formatter_driver_normalize.inc"
#undef weave_fmt_plan_list
#include "formatter_driver_control_plans.inc"
#include "formatter_driver_measure.inc"
#define weave_fmt_emit_control_stmts weave_fmt_emit_control_stmts_legacy
#include "formatter_driver_emit_helpers.inc"
#undef weave_fmt_emit_control_stmts
static int weave_fmt_emit_control_stmts(
    weave_fmt_context *context,
    int64_t body,
    int variadic,
    size_t indentation);
#include "formatter_driver_control_layout.inc"
#include "formatter_driver_control_spacing.inc"
#define weave_fmt_format_control weave_fmt_format_control_canonical
#include "formatter_driver_emit.inc"
#undef weave_fmt_format_control
#include "formatter_driver_cli.inc"

#endif
