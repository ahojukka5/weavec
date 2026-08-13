# Vector lengths and angle

Compute the lengths of two three-dimensional vectors and the angle between them
from six floating-point components on the command line.

From the repository root or an extracted release package:

```sh
weavec build \
  stdlib/process.weave \
  stdlib/parse.weave \
  stdlib/math.weave \
  stdlib/io.weave \
  stdlib/memory.weave \
  stdlib/vector.weave \
  examples/vector-geometry/main.weave \
  -o vector-geometry

./vector-geometry 1 0 0 0 1 0
```

Expected output:

```text
length-a = 1.0
length-b = 1.0
angle-degrees = 90.0
```

Parallel vectors such as `./vector-geometry 1 2 3 2 4 6` report `0.0` degrees,
opposing vectors such as `./vector-geometry 1 2 3 -1 -2 -3` report `180.0`, and
`./vector-geometry 1 1 0 1 0 0` reports `45.0`. A zero-length vector, a wrong
argument count, and a malformed number each produce a concise stderr diagnostic
and exit status 2, because the angle to a zero-length vector is undefined rather
than merely inconvenient.

## Reuse

The example adds no geometry of its own beyond composing existing modules:

- `Vec3` and `vec3_dot` come from `stdlib/vector.weave` (see the vector-dot
  example);
- length is `sqrt_f64` of a vector's dot product with itself, so there is no
  second magnitude implementation;
- `acos_f64` and `radians_to_degrees` come from `stdlib/math.weave`.

`acos_f64` inverts cosine by fixed-count bisection across `[0, pi]`, where
cosine decreases monotonically. That reuses the existing cosine series instead of
introducing a second numerical implementation, and it needs no division that
could be singular.

## Cosine domain

The cosine of the angle is `dot(a, b) / (|a| * |b|)`. In exact arithmetic that
quotient lies in `[-1, 1]`, but floating-point roundoff in the lengths and the
product can place it a few ulps outside. `acos_f64` clamps at exactly that
boundary — inputs at or beyond `1` return `0`, and inputs at or beyond `-1`
return `pi` — and clamps nowhere else. The exact endpoints return exact angles
rather than a converged approximation, so antiparallel vectors report `180.0`
rather than a value a fraction of a degree short.

Because both series are now evaluated only on a quarter turn after range
reduction, cosine is accurate to near binary64 precision across the whole
interval, which is what makes the inverse trustworthy at six decimal places.

The application source contains no raw pointer operations, libc declarations, or
WIR-shaped calls. Allocation stays inside `stdlib/vector.weave`.
