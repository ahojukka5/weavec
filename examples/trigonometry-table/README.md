# Trigonometric function table

Print sine, cosine, and tangent for a small deterministic set of angles in
degrees.

Build and run from the repository root or an extracted release package:

```sh
weavec build \
  stdlib/math.weave \
  stdlib/io.weave \
  examples/trigonometry-table/main.weave \
  -o trigonometry-table

./trigonometry-table
```

Expected output:

```text
angle  sin       cos       tan
0      0.000000  1.000000  0.000000
30     0.500000  0.866025  0.577350
45     0.707107  0.707107  1.000000
60     0.866025  0.500000  1.732051
```

`stdlib/math.weave` defines `PI_F64` as `3.141592653589793` and converts degrees
to radians with `degrees * PI_F64 / 180`. Sine and cosine use deterministic range
reduction followed by fixed-count Taylor recurrences; tangent reuses those two
functions. The focused math regression checks the representative values with an
absolute tolerance of `1e-7` before the table's exact six-decimal formatting is
checked byte-for-byte.

The application source contains no raw pointers, libc declarations, or WIR-shaped
forms. Fixed-six formatting is implemented in `stdlib/io.weave`; no numeric or
formatting semantics are added to the C runtime.
