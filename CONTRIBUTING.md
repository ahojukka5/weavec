# Contributing to weavec

`weavec` is the user-facing self-hosted compiler written primarily in surface
Weave. It combines surface lowering, analysis, WIR v2 to LLVM emission, native
build orchestration, diagnostics, and package runtime discovery.

The reproducible bootstrap path is:

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

Read [`docs/index.md`](docs/index.md) and
[`docs/architecture.md`](docs/architecture.md) before changing compiler
boundaries.

## Principles

- **WIR v2 is the backend boundary.** Coordinate WIR changes with the lower
  compiler chain; do not add a private `weavec` dialect.
- **Surface Weave evolves here.** New surface forms, contracts, structs, quantum
  rewrites, and user-facing compiler behavior belong in this repository when
  they lower through the admitted WIR contract.
- **No feature without a regression.** Add correctness, performance, quantum,
  diagnostics, package, or self-host coverage matching the changed boundary.
- **Review LLVM goldens.** Regenerate them only after intentional backend-output
  changes and inspect the complete diff.
- **Keep self-hosting green.** The normal ladder and deep two-generation
  self-host job are permanent gates.
- **Preserve deterministic source ordering.** `build.sh` and `selfhost.sh` must
  list compiler modules in the same order.
- **Keep bootstrap boundaries named.** Consume `weavec-bootstrap` through its
  command, multifile driver, and `libweave-sexpr.bc`; do not depend on private
  generated parser modules.
- **Prefer published SDKs.** The normal Linux build must remain reproducible from
  release archives and checksums without source-repository side effects.
- **Keep runtime ownership explicit.** Compiler host support and the private
  target program runtime are separate responsibilities.
- **Version automation contracts deliberately.** Incompatible manifest or
  diagnostics changes require a new format identifier.
- **Keep documentation navigable.** Files under `docs/` use lowercase kebab-case
  names, and current local links must resolve.

## What does not belong here

- WIR primitives added only to make one surface feature convenient.
- Uncoordinated changes to Stage 0 runtime externs or Stage 1 backend contracts.
- General maintenance of the frozen `weavec-bootstrap` frontend.
- Production quantum-runtime behavior hidden inside the current test stub.
- Features that cannot be expressed through documented surface and WIR
  boundaries.
- Compatibility aliases for the retired `weavec2` or `weavefront` names.
- Speculative syntax presented as implemented reference material.

A new runtime extern must be released through the required lower-stage boundary,
propagated through the Stage 1 SDK, and then adopted by `weavec`.

## Development workflow

1. Create a focused branch.
2. Read the relevant architecture, command, language, diagnostics, manifest,
   runtime, or backend contract document.
3. Make the smallest coherent change.
4. Add or update fixtures under the relevant test tree.
5. Run the normal ladder:

   ```sh
   ./build.sh
   ./test-all.sh
   ```

6. For frontend, backend, source-order, parser-boundary, or compiler-generation
   changes, also run:

   ```sh
   ./selfhost.sh
   ```

7. For intentional performance LLVM changes:

   ```sh
   ./test/performance/regen-golden.sh
   git diff -- test/performance
   ```

8. Update the README, changelog, and every affected reference or design
   document.
9. Inspect the complete diff and open a focused pull request.

CI runs the normal ladder with Linux glibc SDKs, Linux musl SDKs, and the macOS
source fallback. The deep-selfhost CI job builds the seed first, then verifies
stage-one and stage-two self-hosted compilers.

## Documentation-only changes

Documentation changes must not silently redefine compiler behavior. Ground
reference material in current source, tests, package scripts, and released
protocols.

For a documentation-only pull request:

- do not edit `src/`, `runtime/`, build scripts, test scripts, or workflows unless
  the scope is explicitly expanded;
- use lowercase kebab-case names under `docs/`;
- update all local links when moving a document;
- distinguish implemented behavior, current limitations, historical notes, and
  future proposals;
- avoid workspace-specific paths or commands that assume sibling repositories;
- record meaningful structural documentation changes under `Unreleased`.

The normal compiler workflows remain useful evidence that documentation-only
renames did not accidentally alter tracked executable files, but no compiler
rebuild is required merely to prove Markdown prose compiles.

## Dependency controls

The canonical controls are:

- `WEAVEC1_VERSION` and `WEAVEC1_LIBC` — published Stage 1 SDK;
- `WEAVEC1_SDK` — extracted local Stage 1 SDK;
- `WEAVEC_BOOTSTRAP_VERSION` and `WEAVEC_BOOTSTRAP_LIBC` — published bootstrap
  SDK;
- `WEAVEC_BOOTSTRAP_SDK` — extracted local bootstrap SDK;
- `WEAVEC1`, `WEAVEC1_TAG`, `WEAVEC_BOOTSTRAP`, and
  `WEAVEC_BOOTSTRAP_REF` — explicit source fallbacks;
- `WEAVEC0` and `WEAVEC0_TAG` — Stage 0 source fallback controls;
- `WEAVEC_BACKEND` — existing self-hosted backend executable.

When changing an SDK pin:

- verify the release provides both required libc archives and `SHA256SUMS`;
- inspect `SDK-MANIFEST` for required commands and library paths;
- run the complete glibc, musl, and macOS matrix;
- run deep self-hosting when compiler output or frontend modules changed;
- document why the pin changed;
- update architecture and release documents when the dependency contract changes.

Stage 0 controls matter only when the Stage 1 source fallback is required.

## Public interface changes

Changes to any of the following require documentation and regression coverage:

- `weavec build` command syntax or phase behavior;
- low-level frontend/backend modes;
- surface language syntax or semantics;
- `weavec-build-manifest-v1`;
- `weavec-diagnostics-v1` and stable public exit codes;
- private runtime discovery or target layout;
- package `BUILD-MANIFEST`;
- source ordering or self-host generation rules.

See:

- [`docs/command-reference.md`](docs/command-reference.md)
- [`docs/language-reference.md`](docs/language-reference.md)
- [`docs/build-manifest.md`](docs/build-manifest.md)
- [`docs/diagnostics.md`](docs/diagnostics.md)
- [`docs/releasing.md`](docs/releasing.md)

## Licensing

By submitting a contribution, you agree that it is licensed under the Apache
License, Version 2.0. See [`LICENSE`](LICENSE).
