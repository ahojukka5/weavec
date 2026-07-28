// SPDX-License-Identifier: Apache-2.0
//
// Transactional publication for generated documents. Serializers write a
// complete temporary file beside the destination; only a checked, synced file
// is made visible through rename.

#ifndef WEAVEC_DOCUMENT_PUBLISH_C
#define WEAVEC_DOCUMENT_PUBLISH_C

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

typedef int (*weave_document_stream_writer)(
    FILE *stream,
    const void *context);

typedef int (*weave_json_document_writer)(
    weave_json_writer *writer,
    const void *context);

typedef struct weave_json_document_request {
    weave_json_document_writer write;
    const void *context;
} weave_json_document_request;

static int weave_write_json_document_stream(
    FILE *stream,
    const void *opaque) {
    const weave_json_document_request *request = opaque;
    weave_json_writer writer;
    weave_json_writer_init(&writer, stream);
    return request->write(&writer, request->context) == 0 &&
        weave_json_writer_finish(&writer);
}

static void weave_publish_record_error(int *saved, int fallback) {
    if (*saved == 0) {
        *saved = errno != 0 ? errno : fallback;
    }
}

static int weave_publish_document(
    const char *destination,
    const char *label,
    mode_t mode,
    weave_document_stream_writer write,
    const void *context) {
    if (destination == NULL) {
        return 0;
    }
    if (label == NULL || write == NULL) {
        errno = EINVAL;
        return 1;
    }

    char temporary[PATH_MAX];
    int length = snprintf(
        temporary,
        sizeof(temporary),
        "%s.tmp.XXXXXX",
        destination);
    if (length < 0 || (size_t)length >= sizeof(temporary)) {
        fprintf(
            stderr,
            "weavec: %s path is too long: %s\n",
            label,
            destination);
        errno = ENAMETOOLONG;
        return 1;
    }

    int fd = mkstemp(temporary);
    if (fd < 0) {
        fprintf(
            stderr,
            "weavec: cannot create %s beside %s: %s\n",
            label,
            destination,
            strerror(errno));
        return 1;
    }

    int failed = 0;
    int saved_error = 0;
    if (fchmod(fd, mode) != 0) {
        failed = 1;
        weave_publish_record_error(&saved_error, EIO);
    }

    FILE *stream = NULL;
    if (!failed) {
        stream = fdopen(fd, "wb");
        if (stream == NULL) {
            failed = 1;
            weave_publish_record_error(&saved_error, EIO);
        }
    }

    if (stream != NULL) {
        if (!write(stream, context)) {
            failed = 1;
            weave_publish_record_error(&saved_error, EIO);
        }
        if (ferror(stream)) {
            failed = 1;
            weave_publish_record_error(&saved_error, EIO);
        }
        if (fflush(stream) != 0) {
            failed = 1;
            weave_publish_record_error(&saved_error, EIO);
        }
        if (!failed && fsync(fileno(stream)) != 0) {
            failed = 1;
            weave_publish_record_error(&saved_error, EIO);
        }
        if (fclose(stream) != 0) {
            failed = 1;
            weave_publish_record_error(&saved_error, EIO);
        }
    } else {
        if (close(fd) != 0) {
            weave_publish_record_error(&saved_error, EIO);
        }
    }

    if (failed) {
        if (saved_error == 0) {
            saved_error = EIO;
        }
        fprintf(
            stderr,
            "weavec: cannot write %s %s: %s\n",
            label,
            destination,
            strerror(saved_error));
        (void)unlink(temporary);
        errno = saved_error;
        return 1;
    }

    if (rename(temporary, destination) != 0) {
        int rename_error = errno;
        fprintf(
            stderr,
            "weavec: cannot publish %s %s: %s\n",
            label,
            destination,
            strerror(rename_error));
        (void)unlink(temporary);
        errno = rename_error;
        return 1;
    }
    return 0;
}

static int weave_publish_json_document(
    const char *destination,
    const char *label,
    weave_json_document_writer write,
    const void *context) {
    weave_json_document_request request = {
        .write = write,
        .context = context,
    };
    return weave_publish_document(
        destination,
        label,
        0644,
        weave_write_json_document_stream,
        &request);
}

#endif
