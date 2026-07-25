# Releasing weavec

`weavec` publishes static Linux x86-64 compiler archives for glibc and musl.
Release packages contain the final user-facing compiler and its private target
runtime. Bootstrap SDKs remain separate implementation dependencies.

## Version

`VERSION` contains the release version without the `v` prefix:

```text
VERSION: 0.3.0
tag:     v0.3.0
```

Do not publish release assets from a different commit than the tag or release
target. The archive manifest, compiler binary, private runtime, checksums, and
GitHub tag must all identify the same source commit.

## Package layout

```text
weavec-vX.Y.Z-linux-x86_64-<libc>/
├── bin/
│   └── weavec
├── lib/
│   └── weavec/
│       └── <target>/
│           └── libweave-runtime.a
├── BUILD-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

The compiler is statically linked for the selected libc. Normal users build a
native executable with one command:

```sh
weavec build main.weave -o main
```

The compiler internally owns surface lowering, WIR emission, LLVM IR to object
code generation, target linking, private runtime selection, and atomic output
publication. Users do not provide the runtime path or invoke LLVM tools for the
normal build flow.

Low-level `--frontend` and `--backend` modes remain available for bootstrap,
compiler development, and explicit intermediate-output workflows.

## Local packaging

GitHub Actions are not required for a release. Build and validate both libc
variants on a Linux x86-64 host with the required toolchain and network access
to the pinned bootstrap SDK releases.

For glibc:

```sh
rm -rf build dist
WEAVEC1_LIBC=glibc WEAVEC_BOOTSTRAP_LIBC=glibc ./build.sh
./test-all.sh
bash scripts/package-linux-release.sh glibc v0.3.0 dist
```

For musl, start from a clean build directory so no glibc object or dependency
selection can leak into the archive:

```sh
rm -rf build
WEAVEC1_LIBC=musl WEAVEC_BOOTSTRAP_LIBC=musl ./build.sh
./test-all.sh
bash scripts/package-linux-release.sh musl v0.3.0 dist
```

The package script must validate the exact archived compiler, not merely the
unpackaged build tree. Required checks are:

1. compile `build/weavec.bc` to an object;
2. link a static glibc or musl compiler with `runtime/portable.c`;
3. reject any ELF interpreter or dynamic dependency;
4. include the private target runtime under `lib/weavec/<target>/`;
5. run installed-binary frontend and backend smokes;
6. build and run a native executable through `weavec build`;
7. verify emitted LLVM IR with `llvm-as`;
8. verify that removed implicit backend syntax remains rejected;
9. request `weavec-build-manifest-v1` and `weavec-diagnostics-v1` outputs;
10. verify frontend and backend failure exit codes and diagnostics spans;
11. prove failed builds do not publish an executable;
12. strip the compiler and repeat the installed-package smokes;
13. write `BUILD-MANIFEST` and the final archive.

Create checksums only after both archives have passed all checks:

```sh
(
  cd dist
  sha256sum \
    weavec-v0.3.0-linux-x86_64-glibc.tar.gz \
    weavec-v0.3.0-linux-x86_64-musl.tar.gz \
    > SHA256SUMS
  sha256sum --check SHA256SUMS
)
```

## Publication

When GitHub Actions capacity is available, `.github/workflows/release.yml` can
build and publish the same artifacts for a `v*` tag or an eligible `master`
push.

When Actions capacity is unavailable, publish deliberately from a validated
local build host:

```sh
git tag -s v0.3.0 <release-commit>
git push origin v0.3.0

gh release create v0.3.0 \
  dist/weavec-v0.3.0-linux-x86_64-glibc.tar.gz \
  dist/weavec-v0.3.0-linux-x86_64-musl.tar.gz \
  dist/SHA256SUMS \
  --target <release-commit> \
  --generate-notes \
  --title "weavec v0.3.0"
```

After publication, download every release asset into a fresh directory, verify
`SHA256SUMS`, extract both archives, and repeat the source-to-executable and
failure-diagnostics smokes from the downloaded assets.

## Release gate

Before merging the release-preparation branch or creating the tag:

1. verify the normal glibc, musl, and macOS compiler ladders;
2. verify both static release archives from clean libc-specific builds;
3. run `./selfhost.sh` because frontend/backend generation changed in 0.3.0;
4. confirm `VERSION`, changelog, README, and this document agree;
5. confirm the package manifest records the intended bootstrap versions;
6. verify `weavec build`, `weavec-build-manifest-v1`, and
   `weavec-diagnostics-v1` from the extracted packages;
7. verify release checksums from a fresh download;
8. update downstream documentation to require `weavec >= 0.3.0` only after the
   release assets exist.
