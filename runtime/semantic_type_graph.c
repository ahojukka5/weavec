// SPDX-License-Identifier: Apache-2.0
//
// Compiler-owned structured semantic type graph. References are process-local
// handles; canonical identity strings are the stable semantic identities used by
// equality, hashing, serialization, module interfaces, and future substitution.

#ifndef WEAVEC_SEMANTIC_TYPE_GRAPH_C
#define WEAVEC_SEMANTIC_TYPE_GRAPH_C

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WEAVE_TYPE_NONE ((weave_type_ref)0)

typedef uint32_t weave_type_ref;

typedef enum weave_type_kind {
    WEAVE_TYPE_INVALID = -1,
    WEAVE_TYPE_ERROR = 0,
    WEAVE_TYPE_PRIMITIVE = 1,
    WEAVE_TYPE_NOMINAL = 2,
    WEAVE_TYPE_GENERIC_PARAMETER = 3,
    WEAVE_TYPE_APPLICATION = 4,
    WEAVE_TYPE_FUNCTION = 5,
    WEAVE_TYPE_VARIANT = 6,
    WEAVE_TYPE_POINTER = 7,
    WEAVE_TYPE_OWNED = 8,
    WEAVE_TYPE_BORROW = 9,
    WEAVE_TYPE_BORROW_MUT = 10,
} weave_type_kind;

typedef struct weave_type_buffer {
    char *data;
    size_t length;
    size_t capacity;
    int failed;
} weave_type_buffer;

typedef struct weave_type_node {
    weave_type_kind kind;
    uint64_t hash;
    char *identity;
    char *display;
    char *owner;
    char *name;
    uint32_t ordinal;
    weave_type_ref *children;
    size_t child_count;
} weave_type_node;

typedef struct weave_type_graph {
    weave_type_node *nodes;
    size_t count;
    size_t capacity;
    weave_type_ref *slots;
    size_t slot_count;
    weave_type_ref error_type;
} weave_type_graph;

static char *weave_type_copy_string(const char *value) {
    if (value == NULL) return NULL;
    size_t length = strlen(value);
    char *copy = malloc(length + 1);
    if (copy == NULL) return NULL;
    memcpy(copy, value, length + 1);
    return copy;
}

static int weave_type_buffer_reserve(
    weave_type_buffer *buffer,
    size_t additional) {
    if (buffer->failed) return 0;
    if (additional > SIZE_MAX - buffer->length - 1) {
        buffer->failed = 1;
        return 0;
    }
    size_t required = buffer->length + additional + 1;
    if (required <= buffer->capacity) return 1;
    size_t capacity = buffer->capacity == 0 ? 64 : buffer->capacity;
    while (capacity < required) {
        if (capacity > SIZE_MAX / 2) {
            capacity = required;
            break;
        }
        capacity *= 2;
    }
    char *grown = realloc(buffer->data, capacity);
    if (grown == NULL) {
        buffer->failed = 1;
        return 0;
    }
    buffer->data = grown;
    buffer->capacity = capacity;
    return 1;
}

static int weave_type_buffer_append_n(
    weave_type_buffer *buffer,
    const char *value,
    size_t length) {
    if (!weave_type_buffer_reserve(buffer, length)) return 0;
    if (length != 0) memcpy(buffer->data + buffer->length, value, length);
    buffer->length += length;
    buffer->data[buffer->length] = '\0';
    return 1;
}

static int weave_type_buffer_append(
    weave_type_buffer *buffer,
    const char *value) {
    return value != NULL &&
        weave_type_buffer_append_n(buffer, value, strlen(value));
}

static int weave_type_buffer_append_size(
    weave_type_buffer *buffer,
    size_t value) {
    char encoded[32];
    int count = snprintf(encoded, sizeof(encoded), "%zu", value);
    return count >= 0 && (size_t)count < sizeof(encoded) &&
        weave_type_buffer_append_n(buffer, encoded, (size_t)count);
}

static int weave_type_buffer_append_u32(
    weave_type_buffer *buffer,
    uint32_t value) {
    char encoded[16];
    int count = snprintf(encoded, sizeof(encoded), "%u", value);
    return count >= 0 && (size_t)count < sizeof(encoded) &&
        weave_type_buffer_append_n(buffer, encoded, (size_t)count);
}

static int weave_type_buffer_append_field(
    weave_type_buffer *buffer,
    const char *value) {
    if (value == NULL) return 0;
    size_t length = strlen(value);
    return weave_type_buffer_append(buffer, "|") &&
        weave_type_buffer_append_size(buffer, length) &&
        weave_type_buffer_append(buffer, ":") &&
        weave_type_buffer_append_n(buffer, value, length);
}

static char *weave_type_buffer_take(weave_type_buffer *buffer) {
    if (buffer->failed) {
        free(buffer->data);
        memset(buffer, 0, sizeof(*buffer));
        return NULL;
    }
    if (buffer->data == NULL) {
        buffer->data = calloc(1, 1);
        if (buffer->data == NULL) return NULL;
    }
    char *data = buffer->data;
    memset(buffer, 0, sizeof(*buffer));
    return data;
}

static uint64_t weave_type_hash_bytes(const char *value) {
    const unsigned char *bytes = (const unsigned char *)value;
    uint64_t hash = UINT64_C(14695981039346656037);
    while (*bytes != '\0') {
        hash ^= (uint64_t)*bytes++;
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

static const weave_type_node *weave_type_graph_node(
    const weave_type_graph *graph,
    weave_type_ref reference) {
    if (graph == NULL || reference == WEAVE_TYPE_NONE ||
        (size_t)reference > graph->count) {
        return NULL;
    }
    return &graph->nodes[(size_t)reference - 1];
}

static int weave_type_graph_reserve_nodes(weave_type_graph *graph) {
    if (graph->count < graph->capacity) return 1;
    size_t capacity = graph->capacity == 0 ? 16 : graph->capacity * 2;
    if (capacity < graph->capacity || capacity > UINT32_MAX ||
        capacity > SIZE_MAX / sizeof(*graph->nodes)) {
        return 0;
    }
    weave_type_node *nodes = realloc(
        graph->nodes, capacity * sizeof(*graph->nodes));
    if (nodes == NULL) return 0;
    memset(
        nodes + graph->capacity,
        0,
        (capacity - graph->capacity) * sizeof(*nodes));
    graph->nodes = nodes;
    graph->capacity = capacity;
    return 1;
}

static int weave_type_graph_rehash(
    weave_type_graph *graph,
    size_t slot_count) {
    weave_type_ref *slots = calloc(slot_count, sizeof(*slots));
    if (slots == NULL) return 0;
    for (size_t index = 0; index < graph->count; ++index) {
        size_t slot = (size_t)(graph->nodes[index].hash & (slot_count - 1));
        while (slots[slot] != WEAVE_TYPE_NONE) {
            slot = (slot + 1) & (slot_count - 1);
        }
        slots[slot] = (weave_type_ref)(index + 1);
    }
    free(graph->slots);
    graph->slots = slots;
    graph->slot_count = slot_count;
    return 1;
}

static int weave_type_graph_prepare_slots(weave_type_graph *graph) {
    if (graph->slot_count == 0) return weave_type_graph_rehash(graph, 32);
    size_t threshold = graph->slot_count - graph->slot_count / 3;
    if (graph->count + 1 < threshold) return 1;
    if (graph->slot_count > SIZE_MAX / 2) return 0;
    return weave_type_graph_rehash(graph, graph->slot_count * 2);
}

static weave_type_ref weave_type_graph_find(
    const weave_type_graph *graph,
    uint64_t hash,
    const char *identity) {
    if (graph->slot_count == 0) return WEAVE_TYPE_NONE;
    size_t slot = (size_t)(hash & (graph->slot_count - 1));
    size_t start = slot;
    while (graph->slots[slot] != WEAVE_TYPE_NONE) {
        weave_type_ref reference = graph->slots[slot];
        const weave_type_node *node = weave_type_graph_node(graph, reference);
        if (node != NULL && node->hash == hash &&
            strcmp(node->identity, identity) == 0) {
            return reference;
        }
        slot = (slot + 1) & (graph->slot_count - 1);
        if (slot == start) break;
    }
    return WEAVE_TYPE_NONE;
}

static void weave_type_node_clear(weave_type_node *node) {
    free(node->identity);
    free(node->display);
    free(node->owner);
    free(node->name);
    free(node->children);
    memset(node, 0, sizeof(*node));
}

static weave_type_ref weave_type_graph_intern(
    weave_type_graph *graph,
    weave_type_kind kind,
    char *identity,
    char *display,
    const char *owner,
    const char *name,
    uint32_t ordinal,
    const weave_type_ref *children,
    size_t child_count) {
    if (graph == NULL || identity == NULL || display == NULL) {
        free(identity);
        free(display);
        return WEAVE_TYPE_NONE;
    }
    uint64_t hash = weave_type_hash_bytes(identity);
    weave_type_ref existing = weave_type_graph_find(graph, hash, identity);
    if (existing != WEAVE_TYPE_NONE) {
        free(identity);
        free(display);
        return existing;
    }
    if (!weave_type_graph_prepare_slots(graph) ||
        !weave_type_graph_reserve_nodes(graph)) {
        free(identity);
        free(display);
        return WEAVE_TYPE_NONE;
    }

    weave_type_node node;
    memset(&node, 0, sizeof(node));
    node.kind = kind;
    node.hash = hash;
    node.identity = identity;
    node.display = display;
    node.owner = weave_type_copy_string(owner);
    node.name = weave_type_copy_string(name);
    node.ordinal = ordinal;
    if ((owner != NULL && node.owner == NULL) ||
        (name != NULL && node.name == NULL)) {
        weave_type_node_clear(&node);
        return WEAVE_TYPE_NONE;
    }
    if (child_count != 0) {
        if (child_count > SIZE_MAX / sizeof(*node.children)) {
            weave_type_node_clear(&node);
            return WEAVE_TYPE_NONE;
        }
        node.children = malloc(child_count * sizeof(*node.children));
        if (node.children == NULL) {
            weave_type_node_clear(&node);
            return WEAVE_TYPE_NONE;
        }
        memcpy(node.children, children, child_count * sizeof(*node.children));
        node.child_count = child_count;
    }

    size_t index = graph->count++;
    graph->nodes[index] = node;
    weave_type_ref reference = (weave_type_ref)(index + 1);
    size_t slot = (size_t)(hash & (graph->slot_count - 1));
    while (graph->slots[slot] != WEAVE_TYPE_NONE) {
        slot = (slot + 1) & (graph->slot_count - 1);
    }
    graph->slots[slot] = reference;
    return reference;
}

static int weave_type_graph_all_valid(
    const weave_type_graph *graph,
    const weave_type_ref *children,
    size_t child_count) {
    if (child_count != 0 && children == NULL) return 0;
    for (size_t index = 0; index < child_count; ++index) {
        if (weave_type_graph_node(graph, children[index]) == NULL) return 0;
    }
    return 1;
}

static int weave_type_identity_children(
    weave_type_buffer *buffer,
    const weave_type_graph *graph,
    const weave_type_ref *children,
    size_t child_count) {
    if (!weave_type_buffer_append_field(buffer, "children") ||
        !weave_type_buffer_append(buffer, "|") ||
        !weave_type_buffer_append_size(buffer, child_count)) {
        return 0;
    }
    for (size_t index = 0; index < child_count; ++index) {
        const weave_type_node *child = weave_type_graph_node(graph, children[index]);
        if (child == NULL ||
            !weave_type_buffer_append_field(buffer, child->identity)) {
            return 0;
        }
    }
    return 1;
}

static int weave_type_display_children(
    weave_type_buffer *buffer,
    const weave_type_graph *graph,
    const weave_type_ref *children,
    size_t child_count,
    const char *separator) {
    for (size_t index = 0; index < child_count; ++index) {
        const weave_type_node *child = weave_type_graph_node(graph, children[index]);
        if (child == NULL) return 0;
        if (index != 0 && !weave_type_buffer_append(buffer, separator)) return 0;
        if (!weave_type_buffer_append(buffer, child->display)) return 0;
    }
    return 1;
}

void weave_type_graph_clear(weave_type_graph *graph);

int weave_type_graph_init(weave_type_graph *graph) {
    if (graph == NULL) return 0;
    memset(graph, 0, sizeof(*graph));
    weave_type_buffer identity = {0};
    weave_type_buffer display = {0};
    if (!weave_type_buffer_append(&identity, "error") ||
        !weave_type_buffer_append(&display, "<error>")) {
        free(identity.data);
        free(display.data);
        return 0;
    }
    char *identity_text = weave_type_buffer_take(&identity);
    char *display_text = weave_type_buffer_take(&display);
    graph->error_type = weave_type_graph_intern(
        graph,
        WEAVE_TYPE_ERROR,
        identity_text,
        display_text,
        NULL,
        NULL,
        0,
        NULL,
        0);
    if (graph->error_type == WEAVE_TYPE_NONE) {
        weave_type_graph_clear(graph);
        return 0;
    }
    return 1;
}

void weave_type_graph_clear(weave_type_graph *graph) {
    if (graph == NULL) return;
    for (size_t index = 0; index < graph->count; ++index) {
        weave_type_node_clear(&graph->nodes[index]);
    }
    free(graph->nodes);
    free(graph->slots);
    memset(graph, 0, sizeof(*graph));
}

weave_type_ref weave_type_graph_error(const weave_type_graph *graph) {
    return graph == NULL ? WEAVE_TYPE_NONE : graph->error_type;
}

weave_type_ref weave_type_graph_primitive(
    weave_type_graph *graph,
    const char *name) {
    if (graph == NULL || name == NULL || *name == '\0') return WEAVE_TYPE_NONE;
    weave_type_buffer identity = {0};
    weave_type_buffer display = {0};
    if (!weave_type_buffer_append(&identity, "primitive") ||
        !weave_type_buffer_append_field(&identity, name) ||
        !weave_type_buffer_append(&display, name)) {
        free(identity.data);
        free(display.data);
        return WEAVE_TYPE_NONE;
    }
    return weave_type_graph_intern(
        graph,
        WEAVE_TYPE_PRIMITIVE,
        weave_type_buffer_take(&identity),
        weave_type_buffer_take(&display),
        NULL,
        name,
        0,
        NULL,
        0);
}

weave_type_ref weave_type_graph_nominal(
    weave_type_graph *graph,
    const char *module,
    const char *name) {
    if (graph == NULL || module == NULL || *module == '\0' ||
        name == NULL || *name == '\0') {
        return WEAVE_TYPE_NONE;
    }
    weave_type_buffer identity = {0};
    weave_type_buffer display = {0};
    if (!weave_type_buffer_append(&identity, "nominal") ||
        !weave_type_buffer_append_field(&identity, module) ||
        !weave_type_buffer_append_field(&identity, name) ||
        !weave_type_buffer_append(&display, module) ||
        !weave_type_buffer_append(&display, "::") ||
        !weave_type_buffer_append(&display, name)) {
        free(identity.data);
        free(display.data);
        return WEAVE_TYPE_NONE;
    }
    return weave_type_graph_intern(
        graph,
        WEAVE_TYPE_NOMINAL,
        weave_type_buffer_take(&identity),
        weave_type_buffer_take(&display),
        module,
        name,
        0,
        NULL,
        0);
}

weave_type_ref weave_type_graph_generic_parameter(
    weave_type_graph *graph,
    const char *owner,
    uint32_t ordinal,
    const char *name) {
    if (graph == NULL || owner == NULL || *owner == '\0' ||
        name == NULL || *name == '\0') {
        return WEAVE_TYPE_NONE;
    }
    weave_type_buffer identity = {0};
    weave_type_buffer display = {0};
    if (!weave_type_buffer_append(&identity, "generic-parameter") ||
        !weave_type_buffer_append_field(&identity, owner) ||
        !weave_type_buffer_append(&identity, "|") ||
        !weave_type_buffer_append_u32(&identity, ordinal) ||
        !weave_type_buffer_append_field(&identity, name) ||
        !weave_type_buffer_append(&display, name)) {
        free(identity.data);
        free(display.data);
        return WEAVE_TYPE_NONE;
    }
    return weave_type_graph_intern(
        graph,
        WEAVE_TYPE_GENERIC_PARAMETER,
        weave_type_buffer_take(&identity),
        weave_type_buffer_take(&display),
        owner,
        name,
        ordinal,
        NULL,
        0);
}

weave_type_ref weave_type_graph_application(
    weave_type_graph *graph,
    weave_type_ref constructor,
    const weave_type_ref *arguments,
    size_t argument_count) {
    const weave_type_node *constructor_node =
        weave_type_graph_node(graph, constructor);
    if (constructor_node == NULL || argument_count == 0 ||
        !weave_type_graph_all_valid(graph, arguments, argument_count)) {
        return WEAVE_TYPE_NONE;
    }
    size_t child_count = argument_count + 1;
    if (child_count < argument_count ||
        child_count > SIZE_MAX / sizeof(weave_type_ref)) {
        return WEAVE_TYPE_NONE;
    }
    weave_type_ref *children = malloc(child_count * sizeof(*children));
    if (children == NULL) return WEAVE_TYPE_NONE;
    children[0] = constructor;
    memcpy(children + 1, arguments, argument_count * sizeof(*arguments));

    weave_type_buffer identity = {0};
    weave_type_buffer display = {0};
    int ok = weave_type_buffer_append(&identity, "application") &&
        weave_type_identity_children(
            &identity, graph, children, child_count) &&
        weave_type_buffer_append(&display, constructor_node->display) &&
        weave_type_buffer_append(&display, "<") &&
        weave_type_display_children(
            &display, graph, arguments, argument_count, ", ") &&
        weave_type_buffer_append(&display, ">");
    weave_type_ref reference = WEAVE_TYPE_NONE;
    if (ok) {
        reference = weave_type_graph_intern(
            graph,
            WEAVE_TYPE_APPLICATION,
            weave_type_buffer_take(&identity),
            weave_type_buffer_take(&display),
            NULL,
            NULL,
            0,
            children,
            child_count);
    } else {
        free(identity.data);
        free(display.data);
    }
    free(children);
    return reference;
}

weave_type_ref weave_type_graph_function(
    weave_type_graph *graph,
    const weave_type_ref *parameters,
    size_t parameter_count,
    weave_type_ref result) {
    if (!weave_type_graph_all_valid(graph, parameters, parameter_count) ||
        weave_type_graph_node(graph, result) == NULL) {
        return WEAVE_TYPE_NONE;
    }
    size_t child_count = parameter_count + 1;
    if (child_count < parameter_count ||
        child_count > SIZE_MAX / sizeof(weave_type_ref)) {
        return WEAVE_TYPE_NONE;
    }
    weave_type_ref *children = malloc(child_count * sizeof(*children));
    if (children == NULL) return WEAVE_TYPE_NONE;
    if (parameter_count != 0) {
        memcpy(children, parameters, parameter_count * sizeof(*parameters));
    }
    children[parameter_count] = result;

    weave_type_buffer identity = {0};
    weave_type_buffer display = {0};
    const weave_type_node *result_node = weave_type_graph_node(graph, result);
    int ok = weave_type_buffer_append(&identity, "function") &&
        weave_type_buffer_append_field(&identity, "parameters") &&
        weave_type_buffer_append(&identity, "|") &&
        weave_type_buffer_append_size(&identity, parameter_count);
    for (size_t index = 0; ok && index < parameter_count; ++index) {
        const weave_type_node *node = weave_type_graph_node(graph, parameters[index]);
        ok = node != NULL && weave_type_buffer_append_field(&identity, node->identity);
    }
    ok = ok && weave_type_buffer_append_field(&identity, "result") &&
        weave_type_buffer_append_field(&identity, result_node->identity) &&
        weave_type_buffer_append(&display, "fn(") &&
        weave_type_display_children(
            &display, graph, parameters, parameter_count, ", ") &&
        weave_type_buffer_append(&display, ") -> ") &&
        weave_type_buffer_append(&display, result_node->display);

    weave_type_ref reference = WEAVE_TYPE_NONE;
    if (ok) {
        reference = weave_type_graph_intern(
            graph,
            WEAVE_TYPE_FUNCTION,
            weave_type_buffer_take(&identity),
            weave_type_buffer_take(&display),
            NULL,
            NULL,
            0,
            children,
            child_count);
    } else {
        free(identity.data);
        free(display.data);
    }
    free(children);
    return reference;
}

weave_type_ref weave_type_graph_variant(
    weave_type_graph *graph,
    weave_type_ref owner,
    const char *name,
    const weave_type_ref *payloads,
    size_t payload_count) {
    const weave_type_node *owner_node = weave_type_graph_node(graph, owner);
    if (owner_node == NULL || name == NULL || *name == '\0' ||
        !weave_type_graph_all_valid(graph, payloads, payload_count)) {
        return WEAVE_TYPE_NONE;
    }
    size_t child_count = payload_count + 1;
    if (child_count < payload_count ||
        child_count > SIZE_MAX / sizeof(weave_type_ref)) {
        return WEAVE_TYPE_NONE;
    }
    weave_type_ref *children = malloc(child_count * sizeof(*children));
    if (children == NULL) return WEAVE_TYPE_NONE;
    children[0] = owner;
    if (payload_count != 0) {
        memcpy(children + 1, payloads, payload_count * sizeof(*payloads));
    }

    weave_type_buffer identity = {0};
    weave_type_buffer display = {0};
    int ok = weave_type_buffer_append(&identity, "variant") &&
        weave_type_buffer_append_field(&identity, owner_node->identity) &&
        weave_type_buffer_append_field(&identity, name) &&
        weave_type_identity_children(&identity, graph, payloads, payload_count) &&
        weave_type_buffer_append(&display, owner_node->display) &&
        weave_type_buffer_append(&display, "::") &&
        weave_type_buffer_append(&display, name);
    if (ok && payload_count != 0) {
        ok = weave_type_buffer_append(&display, "(") &&
            weave_type_display_children(
                &display, graph, payloads, payload_count, ", ") &&
            weave_type_buffer_append(&display, ")");
    }

    weave_type_ref reference = WEAVE_TYPE_NONE;
    if (ok) {
        reference = weave_type_graph_intern(
            graph,
            WEAVE_TYPE_VARIANT,
            weave_type_buffer_take(&identity),
            weave_type_buffer_take(&display),
            owner_node->identity,
            name,
            0,
            children,
            child_count);
    } else {
        free(identity.data);
        free(display.data);
    }
    free(children);
    return reference;
}

static weave_type_ref weave_type_graph_unary(
    weave_type_graph *graph,
    weave_type_kind kind,
    const char *identity_name,
    const char *display_name,
    weave_type_ref base) {
    const weave_type_node *base_node = weave_type_graph_node(graph, base);
    if (base_node == NULL) return WEAVE_TYPE_NONE;
    weave_type_buffer identity = {0};
    weave_type_buffer display = {0};
    if (!weave_type_buffer_append(&identity, identity_name) ||
        !weave_type_buffer_append_field(&identity, base_node->identity) ||
        !weave_type_buffer_append(&display, display_name) ||
        !weave_type_buffer_append(&display, "<") ||
        !weave_type_buffer_append(&display, base_node->display) ||
        !weave_type_buffer_append(&display, ">")) {
        free(identity.data);
        free(display.data);
        return WEAVE_TYPE_NONE;
    }
    return weave_type_graph_intern(
        graph,
        kind,
        weave_type_buffer_take(&identity),
        weave_type_buffer_take(&display),
        NULL,
        NULL,
        0,
        &base,
        1);
}

weave_type_ref weave_type_graph_pointer(
    weave_type_graph *graph,
    weave_type_ref pointee) {
    return weave_type_graph_unary(
        graph, WEAVE_TYPE_POINTER, "pointer", "ptr", pointee);
}

weave_type_ref weave_type_graph_owned(
    weave_type_graph *graph,
    weave_type_ref base) {
    return weave_type_graph_unary(
        graph, WEAVE_TYPE_OWNED, "owned", "owned", base);
}

weave_type_ref weave_type_graph_borrow(
    weave_type_graph *graph,
    weave_type_ref base) {
    return weave_type_graph_unary(
        graph, WEAVE_TYPE_BORROW, "borrow", "borrow", base);
}

weave_type_ref weave_type_graph_borrow_mut(
    weave_type_graph *graph,
    weave_type_ref base) {
    return weave_type_graph_unary(
        graph, WEAVE_TYPE_BORROW_MUT, "borrow-mut", "borrow-mut", base);
}

weave_type_kind weave_type_graph_kind(
    const weave_type_graph *graph,
    weave_type_ref reference) {
    const weave_type_node *node = weave_type_graph_node(graph, reference);
    return node == NULL ? WEAVE_TYPE_INVALID : node->kind;
}

const char *weave_type_graph_identity(
    const weave_type_graph *graph,
    weave_type_ref reference) {
    const weave_type_node *node = weave_type_graph_node(graph, reference);
    return node == NULL ? NULL : node->identity;
}

const char *weave_type_graph_display(
    const weave_type_graph *graph,
    weave_type_ref reference) {
    const weave_type_node *node = weave_type_graph_node(graph, reference);
    return node == NULL ? NULL : node->display;
}

uint64_t weave_type_graph_hash(
    const weave_type_graph *graph,
    weave_type_ref reference) {
    const weave_type_node *node = weave_type_graph_node(graph, reference);
    return node == NULL ? 0 : node->hash;
}

const char *weave_type_graph_owner(
    const weave_type_graph *graph,
    weave_type_ref reference) {
    const weave_type_node *node = weave_type_graph_node(graph, reference);
    return node == NULL ? NULL : node->owner;
}

const char *weave_type_graph_name(
    const weave_type_graph *graph,
    weave_type_ref reference) {
    const weave_type_node *node = weave_type_graph_node(graph, reference);
    return node == NULL ? NULL : node->name;
}

uint32_t weave_type_graph_ordinal(
    const weave_type_graph *graph,
    weave_type_ref reference) {
    const weave_type_node *node = weave_type_graph_node(graph, reference);
    return node == NULL ? 0 : node->ordinal;
}

size_t weave_type_graph_child_count(
    const weave_type_graph *graph,
    weave_type_ref reference) {
    const weave_type_node *node = weave_type_graph_node(graph, reference);
    return node == NULL ? 0 : node->child_count;
}

weave_type_ref weave_type_graph_child(
    const weave_type_graph *graph,
    weave_type_ref reference,
    size_t index) {
    const weave_type_node *node = weave_type_graph_node(graph, reference);
    return node == NULL || index >= node->child_count
        ? WEAVE_TYPE_NONE
        : node->children[index];
}

int weave_type_graph_equal(
    const weave_type_graph *left_graph,
    weave_type_ref left,
    const weave_type_graph *right_graph,
    weave_type_ref right) {
    const weave_type_node *left_node = weave_type_graph_node(left_graph, left);
    const weave_type_node *right_node = weave_type_graph_node(right_graph, right);
    return left_node != NULL && right_node != NULL &&
        left_node->hash == right_node->hash &&
        strcmp(left_node->identity, right_node->identity) == 0;
}

weave_type_ref weave_type_graph_from_legacy_code(
    weave_type_graph *graph,
    int32_t code) {
    switch (code) {
        case 0: return weave_type_graph_error(graph);
        case 1: return weave_type_graph_primitive(graph, "void");
        case 2: return weave_type_graph_primitive(graph, "i32");
        case 3: return weave_type_graph_primitive(graph, "i64");
        case 4: return weave_type_graph_primitive(graph, "f32");
        case 5: return weave_type_graph_primitive(graph, "f64");
        case 6: return weave_type_graph_primitive(graph, "bool");
        case 7: return weave_type_graph_primitive(graph, "ptr");
        default: return weave_type_graph_error(graph);
    }
}

int32_t weave_type_graph_to_legacy_code(
    const weave_type_graph *graph,
    weave_type_ref reference) {
    const weave_type_node *node = weave_type_graph_node(graph, reference);
    if (node == NULL || node->kind == WEAVE_TYPE_ERROR) return 0;
    if (node->kind != WEAVE_TYPE_PRIMITIVE || node->name == NULL) return 0;
    if (strcmp(node->name, "void") == 0) return 1;
    if (strcmp(node->name, "i32") == 0) return 2;
    if (strcmp(node->name, "i64") == 0) return 3;
    if (strcmp(node->name, "f32") == 0) return 4;
    if (strcmp(node->name, "f64") == 0) return 5;
    if (strcmp(node->name, "bool") == 0) return 6;
    if (strcmp(node->name, "ptr") == 0) return 7;
    return 0;
}

#endif
