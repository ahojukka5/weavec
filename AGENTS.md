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
   story and follows `CONTRIBUTING.md`.
8. Open a non-draft pull request only after the branch is ready for human review.

## Validation and reporting

Run the smallest relevant checks while developing and the repository-required
qualification before declaring a pull request ready. Do not invoke or wait for
GitHub Actions when the project workflow says they are unavailable; report the
local evidence and any checks the reviewer must run.

Always provide the direct pull-request link. State honestly which validation was
run, which could not be run, and whether the branch contains exactly the intended
commits and files.
