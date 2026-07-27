// SPDX-License-Identifier: Apache-2.0
//
// Public source-to-executable driver for weavec. The self-hosted compiler owns
// surface lowering and LLVM emission; this file owns process orchestration,
// private runtime discovery, temporary artifacts, and atomic output publication.

#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 700
#endif
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

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
#ifndef WEAVEC_DEFAULT_OPTIMIZER
#define WEAVEC_DEFAULT_OPTIMIZER "clang"
#endif
#ifndef WEAVEC_DEFAULT_CODEGEN
#define WEAVEC_DEFAULT_CODEGEN "llc"
#endif
#ifndef WEAVEC_DEFAULT_LINKER
#define WEAVEC_DEFAULT_LINKER "clang"
#endif
#if defined(__APPLE__)
#define WEAVEC_LINK_DEAD_STRIP "-Wl,-dead_strip"
#else
#define WEAVEC_LINK_DEAD_STRIP "-Wl,--gc-sections"
#endif

static int llvm_definition_is_main(const char *line) {
    if (strncmp(line, "define ", 7) != 0) {
        return 0;
    }
    const char *at = strchr(line, '@');
    if (at == NULL) {
        return 0;
    }
    ++at;
    return strncmp(at, "main(", 5) == 0 ||
           strncmp(at, "\"main\"(", 7) == 0;
}

static int internalize_build_module(const char *path) {
    FILE *input = fopen(path, "r");
    if (input == NULL) {
        fprintf(stderr, "weavec: cannot read raw LLVM %s: %s\n", path, strerror(errno));
        return 1;
    }

    char temporary[PATH_MAX];
    if (snprintf(temporary, sizeof(temporary), "%s.internal.XXXXXX", path) >=
        (int)sizeof(temporary)) {
        fprintf(stderr, "weavec: raw LLVM path is too long: %s\n", path);
        fclose(input);
        return 1;
    }
    int output_fd = mkstemp(temporary);
    if (output_fd < 0) {
        fprintf(stderr, "weavec: cannot create internalized LLVM beside %s: %s\n",
                path, strerror(errno));
        fclose(input);
        return 1;
    }
    FILE *output = fdopen(output_fd, "w");
    if (output == NULL) {
        fprintf(stderr, "weavec: cannot open internalized LLVM stream: %s\n",
                strerror(errno));
        close(output_fd);
        unlink(temporary);
        fclose(input);
        return 1;
    }

    char *line = NULL;
    size_t capacity = 0;
    int failed = 0;
    while (getline(&line, &capacity, input) >= 0) {
        if (strncmp(line, "define ", 7) == 0 &&
            !llvm_definition_is_main(line)) {
            if (fputs("define internal ", output) == EOF ||
                fputs(line + 7, output) == EOF) {
                failed = 1;
                break;
            }
        } else if (fputs(line, output) == EOF) {
            failed = 1;
            break;
        }
    }
    if (ferror(input)) {
        failed = 1;
    }
    free(line);
    int input_close_failed = fclose(input) != 0;
    int output_close_failed = fclose(output) != 0;
    if (input_close_failed || output_close_failed) {
        failed = 1;
    }
    if (failed) {
        fprintf(stderr, "weavec: failed to internalize raw LLVM %s\n", path);
        unlink(temporary);
        return 1;
    }
    if (rename(temporary, path) != 0) {
        fprintf(stderr, "weavec: cannot publish internalized LLVM %s: %s\n",
                path, strerror(errno));
        unlink(temporary);
        return 1;
    }
    return 0;
}

static void build_usage(void) {
    fputs(
        "usage: weavec build <input.weave> [input2.weave ...] -o <program>\n"
        "                    [--target <triple>] [--manifest-json <path>]\n"
        "                    [--trace-json <path>] [--emit-wir <path>]\n"
        "                    [--emit-llvm <path>] [--emit-optimized-llvm <path>]\n"
        "                    [--emit-assembly <path>] [--emit-disassembly <path>]\n"
        "                    [--optimization-record <path>] [--llvm-provenance]\n"
        "                    [-O0|-O1|-O2|-O3|-Os|-Oz] [--native]\n"
        "                    [--cpu <name>] [--tune-cpu <name>]\n"
        "                    [--runtime <archive>] [--optimizer <command>]\n"
        "                    [--target-codegen <command>] [--linker <command>]\n"
        "                    [--objdump <command>]\n"
        "                    [--keep-temporaries]\n",
        stderr);
}

static int file_exists(const char *path) {
    struct stat st;
    return path != NULL && stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static int copy_string(char *out, size_t out_size, const char *value) {
    int written = snprintf(out, out_size, "%s", value);
    return written >= 0 && (size_t)written < out_size;
}

static int resolve_from_path(const char *name, char *out, size_t out_size) {
    (void)out_size;
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
        (void)copy_string(path, PATH_MAX, ".");
    } else if (slash == path) {
        slash[1] = '\0';
    } else {
        *slash = '\0';
    }
}

static int runtime_archive_candidate(
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

    if (runtime_archive_candidate(out, out_size, directory, target, 1)) {
        return 1;
    }
    if (runtime_archive_candidate(out, out_size, directory, target, 0)) {
        return 1;
    }

    // Development checkout fallback: build/weavec sits beside ../runtime/.
    int written = snprintf(out, out_size, "%s/../runtime/program.c", directory);
    return written >= 0 && (size_t)written < out_size && file_exists(out);
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
    const char *optimizer,
    const char *codegen,
    const char *linker,
    const char *objdump,
    const char *optimization,
    const char *cpu,
    const char *tune_cpu,
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
    fputs(",\n  \"optimizer\": ", stream);
    json_string(stream, optimizer);
    fputs(",\n  \"codegen\": ", stream);
    json_string(stream, codegen);
    fputs(",\n  \"linker\": ", stream);
    json_string(stream, linker);
    fputs(",\n  \"objdump\": ", stream);
    json_string(stream, objdump);
    fputs(",\n  \"optimization\": {\"level\": ", stream);
    json_string(stream, optimization);
    fputs(", \"cpu\": ", stream);
    if (cpu == NULL) {
        fputs("null", stream);
    } else {
        json_string(stream, cpu);
    }
    fputs(", \"tune_cpu\": ", stream);
    if (tune_cpu == NULL) {
        fputs("null", stream);
    } else {
        json_string(stream, tune_cpu);
    }
    fputs("}", stream);
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

static int same_path(const char *left, const char *right) {
    return left != NULL && right != NULL && strcmp(left, right) == 0;
}

static int requested_paths_conflict(
    const char *const paths[],
    size_t count) {
    for (size_t i = 0; i < count; ++i) {
        for (size_t j = i + 1; j < count; ++j) {
            if (same_path(paths[i], paths[j])) {
                return 1;
            }
        }
    }
    return 0;
}

static int write_all(int fd, const unsigned char *data, size_t length) {
    while (length > 0) {
        ssize_t written = write(fd, data, length);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            return 0;
        }
        data += (size_t)written;
        length -= (size_t)written;
    }
    return 1;
}

static int publish_artifact(
    const char *source,
    const char *destination,
    const char *label) {
    if (destination == NULL) {
        return 0;
    }

    char temporary[PATH_MAX];
    if (snprintf(
            temporary,
            sizeof(temporary),
            "%s.tmp.XXXXXX",
            destination) >= (int)sizeof(temporary)) {
        fprintf(stderr, "weavec: %s path is too long: %s\n", label, destination);
        return 1;
    }

    int input = open(source, O_RDONLY);
    if (input < 0) {
        fprintf(
            stderr,
            "weavec: cannot read %s source %s: %s\n",
            label,
            source,
            strerror(errno));
        return 1;
    }

    int output = mkstemp(temporary);
    if (output < 0) {
        fprintf(
            stderr,
            "weavec: cannot create %s beside %s: %s\n",
            label,
            destination,
            strerror(errno));
        close(input);
        return 1;
    }
    if (fchmod(output, 0644) != 0) {
        fprintf(
            stderr,
            "weavec: cannot set permissions on %s %s: %s\n",
            label,
            destination,
            strerror(errno));
        close(input);
        close(output);
        unlink(temporary);
        return 1;
    }

    unsigned char buffer[16384];
    int failed = 0;
    for (;;) {
        ssize_t length = read(input, buffer, sizeof(buffer));
        if (length == 0) {
            break;
        }
        if (length < 0) {
            if (errno == EINTR) {
                continue;
            }
            failed = 1;
            break;
        }
        if (!write_all(output, buffer, (size_t)length)) {
            failed = 1;
            break;
        }
    }

    if (close(input) != 0) {
        failed = 1;
    }
    if (!failed && fsync(output) != 0) {
        failed = 1;
    }
    if (close(output) != 0) {
        failed = 1;
    }

    if (failed) {
        fprintf(
            stderr,
            "weavec: cannot write %s %s: %s\n",
            label,
            destination,
            strerror(errno));
        unlink(temporary);
        return 1;
    }
    if (rename(temporary, destination) != 0) {
        fprintf(
            stderr,
            "weavec: cannot publish %s %s: %s\n",
            label,
            destination,
            strerror(errno));
        unlink(temporary);
        return 1;
    }
    return 0;
}

typedef struct weave_build_paths {
    char directory[PATH_MAX];
    char wir[PATH_MAX];
    char raw_llvm[PATH_MAX];
    char optimized_llvm[PATH_MAX];
    char assembly[PATH_MAX];
    char object[PATH_MAX];
    char ir_remarks[PATH_MAX];
    char codegen_remarks[PATH_MAX];
    char optimization_record[PATH_MAX];
    char trace_events[PATH_MAX];
    char disassembly[PATH_MAX];
} weave_build_paths;

static void cleanup_build_directory(const weave_build_paths *paths, int keep) {
    if (keep) {
        fprintf(
            stderr,
            "weavec: kept temporary build directory: %s\n",
            paths->directory);
        return;
    }
    unlink(paths->wir);
    unlink(paths->raw_llvm);
    unlink(paths->optimized_llvm);
    unlink(paths->assembly);
    unlink(paths->object);
    unlink(paths->ir_remarks);
    unlink(paths->codegen_remarks);
    unlink(paths->optimization_record);
    unlink(paths->trace_events);
    unlink(paths->disassembly);
    rmdir(paths->directory);
}

static int initialize_build_paths(
    weave_build_paths *paths,
    const char *tmp_root) {
    if (snprintf(
            paths->directory,
            sizeof(paths->directory),
            "%s/weavec-build-XXXXXX",
            tmp_root) >= (int)sizeof(paths->directory) ||
        mkdtemp(paths->directory) == NULL) {
        return 0;
    }
#define WEAVE_BUILD_PATH(field, name) \
    do { \
        if (snprintf( \
                paths->field, sizeof(paths->field), \
                "%s/%s", paths->directory, name) >= \
            (int)sizeof(paths->field)) { \
            cleanup_build_directory(paths, 0); \
            return 0; \
        } \
    } while (0)
    WEAVE_BUILD_PATH(wir, "program.wir");
    WEAVE_BUILD_PATH(raw_llvm, "program.ll");
    WEAVE_BUILD_PATH(optimized_llvm, "program.optimized.ll");
    WEAVE_BUILD_PATH(assembly, "program.s");
    WEAVE_BUILD_PATH(object, "program.o");
    WEAVE_BUILD_PATH(ir_remarks, "program.ir.opt.yaml");
    WEAVE_BUILD_PATH(codegen_remarks, "program.codegen.opt.yaml");
    WEAVE_BUILD_PATH(optimization_record, "program.opt.yaml");
    WEAVE_BUILD_PATH(trace_events, "program.trace.events");
    WEAVE_BUILD_PATH(disassembly, "program.disasm");
#undef WEAVE_BUILD_PATH
    return 1;
}

static int copy_stream(FILE *output, const char *path) {
    FILE *input = fopen(path, "rb");
    if (input == NULL) {
        if (errno == ENOENT) {
            return 1;
        }
        fprintf(stderr, "weavec: cannot read optimization record %s: %s\n", path, strerror(errno));
        return 0;
    }
    unsigned char buffer[16384];
    for (;;) {
        size_t count = fread(buffer, 1, sizeof(buffer), input);
        if (count > 0 && fwrite(buffer, 1, count, output) != count) {
            fclose(input);
            return 0;
        }
        if (count < sizeof(buffer)) {
            if (ferror(input)) {
                fclose(input);
                return 0;
            }
            break;
        }
    }
    return fclose(input) == 0;
}

static int combine_optimization_records(
    const char *ir_record,
    const char *codegen_record,
    const char *output_path) {
    FILE *output = fopen(output_path, "wb");
    if (output == NULL) {
        fprintf(
            stderr,
            "weavec: cannot create optimization record %s: %s\n",
            output_path,
            strerror(errno));
        return 1;
    }
    int ok = fputs("# weavec optimization stage: llvm-ir\n", output) >= 0 &&
        copy_stream(output, ir_record) &&
        fputs("\n# weavec optimization stage: target-codegen\n", output) >= 0 &&
        copy_stream(output, codegen_record);
    if (fclose(output) != 0) {
        ok = 0;
    }
    if (!ok) {
        fprintf(stderr, "weavec: cannot write optimization record %s\n", output_path);
        unlink(output_path);
        return 1;
    }
    return 0;
}

static int optimization_option(const char *arg) {
    return strcmp(arg, "-O0") == 0 || strcmp(arg, "-O1") == 0 ||
           strcmp(arg, "-O2") == 0 || strcmp(arg, "-O3") == 0 ||
           strcmp(arg, "-Os") == 0 || strcmp(arg, "-Oz") == 0;
}

static const char *optimization_name(const char *flag) {
    return flag != NULL && flag[0] == '-' ? flag + 1 : flag;
}

static void write_build_manifest(
    const char *path,
    const char *status,
    const char *phase,
    const char *target,
    const char *compiler,
    const char *runtime,
    const weave_llvm_config *llvm,
    const char *linker,
    const char *output,
    char **sources,
    int source_count) {
    write_manifest(
        path, status, phase, target, compiler, runtime,
        llvm->optimizer, llvm->codegen, linker, llvm->objdump,
        optimization_name(llvm->optimization), llvm->cpu, llvm->tune_cpu,
        output, sources, source_count);
}

int weave_rt_build_main(int argc, char **argv) {
    const char *output = NULL;
    const char *target = WEAVEC_DEFAULT_TARGET;
    const char *runtime_override = NULL;
    const char *optimizer = getenv("WEAVEC_OPTIMIZER");
    if (optimizer == NULL || *optimizer == '\0') {
        optimizer = getenv("WEAVEC_CODEGEN");
    }
    const char *codegen = getenv("WEAVEC_TARGET_CODEGEN");
    if (codegen == NULL || *codegen == '\0') {
        codegen = getenv("WEAVEC_LLC");
    }
    const char *linker = getenv("WEAVEC_LINKER");
    const char *objdump = getenv("WEAVEC_OBJDUMP");
    const char *manifest = NULL;
    const char *trace = NULL;
    const char *emit_wir = NULL;
    const char *emit_llvm = NULL;
    const char *emit_optimized_llvm = NULL;
    const char *emit_assembly = NULL;
    const char *emit_disassembly = NULL;
    const char *optimization_record = NULL;
    const char *optimization = "-O2";
    const char *cpu = NULL;
    const char *tune_cpu = NULL;
    int keep_temporaries = 0;
    int llvm_provenance = 0;

    if (optimizer == NULL || *optimizer == '\0') {
        optimizer = WEAVEC_DEFAULT_OPTIMIZER;
    }
    if (codegen == NULL || *codegen == '\0') {
        codegen = WEAVEC_DEFAULT_CODEGEN;
    }
    if (linker == NULL || *linker == '\0') {
        linker = WEAVEC_DEFAULT_LINKER;
    }
    if (objdump == NULL || *objdump == '\0') {
        objdump = WEAVEC_DEFAULT_OBJDUMP;
    }

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
        } else if (strcmp(arg, "--optimizer") == 0 ||
                   strcmp(arg, "--codegen") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            optimizer = argv[i];
        } else if (strcmp(arg, "--target-codegen") == 0 ||
                   strcmp(arg, "--llc") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            codegen = argv[i];
        } else if (strcmp(arg, "--linker") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            linker = argv[i];
        } else if (strcmp(arg, "--objdump") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            objdump = argv[i];
        } else if (strcmp(arg, "--manifest-json") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            manifest = argv[i];
        } else if (strcmp(arg, "--trace-json") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            trace = argv[i];
        } else if (strcmp(arg, "--emit-wir") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            emit_wir = argv[i];
        } else if (strcmp(arg, "--emit-llvm") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            emit_llvm = argv[i];
        } else if (strcmp(arg, "--emit-optimized-llvm") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            emit_optimized_llvm = argv[i];
        } else if (strcmp(arg, "--emit-assembly") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            emit_assembly = argv[i];
        } else if (strcmp(arg, "--emit-disassembly") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            emit_disassembly = argv[i];
        } else if (strcmp(arg, "--optimization-record") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            optimization_record = argv[i];
        } else if (strcmp(arg, "--cpu") == 0 || strcmp(arg, "--march") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            cpu = argv[i];
        } else if (strncmp(arg, "--march=", 8) == 0) {
            cpu = arg + 8;
        } else if (strcmp(arg, "--tune-cpu") == 0 || strcmp(arg, "--mtune") == 0) {
            if (++i >= argc) {
                build_usage();
                free(sources);
                return 2;
            }
            tune_cpu = argv[i];
        } else if (strncmp(arg, "--mtune=", 8) == 0) {
            tune_cpu = arg + 8;
        } else if (strcmp(arg, "--native") == 0) {
            cpu = "native";
            tune_cpu = "native";
        } else if (optimization_option(arg)) {
            optimization = arg;
        } else if (strcmp(arg, "--keep-temporaries") == 0) {
            keep_temporaries = 1;
        } else if (strcmp(arg, "--llvm-provenance") == 0) {
            llvm_provenance = 1;
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
    if ((cpu != NULL && *cpu == '\0') ||
        (tune_cpu != NULL && *tune_cpu == '\0')) {
        fputs("weavec: CPU names must not be empty\n", stderr);
        free(sources);
        return 2;
    }
    const char *requested_paths[] = {
        output,
        manifest,
        trace,
        emit_wir,
        emit_llvm,
        emit_optimized_llvm,
        emit_assembly,
        emit_disassembly,
        optimization_record,
    };
    if (requested_paths_conflict(
            requested_paths,
            sizeof(requested_paths) / sizeof(requested_paths[0]))) {
        fputs("weavec: all requested output paths must differ\n", stderr);
        free(sources);
        return 2;
    }
    if (llvm_provenance && emit_llvm == NULL) {
        keep_temporaries = 1;
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

    weave_llvm_config llvm = {
        .optimizer = optimizer,
        .codegen = codegen,
        .objdump = objdump,
        .optimization = optimization,
        .cpu = cpu,
        .tune_cpu = tune_cpu,
    };

    const char *tmp_root = getenv("TMPDIR");
    if (tmp_root == NULL || *tmp_root == '\0') {
        tmp_root = "/tmp";
    }
    weave_build_paths paths = {0};
    if (!initialize_build_paths(&paths, tmp_root)) {
        fprintf(stderr, "weavec: cannot create temporary directory: %s\n", strerror(errno));
        free(sources);
        return 1;
    }

    char **frontend = calloc((size_t)source_count + 4, sizeof(char *));
    if (frontend == NULL) {
        cleanup_build_directory(&paths, keep_temporaries);
        free(sources);
        return 1;
    }
    frontend[0] = compiler;
    frontend[1] = "--frontend";
    frontend[2] = paths.wir;
    for (int i = 0; i < source_count; ++i) {
        frontend[3 + i] = sources[i];
    }
    frontend[3 + source_count] = NULL;

    char *saved_trace_events = NULL;
    const char *existing_trace_events = getenv(WEAVEC_TRACE_EVENTS_ENV);
    if (existing_trace_events != NULL) {
        saved_trace_events = strdup(existing_trace_events);
    }
    if (trace != NULL) {
        unlink(paths.trace_events);
        (void)setenv(WEAVEC_TRACE_EVENTS_ENV, paths.trace_events, 1);
    }

    char *saved_source_map = NULL;
    const char *existing_source_map = getenv(WEAVEC_SOURCE_MAP_ENV);
    if (existing_source_map != NULL) {
        saved_source_map = strdup(existing_source_map);
    }
    if (llvm_provenance) {
        (void)setenv(WEAVEC_SOURCE_MAP_ENV, "1", 1);
    }

    int status = weave_run_process(frontend);
    if (llvm_provenance) {
        if (saved_source_map != NULL) {
            (void)setenv(WEAVEC_SOURCE_MAP_ENV, saved_source_map, 1);
        } else {
            (void)unsetenv(WEAVEC_SOURCE_MAP_ENV);
        }
    }
    free(saved_source_map);
    if (trace != NULL) {
        if (saved_trace_events != NULL) {
            (void)setenv(WEAVEC_TRACE_EVENTS_ENV, saved_trace_events, 1);
        } else {
            (void)unsetenv(WEAVEC_TRACE_EVENTS_ENV);
        }
    }
    free(saved_trace_events);
    free(frontend);

#define FAIL_BUILD(phase_name, result) \
    do { \
        write_build_manifest( \
            manifest, "failed", phase_name, target, compiler, runtime, \
            &llvm, linker, output, sources, source_count); \
        (void)weave_trace_write_document( \
            trace, "failed", phase_name, sources, source_count, \
            paths.trace_events); \
        unlink(paths.trace_events); \
        cleanup_build_directory(&paths, keep_temporaries); \
        free(sources); \
        return result; \
    } while (0)

    if (status != 0) {
        FAIL_BUILD("frontend", status);
    }
    if (publish_artifact(paths.wir, emit_wir, "WIR artifact") != 0) {
        FAIL_BUILD("publish", 1);
    }

    char *saved_llvm_provenance = NULL;
    const char *existing_llvm_provenance = getenv(WEAVEC_LLVM_PROVENANCE_ENV);
    if (existing_llvm_provenance != NULL) {
        saved_llvm_provenance = strdup(existing_llvm_provenance);
    }
    if (llvm_provenance) {
        (void)setenv(WEAVEC_LLVM_PROVENANCE_ENV, "1", 1);
    }
    char *backend[] = {
        compiler,
        "--backend",
        paths.wir,
        paths.raw_llvm,
        NULL,
    };
    status = weave_run_process(backend);
    if (llvm_provenance) {
        if (saved_llvm_provenance != NULL) {
            (void)setenv(
                WEAVEC_LLVM_PROVENANCE_ENV,
                saved_llvm_provenance,
                1);
        } else {
            (void)unsetenv(WEAVEC_LLVM_PROVENANCE_ENV);
        }
    }
    free(saved_llvm_provenance);
    if (status != 0) {
        FAIL_BUILD("backend", status);
    }
    if (internalize_build_module(paths.raw_llvm) != 0) {
        FAIL_BUILD("backend", 1);
    }
    if (publish_artifact(paths.raw_llvm, emit_llvm, "raw LLVM artifact") != 0) {
        FAIL_BUILD("publish", 1);
    }

    status = weave_llvm_optimize_ir(
        &llvm,
        paths.raw_llvm,
        paths.optimized_llvm,
        optimization_record != NULL ? paths.ir_remarks : NULL);
    if (status != 0) {
        FAIL_BUILD("optimize", status);
    }
    if (publish_artifact(
            paths.optimized_llvm,
            emit_optimized_llvm,
            "optimized LLVM artifact") != 0) {
        FAIL_BUILD("publish", 1);
    }

    if (emit_assembly != NULL) {
        status = weave_llvm_emit_assembly(
            &llvm,
            paths.optimized_llvm,
            paths.assembly);
        if (status != 0) {
            FAIL_BUILD("assembly", status);
        }
        if (publish_artifact(
                paths.assembly,
                emit_assembly,
                "assembly artifact") != 0) {
            FAIL_BUILD("publish", 1);
        }
    }

    status = weave_llvm_emit_object(
        &llvm,
        paths.optimized_llvm,
        paths.object,
        optimization_record != NULL ? paths.codegen_remarks : NULL);
    if (status != 0) {
        FAIL_BUILD("codegen", status);
    }
    if (optimization_record != NULL) {
        if (combine_optimization_records(
                paths.ir_remarks,
                paths.codegen_remarks,
                paths.optimization_record) != 0) {
            FAIL_BUILD("optimization-record", 1);
        }
        if (publish_artifact(
                paths.optimization_record,
                optimization_record,
                "optimization record") != 0) {
            FAIL_BUILD("publish", 1);
        }
    }

    char output_template[PATH_MAX];
    if (snprintf(
            output_template,
            sizeof(output_template),
            "%s.tmp.XXXXXX",
            output) >= (int)sizeof(output_template)) {
        fputs("weavec: output path is too long\n", stderr);
        FAIL_BUILD("publish", 1);
    }
    int output_fd = mkstemp(output_template);
    if (output_fd < 0) {
        fprintf(
            stderr,
            "weavec: cannot create output beside %s: %s\n",
            output,
            strerror(errno));
        FAIL_BUILD("publish", 1);
    }
    close(output_fd);
    unlink(output_template);

    char *link_args[] = {
        (char *)linker,
        "-ffunction-sections",
        "-fdata-sections",
        paths.object,
        runtime,
        WEAVEC_LINK_DEAD_STRIP,
        "-o",
        output_template,
        NULL,
    };
    status = weave_run_process(link_args);
    if (status != 0) {
        unlink(output_template);
        FAIL_BUILD("link", status);
    }

    if (emit_disassembly != NULL) {
        status = weave_llvm_disassemble(
            &llvm,
            output_template,
            paths.disassembly);
        if (status != 0) {
            unlink(output_template);
            FAIL_BUILD("disassemble", status);
        }
        if (publish_artifact(
                paths.disassembly,
                emit_disassembly,
                "disassembly artifact") != 0) {
            unlink(output_template);
            FAIL_BUILD("publish", 1);
        }
    }

    status = weave_trace_write_document(
        trace,
        "succeeded",
        "complete",
        sources,
        source_count,
        paths.trace_events);
    if (status != 0) {
        unlink(output_template);
        FAIL_BUILD("trace", status);
    }

    if (rename(output_template, output) != 0) {
        fprintf(
            stderr,
            "weavec: cannot publish output %s: %s\n",
            output,
            strerror(errno));
        unlink(output_template);
        FAIL_BUILD("publish", 1);
    }

    write_build_manifest(
        manifest,
        "succeeded",
        "complete",
        target,
        compiler,
        runtime,
        &llvm,
        linker,
        output,
        sources,
        source_count);
    unlink(paths.trace_events);
    cleanup_build_directory(&paths, keep_temporaries);
    free(sources);
#undef FAIL_BUILD
    return status;
}
