# Agent instructions for weavec

These instructions apply to automated agents and connector-backed workflows in
this repository. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before changing code,
documentation, branches, commits, issues, or pull requests.

## Mandatory branch safety

The default branch is protected working history, not a staging area.

- Never create, update, delete, or temporarily replace a file on `master`,
  `main`, or whatever branch GitHub reports as the repository default.
- Never omit the target branch from a connector write. An omitted branch usually
  means the default branch and must be treated as an unsafe request.
- Before the first write, resolve the current default-branch head, create a
  dedicated `agent/<description>` branch from that exact commit, and verify that
  the branch exists.
- Every contents, blob/tree, commit, ref, or file mutation must explicitly name
  the feature branch or be connected to a commit whose only parent is the
  intended feature-branch base.
- Do not create a branch by first writing a marker or placeholder file. Use the
  branch or ref API directly.
- If branch creation or branch lookup fails, stop. Do not retry the same write
  without a branch and do not fall back to the default branch.
- A reversible, temporary, empty, or no-net-content write to the default branch
  is still a direct write and is forbidden.
- Never force-update the default branch. Force-update a feature branch only when
  its history must be cleaned before review and repository rules permit it.

If an accidental default-branch write occurs, stop all writes immediately,
record the exact commit and affected paths, and report it. Do not stack more
direct default-branch commits in an attempt to hide or repair the mistake. Use a
normal reviewed revert when content must be restored, or ask the repository owner
to repair protected history.

## Publishing safely

Prefer local `git` for substantial or multi-file work. Connector file APIs are
appropriate only when the complete payload is known to fit and can be verified.

1. Read the current default branch and relevant repository instructions.
2. Create a focused feature branch before making any mutation.
3. Keep unrelated documentation, cleanup, refactoring, behavior, and generated
   output out of the branch.
4. Validate large generated blobs or module payloads after publication. A
   truncated payload is a failed publication, not a partial success.
5. If a connector has a payload limit, switch to a local clone and ordinary
   `git` commit/push workflow. Do not split production source merely to satisfy a
   transport limitation unless that split is independently good architecture.
6. Inspect the complete base-to-head diff and commit list.
7. Rewrite or squash feature-branch history so each commit tells one logical
   story and follows `CONTRIBUTING.md`. For the common case of collapsing an
   over-split branch into one commit, `git reset --soft origin/master`
   followed by a single `git commit` is simpler than an interactive rebase.
8. Open a non-draft pull request only after the branch is ready for human review.

When force-pushing a rewritten branch, fetch its actual branch name first
(`git fetch origin <branch-name>`) rather than relying on a ref you only
checked out as `refs/pull/<n>/head` — `--force-with-lease`'s stale-tip check
has nothing current to compare against otherwise, and rejects the push with
"stale info" even when nothing changed remotely.

## Validation and reporting

Run the smallest relevant checks while developing and the repository-required
qualification before declaring a pull request ready. Do not invoke or wait for
GitHub Actions when the project workflow says they are unavailable; report the
local evidence and any checks the reviewer must run.

Always provide the direct pull-request link. State honestly which validation was
run, which could not be run, and whether the branch contains exactly the intended
commits and files.

## CI completion gate

Pull-request CI is the file-based contract smoke, commit-message lint, and a
GitHub-hosted compile of `weavec` plus the fast behavioral suites. The full
ladder and deep self-host run only after merge, on `master`.

A task is not complete while a required pull-request check for the exact
current head is queued, pending, in progress, cancelled, timed out, or failing.

- Keep the pull request in draft while those PR checks are unresolved or
  red.
- A red or cancelled PR check is unfinished work. Inspect its logs, fix the
  underlying code, test, workflow, or runner interaction, and trigger fresh
  validation for the exact corrected head.
- Continue until every required PR check is green. A red PR check is
  unfinished work, not a status that can be explained away or handed to the
  reviewer.
- After every history rewrite or force-push, discard earlier PR-check evidence
  and wait for the new exact head.
- Mark the pull request ready for review only after the PR checks are
  green and the branch history and validation summary are final.
- Do not wait for the full ladder or deep self-host on a pull request. If
  post-merge `master` CI fails, open a follow-up fix.
- If GitHub-hosted PR infrastructure is unavailable, keep the pull request in
  draft and report the concrete blocker. Do not claim the task or pull request
  is ready.

## Reviewing and merging a pull request

Reviewing a PR opened by another agent or contributor is a separate
responsibility from opening your own, with failure modes learned from this
repository's own history.

- A PR's own local validation — especially a hand-built harness with stubbed
  tools (fake `clang`, `uname`, `otool`, etc.) — proves the change is
  consistent with its author's assumptions, not that those assumptions are
  correct. Reproduce the claim against the real toolchain or real CI before
  trusting it; a stub written to match a premise cannot refute that premise.
- Verify any factual claim about an external dependency directly (e.g.
  `gh release view <tag> --json assets`) rather than accepting it from the
  PR description or its test fixtures. A version-pin change justified by
  "the new release doesn't have X" needs that checked, not assumed.
- When a PR removes or replaces a code path (a fallback, a deprecated flag,
  an old dependency mode), search the whole repository for other places
  that still assert or depend on the old behavior — docs, error messages,
  and especially CI workflows. A CI step that greps for a log line the new
  code no longer prints, or an env var the new code no longer reads, is
  broken infrastructure, not stale prose, and only surfaces when someone
  runs it.
- Passing checks make a PR mergeable, not correct. If hands-on review shows
  the PR's stated problem does not actually exist, do not merge a
  working-but-unnecessary change out of politeness — close it and attach
  the concrete evidence that disproves the premise.
- Before merging, rewrite the branch's commit history per
  [`CONTRIBUTING.md`](CONTRIBUTING.md) in both directions: split commits
  that mix unrelated work, and squash commits that were only split by
  authorship mechanics (iterative fixup commits correcting the same
  not-yet-merged branch's own earlier mistake, for example) rather than
  leaving a debugging trail in the merged history.
- A green test suite for a new script or entry point does not prove the
  assembled pipeline works — each helper function can pass its own unit
  tests while the wiring between them is wrong. If a PR adds a new entry
  point (a script, a CLI flag, a build/test/selfhost step) and the suite
  never actually invokes it end-to-end, run it yourself before trusting
  the suite.
- A local failure that doesn't reproduce in the PR's actual CI may be an
  environment gap (an older LLVM/clang on your machine, a missing
  toolchain component) rather than a defect in the change. If CI is green
  on the real target matrix, don't block the merge on it — but don't stay
  silent either; note the gap explicitly so a real version dependency
  isn't hidden.
- Regenerated fixtures (LLVM goldens, `--regen-goldens` output) are the one
  category of tracked file expected to conflict across concurrent PRs. If
  rebasing produces a conflict only in golden files, don't hand-splice the
  diff — regenerate them fresh against the merged base and verify the
  regeneration step itself produced the result, rather than reconstructing
  what you assume the tool would have written.
