# Parse digits

Read one or more command-line arguments as digits from 0 to 9, print them, and
print their sum.

From the repository root or an extracted release package:

```sh
weavec build \
  stdlib/process.weave \
  stdlib/parse.weave \
  stdlib/option.weave \
  stdlib/result.weave \
  stdlib/io.weave \
  examples/parse-digits/main.weave \
  -o parse-digits

./parse-digits 1 2 3
```

Expected output:

```text
digits = 1 2 3
sum = 6
```

Each argument must be a decimal number that is exactly an integer from 0 to 9.
`1` and `1.0` are accepted; `10`, `-1`, `1.5`, and `x` are not.

| input | output | exit |
| --- | --- | --- |
| `./parse-digits 1 2 3` | `digits = 1 2 3` / `sum = 6` | 0 |
| `./parse-digits 0 9` | `digits = 0 9` / `sum = 9` | 0 |
| `./parse-digits` | stderr usage | 2 |
| `./parse-digits 1 x` | stderr diagnostic | 2 |

A missing argument list is a usage error. A value that is not a digit is a
recoverable parse error: the program reports the text and exits 2 rather than
substituting a default.

The application source contains no raw pointers, libc declarations, or
compiler-internal forms. `Option` represents a digit that may be absent, `Result`
represents a parse that may fail, `match` chooses between those cases, and
`(try ...)` unwraps a successful parse or returns the error from the summing
helper. A generic `identity` function is specialized at `i32` so the same
template can later be reused at another type.
