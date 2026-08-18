# Weave example programs

Twelve small, complete programs written in ordinary Weave. Each one builds with a
single `weavec build` command and runs from a terminal — from a checkout of this
repository or from an extracted release package, with no other setup.

None of them require knowing anything about how the compiler works. They use
command-line arguments, arithmetic, conditionals, loops, structs, tagged
choices, and files.

## The programs

### Numbers and output

| program | what it does |
| --- | --- |
| [float-arithmetic](float-arithmetic/README.md) | Decimal arithmetic with readable output |
| [pythagoras](pythagoras/README.md) | Hypotenuse from two sides: `./pythagoras 3 4` → `5.0` |
| [trigonometry-table](trigonometry-table/README.md) | Sine, cosine, and tangent for a set of angles |

### Vectors and matrices

| program | what it does |
| --- | --- |
| [vector-dot](vector-dot/README.md) | Dot product of two 3-D vectors: `1 2 3 4 5 6` → `32.0` |
| [vector-geometry](vector-geometry/README.md) | Vector lengths and the angle between them |
| [matrix-vector](matrix-vector/README.md) | A 3×3 matrix times a vector → `[14.0, 32.0, 50.0]` |

### Applied calculation

| program | what it does |
| --- | --- |
| [statistics](statistics/README.md) | Count, mean, variance, and standard deviation of the arguments |
| [quadratic](quadratic/README.md) | Real roots of `ax² + bx + c`, or `no real roots` |
| [projectile-motion](projectile-motion/README.md) | Flight time, height, and range from speed and angle |
| [newton-root](newton-root/README.md) | A square root by iteration, reporting how many passes it took |
| [file-statistics](file-statistics/README.md) | The same summary as `statistics`, read from a text file |

### Absence and recoverable errors

| program | what it does |
| --- | --- |
| [parse-digits](parse-digits/README.md) | Digits from the command line: `1 2 3` → `digits = 1 2 3` / `sum = 6` |

## Building one

Every program is built the same way: list the standard modules it uses, then its
own source, then name the output. From a checkout or an extracted package:

```sh
weavec build \
  stdlib/process.weave \
  stdlib/parse.weave \
  stdlib/math.weave \
  stdlib/io.weave \
  examples/pythagoras/main.weave \
  -o pythagoras

./pythagoras 3 4
```

Each program's README gives its exact command and its expected output. The
modules a program needs are the ones it actually uses:

| module | provides |
| --- | --- |
| `stdlib/process.weave` | command-line arguments |
| `stdlib/parse.weave` | reading numbers from text |
| `stdlib/math.weave` | square root, trigonometry, inverse cosine |
| `stdlib/io.weave` | printing numbers and text |
| `stdlib/memory.weave` | allocation, needed by the modules below |
| `stdlib/vector.weave` | the `Vec3` type and its dot product |
| `stdlib/matrix.weave` | the `Mat3` type and matrix-vector multiplication |
| `stdlib/statistics.weave` | mean and variance over a set of values |
| `stdlib/file.weave` | reading a text file as lines |
| `stdlib/option.weave` | the `Option` type for a value that may be absent |
| `stdlib/result.weave` | the `Result` type for success or a recoverable error |

Modules that depend on another must be listed after it: `stdlib/memory.weave`
comes before anything that allocates, and `stdlib/vector.weave` before
`stdlib/matrix.weave`.

## What these demonstrate

Every program prints exact, documented output and is checked byte-for-byte by the
test suite, both from the repository and from an extracted release package. Where
a result depends on a numerical choice — population versus sample variance, the
gravity constant, a convergence tolerance, the ordering of quadratic roots — the
program's README states the choice and why.

Numerical behavior lives in Weave rather than in C: parsing, formatting, square
root, and trigonometry are all implemented in the standard modules listed above.

The application sources contain no raw pointers, no libc declarations, and no
compiler-internal forms. Reading any `main.weave` alongside its README should be
enough to understand what the program does.
