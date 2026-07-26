// SPDX-License-Identifier: Apache-2.0
//
// Exact surface-source locations for machine-readable backend diagnostics.
//
// Diagnostics builds enable comment-only WIR source maps. The frontend emits one
// mapping comment before each copied AST node, while backend diagnostics record
// the exact WIR token they print. Each mapping uses the source's stable argv index,
// preserving file identity even when two inputs have identical bytes. This wrapper
// joins the two private channels and rewrites only the diagnostics JSON span.
// Ordinary frontend output, plain WIR,
// human stderr, LLVM semantics, and non-diagnostics builds are unchanged.

#define WEAVEC_SOURCE_MAP_ENV "WEAVEC_INTERNAL_SOURCE_LOCATIONS"
#define WEAVEC_DIAGNOSTIC_SPAN_ENV "WEAVEC_INTERNAL_DIAGNOSTIC_WIR_SPAN"
#define WEAVEC_SOURCE_MAP_PREFIX "; weavec-source-span-v1 "

static int64_t weave_source_location_source_index = -1;

void weave_rt_set_source_index(int64_t source_index) {
    weave_source_location_source_index = source_index;
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
    char line[160];
    int written = snprintf(
        line,
        sizeof(line),
        WEAVEC_SOURCE_MAP_PREFIX "%lld %lld %lld\n",
        (long long)weave_source_location_source_index,
        (long long)start,
        (long long)(start + length));
    if (written > 0 && (size_t)written < sizeof(line)) {
        (void)write(fd, line, (size_t)written);
    }
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
           strcmp(arg, "--codegen") == 0 || strcmp(arg, "--linker") == 0 ||
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
    char wir_path[PATH_MAX];
    char ll_path[PATH_MAX];
    char object_path[PATH_MAX];
    if (snprintf(wir_path, sizeof(wir_path), "%s/program.wir", directory) >=
            (int)sizeof(wir_path) ||
        snprintf(ll_path, sizeof(ll_path), "%s/program.ll", directory) >=
            (int)sizeof(ll_path) ||
        snprintf(object_path, sizeof(object_path), "%s/program.o", directory) >=
            (int)sizeof(object_path)) {
        return;
    }
    cleanup_directory(directory, wir_path, ll_path, object_path, 0);
}

int weave_rt_build_main(int argc, char **argv) {
    const char *diagnostics_path = weave_source_location_find_option(
        argc, argv, "--diagnostics-json");
    if (diagnostics_path == NULL) {
        return weave_rt_build_main_diagnostics_legacy(argc, argv);
    }

    int user_keeps_temporaries = weave_source_location_has_flag(
        argc, argv, "--keep-temporaries");
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
