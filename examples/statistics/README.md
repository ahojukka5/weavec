# Descriptive statistics

Compute the count, mean, variance, and standard deviation of the floating-point
values supplied on the command line.

From the repository root or an extracted release package:

```sh
weavec build \
  stdlib/memory.weave \
  stdlib/process.weave \
  stdlib/parse.weave \
  stdlib/math.weave \
  stdlib/io.weave \
  stdlib/statistics.weave \
  examples/statistics/main.weave \
  -o statistics

./statistics 1 2 3 4
```

Expected output:

```text
count = 4
mean = 2.5
variance = 1.25
stddev = 1.118034
```

Any number of values may be supplied. A single value reports a variance and
standard deviation of `0.0`, as do repeated values. Decimals and negative values
are accepted.

Supplying no values at all prints `usage: statistics <value> [value ...]` and
exits 2, because the mean of an empty set is undefined rather than zero. A value
that is not a number is reported by name — `error: not a number: nope` — so the
offending argument is identifiable without counting positions.

## Population, not sample

These are **population** statistics. The supplied arguments are treated as the
whole population, so variance divides the sum of squared deviations by the count
`n`, not by `n - 1`:

```text
variance = sum((x - mean)^2) / n
stddev   = sqrt(variance)
```

For `1 2 3 4` that gives `1.25`, where the sample variance would give
`1.666667`. The program computes only the population form; there is no flag to
select the other.

## Accumulation

The mean is accumulated in one pass and the squared deviations in a second pass
over the same arguments. The single-pass sum-of-squares shortcut
(`E[x^2] - E[x]^2`) is avoided because it loses precision when the mean is large
relative to the spread.

Standard deviation reuses `sqrt_f64` from `stdlib/math.weave`, and output reuses
`print_f64` and `write_u32_decimal` from `stdlib/io.weave`; the count prints as a
plain integer rather than `4.0`.

The application source contains no raw pointers, manual `argc`/`argv` access,
libc declarations, or WIR-shaped forms.
