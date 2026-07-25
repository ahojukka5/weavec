#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Apply the coordinated v0.3.0 compiler-chain pins exactly once."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def replace_exact(path: Path, old: str, new: str, expected: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != expected:
        raise RuntimeError(
            f"{path}: expected {expected} occurrence(s) of {old!r}, found {count}"
        )
    path.write_text(text.replace(old, new), encoding="utf-8")


def update_build() -> None:
    path = ROOT / "build.sh"
    replacements = [
        ("#   WEAVEC1_VERSION=v0.2.0", "#   WEAVEC1_VERSION=v0.3.1"),
        ("#   WEAVEC1_TAG=v0.2.0", "#   WEAVEC1_TAG=v0.3.1"),
        ("#   WEAVEC_BOOTSTRAP_VERSION=v0.2.0", "#   WEAVEC_BOOTSTRAP_VERSION=v0.3.0"),
        ("#   WEAVEC_BOOTSTRAP_REF=v0.2.0", "#   WEAVEC_BOOTSTRAP_REF=v0.3.0"),
        ('WEAVEC0_TAG="${WEAVEC0_TAG:-v0.2.1}"', 'WEAVEC0_TAG="${WEAVEC0_TAG:-v0.4.0}"'),
        ('WEAVEC1_VERSION="${WEAVEC1_VERSION:-v0.2.0}"', 'WEAVEC1_VERSION="${WEAVEC1_VERSION:-v0.3.1}"'),
        ('WEAVEC_BOOTSTRAP_VERSION="${WEAVEC_BOOTSTRAP_VERSION:-v0.2.0}"', 'WEAVEC_BOOTSTRAP_VERSION="${WEAVEC_BOOTSTRAP_VERSION:-v0.3.0}"'),
    ]
    for old, new in replacements:
        replace_exact(path, old, new)


def update_package_manifest() -> None:
    path = ROOT / "scripts" / "package-linux-release.sh"
    replace_exact(
        path,
        'weavec1_version=${WEAVEC1_VERSION:-v0.2.0}',
        'weavec1_version=${WEAVEC1_VERSION:-v0.3.1}',
    )
    replace_exact(
        path,
        'weavec_bootstrap_version=${WEAVEC_BOOTSTRAP_VERSION:-v0.2.0}',
        'weavec_bootstrap_version=${WEAVEC_BOOTSTRAP_VERSION:-v0.3.0}',
    )


def update_docs() -> None:
    replacements = [
        ("weavec1 v0.2.0", "weavec1 v0.3.1"),
        ("weavec-bootstrap v0.2.0", "weavec-bootstrap v0.3.0"),
        ("WEAVEC0_TAG=v0.2.1", "WEAVEC0_TAG=v0.4.0"),
        ("WEAVEC1_VERSION=v0.2.0", "WEAVEC1_VERSION=v0.3.1"),
        ("WEAVEC1_TAG=v0.2.0", "WEAVEC1_TAG=v0.3.1"),
        ("WEAVEC_BOOTSTRAP_VERSION=v0.2.0", "WEAVEC_BOOTSTRAP_VERSION=v0.3.0"),
        ("WEAVEC_BOOTSTRAP_REF=v0.2.0", "WEAVEC_BOOTSTRAP_REF=v0.3.0"),
    ]
    for path in (ROOT / "README.md", ROOT / "docs" / "RELEASING.md"):
        text = path.read_text(encoding="utf-8")
        for old, new in replacements:
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8")


def update_changelog() -> None:
    path = ROOT / "CHANGELOG.md"
    marker = """### Changed

- Normal users and downstream tools no longer need to invoke the surface
"""
    replacement = """### Changed

- The reproducible compiler chain now pins `weavec0 v0.4.0`, `weavec1 v0.3.1`,
  and `weavec-bootstrap v0.3.0`.
- Normal users and downstream tools no longer need to invoke the surface
"""
    replace_exact(path, marker, replacement)


def main() -> None:
    update_build()
    update_package_manifest()
    update_docs()
    update_changelog()


if __name__ == "__main__":
    main()
