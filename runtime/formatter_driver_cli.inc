    weave_fmt_context *context,
    int64_t root) {
    size_t root_start = weave_fmt_node_start(context, root);
    size_t root_end = weave_fmt_node_end(context, root);
    if (root_start > context->source_length || root_end == 0) return 0;
    weave_fmt_collect_signatures(context, root);
    if (!weave_fmt_emit_gap_comments(context, 0, root_start, 0) ||
        !weave_fmt_format_node(
            context, root, 0, WEAVE_FMT_UNKNOWN, 0) ||
        !weave_fmt_emit_gap_comments(
            context, root_end, context->source_length, 0) ||
        !weave_fmt_write_newline(context)) {
        return 0;
    }
    return !context->writer.failed;
}

static unsigned char *weave_fmt_read_file(
    const char *path,
    size_t *length_out) {
    FILE *stream = fopen(path, "rb");
    if (stream == NULL) return NULL;
    if (fseek(stream, 0, SEEK_END) != 0) {
        fclose(stream);
        return NULL;
    }
    long end = ftell(stream);
    if (end < 0 || fseek(stream, 0, SEEK_SET) != 0) {
        fclose(stream);
        return NULL;
    }
    size_t length = (size_t)end;
    unsigned char *data = malloc(length + 1);
    if (data == NULL) {
        fclose(stream);
        return NULL;
    }
    size_t read_count = fread(data, 1, length, stream);
    int close_failed = fclose(stream) != 0;
    if (read_count != length || close_failed) {
        free(data);
        return NULL;
    }
    data[length] = '\0';
    *length_out = length;
    return data;
}

static void weave_fmt_context_clear(weave_fmt_context *context) {
    for (size_t index = 0; index < context->signature_count; ++index) {
        free(context->signatures[index].parameters);
    }
    free(context->signatures);
    free(context->bindings);
    context->signatures = NULL;
    context->bindings = NULL;
}

static int weave_fmt_format_file_to_fd(
    const char *input_path,
    int output_fd) {
    size_t source_length = 0;
    unsigned char *source = weave_fmt_read_file(input_path, &source_length);
    if (source == NULL) {
        fprintf(stderr, "weavec: fmt: cannot read %s\n", input_path);
        return 3;
    }
    void *tokens = lex((const char *)source, (int64_t)source_length);
    if (tokens == NULL) {
        fprintf(stderr, "weavec: fmt: lexical analysis failed for %s\n", input_path);
        free(source);
        return 3;
    }
    void *tree = parse(tokens);
    if (tree == NULL) {
        fprintf(stderr, "weavec: fmt: parse failed for %s\n", input_path);
        tokens_free(tokens);
        free(source);
        return 3;
    }
    FILE *output = fdopen(output_fd, "wb");
    if (output == NULL) {
        fprintf(stderr, "weavec: fmt: cannot open temporary output\n");
        close(output_fd);
        tree_free(tree);
        tokens_free(tokens);
        free(source);
        return 3;
    }
    weave_fmt_context context = {
        .source = source,
        .source_length = source_length,
        .tree = tree,
        .writer = {
            .stream = output,
            .at_line_start = 1,
        },
    };
    int formatted = weave_fmt_format_document(&context, 0);
    int flush_failed = fflush(output) != 0;
    int sync_failed = !flush_failed && fsync(fileno(output)) != 0;
    int close_failed = fclose(output) != 0;
    if (!formatted || context.semantic_overflow || flush_failed ||
        sync_failed || close_failed) {
        fprintf(stderr, "weavec: fmt: formatting failed for %s\n", input_path);
        formatted = 0;
    }
    weave_fmt_context_clear(&context);
    tree_free(tree);
    tokens_free(tokens);
    free(source);
    return formatted ? 0 : 3;
}

static int weave_fmt_files_equal(
    const char *left_path,
    const char *right_path) {
    FILE *left = fopen(left_path, "rb");
    FILE *right = fopen(right_path, "rb");
    if (left == NULL || right == NULL) {
        if (left != NULL) fclose(left);
        if (right != NULL) fclose(right);
        return -1;
    }
    int equal = 1;
    unsigned char left_buffer[8192];
    unsigned char right_buffer[8192];
    for (;;) {
        size_t left_count = fread(left_buffer, 1, sizeof(left_buffer), left);
        size_t right_count = fread(right_buffer, 1, sizeof(right_buffer), right);
        if (left_count != right_count ||
            memcmp(left_buffer, right_buffer, left_count) != 0) {
            equal = 0;
            break;
        }
        if (left_count < sizeof(left_buffer)) {
            if (ferror(left) || ferror(right)) equal = -1;
            break;
        }
    }
    int left_close_failed = fclose(left) != 0;
    int right_close_failed = fclose(right) != 0;
    if (left_close_failed || right_close_failed) equal = -1;
    return equal;
}

static int weave_fmt_same_file(
    const char *left_path,
    const char *right_path) {
    if (strcmp(left_path, right_path) == 0) return 1;
    struct stat left;
    struct stat right;
    return stat(left_path, &left) == 0 && stat(right_path, &right) == 0 &&
        left.st_dev == right.st_dev && left.st_ino == right.st_ino;
}

static int weave_fmt_make_sibling_temp(
    const char *destination,
    char *path,
    size_t path_size) {
    int length = snprintf(path, path_size, "%s.fmt.XXXXXX", destination);
    if (length < 0 || (size_t)length >= path_size) return -1;
    return mkstemp(path);
}

static int weave_fmt_run(
    const char *source_path,
    const char *output_path,
    int check_only) {
    const char *destination = output_path != NULL ? output_path : source_path;
    char temporary[PATH_MAX];
    int temp_fd = weave_fmt_make_sibling_temp(
        destination, temporary, sizeof(temporary));
    if (temp_fd < 0) {
        fprintf(stderr, "weavec: fmt: cannot create temporary output for %s\n", destination);
        return 3;
    }
    int format_status = weave_fmt_format_file_to_fd(source_path, temp_fd);
    if (format_status != 0) {
        unlink(temporary);
        return format_status;
    }
    int equal = weave_fmt_files_equal(source_path, temporary);
    if (equal < 0) {
        fprintf(stderr, "weavec: fmt: cannot compare formatted source\n");
        unlink(temporary);
        return 3;
    }
    if (check_only) {
        unlink(temporary);
        return equal ? 0 : 1;
    }

    int in_place = weave_fmt_same_file(source_path, destination);
    struct stat source_status;
    mode_t mode = 0644;
    if ((in_place || output_path == NULL) && stat(source_path, &source_status) == 0) {
        mode = source_status.st_mode & 0777;
    }
    if (chmod(temporary, mode) != 0) {
        fprintf(stderr, "weavec: fmt: cannot set output mode for %s\n", destination);
        unlink(temporary);
        return 3;
    }
    if (output_path == NULL && equal) {
        unlink(temporary);
        return 0;
    }
    if (rename(temporary, destination) != 0) {
        fprintf(stderr, "weavec: fmt: cannot publish %s: %s\n", destination, strerror(errno));
        unlink(temporary);
        return 3;
    }
    return 0;
}

int weave_rt_format_main(int argc, char **argv) {
    if (argc == 3) {
        return weave_fmt_run(argv[2], NULL, 0);
    }
    if (argc == 4 && strcmp(argv[2], "--check") == 0) {
        return weave_fmt_run(argv[3], NULL, 1);
    }
    if (argc == 5 && strcmp(argv[2], "--output") == 0) {
        return weave_fmt_run(argv[4], argv[3], 0);
    }
    fputs(
        "usage: weavec fmt SOURCE | weavec fmt --check SOURCE | "
        "weavec fmt --output OUTPUT SOURCE\n",
        stderr);
    return 2;
}

