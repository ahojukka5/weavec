# Releasing weavec

`weavec` publishes static Linux x86-64 compiler archives for glibc and musl.
Release packages contain the final user-facing compiler only; the bootstrap SDKs
remain separate implementation dependencies.

## Version

`VERSION` contains the release version without the `v` prefix:

```text
VERSION: 0.2.0
tag:     v0.2.0
```

## Package layout

```text
weavec-vX.Y.Z-linux-x86_64-<libc>/
├── bin/
│   └── weavec
├── BUILD-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

The compiler is statically linked for the selected libc. It does not require the
bootstrap repositories, SDKs, Python, or LLVM to run. LLVM tools are still
needed when the user wants to assemble or link the emitted LLVM IR.

## Local packaging

Build and test the matching SDK variant first:

```sh
WEAVEC1_LIBC=glibc WEAVEC_BOOTSTRAP_LIBC=glibc ./build.sh
./test-all.sh
bash scripts/package-linux-release.sh glibc v0.2.0 dist
```

For musl:

```sh
WEAVEC1_LIBC=musl WEAVEC_BOOTSTRAP_LIBC=musl ./build.sh
./test-all.sh
bash scripts/package-linux-release.sh musl v0.2.0 dist
```

The package script:

1. compiles `build/weavec.bc` to an object;
2. links a static glibc or musl executable with `runtime/portable.c`;
3. rejects any ELF interpreter;
4. runs installed-binary frontend and backend smoke tests;
5. verifies emitted LLVM IR with `llvm-as`;
6. verifies that the removed implicit backend syntax remains rejected;
7. strips the compiler and repeats the backend smoke;
8. writes `BUILD-MANIFEST` and the archive.

## CI and publication

`.github/workflows/release.yml` builds both Linux variants for pull requests,
`master`, explicit tags, and manual dispatches. Pull requests publish temporary
workflow artifacts only.

A successful push to `master` creates the release selected by `VERSION` when it
does not already exist. Each release contains:

- `weavec-vX.Y.Z-linux-x86_64-glibc.tar.gz`;
- `weavec-vX.Y.Z-linux-x86_64-musl.tar.gz`;
- `SHA256SUMS`.

An explicit `v*` tag run may replace the assets for that same tag. Ordinary
`master` runs leave an existing VERSION release immutable.

Before changing `VERSION`:

1. verify the normal glibc, musl, and macOS CI matrix;
2. verify both static release-package jobs;
3. run `./selfhost.sh` when frontend or backend generation changed;
4. update `CHANGELOG.md`, README, and this document;
5. confirm the package manifest records the intended bootstrap versions;
6. update downstream documentation only after release assets and checksums
   exist.
