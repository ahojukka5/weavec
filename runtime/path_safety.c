// SPDX-License-Identifier: Apache-2.0
//
// Final public build boundary that prevents requested outputs from aliasing
// source inputs before any compiler phase or protocol writer opens a path.

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

static int weave_path_safety_option_takes_value(const char *arg) {
    return strcmp(arg, "-o") == 0 || strcmp(arg, "--output") == 0 ||
           strcmp(arg, "--target") == 0 || strcmp(arg, "--runtime") == 0 ||
           strcmp(arg, "--optimizer") == 0 ||
           strcmp(arg, "--codegen") == 0 ||
           strcmp(arg, "--target-codegen") == 0 ||
           strcmp(arg, "--llc") == 0 || strcmp(arg, "--linker") == 0 ||
           strcmp(arg, "--objdump") == 0 ||
           strcmp(arg, "--manifest-json") == 0 ||
           strcmp(arg, "--diagnostics-json") == 0 ||
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

static int weave_path_safety_is_output_option(const char *arg) {
    return strcmp(arg, "-o") == 0 || strcmp(arg, "--output") == 0 ||
           strcmp(arg, "--manifest-json") == 0 ||
           strcmp(arg, "--diagnostics-json") == 0 ||
           strcmp(arg, "--trace-json") == 0 ||
           strcmp(arg, "--emit-wir") == 0 ||
           strcmp(arg, "--emit-llvm") == 0 ||
           strcmp(arg, "--emit-optimized-llvm") == 0 ||
           strcmp(arg, "--emit-assembly") == 0 ||
           strcmp(arg, "--emit-disassembly") == 0 ||
           strcmp(arg, "--optimization-record") == 0;
}

static int weave_path_safety_canonicalize(
    const char *path,
    char *out,
    size_t out_size) {
    if (path == NULL || *path == '\0') {
        return 0;
    }
    if (realpath(path, out) != NULL) {
        return 1;
    }

    char copy[PATH_MAX];
    if (snprintf(copy, sizeof(copy), "%s", path) >= (int)sizeof(copy)) {
        return 0;
    }
    char *slash = strrchr(copy, '/');
    const char *base = copy;
    const char *parent = ".";
    if (slash != NULL) {
        *slash = '\0';
        base = slash + 1;
        parent = copy[0] == '\0' ? "/" : copy;
    }
    if (*base == '\0') {
        return 0;
    }

    char resolved_parent[PATH_MAX];
    if (realpath(parent, resolved_parent) == NULL) {
        return 0;
    }
    int written = snprintf(
        out,
        out_size,
        "%s%s%s",
        resolved_parent,
        strcmp(resolved_parent, "/") == 0 ? "" : "/",
        base);
    return written >= 0 && (size_t)written < out_size;
}

static int weave_path_safety_aliases(const char *left, const char *right) {
    if (left == NULL || right == NULL) {
        return 0;
    }
    if (strcmp(left, right) == 0) {
        return 1;
    }

    struct stat left_stat;
    struct stat right_stat;
    if (stat(left, &left_stat) == 0 && stat(right, &right_stat) == 0 &&
        left_stat.st_dev == right_stat.st_dev &&
        left_stat.st_ino == right_stat.st_ino) {
        return 1;
    }

    char left_path[PATH_MAX];
    char right_path[PATH_MAX];
    return weave_path_safety_canonicalize(left, left_path, sizeof(left_path)) &&
           weave_path_safety_canonicalize(right, right_path, sizeof(right_path)) &&
           strcmp(left_path, right_path) == 0;
}

static int weave_path_safety_aliases_any_source(
    const char *path,
    const char *const sources[],
    int source_count) {
    for (int i = 0; i < source_count; ++i) {
        if (weave_path_safety_aliases(path, sources[i])) {
            return 1;
        }
    }
    return 0;
}

int weave_rt_build_main(int argc, char **argv) {
    if (argc < 2 || strcmp(argv[1], "build") != 0) {
        return weave_rt_build_main_source_locations_legacy(argc, argv);
    }

    const char **sources = calloc((size_t)argc, sizeof(*sources));
    const char **outputs = calloc((size_t)argc, sizeof(*outputs));
    if (sources == NULL || outputs == NULL) {
        free(sources);
        free(outputs);
        fputs("weavec: out of memory while validating build paths\n", stderr);
        return 1;
    }

    int source_count = 0;
    int output_count = 0;
    const char *diagnostics_path = NULL;
    const char *trace_path = NULL;
    for (int i = 2; i < argc; ++i) {
        const char *arg = argv[i];
        if (weave_path_safety_option_takes_value(arg)) {
            if (i + 1 >= argc) {
                free(sources);
                free(outputs);
                return weave_rt_build_main_source_locations_legacy(argc, argv);
            }
            const char *value = argv[++i];
            if (weave_path_safety_is_output_option(arg)) {
                outputs[output_count++] = value;
            }
            if (strcmp(arg, "--diagnostics-json") == 0) {
                diagnostics_path = value;
            } else if (strcmp(arg, "--trace-json") == 0) {
                trace_path = value;
            }
            continue;
        }
        if (arg[0] != '-') {
            sources[source_count++] = arg;
        }
    }

    const char *conflicting_output = NULL;
    for (int i = 0; i < output_count && conflicting_output == NULL; ++i) {
        if (weave_path_safety_aliases_any_source(
                outputs[i], sources, source_count)) {
            conflicting_output = outputs[i];
        }
    }
    if (conflicting_output == NULL) {
        free(sources);
        free(outputs);
        return weave_rt_build_main_source_locations_legacy(argc, argv);
    }

    fprintf(
        stderr,
        "weavec: output path aliases source input: %s\n",
        conflicting_output);

    weave_diag_record record = {
        .code = "driver.output-aliases-source",
        .severity = "error",
        .phase = "driver",
        .message = "an output path aliases a source input",
        .source = conflicting_output,
        .span_origin = "none",
    };
    if (diagnostics_path != NULL &&
        !weave_path_safety_aliases_any_source(
            diagnostics_path, sources, source_count)) {
        weave_diag_write_result(
            diagnostics_path, "failed", "driver", 2, 2, &record);
    }
    if (trace_path != NULL &&
        !weave_path_safety_aliases_any_source(
            trace_path, sources, source_count)) {
        (void)weave_trace_write_document(
            trace_path,
            "failed",
            "driver",
            (char **)sources,
            source_count,
            NULL);
    }

    free(sources);
    free(outputs);
    return 2;
}
