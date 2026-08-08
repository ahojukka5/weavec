// SPDX-License-Identifier: Apache-2.0
//
// Minimal host bridge for raw nominal-struct storage.
//
// Language-level type identity, graph construction, display, compatibility, and
// WIR lowering live in self-hosted Weave. These functions expose only storage
// reset and the module owner needed to construct a nominal identity in Weave.

#ifndef WEAVEC_SEMANTIC_SURFACE_TYPES_C
#define WEAVEC_SEMANTIC_SURFACE_TYPES_C

void weave_surface_symbols_reset_storage_all(void) {
    weave_surface_symbols_reset_flat();
}

const char *weave_surface_struct_owner_flat(
    const char *source,
    int64_t start,
    int64_t length,
    int32_t flat_type) {
    static const char legacy_owner[] = "@legacy";
    if (!weave_surface_struct_is_module_scoped()) {
        return legacy_owner;
    }
    if (weave_surface_current_module < 0 ||
        weave_surface_current_module >= weave_surface_module_count) {
        return NULL;
    }

    int32_t local = weave_surface_struct_lookup_module(
        weave_surface_current_module, source, start, length, 0);
    if (local == flat_type) {
        return weave_surface_modules[weave_surface_current_module].name;
    }

    const weave_surface_import *imported =
        weave_surface_struct_import_binding(source, start, length);
    if (imported != NULL) {
        int32_t imported_type = weave_surface_struct_lookup_stored(
            imported->module_name,
            imported->module_name_length,
            source,
            start,
            length,
            0);
        if (imported_type == flat_type) {
            return imported->module_name;
        }
    }

    return weave_surface_modules[weave_surface_current_module].name;
}

#endif
