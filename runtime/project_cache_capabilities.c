// SPDX-License-Identifier: Apache-2.0
//
// Add incremental project-build discovery to the compiler-authoritative
// capabilities registry without changing the version-one host format.

#ifndef WEAVEC_PROJECT_CACHE_CAPABILITIES_C
#define WEAVEC_PROJECT_CACHE_CAPABILITIES_C

typedef struct weave_project_cache_capability_document {
    const unsigned char *base;
    size_t base_length;
} weave_project_cache_capability_document;

static int weave_project_cache_publish_capabilities(
    FILE *stream,
    const void *opaque) {
    const weave_project_cache_capability_document *document = opaque;
    size_t length = document->base_length;
    while (length > 0 &&
           (document->base[length - 1] == '\n' ||
            document->base[length - 1] == '\r' ||
            document->base[length - 1] == ' ' ||
            document->base[length - 1] == '\t')) {
        --length;
    }
    if (length == 0 || document->base[length - 1] != '}') return 1;
    --length;
    if (fwrite(document->base, 1, length, stream) != length) return 1;
    return fputs(
        ",\n"
        "  \"incremental_project_builds\": {\n"
        "    \"feature\": {\n"
        "      \"id\": \"incremental-project-builds\",\n"
        "      \"status\": \"experimental\",\n"
        "      \"issue\": 125\n"
        "    },\n"
        "    \"protocol\": \"weavec-project-module-cache-v1\",\n"
        "    \"controls\": [\n"
        "      \"--clean\",\n"
        "      \"--no-cache\",\n"
        "      \"--cache-dir <path>\",\n"
        "      \"--cache-report <path>\"\n"
        "    ],\n"
        "    \"default_cache\": \"<project-root>/.weave/cache\",\n"
        "    \"validation\": \"full-project-before-cache\",\n"
        "    \"invalidation\": \"source-and-import-interface-hashes\",\n"
        "    \"physical_paths_in_keys\": false\n"
        "  }\n"
        "}\n",
        stream) == EOF
        ? 1
        : 0;
}

int weave_rt_print_capabilities(void) {
    FILE *temporary = tmpfile();
    if (temporary == NULL) return 1;
    int saved = dup(STDOUT_FILENO);
    if (saved < 0 || dup2(fileno(temporary), STDOUT_FILENO) < 0) {
        if (saved >= 0) close(saved);
        fclose(temporary);
        return 1;
    }
    int result = weave_rt_print_capabilities_cache_legacy();
    fflush(stdout);
    int restore_failed = dup2(saved, STDOUT_FILENO) < 0;
    close(saved);
    if (result != 0 || restore_failed ||
        fseek(temporary, 0, SEEK_END) != 0) {
        fclose(temporary);
        return 1;
    }
    long end = ftell(temporary);
    if (end < 0 || fseek(temporary, 0, SEEK_SET) != 0) {
        fclose(temporary);
        return 1;
    }
    unsigned char *base = malloc((size_t)end + 1);
    if (base == NULL ||
        fread(base, 1, (size_t)end, temporary) != (size_t)end) {
        free(base);
        fclose(temporary);
        return 1;
    }
    fclose(temporary);
    base[end] = '\0';
    weave_project_cache_capability_document document = {
        .base = base,
        .base_length = (size_t)end,
    };
    int published = weave_project_cache_publish_capabilities(
        stdout, &document);
    free(base);
    return published != 0 || fflush(stdout) != 0 ? 1 : 0;
}

#endif
