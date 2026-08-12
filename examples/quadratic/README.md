# Quadratic equation solver

Solve `a*x*x + b*x + c = 0` for real roots.

From the repository root or an extracted release package:

```sh
weavec build \
  stdlib/process.weave \
  stdlib/parse.weave \
  stdlib/math.weave \
  stdlib/io.weave \
  examples/quadratic/main.weave \
  -o quadratic

./quadratic 1 -3 2
```

Expected output:

```text
roots = 1.0, 2.0
```

## The four cases

The discriminant `d = b^2 - 4ac` selects the case:

| input | condition | output | exit |
| --- | --- | --- | --- |
| `./quadratic 1 -3 2` | `d > 0` | `roots = 1.0, 2.0` | 0 |
| `./quadratic 1 2 1` | `d = 0` | `root = -1.0` | 0 |
| `./quadratic 1 0 1` | `d < 0` | `no real roots` | 0 |
| `./quadratic 0 2 4` | `a = 0` | stderr diagnostic | 2 |

Two distinct roots print as `roots = smaller, larger`. A zero discriminant is one
root of multiplicity two and prints the singular `root = ...`, so the two cases
are distinguishable without counting commas. No real roots is a correct answer
rather than a failure, so it goes to stdout and exits 0; only malformed input
exits 2.

A zero leading coefficient is rejected rather than silently solved as a linear
equation, because `a = 0` is not a quadratic and the caller most likely made a
mistake.

## Formulas and ordering

```text
d      = b^2 - 4ac
roots  = (-b + sqrt(d)) / 2a  and  (-b - sqrt(d)) / 2a
repeat = -b / 2a                        when d = 0
```

Output is ordered ascending. Which of the two formulas produces the smaller root
depends on the sign of `a`, so the program compares them and orders explicitly
rather than assuming. `./quadratic -1 3 -2` prints `roots = 1.0, 2.0`, the same
ordering as its positive-leading equivalent.

## Known numerical limitation

The direct formula loses precision through cancellation when `b*b` is much larger
than `4ac`: the root computed from `-b + sqrt(d)` is the difference of two nearly
equal numbers. The standard remedy computes one root from
`q = -(b + sign(b) * sqrt(d)) / 2` and the other as `c / q`.

That remedy is deliberately not implemented here. This program prints six
fractional digits, and for inputs where cancellation matters the affected root is
far smaller than `1e-6`, so both forms print identically. Adding the branch would
add code that no test of this program's output could distinguish. A program that
needs the small root to full precision needs a different output format first.

The application source contains no raw pointers, libc declarations, or WIR-shaped
forms, and reuses `sqrt_f64` rather than iterating for a square root itself.
