# Three-dimensional vector dot product

Compute the dot product of two three-dimensional vectors given as six
floating-point components on the command line.

From the repository root or an extracted release package:

```sh
weavec build \
  stdlib/process.weave \
  stdlib/parse.weave \
  stdlib/io.weave \
  stdlib/memory.weave \
  stdlib/vector.weave \
  examples/vector-dot/main.weave \
  -o vector-dot

./vector-dot 1 2 3 4 5 6
```

Expected output:

```text
32.0
```

Orthogonal vectors such as `./vector-dot 1 0 0 0 1 0` print `0.0`, opposing
vectors such as `./vector-dot 1 2 3 -1 -2 -3` print `-14.0`, and fractional
components such as `./vector-dot 0.5 1.5 2.5 1 1 1` print `4.5`. Wrong argument
counts and malformed numbers produce a concise stderr diagnostic and exit
status 2.

`stdlib/vector.weave` declares `Vec3` as a nominal struct with three `f64`
fields. Because the type is nominal rather than a bare pointer, one vector
cannot be passed where another value is expected, and a plain `ptr` is rejected
with `expected Vec3, got ptr`. The module describes exactly three components on
purpose: it is not a generic collection, a dimension-parameterised vector, or
the start of a linear-algebra hierarchy.

The application source constructs vectors with `(new Vec3 (x ...) (y ...)
(z ...))` and contains no raw pointer operations, libc declarations, or
WIR-shaped calls. Allocation and release stay inside the standard module, which
owns the only `malloc` and `free` declarations involved.
