// SPDX-License-Identifier: Apache-2.0
//
// Public source-to-executable driver for weavec. The self-hosted compiler owns
// surface lowering and LLVM emission; this file owns process orchestration,
// private runtime discovery, temporary artifacts, and atomic output publication.

#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#ifndef WEAVEC_DEFAULT_TARGET
#define WEAVEC_DEFAULT_TARGET "unknown-host"
#endif

#ifndef WEAVEC_DEFAULT_LINKER
#define WEAVEC_DEFAULT_LINKER "clang"
#endif

static void build_usage(void) {
    fputs(
        "usage: weavec build <input.weave> [input2.weave ...] -o <program>\n"
        "                    [--target <triple>] [--manifest-json <path>]\n"
        "                    [--runtime <archive>] [--linker <command>]\n"
        "                    [--keep-temporaries]\n",
        stderr);
}

static int file_exists(const char *path) {
    struct stat st;
    return path != NULL && stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static int run_process(char *const args[]) {
    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "weavec: fork failed: %s\n", strerror(errno));
        return 1;
    }
    if (pid == 0) {
        execvp(args[0], args);
        fprintf(stderr, "weavec: cannot execute %s: %s\n", args[0], strerror(errno));
        _exit(127);
    }

    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) {
            fprintf(stderr, "weavec: waitpid failed: %s\n", strerror(errno));
            return 1;
        }
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return 1;
}

static int copy_string(char *out, size_t out_size, const char *value) {
    int written = snprintf(out, out_size, "%s", value);
    return written >= 0 && (size_t)written < out_size;
}

static int resolve_from_path(const char *name, char *out, size_t out_size) {
    const char *path = getenv("PATH");
    if (path == NULL) {
        return 0;
    }

    char *copy = strdup(path);
    if (copy == NULL) {
        return 0;
    }
    char *save = NULL;
    for (char *dir = strtok_r(copy, ":", &save); dir != NULL;
         dir = strtok_r(NULL, ":", &save)) {
        if (*dir == '\0') {
            dir = ".";
        }
        char candidate[PATH_MAX];
        if (snprintf(candidate, sizeof(candidate), "%s/%s", dir, name) >=
            (int)sizeof(candidate)) {
            continue;
        }
        if (access(candidate, X_OK) == 0 && realpath(candidate, out) != NULL) {
            free(copy);
            return 1;
        }
    }
    free(copy);
    return 0;
}

static int resolve_executable(const char *argv0, char *out, size_t out_size) {
#if defined(__linux__)
    ssize_t length = readlink("/proc/self/exe", out, out_size - 1);
    if (length > 0 && (size_t)length < out_size) {
        out[length] = '\0';
        return 1;
    }
#elif defined(__APPLE__)
    uint32_t size = (uint32_t)out_size;
    if (_NSGetExecutablePath(out, &size) == 0) {
        char resolved[PATH_MAX];
        if (realpath(out, resolved) != NULL) {
            return copy_string(out, out_size, resolved);
        }
        return 1;
    }
#endif

    if (strchr(argv0, '/') != NULL) {
        return realpath(argv0, out) != NULL;
    }
    return resolve_from_path(argv0, out, out_size);
}

static void parent_directory(char *path) {
    char *slash = strrchr(path, '/');
    if (slash == NULL) {
        copy_string(path, PATH_MAX, ".");
    } else if (slash == path) {
        slash[1] = '\0';
    } else {
        *slash = '\0';
    }
}

static int runtime_candidate(
    char *out,
    size_t out_size,
    const char *base,
    const char *target,
    int package_parent) {
    int written = package_parent
        ? snprintf(
              out,
              out_size,
              "%s/../lib/weavec/%s/libweave-runtime.a",
              base,
              target)
        : snprintf(
              out,
              out_size,
              "%s/lib/weavec/%s/libweave-runtime.a",
              base,
              target);
    return written >= 0 && (size_t)written < out_size && file_exists(out);
}

static int locate_runtime(
    const char *explicit_path,
    const char *compiler_path,
    const char *target,
    char *out,
    size_t out_size) {
    if (explicit_path != NULL) {
        return file_exists(explicit_path) && copy_string(out, out_size, explicit_path);
    }

    const char *environment = getenv("WEAVEC_RUNTIME");
    if (environment != NULL && *environment != '\0') {
        return file_exists(environment) && copy_string(out, out_size, environment);
    }

    char directory[PATH_MAX];
    if (!copy_string(directory, sizeof(directory), compiler_path)) {
        return 0;
    }
    parent_directory(directory);

    if (runtime_candidate(out, out_size, directory, target, 1)) {
        return 1;
    }
    if (runtime_candidate(out, out_size, directory, target, 0)) {
        return 1;
    }
    return 0;
}

static void json_string(FILE *stream, const char *value) {
    fputc('"', stream);
    for (const unsigned char *p = (const unsigned char *)value; *p != '\0'; ++p) {
        switch (*p) {
            case '\\': fputs("\\\\", stream); break;
            case '"': fputs("\\\"", stream); break;
            case '\n': fputs("\\n", stream); break;
            case '\r': fputs("\\r", stream); break;
            case '\t': fputs("\\t", stream); break;
            default:
                if (*p < 0x20) {
                    fprintf(stream, "\\u%04x", (unsigned int)*p);
                } else {
                    fputc(*p, stream);
                }
        }
    }
    fputc('"', stream);
}

static void write_manifest(
    const char *path,
    const char *status,
    const char *phase,
    const char *target,
    const char *compiler,
    const char *runtime,
    const char *output,
    char **sources,
    int source_count) {
    if (path == NULL) {
        return;
    }
    FILE *stream = fopen(path, "w");
    if (stream == NULL) {
        fprintf(stderr, "weavec: cannot write manifest %s: %s\n", path, strerror(errno));
        return;
    }
    fputs("{\n  \"format\": \"weavec-build-manifest-v1\",\n  \"status\": ", stream);
    json_string(stream, status);
    fputs(",\n  \"phase\": ", stream);
    json_string(stream, phase);
    fputs(",\n  \"target\": ", stream);
    json_string(stream, target);
    fputs(",\n  \"compiler\": ", stream);
    json_string(stream, compiler);
    fputs(",\n  \"runtime\": ", stream);
    json_string(stream, runtime);
    fputs(",\n  \"output\": ", stream);
    json_string(stream, output);
    fputs(",\n  \"sources\": [", stream);
    for (int i = 0; i < source_count; ++i) {
        if (i != 0) {
            fputs(", ", stream);
        }
        json_string(stream, sources[i]);
    }
    fputs("]\n}\n", stream);
    fclose(stream);
}

static void cleanup_directory(
    const char *directory,
    const char *wir_path,
    const char *ll_path,
    int keep) {
    if (keep) {
        fprintf(stderr, "weavec: kept temporary build directory: %s\n", directory);
        return;
    }
    unlink(wir_path);
    unlink(ll_path);
    rmdir(directory);
}

int weave_rt_build_main(int argc, char **argv) {
    const char *output = NULL;
    const char *target = WEAVEC_DEFAULT_TARGET;
    const char *runtime_override = NULL;
    const char *linker = WEAVEC_DEFAULT_LINKER;
    const char *manifest = NULL;
    int keep_temporaries = 0;

    char **sources = calloc((size_t)argc, sizeof(char *));
    if (sources == NULL) {
        fputs("weavec: out of memory\n", stderr);
        return 1;
    }
    int source_count = 0;

    for (int i = 2; i < argc; ++i) {
        const char *arg = argv[i];
        if (strcmp(arg, "-o") == 0 || strcmp(arg, "--output") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            output = argv[i];
        } else if (strcmp(arg, "--target") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            target = argv[i];
        } else if (strcmp(arg, "--runtime") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            runtime_override = argv[i];
        } else if (strcmp(arg, "--linker") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            linker = argv[i];
        } else if (strcmp(arg, "--manifest-json") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            manifest = argv[i];
        } else if (strcmp(arg, "--keep-temporaries") == 0) {
            keep_temporaries = 1;
        } else if (arg[0] == '-') {
            fprintf(stderr, "weavec: unknown build option: %s\n", arg);
            build_usage();
            free(sources);
            return 2;
        } else {
            sources[source_count++] = argv[i];
        }
    }

    if (source_count == 0 || output == NULL) {
        build_usage();
        free(sources);
        return 2;
    }
    if (strcmp(target, WEAVEC_DEFAULT_TARGET) != 0) {
        fprintf(
            stderr,
            "weavec: target %s is not installed; this package provides %s\n",
            target,
            WEAVEC_DEFAULT_TARGET);
        free(sources);
        return 2;
    }

    char compiler[PATH_MAX];
    if (!resolve_executable(argv[0], compiler, sizeof(compiler))) {
        fprintf(stderr, "weavec: cannot resolve compiler executable: %s\n", argv[0]);
        free(sources);
        return 1;
    }

    char runtime[PATH_MAX];
    if (!locate_runtime(
            runtime_override,
            compiler,
            target,
            runtime,
            sizeof(runtime))) {
        fprintf(
            stderr,
            "weavec: private runtime for target %s was not found\n"
            "weavec: reinstall the compiler package or set WEAVEC_RUNTIME for development\n",
            target);
        free(sources);
        return 1;
    }

    const char *tmp_root = getenv("TMPDIR");
    if (tmp_root == NULL || *tmp_root == '\0') {
        tmp_root = "/tmp";
    }
    char temporary[PATH_MAX];
    if (snprintf(temporary, sizeof(temporary), "%s/weavec-build-XXXXXX", tmp_root) >=
        (int)sizeof(temporary) || mkdtemp(temporary) == NULL) {
        fprintf(stderr, "weavec: cannot create temporary directory: %s\n", strerror(errno));
        free(sources);
        return 1;
    }

    char wir_path[PATH_MAX];
    char ll_path[PATH_MAX];
    snprintf(wir_path, sizeof(wir_path), "%s/program.wir", temporary);
    snprintf(ll_path, sizeof(ll_path), "%s/program.ll", temporary);

    char **frontend = calloc((size_t)source_count + 4, sizeof(char *));
    if (frontend == NULL) {
        cleanup_directory(temporary, wir_path, ll_path, keep_temporaries);
        free(sources);
        return 1;
    }
    frontend[0] = compiler;
    frontend[1] = "--frontend";
    frontend[2] = wir_path;
    for (int i = 0; i < source_count; ++i) {
        frontend[3 + i] = sources[i];
    }
    frontend[3 + source_count] = NULL;

    int status = run_process(frontend);
    free(frontend);
    if (status != 0) {
        write_manifest(
            manifest, "failed", "frontend", target, compiler, runtime, output,
            sources, source_count);
        cleanup_directory(temporary, wir_path, ll_path, keep_temporaries);
        free(sources);
        return status;
    }

    char *backend[] = {compiler, "--backend", wir_path, ll_path, NULL};
    status = run_process(backend);
    if (status != 0) {
        write_manifest(
            manifest, "failed", "backend", target, compiler, runtime, output,
            sources, source_count);
        cleanup_directory(temporary, wir_path, ll_path, keep_temporaries);
        free(sources);
        return status;
    }

    char output_template[PATH_MAX];
    if (snprintf(output_template, sizeof(output_template), "%s.tmp.XXXXXX", output) >=
        (int)sizeof(output_template)) {
        fputs("weavec: output path is too long\n", stderr);
        cleanup_directory(temporary, wir_path, ll_path, keep_temporaries);
        free(sources);
        return 1;
    }
    int output_fd = mkstemp(output_template);
    if (output_fd < 0) {
        fprintf(stderr, "weavec: cannot create output beside %s: %s\n", output, strerror(errno));
        cleanup_directory(temporary, wir_path, ll_path, keep_temporaries);
        free(sources);
        return 1;
    }
    close(output_fd);
    unlink(output_template);

    char *link[] = {(char *)linker, ll_path, runtime, "-o", output_template, NULL};
    status = run_process(link);
    if (status != 0) {
        unlink(output_template);
        write_manifest(
            manifest, "failed", "link", target, compiler, runtime, output,
            sources, source_count);
        cleanup_directory(temporary, wir_path, ll_path, keep_temporaries);
        free(sources);
        return status;
    }

    if (rename(output_template, output) != 0) {
        fprintf(stderr, "weavec: cannot publish output %s: %s\n", output, strerror(errno));
        unlink(output_template);
        write_manifest(
            manifest, "failed", "publish", target, compiler, runtime, output,
            sources, source_count);
        cleanup_directory(temporary, wir_path, ll_path, keep_temporaries);
        free(sources);
        return 1;
    }

    write_manifest(
        manifest, "succeeded", "complete", target, compiler, runtime, output,
        sources, source_count);
    cleanup_directory(temporary, wir_path, ll_path, keep_temporaries);
    free(sources);
    return 0;
}
