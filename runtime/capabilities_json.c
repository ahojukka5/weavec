// SPDX-License-Identifier: Apache-2.0
//
// Compiler-owned typed serializer for weavec-capabilities-v1.

#ifndef WEAVEC_CAPABILITIES_JSON_C
#define WEAVEC_CAPABILITIES_JSON_C

#define WEAVE_CAP_ARRAY_LEN(values) (sizeof(values) / sizeof((values)[0]))

#include "capabilities_json_types.inc"
#include "capabilities_json_registry.inc"
#include "capabilities_json_emit.inc"
#include "capabilities_json_document.inc"

#undef WEAVE_CAP_ARRAY_LEN
#endif
