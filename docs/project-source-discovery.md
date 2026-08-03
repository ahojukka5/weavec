# Deterministic project source discovery

Issue [#120](https://github.com/ahojukka5/weavec/issues/120) maps the source roots
selected by `weave.project` to a deterministic registry of compiler-declared module
identities and project-relative source paths. It extends the project-selection
boundary from [project manifest version 1](project-manifest.md) without changing
surface Weave, module semantics, or WIR core version 2.

## Admitted sources

Project source discovery recursively visits every manifest `source-roots` directory.
The admitted source set contains only entries that are:

- visible: every path component must not begin with `.`;
- regular files;
- named with the exact lowercase suffix `.weave`;
- physically contained by the selected project directory;
- reachable without traversing a symbolic link.

Non-`.weave` files and hidden files or directories are ignored. Sockets, devices,
FIFOs, and other non-regular entries are not sources. Test roots are not part of an
ordinary project build and remain reserved for the testing epic.

Visible symbolic links are rejected anywhere under a source root, even when the
link target would remain inside the project. Hidden entries are excluded before
inspection. This prevents checkout layout, visible link resolution, or duplicate
physical paths from changing source membership. A source root itself must be a real
directory at its lexical project-relative path; roots that escape, alias, or
physically overlap are rejected.

## Deterministic ordering

Manifest roots are normalized and sorted by their UTF-8 bytes. Every visited
directory snapshots its visible entry names and sorts them by raw bytes before
processing them. Recursion follows that sorted order.

The resulting registry is therefore ordered by canonical project-relative path,
not by directory enumeration order, file creation time, inode, command-line
position, or absolute checkout path. Moving an unchanged project produces the same
ordered logical registry.

## Module identity

Every admitted file is read and parsed with the compiler parser. Its root must be:

```weave
(module module-name
  ...)
```

The module identity comes from that root identifier. Filenames and directories do
not infer semantic identity. Legacy `(program ...)` roots are rejected in project
mode, as are malformed or non-module roots. Existing explicit source-list builds
continue to support the documented legacy behavior and do not enter project source
discovery.

Each module identity must occur exactly once. Duplicate identities report the
later deterministic source path and the exact module-name span, while naming both
logical paths in the message.

## Logical and physical paths

Each registry entry retains two different paths:

- the canonical project-relative logical path used by diagnostics and later
  manifests, traces, semantic indexes, hashes, and graph facts;
- the canonical physical path used only for filesystem access and output-alias
  safety.

User-visible source identity never contains the absolute checkout prefix. Requested
build outputs, diagnostics, traces, and tooling artifacts may not alias a discovered
source file.

## Diagnostics

Source discovery uses stable driver-phase diagnostic codes:

```text
project.source.root-read
project.source.root-alias
project.source.path
project.source.escape
project.source.symlink
project.source.read
project.source.parse
project.source.module-root
project.source.legacy-root
project.source.module-identity
project.source.duplicate-module
project.source.empty
driver.output-aliases-project-source
```

Path failures report the canonical project-relative path where available. Parsed
module failures report exact byte spans from the physical source while publishing
the logical path as source identity. Diagnostics JSON retains the existing stable
driver exit code `15`.

## Implementation boundary

After successful discovery, the compiler has an ordered set of:

```text
(module identity, logical source path, physical source path, identity span)
```

The current slice stops with `project.graph.pending`. Import traversal, entry-module
selection, and native project compilation belong to
[#121](https://github.com/ahojukka5/weavec/issues/121). Additive public project
facts in capabilities, manifests, traces, and semantic indexes belong to #123.

The regression suite uses `WEAVEC_INTERNAL_PROJECT_SOURCES` only as a private test
hook to serialize `module<TAB>logical-path` rows. It is not a public command or
protocol and must not be used by external tooling.
