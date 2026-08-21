# Ergonomic surface and standard-library qualification

This is the package and checkout gate for epic #113. Focused suites keep
their own coverage. This page records the one user-facing command
sequence that must work from a source tree and from an extracted
release package.

## Command sequence

From the repository root or an extracted package, `file-statistics`
reads a path argument, opens a text file, parses one number per line,
and writes a numeric summary to stdout. Errors go to stderr with exit
status 2. Application source names no `ptr` and no libc.

```sh
weavec build \
  stdlib/memory.weave \
  stdlib/process.weave \
  stdlib/parse.weave \
  stdlib/math.weave \
  stdlib/io.weave \
  stdlib/statistics.weave \
  stdlib/result.weave \
  stdlib/file.weave \
  examples/file-statistics/main.weave \
  -o file-statistics

printf '1\n2\n3\n4\n' > values.txt
./file-statistics values.txt
```

Expected stdout:

```text
count = 4
mean = 2.5
variance = 1.25
stddev = 1.118034
```

`std.result` is required because `std.file` returns `Result` from
`file_write_text`. This example still uses `file_open_text` plus
`text_file_is_open` as compatibility.

## What else this epic already proved

| Area | Where |
|---|---|
| Expression `if`, loops, inference | focused control-flow suites |
| Strings, bytes, `Option` get | `test/string-bytes` |
| `Vec` / `Slice` bounds | `test/vec-slice` |
| Formatting and `Result` parse | `test/convert-format` |
| Paths, env, `FileError` write | `test/cli-io` |
| `Result` CLI | `test/parse-digits` |

Indexing and I/O policy:
[Bounds-check and I/O error behavior](bounds-io-errors.md).

## Package smoke

`scripts/package-linux-release.sh` builds `file-statistics` and
`parse-digits` from the extracted tree. Checkout qualification is
`test/ergonomic-stdlib-qualify/test.sh`: shuffled independent stdlib
order, relocated copies, usage diagnostics, and a native run when
`llc` is present.
