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

#define weave_surface_symbols_reset weave_surface_symbols_reset_storage
#define weave_surface_symbol_begin weave_surface_symbol_begin_storage
#define weave_surface_struct_type_or_declare \
    weave_surface_struct_type_or_declare_storage
#define weave_surface_struct_define weave_surface_struct_define_storage
#define weave_surface_struct_name weave_surface_struct_name_storage
#define weave_surface_module_export_status \
    weave_surface_module_export_status_storage
#define weave_surface_module_import_status \
    weave_surface_module_import_status_storage
#include "surface_symbols.c"
#undef weave_surface_module_import_status
#undef weave_surface_module_export_status
#undef weave_surface_struct_name
#undef weave_surface_struct_define
#undef weave_surface_struct_type_or_declare
#undef weave_surface_symbol_begin
#undef weave_surface_symbols_reset
#define weave_surface_symbols_reset weave_surface_symbols_reset_symbol_names
#include "module_wir_names.c"
#undef weave_surface_symbols_reset
#include "module_struct_names.c"
#include "json_writer.c"
#include "document_publish.c"
#include "semantic_index.c"
#include "capabilities_json.c"
#include "build_manifest_json.c"
#include "semantic_diagnostic_transport.c"

// formatter_driver.c calls into the self-hosted parser (node_kind, node_ident,
// ...), which is only linked alongside weavec.bc when building the compiler
// itself. This file also serves as the private target-program runtime, so
// formatter_driver.c is compiled as its own translation unit and linked only
// into the weavec executable, never into a compiled program's runtime.

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
#define weave_rt_build_main weave_rt_build_main_diagnostics_core
#include "diagnostics_driver.c"
#undef weave_rt_build_main
#include "semantic_diagnostic_wrapper.c"
#define weave_rt_build_main weave_rt_build_main_source_locations_legacy
#include "source_locations.c"
#undef weave_rt_build_main
#include "trace_runtime.c"
#include "semantic_diagnostic_record.c"
#define weave_rt_build_main weave_rt_build_main_path_safety_legacy
#include "path_safety.c"
#undef weave_rt_build_main

static int weave_project_ascii_alpha(int value) {
    unsigned char ch = (unsigned char)value;
    return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
}

static int weave_project_ascii_alnum(int value) {
    unsigned char ch = (unsigned char)value;
    return weave_project_ascii_alpha(ch) || (ch >= '0' && ch <= '9');
}

#define isalpha weave_project_ascii_alpha
#define isalnum weave_project_ascii_alnum
#define weave_rt_build_main weave_rt_build_main_project_legacy
#include "project_driver.c"
#undef weave_rt_build_main
#undef isalnum
#undef isalpha
#define weave_rt_build_main weave_rt_build_main_source_discovery_legacy
#include "project_sources.c"
#undef weave_rt_build_main
#define weave_rt_build_main weave_rt_build_main_project_graph_legacy
#include "project_graph.c"
#undef weave_rt_build_main
#define weave_rt_build_main_project_legacy \
    weave_rt_build_main_project_graph_legacy
#include "project_safety.c"
#undef weave_rt_build_main_project_legacy