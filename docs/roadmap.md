# Application-language roadmap

`weavec` has a mature compiler-product foundation: reproducible self-hosting,
WIR-v2 frontend/backend compatibility, native builds, deterministic formatting,
structured diagnostics, manifests, compilation traces, semantic indexing,
release packages, and deep fixed-point qualification.

The next development phase prioritizes the usability of surface Weave for real
programming work. New compiler-observability protocols and WIR-next experiments
remain valuable, but they no longer take precedence over the missing
application-language foundations described here.

## Roadmap epics

### 1. Project manifests and package-ready modules

Issue [#111](https://github.com/ahojukka5/weavec/issues/111) turns the existing
explicit-module semantics into a practical project system. It owns the project
manifest, deterministic source discovery, module graph resolution, entry-module
selection, public type interfaces, project builds, and the later incremental
build boundary.

This is the first implementation epic because every other application-facing
area needs a stable project and module model.

### 2. Structured types, generics, variants, and recoverable errors

Issue [#112](https://github.com/ahojukka5/weavec/issues/112) introduces a
structured semantic type representation and builds explicit generics,
monomorphization, variants, exhaustive `match`, `Option`, `Result`, and error
propagation on top of it.

Recoverable errors use `Result`; absence uses `Option`. Stack-unwinding
exceptions are outside the initial roadmap because they require runtime
unwinding and ownership-aware cleanup semantics that do not yet exist.

### 3. Ergonomic surface and minimum viable standard library

Issue [#113](https://github.com/ahojukka5/weavec/issues/113) makes ordinary
programs practical. It covers high-value control-flow and literal ergonomics,
plus the initial standard-library modules for strings, bytes, vectors, slices,
formatting, command-line arguments, files, paths, processes, and environment
access.

The first milestone targets useful command-line programs rather than a broad
platform framework.

### 4. First-class language testing

Issue [#114](https://github.com/ahojukka5/weavec/issues/114) defines top-level
test declarations, assertions, deterministic discovery, native test-harness
generation, filtering, and a versioned machine-readable result format exposed
through `weavec test`.

The standalone command and test-form skeleton may start early. Project-wide test
discovery depends on #111, and generic test helpers can expand after #112.

### 5. Ownership, borrowing, and deterministic resource safety

Issue [#115](https://github.com/ahojukka5/weavec/issues/115) introduces safety in
stages: explicit safe/unsafe boundaries, move-only owned values, lexical borrows,
deterministic cleanup, non-null references, slices, initialization tracking, and
checked indexing.

The archived `weave-bootstrap` ownership work is design input and a negative-test
corpus, not an implementation to port verbatim. The new implementation must state
and prove the guarantees delivered by each stage before claiming Rust-like
safety.

## Recommended execution order

The roadmap is dependency ordered, but not fully serial:

1. Start #111 with the project-manifest and local module-discovery contract.
2. Start the structured type representation from #112 once public type-interface
   requirements are clear.
3. Start the minimal `weavec test` command and test-declaration contract from #114
   while project discovery is being implemented.
4. Build `Option`, `Result`, variants, and generics before the reusable collection
   and I/O layers of #113.
5. Build ownership qualifiers and cleanup from #115 on the structured type model
   and recoverable-error control flow.

Small, independent surface improvements from #113 may proceed earlier when they
do not pre-empt type, project, or safety decisions.

## Epic and subissue workflow

Epics describe user outcomes, architectural boundaries, non-goals, dependencies,
and final acceptance criteria. They are not implementation pull requests.

Before implementation begins for an epic:

1. Create focused subissues for specification, compiler representation, surface
   lowering, diagnostics, formatting, capability publication, semantic indexing,
   runtime or standard-library support, documentation, and qualification as
   applicable.
2. Link every subissue from the epic using a task list and link the epic from the
   subissue body.
3. Give each subissue one independently reviewable outcome. Do not combine an
   entire epic into one pull request.
4. State whether the subissue changes only surface lowering over WIR v2 or needs
   a coordinated intermediate-format decision.
5. Define positive, negative, determinism, cross-module, package, and self-host
   validation before implementation.
6. Close subissues only after their exact merged default-branch revision has
   passed both CI and release push reporters.

An epic closes only when all required subissues are complete and its user-level
acceptance example works from an extracted release package.

## Compatibility principles

- Prefer surface-language changes that lower through frozen WIR v2.
- Preserve legacy `program` roots and explicit source-list builds until a
  documented migration removes them.
- Keep the compiler as the semantic authority; tools must consume capabilities,
  diagnostics, manifests, traces, and the semantic index instead of inferring
  behavior from filenames or examples.
- Keep canonical forms deterministic and suitable for structural editing and LLM
  generation.
- Extend stable JSON protocols additively or introduce a new version when meaning
  changes.
- Every roadmap slice must preserve bootstrap reproducibility and deep self-host
  fixed-point qualification.

## Deferred work

Issue [#22](https://github.com/ahojukka5/weavec/issues/22) remains the collection
item for a future coordinated WIR source-location version. Its Phase 0
specification and conformance corpus remain useful, but production WIR migration
is deferred while the application-language epics establish practical user value.

Hygienic metaprogramming is also deferred. The archived non-hygienic direct AST
substitution design must not be ported as-is. A future macro design must be
module-scoped, deterministic, source-provenance preserving, inspectable, and
represented in compiler capabilities.
