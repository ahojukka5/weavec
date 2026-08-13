# 3×3 matrix-vector multiplication

Multiply a fixed 3×3 matrix by a three-dimensional vector and print the result.

From the repository root or an extracted release package:

```sh
weavec build \
  stdlib/process.weave \
  stdlib/parse.weave \
  stdlib/io.weave \
  stdlib/memory.weave \
  stdlib/vector.weave \
  stdlib/matrix.weave \
  examples/matrix-vector/main.weave \
  -o matrix-vector

./matrix-vector
```

Expected output:

```text
result = [14.0, 32.0, 50.0]
```

With no arguments the program uses the documented demonstration values: the
matrix whose rows are `1 2 3`, `4 5 6`, and `7 8 9`, times the vector `1 2 3`.

All twelve values may be supplied instead, as nine matrix components in row order
followed by the three vector components:

```sh
./matrix-vector 2 0 0  0 3 0  0 0 4  1 2 3   # result = [2.0, 6.0, 12.0]
./matrix-vector 1 0 0  0 1 0  0 0 1  1 2 3   # result = [1.0, 2.0, 3.0]
```

Any other argument count, or a malformed number, produces a concise stderr
diagnostic and exit status 2.

## Representation

`stdlib/matrix.weave` declares `Mat3` with its nine components named directly as
`m00` through `m22`. Weave has no arrays yet, and adding a generic collection or
index arithmetic merely to avoid writing nine fields would introduce far more
machinery than it removes, so the fields are written out.

Multiplication reuses the existing dot product rather than repeating a sum of
products three times: `mat3_row0`, `mat3_row1`, and `mat3_row2` each present a row
as a `Vec3`, and `mat3_apply` dots each row with the input vector. Row order is
pinned by a test using a non-symmetric permutation matrix, so a row-major and a
column-major reading cannot both pass.

`std.matrix` requires `std.vector`, which owns the only host allocation
declarations among the standard modules.

## Output

`result = [x, y, z]` is composed in the example from `write_stdout` and
`write_f64_trimmed`, the trimmed counterpart to `write_f64_fixed6` in
`stdlib/io.weave`. `print_f64` is now that same writer plus a label and a
newline, so labelled lines and bracketed vectors select digits through one
implementation.

The application source contains no raw allocation, pointer arithmetic, generated
struct helper calls, libc declarations, or WIR-shaped forms.
