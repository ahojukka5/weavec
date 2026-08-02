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

static char *weave_surface_mangle_struct_name(
    int32_t module_index,
    const char *name,
    int64_t length) {
    static const char prefix[] = "__weave_m_";
    static const char separator[] = "__t_";
    static const char hex[] = "0123456789abcdef";
    if (module_index < 0 || module_index >= weave_surface_module_count ||
        name == NULL || length <= 0) {
        return NULL;
    }
    const weave_surface_module *module = &weave_surface_modules[module_index];
    if (module->name == NULL || module->name_length <= 0) {
        return NULL;
    }
    uint64_t payload = (uint64_t)module->name_length + (uint64_t)length;
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
    for (int64_t index = 0; index < module->name_length; ++index) {
        unsigned char byte = (unsigned char)module->name[index];
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
    if (!weave_surface_struct_slice_valid(source, start, length)) {
        return 0;
    }
    char *source_name = weave_surface_copy_slice(source, start, length);
    char *wir_name = weave_surface_mangle_struct_name(
        weave_surface_current_module, source + start, length);
    if (source_name == NULL || wir_name == NULL) {
        free(source_name);
        free(wir_name);
        return 0;
    }
    int32_t type = weave_surface_struct_type_or_declare_storage(
        wir_name, 0, (int64_t)strlen(wir_name));
    if (type <= 0) {
        free(source_name);
        free(wir_name);
        return type;
    }
    return weave_surface_struct_install_names(type, source_name, wir_name);
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
