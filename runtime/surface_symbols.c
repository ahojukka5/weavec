// SPDX-License-Identifier: Apache-2.0
//
// Storage for compiler-owned surface semantic facts. This file deliberately
// knows nothing about Weave syntax: the self-hosted frontend assigns type codes,
// decides which declarations, modules, imports, exports, and bindings exist, and
// performs all semantic validation. Host C only copies names so facts survive
// per-file parser teardown.

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define WEAVEC_SURFACE_MAX_SYMBOLS 4096
#define WEAVEC_SURFACE_MAX_PARAMS 64
#define WEAVEC_SURFACE_MAX_LOCALS 4096
#define WEAVEC_SURFACE_MAX_STRUCTS 512
#define WEAVEC_SURFACE_MAX_STRUCT_FIELDS 128
#define WEAVEC_SURFACE_MAX_TYPE_PARAMS 16
#define WEAVEC_SURFACE_MAX_SPECS 64
#define WEAVEC_SURFACE_MAX_ENUMS 256
#define WEAVEC_SURFACE_MAX_VARIANTS 32
#define WEAVEC_SURFACE_MAX_ENUM_SPECS 64
#define WEAVEC_SURFACE_STRUCT_TYPE_BASE 1024
#define WEAVEC_SURFACE_MAX_MODULES 512
#define WEAVEC_SURFACE_MAX_EXPORTS 4096
#define WEAVEC_SURFACE_MAX_IMPORTS 4096

#define WEAVEC_SURFACE_MODULE_MODE_UNSET 0
#define WEAVEC_SURFACE_MODULE_MODE_LEGACY 1
#define WEAVEC_SURFACE_MODULE_MODE_EXPLICIT 2

#define WEAVEC_SURFACE_RESOLUTION_OK 0
#define WEAVEC_SURFACE_RESOLUTION_MISSING 1
#define WEAVEC_SURFACE_RESOLUTION_NOT_IMPORTED 2
#define WEAVEC_SURFACE_RESOLUTION_PRIVATE 3
#define WEAVEC_SURFACE_RESOLUTION_AMBIGUOUS 4

typedef struct {
    char *name;
    int64_t name_length;
    int32_t return_type;
    int32_t parameter_count;
    int32_t parameter_types[WEAVEC_SURFACE_MAX_PARAMS];
    int32_t type_param_count;
    int32_t type_param_types[WEAVEC_SURFACE_MAX_TYPE_PARAMS];
    int32_t module_index;
    char *source_path;
} weave_surface_symbol;

typedef struct {
    char *generic_name;
    int64_t generic_name_length;
    char *key;
    char *spec_name;
    char *source_path;
    int32_t arg_count;
    int32_t arg_types[WEAVEC_SURFACE_MAX_TYPE_PARAMS];
    int32_t emitted;
} weave_surface_spec;

typedef struct {
    char *name;
    int64_t name_length;
    int32_t type;
} weave_surface_local;

typedef struct {
    char *name;
    int64_t name_length;
    int32_t type;
} weave_surface_struct_field;

typedef struct {
    char *name;
    int64_t name_length;
    int32_t defined;
    int32_t field_count;
    int32_t type_param_count;
    weave_surface_struct_field fields[WEAVEC_SURFACE_MAX_STRUCT_FIELDS];
} weave_surface_struct;

typedef struct {
    char *name;
    int64_t name_length;
    int32_t payload_type;
    int32_t tag;
} weave_surface_enum_variant;

typedef struct {
    char *name;
    int64_t name_length;
    int32_t defined;
    int32_t variant_count;
    int32_t type_param_count;
    int32_t graph_type;
    char *source_path;
    weave_surface_enum_variant variants[WEAVEC_SURFACE_MAX_VARIANTS];
} weave_surface_enum;

typedef struct {
    char *generic_name;
    int64_t generic_name_length;
    char *key;
    char *spec_name;
    char *source_path;
    int32_t arg_count;
    int32_t arg_types[WEAVEC_SURFACE_MAX_TYPE_PARAMS];
    int32_t emitted;
} weave_surface_enum_spec;

typedef struct {
    char *name;
    int64_t name_length;
    int32_t type;
    int32_t ordinal;
} weave_surface_type_param;

typedef struct {
    char *name;
    int64_t name_length;
} weave_surface_module;

typedef struct {
    int32_t module_index;
    char *name;
    int64_t name_length;
} weave_surface_export;

typedef struct {
    int32_t owner_module_index;
    char *module_name;
    int64_t module_name_length;
    char *symbol_name;
    int64_t symbol_name_length;
} weave_surface_import;

static weave_surface_symbol weave_surface_symbols[WEAVEC_SURFACE_MAX_SYMBOLS];
static int32_t weave_surface_symbol_count;
static int32_t weave_surface_symbol_being_built = -1;
static weave_surface_local weave_surface_locals[WEAVEC_SURFACE_MAX_LOCALS];
static int32_t weave_surface_local_count;
static int32_t weave_surface_match_temp;
static weave_surface_struct weave_surface_structs[WEAVEC_SURFACE_MAX_STRUCTS];
static int32_t weave_surface_struct_count;
static weave_surface_module weave_surface_modules[WEAVEC_SURFACE_MAX_MODULES];
static int32_t weave_surface_module_count;
static weave_surface_export weave_surface_exports[WEAVEC_SURFACE_MAX_EXPORTS];
static int32_t weave_surface_export_count;
static weave_surface_import weave_surface_imports[WEAVEC_SURFACE_MAX_IMPORTS];
static int32_t weave_surface_import_count;
static int32_t weave_surface_module_mode;
static int32_t weave_surface_current_module = -1;
static int32_t weave_surface_resolution_status;
static int32_t weave_surface_return_type;
static int32_t weave_surface_error;
static weave_surface_type_param
    weave_surface_type_params[WEAVEC_SURFACE_MAX_TYPE_PARAMS];
static int32_t weave_surface_type_param_count;
static weave_surface_spec weave_surface_specs[WEAVEC_SURFACE_MAX_SPECS];
static int32_t weave_surface_n_specs;
static weave_surface_enum weave_surface_enums[WEAVEC_SURFACE_MAX_ENUMS];
static int32_t weave_surface_n_enums;
static weave_surface_enum_spec
    weave_surface_enum_specs[WEAVEC_SURFACE_MAX_ENUM_SPECS];
static int32_t weave_surface_n_enum_specs;
static char *weave_surface_current_source_path;

static char *weave_surface_copy_slice(
    const char *source,
    int64_t start,
    int64_t length) {
    if (source == NULL || start < 0 || length <= 0 ||
        (uint64_t)length > (uint64_t)SIZE_MAX - 1) {
        return NULL;
    }
    char *copy = (char *)malloc((size_t)length + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, source + start, (size_t)length);
    copy[length] = '\0';
    return copy;
}

static int weave_surface_slice_equal(
    const char *stored,
    int64_t stored_length,
    const char *source,
    int64_t start,
    int64_t length) {
    if (stored == NULL || source == NULL || start < 0 || length < 0 ||
        stored_length != length) {
        return 0;
    }
    return memcmp(stored, source + start, (size_t)length) == 0;
}

static int weave_surface_stored_equal(
    const char *left,
    int64_t left_length,
    const char *right,
    int64_t right_length) {
    return left != NULL && right != NULL && left_length == right_length &&
        memcmp(left, right, (size_t)left_length) == 0;
}

static int32_t weave_surface_struct_index_from_type(int32_t type) {
    int32_t index = type - WEAVEC_SURFACE_STRUCT_TYPE_BASE;
    if (index < 0 || index >= weave_surface_struct_count) {
        return -1;
    }
    return index;
}

static int32_t weave_surface_struct_find(
    const char *source,
    int64_t start,
    int64_t length) {
    for (int32_t index = 0; index < weave_surface_struct_count; ++index) {
        if (weave_surface_slice_equal(
                weave_surface_structs[index].name,
                weave_surface_structs[index].name_length,
                source,
                start,
                length)) {
            return index;
        }
    }
    return -1;
}

static int32_t weave_surface_struct_allocate(
    const char *source,
    int64_t start,
    int64_t length) {
    if (weave_surface_struct_count >= WEAVEC_SURFACE_MAX_STRUCTS) {
        return -1;
    }
    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    int32_t index = weave_surface_struct_count++;
    weave_surface_structs[index].name = name;
    weave_surface_structs[index].name_length = length;
    weave_surface_structs[index].defined = 0;
    weave_surface_structs[index].field_count = 0;
    weave_surface_structs[index].type_param_count = 0;
    return index;
}

static int32_t weave_surface_module_find_slice(
    const char *source,
    int64_t start,
    int64_t length) {
    for (int32_t index = 0; index < weave_surface_module_count; ++index) {
        if (weave_surface_slice_equal(
                weave_surface_modules[index].name,
                weave_surface_modules[index].name_length,
                source,
                start,
                length)) {
            return index;
        }
    }
    return -1;
}

static int32_t weave_surface_module_find_stored(
    const char *name,
    int64_t length) {
    for (int32_t index = 0; index < weave_surface_module_count; ++index) {
        if (weave_surface_stored_equal(
                weave_surface_modules[index].name,
                weave_surface_modules[index].name_length,
                name,
                length)) {
            return index;
        }
    }
    return -1;
}

static int weave_surface_export_matches(
    int32_t module_index,
    const char *source,
    int64_t start,
    int64_t length) {
    for (int32_t index = 0; index < weave_surface_export_count; ++index) {
        if (weave_surface_exports[index].module_index == module_index &&
            weave_surface_slice_equal(
                weave_surface_exports[index].name,
                weave_surface_exports[index].name_length,
                source,
                start,
                length)) {
            return 1;
        }
    }
    return 0;
}

static int weave_surface_export_matches_stored(
    int32_t module_index,
    const char *name,
    int64_t length) {
    for (int32_t index = 0; index < weave_surface_export_count; ++index) {
        if (weave_surface_exports[index].module_index == module_index &&
            weave_surface_stored_equal(
                weave_surface_exports[index].name,
                weave_surface_exports[index].name_length,
                name,
                length)) {
            return 1;
        }
    }
    return 0;
}

static int32_t weave_surface_symbol_find_in_module_slice(
    int32_t module_index,
    const char *source,
    int64_t start,
    int64_t length) {
    for (int32_t index = 0; index < weave_surface_symbol_count; ++index) {
        if (weave_surface_symbols[index].module_index == module_index &&
            weave_surface_slice_equal(
                weave_surface_symbols[index].name,
                weave_surface_symbols[index].name_length,
                source,
                start,
                length)) {
            return index;
        }
    }
    return -1;
}

static int32_t weave_surface_symbol_find_in_module_stored(
    int32_t module_index,
    const char *name,
    int64_t length) {
    for (int32_t index = 0; index < weave_surface_symbol_count; ++index) {
        if (weave_surface_symbols[index].module_index == module_index &&
            weave_surface_stored_equal(
                weave_surface_symbols[index].name,
                weave_surface_symbols[index].name_length,
                name,
                length)) {
            return index;
        }
    }
    return -1;
}

void weave_surface_symbols_reset(void) {
    for (int32_t index = 0; index < weave_surface_symbol_count; ++index) {
        free(weave_surface_symbols[index].name);
        free(weave_surface_symbols[index].source_path);
        weave_surface_symbols[index].name = NULL;
        weave_surface_symbols[index].source_path = NULL;
    }
    for (int32_t index = 0; index < weave_surface_local_count; ++index) {
        free(weave_surface_locals[index].name);
        weave_surface_locals[index].name = NULL;
    }
    for (int32_t index = 0; index < weave_surface_struct_count; ++index) {
        free(weave_surface_structs[index].name);
        weave_surface_structs[index].name = NULL;
        for (int32_t field = 0;
             field < weave_surface_structs[index].field_count;
             ++field) {
            free(weave_surface_structs[index].fields[field].name);
            weave_surface_structs[index].fields[field].name = NULL;
        }
    }
    for (int32_t index = 0; index < weave_surface_module_count; ++index) {
        free(weave_surface_modules[index].name);
        weave_surface_modules[index].name = NULL;
    }
    for (int32_t index = 0; index < weave_surface_export_count; ++index) {
        free(weave_surface_exports[index].name);
        weave_surface_exports[index].name = NULL;
    }
    for (int32_t index = 0; index < weave_surface_import_count; ++index) {
        free(weave_surface_imports[index].module_name);
        free(weave_surface_imports[index].symbol_name);
        weave_surface_imports[index].module_name = NULL;
        weave_surface_imports[index].symbol_name = NULL;
    }
    for (int32_t index = 0; index < weave_surface_type_param_count; ++index) {
        free(weave_surface_type_params[index].name);
        weave_surface_type_params[index].name = NULL;
    }
    for (int32_t index = 0; index < weave_surface_n_specs; ++index) {
        free(weave_surface_specs[index].generic_name);
        free(weave_surface_specs[index].key);
        free(weave_surface_specs[index].spec_name);
        free(weave_surface_specs[index].source_path);
        weave_surface_specs[index].generic_name = NULL;
        weave_surface_specs[index].key = NULL;
        weave_surface_specs[index].spec_name = NULL;
        weave_surface_specs[index].source_path = NULL;
    }
    for (int32_t index = 0; index < weave_surface_n_enums; ++index) {
        free(weave_surface_enums[index].name);
        free(weave_surface_enums[index].source_path);
        weave_surface_enums[index].name = NULL;
        weave_surface_enums[index].source_path = NULL;
        for (int32_t variant = 0;
             variant < weave_surface_enums[index].variant_count;
             ++variant) {
            free(weave_surface_enums[index].variants[variant].name);
            weave_surface_enums[index].variants[variant].name = NULL;
        }
    }
    for (int32_t index = 0; index < weave_surface_n_enum_specs; ++index) {
        free(weave_surface_enum_specs[index].generic_name);
        free(weave_surface_enum_specs[index].key);
        free(weave_surface_enum_specs[index].spec_name);
        free(weave_surface_enum_specs[index].source_path);
        weave_surface_enum_specs[index].generic_name = NULL;
        weave_surface_enum_specs[index].key = NULL;
        weave_surface_enum_specs[index].spec_name = NULL;
        weave_surface_enum_specs[index].source_path = NULL;
    }
    weave_surface_symbol_count = 0;
    weave_surface_symbol_being_built = -1;
    weave_surface_local_count = 0;
    weave_surface_match_temp = 0;
    weave_surface_struct_count = 0;
    weave_surface_module_count = 0;
    weave_surface_export_count = 0;
    weave_surface_import_count = 0;
    weave_surface_module_mode = WEAVEC_SURFACE_MODULE_MODE_UNSET;
    weave_surface_current_module = -1;
    weave_surface_resolution_status = WEAVEC_SURFACE_RESOLUTION_OK;
    weave_surface_return_type = 0;
    weave_surface_error = 0;
    weave_surface_type_param_count = 0;
    weave_surface_n_specs = 0;
    weave_surface_n_enums = 0;
    weave_surface_n_enum_specs = 0;
}

int32_t weave_surface_module_use_legacy(void) {
    if (weave_surface_module_mode == WEAVEC_SURFACE_MODULE_MODE_EXPLICIT) {
        return -2;
    }
    weave_surface_module_mode = WEAVEC_SURFACE_MODULE_MODE_LEGACY;
    weave_surface_current_module = -1;
    return 0;
}

int32_t weave_surface_module_begin(
    const char *source,
    int64_t start,
    int64_t length) {
    if (weave_surface_module_mode == WEAVEC_SURFACE_MODULE_MODE_LEGACY) {
        return -3;
    }
    if (weave_surface_module_find_slice(source, start, length) >= 0) {
        return -2;
    }
    if (weave_surface_module_count >= WEAVEC_SURFACE_MAX_MODULES) {
        return -1;
    }
    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    int32_t index = weave_surface_module_count++;
    weave_surface_modules[index].name = name;
    weave_surface_modules[index].name_length = length;
    weave_surface_module_mode = WEAVEC_SURFACE_MODULE_MODE_EXPLICIT;
    weave_surface_current_module = index;
    return index;
}

int32_t weave_surface_module_select(
    const char *source,
    int64_t start,
    int64_t length) {
    if (weave_surface_module_mode != WEAVEC_SURFACE_MODULE_MODE_EXPLICIT) {
        return -1;
    }
    int32_t index = weave_surface_module_find_slice(source, start, length);
    if (index < 0) {
        return -1;
    }
    weave_surface_current_module = index;
    return index;
}

int32_t weave_surface_module_add_export(
    const char *source,
    int64_t start,
    int64_t length) {
    if (weave_surface_current_module < 0 ||
        weave_surface_export_count >= WEAVEC_SURFACE_MAX_EXPORTS) {
        return -1;
    }
    if (weave_surface_export_matches(
            weave_surface_current_module, source, start, length)) {
        return -2;
    }
    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    int32_t index = weave_surface_export_count++;
    weave_surface_exports[index].module_index = weave_surface_current_module;
    weave_surface_exports[index].name = name;
    weave_surface_exports[index].name_length = length;
    return 0;
}

int32_t weave_surface_module_add_import(
    const char *source,
    int64_t module_start,
    int64_t module_length,
    int64_t symbol_start,
    int64_t symbol_length) {
    if (weave_surface_current_module < 0 ||
        weave_surface_import_count >= WEAVEC_SURFACE_MAX_IMPORTS) {
        return -1;
    }
    for (int32_t index = 0; index < weave_surface_import_count; ++index) {
        weave_surface_import *existing = &weave_surface_imports[index];
        if (existing->owner_module_index != weave_surface_current_module ||
            !weave_surface_slice_equal(
                existing->symbol_name,
                existing->symbol_name_length,
                source,
                symbol_start,
                symbol_length)) {
            continue;
        }
        if (weave_surface_slice_equal(
                existing->module_name,
                existing->module_name_length,
                source,
                module_start,
                module_length)) {
            return -2;
        }
        return -3;
    }
    char *module_name = weave_surface_copy_slice(
        source, module_start, module_length);
    char *symbol_name = weave_surface_copy_slice(
        source, symbol_start, symbol_length);
    if (module_name == NULL || symbol_name == NULL) {
        free(module_name);
        free(symbol_name);
        return -1;
    }
    int32_t index = weave_surface_import_count++;
    weave_surface_imports[index].owner_module_index =
        weave_surface_current_module;
    weave_surface_imports[index].module_name = module_name;
    weave_surface_imports[index].module_name_length = module_length;
    weave_surface_imports[index].symbol_name = symbol_name;
    weave_surface_imports[index].symbol_name_length = symbol_length;
    return 0;
}

int32_t weave_surface_module_export_status(
    const char *source,
    int64_t start,
    int64_t length) {
    if (weave_surface_current_module < 0) {
        return -1;
    }
    return weave_surface_symbol_find_in_module_slice(
        weave_surface_current_module, source, start, length) >= 0 ? 0 : -1;
}

int32_t weave_surface_module_import_status(
    const char *source,
    int64_t module_start,
    int64_t module_length,
    int64_t symbol_start,
    int64_t symbol_length) {
    int32_t target = weave_surface_module_find_slice(
        source, module_start, module_length);
    if (target < 0) {
        return -1;
    }
    if (weave_surface_symbol_find_in_module_slice(
            target, source, symbol_start, symbol_length) < 0) {
        return -2;
    }
    if (!weave_surface_export_matches(
            target, source, symbol_start, symbol_length)) {
        return -3;
    }
    return 0;
}

static int weave_surface_module_reaches(
    int32_t from,
    int32_t target,
    unsigned char *visiting) {
    if (from < 0 || from >= weave_surface_module_count) {
        return 0;
    }
    if (visiting[from]) {
        return 0;
    }
    visiting[from] = 1;
    for (int32_t index = 0; index < weave_surface_import_count; ++index) {
        weave_surface_import *item = &weave_surface_imports[index];
        if (item->owner_module_index != from) {
            continue;
        }
        int32_t next = weave_surface_module_find_stored(
            item->module_name, item->module_name_length);
        if (next < 0) {
            continue;
        }
        if (next == target ||
            weave_surface_module_reaches(next, target, visiting)) {
            visiting[from] = 0;
            return 1;
        }
    }
    visiting[from] = 0;
    return 0;
}

int32_t weave_surface_module_current_has_cycle(void) {
    if (weave_surface_current_module < 0) {
        return 0;
    }
    unsigned char visiting[WEAVEC_SURFACE_MAX_MODULES] = {0};
    return weave_surface_module_reaches(
        weave_surface_current_module,
        weave_surface_current_module,
        visiting);
}

const char *weave_surface_module_current_name(void) {
    if (weave_surface_current_module < 0 ||
        weave_surface_current_module >= weave_surface_module_count) {
        return NULL;
    }
    return weave_surface_modules[weave_surface_current_module].name;
}

int32_t weave_surface_symbol_begin(
    const char *source,
    int64_t start,
    int64_t length,
    int32_t return_type) {
    if (return_type <= 0 ||
        weave_surface_symbol_count >= WEAVEC_SURFACE_MAX_SYMBOLS) {
        return -1;
    }
    if (weave_surface_module_mode == WEAVEC_SURFACE_MODULE_MODE_UNSET) {
        weave_surface_module_mode = WEAVEC_SURFACE_MODULE_MODE_LEGACY;
        weave_surface_current_module = -1;
    }
    /* Until deterministic WIR name mangling lands, emitted names must remain
       globally unique even though lookup is module-scoped. */
    for (int32_t index = 0; index < weave_surface_symbol_count; ++index) {
        if (weave_surface_slice_equal(
                weave_surface_symbols[index].name,
                weave_surface_symbols[index].name_length,
                source,
                start,
                length)) {
            return -2;
        }
    }
    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    int32_t index = weave_surface_symbol_count++;
    weave_surface_symbols[index].name = name;
    weave_surface_symbols[index].name_length = length;
    weave_surface_symbols[index].return_type = return_type;
    weave_surface_symbols[index].parameter_count = 0;
    weave_surface_symbols[index].type_param_count = 0;
    weave_surface_symbols[index].module_index = weave_surface_current_module;
    weave_surface_symbols[index].source_path = NULL;
    if (weave_surface_current_source_path != NULL) {
        size_t path_len = strlen(weave_surface_current_source_path);
        weave_surface_symbols[index].source_path =
            weave_surface_copy_slice(
                weave_surface_current_source_path, 0, (int64_t)path_len);
    }
    weave_surface_symbol_being_built = index;
    return index;
}

int32_t weave_surface_symbol_add_parameter(int32_t type) {
    if (weave_surface_symbol_being_built < 0 || type <= 0) {
        return -1;
    }
    weave_surface_symbol *symbol =
        &weave_surface_symbols[weave_surface_symbol_being_built];
    if (symbol->parameter_count >= WEAVEC_SURFACE_MAX_PARAMS) {
        return -1;
    }
    symbol->parameter_types[symbol->parameter_count++] = type;
    return 0;
}

static int32_t weave_surface_symbol_resolve(
    const char *source,
    int64_t start,
    int64_t length) {
    weave_surface_resolution_status = WEAVEC_SURFACE_RESOLUTION_OK;
    if (weave_surface_module_mode != WEAVEC_SURFACE_MODULE_MODE_EXPLICIT) {
        int32_t index = weave_surface_symbol_find_in_module_slice(
            -1, source, start, length);
        if (index < 0) {
            weave_surface_resolution_status = WEAVEC_SURFACE_RESOLUTION_MISSING;
        }
        return index;
    }

    int32_t local = weave_surface_symbol_find_in_module_slice(
        weave_surface_current_module, source, start, length);
    if (local >= 0) {
        return local;
    }

    int32_t resolved = -1;
    for (int32_t index = 0; index < weave_surface_import_count; ++index) {
        weave_surface_import *item = &weave_surface_imports[index];
        if (item->owner_module_index != weave_surface_current_module ||
            !weave_surface_slice_equal(
                item->symbol_name,
                item->symbol_name_length,
                source,
                start,
                length)) {
            continue;
        }
        int32_t target = weave_surface_module_find_stored(
            item->module_name, item->module_name_length);
        if (target < 0 || !weave_surface_export_matches_stored(
                target, item->symbol_name, item->symbol_name_length)) {
            continue;
        }
        int32_t candidate = weave_surface_symbol_find_in_module_stored(
            target, item->symbol_name, item->symbol_name_length);
        if (candidate < 0) {
            continue;
        }
        if (resolved >= 0 && resolved != candidate) {
            weave_surface_resolution_status =
                WEAVEC_SURFACE_RESOLUTION_AMBIGUOUS;
            return -1;
        }
        resolved = candidate;
    }
    if (resolved >= 0) {
        return resolved;
    }

    int exported_elsewhere = 0;
    int private_elsewhere = 0;
    for (int32_t index = 0; index < weave_surface_symbol_count; ++index) {
        weave_surface_symbol *symbol = &weave_surface_symbols[index];
        if (symbol->module_index == weave_surface_current_module ||
            !weave_surface_slice_equal(
                symbol->name,
                symbol->name_length,
                source,
                start,
                length)) {
            continue;
        }
        if (weave_surface_export_matches_stored(
                symbol->module_index, symbol->name, symbol->name_length)) {
            exported_elsewhere = 1;
        } else {
            private_elsewhere = 1;
        }
    }
    if (exported_elsewhere) {
        weave_surface_resolution_status =
            WEAVEC_SURFACE_RESOLUTION_NOT_IMPORTED;
    } else if (private_elsewhere) {
        weave_surface_resolution_status = WEAVEC_SURFACE_RESOLUTION_PRIVATE;
    } else {
        weave_surface_resolution_status = WEAVEC_SURFACE_RESOLUTION_MISSING;
    }
    return -1;
}

int32_t weave_surface_symbol_resolution_status(void) {
    return weave_surface_resolution_status;
}

int32_t weave_surface_symbol_return_type(
    const char *source,
    int64_t start,
    int64_t length) {
    int32_t index = weave_surface_symbol_resolve(source, start, length);
    return index < 0 ? 0 : weave_surface_symbols[index].return_type;
}

int32_t weave_surface_symbol_parameter_count(
    const char *source,
    int64_t start,
    int64_t length) {
    int32_t index = weave_surface_symbol_resolve(source, start, length);
    return index < 0 ? -1 : weave_surface_symbols[index].parameter_count;
}

int32_t weave_surface_symbol_parameter_type(
    const char *source,
    int64_t start,
    int64_t length,
    int32_t parameter_index) {
    int32_t index = weave_surface_symbol_resolve(source, start, length);
    if (index < 0 || parameter_index < 0 ||
        parameter_index >= weave_surface_symbols[index].parameter_count) {
        return 0;
    }
    return weave_surface_symbols[index].parameter_types[parameter_index];
}

void weave_surface_locals_reset(void) {
    for (int32_t index = 0; index < weave_surface_local_count; ++index) {
        free(weave_surface_locals[index].name);
        weave_surface_locals[index].name = NULL;
    }
    weave_surface_local_count = 0;
    weave_surface_match_temp = 0;
    weave_surface_return_type = 0;
}

int32_t weave_surface_local_count_get(void) {
    return weave_surface_local_count;
}

int32_t weave_surface_local_push(
    const char *source,
    int64_t start,
    int64_t length,
    int32_t type) {
    if (type <= 0 || weave_surface_local_count >= WEAVEC_SURFACE_MAX_LOCALS) {
        return -1;
    }
    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    int32_t index = weave_surface_local_count++;
    weave_surface_locals[index].name = name;
    weave_surface_locals[index].name_length = length;
    weave_surface_locals[index].type = type;
    return 0;
}

void weave_surface_local_truncate(int32_t count) {
    if (count < 0) {
        count = 0;
    }
    if (count > weave_surface_local_count) {
        return;
    }
    for (int32_t index = count; index < weave_surface_local_count; ++index) {
        free(weave_surface_locals[index].name);
        weave_surface_locals[index].name = NULL;
    }
    weave_surface_local_count = count;
}

int32_t weave_surface_local_add(
    const char *source,
    int64_t start,
    int64_t length,
    int32_t type) {
    if (type <= 0 || weave_surface_local_count >= WEAVEC_SURFACE_MAX_LOCALS) {
        return -1;
    }
    for (int32_t index = 0; index < weave_surface_local_count; ++index) {
        if (weave_surface_slice_equal(
                weave_surface_locals[index].name,
                weave_surface_locals[index].name_length,
                source,
                start,
                length)) {
            weave_surface_locals[index].type = type;
            return 0;
        }
    }
    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    int32_t index = weave_surface_local_count++;
    weave_surface_locals[index].name = name;
    weave_surface_locals[index].name_length = length;
    weave_surface_locals[index].type = type;
    return 0;
}

int32_t weave_surface_local_type(
    const char *source,
    int64_t start,
    int64_t length) {
    for (int32_t index = weave_surface_local_count - 1; index >= 0; --index) {
        if (weave_surface_slice_equal(
                weave_surface_locals[index].name,
                weave_surface_locals[index].name_length,
                source,
                start,
                length)) {
            return weave_surface_locals[index].type;
        }
    }
    return 0;
}

int32_t weave_surface_struct_type_or_declare(
    const char *source,
    int64_t start,
    int64_t length) {
    int32_t index = weave_surface_struct_find(source, start, length);
    if (index < 0) {
        index = weave_surface_struct_allocate(source, start, length);
    }
    return index < 0 ? 0 : WEAVEC_SURFACE_STRUCT_TYPE_BASE + index;
}

int32_t weave_surface_struct_define(
    const char *source,
    int64_t start,
    int64_t length) {
    int32_t index = weave_surface_struct_find(source, start, length);
    if (index < 0) {
        index = weave_surface_struct_allocate(source, start, length);
        if (index < 0) {
            return -1;
        }
    } else if (weave_surface_structs[index].defined) {
        return -2;
    }
    weave_surface_structs[index].defined = 1;
    weave_surface_structs[index].field_count = 0;
    weave_surface_structs[index].type_param_count = 0;
    return WEAVEC_SURFACE_STRUCT_TYPE_BASE + index;
}

int32_t weave_surface_struct_add_field(
    int32_t struct_type,
    const char *source,
    int64_t start,
    int64_t length,
    int32_t field_type) {
    int32_t index = weave_surface_struct_index_from_type(struct_type);
    if (index < 0 || !weave_surface_structs[index].defined || field_type <= 0) {
        return -1;
    }
    weave_surface_struct *structure = &weave_surface_structs[index];
    if (structure->field_count >= WEAVEC_SURFACE_MAX_STRUCT_FIELDS) {
        return -1;
    }
    for (int32_t field = 0; field < structure->field_count; ++field) {
        if (weave_surface_slice_equal(
                structure->fields[field].name,
                structure->fields[field].name_length,
                source,
                start,
                length)) {
            return -2;
        }
    }
    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    int32_t field = structure->field_count++;
    structure->fields[field].name = name;
    structure->fields[field].name_length = length;
    structure->fields[field].type = field_type;
    return field;
}

int32_t weave_surface_struct_is_type(int32_t type) {
    return weave_surface_struct_index_from_type(type) >= 0;
}

int32_t weave_surface_struct_is_defined(int32_t type) {
    int32_t index = weave_surface_struct_index_from_type(type);
    return index >= 0 && weave_surface_structs[index].defined;
}

const char *weave_surface_struct_name(int32_t type) {
    int32_t index = weave_surface_struct_index_from_type(type);
    return index < 0 ? NULL : weave_surface_structs[index].name;
}

int32_t weave_surface_struct_field_count(int32_t type) {
    int32_t index = weave_surface_struct_index_from_type(type);
    if (index < 0 || !weave_surface_structs[index].defined) {
        return -1;
    }
    return weave_surface_structs[index].field_count;
}

int32_t weave_surface_struct_field_type(int32_t type, int32_t field_index) {
    int32_t index = weave_surface_struct_index_from_type(type);
    if (index < 0 || !weave_surface_structs[index].defined || field_index < 0 ||
        field_index >= weave_surface_structs[index].field_count) {
        return 0;
    }
    return weave_surface_structs[index].fields[field_index].type;
}

const char *weave_surface_struct_field_name(
    int32_t type,
    int32_t field_index) {
    int32_t index = weave_surface_struct_index_from_type(type);
    if (index < 0 || !weave_surface_structs[index].defined || field_index < 0 ||
        field_index >= weave_surface_structs[index].field_count) {
        return NULL;
    }
    return weave_surface_structs[index].fields[field_index].name;
}

int32_t weave_surface_struct_find_field(
    int32_t type,
    const char *source,
    int64_t start,
    int64_t length) {
    int32_t index = weave_surface_struct_index_from_type(type);
    if (index < 0 || !weave_surface_structs[index].defined) {
        return -1;
    }
    weave_surface_struct *structure = &weave_surface_structs[index];
    for (int32_t field = 0; field < structure->field_count; ++field) {
        if (weave_surface_slice_equal(
                structure->fields[field].name,
                structure->fields[field].name_length,
                source,
                start,
                length)) {
            return field;
        }
    }
    return -1;
}

void weave_surface_set_return_type(int32_t type) {
    weave_surface_return_type = type;
}

int32_t weave_surface_get_return_type(void) {
    return weave_surface_return_type;
}

void weave_surface_set_error(void) {
    weave_surface_error = 1;
}

int32_t weave_surface_has_error(void) {
    return weave_surface_error;
}

void weave_surface_type_params_reset(void) {
    for (int32_t index = 0; index < weave_surface_type_param_count; ++index) {
        free(weave_surface_type_params[index].name);
        weave_surface_type_params[index].name = NULL;
    }
    weave_surface_type_param_count = 0;
}

int32_t weave_surface_type_param_push(
    const char *source,
    int64_t start,
    int64_t length,
    int32_t type,
    int32_t ordinal) {
    if (type <= 0 ||
        weave_surface_type_param_count >= WEAVEC_SURFACE_MAX_TYPE_PARAMS) {
        return -1;
    }
    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    int32_t index = weave_surface_type_param_count++;
    weave_surface_type_params[index].name = name;
    weave_surface_type_params[index].name_length = length;
    weave_surface_type_params[index].type = type;
    weave_surface_type_params[index].ordinal = ordinal;
    return index;
}

int32_t weave_surface_type_param_lookup(
    const char *source,
    int64_t start,
    int64_t length) {
    for (int32_t index = 0; index < weave_surface_type_param_count; ++index) {
        if (weave_surface_slice_equal(
                weave_surface_type_params[index].name,
                weave_surface_type_params[index].name_length,
                source,
                start,
                length)) {
            return weave_surface_type_params[index].type;
        }
    }
    return 0;
}

int32_t weave_surface_type_param_count_current(void) {
    return weave_surface_type_param_count;
}

int32_t weave_surface_symbol_set_type_param_count(int32_t count) {
    if (weave_surface_symbol_being_built < 0 ||
        count < 0 ||
        count > WEAVEC_SURFACE_MAX_TYPE_PARAMS) {
        return -1;
    }
    weave_surface_symbol *symbol =
        &weave_surface_symbols[weave_surface_symbol_being_built];
    symbol->type_param_count = count;
    for (int32_t index = 0; index < count; ++index) {
        symbol->type_param_types[index] =
            weave_surface_type_params[index].type;
    }
    return 0;
}

int32_t weave_surface_symbol_type_param_count(
    const char *source,
    int64_t start,
    int64_t length) {
    int32_t index = weave_surface_symbol_resolve(source, start, length);
    if (index < 0) {
        return 0;
    }
    return weave_surface_symbols[index].type_param_count;
}

int32_t weave_surface_struct_set_type_param_count_storage(
    int32_t flat_type,
    int32_t count) {
    int32_t index = weave_surface_struct_index_from_type(flat_type);
    if (index < 0 || count < 0 || count > WEAVEC_SURFACE_MAX_TYPE_PARAMS) {
        return -1;
    }
    weave_surface_structs[index].type_param_count = count;
    return 0;
}

int32_t weave_surface_struct_type_param_count_storage(int32_t flat_type) {
    int32_t index = weave_surface_struct_index_from_type(flat_type);
    if (index < 0) {
        return 0;
    }
    return weave_surface_structs[index].type_param_count;
}

void weave_surface_set_current_source_path(const char *path) {
    weave_surface_current_source_path = (char *)path;
}

const char *weave_surface_get_current_source_path(void) {
    return weave_surface_current_source_path;
}

int32_t weave_surface_symbol_type_param_type(
    const char *source,
    int64_t start,
    int64_t length,
    int32_t parameter_index) {
    int32_t index = weave_surface_symbol_resolve(source, start, length);
    if (index < 0 ||
        parameter_index < 0 ||
        parameter_index >= weave_surface_symbols[index].type_param_count) {
        return 0;
    }
    return weave_surface_symbols[index].type_param_types[parameter_index];
}

const char *weave_surface_symbol_source_path(
    const char *source,
    int64_t start,
    int64_t length) {
    int32_t index = weave_surface_symbol_resolve(source, start, length);
    if (index < 0) {
        return NULL;
    }
    return weave_surface_symbols[index].source_path;
}

int32_t weave_surface_spec_count(void) {
    return weave_surface_n_specs;
}

int32_t weave_surface_spec_intern(
    const char *source,
    int64_t start,
    int64_t length,
    const char *key,
    const char *spec_name) {
    if (source == NULL || start < 0 || length <= 0 ||
        key == NULL || spec_name == NULL) {
        return -1;
    }
    for (int32_t index = 0; index < weave_surface_n_specs; ++index) {
        if (weave_surface_slice_equal(
                weave_surface_specs[index].generic_name,
                weave_surface_specs[index].generic_name_length,
                source,
                start,
                length) &&
            strcmp(weave_surface_specs[index].key, key) == 0) {
            return index;
        }
    }
    if (weave_surface_n_specs >= WEAVEC_SURFACE_MAX_SPECS) {
        return -2;
    }
    char *generic_name = weave_surface_copy_slice(source, start, length);
    char *key_copy = weave_surface_copy_slice(key, 0, (int64_t)strlen(key));
    char *name_copy =
        weave_surface_copy_slice(spec_name, 0, (int64_t)strlen(spec_name));
    if (generic_name == NULL || key_copy == NULL || name_copy == NULL) {
        free(generic_name);
        free(key_copy);
        free(name_copy);
        return -1;
    }
    int32_t index = weave_surface_n_specs++;
    weave_surface_specs[index].generic_name = generic_name;
    weave_surface_specs[index].generic_name_length = length;
    weave_surface_specs[index].key = key_copy;
    weave_surface_specs[index].spec_name = name_copy;
    weave_surface_specs[index].source_path = NULL;
    weave_surface_specs[index].arg_count = 0;
    weave_surface_specs[index].emitted = 0;
    const char *path = weave_surface_symbol_source_path(source, start, length);
    if (path == NULL) {
        path = weave_surface_current_source_path;
    }
    if (path != NULL) {
        weave_surface_specs[index].source_path =
            weave_surface_copy_slice(path, 0, (int64_t)strlen(path));
    }
    return index;
}

const char *weave_surface_spec_name(int32_t index) {
    if (index < 0 || index >= weave_surface_n_specs) {
        return NULL;
    }
    return weave_surface_specs[index].spec_name;
}

const char *weave_surface_spec_generic_name(int32_t index) {
    if (index < 0 || index >= weave_surface_n_specs) {
        return NULL;
    }
    return weave_surface_specs[index].generic_name;
}

const char *weave_surface_spec_source_path(int32_t index) {
    if (index < 0 || index >= weave_surface_n_specs) {
        return NULL;
    }
    return weave_surface_specs[index].source_path;
}

int32_t weave_surface_spec_emitted(int32_t index) {
    if (index < 0 || index >= weave_surface_n_specs) {
        return 1;
    }
    return weave_surface_specs[index].emitted;
}

void weave_surface_spec_mark_emitted(int32_t index) {
    if (index < 0 || index >= weave_surface_n_specs) {
        return;
    }
    weave_surface_specs[index].emitted = 1;
}

int32_t weave_surface_spec_set_args(
    int32_t index,
    const int32_t *args,
    int32_t count) {
    if (index < 0 || index >= weave_surface_n_specs ||
        args == NULL || count < 0 ||
        count > WEAVEC_SURFACE_MAX_TYPE_PARAMS) {
        return -1;
    }
    weave_surface_specs[index].arg_count = count;
    for (int32_t arg = 0; arg < count; ++arg) {
        weave_surface_specs[index].arg_types[arg] = args[arg];
    }
    return 0;
}

int32_t weave_surface_spec_arg_count(int32_t index) {
    if (index < 0 || index >= weave_surface_n_specs) {
        return 0;
    }
    return weave_surface_specs[index].arg_count;
}

int32_t weave_surface_spec_arg_type(int32_t index, int32_t arg_index) {
    if (index < 0 || index >= weave_surface_n_specs ||
        arg_index < 0 ||
        arg_index >= weave_surface_specs[index].arg_count) {
        return 0;
    }
    return weave_surface_specs[index].arg_types[arg_index];
}

static int32_t weave_surface_enum_find(
    const char *source,
    int64_t start,
    int64_t length) {
    for (int32_t index = 0; index < weave_surface_n_enums; ++index) {
        if (weave_surface_slice_equal(
                weave_surface_enums[index].name,
                weave_surface_enums[index].name_length,
                source,
                start,
                length)) {
            return index;
        }
    }
    return -1;
}

int32_t weave_surface_enum_define(
    const char *source,
    int64_t start,
    int64_t length) {
    if (source == NULL || start < 0 || length <= 0) {
        return -1;
    }
    if (weave_surface_enum_find(source, start, length) >= 0) {
        return -2;
    }
    if (weave_surface_n_enums >= WEAVEC_SURFACE_MAX_ENUMS) {
        return -1;
    }
    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    int32_t index = weave_surface_n_enums++;
    weave_surface_enums[index].name = name;
    weave_surface_enums[index].name_length = length;
    weave_surface_enums[index].defined = 1;
    weave_surface_enums[index].variant_count = 0;
    weave_surface_enums[index].type_param_count = 0;
    weave_surface_enums[index].graph_type = 0;
    weave_surface_enums[index].source_path = NULL;
    if (weave_surface_current_source_path != NULL) {
        size_t path_len = strlen(weave_surface_current_source_path);
        weave_surface_enums[index].source_path =
            weave_surface_copy_slice(
                weave_surface_current_source_path, 0, (int64_t)path_len);
    }
    return index;
}

int32_t weave_surface_enum_set_graph_type(int32_t index, int32_t graph_type) {
    if (index < 0 || index >= weave_surface_n_enums || graph_type <= 0) {
        return -1;
    }
    weave_surface_enums[index].graph_type = graph_type;
    return 0;
}

int32_t weave_surface_enum_set_type_param_count(int32_t index, int32_t count) {
    if (index < 0 || index >= weave_surface_n_enums ||
        count < 0 || count > WEAVEC_SURFACE_MAX_TYPE_PARAMS) {
        return -1;
    }
    weave_surface_enums[index].type_param_count = count;
    return 0;
}

int32_t weave_surface_enum_add_variant(
    int32_t index,
    const char *source,
    int64_t start,
    int64_t length,
    int32_t payload_type) {
    if (index < 0 || index >= weave_surface_n_enums ||
        source == NULL || start < 0 || length <= 0 ||
        weave_surface_enums[index].variant_count >=
            WEAVEC_SURFACE_MAX_VARIANTS) {
        return -1;
    }
    weave_surface_enum *item = &weave_surface_enums[index];
    for (int32_t variant = 0; variant < item->variant_count; ++variant) {
        if (weave_surface_slice_equal(
                item->variants[variant].name,
                item->variants[variant].name_length,
                source,
                start,
                length)) {
            return -2;
        }
    }
    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    int32_t tag = item->variant_count;
    item->variants[tag].name = name;
    item->variants[tag].name_length = length;
    item->variants[tag].payload_type = payload_type;
    item->variants[tag].tag = tag;
    item->variant_count += 1;
    return tag;
}

int32_t weave_surface_enum_index(
    const char *source,
    int64_t start,
    int64_t length) {
    return weave_surface_enum_find(source, start, length);
}

int32_t weave_surface_enum_lookup(
    const char *source,
    int64_t start,
    int64_t length) {
    int32_t index = weave_surface_enum_find(source, start, length);
    if (index < 0) {
        return 0;
    }
    return weave_surface_enums[index].graph_type;
}

int32_t weave_surface_enum_is_type(int32_t graph_type) {
    if (graph_type <= 0) {
        return 0;
    }
    for (int32_t index = 0; index < weave_surface_n_enums; ++index) {
        if (weave_surface_enums[index].graph_type == graph_type) {
            return 1;
        }
    }
    return 0;
}

int32_t weave_surface_enum_from_type(int32_t graph_type) {
    if (graph_type <= 0) {
        return -1;
    }
    for (int32_t index = 0; index < weave_surface_n_enums; ++index) {
        if (weave_surface_enums[index].graph_type == graph_type) {
            return index;
        }
    }
    return -1;
}

const char *weave_surface_enum_name(int32_t index) {
    if (index < 0 || index >= weave_surface_n_enums) {
        return NULL;
    }
    return weave_surface_enums[index].name;
}

const char *weave_surface_enum_source_path(int32_t index) {
    if (index < 0 || index >= weave_surface_n_enums) {
        return NULL;
    }
    return weave_surface_enums[index].source_path;
}

int32_t weave_surface_enum_type_param_count(int32_t index) {
    if (index < 0 || index >= weave_surface_n_enums) {
        return 0;
    }
    return weave_surface_enums[index].type_param_count;
}

int32_t weave_surface_enum_variant_count(int32_t index) {
    if (index < 0 || index >= weave_surface_n_enums) {
        return 0;
    }
    return weave_surface_enums[index].variant_count;
}

int32_t weave_surface_enum_find_variant(
    int32_t index,
    const char *source,
    int64_t start,
    int64_t length) {
    if (index < 0 || index >= weave_surface_n_enums) {
        return -1;
    }
    weave_surface_enum *item = &weave_surface_enums[index];
    for (int32_t variant = 0; variant < item->variant_count; ++variant) {
        if (weave_surface_slice_equal(
                item->variants[variant].name,
                item->variants[variant].name_length,
                source,
                start,
                length)) {
            return variant;
        }
    }
    return -1;
}

int32_t weave_surface_enum_variant_tag(int32_t index, int32_t variant) {
    if (index < 0 || index >= weave_surface_n_enums ||
        variant < 0 ||
        variant >= weave_surface_enums[index].variant_count) {
        return -1;
    }
    return weave_surface_enums[index].variants[variant].tag;
}

int32_t weave_surface_enum_variant_payload(int32_t index, int32_t variant) {
    if (index < 0 || index >= weave_surface_n_enums ||
        variant < 0 ||
        variant >= weave_surface_enums[index].variant_count) {
        return 0;
    }
    return weave_surface_enums[index].variants[variant].payload_type;
}

const char *weave_surface_enum_variant_name(int32_t index, int32_t variant) {
    if (index < 0 || index >= weave_surface_n_enums ||
        variant < 0 ||
        variant >= weave_surface_enums[index].variant_count) {
        return NULL;
    }
    return weave_surface_enums[index].variants[variant].name;
}

int32_t weave_surface_enum_spec_count(void) {
    return weave_surface_n_enum_specs;
}

int32_t weave_surface_enum_spec_intern(
    const char *source,
    int64_t start,
    int64_t length,
    const char *key,
    const char *spec_name) {
    if (source == NULL || start < 0 || length <= 0 ||
        key == NULL || spec_name == NULL) {
        return -1;
    }
    for (int32_t index = 0; index < weave_surface_n_enum_specs; ++index) {
        if (weave_surface_slice_equal(
                weave_surface_enum_specs[index].generic_name,
                weave_surface_enum_specs[index].generic_name_length,
                source,
                start,
                length) &&
            strcmp(weave_surface_enum_specs[index].key, key) == 0) {
            return index;
        }
    }
    if (weave_surface_n_enum_specs >= WEAVEC_SURFACE_MAX_ENUM_SPECS) {
        return -2;
    }
    char *generic_name = weave_surface_copy_slice(source, start, length);
    char *key_copy = weave_surface_copy_slice(key, 0, (int64_t)strlen(key));
    char *name_copy =
        weave_surface_copy_slice(spec_name, 0, (int64_t)strlen(spec_name));
    if (generic_name == NULL || key_copy == NULL || name_copy == NULL) {
        free(generic_name);
        free(key_copy);
        free(name_copy);
        return -1;
    }
    int32_t index = weave_surface_n_enum_specs++;
    weave_surface_enum_specs[index].generic_name = generic_name;
    weave_surface_enum_specs[index].generic_name_length = length;
    weave_surface_enum_specs[index].key = key_copy;
    weave_surface_enum_specs[index].spec_name = name_copy;
    weave_surface_enum_specs[index].source_path = NULL;
    weave_surface_enum_specs[index].arg_count = 0;
    weave_surface_enum_specs[index].emitted = 0;
    int32_t enum_index = weave_surface_enum_find(source, start, length);
    const char *path = NULL;
    if (enum_index >= 0) {
        path = weave_surface_enums[enum_index].source_path;
    }
    if (path == NULL) {
        path = weave_surface_current_source_path;
    }
    if (path != NULL) {
        weave_surface_enum_specs[index].source_path =
            weave_surface_copy_slice(path, 0, (int64_t)strlen(path));
    }
    return index;
}

const char *weave_surface_enum_spec_name(int32_t index) {
    if (index < 0 || index >= weave_surface_n_enum_specs) {
        return NULL;
    }
    return weave_surface_enum_specs[index].spec_name;
}

const char *weave_surface_enum_spec_generic_name(int32_t index) {
    if (index < 0 || index >= weave_surface_n_enum_specs) {
        return NULL;
    }
    return weave_surface_enum_specs[index].generic_name;
}

const char *weave_surface_enum_spec_source_path(int32_t index) {
    if (index < 0 || index >= weave_surface_n_enum_specs) {
        return NULL;
    }
    return weave_surface_enum_specs[index].source_path;
}

int32_t weave_surface_enum_spec_emitted(int32_t index) {
    if (index < 0 || index >= weave_surface_n_enum_specs) {
        return 1;
    }
    return weave_surface_enum_specs[index].emitted;
}

void weave_surface_enum_spec_mark_emitted(int32_t index) {
    if (index < 0 || index >= weave_surface_n_enum_specs) {
        return;
    }
    weave_surface_enum_specs[index].emitted = 1;
}

int32_t weave_surface_enum_spec_set_args(
    int32_t index,
    const int32_t *args,
    int32_t count) {
    if (index < 0 || index >= weave_surface_n_enum_specs ||
        args == NULL || count < 0 ||
        count > WEAVEC_SURFACE_MAX_TYPE_PARAMS) {
        return -1;
    }
    weave_surface_enum_specs[index].arg_count = count;
    for (int32_t arg = 0; arg < count; ++arg) {
        weave_surface_enum_specs[index].arg_types[arg] = args[arg];
    }
    return 0;
}

int32_t weave_surface_enum_spec_arg_count(int32_t index) {
    if (index < 0 || index >= weave_surface_n_enum_specs) {
        return 0;
    }
    return weave_surface_enum_specs[index].arg_count;
}

int32_t weave_surface_enum_spec_arg_type(int32_t index, int32_t arg_index) {
    if (index < 0 || index >= weave_surface_n_enum_specs ||
        arg_index < 0 ||
        arg_index >= weave_surface_enum_specs[index].arg_count) {
        return 0;
    }
    return weave_surface_enum_specs[index].arg_types[arg_index];
}

static void weave_surface_enum_write(int fd, const char *text) {
    if (text == NULL) {
        return;
    }
    write(fd, text, strlen(text));
}

void weave_surface_enum_write_constructor(
    int32_t fd,
    const char *prefix,
    const char *variant_name,
    int32_t tag,
    const char *store_head) {
    char line[256];
    weave_surface_enum_write(fd, "    (fn ");
    weave_surface_enum_write(fd, prefix);
    weave_surface_enum_write(fd, "_new_");
    weave_surface_enum_write(fd, variant_name);
    if (store_head != NULL && store_head[0] != '\0') {
        weave_surface_enum_write(fd, " (params (payload ");
        if (strcmp(store_head, "store_i32") == 0) {
            weave_surface_enum_write(fd, "i32");
        } else if (strcmp(store_head, "store_i64") == 0) {
            weave_surface_enum_write(fd, "i64");
        } else if (strcmp(store_head, "store_f32") == 0) {
            weave_surface_enum_write(fd, "f32");
        } else if (strcmp(store_head, "store_f64") == 0) {
            weave_surface_enum_write(fd, "f64");
        } else if (strcmp(store_head, "store_i8") == 0) {
            weave_surface_enum_write(fd, "bool");
        } else {
            weave_surface_enum_write(fd, "ptr");
        }
        weave_surface_enum_write(fd, ")) (returns ptr) (do\n");
    } else {
        weave_surface_enum_write(
            fd, " (params) (returns ptr) (do\n");
    }
    weave_surface_enum_write(
        fd, "      (let self ptr (call_ptr malloc (const_i64 16)))\n");
    weave_surface_enum_write(
        fd,
        "      (if (condition (eq_ptr (local_get self) (const_null)))\n");
    weave_surface_enum_write(
        fd, "        (then (do (return (const_null))))\n");
    weave_surface_enum_write(fd, "        (else (do)))\n");
    snprintf(line, sizeof(line),
        "      (store_i32 (local_get self) (const_i32 %d))\n", tag);
    weave_surface_enum_write(fd, line);
    if (store_head != NULL && store_head[0] != '\0') {
        weave_surface_enum_write(fd, "      (");
        weave_surface_enum_write(fd, store_head);
        weave_surface_enum_write(
            fd,
            " (ptr_add (local_get self) (const_i64 8)) (param_get payload))\n");
    } else {
        weave_surface_enum_write(
            fd,
            "      (store_i64 (ptr_add (local_get self) (const_i64 8)) (const_i64 0))\n");
    }
    weave_surface_enum_write(fd, "      (return (local_get self)))))\n");
}

void weave_surface_enum_write_tag_fn(int32_t fd, const char *prefix) {
    weave_surface_enum_write(fd, "    (fn ");
    weave_surface_enum_write(fd, prefix);
    weave_surface_enum_write(
        fd,
        "_tag (params (self ptr)) (returns i32) (do (return (load_i32 (param_get self)))))\n");
}

void weave_surface_enum_write_payload_fn(
    int32_t fd,
    const char *prefix,
    const char *variant_name,
    const char *load_head,
    const char *wir_type) {
    if (load_head == NULL || wir_type == NULL) {
        return;
    }
    weave_surface_enum_write(fd, "    (fn ");
    weave_surface_enum_write(fd, prefix);
    weave_surface_enum_write(fd, "_payload_");
    weave_surface_enum_write(fd, variant_name);
    weave_surface_enum_write(fd, " (params (self ptr)) (returns ");
    weave_surface_enum_write(fd, wir_type);
    weave_surface_enum_write(fd, ") (do (return (");
    weave_surface_enum_write(fd, load_head);
    weave_surface_enum_write(
        fd, " (ptr_add (param_get self) (const_i64 8)))))))\n");
}

int32_t weave_surface_match_temp_next(void) {
    return weave_surface_match_temp++;
}

void weave_surface_match_write_temp(int32_t fd, int32_t temp) {
    char line[32];
    snprintf(line, sizeof(line), "__m%d", temp);
    weave_surface_enum_write(fd, line);
}

void weave_surface_match_write_local_get(int32_t fd, int32_t temp) {
    char line[48];
    snprintf(line, sizeof(line), "(local_get __m%d)", temp);
    weave_surface_enum_write(fd, line);
}

void weave_surface_match_write_let_head(int32_t fd, int32_t temp) {
    char line[48];
    snprintf(line, sizeof(line), "(let __m%d ptr ", temp);
    weave_surface_enum_write(fd, line);
}

void weave_surface_match_write_cond(
    int32_t fd,
    const char *prefix,
    int32_t temp,
    int32_t tag) {
    char line[256];
    if (prefix == NULL) {
        prefix = "";
    }
    snprintf(
        line,
        sizeof(line),
        "(eq_i32 (call_i32 %s_tag (local_get __m%d)) (const_i32 %d))",
        prefix,
        temp,
        tag);
    weave_surface_enum_write(fd, line);
}

void weave_surface_match_write_open_if(int32_t fd) {
    weave_surface_enum_write(fd, "(if (condition ");
}

void weave_surface_match_write_then_do(int32_t fd) {
    weave_surface_enum_write(fd, ") (then (do ");
}

void weave_surface_match_write_else_do(int32_t fd) {
    weave_surface_enum_write(fd, ") (else (do ");
}

void weave_surface_match_write_close2(int32_t fd) {
    weave_surface_enum_write(fd, "))");
}

void weave_surface_match_write_close3(int32_t fd) {
    weave_surface_enum_write(fd, ")))");
}

void weave_surface_match_write_dummy(int32_t fd, const char *wir_type) {
    if (wir_type != NULL && strcmp(wir_type, "ptr") == 0) {
        weave_surface_enum_write(fd, "(const_null)");
        return;
    }
    if (wir_type != NULL && strcmp(wir_type, "bool") == 0) {
        weave_surface_enum_write(fd, "(const_bool false)");
        return;
    }
    if (wir_type != NULL && strcmp(wir_type, "i64") == 0) {
        weave_surface_enum_write(fd, "(const_i64 0)");
        return;
    }
    if (wir_type != NULL && strcmp(wir_type, "f32") == 0) {
        weave_surface_enum_write(fd, "(const_f32 0.0)");
        return;
    }
    if (wir_type != NULL && strcmp(wir_type, "f64") == 0) {
        weave_surface_enum_write(fd, "(const_f64 0.0)");
        return;
    }
    weave_surface_enum_write(fd, "(const_i32 0)");
}
