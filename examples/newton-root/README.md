# Newton square root

Find the square root of a non-negative number by Newton iteration, reporting the
approximation and how many iterations it took.

From the repository root or an extracted release package:

```sh
weavec build \
  stdlib/process.weave \
  stdlib/parse.weave \
  stdlib/math.weave \
  stdlib/io.weave \
  examples/newton-root/main.weave \
  -o newton-root

./newton-root 2
```

Expected output:

```text
root = 1.414214
iterations = 5
```

## Why this does not call sqrt_f64

`stdlib/math.weave` already provides `sqrt_f64`, and this example deliberately
does not use it. The point here is the loop: an explicit convergence test, a
visible iteration count, and a deterministic failure path. Delegating would
demonstrate none of that. The test asserts both that the source never mentions
`sqrt_f64` and that the elaborated program contains no call to it.

`std.math` is still built, because the example reuses `f64_abs` for its
convergence test rather than writing a second absolute value.

## The iteration

Newton's method applied to `f(x) = x² - value` simplifies to averaging a guess
with the value divided by that guess:

```text
next = (guess + value / guess) / 2
```

The first guess is the value itself. Each pass roughly doubles the number of
correct digits, which is why even `1000000` converges in 15 iterations.

## Stopping criteria

Iteration stops when two successive approximations differ by no more than
`TOLERANCE_F64`, which is `1e-9`:

```text
|next - guess| <= 1e-9
```

This is an **absolute** test, not a relative one. That is adequate for this
program because the reported result is printed to six fractional digits, so an
absolute agreement of `1e-9` is three orders of magnitude tighter than anything
the output can show. A general-purpose solver over very large or very small
magnitudes would want a relative test instead; this is a demonstration, not a
general solver.

Because the test compares successive iterates rather than measuring the true
error, the returned value is typically accurate to rather better than the
tolerance — quadratic convergence means the final step overshoots the stopping
threshold substantially. For `2` the printed root matches the correctly rounded
`sqrt(2)` at six digits, which the test verifies against an independently
computed square root.

`ITERATION_LIMIT_I32` caps the loop at 100 passes. No converging input comes
close to that, so the limit exists to fail deterministically rather than spin:
if it is reached, the program writes `error: no convergence within the iteration
limit` to stderr and exits 1. That exit status is distinct from the 2 used for
bad input, so a caller can tell a malformed argument from a numerical failure.

## Cases

| input | result | note |
| --- | --- | --- |
| `2` | `1.414214` in 5 | the documented case |
| `4` | `2.000000` in 6 | exact square |
| `0.25` | `0.500000` in 6 | below one |
| `1` | `1.000000` in 1 | already its own root |
| `0` | `0.000000` in 0 | exact, and no division by the first guess |
| `-4` | stderr, exit 2 | no real square root |

Zero is special-cased before the loop: its root is exact, and it is also the one
input whose first guess would be zero and produce a division by zero.

The application source contains no raw pointers, libc declarations, or WIR-shaped
forms.
