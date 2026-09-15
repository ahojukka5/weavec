// SPDX-License-Identifier: Apache-2.0
//
// Runtime support linked into programs produced by `weavec build`.
// This is a private compiler resource, not a user-managed library API.

#include <stdint.h>
#include <unistd.h>

#include "process_args.inc"
#include "tree_walk_depth.h"

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

/* Parser.weave calls this. Produced programs always use the public budget. */
int64_t weave_rt_tree_walk_budget(void) {
    return WEAVEC_TREE_WALK_MAX_DEPTH;
}

int32_t weave_rt_write(int32_t fd, const void *data, int64_t n) {
    if (n <= 0 || data == 0) {
        return 0;
    }
    return write((int)fd, data, (size_t)n) < 0 ? 1 : 0;
}

int32_t weave_rt_write_u8(int32_t fd, int32_t b) {
    unsigned char byte = (unsigned char)b;
    return weave_rt_write(fd, &byte, 1);
}

int32_t weave_rt_write_finish(int32_t fd) {
    (void)fd;
    return 0;
}

int32_t weave_rt_write_failed(void) {
    return 0;
}
