// SPDX-License-Identifier: Apache-2.0
//
// Tiny portability shim for POSIX flag constants that differ across
// platforms. weavec's WIR source previously baked open() flag values
// in as integer literals — but those values are platform-specific
// (e.g. O_WRONLY|O_CREAT|O_TRUNC = 1537 on macOS, 577 on Linux). The
// WIR layer doesn't know about <fcntl.h>, so we wrap the call here in
// C using the OS-native constants.

#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// Open a file for writing, truncating if it exists, creating if it
// doesn't. Returns the file descriptor, or -1 on failure. The mode
// parameter is a POSIX mode_t value (e.g. 0644).
int weave_rt_open_write_trunc(const char *path, int mode) {
    return open(path, O_WRONLY | O_CREAT | O_TRUNC, mode);
}

// Print a contract violation message to stderr and terminate the process.
// Used by surface (requires ...) / (ensures ...) lowering.
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
