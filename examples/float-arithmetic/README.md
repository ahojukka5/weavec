# Floating-point arithmetic

This example proves that a normal Weave program can write decimal `f64` values,
combine them with the canonical `add`, `sub`, `mul`, and `div` operators, and
print readable results.

Build and run from the repository root:

```sh
weavec build \
  stdlib/io.weave \
  examples/float-arithmetic/main.weave \
  -o build/float-arithmetic

./build/float-arithmetic
```

Expected output:

```text
1.5 + 2.25 = 3.75
7.0 / 2.0 = 3.5
2.5 * 4.0 - 1.0 = 9.0
```

The example source uses no user-declared external functions, pointer operations,
or WIR-shaped arithmetic operations. `stdlib/io.weave` implements numeric
rounding, decimal digit generation, and trailing-zero removal in Weave. Its only
host dependencies are byte output and string length from the platform C library.
