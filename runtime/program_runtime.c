// SPDX-License-Identifier: Apache-2.0
// Private runtime linked into native programs produced by `weavec build`.

#include <unistd.h>

void weave_rt_contract_fail(const char *message) {
    const char newline = '\n';
    if (message != 0) {
        (void)write(STDERR_FILENO, message, __builtin_strlen(message));
    }
    (void)write(STDERR_FILENO, &newline, 1);
    _exit(1);
}
