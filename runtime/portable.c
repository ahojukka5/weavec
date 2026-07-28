// SPDX-License-Identifier: Apache-2.0
//
// Host support linked into the compiler executable. Program runtime code lives
// separately in program.c and is shipped as a private target resource.

#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// Normal builds provide a strong definition from a generated LLVM module linked
// into compiler bitcode. The weak fallback keeps direct host-runtime links valid.
__attribute__((weak)) const char weave_compiler_version[] = "v0.0.0+unknown";

#ifndef WEAVEC_DEFAULT_TARGET
#if defined(__linux__) && defined(__x86_64__)
#define WEAVEC_DEFAULT_TARGET "x86_64-unknown-linux-gnu"
#elif defined(__APPLE__) && defined(__aarch64__)
#define WEAVEC_DEFAULT_TARGET "aarch64-apple-darwin"
#elif defined(__APPLE__) && defined(__x86_64__)
#define WEAVEC_DEFAULT_TARGET "x86_64-apple-darwin"
#else
#define WEAVEC_DEFAULT_TARGET "unknown-host"
#endif
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

int weave_rt_open_write_trunc(const char *path, int mode) {
    return open(path, O_WRONLY | O_CREAT | O_TRUNC, mode);
}

int weave_rt_print_version(void) {
    static const char prefix[] = "weavec ";
    static const char newline[] = "\n";
    const unsigned long prefix_length = sizeof(prefix) - 1;
    const unsigned long version_length =
        (unsigned long)__builtin_strlen(weave_compiler_version);

    if (write(1, prefix, prefix_length) != (ssize_t)prefix_length ||
        write(1, weave_compiler_version, version_length) !=
            (ssize_t)version_length ||
        write(1, newline, 1) != 1) {
        return 1;
    }
    return 0;
}

// The compiler itself may contain lowered contract checks, so it retains this
// definition. Programs receive the same symbol from the private runtime archive.
void weave_rt_contract_fail(const char *msg) {
    const char nl = '\n';
    (void)write(2, msg, (unsigned long)__builtin_strlen(msg));
    (void)write(2, &nl, 1);
    _exit(1);
}

static int weave_frontend_strict_contracts = 0;

void weave_frontend_set_strict_contracts(int enabled) {
    weave_frontend_strict_contracts = enabled ? 1 : 0;
}

int weave_frontend_strict_contracts_enabled(void) {
    return weave_frontend_strict_contracts;
}

static void *weave_audit_json_effect_table = 0;

void weave_audit_json_set_table(void *table) {
    weave_audit_json_effect_table = table;
}

void *weave_audit_json_get_table(void) {
    return weave_audit_json_effect_table;
}

// Some Apple SDK modes do not declare mkdtemp even when the rest of the POSIX
// process API is visible. Build it from the universally available mkstemp,
// unlink, and mkdir primitives so the driver has one portable implementation.
static char *weave_rt_mkdtemp(char *path_template) {
    int fd = mkstemp(path_template);
    if (fd < 0) {
        return NULL;
    }
    if (close(fd) != 0) {
        int saved = errno;
        (void)unlink(path_template);
        errno = saved;
        return NULL;
    }
    if (unlink(path_template) != 0 || mkdir(path_template, 0700) != 0) {
        return NULL;
    }
    return path_template;
}

#define mkdtemp weave_rt_mkdtemp

#ifndef WEAVEC_TRACE_EVENTS_ENV
#define WEAVEC_TRACE_EVENTS_ENV "WEAVEC_INTERNAL_TRACE_EVENTS"
#endif

#ifndef WEAVEC_SOURCE_MAP_ENV
#define WEAVEC_SOURCE_MAP_ENV "WEAVEC_INTERNAL_SOURCE_LOCATIONS"
#endif
#ifndef WEAVEC_LLVM_PROVENANCE_ENV
#define WEAVEC_LLVM_PROVENANCE_ENV "WEAVEC_INTERNAL_LLVM_PROVENANCE"
#endif


static int weave_trace_write_document(
    const char *path,
    const char *status,
    const char *phase,
    char **sources,
    int source_count,
    const char *events_path);
// Keep the self-hosted compiler link command simple. The original build driver
// remains the implementation core, while diagnostics_driver.c provides the
// versioned public diagnostics facade without duplicating the phase pipeline.
#include "llvm_toolchain.c"
#define weave_rt_build_main weave_rt_build_main_legacy
#include "build_driver.c"
#undef weave_rt_build_main
#define weave_rt_build_main weave_rt_build_main_diagnostics_legacy
#include "diagnostics_driver.c"
#undef weave_rt_build_main
#define weave_rt_build_main weave_rt_build_main_source_locations_legacy
#include "source_locations.c"
#undef weave_rt_build_main
#include "trace_runtime.c"
#include "path_safety.c"
