// SPDX-License-Identifier: Apache-2.0
//
// Native entry point for Weave-owned compiler capabilities. Schema, registry,
// field ordering, and compatibility policy live in src/protocol/*.weave.

#ifndef WEAVEC_CAPABILITIES_JSON_C
#define WEAVEC_CAPABILITIES_JSON_C

#include "json_writer_bridge.c"

extern int weave_protocol_capabilities_serialize(void *writer);

int weave_rt_print_capabilities(void) {
    weave_json_writer writer;
    weave_json_writer_init(&writer, stdout);
    if (weave_protocol_capabilities_serialize(&writer) != 0 ||
        !weave_json_writer_finish(&writer) ||
        fflush(stdout) != 0) {
        return 1;
    }
    return 0;
}

#endif
