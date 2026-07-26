# Releasing weavec

`weavec` publishes static Linux x86-64 compiler archives for glibc and musl.
Release packages contain the final user-facing compiler and its private target
runtime. Bootstrap SDKs remain separate, checksum-verified implementation
dependencies.

## Version and release commit

`VERSION` contains the release version without a `v` prefix. The Git tag and
archive names add the prefix:

```sh
version="$(tr -d '[:space:]' < VERSION)"
tag="v${version}"
```

Do not publish assets from a different commit than the tag or release target.
The archive manifest, compiler binary, private runtime, checksums, Git tag, and
source commit must identify the same release.

Before preparing a release:

- update `VERSION` only for the intended release;
- move relevant entries from `Unreleased` into the new changelog section;
- confirm the README and reference documents describe the released behavior;
- confirm dependency pins name published lower-stage releases.

## Package layout

```text
weavec-vX.Y.Z-linux-x86_64-<libc>/
├── bin/
│   └── weavec
├── lib/
│   └── weavec/
│       └── <target-triple>/
│           └── libweave-runtime.a
├── BUILD-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

The compiler is statically linked for the selected libc. The target runtime is a
private static archive discovered relative to the installed compiler.

Normal users compile a native program with:

```sh
weavec build main.weave -o main
```

Low-level `--frontend` and `--backend` modes remain available for bootstrap,
compiler development, and explicit intermediate-output workflows.

## Required release inputs

A release build requires:

- the exact `weavec` release commit;
- published `weavec1` and `weavec-bootstrap` SDK releases for glibc and musl;
- `SHA256SUMS` for each dependency release;
- Clang and LLVM tools;
- `musl-gcc` for the musl compiler and runtime package;
- `ar`, `readelf`, `file`, `tar`, and Python 3.

Stage 0 is not part of the normal Linux package build. It is used only if an
explicit or unsupported-host source fallback must build Stage 1.

## Validation before packaging

From a clean checkout, run the complete compiler matrix:

```sh
./build.sh
./test-all.sh
./selfhost.sh
```

CI must pass:

- Linux x86-64 with glibc SDKs;
- Linux x86-64 with musl SDKs;
- macOS with pinned source fallbacks;
- the deep two-generation self-host ladder.

A release must not rely only on unit or low-level compiler tests. The public
source-to-executable product and exact extracted package trees are release gates.

## Local packaging

GitHub Actions are not required for a release. Both libc variants can be built
and validated on a Linux x86-64 host with access to the pinned SDK releases.

Set reusable version variables:

```sh
version="$(tr -d '[:space:]' < VERSION)"
tag="v${version}"
rm -rf dist
mkdir -p dist
```

### glibc

```sh
rm -rf build
WEAVEC1_LIBC=glibc WEAVEC_BOOTSTRAP_LIBC=glibc ./build.sh
./test-all.sh
bash scripts/package-linux-release.sh glibc "$tag" dist
```

### musl

Start from a clean build directory so no glibc object or dependency selection
can enter the musl archive:

```sh
rm -rf build
WEAVEC1_LIBC=musl WEAVEC_BOOTSTRAP_LIBC=musl ./build.sh
./test-all.sh
bash scripts/package-linux-release.sh musl "$tag" dist
```

## Package-script gates

The package script validates the exact archived compiler, not merely the
unpackaged build tree. It must:

1. compile `build/weavec.bc` to a compiler object;
2. link a static glibc or musl compiler with host support;
3. reject an ELF interpreter or dynamic dependency;
4. build and install the matching private runtime archive;
5. run installed-binary frontend and backend smokes;
6. build and run a native executable through `weavec build`;
7. verify emitted LLVM IR with `llvm-as`;
8. verify the removed implicit backend syntax remains rejected;
9. request `weavec-build-manifest-v1` and `weavec-diagnostics-v1`;
10. verify frontend and backend failure phases, exit codes, and spans;
11. prove failed builds do not publish an executable;
12. strip the compiler and repeat installed-package smokes;
13. write package `BUILD-MANIFEST`, `VERSION`, and the final archive.

The manifest formats are documented in [Build manifests](build-manifest.md), and
the diagnostics protocol in [Machine-readable build diagnostics](diagnostics.md).

## Checksums

Create checksums only after both archives have passed every package gate:

```sh
(
  cd dist
  sha256sum \
    "weavec-${tag}-linux-x86_64-glibc.tar.gz" \
    "weavec-${tag}-linux-x86_64-musl.tar.gz" \
    > SHA256SUMS
  sha256sum --check SHA256SUMS
)
```

Archive names use the tag passed to the packaging script. Verify the actual
filenames in `dist/` before publication.

## Fresh-extraction verification

For each libc archive:

1. extract into a new empty directory;
2. verify `bin/weavec` is executable and statically linked;
3. verify exactly one private runtime exists under
   `lib/weavec/<target>/libweave-runtime.a`;
4. build and run a program that returns a known exit code;
5. verify successful diagnostics output;
6. verify a frontend parse failure returns stable exit `10` and publishes no
   executable;
7. verify a backend failure returns stable exit `11` and publishes no executable;
8. verify the package `BUILD-MANIFEST` and `VERSION` agree with the archive name.

The release workflow performs this verification in a separate job using the
archives produced by the build jobs.

## Publication

Create the signed or annotated release tag on the validated release commit:

```sh
git tag -s "$tag" <release-commit>
git push origin "$tag"
```

Publish the two archives and checksums:

```sh
gh release create "$tag" \
  "dist/weavec-${tag}-linux-x86_64-glibc.tar.gz" \
  "dist/weavec-${tag}-linux-x86_64-musl.tar.gz" \
  dist/SHA256SUMS \
  --target <release-commit> \
  --generate-notes \
  --title "weavec ${tag}"
```

The GitHub release workflow can build and publish the same artifacts for an
explicit `v*` tag. Existing release assets should remain immutable unless an
explicit tag rebuild deliberately replaces assets after the exact same release
commit has been revalidated.

## Post-publication verification

After publication:

1. download every release asset into a fresh directory;
2. run `sha256sum --check SHA256SUMS`;
3. extract both archives;
4. repeat successful native-build and failure-diagnostics smokes;
5. confirm the GitHub release target equals the release commit;
6. confirm downstream documentation is updated only after the assets exist.

## Release checklist

Before merging release preparation or creating the tag, confirm:

- [ ] `VERSION`, changelog, README, and release guide agree.
- [ ] Lower-stage pins identify existing published SDK releases.
- [ ] glibc, musl, and macOS full compiler ladders pass.
- [ ] Deep self-hosting passes through stage 2.
- [ ] Both static package archives pass exact-package smokes.
- [ ] Private runtime paths and targets are correct.
- [ ] Build-manifest and diagnostics protocols pass from extracted packages.
- [ ] Failed builds publish no executable.
- [ ] Checksums pass before and after publication.
- [ ] Tag, source commit, package manifests, and release target agree.
