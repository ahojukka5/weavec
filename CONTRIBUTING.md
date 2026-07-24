# Contributing to weavec

`weavec` is the user-facing self-hosted compiler written in surface Weave. It
combines surface lowering and WIR-to-LLVM emission. `weavec0`, `weavec1`, and
`weavec-bootstrap` form the reproducible bootstrap path.

## Principles

- **WIR is the backend boundary.** Coordinate WIR changes with `weavec0` and
  `weavec1`; do not add a private WIR dialect here.
- **Surface Weave evolves here.** New surface forms, contracts, structs, and
  quantum rewrites belong in `src/frontend/` when they lower to admitted WIR.
- **No feature without a test.** Add the relevant correctness, performance,
  quantum, or self-host fixture.
- **Review LLVM goldens.** Regenerate them only after an intentional backend
  change and inspect the complete diff.
- **Keep self-hosting green.** The basic self-host gate must always pass. Changes
  to source ordering, combined lowering, or backend generation should also run
  `./selfhost.sh`.
- **Preserve deterministic source ordering.** `build.sh` and `selfhost.sh` must
  list compiler modules in the same order.
- **Keep bootstrap boundaries named.** Consume `weavec-bootstrap` through its
  command, multifile driver, and `libweave-sexpr.bc`; do not depend on private
  generated `.ll` files.

## What does not belong here

- WIR primitives added only for a surface feature.
- Uncoordinated changes to Stage 0 runtime externs.
- General bootstrap-frontend maintenance that belongs in `weavec-bootstrap`.
- Production quantum-runtime behavior in the current test stub.
- Features that cannot be expressed through the documented surface and WIR
  contracts.

A new runtime extern must be released through Stage 0, propagated through the
Stage 1 SDK, and then adopted here.

## Development workflow

1. Create a focused branch.
2. Edit the relevant `src/**/*.weave` modules.
3. Add or update fixtures under `test/correctness/`, `test/performance/`,
   `test/quantum/`, or `test/selfhost/`.
4. Run:

   ```sh
   ./build.sh
   ./test-all.sh
   ```

5. For intentional backend-output changes:

   ```sh
   ./test/performance/regen-golden.sh
   git diff -- test/performance
   ```

6. For frontend, source-order, parser-boundary, or self-host changes:

   ```sh
   ./selfhost.sh
   ```

7. Update README, changelog, CI comments, and the relevant design documents.
8. Open a pull request.

Normal CI runs the full ladder on Linux and macOS. The deeper self-host flow is
local-only because it rebuilds the compiler through multiple generations.

## Dependency changes

The canonical dependency controls are:

- `WEAVEC0_TAG` — Stage 0 release;
- `WEAVEC1_TAG` — Stage 1 release;
- `WEAVEC_BOOTSTRAP_REF` — exact bootstrap-frontend tag or commit;
- `WEAVEC_BACKEND` — an existing self-hosted backend executable.

When changing a pin:

- verify the release, tag, or commit exists;
- clear the corresponding vendor cache when necessary;
- run the complete Linux and macOS ladder;
- run deeper self-hosting when compiler output or frontend modules changed;
- document the dependency reason.

No `weavec2`, `weavefront`, `WEAVEC_*`, or `WEAVEFRONT_*` compatibility
interfaces are maintained in current code.

## Licensing

By submitting a contribution, you agree that it is licensed under the Apache
License, Version 2.0. See [`LICENSE`](LICENSE).
