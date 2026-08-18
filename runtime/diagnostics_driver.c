// SPDX-License-Identifier: Apache-2.0
//
// Machine-readable diagnostic facade for `weavec build`.
//
// This translation unit is included after build_driver.c. portable.c renames the
// original entry point to weave_rt_build_main_legacy, then includes this file to
// expose the stable public wrapper below.

#include <ctype.h>
#include <stdint.h>

#define WEAVEC_EXIT_FRONTEND 10
#define WEAVEC_EXIT_BACKEND 11
#define WEAVEC_EXIT_CODEGEN 12
#define WEAVEC_EXIT_LINK 13
#define WEAVEC_EXIT_PUBLISH 14
#define WEAVEC_EXIT_DRIVER 15

typedef struct weave_diag_record {
    const char *code;
    const char *severity;
    const char *phase;
    const char *message;
    const char *source;
    const char *span_origin;
    size_t start_byte;
    size_t end_byte;
    int has_span;
    int owns_message;
} weave_diag_record;

static void weave_diag_record_clear(weave_diag_record *record) {
    if (record->owns_message && record->message != NULL) {
        free((void *)record->message);
    }
    memset(record, 0, sizeof(*record));
}

static void weave_diag_position(
    const unsigned char *data,
    size_t length,
    size_t offset,
    size_t *line,
    size_t *column) {
    if (offset > length) {
        offset = length;
    }
    size_t current_line = 1;
    size_t current_column = 1;
    for (size_t i = 0; i < offset; ++i) {
        if (data[i] == '\n') {
            ++current_line;
            current_column = 1;
        } else if ((data[i] & 0xc0) != 0x80) {
            ++current_column;
        }
    }
    *line = current_line;
    *column = current_column;
}

static unsigned char *weave_diag_read_file(const char *path, size_t *length_out) {
    FILE *stream = fopen(path, "rb");
    if (stream == NULL) {
        return NULL;
    }
    if (fseek(stream, 0, SEEK_END) != 0) {
        fclose(stream);
        return NULL;
    }
    long end = ftell(stream);
    if (end < 0 || fseek(stream, 0, SEEK_SET) != 0) {
        fclose(stream);
        return NULL;
    }
    size_t length = (size_t)end;
    unsigned char *data = malloc(length + 1);
    if (data == NULL) {
        fclose(stream);
        return NULL;
    }
    size_t count = fread(data, 1, length, stream);
    fclose(stream);
    if (count != length) {
        free(data);
        return NULL;
    }
    data[length] = '\0';
    *length_out = length;
    return data;
}

static int weave_diag_preflight_source(
    const char *path,
    weave_diag_record *record) {
    size_t length = 0;
    unsigned char *data = weave_diag_read_file(path, &length);
    if (data == NULL) {
        record->code = "frontend.source-unreadable";
        record->severity = "error";
        record->phase = "frontend";
        record->message = "cannot read source file";
        record->source = path;
        record->span_origin = "none";
        record->has_span = 0;
        return 1;
    }

    size_t stack_capacity = 64;
    size_t stack_size = 0;
    size_t *stack = malloc(stack_capacity * sizeof(*stack));
    if (stack == NULL) {
        free(data);
        record->code = "driver.out-of-memory";
        record->severity = "error";
        record->phase = "driver";
        record->message = "out of memory while validating source";
        record->source = path;
        record->span_origin = "none";
        return 1;
    }

    int in_string = 0;
    int in_comment = 0;
    size_t string_start = 0;
    for (size_t i = 0; i < length; ++i) {
        unsigned char ch = data[i];
        if (in_comment) {
            if (ch == '\n') {
                in_comment = 0;
            }
            continue;
        }
        if (in_string == 3) {
            if (ch == '"' && i + 2 < length &&
                data[i + 1] == '"' && data[i + 2] == '"') {
                i += 2;
                in_string = 0;
            }
            continue;
        }
        if (in_string == 2) {
            if (ch == '"') {
                in_string = 0;
            }
            continue;
        }
        if (in_string) {
            if (ch == '\\' && i + 1 < length) {
                ++i;
                continue;
            }
            if (ch == '"') {
                in_string = 0;
            }
            continue;
        }
        if (ch == ';') {
            in_comment = 1;
            continue;
        }
        if (ch == '#' && i + 1 < length && data[i + 1] == '"') {
            string_start = i;
            if (i + 3 < length && data[i + 2] == '"' && data[i + 3] == '"') {
                in_string = 3;
                i += 3;
            } else {
                in_string = 2;
                i += 1;
            }
            continue;
        }
        if (ch == '"') {
            string_start = i;
            if (i + 2 < length && data[i + 1] == '"' && data[i + 2] == '"') {
                in_string = 3;
                i += 2;
            } else {
                in_string = 1;
            }
            continue;
        }
        if (ch == '(') {
            if (stack_size == stack_capacity) {
                size_t new_capacity = stack_capacity * 2;
                size_t *new_stack = realloc(stack, new_capacity * sizeof(*stack));
                if (new_stack == NULL) {
                    free(stack);
                    free(data);
                    record->code = "driver.out-of-memory";
                    record->severity = "error";
                    record->phase = "driver";
                    record->message = "out of memory while validating source";
                    record->source = path;
                    record->span_origin = "none";
                    return 1;
                }
                stack = new_stack;
                stack_capacity = new_capacity;
            }
            stack[stack_size++] = i;
        } else if (ch == ')') {
            if (stack_size == 0) {
                record->code = "frontend.parse.unmatched-closing-paren";
                record->severity = "error";
                record->phase = "frontend";
                record->message = "unmatched closing parenthesis";
                record->source = path;
                record->span_origin = "compiler-preflight";
                record->start_byte = i;
                record->end_byte = i + 1;
                record->has_span = 1;
                free(stack);
                free(data);
                return 1;
            }
            --stack_size;
        }
    }

    if (in_string) {
        record->code = "frontend.parse.unterminated-string";
        record->severity = "error";
        record->phase = "frontend";
        record->message = "unterminated string literal";
        record->source = path;
        record->span_origin = "compiler-preflight";
        record->start_byte = string_start;
        record->end_byte = length;
        record->has_span = 1;
        free(stack);
        free(data);
        return 1;
    }
    if (stack_size != 0) {
        size_t opening = stack[stack_size - 1];
        record->code = "frontend.parse.unclosed-list";
        record->severity = "error";
        record->phase = "frontend";
        record->message = "unclosed list";
        record->source = path;
        record->span_origin = "compiler-preflight";
        record->start_byte = opening;
        record->end_byte = opening + 1;
        record->has_span = 1;
        free(stack);
        free(data);
        return 1;
    }

    free(stack);
    free(data);
    return 0;
}

static int weave_diag_identifier_char(unsigned char ch) {
    return isalnum(ch) || ch == '_' || ch == '-';
}

static int weave_diag_unique_token_span(
    char **sources,
    int source_count,
    const char *token,
    int list_head_only,
    weave_diag_record *record) {
    size_t token_length = strlen(token);
    if (token_length == 0) {
        return 0;
    }
    int matches = 0;
    const char *matched_source = NULL;
    size_t matched_start = 0;

    for (int source_index = 0; source_index < source_count; ++source_index) {
        size_t length = 0;
        unsigned char *data = weave_diag_read_file(sources[source_index], &length);
        if (data == NULL) {
            continue;
        }
        int in_string = 0;
        int in_comment = 0;
        for (size_t i = 0; i + token_length <= length; ++i) {
            unsigned char ch = data[i];
            if (in_comment) {
                if (ch == '\n') {
                    in_comment = 0;
                }
                continue;
            }
            if (in_string == 3) {
                if (ch == '"' && i + 2 < length &&
                    data[i + 1] == '"' && data[i + 2] == '"') {
                    i += 2;
                    in_string = 0;
                }
                continue;
            }
            if (in_string == 2) {
                if (ch == '"') {
                    in_string = 0;
                }
                continue;
            }
            if (in_string) {
                if (ch == '\\' && i + 1 < length) {
                    ++i;
                } else if (ch == '"') {
                    in_string = 0;
                }
                continue;
            }
            if (ch == ';') {
                in_comment = 1;
                continue;
            }
            if (ch == '#' && i + 1 < length && data[i + 1] == '"') {
                if (i + 3 < length && data[i + 2] == '"' && data[i + 3] == '"') {
                    in_string = 3;
                    i += 3;
                } else {
                    in_string = 2;
                    i += 1;
                }
                continue;
            }
            if (ch == '"') {
                if (i + 2 < length && data[i + 1] == '"' && data[i + 2] == '"') {
                    in_string = 3;
                    i += 2;
                } else {
                    in_string = 1;
                }
                continue;
            }
            if (memcmp(data + i, token, token_length) != 0) {
                continue;
            }
            if (i > 0 && weave_diag_identifier_char(data[i - 1])) {
                continue;
            }
            if (i + token_length < length &&
                weave_diag_identifier_char(data[i + token_length])) {
                continue;
            }
            if (list_head_only) {
                size_t before = i;
                while (before > 0 && isspace(data[before - 1])) {
                    --before;
                }
                if (before == 0 || data[before - 1] != '(') {
                    continue;
                }
            }
            ++matches;
            matched_source = sources[source_index];
            matched_start = i;
        }
        free(data);
    }

    if (matches != 1) {
        return 0;
    }
    record->source = matched_source;
    record->span_origin = "inferred-unique-token";
    record->start_byte = matched_start;
    record->end_byte = matched_start + token_length;
    record->has_span = 1;
    return 1;
}

static char *weave_diag_trimmed_message(const char *stderr_text) {
    const char *cursor = stderr_text != NULL ? stderr_text : "";
    const char *error_prefix = "weavec: error: ";
    const char *temporary_prefix = "weavec: kept temporary build directory: ";
    while (*cursor != '\0') {
        while (*cursor == '\n' || *cursor == '\r' ||
               *cursor == ' ' || *cursor == '\t') {
            ++cursor;
        }
        if (*cursor == '\0') {
            break;
        }
        const char *end = cursor;
        while (*end != '\0' && *end != '\n' && *end != '\r') {
            ++end;
        }
        if (strncmp(cursor, temporary_prefix, strlen(temporary_prefix)) == 0) {
            cursor = end;
            continue;
        }
        const char *start = cursor;
        if (strncmp(start, error_prefix, strlen(error_prefix)) == 0) {
            start += strlen(error_prefix);
        }
        size_t length = (size_t)(end - start);
        if (length == 0) {
            cursor = end;
            continue;
        }
        char *message = malloc(length + 1);
        if (message == NULL) {
            return NULL;
        }
        memcpy(message, start, length);
        message[length] = '\0';
        return message;
    }
    return strdup("compiler phase failed; see stderr");
}

static char *weave_diag_extract_token(
    const char *message,
    const char *prefix,
    int stop_at_colon) {
    if (message == NULL || strncmp(message, prefix, strlen(prefix)) != 0) {
        return NULL;
    }
    const char *start = message + strlen(prefix);
    const char *end = start;
    while (*end != '\0' && *end != '\n' && *end != '\r' &&
           (!stop_at_colon || *end != ':')) {
        ++end;
    }
    while (end > start && isspace((unsigned char)end[-1])) {
        --end;
    }
    if (end == start || (size_t)(end - start) > 255) {
        return NULL;
    }
    size_t length = (size_t)(end - start);
    char *token = malloc(length + 1);
    if (token == NULL) {
        return NULL;
    }
    memcpy(token, start, length);
    token[length] = '\0';
    return token;
}

static void weave_diag_classify_compiler_error(
    const char *phase,
    const char *stderr_text,
    char **sources,
    int source_count,
    weave_diag_record *record) {
    record->severity = "error";
    record->phase = phase;
    record->span_origin = "none";
    record->message = weave_diag_trimmed_message(stderr_text);
    record->owns_message = record->message != NULL;
    if (record->message == NULL) {
        record->message = "compiler phase failed; see stderr";
    }

    char *token = NULL;
    int list_head = 0;
    if (strcmp(phase, "backend") == 0 &&
        (token = weave_diag_extract_token(
             record->message, "unknown expression operator: ", 0)) != NULL) {
        record->code = "backend.unknown-expression-operator";
        list_head = 1;
    } else if (strcmp(phase, "backend") == 0 &&
               (token = weave_diag_extract_token(
                    record->message, "unknown identifier: ", 0)) != NULL) {
        record->code = "backend.unknown-identifier";
    } else if (strcmp(phase, "backend") == 0 &&
               (token = weave_diag_extract_token(
                    record->message, "wrong arity for ", 1)) != NULL) {
        record->code = "backend.wrong-arity";
        list_head = 1;
    } else if (strcmp(phase, "backend") == 0 &&
               (token = weave_diag_extract_token(
                    record->message, "expected expression list, got: ", 0)) != NULL) {
        record->code = "backend.expected-expression-list";
    } else if (strcmp(phase, "frontend") == 0) {
        record->code = "frontend.failed";
    } else if (strcmp(phase, "backend") == 0) {
        record->code = "backend.failed";
    } else if (strcmp(phase, "optimize") == 0) {
        record->code = "codegen.optimize-failed";
    } else if (strcmp(phase, "assembly") == 0) {
        record->code = "codegen.assembly-failed";
    } else if (strcmp(phase, "codegen") == 0) {
        record->code = "codegen.failed";
    } else if (strcmp(phase, "optimization-record") == 0) {
        record->code = "codegen.optimization-record-failed";
    } else if (strcmp(phase, "disassemble") == 0) {
        record->code = "codegen.disassembly-failed";
    } else if (strcmp(phase, "link") == 0) {
        record->code = "link.failed";
    } else if (strcmp(phase, "publish") == 0) {
        record->code = "publish.failed";
    } else {
        record->code = "driver.failed";
    }

    if (token != NULL) {
        (void)weave_diag_unique_token_span(
            sources, source_count, token, list_head, record);
        free(token);
    }
    if (record->source == NULL && strcmp(phase, "frontend") == 0 && source_count == 1) {
        record->source = sources[0];
    }
}

static int weave_diag_stable_exit_code(const char *phase, int raw_exit_code) {
    if (raw_exit_code == 0) {
        return 0;
    }
    if (strcmp(phase, "frontend") == 0) return WEAVEC_EXIT_FRONTEND;
    if (strcmp(phase, "backend") == 0) return WEAVEC_EXIT_BACKEND;
    if (strcmp(phase, "optimize") == 0 ||
        strcmp(phase, "assembly") == 0 ||
        strcmp(phase, "codegen") == 0 ||
        strcmp(phase, "optimization-record") == 0 ||
        strcmp(phase, "disassemble") == 0) return WEAVEC_EXIT_CODEGEN;
    if (strcmp(phase, "link") == 0) return WEAVEC_EXIT_LINK;
    if (strcmp(phase, "publish") == 0) return WEAVEC_EXIT_PUBLISH;
    if (raw_exit_code == 2) return 2;
    return WEAVEC_EXIT_DRIVER;
}

static void weave_diag_read_manifest_phase(
    const char *path,
    char *phase,
    size_t phase_size) {
    (void)snprintf(phase, phase_size, "%s", "driver");
    size_t length = 0;
    unsigned char *data = weave_diag_read_file(path, &length);
    if (data == NULL) {
        return;
    }
    const char *needle = "\"phase\"";
    char *found = strstr((char *)data, needle);
    if (found != NULL) {
        found = strchr(found + strlen(needle), ':');
    }
    if (found != NULL) {
        found = strchr(found, '"');
    }
    if (found != NULL) {
        ++found;
        char *end = strchr(found, '"');
        if (end != NULL) {
            size_t count = (size_t)(end - found);
            if (count >= phase_size) count = phase_size - 1;
            memcpy(phase, found, count);
            phase[count] = '\0';
        }
    }
    free(data);
}

#include "diagnostics_json.c"

static char *weave_diag_read_text(const char *path) {
    size_t length = 0;
    unsigned char *data = weave_diag_read_file(path, &length);
    return (char *)data;
}

static int weave_diag_option_takes_value(const char *arg) {
    return strcmp(arg, "-o") == 0 || strcmp(arg, "--output") == 0 ||
           strcmp(arg, "--project") == 0 ||
           strcmp(arg, "--target") == 0 || strcmp(arg, "--runtime") == 0 ||
           strcmp(arg, "--optimizer") == 0 ||
           strcmp(arg, "--codegen") == 0 ||
           strcmp(arg, "--target-codegen") == 0 ||
           strcmp(arg, "--llc") == 0 || strcmp(arg, "--linker") == 0 ||
           strcmp(arg, "--objdump") == 0 ||
           strcmp(arg, "--manifest-json") == 0 ||
           strcmp(arg, "--trace-json") == 0 ||
           strcmp(arg, "--emit-wir") == 0 ||
           strcmp(arg, "--emit-llvm") == 0 ||
           strcmp(arg, "--emit-optimized-llvm") == 0 ||
           strcmp(arg, "--emit-assembly") == 0 ||
           strcmp(arg, "--emit-disassembly") == 0 ||
           strcmp(arg, "--optimization-record") == 0 ||
           strcmp(arg, "--cpu") == 0 || strcmp(arg, "--march") == 0 ||
           strcmp(arg, "--tune-cpu") == 0 || strcmp(arg, "--mtune") == 0;
}

// Collect the positional source arguments of a build invocation. Options and
// their values are skipped so the caller sees only compilable inputs.
static int weave_diag_collect_sources(
    char **filtered,
    int filtered_argc,
    char **sources) {
    int source_count = 0;
    for (int i = 2; i < filtered_argc; ++i) {
        if (strcmp(filtered[i], "--keep-temporaries") == 0) {
            continue;
        }
        if (filtered[i][0] == '-') {
            if (weave_diag_option_takes_value(filtered[i]) && i + 1 < filtered_argc) {
                ++i;
            }
            continue;
        }
        sources[source_count++] = filtered[i];
    }
    return source_count;
}

// Write one preflight diagnostic to stderr, resolving its span to a line and
// column when the source is still readable.
static void weave_diag_report_record(
    const char *source,
    const weave_diag_record *record) {
    size_t length = 0;
    unsigned char *data = weave_diag_read_file(source, &length);
    size_t line = 0, column = 0;
    if (data != NULL && record->has_span) {
        weave_diag_position(data, length, record->start_byte, &line, &column);
        fprintf(
            stderr, "weavec: error: %s:%zu:%zu: %s\n",
            source, line, column, record->message);
    } else {
        fprintf(stderr, "weavec: error: %s: %s\n", source, record->message);
    }
    free(data);
}

int weave_rt_build_main(int argc, char **argv) {
    const char *diagnostics_path = NULL;
    const char *manifest_path = NULL;
    const char *trace_path = NULL;
    const char *output_path = NULL;
    const char *wir_path = NULL;
    const char *llvm_path = NULL;
    const char *optimized_llvm_path = NULL;
    const char *assembly_path = NULL;
    const char *disassembly_path = NULL;
    const char *optimization_record_path = NULL;
    char **filtered = calloc((size_t)argc + 4, sizeof(*filtered));
    char **sources = calloc((size_t)argc, sizeof(*sources));
    if (filtered == NULL || sources == NULL) {
        free(filtered);
        free(sources);
        fputs("weavec: out of memory\n", stderr);
        return 1;
    }

    int filtered_argc = 0;
    filtered[filtered_argc++] = argv[0];
    filtered[filtered_argc++] = argv[1];
    for (int i = 2; i < argc; ++i) {
        if (strcmp(argv[i], "--diagnostics-json") == 0) {
            if (++i >= argc) {
                fputs("weavec: --diagnostics-json requires a path\n", stderr);
                free(filtered);
                free(sources);
                return 2;
            }
            diagnostics_path = argv[i];
            continue;
        }
        filtered[filtered_argc++] = argv[i];
        if ((strcmp(argv[i], "-o") == 0 ||
             strcmp(argv[i], "--output") == 0) && i + 1 < argc) {
            output_path = argv[i + 1];
        }
        if (strcmp(argv[i], "--manifest-json") == 0 && i + 1 < argc) {
            manifest_path = argv[i + 1];
        }
        if (strcmp(argv[i], "--trace-json") == 0 && i + 1 < argc) {
            trace_path = argv[i + 1];
        }
        if (strcmp(argv[i], "--emit-wir") == 0 && i + 1 < argc) {
            wir_path = argv[i + 1];
        }
        if (strcmp(argv[i], "--emit-llvm") == 0 && i + 1 < argc) {
            llvm_path = argv[i + 1];
        }
        if (strcmp(argv[i], "--emit-optimized-llvm") == 0 && i + 1 < argc) {
            optimized_llvm_path = argv[i + 1];
        }
        if (strcmp(argv[i], "--emit-assembly") == 0 && i + 1 < argc) {
            assembly_path = argv[i + 1];
        }
        if (strcmp(argv[i], "--emit-disassembly") == 0 && i + 1 < argc) {
            disassembly_path = argv[i + 1];
        }
        if (strcmp(argv[i], "--optimization-record") == 0 && i + 1 < argc) {
            optimization_record_path = argv[i + 1];
        }
    }
    filtered[filtered_argc] = NULL;

    if (diagnostics_path == NULL) {
        // Human-readable parse diagnostics are baseline build behavior. Without
        // this preflight the legacy path reports a malformed source only as a
        // non-zero exit status with empty stderr.
        int source_count =
            weave_diag_collect_sources(filtered, filtered_argc, sources);
        weave_diag_record record = {0};
        for (int i = 0; i < source_count; ++i) {
            if (weave_diag_preflight_source(sources[i], &record)) {
                weave_diag_report_record(sources[i], &record);
                weave_diag_record_clear(&record);
                free(filtered);
                free(sources);
                // Stable public phase exits stay tied to --diagnostics-json.
                return 1;
            }
        }
        int result = weave_rt_build_main_legacy(filtered_argc, filtered);
        free(filtered);
        free(sources);
        return result;
    }
    const char *requested_paths[] = {
        output_path,
        manifest_path,
        trace_path,
        wir_path,
        llvm_path,
        optimized_llvm_path,
        assembly_path,
        disassembly_path,
        optimization_record_path,
        diagnostics_path,
    };
    if (requested_paths_conflict(
            requested_paths,
            sizeof(requested_paths) / sizeof(requested_paths[0]))) {
        fputs("weavec: all requested output paths must differ\n", stderr);
        weave_diag_record record = {
            .code = "driver.conflicting-output-paths",
            .severity = "error",
            .phase = "driver",
            .message = "all requested output paths must differ",
            .span_origin = "none",
        };
        weave_diag_write_result(
            diagnostics_path, "failed", "driver", 2, 2, &record);
        free(filtered);
        free(sources);
        return 2;
    }

    int source_count =
        weave_diag_collect_sources(filtered, filtered_argc, sources);

    weave_diag_record record = {0};
    for (int i = 0; i < source_count; ++i) {
        if (weave_diag_preflight_source(sources[i], &record)) {
            weave_diag_report_record(sources[i], &record);
            int exit_code = strcmp(record.phase, "driver") == 0
                ? WEAVEC_EXIT_DRIVER : WEAVEC_EXIT_FRONTEND;
            weave_diag_write_result(
                diagnostics_path, "failed", record.phase,
                exit_code, 1, &record);
            (void)weave_trace_write_document(
                trace_path, "failed", record.phase, sources, source_count,
                NULL);
            weave_diag_record_clear(&record);
            free(filtered);
            free(sources);
            return exit_code;
        }
    }

    char temporary_manifest[PATH_MAX] = {0};
    int owns_manifest = 0;
    if (manifest_path == NULL) {
        const char *tmp_root = getenv("TMPDIR");
        if (tmp_root == NULL || *tmp_root == '\0') tmp_root = "/tmp";
        if (snprintf(
                temporary_manifest, sizeof(temporary_manifest),
                "%s/weavec-manifest-XXXXXX", tmp_root) >= (int)sizeof(temporary_manifest)) {
            weave_diag_record driver_record = {
                .code = "driver.temporary-path-too-long",
                .severity = "error",
                .phase = "driver",
                .message = "temporary manifest path is too long",
                .span_origin = "none",
            };
            weave_diag_write_result(
                diagnostics_path, "failed", "driver",
                WEAVEC_EXIT_DRIVER, 1, &driver_record);
            free(filtered);
            free(sources);
            return WEAVEC_EXIT_DRIVER;
        }
        int manifest_fd = mkstemp(temporary_manifest);
        if (manifest_fd < 0) {
            weave_diag_record driver_record = {
                .code = "driver.temporary-manifest-failed",
                .severity = "error",
                .phase = "driver",
                .message = "cannot create temporary manifest",
                .span_origin = "none",
            };
            weave_diag_write_result(
                diagnostics_path, "failed", "driver",
                WEAVEC_EXIT_DRIVER, 1, &driver_record);
            free(filtered);
            free(sources);
            return WEAVEC_EXIT_DRIVER;
        }
        close(manifest_fd);
        unlink(temporary_manifest);
        filtered[filtered_argc++] = "--manifest-json";
        filtered[filtered_argc++] = temporary_manifest;
        filtered[filtered_argc] = NULL;
        manifest_path = temporary_manifest;
        owns_manifest = 1;
    }

    char stderr_template[PATH_MAX];
    const char *tmp_root = getenv("TMPDIR");
    if (tmp_root == NULL || *tmp_root == '\0') tmp_root = "/tmp";
    if (snprintf(stderr_template, sizeof(stderr_template),
                 "%s/weavec-stderr-XXXXXX", tmp_root) >= (int)sizeof(stderr_template)) {
        free(filtered);
        free(sources);
        if (owns_manifest) unlink(temporary_manifest);
        return WEAVEC_EXIT_DRIVER;
    }
    int capture_fd = mkstemp(stderr_template);
    int saved_stderr = capture_fd >= 0 ? dup(STDERR_FILENO) : -1;
    int raw_exit_code;
    if (capture_fd >= 0 && saved_stderr >= 0 && dup2(capture_fd, STDERR_FILENO) >= 0) {
        close(capture_fd);
        raw_exit_code = weave_rt_build_main_legacy(filtered_argc, filtered);
        fflush(stderr);
        (void)dup2(saved_stderr, STDERR_FILENO);
        close(saved_stderr);
    } else {
        if (capture_fd >= 0) close(capture_fd);
        if (saved_stderr >= 0) close(saved_stderr);
        raw_exit_code = weave_rt_build_main_legacy(filtered_argc, filtered);
    }

    char *stderr_text = weave_diag_read_text(stderr_template);
    if (stderr_text != NULL && *stderr_text != '\0') {
        fputs(stderr_text, stderr);
    }
    unlink(stderr_template);

    char phase[32];
    weave_diag_read_manifest_phase(manifest_path, phase, sizeof(phase));
    if (raw_exit_code == 0) {
        (void)snprintf(phase, sizeof(phase), "%s", "complete");
    }
    int stable_exit_code = weave_diag_stable_exit_code(phase, raw_exit_code);
    if (raw_exit_code != 0) {
        weave_diag_classify_compiler_error(
            phase, stderr_text, sources, source_count, &record);
    }
    int diagnostics_failed = weave_diag_write_result(
        diagnostics_path,
        raw_exit_code == 0 ? "succeeded" : "failed",
        phase,
        stable_exit_code,
        raw_exit_code,
        raw_exit_code == 0 ? NULL : &record);
    if (raw_exit_code == 0 && diagnostics_failed != 0) {
        stable_exit_code = WEAVEC_EXIT_PUBLISH;
    }

    weave_diag_record_clear(&record);
    free(stderr_text);
    if (owns_manifest) unlink(temporary_manifest);
    free(filtered);
    free(sources);
    return stable_exit_code;
}
