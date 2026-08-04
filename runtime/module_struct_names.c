// SPDX-License-Identifier: Apache-2.0
//
// Module-scoped nominal struct identities and generated helper names.
//
// surface_symbols.c remains syntax-agnostic storage. Explicit modules reach it
// through deterministic internal keys, while diagnostics retain source names
// and legacy programs keep the historical NAME_new/get/set ABI.

static char *
    weave_surface_struct_source_names[WEAVEC_SURFACE_MAX_STRUCTS];
static char *
    weave_surface_struct_wir_names[WEAVEC_SURFACE_MAX_STRUCTS];

static char *weave_surface_mangle_struct_stored(
    const char *module_name,
    int64_t module_length,
    const char *name,
    int64_t length) {
    static const char prefix[] = "__weave_m_";
    static const char separator[] = "__t_";
    static const char hex[] = "0123456789abcdef";
    if (module_name == NULL || module_length <= 0 ||
        name == NULL || length <= 0) {
        return NULL;
    }
    uint64_t payload = (uint64_t)module_length + (uint64_t)length;
    uint64_t fixed = (uint64_t)(sizeof(prefix) - 1) +
        (uint64_t)(sizeof(separator) - 1) + 1;
    if (payload > ((uint64_t)SIZE_MAX - fixed) / 2) {
        return NULL;
    }
    size_t size = (size_t)(fixed + payload * 2);
    char *result = (char *)malloc(size);
    if (result == NULL) {
        return NULL;
    }
    size_t offset = 0;
    memcpy(result + offset, prefix, sizeof(prefix) - 1);
    offset += sizeof(prefix) - 1;
    for (int64_t index = 0; index < module_length; ++index) {
        unsigned char byte = (unsigned char)module_name[index];
        result[offset++] = hex[byte >> 4];
        result[offset++] = hex[byte & 15];
    }
    memcpy(result + offset, separator, sizeof(separator) - 1);
    offset += sizeof(separator) - 1;
    for (int64_t index = 0; index < length; ++index) {
        unsigned char byte = (unsigned char)name[index];
        result[offset++] = hex[byte >> 4];
        result[offset++] = hex[byte & 15];
    }
    result[offset] = '\0';
    return result;
}

static char *weave_surface_mangle_struct_name(
    int32_t module_index,
    const char *name,
    int64_t length) {
    if (module_index < 0 || module_index >= weave_surface_module_count) {
        return NULL;
    }
    const weave_surface_module *module = &weave_surface_modules[module_index];
    return weave_surface_mangle_struct_stored(
        module->name, module->name_length, name, length);
}

static int weave_surface_struct_is_module_scoped(void) {
    return weave_surface_module_mode == WEAVEC_SURFACE_MODULE_MODE_EXPLICIT &&
        weave_surface_current_module >= 0;
}

static int weave_surface_struct_slice_valid(
    const char *source,
    int64_t start,
    int64_t length) {
    return source != NULL && start >= 0 && length > 0;
}

static int32_t weave_surface_struct_install_names(
    int32_t type,
    char *source_name,
    char *wir_name) {
    int32_t index = weave_surface_struct_index_from_type(type);
    if (index < 0) {
        free(source_name);
        free(wir_name);
        return 0;
    }
    if (weave_surface_struct_source_names[index] == NULL) {
        weave_surface_struct_source_names[index] = source_name;
        weave_surface_struct_wir_names[index] = wir_name;
    } else {
        free(source_name);
        free(wir_name);
    }
    return type;
}

static int32_t weave_surface_struct_lookup_stored(
    const char *module_name,
    int64_t module_length,
    const char *source,
    int64_t start,
    int64_t length,
    int declare) {
    if (!weave_surface_struct_slice_valid(source, start, length)) {
        return 0;
    }
    char *source_name = weave_surface_copy_slice(source, start, length);
    char *wir_name = weave_surface_mangle_struct_stored(
        module_name, module_length, source + start, length);
    if (source_name == NULL || wir_name == NULL) {
        free(source_name);
        free(wir_name);
        return 0;
    }
    int32_t index = weave_surface_struct_find(
        wir_name, 0, (int64_t)strlen(wir_name));
    int32_t type = index < 0
        ? 0
        : WEAVEC_SURFACE_STRUCT_TYPE_BASE + index;
    if (type == 0 && declare) {
        type = weave_surface_struct_type_or_declare_storage(
            wir_name, 0, (int64_t)strlen(wir_name));
    }
    if (type <= 0) {
        free(source_name);
        free(wir_name);
        return type;
    }
    return weave_surface_struct_install_names(type, source_name, wir_name);
}

static int32_t weave_surface_struct_lookup_module(
    int32_t module_index,
    const char *source,
    int64_t start,
    int64_t length,
    int declare) {
    if (module_index < 0 || module_index >= weave_surface_module_count) {
        return 0;
    }
    const weave_surface_module *module = &weave_surface_modules[module_index];
    return weave_surface_struct_lookup_stored(
        module->name, module->name_length,
        source, start, length, declare);
}

static const weave_surface_import *weave_surface_struct_import_binding(
    const char *source,
    int64_t start,
    int64_t length) {
    for (int32_t index = 0; index < weave_surface_import_count; ++index) {
        const weave_surface_import *item = &weave_surface_imports[index];
        if (item->owner_module_index == weave_surface_current_module &&
            weave_surface_slice_equal(
                item->symbol_name,
                item->symbol_name_length,
                source,
                start,
                length)) {
            return item;
        }
    }
    return NULL;
}

void weave_surface_symbols_reset(void) {
    for (int32_t index = 0; index < WEAVEC_SURFACE_MAX_STRUCTS; ++index) {
        free(weave_surface_struct_source_names[index]);
        free(weave_surface_struct_wir_names[index]);
        weave_surface_struct_source_names[index] = NULL;
        weave_surface_struct_wir_names[index] = NULL;
    }
    weave_surface_symbols_reset_symbol_names();
}

int32_t weave_surface_struct_type_or_declare(
    const char *source,
    int64_t start,
    int64_t length) {
    if (!weave_surface_struct_is_module_scoped()) {
        return weave_surface_struct_type_or_declare_storage(
            source, start, length);
    }
    int32_t local = weave_surface_struct_lookup_module(
        weave_surface_current_module, source, start, length, 0);
    if (local > 0) {
        return local;
    }
    const weave_surface_import *imported =
        weave_surface_struct_import_binding(source, start, length);
    if (imported != NULL) {
        return weave_surface_struct_lookup_stored(
            imported->module_name,
            imported->module_name_length,
            source,
            start,
            length,
            1);
    }
    return weave_surface_struct_lookup_module(
        weave_surface_current_module, source, start, length, 1);
}

int32_t weave_surface_struct_define(
    const char *source,
    int64_t start,
    int64_t length) {
    if (!weave_surface_struct_is_module_scoped()) {
        return weave_surface_struct_define_storage(source, start, length);
    }
    if (!weave_surface_struct_slice_valid(source, start, length)) {
        return -1;
    }
    char *source_name = weave_surface_copy_slice(source, start, length);
    char *wir_name = weave_surface_mangle_struct_name(
        weave_surface_current_module, source + start, length);
    if (source_name == NULL || wir_name == NULL) {
        free(source_name);
        free(wir_name);
        return -1;
    }
    int32_t type = weave_surface_struct_define_storage(
        wir_name, 0, (int64_t)strlen(wir_name));
    if (type < 0) {
        free(source_name);
        free(wir_name);
        return type;
    }
    return weave_surface_struct_install_names(type, source_name, wir_name);
}

int32_t weave_surface_module_export_status(
    const char *source,
    int64_t start,
    int64_t length) {
    if (weave_surface_module_export_status_storage(
            source, start, length) == 0) {
        return 0;
    }
    int32_t type = weave_surface_struct_lookup_module(
        weave_surface_current_module, source, start, length, 0);
    return type > 0 && weave_surface_struct_is_defined(type) ? 0 : -1;
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
    int32_t symbol = weave_surface_symbol_find_in_module_slice(
        target, source, symbol_start, symbol_length);
    int32_t type = weave_surface_struct_lookup_module(
        target, source, symbol_start, symbol_length, 0);
    int has_type = type > 0 && weave_surface_struct_is_defined(type);
    if (symbol < 0 && !has_type) {
        return -2;
    }
    if (!weave_surface_export_matches(
            target, source, symbol_start, symbol_length)) {
        return -3;
    }
    return 0;
}

const char *weave_surface_struct_name(int32_t type) {
    int32_t index = weave_surface_struct_index_from_type(type);
    if (index < 0) {
        return NULL;
    }
    if (weave_surface_struct_source_names[index] != NULL) {
        return weave_surface_struct_source_names[index];
    }
    return weave_surface_struct_name_storage(type);
}

const char *weave_surface_struct_wir_name(int32_t type) {
    int32_t index = weave_surface_struct_index_from_type(type);
    if (index < 0) {
        return NULL;
    }
    if (weave_surface_struct_wir_names[index] != NULL) {
        return weave_surface_struct_wir_names[index];
    }
    return weave_surface_struct_name_storage(type);
}
