// SPDX-License-Identifier: Apache-2.0
//
// Small checked streaming JSON writer shared by every public compiler protocol.
// It owns JSON syntax, escaping, nesting, commas, and write-error tracking.

#ifndef WEAVEC_JSON_WRITER_C
#define WEAVEC_JSON_WRITER_C

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define WEAVE_JSON_MAX_DEPTH 32

typedef enum weave_json_context_kind {
    WEAVE_JSON_OBJECT = 1,
    WEAVE_JSON_ARRAY = 2,
} weave_json_context_kind;

typedef struct weave_json_context {
    weave_json_context_kind kind;
    size_t count;
    int key_pending;
} weave_json_context;

typedef struct weave_json_writer {
    FILE *stream;
    weave_json_context stack[WEAVE_JSON_MAX_DEPTH];
    size_t depth;
    int root_written;
    int pretty;
    int failed;
} weave_json_writer;

static void weave_json_fail(weave_json_writer *writer) {
    writer->failed = 1;
}

static int weave_json_write_bytes(
    weave_json_writer *writer,
    const void *data,
    size_t length) {
    if (writer->failed) {
        return 0;
    }
    if (length != 0 && fwrite(data, 1, length, writer->stream) != length) {
        weave_json_fail(writer);
        return 0;
    }
    return 1;
}

static int weave_json_write_cstr(
    weave_json_writer *writer,
    const char *value) {
    return weave_json_write_bytes(writer, value, strlen(value));
}

static int weave_json_write_char(weave_json_writer *writer, int value) {
    if (writer->failed) {
        return 0;
    }
    if (fputc(value, writer->stream) == EOF) {
        weave_json_fail(writer);
        return 0;
    }
    return 1;
}

static int weave_json_indent(weave_json_writer *writer, size_t depth) {
    if (!writer->pretty) {
        return 1;
    }
    if (!weave_json_write_char(writer, '\n')) {
        return 0;
    }
    for (size_t i = 0; i < depth * 2; ++i) {
        if (!weave_json_write_char(writer, ' ')) {
            return 0;
        }
    }
    return 1;
}

static int weave_json_before_value(weave_json_writer *writer) {
    if (writer->failed) {
        return 0;
    }
    if (writer->depth == 0) {
        if (writer->root_written) {
            weave_json_fail(writer);
            return 0;
        }
        writer->root_written = 1;
        return 1;
    }

    weave_json_context *context = &writer->stack[writer->depth - 1];
    if (context->kind == WEAVE_JSON_ARRAY) {
        if (context->count != 0 && !weave_json_write_char(writer, ',')) {
            return 0;
        }
        if (!weave_json_indent(writer, writer->depth)) {
            return 0;
        }
        ++context->count;
        return 1;
    }

    if (!context->key_pending) {
        weave_json_fail(writer);
        return 0;
    }
    context->key_pending = 0;
    ++context->count;
    return 1;
}

static int weave_json_write_quoted_bytes(
    weave_json_writer *writer,
    const unsigned char *data,
    size_t length) {
    static const char hex[] = "0123456789abcdef";
    if (!weave_json_write_char(writer, '"')) {
        return 0;
    }
    for (size_t i = 0; i < length; ++i) {
        unsigned char ch = data[i];
        switch (ch) {
            case '\\':
                if (!weave_json_write_cstr(writer, "\\\\")) return 0;
                break;
            case '"':
                if (!weave_json_write_cstr(writer, "\\\"")) return 0;
                break;
            case '\b':
                if (!weave_json_write_cstr(writer, "\\b")) return 0;
                break;
            case '\f':
                if (!weave_json_write_cstr(writer, "\\f")) return 0;
                break;
            case '\n':
                if (!weave_json_write_cstr(writer, "\\n")) return 0;
                break;
            case '\r':
                if (!weave_json_write_cstr(writer, "\\r")) return 0;
                break;
            case '\t':
                if (!weave_json_write_cstr(writer, "\\t")) return 0;
                break;
            default:
                if (ch < 0x20) {
                    char escaped[6] = {
                        '\\', 'u', '0', '0', hex[ch >> 4], hex[ch & 0x0f],
                    };
                    if (!weave_json_write_bytes(
                            writer, escaped, sizeof(escaped))) return 0;
                } else if (!weave_json_write_char(writer, ch)) {
                    return 0;
                }
        }
    }
    return weave_json_write_char(writer, '"');
}

static void weave_json_writer_init_mode(
    weave_json_writer *writer,
    FILE *stream,
    int pretty) {
    memset(writer, 0, sizeof(*writer));
    writer->stream = stream;
    writer->pretty = pretty ? 1 : 0;
    if (stream == NULL) {
        writer->failed = 1;
    }
}

static void weave_json_writer_init(
    weave_json_writer *writer,
    FILE *stream) {
    weave_json_writer_init_mode(writer, stream, 1);
}

static int weave_json_key(
    weave_json_writer *writer,
    const char *key) {
    if (writer->failed || key == NULL || writer->depth == 0) {
        weave_json_fail(writer);
        return 0;
    }
    weave_json_context *context = &writer->stack[writer->depth - 1];
    if (context->kind != WEAVE_JSON_OBJECT || context->key_pending) {
        weave_json_fail(writer);
        return 0;
    }
    if (context->count != 0 && !weave_json_write_char(writer, ',')) {
        return 0;
    }
    if (!weave_json_indent(writer, writer->depth) ||
        !weave_json_write_quoted_bytes(
            writer,
            (const unsigned char *)key,
            strlen(key)) ||
        !weave_json_write_cstr(writer, writer->pretty ? ": " : ":")) {
        return 0;
    }
    context->key_pending = 1;
    return 1;
}

static int weave_json_object_begin(weave_json_writer *writer) {
    if (!weave_json_before_value(writer) ||
        writer->depth >= WEAVE_JSON_MAX_DEPTH ||
        !weave_json_write_char(writer, '{')) {
        weave_json_fail(writer);
        return 0;
    }
    writer->stack[writer->depth++] = (weave_json_context){
        .kind = WEAVE_JSON_OBJECT,
    };
    return 1;
}

static int weave_json_object_end(weave_json_writer *writer) {
    if (writer->failed || writer->depth == 0) {
        weave_json_fail(writer);
        return 0;
    }
    weave_json_context *context = &writer->stack[writer->depth - 1];
    if (context->kind != WEAVE_JSON_OBJECT || context->key_pending) {
        weave_json_fail(writer);
        return 0;
    }
    if (context->count != 0 &&
        !weave_json_indent(writer, writer->depth - 1)) {
        return 0;
    }
    --writer->depth;
    return weave_json_write_char(writer, '}');
}

static int weave_json_array_begin(weave_json_writer *writer) {
    if (!weave_json_before_value(writer) ||
        writer->depth >= WEAVE_JSON_MAX_DEPTH ||
        !weave_json_write_char(writer, '[')) {
        weave_json_fail(writer);
        return 0;
    }
    writer->stack[writer->depth++] = (weave_json_context){
        .kind = WEAVE_JSON_ARRAY,
    };
    return 1;
}

static int weave_json_array_end(weave_json_writer *writer) {
    if (writer->failed || writer->depth == 0) {
        weave_json_fail(writer);
        return 0;
    }
    weave_json_context *context = &writer->stack[writer->depth - 1];
    if (context->kind != WEAVE_JSON_ARRAY || context->key_pending) {
        weave_json_fail(writer);
        return 0;
    }
    if (context->count != 0 &&
        !weave_json_indent(writer, writer->depth - 1)) {
        return 0;
    }
    --writer->depth;
    return weave_json_write_char(writer, ']');
}

static int weave_json_string_bytes(
    weave_json_writer *writer,
    const unsigned char *data,
    size_t length) {
    return weave_json_before_value(writer) &&
        weave_json_write_quoted_bytes(writer, data, length);
}

static int weave_json_string(
    weave_json_writer *writer,
    const char *value) {
    if (value == NULL) {
        weave_json_fail(writer);
        return 0;
    }
    return weave_json_string_bytes(
        writer,
        (const unsigned char *)value,
        strlen(value));
}

static int weave_json_null(weave_json_writer *writer) {
    return weave_json_before_value(writer) &&
        weave_json_write_cstr(writer, "null");
}

static int weave_json_nullable_string(
    weave_json_writer *writer,
    const char *value) {
    return value != NULL
        ? weave_json_string(writer, value)
        : weave_json_null(writer);
}

static int weave_json_boolean(weave_json_writer *writer, int value) {
    return weave_json_before_value(writer) &&
        weave_json_write_cstr(writer, value ? "true" : "false");
}

static int weave_json_int64(weave_json_writer *writer, int64_t value) {
    char buffer[32];
    int length = snprintf(buffer, sizeof(buffer), "%lld", (long long)value);
    if (length < 0 || (size_t)length >= sizeof(buffer)) {
        weave_json_fail(writer);
        return 0;
    }
    return weave_json_before_value(writer) &&
        weave_json_write_bytes(writer, buffer, (size_t)length);
}

static int weave_json_uint64(weave_json_writer *writer, uint64_t value) {
    char buffer[32];
    int length = snprintf(
        buffer, sizeof(buffer), "%llu", (unsigned long long)value);
    if (length < 0 || (size_t)length >= sizeof(buffer)) {
        weave_json_fail(writer);
        return 0;
    }
    return weave_json_before_value(writer) &&
        weave_json_write_bytes(writer, buffer, (size_t)length);
}

// Internal bridge for event values already serialized by this same writer.
// Public protocol serializers should prefer the typed operations above.
static int weave_json_trusted_value(
    weave_json_writer *writer,
    const unsigned char *data,
    size_t length) {
    if (data == NULL || length == 0) {
        weave_json_fail(writer);
        return 0;
    }
    return weave_json_before_value(writer) &&
        weave_json_write_bytes(writer, data, length);
}

static int weave_json_writer_finish(weave_json_writer *writer) {
    if (writer->failed || writer->depth != 0 || !writer->root_written) {
        weave_json_fail(writer);
        return 0;
    }
    if (!weave_json_write_char(writer, '\n') || ferror(writer->stream)) {
        weave_json_fail(writer);
        return 0;
    }
    return 1;
}

#endif
