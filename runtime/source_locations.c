// SPDX-License-Identifier: Apache-2.0
//
// Exact surface-source locations for diagnostics and LLVM inspection.
//
// Opt-in builds enable comment-only WIR source maps. The frontend emits stable
// source-file and source-span comments, backend diagnostics map errors back to
// surface bytes, and LLVM provenance maps emitted instruction groups to both
// source and WIR forms. Ordinary frontend output, plain WIR, human stderr, and
// code-generation semantics remain unchanged.

#ifndef WEAVEC_SOURCE_MAP_ENV
#define WEAVEC_SOURCE_MAP_ENV "WEAVEC_INTERNAL_SOURCE_LOCATIONS"
#endif
#ifndef WEAVEC_DIAGNOSTIC_SPAN_ENV
#define WEAVEC_DIAGNOSTIC_SPAN_ENV "WEAVEC_INTERNAL_DIAGNOSTIC_WIR_SPAN"
#endif
#ifndef WEAVEC_LLVM_PROVENANCE_ENV
#define WEAVEC_LLVM_PROVENANCE_ENV "WEAVEC_INTERNAL_LLVM_PROVENANCE"
#endif
#define WEAVEC_SOURCE_MAP_PREFIX "; weavec-source-span-v1 "
#define WEAVEC_SOURCE_FILE_PREFIX "; weavec-source-file-v1 "

static int64_t weave_source_location_source_index = -1;

static size_t weave_source_sexpr_length(const char *source, size_t start) {
    if (source == NULL || source[start] != '(') {
        return 0;
    }
    size_t depth = 0;
    int in_string = 0;
    int escaped = 0;
    int in_comment = 0;
    for (size_t index = start; source[index] != '\0'; ++index) {
        unsigned char ch = (unsigned char)source[index];
        if (in_comment) {
            if (ch == '\n') {
                in_comment = 0;
            }
            continue;
        }
        if (in_string) {
            if (escaped) {
                escaped = 0;
            } else if (ch == '\\') {
                escaped = 1;
            } else if (ch == '"') {
                in_string = 0;
            }
            continue;
        }
        if (ch == ';') {
            in_comment = 1;
        } else if (ch == '"') {
            in_string = 1;
        } else if (ch == '(') {
            ++depth;
        } else if (ch == ')') {
            if (depth == 0) {
                return 0;
            }
            --depth;
            if (depth == 0) {
                return index - start + 1;
            }
        }
    }
    return 0;
}

static size_t weave_source_form_end(
    const char *source,
    size_t start,
    size_t fallback_length) {
    size_t end = start + fallback_length;
    if (source == NULL || source[start] != '(') {
        return end;
    }
    size_t final_start = start;
    if (fallback_length > 1 && source[end - 1] == '(') {
        final_start = end - 1;
    }
    size_t final_length = weave_source_sexpr_length(source, final_start);
    return final_length == 0 ? end : final_start + final_length;
}

void weave_rt_set_source_index(int64_t source_index) {
    weave_source_location_source_index = source_index;
}

static void weave_source_location_emit(int fd, const void *buf, size_t n) {
    if (buf == NULL || n == 0) {
        return;
    }
    (void)weave_rt_write((int32_t)fd, buf, (int64_t)n);
}

static void weave_source_location_write_json_fd(int fd, const char *value) {
    const unsigned char *cursor = (const unsigned char *)(value != NULL ? value : "");
    weave_source_location_emit(fd, "\"", 1);
    while (*cursor != '\0') {
        char escaped[7];
        const char *bytes = (const char *)cursor;
        size_t length = 1;
        switch (*cursor) {
            case '\\': bytes = "\\\\"; length = 2; break;
            case '"': bytes = "\\\""; length = 2; break;
            case '\n': bytes = "\\n"; length = 2; break;
            case '\r': bytes = "\\r"; length = 2; break;
            case '\t': bytes = "\\t"; length = 2; break;
            default:
                if (*cursor < 0x20) {
                    int written = snprintf(
                        escaped, sizeof(escaped), "\\u%04x", (unsigned int)*cursor);
                    if (written == 6) {
                        bytes = escaped;
                        length = 6;
                    }
                }
                break;
        }
        weave_source_location_emit(fd, bytes, length);
        ++cursor;
    }
    weave_source_location_emit(fd, "\"", 1);
}

void weave_rt_emit_source_file(
    int fd,
    int64_t source_index,
    const char *source_path) {
    const char *enabled = getenv(WEAVEC_SOURCE_MAP_ENV);
    if (enabled == NULL || strcmp(enabled, "1") != 0 || fd < 0 ||
        source_index < 0 || source_path == NULL) {
        return;
    }
    char prefix[96];
    int written = snprintf(
        prefix,
        sizeof(prefix),
        WEAVEC_SOURCE_FILE_PREFIX "%lld ",
        (long long)source_index);
    if (written <= 0 || (size_t)written >= sizeof(prefix)) {
        return;
    }
    weave_source_location_emit(fd, prefix, (size_t)written);
    weave_source_location_write_json_fd(fd, source_path);
    weave_source_location_emit(fd, "\n", 1);
}

void weave_rt_emit_source_span(
    int fd,
    const char *source,
    int64_t start,
    int64_t length) {
    const char *enabled = getenv(WEAVEC_SOURCE_MAP_ENV);
    (void)source;
    if (enabled == NULL || strcmp(enabled, "1") != 0 || fd < 0 ||
        weave_source_location_source_index < 0 || start < 0 || length < 0) {
        return;
    }
    size_t expanded_end = weave_source_form_end(
        source, (size_t)start, (size_t)length);
    char line[160];
    int written = snprintf(
        line,
        sizeof(line),
        WEAVEC_SOURCE_MAP_PREFIX "%lld %lld %zu\n",
        (long long)weave_source_location_source_index,
        (long long)start,
        expanded_end);
    if (written > 0 && (size_t)written < sizeof(line)) {
        weave_source_location_emit(fd, line, (size_t)written);
    }
}


typedef struct weave_source_location_mapping {
    size_t source_index;
    size_t source_start;
    size_t source_end;
    const char *quoted_path;
    size_t quoted_path_length;
} weave_source_location_mapping;

static int weave_source_location_parse_file_line(
    const char *line,
    const char *line_end,
    size_t *source_index,
    const char **quoted_path,
    size_t *quoted_path_length) {
    unsigned long long parsed_index = 0;
    int consumed = 0;
    if (line == NULL || line_end == NULL || line_end < line ||
        strncmp(line, WEAVEC_SOURCE_FILE_PREFIX,
                strlen(WEAVEC_SOURCE_FILE_PREFIX)) != 0 ||
        sscanf(line + strlen(WEAVEC_SOURCE_FILE_PREFIX),
               "%llu %n", &parsed_index, &consumed) != 1 ||
        parsed_index > SIZE_MAX) {
        return 0;
    }
    const char *quoted = line + strlen(WEAVEC_SOURCE_FILE_PREFIX) + consumed;
    if (quoted >= line_end || *quoted != '"') {
        return 0;
    }
    *source_index = (size_t)parsed_index;
    *quoted_path = quoted;
    *quoted_path_length = (size_t)(line_end - quoted);
    return 1;
}

static int weave_source_location_parse_span_line(
    const char *line,
    size_t *source_index,
    size_t *source_start,
    size_t *source_end) {
    unsigned long long parsed_index = 0;
    unsigned long long parsed_start = 0;
    unsigned long long parsed_end = 0;
    if (line == NULL ||
        strncmp(line, WEAVEC_SOURCE_MAP_PREFIX,
                strlen(WEAVEC_SOURCE_MAP_PREFIX)) != 0 ||
        sscanf(line + strlen(WEAVEC_SOURCE_MAP_PREFIX),
               "%llu %llu %llu", &parsed_index, &parsed_start,
               &parsed_end) != 3 ||
        parsed_index > SIZE_MAX || parsed_start > parsed_end ||
        parsed_start > SIZE_MAX || parsed_end > SIZE_MAX) {
        return 0;
    }
    *source_index = (size_t)parsed_index;
    *source_start = (size_t)parsed_start;
    *source_end = (size_t)parsed_end;
    return 1;
}

static int weave_source_location_lookup_wir(
    const char *wir,
    size_t wir_start,
    weave_source_location_mapping *result) {
    if (wir == NULL || result == NULL) {
        return 0;
    }
    memset(result, 0, sizeof(*result));

    int found_mapping = 0;
    const char *cursor = wir;
    while (cursor < wir + wir_start) {
        const char *mapping = strstr(cursor, WEAVEC_SOURCE_MAP_PREFIX);
        if (mapping == NULL || (size_t)(mapping - wir) >= wir_start) {
            break;
        }
        const char *line_end = strchr(mapping, '\n');
        if (line_end == NULL || (size_t)(line_end - wir) > wir_start) {
            break;
        }
        size_t source_index = 0;
        size_t source_start = 0;
        size_t source_end = 0;
        if (weave_source_location_parse_span_line(
                mapping, &source_index, &source_start, &source_end)) {
            result->source_index = source_index;
            result->source_start = source_start;
            result->source_end = source_end;
            found_mapping = 1;
        }
        cursor = line_end + 1;
    }
    if (!found_mapping) {
        return 0;
    }

    cursor = wir;
    while (cursor < wir + wir_start) {
        const char *file = strstr(cursor, WEAVEC_SOURCE_FILE_PREFIX);
        if (file == NULL || (size_t)(file - wir) >= wir_start) {
            break;
        }
        const char *line_end = strchr(file, '\n');
        if (line_end == NULL || (size_t)(line_end - wir) > wir_start) {
            break;
        }
        size_t source_index = 0;
        const char *quoted_path = NULL;
        size_t quoted_path_length = 0;
        if (weave_source_location_parse_file_line(
                file, line_end, &source_index, &quoted_path,
                &quoted_path_length) &&
            source_index == result->source_index) {
            result->quoted_path = quoted_path;
            result->quoted_path_length = quoted_path_length;
        }
        cursor = line_end + 1;
    }
    return 1;
}

void weave_rt_emit_llvm_source_span(
    int fd,
    const char *wir_source,
    int64_t wir_start,
    int64_t wir_length,
    int64_t kind) {
    const char *enabled = getenv(WEAVEC_LLVM_PROVENANCE_ENV);
    if (enabled == NULL || strcmp(enabled, "1") != 0 || fd < 0 ||
        wir_source == NULL || wir_start < 0 || wir_length < 0) {
        return;
    }
    weave_source_location_mapping mapping;
    if (!weave_source_location_lookup_wir(
            wir_source, (size_t)wir_start, &mapping)) {
        return;
    }

    static size_t last_index = SIZE_MAX;
    static size_t last_start = SIZE_MAX;
    static size_t last_end = SIZE_MAX;
    static int64_t last_kind = -1;
    static int64_t last_wir_start = -1;
    if (mapping.source_index == last_index &&
        mapping.source_start == last_start &&
        mapping.source_end == last_end && kind == last_kind &&
        wir_start == last_wir_start) {
        return;
    }
    last_index = mapping.source_index;
    last_start = mapping.source_start;
    last_end = mapping.source_end;
    last_kind = kind;
    last_wir_start = wir_start;

    size_t wir_end = weave_source_form_end(
        wir_source, (size_t)wir_start, (size_t)wir_length);
    const char *kind_name = kind == 0 ? "function" : "statement";
    char prefix[256];
    int written = snprintf(
        prefix,
        sizeof(prefix),
        "; weave.source kind=%s index=%zu bytes=%zu..%zu "
        "wir-bytes=%lld..%zu path=",
        kind_name,
        mapping.source_index,
        mapping.source_start,
        mapping.source_end,
        (long long)wir_start,
        wir_end);
    if (written <= 0 || (size_t)written >= sizeof(prefix)) {
        return;
    }
    weave_source_location_emit(fd, prefix, (size_t)written);
    if (mapping.quoted_path != NULL && mapping.quoted_path_length > 0) {
        weave_source_location_emit(
            fd, mapping.quoted_path, mapping.quoted_path_length);
    } else {
        weave_source_location_emit(fd, "null", 4);
    }
    weave_source_location_emit(fd, "\n", 1);
}

void weave_rt_record_diagnostic_wir_span(int fd, int64_t start, int64_t length) {
    const char *path = getenv(WEAVEC_DIAGNOSTIC_SPAN_ENV);
    if (fd != STDERR_FILENO || path == NULL || *path == '\0' ||
        start < 0 || length < 0) {
        return;
    }
    FILE *stream = fopen(path, "w");
    if (stream == NULL) {
        return;
    }
    fprintf(stream, "%lld %lld\n", (long long)start, (long long)length);
    fclose(stream);
}

typedef struct weave_source_location_saved_env {
    int was_set;
    char *value;
} weave_source_location_saved_env;

static weave_source_location_saved_env weave_source_location_save_env(const char *name) {
    weave_source_location_saved_env saved = {0};
    const char *value = getenv(name);
    if (value != NULL) {
        saved.was_set = 1;
        saved.value = strdup(value);
    }
    return saved;
}

static void weave_source_location_restore_env(
    const char *name,
    weave_source_location_saved_env *saved) {
    if (saved->was_set && saved->value != NULL) {
        (void)setenv(name, saved->value, 1);
    } else {
        (void)unsetenv(name);
    }
    free(saved->value);
    saved->value = NULL;
}

static int weave_source_location_option_takes_value(const char *arg) {
    return strcmp(arg, "-o") == 0 || strcmp(arg, "--output") == 0 ||
           strcmp(arg, "--target") == 0 || strcmp(arg, "--runtime") == 0 ||
           strcmp(arg, "--optimizer") == 0 ||
           strcmp(arg, "--codegen") == 0 ||
           strcmp(arg, "--target-codegen") == 0 ||
           strcmp(arg, "--llc") == 0 || strcmp(arg, "--linker") == 0 ||
           strcmp(arg, "--manifest-json") == 0 ||
           strcmp(arg, "--diagnostics-json") == 0 ||
           strcmp(arg, "--trace-json") == 0;
}

static const char *weave_source_location_find_option(
    int argc,
    char **argv,
    const char *name) {
    for (int i = 2; i < argc; ++i) {
        if (strcmp(argv[i], name) == 0 && i + 1 < argc) {
            return argv[i + 1];
        }
    }
    return NULL;
}

static int weave_source_location_has_flag(int argc, char **argv, const char *name) {
    for (int i = 2; i < argc; ++i) {
        if (strcmp(argv[i], name) == 0) {
            return 1;
        }
    }
    return 0;
}

static char **weave_source_location_collect_sources(
    int argc,
    char **argv,
    int *count_out) {
    char **sources = calloc((size_t)argc, sizeof(*sources));
    if (sources == NULL) {
        return NULL;
    }
    int count = 0;
    for (int i = 2; i < argc; ++i) {
        if (strcmp(argv[i], "--keep-temporaries") == 0) {
            continue;
        }
        if (argv[i][0] == '-') {
            if (weave_source_location_option_takes_value(argv[i]) && i + 1 < argc) {
                ++i;
            }
            continue;
        }
        sources[count++] = argv[i];
    }
    *count_out = count;
    return sources;
}

static int weave_source_location_make_temp(
    const char *stem,
    char *path,
    size_t path_size) {
    const char *root = getenv("TMPDIR");
    if (root == NULL || *root == '\0') {
        root = "/tmp";
    }
    if (snprintf(path, path_size, "%s/%s-XXXXXX", root, stem) >= (int)path_size) {
        return -1;
    }
    return mkstemp(path);
}

static int weave_source_location_kept_directory(
    const char *stderr_text,
    char *directory,
    size_t directory_size) {
    static const char prefix[] = "weavec: kept temporary build directory: ";
    const char *cursor = stderr_text != NULL ? stderr_text : "";
    while (*cursor != '\0') {
        const char *line_end = strchr(cursor, '\n');
        if (line_end == NULL) {
            line_end = cursor + strlen(cursor);
        }
        if (strncmp(cursor, prefix, sizeof(prefix) - 1) == 0) {
            const char *value = cursor + sizeof(prefix) - 1;
            size_t length = (size_t)(line_end - value);
            if (length > 0 && length < directory_size) {
                memcpy(directory, value, length);
                directory[length] = '\0';
                return 1;
            }
        }
        cursor = *line_end == '\0' ? line_end : line_end + 1;
    }
    return 0;
}

static char *weave_source_location_filter_stderr(
    const char *stderr_text,
    int hide_kept_directory) {
    static const char prefix[] = "weavec: kept temporary build directory: ";
    const char *input = stderr_text != NULL ? stderr_text : "";
    size_t input_length = strlen(input);
    char *output = malloc(input_length + 1);
    if (output == NULL) {
        return NULL;
    }
    size_t used = 0;
    const char *cursor = input;
    while (*cursor != '\0') {
        const char *line_end = strchr(cursor, '\n');
        if (line_end == NULL) {
            line_end = cursor + strlen(cursor);
        }
        size_t line_length = (size_t)(line_end - cursor);
        int has_newline = *line_end == '\n';
        int omit = hide_kept_directory &&
            line_length >= sizeof(prefix) - 1 &&
            strncmp(cursor, prefix, sizeof(prefix) - 1) == 0;
        if (!omit) {
            memcpy(output + used, cursor, line_length);
            used += line_length;
            if (has_newline) {
                output[used++] = '\n';
            }
        }
        cursor = has_newline ? line_end + 1 : line_end;
    }
    output[used] = '\0';
    return output;
}

static int weave_source_location_read_wir_span(
    const char *path,
    size_t *start_out,
    size_t *length_out) {
    FILE *stream = fopen(path, "r");
    if (stream == NULL) {
        return 0;
    }
    unsigned long long start = 0;
    unsigned long long length = 0;
    int matched = fscanf(stream, "%llu %llu", &start, &length) == 2;
    fclose(stream);
    if (!matched || start > SIZE_MAX || length > SIZE_MAX - (size_t)start) {
        return 0;
    }
    *start_out = (size_t)start;
    *length_out = (size_t)length;
    return 1;
}

static int weave_source_location_parse_raw_exit(const char *path, int fallback) {
    size_t length = 0;
    unsigned char *data = weave_diag_read_file(path, &length);
    if (data == NULL) {
        return fallback;
    }
    char *field = strstr((char *)data, "\"raw_exit_code\"");
    if (field != NULL) {
        field = strchr(field, ':');
    }
    int value = fallback;
    if (field != NULL) {
        char *end = NULL;
        long parsed = strtol(field + 1, &end, 10);
        if (end != field + 1 && parsed >= 0 && parsed <= 255) {
            value = (int)parsed;
        }
    }
    free(data);
    return value;
}

static int weave_source_location_map_wir_span(
    const char *wir_path,
    size_t wir_start,
    char **sources,
    int source_count,
    weave_diag_record *record) {
    size_t wir_length = 0;
    unsigned char *wir = weave_diag_read_file(wir_path, &wir_length);
    if (wir == NULL || wir_start > wir_length) {
        free(wir);
        return 0;
    }

    size_t source_index = 0;
    size_t source_start = 0;
    size_t source_end = 0;
    int found_mapping = 0;
    char *cursor = (char *)wir;
    while (cursor < (char *)wir + wir_start) {
        char *mapping = strstr(cursor, WEAVEC_SOURCE_MAP_PREFIX);
        if (mapping == NULL || (size_t)(mapping - (char *)wir) >= wir_start) {
            break;
        }
        char *line_end = strchr(mapping, '\n');
        if (line_end == NULL) {
            break;
        }
        unsigned long long parsed_index = 0;
        unsigned long long parsed_start = 0;
        unsigned long long parsed_end = 0;
        if ((size_t)(line_end - (char *)wir) <= wir_start &&
            sscanf(
                mapping + strlen(WEAVEC_SOURCE_MAP_PREFIX),
                "%llu %llu %llu",
                &parsed_index,
                &parsed_start,
                &parsed_end) == 3 &&
            parsed_index <= SIZE_MAX && parsed_start <= parsed_end &&
            parsed_start <= SIZE_MAX && parsed_end <= SIZE_MAX) {
            source_index = (size_t)parsed_index;
            source_start = (size_t)parsed_start;
            source_end = (size_t)parsed_end;
            found_mapping = 1;
        }
        cursor = line_end + 1;
    }
    free(wir);
    if (!found_mapping) {
        return 0;
    }

    if (source_index >= (size_t)source_count || sources[source_index] == NULL) {
        return 0;
    }
    size_t source_length = 0;
    unsigned char *source = weave_diag_read_file(
        sources[source_index], &source_length);
    if (source == NULL || source_end > source_length) {
        free(source);
        return 0;
    }
    free(source);

    record->source = sources[source_index];
    record->span_origin = "propagated-wir-location";
    record->start_byte = source_start;
    record->end_byte = source_end;
    record->has_span = 1;
    return 1;
}

static void weave_source_location_cleanup_build_directory(const char *directory) {
    if (directory == NULL || *directory == '\0') {
        return;
    }
    const char *names[] = {
        "program.wir",
        "program.ll",
        "program.optimized.ll",
        "program.s",
        "program.o",
        "program.ir.opt.yaml",
        "program.codegen.opt.yaml",
        "program.opt.yaml",
        "program.trace.events",
        "program.disasm",
    };
    char path[PATH_MAX];
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
        if (snprintf(path, sizeof(path), "%s/%s", directory, names[i]) <
            (int)sizeof(path)) {
            unlink(path);
        }
    }
    rmdir(directory);
}

int weave_rt_build_main(int argc, char **argv) {
    const char *diagnostics_path = weave_source_location_find_option(
        argc, argv, "--diagnostics-json");
    if (diagnostics_path == NULL) {
        return weave_rt_build_main_diagnostics_legacy(argc, argv);
    }

    int user_keeps_temporaries =
        weave_source_location_has_flag(argc, argv, "--keep-temporaries") ||
        weave_source_location_has_flag(argc, argv, "--llvm-provenance");
    char **forwarded = calloc((size_t)argc + 2, sizeof(*forwarded));
    if (forwarded == NULL) {
        return weave_rt_build_main_diagnostics_legacy(argc, argv);
    }
    for (int i = 0; i < argc; ++i) {
        forwarded[i] = argv[i];
    }
    int forwarded_argc = argc;
    if (!user_keeps_temporaries) {
        forwarded[forwarded_argc++] = "--keep-temporaries";
    }
    forwarded[forwarded_argc] = NULL;

    char span_path[PATH_MAX];
    char stderr_path[PATH_MAX];
    int span_fd = weave_source_location_make_temp(
        "weavec-source-span", span_path, sizeof(span_path));
    int capture_fd = weave_source_location_make_temp(
        "weavec-source-stderr", stderr_path, sizeof(stderr_path));
    int saved_stderr = capture_fd >= 0 ? dup(STDERR_FILENO) : -1;
    if (span_fd < 0 || capture_fd < 0 || saved_stderr < 0) {
        if (span_fd >= 0) {
            close(span_fd);
            unlink(span_path);
        }
        if (capture_fd >= 0) {
            close(capture_fd);
            unlink(stderr_path);
        }
        if (saved_stderr >= 0) {
            close(saved_stderr);
        }
        free(forwarded);
        return weave_rt_build_main_diagnostics_legacy(argc, argv);
    }
    close(span_fd);

    weave_source_location_saved_env saved_map =
        weave_source_location_save_env(WEAVEC_SOURCE_MAP_ENV);
    weave_source_location_saved_env saved_span =
        weave_source_location_save_env(WEAVEC_DIAGNOSTIC_SPAN_ENV);
    (void)setenv(WEAVEC_SOURCE_MAP_ENV, "1", 1);
    (void)setenv(WEAVEC_DIAGNOSTIC_SPAN_ENV, span_path, 1);

    int redirected = dup2(capture_fd, STDERR_FILENO) >= 0;
    close(capture_fd);
    int result = redirected
        ? weave_rt_build_main_diagnostics_legacy(forwarded_argc, forwarded)
        : weave_rt_build_main_diagnostics_legacy(argc, argv);
    fflush(stderr);
    (void)dup2(saved_stderr, STDERR_FILENO);
    close(saved_stderr);

    weave_source_location_restore_env(WEAVEC_SOURCE_MAP_ENV, &saved_map);
    weave_source_location_restore_env(WEAVEC_DIAGNOSTIC_SPAN_ENV, &saved_span);
    free(forwarded);

    char *captured = weave_diag_read_text(stderr_path);
    unlink(stderr_path);
    char kept_directory[PATH_MAX] = {0};
    int has_kept_directory = weave_source_location_kept_directory(
        captured, kept_directory, sizeof(kept_directory));
    int hide_kept_directory = !user_keeps_temporaries && has_kept_directory;
    char *human_stderr = weave_source_location_filter_stderr(
        captured, hide_kept_directory);
    if (human_stderr != NULL) {
        fputs(human_stderr, stderr);
    } else if (captured != NULL) {
        fputs(captured, stderr);
    }

    if (result == WEAVEC_EXIT_BACKEND && has_kept_directory) {
        char wir_path[PATH_MAX];
        if (snprintf(wir_path, sizeof(wir_path), "%s/program.wir", kept_directory) <
            (int)sizeof(wir_path)) {
            size_t wir_start = 0;
            size_t wir_span_length = 0;
            int source_count = 0;
            char **sources = weave_source_location_collect_sources(
                argc, argv, &source_count);
            weave_diag_record record = {0};
            const char *diagnostic_text = human_stderr != NULL
                ? human_stderr : captured;
            weave_diag_classify_compiler_error(
                "backend", diagnostic_text, sources, source_count, &record);
            if (sources != NULL &&
                weave_source_location_read_wir_span(
                    span_path, &wir_start, &wir_span_length) &&
                weave_source_location_map_wir_span(
                    wir_path, wir_start, sources, source_count, &record)) {
                int raw_exit_code = weave_source_location_parse_raw_exit(
                    diagnostics_path, 1);
                weave_diag_write_result(
                    diagnostics_path,
                    "failed",
                    "backend",
                    WEAVEC_EXIT_BACKEND,
                    raw_exit_code,
                    &record);
            }
            weave_diag_record_clear(&record);
            free(sources);
        }
    }

    unlink(span_path);
    if (!user_keeps_temporaries && has_kept_directory) {
        weave_source_location_cleanup_build_directory(kept_directory);
    }
    free(human_stderr);
    free(captured);
    return result;
}
