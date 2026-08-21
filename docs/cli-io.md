# Paths, files, process, and environment

This is the command-line I/O layer for ordinary Weave programs. Layout
and naming remain in [Standard-library layout](stdlib.md). Failure
conventions remain in
[Standard-library API conventions](stdlib-conventions.md).

## What shipped

| Module | Adds |
|---|---|
| `std.process` | `process_exit`, plus existing `args_count` / `arg` |
| `std.file` | `file_write_text`, plus existing text-file read |
| `std.path` | `path_is_absolute`, `path_join`, `path_basename` |
| `std.env` | `env_get` |

A program can read an argument, write a file, read it back, and write
stdout or stderr without naming `ptr` in application source. Canonical
`main(argc, argv)` remains issue #338; `program_main` plus `arg` is
still the working entry.

## Process

`process_exit` terminates the process with an exit status. The status
is not a length. `std.process` still does not depend on `String` or
`Option`, so existing examples keep the same build lists.

`arg` still returns `ptr` and uses null for an out-of-range index.
`process_arg` as `Option` waits on helper specialization, as recorded
in the API conventions.

## Files

`file_write_text(path, text)` replaces the named file with one
NUL-terminated string. It returns `Result bool FileError`. `Ok true`
means the file now holds that text; `Err Failed` means it does not.
That is a recoverable I/O result, not a byte count and not errno.

`file_open_text` is unchanged. A `TextFile` whose content is null still
means the file could not be read; `text_file_is_open` remains the
compatibility check. `std.result` must appear before `std.file`.

No new public length parameter is `i32`. Lengths stay inside the
implementation (`i64` from `ftell` / a C-string walk) until `usize` is
admitted.

## Paths

POSIX `/` only. No current-directory lookup, no `..` resolution, and
no Windows drives.

- `path_is_absolute` is true when the path starts with `/`.
- `path_join` copies the right path when it is absolute, otherwise
  joins with a single `/`.
- `path_basename` is the text after the last `/`, or the whole path.

Joined and basename results are owned `String` values. Callers pass C
strings at the boundary so the helpers compose with `arg()` and
`file_open_text`. `std.memory`, `std.option`, `std.bytes`, and
`std.string` must appear first.

## Environment

`env_get(name)` returns `Option String`. A missing name is `None`, not
a null pointer and not an empty string. The host `getenv` pointer is
copied immediately.

`std.env` is a separate module so `std.process` stays free of `String`.

## Host boundary

`exit`, `getenv`, `fopen`, and `fwrite` are libc. There are no new
`weave_rt_` symbols. Path joining, basename, and C-string length walks
are Weave.
