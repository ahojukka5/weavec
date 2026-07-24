// SPDX-License-Identifier: Apache-2.0
// Private support functions used by the weavec compiler itself.

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

int weave_rt_open_write_trunc(const char *path, int mode) {
    return open(path, O_WRONLY | O_CREAT | O_TRUNC, (mode_t)mode);
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
