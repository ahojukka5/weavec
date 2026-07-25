// SPDX-License-Identifier: Apache-2.0
//
// Host support linked into the compiler executable. Program runtime code lives
// separately in program.c and is shipped as a private target resource.

#define _POSIX_C_SOURCE 200809L

#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

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

#ifndef WEAVEC_DEFAULT_LINKER
#define WEAVEC_DEFAULT_LINKER "clang"
#endif

int weave_rt_open_write_trunc(const char *path, int mode) {
    return open(path, O_WRONLY | O_CREAT | O_TRUNC, mode);
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

// Keep the self-hosted compiler link command simple: the build driver is a
// separate implementation module but shares this host-support translation unit.
#include "build_driver.c"
