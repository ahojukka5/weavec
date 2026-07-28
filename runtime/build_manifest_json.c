// SPDX-License-Identifier: Apache-2.0
//
// Typed serializer for weavec-build-manifest-v1. Build phase orchestration
// supplies the document values; this module owns only schema serialization and
// transactional publication through the shared runtime infrastructure.

#ifndef WEAVEC_BUILD_MANIFEST_JSON_C
#define WEAVEC_BUILD_MANIFEST_JSON_C

typedef struct weave_build_manifest_document {
    const char *status;
    const char *phase;
    const char *target;
    const char *compiler;
    const char *runtime;
    const char *optimizer;
    const char *codegen;
    const char *linker;
    const char *objdump;
    const char *optimization;
    const char *cpu;
    const char *tune_cpu;
    const char *output;
    char **sources;
    int source_count;
} weave_build_manifest_document;

static int weave_build_manifest_serialize(
    weave_json_writer *writer,
    const void *opaque) {
    const weave_build_manifest_document *document = opaque;
    if (!weave_json_object_begin(writer) ||
        !weave_json_key(writer, "format") ||
        !weave_json_string(writer, "weavec-build-manifest-v1") ||
        !weave_json_key(writer, "status") ||
        !weave_json_string(writer, document->status) ||
        !weave_json_key(writer, "phase") ||
        !weave_json_string(writer, document->phase) ||
        !weave_json_key(writer, "target") ||
        !weave_json_string(writer, document->target) ||
        !weave_json_key(writer, "compiler") ||
        !weave_json_string(writer, document->compiler) ||
        !weave_json_key(writer, "runtime") ||
        !weave_json_string(writer, document->runtime) ||
        !weave_json_key(writer, "optimizer") ||
        !weave_json_string(writer, document->optimizer) ||
        !weave_json_key(writer, "codegen") ||
        !weave_json_string(writer, document->codegen) ||
        !weave_json_key(writer, "linker") ||
        !weave_json_string(writer, document->linker) ||
        !weave_json_key(writer, "objdump") ||
        !weave_json_string(writer, document->objdump) ||
        !weave_json_key(writer, "optimization") ||
        !weave_json_object_begin(writer) ||
        !weave_json_key(writer, "level") ||
        !weave_json_string(writer, document->optimization) ||
        !weave_json_key(writer, "cpu") ||
        !weave_json_nullable_string(writer, document->cpu) ||
        !weave_json_key(writer, "tune_cpu") ||
        !weave_json_nullable_string(writer, document->tune_cpu) ||
        !weave_json_object_end(writer) ||
        !weave_json_key(writer, "output") ||
        !weave_json_string(writer, document->output) ||
        !weave_json_key(writer, "sources") ||
        !weave_json_array_begin(writer)) {
        return 1;
    }
    for (int i = 0; i < document->source_count; ++i) {
        if (!weave_json_string(writer, document->sources[i])) {
            return 1;
        }
    }
    return weave_json_array_end(writer) &&
        weave_json_object_end(writer)
        ? 0
        : 1;
}

static int weave_build_manifest_write(
    const char *path,
    const char *status,
    const char *phase,
    const char *target,
    const char *compiler,
    const char *runtime,
    const char *optimizer,
    const char *codegen,
    const char *linker,
    const char *objdump,
    const char *optimization,
    const char *cpu,
    const char *tune_cpu,
    const char *output,
    char **sources,
    int source_count) {
    if (path == NULL) {
        return 0;
    }
    weave_build_manifest_document document = {
        .status = status,
        .phase = phase,
        .target = target,
        .compiler = compiler,
        .runtime = runtime,
        .optimizer = optimizer,
        .codegen = codegen,
        .linker = linker,
        .objdump = objdump,
        .optimization = optimization,
        .cpu = cpu,
        .tune_cpu = tune_cpu,
        .output = output,
        .sources = sources,
        .source_count = source_count,
    };
    return weave_publish_json_document(
        path,
        "build manifest",
        weave_build_manifest_serialize,
        &document);
}

#endif
