# Floating-point special values

This is the IEEE-754 contract for `f32` and `f64`. Arithmetic is not
optional-real: every operation has a result, and that result may be
`NaN`, `±inf`, or signed zero.

## Decision

`f32` and `f64` are IEEE-754 binary32 and binary64 with the default
rounding mode (round to nearest, ties to even). There is no
rounding-mode control and no sticky exception flag.

| Situation | Result |
|---|---|
| Invalid IEEE operation (`0/0`, `sqrt` of a negative, `inf-inf`) | `NaN` |
| Overflow | `±inf` |
| Underflow | signed zero or a subnormal, as IEEE specifies |
| Absence or a recoverable non-numeric error | `Option` / `Result`, not `NaN` |

`NaN` is the loud IEEE answer. It is not a plausible real, so it is
not the silent-wrong-answer failure that
[Standard-library API conventions](stdlib-conventions.md) forbid.
Do not wrap `sqrt` in `Option f64` for a negative input.

Parse failures stay `Result`. Out-of-range indexing stays `Option`.
Those are not IEEE operations.

## Comparisons and literals

`=` / `eq_f64` are ordered equal (`oeq`): false if either operand is
`NaN`, including `NaN = NaN`. `!=` / `ne_f64` are unordered not-equal
(`une`): true if either operand is `NaN`. Ordered `<` `<=` `>` `>=`
are false if either operand is `NaN`.

There is no `isnan` builtin. `(!= x x)` is the predicate.

There are no `nan` or `inf` tokens yet. Produce them with IEEE
operations: `(/ 0.0 0.0)` is `NaN`, `(/ 1.0 0.0)` is `+inf`. Decimal
`-0.0` keeps its sign.

## `sqrt_f64`

The language result is IEEE `sqrt`:

- `NaN` for a negative input and for `NaN`
- signed zero for signed zero
- `+inf` for `+inf`
- correctly rounded for finite non-negative values

The implementation will be `llvm.sqrt`, which is deterministic and
correctly rounded. Avoiding libm does not apply to it. That lowering
needs an admitted WIR operator or a recognized intrinsic; it is not
a host `sqrt` call.

Until that operator exists, `stdlib/math.weave` uses a fixed 32-step
Newton iteration. Negative inputs return `NaN` (`0.0/0.0`), not
`0.0`. Signed zeros are returned unchanged. Finite positives are the
Newton result. `+inf` currently becomes `NaN` because `inf/inf` is
`NaN`; that is a known Newton defect, not the language rule.

## Other `std.math` kernels

These stay in Weave so numerics are not a process-wide libm:

| Function | Domain / notes | Accuracy (current) |
|---|---|---|
| `sin_f64` / `cos_f64` | Argument reduced to `[-π, π]`, then ten Taylor terms on `[0, π/2]` | About 1 ULP on the reduced quarter-turn; large inputs lose precision in the reduction |
| `tan_f64` | `sin/cos`; singular at cosine zeros | Follows `sin` and `cos`; infinities are the caller's |
| `acos_f64` | IEEE domain `[-1, 1]` should yield `NaN` outside | Sixty bisections of `cos_f64`; currently **clamps** `|x| > 1` instead of `NaN` |
| `f64_abs` | Absolute value | `-0.0` currently stays `-0.0` because `<` is ordered |
| `exp` / `log` / `pow` / `atan2` / `floor` / `ceil` | Not admitted | — |

`acos_f64` clamping is compatibility. New code must not copy it.
`PI_F64` is the binary64 rounding of π.

## What this does not decide

Reproducible cross-host numerics for the Taylor kernels are a
separate proposal. `f32` math helpers are not in `std.math` yet.
Payload `Option f64` still waits on specialization.
