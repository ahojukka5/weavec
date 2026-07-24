// SPDX-License-Identifier: Apache-2.0
// Private source-to-executable driver used by the public `weavec build` command.

#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#ifndef WEAVEC_DEFAULT_CC
#define WEAVEC_DEFAULT_CC "clang"
#endif

static void driver_error(const char *message) {
    fprintf(stderr, "weavec: build: %s\n", message);
}

static int path_exists(const char *path) {
    return path != NULL && access(path, R_OK) == 0;
}

static int run_command(char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) {
        perror("weavec: build: fork");
        return 1;
    }
    if (pid == 0) {
        execvp(argv[0], argv);
        fprintf(stderr, "weavec: build: cannot execute %s: %s\n", argv[0], strerror(errno));
        _exit(127);
    }

    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) {
            perror("weavec: build: waitpid");
            return 1;
        }
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        fprintf(stderr, "weavec: build: %s terminated by signal %d\n", argv[0], WTERMSIG(status));
        return 128 + WTERMSIG(status);
    }
    return 1;
}

static int resolve_executable(const char *argv0, char *resolved, size_t size) {
#if defined(__linux__)
    ssize_t count = readlink("/proc/self/exe", resolved, size - 1);
    if (count > 0 && (size_t)count < size) {
        resolved[count] = '\0';
        return 0;
    }
#endif
    if (argv0 == NULL || argv0[0] == '\0') {
        return -1;
    }
    if (strchr(argv0, '/') != NULL) {
        return realpath(argv0, resolved) == NULL ? -1 : 0;
    }

    const char *path = getenv("PATH");
    if (path == NULL) {
        return -1;
    }
    char *copy = strdup(path);
    if (copy == NULL) {
        return -1;
    }
    int result = -1;
    char *save = NULL;
    for (char *entry = strtok_r(copy, ":", &save); entry != NULL;
         entry = strtok_r(NULL, ":", &save)) {
        const char *directory = entry[0] == '\0' ? "." : entry;
        if (snprintf(resolved, size, "%s/%s", directory, argv0) >= (int)size) {
            continue;
        }
        if (access(resolved, X_OK) == 0) {
            char canonical[PATH_MAX];
            if (realpath(resolved, canonical) != NULL) {
                snprintf(resolved, size, "%s", canonical);
            }
            result = 0;
            break;
        }
    }
    free(copy);
    return result;
}

static int parent_directory(const char *path, char *result, size_t size) {
    if (path == NULL || snprintf(result, size, "%s", path) >= (int)size) {
        return -1;
    }
    char *slash = strrchr(result, '/');
    if (slash == NULL) {
        return snprintf(result, size, ".") >= (int)size ? -1 : 0;
    }
    if (slash == result) {
        slash[1] = '\0';
    } else {
        *slash = '\0';
    }
    return 0;
}

static int resolve_runtime(const char *compiler, char *runtime, size_t size) {
    const char *configured = getenv("WEAVEC_RUNTIME");
    if (path_exists(configured)) {
        return snprintf(runtime, size, "%s", configured) >= (int)size ? -1 : 0;
    }

    char bin_directory[PATH_MAX];
    if (parent_directory(compiler, bin_directory, sizeof(bin_directory)) != 0) {
        return -1;
    }

    const char *patterns[] = {
        "%s/../lib/weavec/libweave-runtime.a",
        "%s/runtime/libweave-runtime.a",
    };
    for (size_t index = 0; index < sizeof(patterns) / sizeof(patterns[0]); ++index) {
        if (snprintf(runtime, size, patterns[index], bin_directory) >= (int)size) {
            continue;
        }
        if (path_exists(runtime)) {
            return 0;
        }
    }
    return -1;
}

static void cleanup_build_directory(
    const char *directory,
    const char *wir,
    const char *llvm,
    const char *temporary_binary
) {
    if (wir != NULL) {
        (void)unlink(wir);
    }
    if (llvm != NULL) {
        (void)unlink(llvm);
    }
    if (temporary_binary != NULL) {
        (void)unlink(temporary_binary);
    }
    if (directory != NULL) {
        (void)rmdir(directory);
    }
}

static void print_usage(void) {
    fputs(
        "usage: weavec build [--keep-temporaries] <input.weave> "
        "[input2.weave ...] -o <output>\n",
        stderr
    );
}

int weave_driver_build(int argc, char **argv) {
    if (argc < 5 || argv == NULL) {
        print_usage();
        return 2;
    }

    int keep_temporaries = 0;
    const char *output = NULL;
    char **inputs = calloc((size_t)argc, sizeof(char *));
    if (inputs == NULL) {
        driver_error("out of memory");
        return 1;
    }
    int input_count = 0;

    for (int index = 2; index < argc; ++index) {
        if (strcmp(argv[index], "--keep-temporaries") == 0) {
            keep_temporaries = 1;
        } else if (strcmp(argv[index], "-o") == 0 || strcmp(argv[index], "--output") == 0) {
            if (output != NULL || index + 1 >= argc) {
                print_usage();
                free(inputs);
                return 2;
            }
            output = argv[++index];
        } else if (argv[index][0] == '-') {
            fprintf(stderr, "weavec: build: unknown option: %s\n", argv[index]);
            free(inputs);
            return 2;
        } else {
            inputs[input_count++] = argv[index];
        }
    }

    if (output == NULL || output[0] == '\0' || input_count == 0) {
        print_usage();
        free(inputs);
        return 2;
    }

    char compiler[PATH_MAX];
    if (resolve_executable(argv[0], compiler, sizeof(compiler)) != 0) {
        driver_error("cannot resolve the weavec executable path");
        free(inputs);
        return 1;
    }

    char runtime[PATH_MAX];
    if (resolve_runtime(compiler, runtime, sizeof(runtime)) != 0) {
        driver_error(
            "private runtime not found; reinstall the weavec package or set WEAVEC_RUNTIME"
        );
        free(inputs);
        return 1;
    }

    size_t template_length = strlen(output) + sizeof(".weavec-build-XXXXXX");
    char *build_directory = malloc(template_length);
    if (build_directory == NULL) {
        driver_error("out of memory");
        free(inputs);
        return 1;
    }
    snprintf(build_directory, template_length, "%s.weavec-build-XXXXXX", output);
    if (mkdtemp(build_directory) == NULL) {
        fprintf(stderr, "weavec: build: cannot create temporary directory: %s\n", strerror(errno));
        free(build_directory);
        free(inputs);
        return 1;
    }

    char wir[PATH_MAX];
    char llvm[PATH_MAX];
    char temporary_binary[PATH_MAX];
    if (snprintf(wir, sizeof(wir), "%s/program.wir", build_directory) >= (int)sizeof(wir) ||
        snprintf(llvm, sizeof(llvm), "%s/program.ll", build_directory) >= (int)sizeof(llvm) ||
        snprintf(temporary_binary, sizeof(temporary_binary), "%s/program", build_directory) >=
            (int)sizeof(temporary_binary)) {
        driver_error("output path is too long");
        cleanup_build_directory(build_directory, NULL, NULL, NULL);
        free(build_directory);
        free(inputs);
        return 1;
    }

    char **frontend = calloc((size_t)input_count + 5, sizeof(char *));
    if (frontend == NULL) {
        driver_error("out of memory");
        cleanup_build_directory(build_directory, wir, llvm, temporary_binary);
        free(build_directory);
        free(inputs);
        return 1;
    }
    frontend[0] = compiler;
    frontend[1] = "--frontend";
    frontend[2] = wir;
    for (int index = 0; index < input_count; ++index) {
        frontend[index + 3] = inputs[index];
    }
    frontend[input_count + 3] = NULL;

    int status = run_command(frontend);
    free(frontend);
    if (status == 0) {
        char *backend[] = {compiler, "--backend", wir, llvm, NULL};
        status = run_command(backend);
    }
    if (status == 0) {
        const char *configured_cc = getenv("WEAVEC_CC");
        char *cc = (char *)((configured_cc != NULL && configured_cc[0] != '\0')
            ? configured_cc
            : WEAVEC_DEFAULT_CC);
        char *link[] = {cc, llvm, runtime, "-o", temporary_binary, NULL};
        status = run_command(link);
    }
    if (status == 0 && rename(temporary_binary, output) != 0) {
        fprintf(stderr, "weavec: build: cannot install output %s: %s\n", output, strerror(errno));
        status = 1;
    }

    if (keep_temporaries) {
        fprintf(stderr, "weavec: build: intermediates: %s\n", build_directory);
    } else {
        cleanup_build_directory(build_directory, wir, llvm, temporary_binary);
    }

    free(build_directory);
    free(inputs);
    return status;
}
