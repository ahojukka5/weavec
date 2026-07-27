# Standalone dead-code elimination

`weavec build` produces a standalone executable. Only `main` is a public source
entry point in that product mode; other source functions are implementation
details unless future language syntax explicitly exports them.

The build pipeline therefore applies two complementary policies before publishing
the native executable:

1. Raw source-function definitions other than `main` are marked with LLVM
   `internal` linkage before optimization. This allows inlining, constant folding,
   and global dead-code elimination to remove functions that no longer have a
   reachable caller.
2. The final link uses function/data sections and linker section garbage
   collection. Unused private-runtime helpers and their otherwise unnecessary
   imports are excluded from the executable.

The low-level `--backend` interface remains unchanged. Internalization belongs to
the executable-oriented `build` pipeline because library/export semantics have not
yet been introduced.

`test/optimization-evidence/test.sh` verifies this contract with Fibonacci: after
`main` is folded to return 55 directly, neither `fib` nor the unused runtime
contract-failure helper may remain in optimized LLVM, target assembly, or linked
disassembly.
