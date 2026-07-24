# weavec performance tests

This directory contains LLVM code shape tests. These tests are not primarily
runtime correctness tests; they compare generated LLVM text with checked-in
expected LLVM so code quality changes are easy to inspect.

- `wir/` contains small WIR inputs chosen for LLVM inspection.
- `expected-llvm/` contains the LLVM text expected from `build/weavec`.

Run from the `weavec` directory:

```bash
./test/performance/test.sh
```

When generated LLVM changes intentionally, inspect the diff first, decide
whether the new LLVM is cleaner or worse, and then update the matching file in
`expected-llvm/`.
