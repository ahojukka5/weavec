# Build manifests

`weavec` uses two different manifest formats for two different purposes:

1. `weavec-build-manifest-v1` describes one invocation of `weavec build`.
2. `BUILD-MANIFEST` inside a release archive describes the packaged compiler.

They are intentionally distinct. The JSON build manifest is a versioned
automation protocol; the package manifest is installation metadata for a release
artifact.

## `weavec-build-manifest-v1`

Request a JSON build manifest with:

```sh
weavec build main.weave -o main --manifest-json main.build.json
```

A representative successful document is:

```json
{
  "format": "weavec-build-manifest-v1",
  "status": "succeeded",
  "phase": "complete",
  "target": "x86_64-unknown-linux-gnu",
  "compiler": "/opt/weavec/bin/weavec",
  "runtime": "/opt/weavec/lib/weavec/x86_64-unknown-linux-gnu/libweave-runtime.a",
  "codegen": "clang",
  "linker": "clang",
  "output": "main",
  "sources": ["main.weave"]
}
```

The document is written for both successful and failed builds when the driver can
open the requested manifest path.

### Fields

| Field | Type | Meaning |
|---|---|---|
| `format` | string | Always `weavec-build-manifest-v1`. |
| `status` | string | `succeeded` or `failed`. |
| `phase` | string | Last completed or failed build phase. |
| `target` | string | Selected installed target triple. |
| `compiler` | string | Resolved compiler executable path. |
| `runtime` | string | Resolved private runtime resource. |
| `codegen` | string | LLVM IR to object command. |
| `linker` | string | Final target linker command. |
| `output` | string | Requested executable path. |
| `sources` | array of strings | Ordered source arguments. |

### Phase values

Current phase values are:

| Phase | Meaning |
|---|---|
| `frontend` | Surface source to WIR failed. |
| `backend` | WIR to LLVM failed. |
| `codegen` | LLVM IR to object generation failed. |
| `link` | Target linker failed. |
| `publish` | Atomic rename to the requested output failed. |
| `complete` | The executable was published successfully. |

The diagnostics facade maps these internal phases to the stable public exit codes
documented in [Machine-readable diagnostics](diagnostics.md).

### Path and reproducibility notes

The manifest records the concrete paths and command names used by that build. It
therefore describes what happened; it does not claim that absolute paths are
portable across machines.

For reproducible automation, consumers should retain:

- the compiler release or source commit;
- the selected target package;
- the manifest itself;
- the ordered source inputs and their own content hashes;
- any explicit codegen, linker, or runtime overrides.

The current schema does not include source hashes or tool version output. Adding
new required fields would require a new manifest format version.

## Relationship to diagnostics

A build may request both protocols:

```sh
weavec build main.weave -o main \
  --manifest-json main.build.json \
  --diagnostics-json main.diagnostics.json
```

The two paths must be different.

- The manifest describes build provenance and the final phase.
- The diagnostics document describes errors, stable public exit codes, and source
  spans.

On success, diagnostics contains an empty diagnostic list while the manifest
still records the concrete compiler, target, runtime, code generator, linker,
output, and sources.

## Release-package `BUILD-MANIFEST`

Every Linux compiler archive includes a line-oriented file named
`BUILD-MANIFEST`. A representative file is:

```text
name=weavec
version=v0.3.0
platform=linux-x86_64
libc=glibc
target=x86_64-unknown-linux-gnu
compiler=bin/weavec
runtime=lib/weavec/x86_64-unknown-linux-gnu/libweave-runtime.a
weavec1_version=v0.3.1
weavec_bootstrap_version=v0.3.0
source_commit=<commit>
compiler_linkage=static
runtime_visibility=private
build_manifest_format=weavec-build-manifest-v1
diagnostics_format=weavec-diagnostics-v1
```

This file identifies the package layout and compiler-chain dependencies. It is
not emitted by `weavec build`, and it is not JSON.

Release validation checks that the archived compiler is static, the runtime path
exists, and the exact packaged compiler can produce and run a native program
while emitting the declared automation formats.
