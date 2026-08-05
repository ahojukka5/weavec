typedef struct weave_capability_protocol {
    const char *id; const char *kind; int version;
} weave_capability_protocol;
typedef struct weave_capability_command {
    const char *name; const char *spelling; const char *audience;
    const char *status; size_t protocol_start; size_t protocol_count;
} weave_capability_command;
typedef struct weave_capability_feature {
    const char *id; const char *status; int issue;
} weave_capability_feature;
typedef struct weave_capability_role {
    const char *name; const char *cardinality; const char *kind; int position;
} weave_capability_role;
typedef struct weave_capability_form {
    const char *head; const char *status; const char *type_information;
    const char *feature; const char *canonical_replacement;
    int min_children; int max_children; size_t role_start; size_t role_count;
} weave_capability_form;
typedef struct weave_capability_family {
    const char *id; const char *status; const char *head_pattern;
    const char *canonical_replacement; const char *type_information;
    const char *grammar_reference; size_t member_start; size_t member_count;
} weave_capability_family;
typedef struct weave_capability_operator_group {
    const char *id; const char *result_type;
    size_t name_start; size_t name_count;
    size_t type_start; size_t type_count; int arity;
} weave_capability_operator_group;
typedef struct weave_capability_cast_pair {
    const char *source; const char *target;
} weave_capability_cast_pair;
typedef struct weave_capability_literal_kind {
    const char *kind; size_t type_start; size_t type_count;
    size_t context_start; size_t context_count;
} weave_capability_literal_kind;
static int weave_capabilities_write_bool(
    weave_json_writer *writer, int value) {
    return weave_json_before_value(writer) &&
        weave_json_write_cstr(writer, value ? "true" : "false");
}


static const char *const weave_cap_command_protocols[] = {
    "weavec-capabilities-v1",
    "weavec-build-manifest-v1",
    "weavec-diagnostics-v1",
    "weavec-compilation-trace-v1",
    "weave-wir-core-v2",
    "weave-wir-core-v2",
    "weavec-semantic-index-v1",
};
static const char *const weave_cap_family_members[] = {
    "call_i32",
    "call_i64",
    "call_f32",
    "call_f64",
    "call_bool",
    "call_ptr",
    "call_void",
    "const_i32",
    "const_i64",
    "const_f32",
    "const_f64",
    "const_bool",
    "const_null",
    "const_string_ptr",
    "arithmetic:numeric",
    "bitwise:integer",
    "comparison:numeric-or-pointer-equality",
    "boolean:bool",
    "i64->i32",
    "i32->i64",
    "i32->f32",
    "i32->f64",
    "f32->i32",
    "f32->f64",
    "f64->i32",
    "f64->f32",
    "param_get",
    "local_get",
};
static const char *const weave_cap_primitive_types[] = {
    "i32",
    "i64",
    "f32",
    "f64",
    "bool",
    "ptr",
    "void",
    "Qubit",
};
static const char *const weave_cap_operator_names[] = {
    "add",
    "sub",
    "mul",
    "div",
    "mod",
    "bit-and",
    "bit-or",
    "bit-xor",
    "shift-left",
    "shift-right",
    "equal",
    "not-equal",
    "less-than",
    "less-or-equal",
    "greater-than",
    "greater-or-equal",
    "and",
    "or",
    "not",
};
static const char *const weave_cap_operator_types[] = {
    "i32",
    "i64",
    "f32",
    "f64",
    "i32",
    "i64",
    "i32",
    "i64",
    "f32",
    "f64",
    "ptr",
    "i32",
    "i64",
    "f32",
    "f64",
    "bool",
    "bool",
};
static const char *const weave_cap_literal_types[] = {
    "i32",
    "i64",
    "bool",
    "ptr",
    "ptr",
};
static const char *const weave_cap_literal_contexts[] = {
    "binding",
    "assignment",
    "argument",
    "return",
    "operator-operand",
    "binding",
    "assignment",
    "argument",
    "return",
    "operator-operand",
    "condition",
    "binding",
    "assignment",
    "argument",
    "return",
    "operator-operand",
    "binding",
    "assignment",
    "argument",
    "return",
};
