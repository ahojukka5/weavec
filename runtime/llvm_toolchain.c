// SPDX-License-Identifier: Apache-2.0
//
// LLVM toolchain adapter used by the public build driver.
//
// The current implementation invokes command-line tools in subprocesses. Keep
// the build driver dependent on these semantic operations rather than concrete
// tool arguments so a future in-process LLVM integration can replace this file
// without changing the public build or artifact contracts.

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef WEAVEC_DEFAULT_OBJDUMP
#define WEAVEC_DEFAULT_OBJDUMP "llvm-objdump"
#endif

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

typedef struct weave_llvm_config {
    const char *optimizer;
    const char *codegen;
    const char *objdump;
    const char *optimization;
    const char *cpu;
    const char *tune_cpu;
} weave_llvm_config;

static int weave_run_process(char *const args[]) {
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

static int weave_run_process_filter(
    char *const args[],
    const char *input_path,
    const char *output_path) {
    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "weavec: fork failed: %s\n", strerror(errno));
        return 1;
    }
    if (pid == 0) {
        int input = open(input_path, O_RDONLY);
        if (input < 0) {
            fprintf(
                stderr,
                "weavec: cannot read %s: %s\n",
                input_path,
                strerror(errno));
            _exit(127);
        }
        int output = open(output_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (output < 0) {
            fprintf(
                stderr,
                "weavec: cannot create %s: %s\n",
                output_path,
                strerror(errno));
            close(input);
            _exit(127);
        }
        if (dup2(input, STDIN_FILENO) < 0 ||
            dup2(output, STDOUT_FILENO) < 0) {
            fprintf(
                stderr,
                "weavec: cannot redirect toolchain input/output: %s\n",
                strerror(errno));
            close(input);
            close(output);
            _exit(127);
        }
        close(input);
        close(output);
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

static int weave_clang_cpu_flag(
    const char *cpu,
    char *buffer,
    size_t buffer_size) {
    if (cpu == NULL || *cpu == '\0') {
        return 1;
    }
#if defined(__aarch64__) || defined(__arm64__)
    int written = snprintf(buffer, buffer_size, "-mcpu=%s", cpu);
#else
    int written = snprintf(buffer, buffer_size, "-march=%s", cpu);
#endif
    return written >= 0 && (size_t)written < buffer_size;
}

static int weave_llvm_mcpu_flag(
    const char *cpu,
    char *buffer,
    size_t buffer_size) {
    if (cpu == NULL || *cpu == '\0') {
        return 1;
    }
    int written = snprintf(buffer, buffer_size, "-mcpu=%s", cpu);
    return written >= 0 && (size_t)written < buffer_size;
}

static int weave_llvm_tune_flag(
    const char *cpu,
    char *buffer,
    size_t buffer_size) {
    if (cpu == NULL || *cpu == '\0') {
        return 1;
    }
    int written = snprintf(buffer, buffer_size, "-mtune=%s", cpu);
    return written >= 0 && (size_t)written < buffer_size;
}

static size_t weave_clang_optimization_args(
    const weave_llvm_config *config,
    char **args,
    size_t index,
    char *cpu_flag,
    size_t cpu_flag_size,
    char *tune_flag,
    size_t tune_flag_size) {
    args[index++] = (char *)config->optimizer;
    args[index++] = "-Wno-override-module";
    args[index++] = (char *)config->optimization;
    if (config->cpu != NULL && *config->cpu != '\0') {
        if (!weave_clang_cpu_flag(config->cpu, cpu_flag, cpu_flag_size)) {
            return 0;
        }
        args[index++] = cpu_flag;
    }
    if (config->tune_cpu != NULL && *config->tune_cpu != '\0') {
        if (!weave_llvm_tune_flag(config->tune_cpu, tune_flag, tune_flag_size)) {
            return 0;
        }
        args[index++] = tune_flag;
    }
    return index;
}

static const char *weave_llc_optimization(const char *optimization) {
    if (strcmp(optimization, "-O0") == 0) return "-O=0";
    if (strcmp(optimization, "-O1") == 0) return "-O=1";
    if (strcmp(optimization, "-O3") == 0) return "-O=3";
    return "-O=2";
}

static size_t weave_llc_codegen_args(
    const weave_llvm_config *config,
    char **args,
    size_t index,
    char *cpu_flag,
    size_t cpu_flag_size) {
    args[index++] = (char *)config->codegen;
    args[index++] = (char *)weave_llc_optimization(config->optimization);
    args[index++] = "-relocation-model=pic";
    if (config->cpu != NULL && *config->cpu != '\0') {
        if (!weave_llvm_mcpu_flag(config->cpu, cpu_flag, cpu_flag_size)) {
            return 0;
        }
        args[index++] = cpu_flag;
    }
    return index;
}

static int weave_llvm_tool_major(const char *tool) {
    int fds[2];
    if (tool == NULL || *tool == '\0' || pipe(fds) != 0) {
        return -1;
    }
    pid_t pid = fork();
    if (pid < 0) {
        close(fds[0]);
        close(fds[1]);
        return -1;
    }
    if (pid == 0) {
        close(fds[0]);
        if (dup2(fds[1], STDOUT_FILENO) < 0) {
            _exit(127);
        }
        close(fds[1]);
        char *args[] = {(char *)tool, "--version", NULL};
        execvp(args[0], args);
        _exit(127);
    }
    close(fds[1]);
    char text[2048];
    size_t used = 0;
    for (;;) {
        ssize_t got = read(fds[0], text + used, sizeof(text) - 1 - used);
        if (got < 0 && errno == EINTR) {
            continue;
        }
        if (got <= 0) {
            break;
        }
        used += (size_t)got;
        if (used >= sizeof(text) - 1) {
            break;
        }
    }
    text[used] = '\0';
    close(fds[0]);
    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) {
            return -1;
        }
    }
    const char *cursor = text;
    while ((cursor = strstr(cursor, "version ")) != NULL) {
        cursor += 8;
        if (*cursor >= '0' && *cursor <= '9') {
            return atoi(cursor);
        }
    }
    return -1;
}

static int weave_llvm_check_toolchain(const weave_llvm_config *config) {
    int optimizer_major = weave_llvm_tool_major(config->optimizer);
    int codegen_major = weave_llvm_tool_major(config->codegen);
    if (optimizer_major < 0 || codegen_major < 0) {
        return 0;
    }
    if (optimizer_major <= codegen_major) {
        return 0;
    }
    fprintf(stderr, "weavec: error: LLVM toolchain skew\n");
    fprintf(
        stderr,
        "  %s is version %d but %s is version %d.\n",
        config->optimizer,
        optimizer_major,
        config->codegen,
        codegen_major);
    fputs(
        "  weavec produces IR with the optimizer and generates code\n",
        stderr);
    fputs(
        "  with the code generator, so the newer compiler emits IR\n",
        stderr);
    fputs(
        "  the older code generator cannot parse. Install a code\n",
        stderr);
    fputs(
        "  generator at least as new as the optimizer, or pass\n",
        stderr);
    fputs(
        "  --target-codegen. See docs/development-builds.md.\n",
        stderr);
    return 1;
}

static int weave_llvm_optimize_ir(
    const weave_llvm_config *config,
    const char *input,
    const char *output,
    const char *remarks) {
    char cpu_flag[PATH_MAX];
    char tune_flag[PATH_MAX];
    char remarks_flag[PATH_MAX];
    char *args[20];
    size_t count = weave_clang_optimization_args(
        config, args, 0,
        cpu_flag, sizeof(cpu_flag), tune_flag, sizeof(tune_flag));
    if (count == 0) {
        fputs("weavec: LLVM target option is too long\n", stderr);
        return 1;
    }
    args[count++] = "-x";
    args[count++] = "ir";
    args[count++] = "-S";
    args[count++] = "-emit-llvm";
    if (remarks != NULL) {
        int written = snprintf(
            remarks_flag, sizeof(remarks_flag),
            "-foptimization-record-file=%s", remarks);
        if (written < 0 || (size_t)written >= sizeof(remarks_flag)) {
            fputs("weavec: optimization record path is too long\n", stderr);
            return 1;
        }
        args[count++] = "-fsave-optimization-record";
        args[count++] = remarks_flag;
    }
    args[count++] = "-";
    args[count++] = "-o";
    args[count++] = (char *)output;
    args[count] = NULL;
    return weave_run_process_filter(args, input, "/dev/null");
}

static int weave_llvm_emit_assembly(
    const weave_llvm_config *config,
    const char *input,
    const char *output) {
    char cpu_flag[PATH_MAX];
    char *args[16];
    size_t count = weave_llc_codegen_args(
        config, args, 0, cpu_flag, sizeof(cpu_flag));
    if (count == 0) {
        fputs("weavec: LLVM target option is too long\n", stderr);
        return 1;
    }
    args[count++] = "-filetype=asm";
    args[count++] = "-o";
    args[count++] = (char *)output;
    args[count++] = "-";
    args[count] = NULL;
    return weave_run_process_filter(args, input, "/dev/null");
}

static int weave_llvm_emit_object(
    const weave_llvm_config *config,
    const char *input,
    const char *output,
    const char *remarks) {
    char cpu_flag[PATH_MAX];
    char remarks_flag[PATH_MAX];
    char *args[20];
    size_t count = weave_llc_codegen_args(
        config, args, 0, cpu_flag, sizeof(cpu_flag));
    if (count == 0) {
        fputs("weavec: LLVM target option is too long\n", stderr);
        return 1;
    }
    args[count++] = "-filetype=obj";
    if (remarks != NULL) {
        int written = snprintf(
            remarks_flag, sizeof(remarks_flag),
            "-pass-remarks-output=%s", remarks);
        if (written < 0 || (size_t)written >= sizeof(remarks_flag)) {
            fputs("weavec: optimization record path is too long\n", stderr);
            return 1;
        }
        args[count++] = "-pass-remarks=.*";
        args[count++] = "-pass-remarks-missed=.*";
        args[count++] = "-pass-remarks-analysis=.*";
        args[count++] = remarks_flag;
    }
    args[count++] = "-o";
    args[count++] = (char *)output;
    args[count++] = "-";
    args[count] = NULL;
    return weave_run_process_filter(args, input, "/dev/null");
}

static int weave_llvm_disassemble(
    const weave_llvm_config *config,
    const char *input,
    const char *output) {
    char *args[] = {
        (char *)config->objdump,
        "--disassemble",
        "--demangle",
        "-",
        NULL,
    };
    return weave_run_process_filter(args, input, output);
}
