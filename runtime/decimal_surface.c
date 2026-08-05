// SPDX-License-Identifier: Apache-2.0
//
// Decimal literals reuse the existing integer token and AST-node shape. Only
// the token scanner, arithmetic type seed, and float constant backend need to
// distinguish a decimal source span. The generic lexer, parser, and emitter stay
// unchanged.

#include <stdbool.h>
#include <stdint.h>

extern bool tokens_push(
    void *tokens,
    int32_t kind,
    int64_t start,
    int64_t length,
    int64_t value);
extern bool is_digit(int32_t ch);
extern int64_t parse_integer(
    const unsigned char *source,
    int64_t start,
    int64_t length);

extern int32_t node_kind(void *tree, int64_t node);
extern int32_t node_int(void);
extern int64_t node_value(void *tree, int64_t node);
extern int64_t node_text_start(void *tree, int64_t node);
extern int64_t node_text_len(void *tree, int64_t node);
extern int64_t nth_child(void *tree, int64_t node, int64_t index);

extern int32_t surface_type_unknown(void);
extern int32_t surface_type_f64(void);
extern int32_t sop_expr_type(
    void *tree,
    const unsigned char *source,
    int64_t node,
    int32_t expected);
extern void emit_node_text(
    int32_t fd,
    const unsigned char *source,
    void *tree,
    int64_t node);
extern void write_cstr(int32_t fd, const char *text);
extern void write_byte(int32_t fd, int32_t value);
extern void write_i64_dec(int32_t fd, int64_t value);

extern int32_t ctx_get_fd(void *ctx);
extern void *ctx_get_tree(void *ctx);
extern void *ctx_get_source(void *ctx);
extern int64_t ctx_alloc_temp(void *ctx);
extern void emit_type(int32_t fd, int32_t type_id);

static bool weave_decimal_span(
    const unsigned char *source,
    int64_t start,
    int64_t length) {
    int64_t index = start;
    int64_t end = start + length;
    if (index < end && source[index] == '-') {
        ++index;
    }

    int64_t whole_start = index;
    while (index < end && is_digit(source[index])) {
        ++index;
    }
    if (index == whole_start || index >= end || source[index] != '.') {
        return false;
    }

    ++index;
    int64_t fraction_start = index;
    while (index < end && is_digit(source[index])) {
        ++index;
    }
    return index == end && index > fraction_start;
}

static bool weave_decimal_node(
    const unsigned char *source,
    void *tree,
    int64_t node) {
    if (node_kind(tree, node) != node_int()) {
        return false;
    }
    return weave_decimal_span(
        source,
        node_text_start(tree, node),
        node_text_len(tree, node));
}

// Replace only the bootstrap integer scanner. A decimal remains one token_int,
// preserving every existing parser and AST contract while retaining its exact
// source spelling for typed lowering.
int64_t lex_integer(
    const unsigned char *source,
    int64_t length,
    void *tokens,
    int64_t start) {
    int64_t index = start;
    if (index < length && source[index] == '-') {
        ++index;
    }
    while (index < length && is_digit(source[index])) {
        ++index;
    }

    bool decimal = false;
    if (index + 1 < length &&
        source[index] == '.' &&
        is_digit(source[index + 1])) {
        decimal = true;
        ++index;
        while (index < length && is_digit(source[index])) {
            ++index;
        }
    }

    int64_t token_length = index - start;
    int64_t value = decimal
        ? 0
        : parse_integer(source, start, token_length);
    (void)tokens_push(tokens, 5, start, token_length, value);
    return index;
}

// Integer literals remain context-dependent. Decimal literals seed canonical
// arithmetic as f64 without introducing implicit promotion between other types.
int32_t sop_expr_seed_type(
    void *tree,
    const unsigned char *source,
    int64_t node) {
    if (node_kind(tree, node) == node_int()) {
        return weave_decimal_node(source, tree, node)
            ? surface_type_f64()
            : surface_type_unknown();
    }
    return sop_expr_type(tree, source, node, surface_type_unknown());
}

// Existing integer float constants still lower through sitofp. Decimal source
// spells a native LLVM floating constant directly; the no-op add is folded by
// the established optimization pipeline.
int64_t emit_const_float(void *ctx, int64_t node, int32_t dst_type_id) {
    int32_t fd = ctx_get_fd(ctx);
    void *tree = ctx_get_tree(ctx);
    const unsigned char *source = ctx_get_source(ctx);
    int64_t value_node = nth_child(tree, node, 1);
    int64_t temporary = ctx_alloc_temp(ctx);

    write_cstr(fd, "  %t");
    write_i64_dec(fd, temporary);

    if (weave_decimal_node(source, tree, value_node)) {
        write_cstr(fd, " = fadd ");
        emit_type(fd, dst_type_id);
        write_cstr(fd, " 0.0, ");
        emit_node_text(fd, source, tree, value_node);
        write_byte(fd, '\n');
        return temporary;
    }

    write_cstr(fd, " = sitofp i32 ");
    write_i64_dec(fd, node_value(tree, value_node));
    write_cstr(fd, " to ");
    emit_type(fd, dst_type_id);
    write_byte(fd, '\n');
    return temporary;
}
