# Bounds-check and I/O error behavior

This is the failure policy for public indexing helpers and recoverable
I/O. Naming and the three admitted outcomes remain in
[Standard-library API conventions](stdlib-conventions.md). Paths and
files remain in [Paths, files, process, and environment](cli-io.md).

## Indexing

Out-of-range **get** returns `Option` / `None`. It does not abort.

| Helper | Missing index |
|---|---|
| `string_get`, `bytes_get` | `None` |
| `vec_get`, `slice_get` | `None` |

Out-of-range or refused **set** / **push** returns `bool` `false`. The
receiver is unchanged.

A proven in-range invariant break may abort. That is not a substitute
for `Option` or `Result` on a public API.

`text_file_line` still returns a null `ptr` for an out-of-range index
or a file that failed to open. That is compatibility with the
line-oriented examples, not a pattern to copy. New indexing helpers
use `Option`.

`arg` still returns null for an out-of-range index. `process_arg` as
`Option` waits on helper specialization, as recorded in the API
conventions. No public indexing helper takes an `i32` length.

## I/O

Absence is not an I/O error. `env_get` returns `Option String`: a
missing name is `None`, not `""` and not a null pointer.

Recoverable filesystem failure is `Result` with a named error enum.
`file_write_text` returns `Result bool FileError`. `Ok true` means the
file now holds that C string. `Err Failed` means it does not: a null
argument, an open failure, or a short write. Callers inspect the
`Result` tag. There is no errno integer in user source.

`FileError` is coarse on purpose. The only constructor today is
`Failed`, so exhaustive match does not freeze a platform taxonomy.

`file_open_text` is unchanged compatibility: a `TextFile` whose content
is null still means the file could not be read, and
`text_file_is_open` remains the check. New open helpers should return
`Result` with `FileError`.

`std.file` requires `std.result` earlier in the build list.
`std.process` still does not depend on `Option`, `String`, or
`Result`.
