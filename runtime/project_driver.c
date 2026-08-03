// SPDX-License-Identifier: Apache-2.0
//
// Final project-mode build boundary. This layer owns project selection and the
// version-1 weave.project structural contract. Source enumeration and module
// graph construction are deliberately left to the next project-system slices.

#ifndef WEAVEC_PROJECT_DRIVER_C
#define WEAVEC_PROJECT_DRIVER_C

#include <ctype.h>
#include <stdint.h>

#define WEAVE_PROJECT_MANIFEST_NAME "weave.project"
#define WEAVE_PROJECT_MAX_IDENTIFIER 255

typedef enum weave_project_token_kind {
    WEAVE_PROJECT_TOKEN_EOF = 0,
    WEAVE_PROJECT_TOKEN_LPAREN,
    WEAVE_PROJECT_TOKEN_RPAREN,
    WEAVE_PROJECT_TOKEN_ATOM,
    WEAVE_PROJECT_TOKEN_STRING,
} weave_project_token_kind;

typedef struct weave_project_token {
    weave_project_token_kind kind;
    size_t start;
    size_t end;
    char *text;
} weave_project_token;

typedef struct weave_project_error {
    const char *code;
    const char *message;
    const char *source;
    size_t start;
    size_t end;
    int has_span;
} weave_project_error;

typedef struct weave_project_lexer {
    const unsigned char *data;
    size_t length;
    size_t offset;
} weave_project_lexer;

typedef struct weave_project_parser {
    weave_project_lexer lexer;
    weave_project_token lookahead;
    int has_lookahead;
    weave_project_error *error;
} weave_project_parser;

typedef struct weave_project_manifest {
    char path[PATH_MAX];
    char directory[PATH_MAX];
    char name[WEAVE_PROJECT_MAX_IDENTIFIER + 1];
    char kind[16];
    char entry[WEAVE_PROJECT_MAX_IDENTIFIER + 1];
    char output[PATH_MAX];
    char **source_roots;
    size_t source_root_count;
    size_t source_root_capacity;
    char **test_roots;
    size_t test_root_count;
    size_t test_root_capacity;
} weave_project_manifest;

typedef struct weave_project_request {
    const char *project;
    const char *output;
    const char *diagnostics;
    const char *trace;
    const char **output_paths;
    int output_path_count;
    int source_count;
    int help;
    const char *unknown_option;
} weave_project_request;

static void weave_project_usage(FILE *stream) {
    fputs(
        "usage: weavec build <input.weave> [input2.weave ...] -o <program>\n"
        "       weavec build [--project <directory-or-manifest>] [-o <program>]\n"
        "                    [--diagnostics-json <path>] [--trace-json <path>]\n"
        "                    [other existing build options]\n"
        "\n"
        "With explicit source arguments, project discovery is disabled. With no\n"
        "sources, --project selects a directory or weave.project file; otherwise\n"
        "the nearest weave.project is discovered from the working directory.\n",
        stream);
}

static int weave_project_fail(
    weave_project_error *error,
    const char *code,
    const char *message,
    size_t start,
    size_t end,
    int has_span) {
    if (error != NULL && error->code == NULL) {
        error->code = code;
        error->message = message;
        error->start = start;
        error->end = end;
        error->has_span = has_span;
    }
    return 0;
}

static void weave_project_token_clear(weave_project_token *token) {
    free(token->text);
    memset(token, 0, sizeof(*token));
}

static int weave_project_hex(unsigned char ch) {
    if (ch >= '0' && ch <= '9') return (int)(ch - '0');
    if (ch >= 'a' && ch <= 'f') return (int)(ch - 'a') + 10;
    if (ch >= 'A' && ch <= 'F') return (int)(ch - 'A') + 10;
    return -1;
}

static int weave_project_decode_hex4(
    const unsigned char *data,
    size_t length,
    size_t offset,
    uint32_t *value) {
    if (offset + 4 > length) return 0;
    uint32_t result = 0;
    for (size_t i = 0; i < 4; ++i) {
        int digit = weave_project_hex(data[offset + i]);
        if (digit < 0) return 0;
        result = result * 16u + (uint32_t)digit;
    }
    *value = result;
    return 1;
}

static int weave_project_append_utf8(char *out, size_t *used, uint32_t value) {
    if (value <= 0x7fu) {
        out[(*used)++] = (char)value;
    } else if (value <= 0x7ffu) {
        out[(*used)++] = (char)(0xc0u | (value >> 6));
        out[(*used)++] = (char)(0x80u | (value & 0x3fu));
    } else if (value <= 0xffffu) {
        out[(*used)++] = (char)(0xe0u | (value >> 12));
        out[(*used)++] = (char)(0x80u | ((value >> 6) & 0x3fu));
        out[(*used)++] = (char)(0x80u | (value & 0x3fu));
    } else if (value <= 0x10ffffu) {
        out[(*used)++] = (char)(0xf0u | (value >> 18));
        out[(*used)++] = (char)(0x80u | ((value >> 12) & 0x3fu));
        out[(*used)++] = (char)(0x80u | ((value >> 6) & 0x3fu));
        out[(*used)++] = (char)(0x80u | (value & 0x3fu));
    } else {
        return 0;
    }
    return 1;
}

static int weave_project_lex_string(
    weave_project_lexer *lexer,
    weave_project_token *token,
    weave_project_error *error) {
    size_t start = lexer->offset++;
    char *decoded = malloc(lexer->length - start + 1);
    if (decoded == NULL) {
        return weave_project_fail(
            error, "driver.out-of-memory",
            "out of memory while reading project manifest", start, start + 1, 1);
    }
    size_t used = 0;
    while (lexer->offset < lexer->length) {
        unsigned char ch = lexer->data[lexer->offset++];
        if (ch == '"') {
            decoded[used] = '\0';
            token->kind = WEAVE_PROJECT_TOKEN_STRING;
            token->start = start;
            token->end = lexer->offset;
            token->text = decoded;
            return 1;
        }
        if (ch < 0x20u) {
            free(decoded);
            return weave_project_fail(
                error, "project.manifest.parse",
                "unescaped control byte in project string",
                lexer->offset - 1, lexer->offset, 1);
        }
        if (ch != '\\') {
            decoded[used++] = (char)ch;
            continue;
        }
        if (lexer->offset >= lexer->length) {
            free(decoded);
            return weave_project_fail(
                error, "project.manifest.parse",
                "unterminated escape in project string", start, lexer->length, 1);
        }
        unsigned char escaped = lexer->data[lexer->offset++];
        switch (escaped) {
            case '"': decoded[used++] = '"'; break;
            case '\\': decoded[used++] = '\\'; break;
            case '/': decoded[used++] = '/'; break;
            case 'b': decoded[used++] = '\b'; break;
            case 'f': decoded[used++] = '\f'; break;
            case 'n': decoded[used++] = '\n'; break;
            case 'r': decoded[used++] = '\r'; break;
            case 't': decoded[used++] = '\t'; break;
            case 'u': {
                uint32_t value = 0;
                size_t digits = lexer->offset;
                if (!weave_project_decode_hex4(
                        lexer->data, lexer->length, digits, &value)) {
                    free(decoded);
                    return weave_project_fail(
                        error, "project.manifest.parse",
                        "invalid Unicode escape in project string",
                        digits, digits + 4 <= lexer->length ? digits + 4 : lexer->length,
                        1);
                }
                lexer->offset += 4;
                if (value >= 0xd800u && value <= 0xdbffu) {
                    if (lexer->offset + 6 > lexer->length ||
                        lexer->data[lexer->offset] != '\\' ||
                        lexer->data[lexer->offset + 1] != 'u') {
                        free(decoded);
                        return weave_project_fail(
                            error, "project.manifest.parse",
                            "high surrogate is not followed by a low surrogate",
                            digits, lexer->offset, 1);
                    }
                    uint32_t low = 0;
                    if (!weave_project_decode_hex4(
                            lexer->data, lexer->length,
                            lexer->offset + 2, &low) ||
                        low < 0xdc00u || low > 0xdfffu) {
                        free(decoded);
                        return weave_project_fail(
                            error, "project.manifest.parse",
                            "invalid low surrogate in project string",
                            lexer->offset, lexer->offset + 6, 1);
                    }
                    lexer->offset += 6;
                    value = 0x10000u + ((value - 0xd800u) << 10) +
                        (low - 0xdc00u);
                } else if (value >= 0xdc00u && value <= 0xdfffu) {
                    free(decoded);
                    return weave_project_fail(
                        error, "project.manifest.parse",
                        "unexpected low surrogate in project string",
                        digits, lexer->offset, 1);
                }
                if (!weave_project_append_utf8(decoded, &used, value)) {
                    free(decoded);
                    return weave_project_fail(
                        error, "project.manifest.parse",
                        "invalid Unicode scalar in project string",
                        digits, lexer->offset, 1);
                }
                break;
            }
            default:
                free(decoded);
                return weave_project_fail(
                    error, "project.manifest.parse",
                    "invalid escape in project string",
                    lexer->offset - 2, lexer->offset, 1);
        }
    }
    free(decoded);
    return weave_project_fail(
        error, "project.manifest.parse", "unterminated project string",
        start, lexer->length, 1);
}

static int weave_project_lex_next(
    weave_project_lexer *lexer,
    weave_project_token *token,
    weave_project_error *error) {
    memset(token, 0, sizeof(*token));
    while (lexer->offset < lexer->length) {
        unsigned char ch = lexer->data[lexer->offset];
        if (isspace(ch)) {
            ++lexer->offset;
            continue;
        }
        if (ch == ';') {
            while (lexer->offset < lexer->length &&
                   lexer->data[lexer->offset] != '\n') {
                ++lexer->offset;
            }
            continue;
        }
        break;
    }
    if (lexer->offset >= lexer->length) {
        token->kind = WEAVE_PROJECT_TOKEN_EOF;
        token->start = token->end = lexer->length;
        return 1;
    }

    size_t start = lexer->offset;
    unsigned char ch = lexer->data[lexer->offset];
    if (ch == '(' || ch == ')') {
        ++lexer->offset;
        token->kind = ch == '('
            ? WEAVE_PROJECT_TOKEN_LPAREN : WEAVE_PROJECT_TOKEN_RPAREN;
        token->start = start;
        token->end = lexer->offset;
        return 1;
    }
    if (ch == '"') {
        return weave_project_lex_string(lexer, token, error);
    }

    while (lexer->offset < lexer->length) {
        ch = lexer->data[lexer->offset];
        if (isspace(ch) || ch == '(' || ch == ')' || ch == ';') break;
        if (ch == '"') {
            return weave_project_fail(
                error, "project.manifest.parse",
                "quote is not allowed inside a project atom",
                lexer->offset, lexer->offset + 1, 1);
        }
        ++lexer->offset;
    }
    if (lexer->offset == start) {
        return weave_project_fail(
            error, "project.manifest.parse", "unexpected project byte",
            start, start + 1, 1);
    }
    size_t length = lexer->offset - start;
    char *atom = malloc(length + 1);
    if (atom == NULL) {
        return weave_project_fail(
            error, "driver.out-of-memory",
            "out of memory while reading project manifest",
            start, lexer->offset, 1);
    }
    memcpy(atom, lexer->data + start, length);
    atom[length] = '\0';
    token->kind = WEAVE_PROJECT_TOKEN_ATOM;
    token->start = start;
    token->end = lexer->offset;
    token->text = atom;
    return 1;
}

static weave_project_token *weave_project_peek(weave_project_parser *parser) {
    if (!parser->has_lookahead) {
        if (!weave_project_lex_next(
                &parser->lexer, &parser->lookahead, parser->error)) {
            return NULL;
        }
        parser->has_lookahead = 1;
    }
    return &parser->lookahead;
}

static int weave_project_take(
    weave_project_parser *parser,
    weave_project_token *token) {
    weave_project_token *next = weave_project_peek(parser);
    if (next == NULL) return 0;
    *token = *next;
    memset(&parser->lookahead, 0, sizeof(parser->lookahead));
    parser->has_lookahead = 0;
    return 1;
}

static int weave_project_expect(
    weave_project_parser *parser,
    weave_project_token_kind kind,
    const char *code,
    const char *message,
    weave_project_token *token) {
    weave_project_token value = {0};
    if (!weave_project_take(parser, &value)) return 0;
    if (value.kind != kind) {
        int result = weave_project_fail(
            parser->error, code, message, value.start, value.end, 1);
        weave_project_token_clear(&value);
        return result;
    }
    if (token != NULL) {
        *token = value;
    } else {
        weave_project_token_clear(&value);
    }
    return 1;
}

static int weave_project_identifier(const char *value) {
    if (value == NULL || !isalpha((unsigned char)value[0])) return 0;
    size_t length = strlen(value);
    if (length > WEAVE_PROJECT_MAX_IDENTIFIER) return 0;
    for (size_t i = 1; i < length; ++i) {
        unsigned char ch = (unsigned char)value[i];
        if (!isalnum(ch) && ch != '_' && ch != '-') return 0;
    }
    return 1;
}

static int weave_project_root_path(const char *value) {
    if (value == NULL || *value == '\0' || strchr(value, '\\') != NULL ||
        value[0] == '/' ||
        (isalpha((unsigned char)value[0]) && value[1] == ':')) {
        return 0;
    }
    const char *part = value;
    for (const char *cursor = value;; ++cursor) {
        if (*cursor == '/' || *cursor == '\0') {
            size_t length = (size_t)(cursor - part);
            if (length == 0 ||
                (length == 1 && part[0] == '.') ||
                (length == 2 && part[0] == '.' && part[1] == '.')) {
                return 0;
            }
            if (*cursor == '\0') break;
            part = cursor + 1;
        }
    }
    return 1;
}

static int weave_project_output_name(const char *value) {
    return value != NULL && *value != '\0' && strcmp(value, ".") != 0 &&
        strcmp(value, "..") != 0 && strchr(value, '/') == NULL &&
        strchr(value, '\\') == NULL;
}

static int weave_project_roots_overlap(const char *left, const char *right) {
    size_t left_length = strlen(left);
    size_t right_length = strlen(right);
    if (strcmp(left, right) == 0) return 1;
    if (left_length < right_length &&
        memcmp(left, right, left_length) == 0 && right[left_length] == '/') {
        return 1;
    }
    return right_length < left_length &&
        memcmp(right, left, right_length) == 0 && left[right_length] == '/';
}

static int weave_project_root_compare(const void *left, const void *right) {
    const char *const *left_value = left;
    const char *const *right_value = right;
    return strcmp(*left_value, *right_value);
}

static int weave_project_append_root(
    char ***roots,
    size_t *count,
    size_t *capacity,
    const char *value) {
    if (*count == *capacity) {
        size_t new_capacity = *capacity == 0 ? 4 : *capacity * 2;
        char **new_roots = realloc(*roots, new_capacity * sizeof(**roots));
        if (new_roots == NULL) return 0;
        *roots = new_roots;
        *capacity = new_capacity;
    }
    (*roots)[*count] = strdup(value);
    if ((*roots)[*count] == NULL) return 0;
    ++*count;
    return 1;
}

static void weave_project_manifest_clear(weave_project_manifest *manifest) {
    for (size_t i = 0; i < manifest->source_root_count; ++i) {
        free(manifest->source_roots[i]);
    }
    for (size_t i = 0; i < manifest->test_root_count; ++i) {
        free(manifest->test_roots[i]);
    }
    free(manifest->source_roots);
    free(manifest->test_roots);
    memset(manifest, 0, sizeof(*manifest));
}

static int weave_project_field_end(weave_project_parser *parser) {
    return weave_project_expect(
        parser, WEAVE_PROJECT_TOKEN_RPAREN,
        "project.manifest.field-shape",
        "project field has an invalid shape", NULL);
}

static int weave_project_parse_roots(
    weave_project_parser *parser,
    weave_project_manifest *manifest,
    int tests,
    weave_project_token field) {
    size_t before = tests
        ? manifest->test_root_count : manifest->source_root_count;
    for (;;) {
        weave_project_token *next = weave_project_peek(parser);
        if (next == NULL) return 0;
        if (next->kind == WEAVE_PROJECT_TOKEN_RPAREN) break;
        weave_project_token value = {0};
        if (!weave_project_expect(
                parser, WEAVE_PROJECT_TOKEN_STRING,
                "project.manifest.field-shape",
                "project root values must be strings", &value)) {
            return 0;
        }
        if (!weave_project_root_path(value.text)) {
            int result = weave_project_fail(
                parser->error, "project.manifest.path",
                "project root is not a canonical relative path",
                value.start, value.end, 1);
            weave_project_token_clear(&value);
            return result;
        }
        int appended = tests
            ? weave_project_append_root(
                &manifest->test_roots, &manifest->test_root_count,
                &manifest->test_root_capacity, value.text)
            : weave_project_append_root(
                &manifest->source_roots, &manifest->source_root_count,
                &manifest->source_root_capacity, value.text);
        if (!appended) {
            weave_project_token_clear(&value);
            return weave_project_fail(
                parser->error, "driver.out-of-memory",
                "out of memory while reading project roots",
                field.start, field.end, 1);
        }
        weave_project_token_clear(&value);
    }
    if (!tests && manifest->source_root_count == before) {
        return weave_project_fail(
            parser->error, "project.manifest.field-shape",
            "source-roots requires at least one path",
            field.start, field.end, 1);
    }
    return weave_project_field_end(parser);
}

static int weave_project_copy_token(
    char *destination,
    size_t destination_size,
    const weave_project_token *token,
    weave_project_error *error,
    const char *code,
    const char *message) {
    if (snprintf(destination, destination_size, "%s", token->text) >=
        (int)destination_size) {
        return weave_project_fail(
            error, code, message, token->start, token->end, 1);
    }
    return 1;
}

static int weave_project_parse_document(
    const unsigned char *data,
    size_t length,
    weave_project_manifest *manifest,
    weave_project_error *error) {
    weave_project_parser parser = {
        .lexer = {.data = data, .length = length, .offset = 0},
        .error = error,
    };
    weave_project_token root_open = {0};
    weave_project_token root_head = {0};
    if (!weave_project_expect(
            &parser, WEAVE_PROJECT_TOKEN_LPAREN,
            "project.manifest.root",
            "project manifest root must be a list", &root_open) ||
        !weave_project_expect(
            &parser, WEAVE_PROJECT_TOKEN_ATOM,
            "project.manifest.root",
            "project manifest root must have a head", &root_head)) {
        weave_project_token_clear(&root_open);
        weave_project_token_clear(&root_head);
        return 0;
    }
    if (strcmp(root_head.text, "weave-project") != 0) {
        weave_project_fail(
            error, "project.manifest.root",
            "project manifest root must be weave-project",
            root_head.start, root_head.end, 1);
        weave_project_token_clear(&root_open);
        weave_project_token_clear(&root_head);
        return 0;
    }

    enum {
        SEEN_FORMAT = 1 << 0,
        SEEN_NAME = 1 << 1,
        SEEN_KIND = 1 << 2,
        SEEN_SOURCE_ROOTS = 1 << 3,
        SEEN_TEST_ROOTS = 1 << 4,
        SEEN_ENTRY = 1 << 5,
        SEEN_OUTPUT = 1 << 6,
    };
    unsigned int seen = 0;
    int ok = 1;
    while (ok) {
        weave_project_token *next = weave_project_peek(&parser);
        if (next == NULL) {
            ok = 0;
            break;
        }
        if (next->kind == WEAVE_PROJECT_TOKEN_RPAREN) {
            weave_project_token close = {0};
            ok = weave_project_take(&parser, &close);
            weave_project_token_clear(&close);
            break;
        }
        weave_project_token field_open = {0};
        weave_project_token field = {0};
        if (!weave_project_expect(
                &parser, WEAVE_PROJECT_TOKEN_LPAREN,
                "project.manifest.field-shape",
                "project manifest children must be fields", &field_open) ||
            !weave_project_expect(
                &parser, WEAVE_PROJECT_TOKEN_ATOM,
                "project.manifest.field-shape",
                "project field must have a name", &field)) {
            weave_project_token_clear(&field_open);
            weave_project_token_clear(&field);
            ok = 0;
            break;
        }

        unsigned int bit = 0;
        if (strcmp(field.text, "format") == 0) bit = SEEN_FORMAT;
        else if (strcmp(field.text, "name") == 0) bit = SEEN_NAME;
        else if (strcmp(field.text, "kind") == 0) bit = SEEN_KIND;
        else if (strcmp(field.text, "source-roots") == 0) bit = SEEN_SOURCE_ROOTS;
        else if (strcmp(field.text, "test-roots") == 0) bit = SEEN_TEST_ROOTS;
        else if (strcmp(field.text, "entry") == 0) bit = SEEN_ENTRY;
        else if (strcmp(field.text, "output") == 0) bit = SEEN_OUTPUT;
        else {
            weave_project_fail(
                error, "project.manifest.unknown-field",
                "unknown project manifest field",
                field.start, field.end, 1);
            ok = 0;
        }
        if (ok && (seen & bit) != 0) {
            weave_project_fail(
                error, "project.manifest.duplicate-field",
                "duplicate project manifest field",
                field.start, field.end, 1);
            ok = 0;
        }
        if (!ok) {
            weave_project_token_clear(&field_open);
            weave_project_token_clear(&field);
            break;
        }
        seen |= bit;

        if (bit == SEEN_SOURCE_ROOTS || bit == SEEN_TEST_ROOTS) {
            ok = weave_project_parse_roots(
                &parser, manifest, bit == SEEN_TEST_ROOTS, field);
        } else {
            weave_project_token value = {0};
            weave_project_token_kind expected = bit == SEEN_OUTPUT
                ? WEAVE_PROJECT_TOKEN_STRING : WEAVE_PROJECT_TOKEN_ATOM;
            ok = weave_project_expect(
                &parser, expected,
                "project.manifest.field-shape",
                "project field has an invalid value shape", &value);
            if (ok && bit == SEEN_FORMAT && strcmp(value.text, "1") != 0) {
                ok = weave_project_fail(
                    error, "project.manifest.format",
                    "unsupported project manifest format",
                    value.start, value.end, 1);
            } else if (ok && bit == SEEN_NAME) {
                if (!weave_project_identifier(value.text)) {
                    ok = weave_project_fail(
                        error, "project.manifest.identifier",
                        "project name is not a portable identifier",
                        value.start, value.end, 1);
                } else {
                    ok = weave_project_copy_token(
                        manifest->name, sizeof(manifest->name), &value,
                        error, "project.manifest.identifier",
                        "project name is too long");
                }
            } else if (ok && bit == SEEN_KIND) {
                if (strcmp(value.text, "executable") != 0 &&
                    strcmp(value.text, "library") != 0) {
                    ok = weave_project_fail(
                        error, "project.manifest.kind",
                        "project kind must be executable or library",
                        value.start, value.end, 1);
                } else {
                    ok = weave_project_copy_token(
                        manifest->kind, sizeof(manifest->kind), &value,
                        error, "project.manifest.kind",
                        "project kind is too long");
                }
            } else if (ok && bit == SEEN_ENTRY) {
                if (!weave_project_identifier(value.text)) {
                    ok = weave_project_fail(
                        error, "project.manifest.entry",
                        "entry module is not a portable identifier",
                        value.start, value.end, 1);
                } else {
                    ok = weave_project_copy_token(
                        manifest->entry, sizeof(manifest->entry), &value,
                        error, "project.manifest.entry",
                        "entry module is too long");
                }
            } else if (ok && bit == SEEN_OUTPUT) {
                if (!weave_project_output_name(value.text)) {
                    ok = weave_project_fail(
                        error, "project.manifest.output",
                        "project output must be one portable path component",
                        value.start, value.end, 1);
                } else {
                    ok = weave_project_copy_token(
                        manifest->output, sizeof(manifest->output), &value,
                        error, "project.manifest.output",
                        "project output name is too long");
                }
            }
            if (ok) ok = weave_project_field_end(&parser);
            weave_project_token_clear(&value);
        }
        weave_project_token_clear(&field_open);
        weave_project_token_clear(&field);
    }

    if (ok) {
        weave_project_token trailing = {0};
        ok = weave_project_expect(
            &parser, WEAVE_PROJECT_TOKEN_EOF,
            "project.manifest.parse",
            "trailing expression after project manifest", &trailing);
        weave_project_token_clear(&trailing);
    }
    if (ok && (seen & SEEN_FORMAT) == 0) {
        ok = weave_project_fail(
            error, "project.manifest.missing-field",
            "project manifest is missing format",
            root_head.start, root_head.end, 1);
    }
    if (ok && (seen & SEEN_NAME) == 0) {
        ok = weave_project_fail(
            error, "project.manifest.missing-field",
            "project manifest is missing name",
            root_head.start, root_head.end, 1);
    }
    if (ok && (seen & SEEN_KIND) == 0) {
        ok = weave_project_fail(
            error, "project.manifest.missing-field",
            "project manifest is missing kind",
            root_head.start, root_head.end, 1);
    }
    if (ok && (seen & SEEN_SOURCE_ROOTS) == 0) {
        ok = weave_project_fail(
            error, "project.manifest.missing-field",
            "project manifest is missing source-roots",
            root_head.start, root_head.end, 1);
    }
    if (ok && strcmp(manifest->kind, "executable") == 0 &&
        (seen & SEEN_ENTRY) == 0) {
        ok = weave_project_fail(
            error, "project.manifest.entry",
            "executable project requires an entry module",
            root_head.start, root_head.end, 1);
    }
    if (ok && strcmp(manifest->kind, "library") == 0 &&
        (seen & SEEN_ENTRY) != 0) {
        ok = weave_project_fail(
            error, "project.manifest.entry",
            "library project forbids an entry module",
            root_head.start, root_head.end, 1);
    }
    if (ok && (seen & SEEN_TEST_ROOTS) == 0 &&
        !weave_project_append_root(
            &manifest->test_roots, &manifest->test_root_count,
            &manifest->test_root_capacity, "test")) {
        ok = weave_project_fail(
            error, "driver.out-of-memory",
            "out of memory while applying project defaults",
            root_head.start, root_head.end, 1);
    }
    if (ok && (seen & SEEN_OUTPUT) == 0 &&
        snprintf(manifest->output, sizeof(manifest->output), "%s", manifest->name) >=
            (int)sizeof(manifest->output)) {
        ok = weave_project_fail(
            error, "project.manifest.output",
            "project output name is too long",
            root_head.start, root_head.end, 1);
    }

    if (ok) {
        qsort(
            manifest->source_roots, manifest->source_root_count,
            sizeof(*manifest->source_roots), weave_project_root_compare);
        qsort(
            manifest->test_roots, manifest->test_root_count,
            sizeof(*manifest->test_roots), weave_project_root_compare);
        for (size_t i = 0; ok && i < manifest->source_root_count; ++i) {
            for (size_t j = i + 1; j < manifest->source_root_count; ++j) {
                if (weave_project_roots_overlap(
                        manifest->source_roots[i], manifest->source_roots[j])) {
                    ok = weave_project_fail(
                        error, "project.manifest.root-overlap",
                        "source roots overlap or repeat",
                        root_head.start, root_head.end, 1);
                    break;
                }
            }
        }
        for (size_t i = 0; ok && i < manifest->test_root_count; ++i) {
            for (size_t j = i + 1; j < manifest->test_root_count; ++j) {
                if (weave_project_roots_overlap(
                        manifest->test_roots[i], manifest->test_roots[j])) {
                    ok = weave_project_fail(
                        error, "project.manifest.root-overlap",
                        "test roots overlap or repeat",
                        root_head.start, root_head.end, 1);
                    break;
                }
            }
        }
        for (size_t i = 0; ok && i < manifest->source_root_count; ++i) {
            for (size_t j = 0; j < manifest->test_root_count; ++j) {
                if (weave_project_roots_overlap(
                        manifest->source_roots[i], manifest->test_roots[j])) {
                    ok = weave_project_fail(
                        error, "project.manifest.root-overlap",
                        "source and test roots overlap",
                        root_head.start, root_head.end, 1);
                    break;
                }
            }
        }
    }

    weave_project_token_clear(&root_open);
    weave_project_token_clear(&root_head);
    if (parser.has_lookahead) weave_project_token_clear(&parser.lookahead);
    return ok;
}

static int weave_project_parent(char *path) {
    if (strcmp(path, "/") == 0) return 0;
    char *slash = strrchr(path, '/');
    if (slash == NULL) return 0;
    if (slash == path) {
        path[1] = '\0';
    } else {
        *slash = '\0';
    }
    return 1;
}

static int weave_project_manifest_path(
    const char *selection,
    char *path,
    size_t path_size,
    weave_project_error *error) {
    if (selection != NULL) {
        struct stat st;
        if (stat(selection, &st) != 0) {
            error->source = selection;
            return weave_project_fail(
                error, "project.manifest.read",
                "explicit project path does not exist", 0, 0, 0);
        }
        char candidate[PATH_MAX];
        if (S_ISDIR(st.st_mode)) {
            if (snprintf(
                    candidate, sizeof(candidate), "%s/%s",
                    selection, WEAVE_PROJECT_MANIFEST_NAME) >=
                (int)sizeof(candidate)) {
                error->source = selection;
                return weave_project_fail(
                    error, "project.manifest.read",
                    "explicit project path is too long", 0, 0, 0);
            }
        } else if (S_ISREG(st.st_mode)) {
            const char *base = strrchr(selection, '/');
            base = base == NULL ? selection : base + 1;
            if (strcmp(base, WEAVE_PROJECT_MANIFEST_NAME) != 0) {
                error->source = selection;
                return weave_project_fail(
                    error, "project.manifest.read",
                    "explicit manifest file must be named weave.project",
                    0, 0, 0);
            }
            if (snprintf(candidate, sizeof(candidate), "%s", selection) >=
                (int)sizeof(candidate)) {
                error->source = selection;
                return weave_project_fail(
                    error, "project.manifest.read",
                    "explicit manifest path is too long", 0, 0, 0);
            }
        } else {
            error->source = selection;
            return weave_project_fail(
                error, "project.manifest.read",
                "explicit project path is not a directory or regular file",
                0, 0, 0);
        }
        if (realpath(candidate, path) == NULL) {
            error->source = selection;
            return weave_project_fail(
                error, "project.manifest.read",
                "cannot resolve explicit project manifest", 0, 0, 0);
        }
        return 1;
    }

    char directory[PATH_MAX];
    if (getcwd(directory, sizeof(directory)) == NULL) {
        return weave_project_fail(
            error, "project.manifest.read",
            "cannot determine the current directory", 0, 0, 0);
    }
    char origin[PATH_MAX];
    (void)snprintf(origin, sizeof(origin), "%s", directory);
    for (;;) {
        char candidate[PATH_MAX];
        int written = snprintf(
            candidate, sizeof(candidate), "%s%s%s",
            directory, strcmp(directory, "/") == 0 ? "" : "/",
            WEAVE_PROJECT_MANIFEST_NAME);
        if (written < 0 || written >= (int)sizeof(candidate)) {
            error->source = origin;
            return weave_project_fail(
                error, "project.manifest.read",
                "project discovery path is too long", 0, 0, 0);
        }
        struct stat st;
        if (stat(candidate, &st) == 0) {
            if (!S_ISREG(st.st_mode) || realpath(candidate, path) == NULL) {
                error->source = candidate;
                return weave_project_fail(
                    error, "project.manifest.read",
                    "discovered weave.project is not a readable regular file",
                    0, 0, 0);
            }
            return 1;
        }
        if (errno != ENOENT && errno != ENOTDIR) {
            error->source = candidate;
            return weave_project_fail(
                error, "project.manifest.read",
                "cannot inspect candidate project manifest", 0, 0, 0);
        }
        if (!weave_project_parent(directory)) break;
    }
    error->source = origin;
    return weave_project_fail(
        error, "project.manifest.read",
        "no weave.project found in the current directory or its parents",
        0, 0, 0);
}

static int weave_project_load(
    const char *selection,
    weave_project_manifest *manifest,
    weave_project_error *error) {
    if (!weave_project_manifest_path(
            selection, manifest->path, sizeof(manifest->path), error)) {
        return 0;
    }
    error->source = manifest->path;
    size_t length = 0;
    unsigned char *data = weave_diag_read_file(manifest->path, &length);
    if (data == NULL) {
        return weave_project_fail(
            error, "project.manifest.read",
            "cannot read project manifest", 0, 0, 0);
    }
    int parsed = weave_project_parse_document(data, length, manifest, error);
    free(data);
    if (!parsed) return 0;

    if (snprintf(
            manifest->directory, sizeof(manifest->directory), "%s",
            manifest->path) >= (int)sizeof(manifest->directory)) {
        return weave_project_fail(
            error, "project.manifest.read",
            "project directory path is too long", 0, 0, 0);
    }
    char *slash = strrchr(manifest->directory, '/');
    if (slash == NULL) {
        (void)snprintf(manifest->directory, sizeof(manifest->directory), ".");
    } else if (slash == manifest->directory) {
        slash[1] = '\0';
    } else {
        *slash = '\0';
    }
    return 1;
}

static int weave_project_option_takes_value(const char *arg) {
    return strcmp(arg, "-o") == 0 || strcmp(arg, "--output") == 0 ||
        strcmp(arg, "--project") == 0 || strcmp(arg, "--target") == 0 ||
        strcmp(arg, "--runtime") == 0 || strcmp(arg, "--optimizer") == 0 ||
        strcmp(arg, "--codegen") == 0 ||
        strcmp(arg, "--target-codegen") == 0 || strcmp(arg, "--llc") == 0 ||
        strcmp(arg, "--linker") == 0 || strcmp(arg, "--objdump") == 0 ||
        strcmp(arg, "--manifest-json") == 0 ||
        strcmp(arg, "--diagnostics-json") == 0 ||
        strcmp(arg, "--trace-json") == 0 || strcmp(arg, "--emit-wir") == 0 ||
        strcmp(arg, "--emit-llvm") == 0 ||
        strcmp(arg, "--emit-optimized-llvm") == 0 ||
        strcmp(arg, "--emit-assembly") == 0 ||
        strcmp(arg, "--emit-disassembly") == 0 ||
        strcmp(arg, "--optimization-record") == 0 ||
        strcmp(arg, "--cpu") == 0 || strcmp(arg, "--march") == 0 ||
        strcmp(arg, "--tune-cpu") == 0 || strcmp(arg, "--mtune") == 0;
}

static int weave_project_output_option(const char *arg) {
    return strcmp(arg, "-o") == 0 || strcmp(arg, "--output") == 0 ||
        strcmp(arg, "--manifest-json") == 0 ||
        strcmp(arg, "--diagnostics-json") == 0 ||
        strcmp(arg, "--trace-json") == 0 || strcmp(arg, "--emit-wir") == 0 ||
        strcmp(arg, "--emit-llvm") == 0 ||
        strcmp(arg, "--emit-optimized-llvm") == 0 ||
        strcmp(arg, "--emit-assembly") == 0 ||
        strcmp(arg, "--emit-disassembly") == 0 ||
        strcmp(arg, "--optimization-record") == 0;
}

static int weave_project_known_flag(const char *arg) {
    return strcmp(arg, "--keep-temporaries") == 0 ||
        strcmp(arg, "--llvm-provenance") == 0 ||
        strcmp(arg, "--native") == 0 ||
        strcmp(arg, "-O0") == 0 || strcmp(arg, "-O1") == 0 ||
        strcmp(arg, "-O2") == 0 || strcmp(arg, "-O3") == 0 ||
        strcmp(arg, "-Os") == 0 || strcmp(arg, "-Oz") == 0 ||
        strncmp(arg, "--march=", 8) == 0 ||
        strncmp(arg, "--mtune=", 8) == 0;
}

static int weave_project_parse_request(
    int argc,
    char **argv,
    weave_project_request *request,
    weave_project_error *error) {
    request->output_paths = calloc((size_t)argc, sizeof(*request->output_paths));
    if (request->output_paths == NULL) {
        return weave_project_fail(
            error, "driver.out-of-memory",
            "out of memory while reading build options", 0, 0, 0);
    }
    for (int i = 2; i < argc; ++i) {
        const char *arg = argv[i];
        if (strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0) {
            request->help = 1;
            continue;
        }
        if (strncmp(arg, "--project=", 10) == 0) {
            if (request->project != NULL || arg[10] == '\0') {
                return weave_project_fail(
                    error, "driver.invalid-command-line",
                    "project selection must occur exactly once with a value",
                    0, 0, 0);
            }
            request->project = arg + 10;
            continue;
        }
        if (weave_project_option_takes_value(arg)) {
            if (++i >= argc) {
                return weave_project_fail(
                    error, "driver.invalid-command-line",
                    "build option requires a value", 0, 0, 0);
            }
            const char *value = argv[i];
            if (strcmp(arg, "--project") == 0) {
                if (request->project != NULL || *value == '\0') {
                    return weave_project_fail(
                        error, "driver.invalid-command-line",
                        "project selection must occur exactly once with a value",
                        0, 0, 0);
                }
                request->project = value;
            } else if (strcmp(arg, "-o") == 0 ||
                       strcmp(arg, "--output") == 0) {
                request->output = value;
            } else if (strcmp(arg, "--diagnostics-json") == 0) {
                request->diagnostics = value;
            } else if (strcmp(arg, "--trace-json") == 0) {
                request->trace = value;
            }
            if (weave_project_output_option(arg)) {
                request->output_paths[request->output_path_count++] = value;
            }
            continue;
        }
        if (weave_project_known_flag(arg)) continue;
        if (arg[0] == '-') {
            request->unknown_option = arg;
            continue;
        }
        ++request->source_count;
    }
    return 1;
}

static int weave_project_publish_error(
    const weave_project_error *error,
    const char *diagnostics_path,
    const char *trace_path,
    int raw_exit) {
    if (error->source != NULL && error->has_span) {
        size_t length = 0;
        unsigned char *data = weave_diag_read_file(error->source, &length);
        size_t line = 0;
        size_t column = 0;
        if (data != NULL) {
            weave_diag_position(data, length, error->start, &line, &column);
        }
        if (data != NULL) {
            fprintf(
                stderr, "weavec: error: %s:%zu:%zu: %s [%s]\n",
                error->source, line, column, error->message, error->code);
        } else {
            fprintf(
                stderr, "weavec: error: %s: %s [%s]\n",
                error->source, error->message, error->code);
        }
        free(data);
    } else if (error->source != NULL) {
        fprintf(
            stderr, "weavec: error: %s: %s [%s]\n",
            error->source, error->message, error->code);
    } else {
        fprintf(stderr, "weavec: error: %s [%s]\n", error->message, error->code);
    }

    weave_diag_record record = {
        .code = error->code,
        .severity = "error",
        .phase = "driver",
        .message = error->message,
        .source = error->source,
        .span_origin = error->has_span ? "compiler-project-parser" : "none",
        .start_byte = error->start,
        .end_byte = error->end,
        .has_span = error->has_span,
    };
    if (diagnostics_path != NULL) {
        (void)weave_diag_write_result(
            diagnostics_path, "failed", "driver",
            WEAVEC_EXIT_DRIVER, raw_exit, &record);
    }
    if (trace_path != NULL) {
        (void)weave_trace_write_document(
            trace_path, "failed", "driver", NULL, 0, NULL);
    }
    return diagnostics_path != NULL ? WEAVEC_EXIT_DRIVER : raw_exit;
}

static int weave_project_outputs_alias_manifest(
    const weave_project_request *request,
    const char *manifest_path,
    const char **conflict) {
    for (int i = 0; i < request->output_path_count; ++i) {
        if (weave_path_safety_aliases(
                request->output_paths[i], manifest_path)) {
            *conflict = request->output_paths[i];
            return 1;
        }
    }
    return 0;
}

int weave_rt_build_main(int argc, char **argv) {
    if (argc < 2 || strcmp(argv[1], "build") != 0) {
        return weave_rt_build_main_path_safety_legacy(argc, argv);
    }

    weave_project_request request = {0};
    weave_project_error error = {0};
    if (!weave_project_parse_request(argc, argv, &request, &error)) {
        int result = weave_project_publish_error(
            &error, request.diagnostics, request.trace, 2);
        free(request.output_paths);
        return result;
    }
    if (request.help) {
        weave_project_usage(stdout);
        free(request.output_paths);
        return 0;
    }
    if (request.unknown_option != NULL) {
        error.code = "driver.unknown-option";
        error.message = "unknown build option";
        int result = weave_project_publish_error(
            &error, request.diagnostics, request.trace, 2);
        weave_project_usage(stderr);
        free(request.output_paths);
        return result;
    }
    if (request.source_count > 0) {
        if (request.project != NULL) {
            error.code = "driver.ambiguous-build-mode";
            error.message =
                "--project cannot be combined with explicit source arguments";
            int result = weave_project_publish_error(
                &error, request.diagnostics, request.trace, 2);
            free(request.output_paths);
            return result;
        }
        free(request.output_paths);
        return weave_rt_build_main_path_safety_legacy(argc, argv);
    }

    weave_project_manifest manifest = {0};
    if (!weave_project_load(request.project, &manifest, &error)) {
        int result = weave_project_publish_error(
            &error, request.diagnostics, request.trace, 2);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return result;
    }

    const char *conflict = NULL;
    if (weave_project_outputs_alias_manifest(
            &request, manifest.path, &conflict)) {
        error.code = "driver.output-aliases-project-manifest";
        error.message = "an output path aliases the selected project manifest";
        error.source = conflict;
        error.has_span = 0;
        const char *diagnostics = request.diagnostics;
        if (diagnostics != NULL &&
            weave_path_safety_aliases(diagnostics, manifest.path)) {
            diagnostics = NULL;
        }
        int result = weave_project_publish_error(
            &error, diagnostics, request.trace, 2);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return result;
    }

    char resolved_output[PATH_MAX];
    if (request.output != NULL) {
        if (snprintf(
                resolved_output, sizeof(resolved_output), "%s",
                request.output) >= (int)sizeof(resolved_output)) {
            error.code = "project.manifest.output";
            error.message = "requested output path is too long";
            error.source = manifest.path;
            int result = weave_project_publish_error(
                &error, request.diagnostics, request.trace, 2);
            weave_project_manifest_clear(&manifest);
            free(request.output_paths);
            return result;
        }
    } else if (snprintf(
            resolved_output, sizeof(resolved_output), "%s%s%s",
            manifest.directory,
            strcmp(manifest.directory, "/") == 0 ? "" : "/",
            manifest.output) >= (int)sizeof(resolved_output)) {
        error.code = "project.manifest.output";
        error.message = "resolved project output path is too long";
        error.source = manifest.path;
        int result = weave_project_publish_error(
            &error, request.diagnostics, request.trace, 2);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return result;
    }

    char pending_message[PATH_MAX * 2];
    (void)snprintf(
        pending_message, sizeof(pending_message),
        "project selected at %s with output %s; source discovery is not yet available",
        manifest.path, resolved_output);
    error.code = "project.sources.pending";
    error.message = pending_message;
    error.source = manifest.path;
    error.has_span = 0;
    int result = weave_project_publish_error(
        &error, request.diagnostics, request.trace, 2);

    weave_project_manifest_clear(&manifest);
    free(request.output_paths);
    return result;
}

#endif
