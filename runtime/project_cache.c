// SPDX-License-Identifier: Apache-2.0
//
// Content-addressed project artifact cache. This outer wrapper keeps the
// compiler-authoritative project pipeline intact and reuses only exact successful
// artifacts after all project inputs and build controls match.

#ifndef WEAVEC_PROJECT_CACHE_C
#define WEAVEC_PROJECT_CACHE_C

#include <dirent.h>
#include <stdio.h>

#define WEAVE_PROJECT_CACHE_FORMAT "weavec-project-cache-v1"

typedef struct weave_project_cache_options {
    int no_cache;
    int clean;
    const char *cache_dir;
    const char *report;
    int argc;
    char **argv;
} weave_project_cache_options;

static int weave_project_cache_option_value(
    const char *argument,
    const char *name,
    const char **value) {
    size_t length = strlen(name);
    if (strncmp(argument, name, length) != 0 ||
        argument[length] != '=') {
        return 0;
    }
    *value = argument + length + 1;
    return 1;
}

static void weave_project_cache_options_clear(
    weave_project_cache_options *options) {
    free(options->argv);
    memset(options, 0, sizeof(*options));
}

static int weave_project_cache_parse_options(
    int argc,
    char **argv,
    weave_project_cache_options *options) {
    options->argv = calloc((size_t)argc + 1, sizeof(*options->argv));
    if (options->argv == NULL) {
        fputs("weavec: out of memory while parsing cache options\n", stderr);
        return 0;
    }
    options->argv[options->argc++] = argv[0];
    for (int i = 1; i < argc; ++i) {
        const char *argument = argv[i];
        const char *value = NULL;
        if (strcmp(argument, "--no-cache") == 0) {
            options->no_cache = 1;
            continue;
        }
        if (strcmp(argument, "--clean") == 0) {
            options->clean = 1;
            continue;
        }
        if (strcmp(argument, "--cache-dir") == 0 ||
            strcmp(argument, "--cache-report") == 0) {
            if (i + 1 >= argc || argv[i + 1][0] == '\0') {
                fprintf(stderr, "weavec: %s requires a path\n", argument);
                return 0;
            }
            value = argv[++i];
            if (strcmp(argument, "--cache-dir") == 0) {
                options->cache_dir = value;
            } else {
                options->report = value;
            }
            continue;
        }
        if (weave_project_cache_option_value(
                argument, "--cache-dir", &value)) {
            if (*value == '\0') {
                fputs("weavec: --cache-dir requires a path\n", stderr);
                return 0;
            }
            options->cache_dir = value;
            continue;
        }
        if (weave_project_cache_option_value(
                argument, "--cache-report", &value)) {
            if (*value == '\0') {
                fputs("weavec: --cache-report requires a path\n", stderr);
                return 0;
            }
            options->report = value;
            continue;
        }
        options->argv[options->argc++] = argv[i];
    }
    options->argv[options->argc] = NULL;
    return 1;
}

static int weave_project_cache_has_help(
    const weave_project_cache_options *options) {
    for (int i = 2; i < options->argc; ++i) {
        if (strcmp(options->argv[i], "-h") == 0 ||
            strcmp(options->argv[i], "--help") == 0) {
            return 1;
        }
    }
    return 0;
}

static void weave_project_cache_usage(void) {
    fputs(
        "\nIncremental project cache options:\n"
        "  --no-cache             build without reading or writing the cache\n"
        "  --clean                clear the selected cache before building\n"
        "  --cache-dir <path>     select a cache base directory\n"
        "  --cache-report <path>  write deterministic cache evidence as JSON\n",
        stdout);
}

static int weave_project_cache_mkdirs(const char *path) {
    if (path == NULL || *path == '\0') return 0;
    char copy[PATH_MAX];
    if (snprintf(copy, sizeof(copy), "%s", path) >= (int)sizeof(copy)) {
        return 0;
    }
    size_t length = strlen(copy);
    while (length > 1 && copy[length - 1] == '/') {
        copy[--length] = '\0';
    }
    for (char *cursor = copy + (copy[0] == '/' ? 1 : 0);
         *cursor != '\0';
         ++cursor) {
        if (*cursor != '/') continue;
        *cursor = '\0';
        struct stat status;
        if (lstat(copy, &status) != 0) {
            if (errno != ENOENT || mkdir(copy, 0700) != 0) {
                *cursor = '/';
                return 0;
            }
        } else if (!S_ISDIR(status.st_mode) || S_ISLNK(status.st_mode)) {
            *cursor = '/';
            return 0;
        }
        *cursor = '/';
    }
    struct stat status;
    if (lstat(copy, &status) != 0) {
        return errno == ENOENT && mkdir(copy, 0700) == 0;
    }
    return S_ISDIR(status.st_mode) && !S_ISLNK(status.st_mode);
}

static int weave_project_cache_remove_tree(const char *path) {
    struct stat status;
    if (lstat(path, &status) != 0) {
        return errno == ENOENT;
    }
    if (S_ISLNK(status.st_mode) || !S_ISDIR(status.st_mode)) {
        return unlink(path) == 0;
    }
    DIR *directory = opendir(path);
    if (directory == NULL) return 0;
    int ok = 1;
    struct dirent *entry = NULL;
    while (ok && (entry = readdir(directory)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 ||
            strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        char child[PATH_MAX];
        if (snprintf(
                child, sizeof(child), "%s/%s", path, entry->d_name) >=
            (int)sizeof(child)) {
            ok = 0;
            break;
        }
        ok = weave_project_cache_remove_tree(child);
    }
    if (closedir(directory) != 0) ok = 0;
    return ok && rmdir(path) == 0;
}

static int weave_project_cache_copy_file(
    const char *source,
    const char *destination,
    mode_t mode) {
    int input = open(source, O_RDONLY);
    if (input < 0) return 0;
    struct stat status;
    if (fstat(input, &status) != 0 || !S_ISREG(status.st_mode)) {
        close(input);
        return 0;
    }
    char temporary[PATH_MAX];
    if (snprintf(
            temporary, sizeof(temporary), "%s.weavec-cache-XXXXXX",
            destination) >= (int)sizeof(temporary)) {
        close(input);
        return 0;
    }
    int output = mkstemp(temporary);
    if (output < 0) {
        close(input);
        return 0;
    }
    int ok = 1;
    unsigned char buffer[16384];
    while (ok) {
        ssize_t count = read(input, buffer, sizeof(buffer));
        if (count < 0) {
            if (errno == EINTR) continue;
            ok = 0;
            break;
        }
        if (count == 0) break;
        size_t offset = 0;
        while (offset < (size_t)count) {
            ssize_t written = write(
                output, buffer + offset, (size_t)count - offset);
            if (written < 0) {
                if (errno == EINTR) continue;
                ok = 0;
                break;
            }
            offset += (size_t)written;
        }
    }
    if (ok && fchmod(output, mode & 0777) != 0) ok = 0;
    if (ok && fsync(output) != 0) ok = 0;
    if (close(input) != 0) ok = 0;
    if (close(output) != 0) ok = 0;
    if (ok && rename(temporary, destination) != 0) ok = 0;
    if (!ok) unlink(temporary);
    return ok;
}

static void weave_project_cache_hash_size(
    weave_si_sha256 *hash,
    size_t value) {
    unsigned char encoded[8];
    uint64_t wide = (uint64_t)value;
    for (size_t i = 0; i < sizeof(encoded); ++i) {
        encoded[sizeof(encoded) - i - 1] =
            (unsigned char)(wide >> (i * 8));
    }
    weave_si_sha256_update(hash, encoded, sizeof(encoded));
}

static void weave_project_cache_hash_field(
    weave_si_sha256 *hash,
    const char *name,
    const void *data,
    size_t length) {
    weave_project_cache_hash_size(hash, strlen(name));
    weave_si_sha256_update(hash, name, strlen(name));
    weave_project_cache_hash_size(hash, length);
    weave_si_sha256_update(hash, data, length);
}

static int weave_project_cache_hash_file(
    weave_si_sha256 *hash,
    const char *name,
    const char *path) {
    size_t length = 0;
    unsigned char *data = weave_diag_read_file(path, &length);
    if (data == NULL) return 0;
    weave_project_cache_hash_field(hash, name, data, length);
    free(data);
    return 1;
}

static int weave_project_cache_skip_argument(
    const char *argument) {
    return strcmp(argument, "--project") == 0 ||
        strcmp(argument, "-o") == 0 ||
        strcmp(argument, "--output") == 0;
}

static int weave_project_cache_ignored_argument(
    const char *argument) {
    return strncmp(argument, "--project=", 10) == 0 ||
        strncmp(argument, "--output=", 9) == 0;
}

static int weave_project_cache_extra_outputs(
    const weave_project_request *request,
    const weave_project_cache_options *options) {
    if (request->diagnostics != NULL || request->trace != NULL) return 1;
    for (int i = 2; i < options->argc; ++i) {
        const char *argument = options->argv[i];
        if (strncmp(argument, "--emit-", 7) == 0 ||
            strncmp(argument, "--build-manifest", 16) == 0 ||
            strncmp(argument, "--semantic-index", 16) == 0 ||
            strncmp(argument, "--audit-json", 12) == 0 ||
            strncmp(argument, "--contracts-json", 16) == 0) {
            return 1;
        }
    }
    return 0;
}

static int weave_project_cache_key(
    const weave_project_cache_options *options,
    const weave_project_manifest *manifest,
    const weave_project_source_registry *registry,
    const weave_project_graph *graph,
    char output[65]) {
    weave_si_sha256 hash;
    weave_si_sha256_init(&hash);
    weave_project_cache_hash_field(
        &hash, "format", WEAVE_PROJECT_CACHE_FORMAT,
        strlen(WEAVE_PROJECT_CACHE_FORMAT));
    weave_project_cache_hash_field(
        &hash, "compiler-version", weave_compiler_version,
        strlen(weave_compiler_version));
    weave_project_cache_hash_field(
        &hash, "default-target", WEAVEC_DEFAULT_TARGET,
        strlen(WEAVEC_DEFAULT_TARGET));
    weave_project_cache_hash_field(
        &hash, "default-optimizer", WEAVEC_DEFAULT_OPTIMIZER,
        strlen(WEAVEC_DEFAULT_OPTIMIZER));
    weave_project_cache_hash_field(
        &hash, "default-codegen", WEAVEC_DEFAULT_CODEGEN,
        strlen(WEAVEC_DEFAULT_CODEGEN));
    weave_project_cache_hash_field(
        &hash, "default-linker", WEAVEC_DEFAULT_LINKER,
        strlen(WEAVEC_DEFAULT_LINKER));
    if (!weave_project_cache_hash_file(
            &hash, "manifest", manifest->path)) {
        return 0;
    }
    for (size_t order = 0; order < graph->order_count; ++order) {
        size_t index = graph->order[order];
        const weave_project_source *source = &registry->items[index];
        weave_project_cache_hash_field(
            &hash, "module", source->module_name,
            strlen(source->module_name));
        weave_project_cache_hash_field(
            &hash, "logical-path", source->logical_path,
            strlen(source->logical_path));
        if (!weave_project_cache_hash_file(
                &hash, "source", source->physical_path)) {
            return 0;
        }
    }
    for (int i = 2; i < options->argc; ++i) {
        const char *argument = options->argv[i];
        if (weave_project_cache_skip_argument(argument)) {
            ++i;
            continue;
        }
        if (weave_project_cache_ignored_argument(argument)) continue;
        weave_project_cache_hash_field(
            &hash, "build-argument", argument, strlen(argument));
    }
    const char *runtime = getenv("WEAVEC_RUNTIME");
    if (runtime != NULL && *runtime != '\0') {
        if (!weave_project_cache_hash_file(
                &hash, "runtime", runtime)) {
            weave_project_cache_hash_field(
                &hash, "runtime-path", runtime, strlen(runtime));
        }
    }
    unsigned char digest[32];
    weave_si_sha256_finish(&hash, digest);
    weave_si_hex(digest, output);
    return 1;
}

static int weave_project_cache_resolve_root(
    const weave_project_cache_options *options,
    const weave_project_manifest *manifest,
    char root[PATH_MAX]) {
    char base[PATH_MAX];
    if (options->cache_dir != NULL) {
        if (options->cache_dir[0] == '/') {
            if (snprintf(
                    base, sizeof(base), "%s", options->cache_dir) >=
                (int)sizeof(base)) {
                return 0;
            }
        } else {
            char cwd[PATH_MAX];
            if (getcwd(cwd, sizeof(cwd)) == NULL ||
                snprintf(
                    base, sizeof(base), "%s/%s",
                    cwd, options->cache_dir) >= (int)sizeof(base)) {
                return 0;
            }
        }
    } else if (snprintf(
            base, sizeof(base), "%s/.weave/cache",
            manifest->directory) >= (int)sizeof(base)) {
        return 0;
    }
    return snprintf(
        root, PATH_MAX, "%s/%s", base,
        WEAVE_PROJECT_CACHE_FORMAT) < PATH_MAX;
}

static int weave_project_cache_safe_output(
    const weave_project_manifest *manifest,
    const weave_project_source_registry *registry,
    const char *output) {
    if (weave_path_safety_aliases(output, manifest->path)) return 0;
    for (size_t i = 0; i < registry->count; ++i) {
        if (weave_path_safety_aliases(
                output, registry->items[i].physical_path)) {
            return 0;
        }
    }
    return 1;
}

static int weave_project_cache_safe_report(
    const weave_project_cache_options *options,
    const weave_project_manifest *manifest,
    const weave_project_source_registry *registry,
    const char *output) {
    if (options->report == NULL) return 1;
    if (weave_path_safety_aliases(options->report, output) ||
        weave_path_safety_aliases(options->report, manifest->path)) {
        return 0;
    }
    for (size_t i = 0; i < registry->count; ++i) {
        if (weave_path_safety_aliases(
                options->report,
                registry->items[i].physical_path)) {
            return 0;
        }
    }
    return 1;
}

static int weave_project_cache_digest_file(
    const char *path,
    char output[65],
    mode_t *mode) {
    int descriptor = open(path, O_RDONLY);
    if (descriptor < 0) return 0;
    struct stat status;
    if (fstat(descriptor, &status) != 0 || !S_ISREG(status.st_mode)) {
        close(descriptor);
        return 0;
    }
    weave_si_sha256 hash;
    weave_si_sha256_init(&hash);
    unsigned char buffer[16384];
    int ok = 1;
    while (ok) {
        ssize_t count = read(descriptor, buffer, sizeof(buffer));
        if (count < 0) {
            if (errno == EINTR) continue;
            ok = 0;
            break;
        }
        if (count == 0) break;
        weave_si_sha256_update(&hash, buffer, (size_t)count);
    }
    if (close(descriptor) != 0) ok = 0;
    if (!ok) return 0;
    unsigned char digest[32];
    weave_si_sha256_finish(&hash, digest);
    weave_si_hex(digest, output);
    if (mode != NULL) *mode = status.st_mode;
    return 1;
}

static int weave_project_cache_read_digest(
    const char *path,
    char output[65]) {
    size_t length = 0;
    unsigned char *data = weave_diag_read_file(path, &length);
    if (data == NULL) return 0;
    int ok = length == 65 && data[64] == '\n';
    if (ok) {
        for (size_t i = 0; i < 64; ++i) {
            unsigned char ch = data[i];
            if (!((ch >= '0' && ch <= '9') ||
                  (ch >= 'a' && ch <= 'f'))) {
                ok = 0;
                break;
            }
        }
    }
    if (ok) {
        memcpy(output, data, 64);
        output[64] = '\0';
    }
    free(data);
    return ok;
}

static int weave_project_cache_write_bytes(
    const char *path,
    const void *data,
    size_t length,
    mode_t mode) {
    int descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, mode);
    if (descriptor < 0) return 0;
    size_t offset = 0;
    int ok = 1;
    while (offset < length) {
        ssize_t written = write(
            descriptor, (const unsigned char *)data + offset,
            length - offset);
        if (written < 0) {
            if (errno == EINTR) continue;
            ok = 0;
            break;
        }
        offset += (size_t)written;
    }
    if (ok && fsync(descriptor) != 0) ok = 0;
    if (close(descriptor) != 0) ok = 0;
    if (!ok) unlink(path);
    return ok;
}

static int weave_project_cache_store(
    const char *root,
    const char *key,
    const char *output) {
    if (!weave_project_cache_mkdirs(root)) return 0;
    char entry[PATH_MAX];
    char temporary[PATH_MAX];
    if (snprintf(entry, sizeof(entry), "%s/%s", root, key) >=
            (int)sizeof(entry) ||
        snprintf(
            temporary, sizeof(temporary), "%s/.tmp-XXXXXX", root) >=
            (int)sizeof(temporary) ||
        mkdtemp(temporary) == NULL) {
        return 0;
    }
    char artifact[PATH_MAX];
    char digest_path[PATH_MAX];
    if (snprintf(
            artifact, sizeof(artifact), "%s/artifact", temporary) >=
            (int)sizeof(artifact) ||
        snprintf(
            digest_path, sizeof(digest_path), "%s/artifact.sha256",
            temporary) >= (int)sizeof(digest_path)) {
        weave_project_cache_remove_tree(temporary);
        return 0;
    }
    char digest[65];
    mode_t mode = 0;
    int ok = weave_project_cache_digest_file(output, digest, &mode) &&
        weave_project_cache_copy_file(output, artifact, mode);
    char line[66];
    if (ok) {
        snprintf(line, sizeof(line), "%s\n", digest);
        ok = weave_project_cache_write_bytes(
            digest_path, line, 65, 0600);
    }
    if (ok) {
        (void)weave_project_cache_remove_tree(entry);
        ok = rename(temporary, entry) == 0;
    }
    if (!ok) weave_project_cache_remove_tree(temporary);
    return ok;
}

static int weave_project_cache_restore(
    const char *root,
    const char *key,
    const char *output) {
    char artifact[PATH_MAX];
    char digest_path[PATH_MAX];
    if (snprintf(
            artifact, sizeof(artifact), "%s/%s/artifact",
            root, key) >= (int)sizeof(artifact) ||
        snprintf(
            digest_path, sizeof(digest_path), "%s/%s/artifact.sha256",
            root, key) >= (int)sizeof(digest_path)) {
        return 0;
    }
    char expected[65];
    char actual[65];
    mode_t mode = 0;
    return weave_project_cache_read_digest(digest_path, expected) &&
        weave_project_cache_digest_file(artifact, actual, &mode) &&
        strcmp(expected, actual) == 0 &&
        weave_project_cache_copy_file(artifact, output, mode);
}

static int weave_project_cache_json_string(
    FILE *stream,
    const char *value) {
    if (fputc('"', stream) == EOF) return 0;
    for (const unsigned char *cursor =
             (const unsigned char *)value;
         *cursor != '\0';
         ++cursor) {
        unsigned char ch = *cursor;
        if (ch == '\\' || ch == '"') {
            if (fputc('\\', stream) == EOF ||
                fputc((int)ch, stream) == EOF) {
                return 0;
            }
        } else if (ch < 0x20U) {
            if (fprintf(stream, "\\u%04x", (unsigned int)ch) < 0) {
                return 0;
            }
        } else if (fputc((int)ch, stream) == EOF) {
            return 0;
        }
    }
    return fputc('"', stream) != EOF;
}

static int weave_project_cache_write_report(
    const char *path,
    const char *status,
    const char *key,
    const char *root,
    int exit_code) {
    if (path == NULL) return 1;
    char temporary[PATH_MAX];
    if (snprintf(
            temporary, sizeof(temporary), "%s.tmp-XXXXXX", path) >=
        (int)sizeof(temporary)) {
        return 0;
    }
    int descriptor = mkstemp(temporary);
    if (descriptor < 0) return 0;
    FILE *stream = fdopen(descriptor, "wb");
    if (stream == NULL) {
        close(descriptor);
        unlink(temporary);
        return 0;
    }
    int ok = fputs("{\"format\":", stream) >= 0 &&
        weave_project_cache_json_string(
            stream, WEAVE_PROJECT_CACHE_FORMAT) &&
        fputs(",\"status\":", stream) >= 0 &&
        weave_project_cache_json_string(stream, status) &&
        fputs(",\"key\":", stream) >= 0 &&
        weave_project_cache_json_string(stream, key) &&
        fputs(",\"cache_dir\":", stream) >= 0 &&
        weave_project_cache_json_string(stream, root) &&
        fprintf(stream, ",\"exit_code\":%d}\n", exit_code) >= 0;
    if (ok && fflush(stream) != 0) ok = 0;
    if (ok && fsync(fileno(stream)) != 0) ok = 0;
    if (fclose(stream) != 0) ok = 0;
    if (ok && rename(temporary, path) != 0) ok = 0;
    if (!ok) unlink(temporary);
    return ok;
}

static int weave_project_cache_build(
    weave_project_cache_options *options) {
    weave_project_request request = {0};
    weave_project_error request_error = {0};
    if (!weave_project_parse_request(
            options->argc, options->argv,
            &request, &request_error) ||
        request.help || request.unknown_option != NULL ||
        request.source_count > 0) {
        free(request.output_paths);
        return weave_rt_build_main_project_cache_legacy(
            options->argc, options->argv);
    }

    weave_project_manifest manifest = {0};
    weave_project_error manifest_error = {0};
    if (!weave_project_load(
            request.project, &manifest, &manifest_error)) {
        free(request.output_paths);
        weave_project_manifest_clear(&manifest);
        return weave_rt_build_main_project_cache_legacy(
            options->argc, options->argv);
    }

    weave_project_source_registry registry = {0};
    weave_project_source_error source_error = {0};
    weave_project_graph graph = {0};
    int prepared = weave_project_discover_sources(
        &request, &manifest, &registry, &source_error);
    if (prepared) {
        prepared = weave_project_graph_build(
            &manifest, &registry, &graph, &source_error);
    }
    char output[PATH_MAX] = {0};
    if (prepared) {
        prepared = weave_project_resolve_output(
            &request, &manifest, output, sizeof(output), &source_error);
    }
    if (!prepared ||
        !weave_project_cache_safe_output(
            &manifest, &registry, output) ||
        weave_project_cache_extra_outputs(&request, options)) {
        weave_project_graph_clear(&graph);
        weave_project_source_registry_clear(&registry);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return weave_rt_build_main_project_cache_legacy(
            options->argc, options->argv);
    }
    if (!weave_project_cache_safe_report(
            options, &manifest, &registry, output)) {
        fputs(
            "weavec: cache report aliases a project input or output\n",
            stderr);
        weave_project_graph_clear(&graph);
        weave_project_source_registry_clear(&registry);
        weave_project_manifest_clear(&manifest);
        free(request.output_paths);
        return 2;
    }

    char root[PATH_MAX] = {0};
    char key[65] = {0};
    int cache_ready = weave_project_cache_resolve_root(
            options, &manifest, root) &&
        weave_project_cache_key(
            options, &manifest, &registry, &graph, key);

    if (cache_ready && options->clean) {
        cache_ready = weave_project_cache_remove_tree(root);
    }

    int result = 0;
    const char *status = "disabled";
    if (!options->no_cache && cache_ready &&
        weave_project_cache_restore(root, key, output)) {
        status = "hit";
        result = 0;
    } else {
        result = weave_rt_build_main_project_cache_legacy(
            options->argc, options->argv);
        if (options->no_cache) {
            status = "disabled";
        } else if (!cache_ready) {
            status = "unavailable";
        } else if (result == 0 &&
                   weave_project_cache_store(root, key, output)) {
            status = "miss";
        } else {
            status = result == 0 ? "store-failed" : "build-failed";
        }
    }

    if (!weave_project_cache_write_report(
            options->report, status, key, root, result)) {
        fputs("weavec: cannot publish project cache report\n", stderr);
        if (result == 0) result = 2;
    }

    weave_project_graph_clear(&graph);
    weave_project_source_registry_clear(&registry);
    weave_project_manifest_clear(&manifest);
    free(request.output_paths);
    return result;
}

int weave_rt_build_main(int argc, char **argv) {
    weave_project_cache_options options = {0};
    if (!weave_project_cache_parse_options(
            argc, argv, &options)) {
        weave_project_cache_options_clear(&options);
        return 2;
    }
    int result = 0;
    if (options.argc >= 2 &&
        strcmp(options.argv[1], "build") == 0) {
        result = weave_project_cache_build(&options);
        if (weave_project_cache_has_help(&options)) {
            weave_project_cache_usage();
        }
    } else {
        result = weave_rt_build_main_project_cache_legacy(
            options.argc, options.argv);
    }
    weave_project_cache_options_clear(&options);
    return result;
}

#endif
