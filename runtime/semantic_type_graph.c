// SPDX-License-Identifier: Apache-2.0
//
// Minimal host slot for self-hosted semantic compiler state.
//
// Surface Weave does not yet have process-wide mutable globals, so the compiler
// needs one native cell in which to retain its heap-owned semantic state between
// frontend calls. The host never interprets the pointer or any type data.

#ifndef WEAVEC_SEMANTIC_TYPE_GRAPH_C
#define WEAVEC_SEMANTIC_TYPE_GRAPH_C

static void *weave_host_semantic_state = NULL;

void *weave_host_semantic_state_get(void) {
    return weave_host_semantic_state;
}

void weave_host_semantic_state_set(void *state) {
    weave_host_semantic_state = state;
}

#endif
