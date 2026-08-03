# Deterministic project source discovery and graph builds

Issues [#120](https://github.com/ahojukka5/weavec/issues/120) and
[#121](https://github.com/ahojukka5/weavec/issues/121) turn a selected
`weave.project` manifest into a deterministic set of compiler-declared modules,
a validated local dependency graph, and a complete project build. The project
layer does not change surface Weave, explicit-module semantics, or WIR core
version 2.

## Admitted sources

Project source discovery recursively visits every manifest `source-roots`
directory. The admitted source set contains only entries that are:

- visible: every path component must not begin with `.`;
- regular files;
- named with the exact lowercase suffix `.weave`;
- physically contained by the selected project directory;
- reachable without traversing a symbolic link.

Non-`.weave` files and hidden files or directories are ignored. Sockets, devices,
FIFOs, and other non-regular entries are not sources. Test roots are not part of
an ordinary project build and remain reserved for the testing epic.

Visible symbolic links are rejected anywhere under a source root, even when the
link target would remain inside the project. Hidden entries are excluded before
inspection. This prevents checkout layout, visible link resolution, or duplicate
physical paths from changing source membership. A source root itself must be a
real directory at its lexical project-relative path; roots that escape, alias, or
physically overlap are rejected.

## Deterministic source registry

Manifest roots are normalized and sorted by their UTF-8 bytes. Every visited
directory snapshots its visible entry names and sorts them by raw bytes before
processing them. Recursion follows that sorted order.

The resulting source registry is ordered by canonical project-relative path, not
by directory enumeration order, file creation time, inode, command-line position,
or absolute checkout path. Moving an unchanged project therefore produces the
same logical source registry.

Every admitted file is read and parsed with the compiler parser. Its root must be:

```weave
(module module-name
  ...)
```

The module identity comes from that root identifier. Filenames and directories do
not infer semantic identity. Legacy `(program ...)` roots are rejected in project
mode, as are malformed or non-module roots. Existing explicit source-list builds
retain their documented behavior and do not enter project discovery.

Each module identity must occur exactly once. Duplicate identities report the
later deterministic source path and the exact module-name span, while naming both
logical paths in the message.

## Logical and physical paths

Each registry entry retains two paths with different roles:

- the canonical project-relative logical path used by project diagnostics and
  future manifests, traces, semantic indexes, hashes, and graph facts;
- the canonical physical path used only for filesystem access, compiler input,
  exact-span resolution, and output-alias safety.

Project-driver diagnostics do not expose the absolute checkout prefix. Requested
build outputs, diagnostics, traces, and tooling artifacts may not alias a
discovered source file.

## Local module graph

After source discovery, the project driver reads top-level import targets and
constructs the complete local module graph. Every imported module must be present
in the discovered registry. External packages, implicit modules, filename-based
resolution, and network dependency lookup are not part of manifest format 1.

Dependencies are visited before their importers. When several independent modules
are available, their compiler-declared module identities provide the stable UTF-8
byte tie-break. The resulting frontend source order is therefore independent of
source-root order, directory enumeration, file creation order, and absolute
checkout path.

The graph layer owns only project membership, dependency reachability, cycle
rejection, deterministic ordering, and manifest entry selection. The existing
frontend remains authoritative for import shape, duplicate and conflicting
bindings, exports, private visibility, callable and constant interfaces,
module-scoped nominal identities, symbol resolution, interface hashes, and WIR
lowering. Project mode feeds the complete ordered source set into that existing
frontend rather than implementing a second interface checker.

## Entry selection

An executable manifest names exactly one entry module. Project resolution rejects:

- an entry module absent from the discovered source registry;
- a selected module with no top-level `entry` declaration;
- multiple entry declarations in the selected module;
- an entry declaration in a module other than the selected module.

Library projects forbid entry declarations. Entry identity comes from the
manifest and compiler-declared module root, never from a filename such as
`main.weave`.

## Project outputs

Executable projects pass their dependency-ordered sources through the normal
frontend, backend, optimizer, code generator, linker, diagnostics, trace, and
atomic native-output path. The manifest output name is resolved relative to the
project directory unless `-o` or `--output` overrides it.

Library projects publish the frontend's normalized WIR module bundle at the
resolved project output path. This gives a deterministic, compiler-validated
local library artifact without inventing a public native-library ABI before
public nominal types and package interfaces are implemented. Passing
`--emit-wir` for a library project is rejected because the project output already
has that role.

## Diagnostics

Source discovery retains these stable driver-phase diagnostic codes:

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

Graph and entry selection add:

```text
project.graph.missing-module
project.graph.import-cycle
project.entry.missing-module
project.entry.missing-declaration
project.entry.duplicate-declaration
project.entry.unselected-declaration
project.entry.library-declaration
project.library.emit-wir-conflict
```

Path failures report the canonical project-relative path where available. Parsed
source failures use exact byte spans from the physical file while publishing its
logical path as source identity. Diagnostics JSON retains the stable driver exit
code `15` when it can be published safely.

## Tooling boundary

The regression suite may set:

```text
WEAVEC_INTERNAL_PROJECT_SOURCES
WEAVEC_INTERNAL_PROJECT_GRAPH
```

These private hooks serialize `module<TAB>logical-path` rows for deterministic
cross-platform qualification. They are not public commands or protocols and must
not be consumed by external tools.

Additive project facts in capabilities, build manifests, diagnostics, traces, and
the semantic index remain owned by
[#123](https://github.com/ahojukka5/weavec/issues/123). Public nominal type
interfaces remain owned by
[#122](https://github.com/ahojukka5/weavec/issues/122), and integrated release and
self-host qualification remains owned by
[#124](https://github.com/ahojukka5/weavec/issues/124).