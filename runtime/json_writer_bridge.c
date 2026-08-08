// SPDX-License-Identifier: Apache-2.0
//
// Opaque host bridge for the checked JSON byte writer. Public protocol schemas,
// field names, ordering, registry data, and compatibility policy belong to
// surface Weave. This file exposes only serialization mechanics while Weave does
// not yet have a safe owned String/Bytes implementation.

#ifndef WEAVEC_JSON_WRITER_BRIDGE_C
#define WEAVEC_JSON_WRITER_BRIDGE_C

int weave_host_json_object_begin(void *opaque) {
    return weave_json_object_begin((weave_json_writer *)opaque);
}

int weave_host_json_object_end(void *opaque) {
    return weave_json_object_end((weave_json_writer *)opaque);
}

int weave_host_json_array_begin(void *opaque) {
    return weave_json_array_begin((weave_json_writer *)opaque);
}

int weave_host_json_array_end(void *opaque) {
    return weave_json_array_end((weave_json_writer *)opaque);
}

int weave_host_json_key(void *opaque, const char *key) {
    return weave_json_key((weave_json_writer *)opaque, key);
}

int weave_host_json_string(void *opaque, const char *value) {
    return weave_json_string((weave_json_writer *)opaque, value);
}

int weave_host_json_nullable_string(void *opaque, const char *value) {
    return weave_json_nullable_string((weave_json_writer *)opaque, value);
}

int weave_host_json_string_bytes(
    void *opaque,
    const unsigned char *data,
    long long length) {
    if (length < 0) return 0;
    return weave_json_string_bytes(
        (weave_json_writer *)opaque,
        data,
        (size_t)length);
}

int weave_host_json_null(void *opaque) {
    return weave_json_null((weave_json_writer *)opaque);
}

int weave_host_json_i64(void *opaque, long long value) {
    return weave_json_int64((weave_json_writer *)opaque, (int64_t)value);
}

int weave_host_json_u64(void *opaque, long long value) {
    if (value < 0) return 0;
    return weave_json_uint64((weave_json_writer *)opaque, (uint64_t)value);
}

int weave_host_json_bool(void *opaque, int value) {
    static const unsigned char yes[] = "true";
    static const unsigned char no[] = "false";
    return weave_json_trusted_value(
        (weave_json_writer *)opaque,
        value ? yes : no,
        value ? 4 : 5);
}

// Append newline-delimited JSON values produced by this same checked writer.
// The host owns bounded file transport only; the Weave trace protocol decides
// where these values appear in the public document.
int weave_host_json_append_trusted_lines(void *opaque, const char *path) {
    if (path == NULL) return 1;
    FILE *stream = fopen(path, "r");
    if (stream == NULL) return errno == ENOENT ? 1 : 0;

    char *line = NULL;
    size_t capacity = 0;
    ssize_t length;
    int ok = 1;
    while ((length = getline(&line, &capacity, stream)) >= 0) {
        while (length > 0 &&
               (line[length - 1] == '\n' || line[length - 1] == '\r')) {
            --length;
        }
        if (length != 0 &&
            !weave_json_trusted_value(
                (weave_json_writer *)opaque,
                (const unsigned char *)line,
                (size_t)length)) {
            ok = 0;
            break;
        }
    }
    if (ferror(stream)) ok = 0;
    free(line);
    if (fclose(stream) != 0) ok = 0;
    return ok;
}

const char *weave_host_compiler_version(void) {
    return weave_compiler_version;
}

const char *weave_host_default_target(void) {
    return WEAVEC_DEFAULT_TARGET;
}

#endif
