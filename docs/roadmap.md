# Application-language roadmap

`weavec` has a mature compiler-product foundation: reproducible self-hosting,
WIR-v3 frontend/backend compatibility, native builds, deterministic formatting,
structured diagnostics, manifests, compilation traces, semantic indexing,
release packages, and deep fixed-point qualification.

The next development phase prioritizes the usability of surface Weave for real
programming work. New compiler-observability protocols and WIR-next experiments
remain valuable, but they no longer take precedence over the missing
application-language foundations described here.

Alongside those foundations, the project has one strategic flagship lane:
**compiled declarative rewriting**, with quantum circuit and ZX-calculus
optimization as the first demanding application. That lane must reuse the same
structured type, ownership, determinism, package, and compiler-IR foundations
rather than becoming a parallel language.

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
through `weavec test`. The first-milestone contract is
[Language testing](testing.md).

The standalone command and test-form skeleton may start early. Project-wide test
discovery depends on #111, and generic test helpers can expand after #112.

### 5. Ownership, borrowing, and deterministic resource safety

Issue [#115](https://github.com/ahojukka5/weavec/issues/115) introduces safety in
stages: explicit safe/unsafe boundaries, move-only owned values, lexical borrows,
deterministic cleanup, non-null references, slices, initialization tracking, and
checked indexing.

Concurrency, GPU eligibility, and LLVM `noalias` are requirements on that
model, recorded in
[Ownership requirements for concurrency and GPU](ownership-concurrency.md).
They are specified before implementation so shared-vs-exclusive access is
not retrofitted.

The archived `weave-bootstrap` ownership work is design input and a negative-test
corpus, not an implementation to port verbatim. The new implementation must state
and prove the guarantees delivered by each stage before claiming Rust-like
safety.

### 6. Compiled rewriting and the quantum-compiler flagship

Issue [#455](https://github.com/ahojukka5/weavec/issues/455) makes structured
transformations themselves a programmable compiler capability and uses quantum
circuit / ZX-calculus optimization as the first flagship application.

The reusable capability is not quantum syntax. It is a typed deterministic
rewrite substrate over compiler-owned structured representations with explicit
rule provenance, side conditions, cost functions, and bounded search policy.
Quantum is a demanding proving ground because circuit compilation already relies
on large transformation spaces, graph rewriting, target gate sets, and difficult
rewrite ordering.

The first implementation deliberately avoids public rewrite syntax. It starts
with ordinary Weave data structures and functions, then measures whether the
model is compact and fast enough to justify a later declarative surface.

The bounded sequence is:

1. [#456](https://github.com/ahojukka5/weavec/issues/456) — typed deterministic
   rewrite semantics;
2. [#457](https://github.com/ahojukka5/weavec/issues/457) — circuit IR and
   compiled local rewrites;
3. [#458](https://github.com/ahojukka5/weavec/issues/458) — ZX graph rewrites and
   deterministic circuit extraction;
4. [#459](https://github.com/ahojukka5/weavec/issues/459) — bounded search and
   target/domain packs;
5. [#460](https://github.com/ahojukka5/weavec/issues/460) — frozen benchmark
   against the current Weave quantum path and PyZX.

The flagship does not supersede the HPC trajectory in #310. The shared design
claim is broader: compiled structured transformations should become useful
infrastructure that can later be evaluated outside quantum as well.

See [Compiled rewriting](compiled-rewriting.md) and
[Quantum compiler flagship and current surface support](quantum.md).

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
6. Specify #456 in parallel, but defer deep integration of the quantum rewrite
   flagship until #270 has a real structural compiler boundary and the relevant
   type-graph work no longer erases `Qubit` identity.

Small, independent surface improvements from #113 may proceed earlier when they
do not pre-empt type, project, or safety decisions. The quantum flagship should
likewise begin with standalone data structures and benchmarkable transformation
code rather than coupling itself prematurely to unfinished compiler internals.

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
4. State whether the subissue changes only surface lowering over WIR v3 or needs
   a coordinated intermediate-format decision.
5. Define positive, negative, determinism, cross-module, package, and self-host
   validation before implementation.
6. Close subissues only after their exact merged default-branch revision has
   passed both CI and release push reporters.

An epic closes only when all required subissues are complete and its user-level
acceptance example works from an extracted release package.

## Compatibility principles

- Prefer surface-language changes that lower through existing WIR v3.
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
- Keep domain optimization IR above ordinary WIR unless a coordinated WIR change
  is independently justified; do not create a private quantum WIR dialect.

## Deferred work

Issue [#22](https://github.com/ahojukka5/weavec/issues/22) remains the collection
item for a future coordinated WIR source-location version. Its Phase 0
specification and conformance corpus remain useful, but production WIR migration
is deferred while the application-language epics establish practical user value.

Hygienic metaprogramming is also deferred. The archived non-hygienic direct AST
substitution design must not be ported as-is. A future macro design must be
module-scoped, deterministic, source-provenance preserving, inspectable, and
represented in compiler capabilities. Macros are source-expansion machinery and
must remain distinct from the compiled optimization-rewrite semantics in #455.
