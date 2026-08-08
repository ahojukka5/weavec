# Pythagorean theorem

Compute the hypotenuse from two positive side lengths supplied on the command
line.

From the repository root or an extracted release package:

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

Expected output:

```text
5.0
```

Another valid invocation is `./pythagoras 1.5 2.0`, which prints `2.5`.
Invalid arity, malformed numbers, zero, and negative side lengths produce a
concise stderr diagnostic and exit status 2.

The application source contains no raw pointer operations, libc declarations, or
WIR-shaped calls. `stdlib/process.weave` owns the low-level native entry wrapper,
while argument conventions, numeric parsing, and square root are implemented in
Weave. The C program runtime only stores and returns the platform-provided raw
argument pointers mechanically.
