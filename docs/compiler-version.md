# Compiler version identity

Every `weavec` executable identifies the exact compiler build used for native
compilation and audit evidence:

```sh
weavec --version
```

A release build prints its semantic release tag:

```text
weavec v0.3.0
```

A development build prints the release base plus the source Git commit:

```text
weavec v0.3.0+git.b7046aacc634
```

A build made from modified tracked files appends `.dirty`. Build directories and
other untracked files do not change the identity.

## Resolution rules

The build reads the release base from the repository-root `VERSION` file. A clean
commit whose exact Git tag equals that base is a release build. Every other Git
worktree build is a development build containing the 12-character commit SHA.
Source archives without Git metadata use the base release version.

`WEAVEC_VERSION_OVERRIDE` may set an explicit package identity:

```sh
WEAVEC_VERSION_OVERRIDE=v0.3.0 ./build.sh
```

The override and `VERSION` file must match
`vMAJOR.MINOR.PATCH` with an optional SemVer-style `-` or `+` suffix. Invalid
values fail the build before reaching the C preprocessor.

## Reproducibility contract

The identity is embedded while linking the compiler; `--version` does not inspect
the current repository at runtime. Moving the executable or changing the source
tree later cannot change what the binary reports.

The seed compiler and both self-hosted generations receive the same identity.
Self-host validation rejects a stage executable when its reported version differs
from the build identity. Release packaging should pass the release tag explicitly
or build from the matching clean tag, then verify the packaged compiler output.

External tools should record both `weavec --version` and the compiler binary
SHA-256. The version names the source lineage, while the binary hash distinguishes
builds produced with different hosts or toolchains.
