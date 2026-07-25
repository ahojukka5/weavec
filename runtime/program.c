// SPDX-License-Identifier: Apache-2.0
//
// Runtime support linked into programs produced by `weavec build`.
// This is a private compiler resource, not a user-managed library API.

#include <unistd.h>

void weave_rt_contract_fail(const char *msg) {
    const char nl = '\n';
    const char *p = msg;
    unsigned long len = 0;

    if (p != 0) {
        while (p[len] != '\0') {
            ++len;
        }
        (void)write(2, p, len);
    }
    (void)write(2, &nl, 1);
    _exit(1);
}
