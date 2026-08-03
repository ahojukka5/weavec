// SPDX-License-Identifier: Apache-2.0
//
// Deterministic source discovery for manifest-selected project builds. This
// wrapper consumes the #119 manifest boundary and deliberately stops before the
// import graph and entry selection owned by #121.

#ifndef WEAVEC_PROJECT_SOURCES_C
#define WEAVEC_PROJECT_SOURCES_C

#include <dirent.h>
#include <stdarg.h>

#define WEAVE_PROJECT_SOURCES_ENV "WEAVEC_INTERNAL_PROJECT_SOURCES"

typedef struct weave_project_source {
    char *logical_path;
    char *physical_path;
    char *module_name;
    size_t module_start;
    size_t module_end;
} weave_project_source;

typedef struct weave_project_source_registry {
    weave_project_source *items;
    size_t count;
    size_t capacity;
} weave_project_source_registry;

typedef struct weave_project_source_error {
    const char *code;
    char message[PATH_MAX * 3];
    char logical_source[PATH_MAX];
    char physical_source[PATH_MAX];
    size_t start;
    size_t end;
    int has_logical_source;
    int has_physical_source;
    int has_span;
} weave_project_source_error;

static void weave_project_source_registry_clear(
    weave_project_source_registry *registry) {
    for (size_t i = 0; i < registry->count; ++i) {
        free(registry->items[i].logical_path);
        free(registry->items[i].physical_path);
        free(registry->items[i].module_name);
    }
    free(registry->items);
    memset(registry, 0, sizeof(*registry));
}

static void weave_project_source_error_paths(
    weave_project_source_error *error,
    const char *logical_source,
    const char *physical_source) {
    if (logical_source != NULL &&
        snprintf(
            error->logical_source, sizeof(error->logical_source), "%s",
            logical_source) < (int)sizeof(error->logical_source)) {
        error->has_logical_source = 1;
    }
    if (physical_source != NULL &&
        snprintf(
            error->physical_source, sizeof(error->physical_source), "%s",
            physical_source) < (int)sizeof(error->physical_source)) {
        error->has_physical_source = 1;
    }
}

static int weave_project_source_fail(
    weave_project_source_error *error,
    const char *code,
    const char *message,
    const char *logical_source,
    const char *physical_source,
    size_t start,
    size_t end,
    int has_span) {
    if (error->code == NULL) {
        error->code = code;
        (void)snprintf(error->message, sizeof(error->message), "%s", message);
        weave_project_source_error_paths(
            error, logical_source, physical_source);
        error->start = start;
        error->end = end;
        error->has_span = has_span;
    }
    return 0;
}

static int weave_project_source_failf(
    weave_project_source_error *error,
    const char *code,
    const char *logical_source,
    const char *physical_source,
    size_t start,
    size_t end,
    int has_span,
    const char *format,
    ...) {
    if (error->code == NULL) {
        error->code = code;
        va_list arguments;
        va_start(arguments, format);
        (void)vsnprintf(
            error->message, sizeof(error->message), format, arguments);
        va_end(arguments);
        weave_project_source_error_paths(
            error, logical_source, physical_source);
        error->start = start;
        error->end = end;
        error->has_span = has_span;
    }
    return 0;
}

static int weave_project_path_within(
    const char *parent,
    const char *path) {
    size_t length = strlen(parent);
    if (strcmp(parent, "/") == 0) return path[0] == '/';
    return strncmp(parent, path, length) == 0 &&
        (path[length] == '\0' || path[length] == '/');
}

static int weave_project_path_overlap(
    const char *left,
    const char *right) {
    return weave_project_path_within(left, right) ||
        weave_project_path_within(right, left);
}

static int weave_project_join_path(
    char *output,
    size_t output_size,
    const char *left,
    const char *right) {
    int written = snprintf(
        output, output_size, "%s%s%s",
        left, strcmp(left, "/") == 0 ? "" : "/", right);
    return written >= 0 && written < (int)output_size;
}

static int weave_project_has_source_extension(const char *name) {
    size_t length = strlen(name);
    return length >= 6 && strcmp(name + length - 6, ".weave") == 0;
}

static int weave_project_name_compare(const void *left, const void *right) {
    const char *const *left_name = left;
    const char *const *right_name = right;
    return strcmp(*left_name, *right_name);
}

static int weave_project_node_span(
    void *tree,
    int64_t node,
    size_t source_length,
    size_t *start_out,
    size_t *end_out) {
    if (node < 0) return 0;
    int64_t start = node_text_start(tree, node);
    int64_t length = node_text_len(tree, node);
    if (start < 0 || length < 0 ||
        (size_t)start > source_length ||
        (size_t)length > source_length - (size_t)start) {
        return 0;
    }
    *start_out = (size_t)start;
    *end_out = (size_t)start + (size_t)length;
    return 1;
}

static int weave_project_node_text_equals(
    const char *bytes,
    size_t length,
    void *tree,
    int64_t node,
    const char *expected) {
    if (node < 0 || node_kind(tree, node) != node_ident()) return 0;
    int64_t start = node_text_start(tree, node);
    int64_t size = node_text_len(tree, node);
    size_t expected_size = strlen(expected);
    return start >= 0 && size >= 0 &&
        (size_t)start <= length && (size_t)size <= length - (size_t)start &&
        (size_t)size == expected_size &&
        memcmp(bytes + start, expected, expected_size) == 0;
}

static char *weave_project_node_text(
    const char *bytes,
    size_t length,
    void *tree,
    int64_t node,
    size_t *start_out,
    size_t *end_out) {
    if (node < 0 || node_kind(tree, node) != node_ident()) return NULL;
    int64_t start = node_text_start(tree, node);
    int64_t size = node_text_len(tree, node);
    if (start < 0 || size < 0 ||
        (size_t)start > length || (size_t)size > length - (size_t)start) {
        return NULL;
    }
    char *copy = malloc((size_t)size + 1);
    if (copy == NULL) return NULL;
    memcpy(copy, bytes + start, (size_t)size);
    copy[(size_t)size] = '\0';
    *start_out = (size_t)start;
    *end_out = (size_t)start + (size_t)size;
    return copy;
}

static int weave_project_registry_append(
    weave_project_source_registry *registry,
    weave_project_source item) {
    if (registry->count == registry->capacity) {
        size_t capacity = registry->capacity == 0 ? 8 : registry->capacity * 2;
        if (capacity < registry->capacity ||
            capacity > SIZE_MAX / sizeof(*registry->items)) {
            return 0;
        }
        weave_project_source *grown = realloc(
            registry->items, capacity * sizeof(*registry->items));
        if (grown == NULL) return 0;
        registry->items = grown;
        registry->capacity = capacity;
    }
    registry->items[registry->count++] = item;
    return 1;
}

static const char *weave_project_output_alias(
    const weave_project_request *request,
    const char *physical_path) {
    for (int i = 0; i < request->output_path_count; ++i) {
        if (weave_path_safety_aliases(
                request->output_paths[i], physical_path)) {
            return request->output_paths[i];
        }
    }
    return NULL;
}

static int weave_project_parse_source(
    const char *logical_path,
    const char *physical_path,
    weave_project_source_registry *registry,
    weave_project_source_error *error) {
    size_t length = 0;
    unsigned char *raw = weave_diag_read_file(physical_path, &length);
    if (raw == NULL) {
        return weave_project_source_failf(
            error, "project.source.read", logical_path, physical_path,
            0, 0, 0, "cannot read project source %s", logical_path);
    }
    if (memchr(raw, '\0', length) != NULL) {
        free(raw);
        return weave_project_source_failf(
            error, "project.source.parse", logical_path, physical_path,
            0, 0, 0, "project source %s contains NUL", logical_path);
    }

    void *tokens = lex((const char *)raw, (int64_t)length);
    void *tree = tokens == NULL ? NULL : parse(tokens);
    if (tokens == NULL || tree == NULL || node_kind(tree, 0) != node_list()) {
        if (tree != NULL) tree_free(tree);
        if (tokens != NULL) tokens_free(tokens);
        free(raw);
        return weave_project_source_failf(
            error, "project.source.parse", logical_path, physical_path,
            0, 0, 0, "cannot parse project source %s", logical_path);
    }

    int64_t head = node_first_child(tree, 0);
    size_t head_start = 0;
    size_t head_end = 0;
    int has_head_span = weave_project_node_span(
        tree, head, length, &head_start, &head_end);
    if (weave_project_node_text_equals(
            (const char *)raw, length, tree, head, "program")) {
        tree_free(tree);
        tokens_free(tokens);
        free(raw);
        return weave_project_source_failf(
            error, "project.source.legacy-root", logical_path, physical_path,
            head_start, head_end, has_head_span,
            "project source %s uses legacy program root; project sources require explicit modules",
            logical_path);
    }
    if (!weave_project_node_text_equals(
            (const char *)raw, length, tree, head, "module")) {
        tree_free(tree);
        tokens_free(tokens);
        free(raw);
        return weave_project_source_failf(
            error, "project.source.module-root", logical_path, physical_path,
            head_start, head_end, has_head_span,
            "project source %s does not have an explicit module root",
            logical_path);
    }

    int64_t name_node = node_next_sibling(tree, head);
    size_t name_start = 0;
    size_t name_end = 0;
    char *module_name = weave_project_node_text(
        (const char *)raw, length, tree, name_node, &name_start, &name_end);
    int valid_identity = module_name != NULL &&
        weave_project_identifier(module_name);
    if (!valid_identity) {
        int has_name_span = module_name != NULL;
        free(module_name);
        tree_free(tree);
        tokens_free(tokens);
        free(raw);
        return weave_project_source_failf(
            error, "project.source.module-identity", logical_path, physical_path,
            name_start, name_end, has_name_span,
            "project source %s has no portable module identity", logical_path);
    }

    for (size_t i = 0; i < registry->count; ++i) {
        if (strcmp(registry->items[i].module_name, module_name) == 0) {
            int result = weave_project_source_failf(
                error, "project.source.duplicate-module",
                logical_path, physical_path, name_start, name_end, 1,
                "module %s is declared by both %s and %s",
                module_name, registry->items[i].logical_path, logical_path);
            free(module_name);
            tree_free(tree);
            tokens_free(tokens);
            free(raw);
            return result;
        }
    }

    weave_project_source item = {
        .logical_path = strdup(logical_path),
        .physical_path = strdup(physical_path),
        .module_name = module_name,
        .module_start = name_start,
        .module_end = name_end,
    };
    int ok = item.logical_path != NULL && item.physical_path != NULL &&
        weave_project_registry_append(registry, item);
    if (!ok) {
        free(item.logical_path);
        free(item.physical_path);
        free(item.module_name);
        weave_project_source_fail(
            error, "driver.out-of-memory",
            "out of memory while recording project sources",
            logical_path, physical_path, 0, 0, 0);
    }

    tree_free(tree);
    tokens_free(tokens);
    free(raw);
    return ok;
}

static int weave_project_collect_directory(
    const weave_project_request *request,
    const char *project_directory,
    const char *physical_directory,
    const char *logical_directory,
    weave_project_source_registry *registry,
    weave_project_source_error *error) {
    DIR *directory = opendir(physical_directory);
    if (directory == NULL) {
        return weave_project_source_failf(
            error, "project.source.root-read", logical_directory,
            physical_directory, 0, 0, 0,
            "cannot enumerate project source directory %s", logical_directory);
    }

    char **names = NULL;
    size_t count = 0;
    size_t capacity = 0;
    struct dirent *entry = NULL;
    while ((entry = readdir(directory)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 ||
            strcmp(entry->d_name, "..") == 0 || entry->d_name[0] == '.') {
            continue;
        }
        if (count == capacity) {
            size_t next = capacity == 0 ? 16 : capacity * 2;
            if (next < capacity || next > SIZE_MAX / sizeof(*names)) {
                closedir(directory);
                for (size_t i = 0; i < count; ++i) free(names[i]);
                free(names);
                return weave_project_source_fail(
                    error, "driver.out-of-memory",
                    "project source directory is too large",
                    logical_directory, physical_directory, 0, 0, 0);
            }
            char **grown = realloc(names, next * sizeof(*names));
            if (grown == NULL) {
                closedir(directory);
                for (size_t i = 0; i < count; ++i) free(names[i]);
                free(names);
                return weave_project_source_fail(
                    error, "driver.out-of-memory",
                    "out of memory while enumerating project sources",
                    logical_directory, physical_directory, 0, 0, 0);
            }
            names = grown;
            capacity = next;
        }
        names[count] = strdup(entry->d_name);
        if (names[count] == NULL) {
            closedir(directory);
            for (size_t i = 0; i < count; ++i) free(names[i]);
            free(names);
            return weave_project_source_fail(
                error, "driver.out-of-memory",
                "out of memory while enumerating project sources",
                logical_directory, physical_directory, 0, 0, 0);
        }
        ++count;
    }

    int ok = closedir(directory) == 0;
    qsort(names, count, sizeof(*names), weave_project_name_compare);
    if (!ok) {
        weave_project_source_failf(
            error, "project.source.root-read", logical_directory,
            physical_directory, 0, 0, 0,
            "cannot finish enumerating project source directory %s",
            logical_directory);
    }

    for (size_t i = 0; ok && i < count; ++i) {
        char physical[PATH_MAX];
        char logical[PATH_MAX];
        if (!weave_project_join_path(
                physical, sizeof(physical), physical_directory, names[i]) ||
            !weave_project_join_path(
                logical, sizeof(logical), logical_directory, names[i])) {
            ok = weave_project_source_fail(
                error, "project.source.path",
                "project source path is too long",
                logical_directory, physical_directory, 0, 0, 0);
            break;
        }

        struct stat st;
        if (lstat(physical, &st) != 0) {
            ok = weave_project_source_failf(
                error, "project.source.read", logical, physical,
                0, 0, 0, "cannot inspect project source entry %s", logical);
        } else if (S_ISLNK(st.st_mode)) {
            ok = weave_project_source_failf(
                error, "project.source.symlink", logical, physical,
                0, 0, 0, "symlink is not admitted in project source roots: %s",
                logical);
        } else if (S_ISDIR(st.st_mode)) {
            char canonical[PATH_MAX];
            if (realpath(physical, canonical) == NULL ||
                strcmp(physical, canonical) != 0 ||
                !weave_project_path_within(project_directory, canonical)) {
                ok = weave_project_source_failf(
                    error, "project.source.escape", logical, physical,
                    0, 0, 0,
                    "project source directory escapes or aliases its lexical path: %s",
                    logical);
            } else {
                ok = weave_project_collect_directory(
                    request, project_directory, physical, logical,
                    registry, error);
            }
        } else if (S_ISREG(st.st_mode) &&
                   weave_project_has_source_extension(names[i])) {
            char canonical[PATH_MAX];
            if (realpath(physical, canonical) == NULL ||
                strcmp(physical, canonical) != 0 ||
                !weave_project_path_within(project_directory, canonical)) {
                ok = weave_project_source_failf(
                    error, "project.source.escape", logical, physical,
                    0, 0, 0,
                    "project source file escapes or aliases its lexical path: %s",
                    logical);
            } else {
                const char *alias = weave_project_output_alias(request, physical);
                if (alias != NULL) {
                    ok = weave_project_source_failf(
                        error, "driver.output-aliases-project-source",
                        logical, physical, 0, 0, 0,
                        "output path %s aliases project source %s",
                        alias, logical);
                } else {
                    ok = weave_project_parse_source(
                        logical, physical, registry, error);
                }
            }
        }
    }

    for (size_t i = 0; i < count; ++i) free(names[i]);
    free(names);
    return ok;
}

static int weave_project_discover_sources(
    const weave_project_request *request,
    const weave_project_manifest *manifest,
    weave_project_source_registry *registry,
    weave_project_source_error *error) {
    char **canonical_roots = calloc(
        manifest->source_root_count, sizeof(*canonical_roots));
    if (canonical_roots == NULL) {
        return weave_project_source_fail(
            error, "driver.out-of-memory",
            "out of memory while validating project source roots",
            NULL, NULL, 0, 0, 0);
    }

    int ok = 1;
    for (size_t i = 0; ok && i < manifest->source_root_count; ++i) {
        char lexical[PATH_MAX];
        if (!weave_project_join_path(
                lexical, sizeof(lexical), manifest->directory,
                manifest->source_roots[i])) {
            ok = weave_project_source_fail(
                error, "project.source.path",
                "project source root path is too long",
                manifest->source_roots[i], NULL, 0, 0, 0);
            break;
        }
        struct stat st;
        if (lstat(lexical, &st) != 0) {
            ok = weave_project_source_failf(
                error, "project.source.root-read",
                manifest->source_roots[i], lexical, 0, 0, 0,
                "project source root does not exist: %s",
                manifest->source_roots[i]);
            break;
        }
        if (S_ISLNK(st.st_mode)) {
            ok = weave_project_source_failf(
                error, "project.source.symlink",
                manifest->source_roots[i], lexical, 0, 0, 0,
                "project source root is a symlink: %s",
                manifest->source_roots[i]);
            break;
        }
        if (!S_ISDIR(st.st_mode)) {
            ok = weave_project_source_failf(
                error, "project.source.root-read",
                manifest->source_roots[i], lexical, 0, 0, 0,
                "project source root is not a directory: %s",
                manifest->source_roots[i]);
            break;
        }
        char canonical[PATH_MAX];
        if (realpath(lexical, canonical) == NULL ||
            strcmp(lexical, canonical) != 0 ||
            !weave_project_path_within(manifest->directory, canonical)) {
            ok = weave_project_source_failf(
                error, "project.source.escape",
                manifest->source_roots[i], lexical, 0, 0, 0,
                "project source root escapes or aliases its lexical path: %s",
                manifest->source_roots[i]);
            break;
        }
        for (size_t j = 0; j < i; ++j) {
            if (weave_project_path_overlap(canonical_roots[j], canonical)) {
                ok = weave_project_source_failf(
                    error, "project.source.root-alias",
                    manifest->source_roots[i], lexical, 0, 0, 0,
                    "project source roots resolve to overlapping paths: %s and %s",
                    manifest->source_roots[j], manifest->source_roots[i]);
                break;
            }
        }
        if (!ok) break;
        canonical_roots[i] = strdup(canonical);
        if (canonical_roots[i] == NULL) {
            ok = weave_project_source_fail(
                error, "driver.out-of-memory",
                "out of memory while validating project source roots",
                manifest->source_roots[i], lexical, 0, 0, 0);
        }
    }

    for (size_t i = 0; ok && i < manifest->source_root_count; ++i) {
        ok = weave_project_collect_directory(
            request, manifest->directory, canonical_roots[i],
            manifest->source_roots[i], registry, error);
    }
    for (size_t i = 0; i < manifest->source_root_count; ++i) {
        free(canonical_roots[i]);
    }
    free(canonical_roots);

    if (ok && registry->count == 0) {
        ok = weave_project_source_fail(
            error, "project.source.empty",
            "project source roots contain no admitted .weave module sources",
            manifest->path, manifest->path, 0, 0, 0);
    }
    return ok;
}

static int weave_project_publish_source_error(
    const weave_project_source_error *error,
    const char *diagnostics_path,
    const char *trace_path,
    int raw_exit) {
    size_t line = 0;
    size_t column = 0;
    if (error->has_span && error->has_physical_source) {
        size_t length = 0;
        unsigned char *data = weave_diag_read_file(
            error->physical_source, &length);
        if (data != NULL) {
            weave_diag_position(data, length, error->start, &line, &column);
            free(data);
        }
    }
    if (error->has_logical_source && error->has_span && line > 0) {
        fprintf(
            stderr, "weavec: error: %s:%zu:%zu: %s [%s]\n",
            error->logical_source, line, column,
            error->message, error->code);
    } else if (error->has_logical_source) {
        fprintf(
            stderr, "weavec: error: %s: %s [%s]\n",
            error->logical_source, error->message, error->code);
    } else {
        fprintf(stderr, "weavec: error: %s [%s]\n", error->message, error->code);
    }

    weave_diag_record record = {
        .code = error->code,
        .severity = "error",
        .phase = "driver",
        .message = error->message,
        .source = error->has_logical_source ? error->logical_source : NULL,
        .span_origin = error->has_span
            ? "compiler-project-source-parser" : "none",
        .start_byte = error->start,
        .end_byte = error->end,
        .has_span = error->has_span,
    };
    if (diagnostics_path != NULL) {
        const char *previous_span_source = weave_diag_span_source_override;
        weave_diag_span_source_override = error->has_physical_source
            ? error->physical_source : NULL;
        (void)weave_diag_write_result(
            diagnostics_path, "failed", "driver",
            WEAVEC_EXIT_DRIVER, raw_exit, &record);
        weave_diag_span_source_override = previous_span_source;
    }
    if (trace_path != NULL) {
        (void)weave_trace_write_document(
            trace_path, "failed", "driver", NULL, 0, NULL);
    }
    return diagnostics_path != NULL ? WEAVEC_EXIT_DRIVER : raw_exit;
}

static void weave_project_safe_protocol_outputs(
    const weave_project_request *request,
    const weave_project_source_error *error,
    const char **diagnostics,
    const char **trace) {
    *diagnostics = request->diagnostics;
    *trace = request->trace;
    if (!error->has_physical_source) return;
    if (*diagnostics != NULL && weave_path_safety_aliases(
            *diagnostics, error->physical_source)) {
        *diagnostics = NULL;
    }
    if (*trace != NULL && weave_path_safety_aliases(
            *trace, error->physical_source)) {
        *trace = NULL;
    }
}

static int weave_project_publish_internal_sources(
    const weave_project_manifest *manifest,
    const weave_project_source_registry *registry,
    weave_project_source_error *error) {
    const char *path = getenv(WEAVE_PROJECT_SOURCES_ENV);
    if (path == NULL || *path == '\0') return 1;
    if (weave_path_safety_aliases(path, manifest->path)) {
        return weave_project_source_fail(
            error, "driver.internal-output-alias",
            "internal project-source registry aliases the project manifest",
            path, path, 0, 0, 0);
    }
    for (size_t i = 0; i < registry->count; ++i) {
        if (weave_path_safety_aliases(path, registry->items[i].physical_path)) {
            return weave_project_source_fail(
                error, "driver.internal-output-alias",
                "internal project-source registry aliases a project source",
                registry->items[i].logical_path,
                registry->items[i].physical_path, 0, 0, 0);
        }
    }

    FILE *stream = fopen(path, "wb");
    if (stream == NULL) {
        return weave_project_source_fail(
            error, "driver.internal-output-write",
            "cannot write internal project-source registry",
            path, path, 0, 0, 0);
    }
    int ok = 1;
    for (size_t i = 0; ok && i < registry->count; ++i) {
        ok = fprintf(
            stream, "%s\t%s\n",
            registry->items[i].module_name,
            registry->items[i].logical_path) >= 0;
    }
    if (fclose(stream) != 0) ok = 0;
    if (!ok) {
        (void)unlink(path);
        return weave_project_source_fail(
            error, "driver.internal-output-write",
            "cannot finish internal project-source registry",
            path, path, 0, 0, 0);
    }
    return 1;
}

int weave_rt_build_main(int argc, char **argv) {
    if (argc < 2 || strcmp(argv[1], "build") != 0) {
        return weave_rt_build_main_project_legacy(argc, argv);
    }

    weave_project_request request = {0};
    weave_project_error manifest_error = {0};
    if (!weave_project_parse_request(argc, argv, &request, &manifest_error) ||
        request.help || request.unknown_option != NULL ||
        request.source_count > 0) {
        free(request.output_paths);
        return weave_rt_build_main_project_legacy(argc, argv);
    }

    weave_project_manifest manifest = {0};
    if (!weave_project_load(request.project, &manifest, &manifest_error)) {
        int result = weave_project_publish_error(
            &manifest_error, request.diagnostics, request.trace, 2);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return result;
    }

    const char *manifest_conflict = NULL;
    if (weave_project_outputs_alias_manifest(
            &request, manifest.path, &manifest_conflict)) {
        manifest_error.code = "driver.output-aliases-project-manifest";
        manifest_error.message =
            "an output path aliases the selected project manifest";
        manifest_error.source = manifest_conflict;
        const char *diagnostics = request.diagnostics;
        const char *trace = request.trace;
        if (diagnostics != NULL &&
            weave_path_safety_aliases(diagnostics, manifest.path)) {
            diagnostics = NULL;
        }
        if (trace != NULL && weave_path_safety_aliases(trace, manifest.path)) {
            trace = NULL;
        }
        int result = weave_project_publish_error(
            &manifest_error, diagnostics, trace, 2);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return result;
    }

    weave_project_source_registry registry = {0};
    weave_project_source_error source_error = {0};
    if (!weave_project_discover_sources(
            &request, &manifest, &registry, &source_error)) {
        const char *diagnostics = NULL;
        const char *trace = NULL;
        weave_project_safe_protocol_outputs(
            &request, &source_error, &diagnostics, &trace);
        int result = weave_project_publish_source_error(
            &source_error, diagnostics, trace, 2);
        weave_project_source_registry_clear(&registry);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return result;
    }

    if (!weave_project_publish_internal_sources(
            &manifest, &registry, &source_error)) {
        const char *diagnostics = NULL;
        const char *trace = NULL;
        weave_project_safe_protocol_outputs(
            &request, &source_error, &diagnostics, &trace);
        int result = weave_project_publish_source_error(
            &source_error, diagnostics, trace, 2);
        weave_project_source_registry_clear(&registry);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return result;
    }

    char resolved_output[PATH_MAX];
    int output_ok = request.output != NULL
        ? snprintf(
              resolved_output, sizeof(resolved_output), "%s",
              request.output) < (int)sizeof(resolved_output)
        : weave_project_join_path(
              resolved_output, sizeof(resolved_output),
              manifest.directory, manifest.output);
    if (!output_ok) {
        (void)weave_project_source_fail(
            &source_error, "project.manifest.output",
            "resolved project output path is too long",
            manifest.path, manifest.path, 0, 0, 0);
    } else {
        char pending[PATH_MAX * 3];
        (void)snprintf(
            pending, sizeof(pending),
            "discovered %zu project modules for output %s; graph resolution is not yet available",
            registry.count, resolved_output);
        (void)weave_project_source_fail(
            &source_error, "project.graph.pending", pending,
            manifest.path, manifest.path, 0, 0, 0);
    }

    int result = weave_project_publish_source_error(
        &source_error, request.diagnostics, request.trace, 2);
    weave_project_source_registry_clear(&registry);
    weave_project_manifest_clear(&manifest);
    free(request.output_paths);
    return result;
}

#endif
