# Contributing to weavec2

`weavec2` is the self-hosted compiler written in surface Weave. It combines
surface lowering and WIR-to-LLVM emission, while the lower repositories remain
the reproducible bootstrap path.

## Principles

- **WIR is the backend boundary.** Do not extend WIR from this repository. A WIR
  change must be coordinated with `weavec0` and `weavec1` first.
- **Surface Weave evolves here.** New surface forms, contracts, structs, and
  quantum rewrites belong in `src/frontend/` when they lower to admitted WIR.
- **No feature without a test.** Add an appropriate correctness, performance,
  quantum, or self-host fixture.
- **Review LLVM goldens.** Regenerate performance output only after an
  intentional backend change and inspect the complete diff.
- **Keep self-hosting green.** The basic self-host gate must always pass.
  Changes to combined lowering, source ordering, or code generation should also
  run the deeper `./selfhost.sh` flow.
- **Preserve deterministic source ordering.** `build.sh`, `selfhost.sh`, and
  multifile lowering must agree about the compiler source sequence.

## What does not belong here

- New WIR primitives added only for a surface feature.
- Uncoordinated changes to Stage 0 runtime externs.
- Production quantum-runtime behavior in the current test stub.
- High-level features that cannot be expressed through the documented surface
  and WIR contracts.

A new runtime extern must be released through Stage 0, propagated through the
Stage 1 SDK, and then adopted by the source bootstrap here.

## Development workflow

1. Create a focused branch.
2. Edit the relevant `src/**/*.weave` modules.
3. Add or update fixtures under:
   - `test/correctness/`;
   - `test/performance/`;
   - `test/quantum/`;
   - `test/selfhost/`.
4. Run:

   ```sh
   ./build.sh
   ./test-all.sh
   ```

5. For backend output changes, regenerate and review performance goldens:

   ```sh
   ./test/performance/regen-golden.sh
   git diff -- test/performance
   ```

6. For frontend, source-order, or self-host changes, run:

   ```sh
   ./selfhost.sh
   ```

7. Update README, changelog, CI comments, and relevant design documents when a
   public contract or build assumption changes.
8. Open a pull request.

Normal CI runs the full ladder on Linux and macOS. The deeper self-host flow is
local-only because it rebuilds the compiler through multiple generations.

## Dependency changes

The current build consumes pinned source releases because it needs frontend
parser LLVM modules that are not yet distributed in an SDK.

When changing `WEAVEC0_TAG`, `WEAVEC1_TAG`, or `WEAVEFRONT_TAG`:

- verify the release exists;
- delete the corresponding cached vendor directory;
- run the complete ladder on Linux and macOS;
- run deeper self-hosting when compiler output or frontend modules changed;
- document why the pin changed.

## Licensing

By submitting a contribution, you agree that it is licensed under the Apache
License, Version 2.0. See [`LICENSE`](LICENSE).
