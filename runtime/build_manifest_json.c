// SPDX-License-Identifier: Apache-2.0
//
// Native data/publication bridge for weavec-build-manifest-v1. The public
// schema and deterministic field ordering are owned by src/protocol.

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

extern int weave_protocol_build_manifest_serialize(
    void *writer,
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
    int source_count);

static int weave_build_manifest_serialize(
    weave_json_writer *writer,
    const void *opaque) {
    const weave_build_manifest_document *document = opaque;
    return weave_protocol_build_manifest_serialize(
        writer,
        document->status,
        document->phase,
        document->target,
        document->compiler,
        document->runtime,
        document->optimizer,
        document->codegen,
        document->linker,
        document->objdump,
        document->optimization,
        document->cpu,
        document->tune_cpu,
        document->output,
        document->sources,
        document->source_count);
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
