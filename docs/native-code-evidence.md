# Native optimization and machine-code evidence

`weavec build` has one explicit LLVM optimization and target-code-generation
pipeline. The compiler emits simple, correct raw LLVM; the installed LLVM
implementation performs general scalar, control-flow, loop, and target-specific
optimization.

The current implementation invokes Clang, `llc`, and `llvm-objdump` through the
isolated `runtime/llvm_toolchain.c` adapter. This is an implementation detail. A future
in-process LLVM integration can replace that adapter without changing the
command-line or artifact contracts described here.

## Optimization profiles

The default native build uses portable `O2` optimization:

```sh
weavec build main.weave -o main
```

Maximum-performance inspection for the current machine is explicit:

```sh
weavec build main.weave -o main -O3 --native
```

`--native` selects the current host CPU and tuning model. It can enable
instructions unavailable on another computer, so it is appropriate for local
performance builds and audits, not portable release artifacts.

Supported optimization flags are `-O0`, `-O1`, `-O2`, `-O3`, `-Os`, and `-Oz`.
CPU selection can be stated independently:

```text
--cpu <name>          select the instruction-set CPU
--tune-cpu <name>     select the scheduling/tuning CPU
--native              equivalent to --cpu native --tune-cpu native
--march <name>        familiar alias for --cpu
--mtune <name>        familiar alias for --tune-cpu
```

For IR optimization, the adapter maps CPU selection to Clang `-march` on x86
and `-mcpu` on AArch64. Target code generation uses `llc -mcpu` and `-mtune`.
These mappings are private to the adapter and do not constrain a future LLVM
API implementation.

## Complete evidence capture

The following command captures every stable compiler and native-code artifact:

```sh
weavec build fibonacci.weave -o fibonacci \
  -O3 --native \
  --emit-wir fibonacci.wir \
  --emit-llvm fibonacci.raw.ll \
  --emit-optimized-llvm fibonacci.optimized.ll \
  --emit-assembly fibonacci.s \
  --emit-disassembly fibonacci.disasm \
  --optimization-record fibonacci.opt.yaml \
  --trace-json fibonacci.trace.json \
  --diagnostics-json fibonacci.diagnostics.json \
  --manifest-json fibonacci.build.json \
  --llvm-provenance
```

Expected files:

```text
fibonacci
fibonacci.wir
fibonacci.raw.ll
fibonacci.optimized.ll
fibonacci.s
fibonacci.disasm
fibonacci.opt.yaml
fibonacci.trace.json
fibonacci.diagnostics.json
fibonacci.build.json
```

The artifacts answer different questions:

| Artifact | Question answered |
|---|---|
| `fibonacci.wir` | What semantic program did the frontend produce? |
| `fibonacci.raw.ll` | What LLVM did the self-hosted backend emit? |
| `fibonacci.optimized.ll` | What did LLVM's selected optimization profile retain? |
| `fibonacci.opt.yaml` | Which LLVM optimization and code-generation remarks were emitted? |
| `fibonacci.s` | What target assembly did LLVM select under the profile? |
| `fibonacci.disasm` | What instructions are actually present in the linked executable? |
| build/trace/diagnostics JSON | Which compiler, profile, phases, transformations, and failures produced the evidence? |

The published optimized LLVM is the exact module passed to `llc` for both
assembly and object generation. The target generator does not rerun the LLVM IR
optimization pipeline.

`--emit-llvm` deliberately means **raw backend LLVM**. It is not silently
redefined by optimization. The optimized view is explicitly named because both
views are required to distinguish backend design problems from ordinary
pre-optimization IR.

## Fibonacci: expected transformation

The repository fixture is
`test/optimization-evidence/fibonacci.weave`. It computes `fib(10)` and exits
with status `55`.

The current raw LLVM contains explicit loop-carried state and backend bookkeeping.
Under LLVM 17 on an x86-64 native `O3` profile, the representative structural
instruction count falls from 31 to 12. Exact counts and assembly vary with LLVM
version and CPU, so tests require a real simplification rather than freezing one
host's assembly.

A representative optimized loop is:

```llvm
while.body1:
  %i.phi = phi i32 [ %i.next, %while.body1 ], [ 2, %entry ]
  %curr.phi = phi i32 [ %curr.next, %while.body1 ], [ 1, %entry ]
  %prev.phi = phi i32 [ %curr.phi, %while.body1 ], [ 0, %entry ]
  %curr.next = add i32 %curr.phi, %prev.phi
  %i.next = add i32 %i.phi, 1
  %done = icmp sgt i32 %i.next, %n
  br i1 %done, label %common.ret, label %while.body1
```

A representative x86-64 native loop body is:

```asm
addl  %esi, %ecx
incl  %edx
movl  %esi, %r8d
movl  %ecx, %eax
movl  %ecx, %esi
movl  %r8d, %ecx
cmpl  %edi, %edx
jle   loop
```

The disassembly is the authoritative static result because it is read from the
linked executable rather than predicted from an intermediate file.

## Publication and failure semantics

Artifacts are published by completed phase:

1. WIR after frontend success;
2. raw LLVM after backend success;
3. optimized LLVM after LLVM optimization success;
4. assembly after target assembly emission success;
5. optimization record after object generation success;
6. disassembly after linking success;
7. executable only after every requested artifact and trace succeeds.

A failed phase does not replace an existing destination for that phase. For
example, an optimizer failure preserves newly produced raw LLVM but leaves an
existing optimized-LLVM destination untouched.

All requested output paths must differ.

## What the evidence can and cannot prove

No practical compiler can generally prove that arbitrary machine code is the
unique globally optimal implementation for every input and microarchitectural
state. The evidence pipeline supports a narrower, defensible claim:

> No better code was detected among the tested LLVM profiles, CPU targets,
> static scheduling models, and measured workloads.

The final disassembly establishes what instructions exist. Optimization remarks
explain performed and missed transformations. Later Loupe stages can add
`llvm-mca` modelling and repeated hardware-counter benchmarks. Those dynamic
measurements are required before claiming that one machine-code variant is
faster on real hardware.

## Evaluating custom backend optimizations

Custom backend transformations are judged only after this pipeline exists.
Compare two compiler builds using the same optimization profile and hardware:

1. current backend with the custom transformation;
2. simplified backend without it;
3. optimized LLVM;
4. final disassembly;
5. static and measured performance evidence.

If LLVM produces equivalent optimized IR and machine code without the custom
transformation, the custom complexity should be removed. If it does not, the
remaining difference should be explained through a general semantic or lowering
property—not another source-pattern-specific workaround.
