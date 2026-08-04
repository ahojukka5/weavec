// SPDX-License-Identifier: Apache-2.0
//
// The project facade's in-memory JSON transformer uses the conventional C
// return value of zero for success. Adapt that contract to the checked document
// publisher, whose stream callback returns nonzero on success.

#ifndef WEAVEC_PROJECT_PROTOCOL_PUBLISH_C
#define WEAVEC_PROJECT_PROTOCOL_PUBLISH_C

typedef struct weave_project_protocol_publish_request {
    weave_document_stream_writer write;
    const void *context;
} weave_project_protocol_publish_request;

static int weave_project_protocol_publish_stream(
    FILE *stream,
    const void *opaque) {
    const weave_project_protocol_publish_request *request = opaque;
    return request->write(stream, request->context) == 0;
}

static int weave_project_protocol_publish_document(
    const char *destination,
    const char *label,
    mode_t mode,
    weave_document_stream_writer write,
    const void *context) {
    weave_project_protocol_publish_request request = {
        .write = write,
        .context = context,
    };
    return weave_publish_document(
        destination,
        label,
        mode,
        weave_project_protocol_publish_stream,
        &request);
}

#endif
