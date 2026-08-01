// SPDX-License-Identifier: Apache-2.0
//
// Deterministic WIR names for compiler-owned module symbols.
//
// This file is included immediately after surface_symbols.c by portable.c. It
// reuses the registry's copied semantic facts instead of parsing Weave or
// inventing a second namespace model in host C.

static char *weave_surface_symbol_wir_names[WEAVEC_SURFACE_MAX_SYMBOLS];
static unsigned char
    weave_surface_symbol_raw_linkage[WEAVEC_SURFACE_MAX_SYMBOLS];

static int weave_surface_name_is_main(const char *name, int64_t length) {
    static const char main_name[] = "main";
    return name != NULL && length == 4 && memcmp(name, main_name, 4) == 0;
}

static int weave_surface_slice_is_main(
    const char *source,
    int64_t start,
    int64_t length) {
    return source != NULL && start >= 0 &&
        weave_surface_name_is_main(source + start, length);
}

static char *weave_surface_mangle_stored_name(
    int32_t module_index,
    const char *name,
    int64_t length) {
    static const char prefix[] = "__weave_m_";
    static const char separator[] = "__s_";
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

static int weave_surface_symbol_has_public_name(int32_t index) {
    const weave_surface_symbol *symbol = &weave_surface_symbols[index];
    if (symbol->module_index < 0 ||
        weave_surface_symbol_raw_linkage[index] != 0 ||
        weave_surface_name_is_main(symbol->name, symbol->name_length)) {
        return 1;
    }
    return weave_surface_export_matches_stored(
        symbol->module_index, symbol->name, symbol->name_length);
}

static int weave_surface_symbol_ensure_mangled(int32_t index) {
    if (weave_surface_symbol_wir_names[index] != NULL) {
        return 0;
    }
    weave_surface_symbol *symbol = &weave_surface_symbols[index];
    char *wir_name = weave_surface_mangle_stored_name(
        symbol->module_index, symbol->name, symbol->name_length);
    if (wir_name == NULL) {
        return -1;
    }
    weave_surface_symbol_wir_names[index] = wir_name;
    return 0;
}

void weave_surface_symbols_reset(void) {
    for (int32_t index = 0; index < WEAVEC_SURFACE_MAX_SYMBOLS; ++index) {
        free(weave_surface_symbol_wir_names[index]);
        weave_surface_symbol_wir_names[index] = NULL;
        weave_surface_symbol_raw_linkage[index] = 0;
    }
    weave_surface_symbols_reset_storage();
}

int32_t weave_surface_symbol_begin(
    const char *source,
    int64_t start,
    int64_t length,
    int32_t return_type) {
    if (return_type <= 0 || source == NULL || start < 0 || length <= 0 ||
        weave_surface_symbol_count >= WEAVEC_SURFACE_MAX_SYMBOLS) {
        return -1;
    }
    if (weave_surface_module_mode == WEAVEC_SURFACE_MODULE_MODE_UNSET) {
        weave_surface_module_mode = WEAVEC_SURFACE_MODULE_MODE_LEGACY;
        weave_surface_current_module = -1;
    }

    int new_public_name =
        weave_surface_module_mode != WEAVEC_SURFACE_MODULE_MODE_EXPLICIT ||
        weave_surface_current_module < 0 ||
        weave_surface_export_matches(
            weave_surface_current_module, source, start, length) ||
        weave_surface_slice_is_main(source, start, length);
    int duplicate_private_name = 0;

    for (int32_t index = 0; index < weave_surface_symbol_count; ++index) {
        if (!weave_surface_slice_equal(
                weave_surface_symbols[index].name,
                weave_surface_symbols[index].name_length,
                source,
                start,
                length)) {
            continue;
        }
        if (weave_surface_symbols[index].module_index ==
            weave_surface_current_module) {
            return -2;
        }
        if (new_public_name || weave_surface_symbol_has_public_name(index)) {
            return -2;
        }
        if (weave_surface_symbol_ensure_mangled(index) != 0) {
            return -1;
        }
        duplicate_private_name = 1;
    }

    char *name = weave_surface_copy_slice(source, start, length);
    if (name == NULL) {
        return -1;
    }
    char *wir_name = NULL;
    if (duplicate_private_name) {
        wir_name = weave_surface_mangle_stored_name(
            weave_surface_current_module, name, length);
        if (wir_name == NULL) {
            free(name);
            return -1;
        }
    }

    int32_t index = weave_surface_symbol_count++;
    free(weave_surface_symbol_wir_names[index]);
    weave_surface_symbol_wir_names[index] = wir_name;
    weave_surface_symbol_raw_linkage[index] = 0;
    weave_surface_symbols[index].name = name;
    weave_surface_symbols[index].name_length = length;
    weave_surface_symbols[index].return_type = return_type;
    weave_surface_symbols[index].parameter_count = 0;
    weave_surface_symbols[index].module_index = weave_surface_current_module;
    weave_surface_symbol_being_built = index;
    return index;
}

int32_t weave_surface_symbol_mark_external(
    const char *source,
    int64_t start,
    int64_t length) {
    int32_t index = weave_surface_symbol_find_in_module_slice(
        weave_surface_current_module, source, start, length);
    if (index < 0) {
        return -1;
    }
    for (int32_t other = 0; other < weave_surface_symbol_count; ++other) {
        if (other == index ||
            !weave_surface_slice_equal(
                weave_surface_symbols[other].name,
                weave_surface_symbols[other].name_length,
                source,
                start,
                length)) {
            continue;
        }
        if (weave_surface_symbol_has_public_name(other)) {
            return -2;
        }
    }
    free(weave_surface_symbol_wir_names[index]);
    weave_surface_symbol_wir_names[index] = NULL;
    weave_surface_symbol_raw_linkage[index] = 1;
    return 0;
}

const char *weave_surface_symbol_wir_name(
    const char *source,
    int64_t start,
    int64_t length) {
    int32_t index = weave_surface_symbol_resolve(source, start, length);
    if (index < 0) {
        return NULL;
    }
    if (weave_surface_symbol_wir_names[index] != NULL) {
        return weave_surface_symbol_wir_names[index];
    }
    return weave_surface_symbols[index].name;
}
