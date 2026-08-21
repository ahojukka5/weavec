# File-based numeric summary

Read one floating-point value per line from a text file and print count, mean,
population variance, and population standard deviation.

From the repository root or an extracted release package:

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

Expected output:

```text
count = 4
mean = 2.5
variance = 1.25
stddev = 1.118034
```

These are **population** statistics, the same as the command-line
[statistics](../statistics/README.md) example: the divisor is the count `n`, not
`n - 1`.

## Shared statistics

The formulas are not repeated here. Both this example and the command-line one
build a `Samples` value from `stdlib/statistics.weave` and ask it for the mean
and variance, so there is exactly one implementation to be right or wrong. The
test asserts this example calls `samples_population_variance` and does not
recompute deviations itself, and checks that the same four values produce the
same summary through both programs.

`Samples` is a fixed-capacity block of `f64`. Both callers know how many values
they will have before parsing — an argument count, a line count — so it never
needs to grow, and no growth machinery exists.

## Reading the file

`stdlib/file.weave` provides only what a line-oriented program needs:

```text
file_open_text(path)      -> TextFile
text_file_is_open(file)   -> bool
text_file_line_count(file) -> i32
text_file_line(file, i)   -> line text
text_file_close(file)
file_write_text(path, text) -> Result bool FileError
```

There is no directory traversal, no seeking, no streaming, and no
path handling. Writing a whole C string is `file_write_text`. `TextFile` is a
nominal struct, so this example holds a value of that type and never a
descriptor or a buffer address.

The whole file is read at open time and each newline is replaced by a terminator
in place, so a line is an ordinary string without copying. That suits the small
inputs these examples work with; it is not a design for large files.

### Line counting

A trailing newline ends the last line rather than starting an empty one, so
`1\n2\n3\n4\n` is four lines. A file whose final line has no newline still counts
that line, so `5\n6` is two. An empty file has no lines and is rejected, because
the mean of nothing is undefined.

Carriage returns are not stripped. A CRLF file therefore fails with a
line-numbered parse error rather than being silently mis-parsed.

## Errors

| condition | message | exit |
| --- | --- | --- |
| no argument | `usage: file-statistics <path>` | 2 |
| missing or unreadable file | `error: cannot read file: <path>` | 2 |
| empty file | `error: file contains no values` | 2 |
| malformed line | `error: line 3: not a number: x` | 2 |

Line numbers count from one, so they match what an editor shows. A missing file
and an unreadable file report the same thing deliberately: from the program's
point of view the file could not be read, and distinguishing the two would mean
reporting `errno` detail this API does not expose.

The application source contains no raw pointers, file descriptors, buffers,
user-declared libc functions, or WIR-shaped forms.
