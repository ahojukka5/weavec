# Development builds

Normal development in this repository builds only the final `weavec` compiler.
It must not clone or build `weavec0`, `weavec1`, or `weavec-bootstrap` as an
implicit side effect.

## Canonical entrypoints

Repository automation lives under `scripts/`:

```sh
scripts/build.sh
scripts/test-all.sh
scripts/selfhost.sh
```

The root `build.sh`, `test-all.sh`, and `selfhost.sh` paths are compatibility
symlinks. New documentation and automation should use the canonical paths.

## Released lower-stage SDKs

`scripts/build.sh` consumes two versioned release packages:

- `weavec1`, which translates WIR core version 2 to LLVM IR;
- `weavec-bootstrap`, which lowers the compiler's surface sources to WIR.

The build selects a package suffix from the current host:

| Host | Package suffix |
|---|---|
| Linux x86-64 with glibc | `linux-x86_64-glibc` |
| Linux x86-64 with musl | `linux-x86_64-musl` |
| macOS Apple silicon | `macos-arm64` |
| macOS Intel | `macos-x86_64` |

Downloaded archives and `SHA256SUMS` are verified and cached under
`build/vendor/` and `build/downloads/`.

An unavailable package is a release dependency failure. The final-compiler build
does not fall back to source checkouts or reconstruct the bootstrap chain.
Creating and publishing a missing lower-stage package belongs to the relevant
lower-stage repository and release process.

## Explicit SDK paths

A local or pre-extracted SDK can be supplied without changing the source tree:

```sh
WEAVEC1_SDK=/path/to/weavec1-sdk \
WEAVEC_BOOTSTRAP_SDK=/path/to/weavec-bootstrap-sdk \
  scripts/build.sh
```

The expected contents are:

```text
weavec1 SDK/
└── bin/weavec1

weavec-bootstrap SDK/
├── bin/weavec-bootstrap
└── bin/weavec-bootstrap-cat
```

The bootstrap compiler uses its own parser while lowering the source tree, but
`scripts/build.sh` does not link lower-stage parser bitcode into final `weavec`.
The final parser is compiled from `src/parser/*.weave` in the ordinary compiler
source manifest.

`WEAVEC_BACKEND=/path/to/weavec` may explicitly replace the Stage 1 backend for
compiler-development experiments. It is never selected from stale self-host
outputs automatically.

## Testing without rebuilding

The full test ladder builds the final compiler from released SDKs before running
tests:

```sh
scripts/test-all.sh
```

To test an existing `build/weavec` without downloading dependencies or rebuilding
the compiler:

```sh
scripts/test-all.sh --no-build
```

`--no-build` fails if `build/weavec` is absent. It does not silently build a
compiler.

## Self-host qualification

After the SDK-built seed is available, run:

```sh
scripts/selfhost.sh
```

This builds two generations with `weavec` itself, verifies their fixed point, and
runs the stage-two correctness and protocol suites. Self-hosting validates the
final compiler; it does not rebuild earlier repositories.

## Lower-stage maintenance

A complete bootstrap-chain rebuild remains useful when preparing or auditing a
lower-stage release. That workflow must be explicit and owned by the lower-stage
repositories. It is intentionally not an option or fallback in the ordinary
`weavec` development build.
