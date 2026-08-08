// Process argument storage shared by the compiler host runtime and program runtime.
//
// This file is included into exactly one runtime translation unit per executable.
// It preserves the platform-provided argc/argv values mechanically. User-facing
// decisions such as hiding argv[0] and bounds semantics live in std.process.

static int weave_process_raw_argc = 0;
static char **weave_process_raw_argv = 0;

void weave_rt_process_capture(int argc, void *argv) {
    weave_process_raw_argc = argc;
    weave_process_raw_argv = (char **)argv;
}

int weave_rt_process_raw_argc(void) {
    return weave_process_raw_argc;
}

void *weave_rt_process_raw_arg(int index) {
    if (weave_process_raw_argv == 0 || index < 0 || index >= weave_process_raw_argc) {
        return 0;
    }
    return weave_process_raw_argv[index];
}
