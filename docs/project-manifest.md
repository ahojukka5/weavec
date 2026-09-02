# Weave project manifest version 1

Status: implemented manifest-selection contract for epic #111.

A Weave project is rooted by one UTF-8 file named `weave.project`. The file is a
versioned S-expression document separate from surface `.weave` sources and from
`weavec-build-manifest-v1` JSON build evidence.

This document fixes the first-version manifest semantics used by the compiler's
project-selection boundary. The reference corpus and checker under
`spec/project-manifest/` and `scripts/check_project_manifest_spec.py` are normative
for the structural rules, while the production parser in the final compiler is
covered by project-discovery regressions.

## Canonical example

```weave
(weave-project
  (format 1)
  (name example)
  (kind executable)
  (source-roots "src")
  (test-roots "test")
  (entry application)
  (output "example"))
```

A library project omits `entry`:

```weave
(weave-project
  (format 1)
  (name arithmetic)
  (kind library)
  (source-roots "src")
  (test-roots)
  (output "arithmetic"))
```

## Root and field model

The document root is exactly `weave-project`. Every child is a named field. Version
1 admits only these fields:

| Field | Cardinality | Value |
|---|---:|---|
| `format` | exactly one | the atom `1` |
| `name` | exactly one | one portable identifier |
| `kind` | exactly one | `executable` or `library` |
| `source-roots` | exactly one | one or more path strings |
| `test-roots` | zero or one | zero or more path strings |
| `entry` | conditional | one module identifier |
| `output` | zero or one | one portable output-name string |

Unknown fields are rejected under format 1. Readers must not silently ignore an
unknown field because doing so could change source membership, entry selection,
or output behavior. A future field that changes project meaning requires a format
revision or a separately specified additive rule.

Every field may occur at most once. Duplicate fields are rejected even when their
values are byte-identical.

## Project identity

`name` is the logical project identity. It is an atom matching:

```text
[A-Za-z][A-Za-z0-9_-]*
```

Project identity does not come from the checkout directory, manifest path,
absolute path, source ordering, or output filename. Moving an unchanged project to
another absolute path therefore does not change its logical identity.

Format 1 does not define organization names, package namespaces, semantic
versions, dependency coordinates, or registry identities.

## Project kind

`kind` is required and has two values:

- `executable` builds an application and requires exactly one `entry` field;
- `library` defines reusable modules and forbids `entry`.

The first version deliberately does not define a project that emits both an
executable and a library. Multiple products require a later manifest format or a
new explicitly versioned product model.

## Source and test roots

`source-roots` contains one or more directories whose `.weave` files are ordinary
project sources. `test-roots` contains zero or more directories reserved for
project tests.

When `test-roots` is omitted, its semantic value is:

```weave
(test-roots "test")
```

An explicit empty form disables implicit test-source discovery:

```weave
(test-roots)
```

Each path is a UTF-8 string interpreted relative to the directory containing
`weave.project`. A root path:

- must not be empty;
- must use `/` separators;
- must not be absolute or use a drive prefix;
- must not contain empty, `.` or `..` components;
- must not contain NUL;
- is stored and reported in project-relative canonical form.

Duplicate roots are rejected. Roots within one field must not overlap, and source
roots must not overlap test roots. For example, `"src"` and `"src/generated"`
cannot both be roots. This prevents one file from acquiring ambiguous project
membership.

The canonical form sorts roots by their UTF-8 bytes. Root ordering has no
precedence semantics.

Symlink traversal, filesystem boundary checks, ignored entries, and admitted
source extensions are owned by source-discovery issue #120. That implementation
must preserve the logical path rules fixed here.

## Entry module

`entry` names the compiler-declared explicit module that owns the executable
entry declaration. It uses the same portable identifier grammar as `name`.

An executable manifest without `entry` is invalid. A library manifest containing
`entry` is invalid. The entry module is semantic; it is not inferred from a
filename such as `main.weave`.

Format 1 does not provide a command-line override for the entry module. Adding one
later must define its effect on manifests, diagnostics, build evidence, and
reproducibility.

## Output name

`output` is a logical default artifact name. It is a UTF-8 string containing
exactly one path component. It must not be empty, `.`, `..`, contain NUL, `/`, or
`\`.

When omitted, `output` defaults to the project `name`. Canonical serialization
always writes the resolved value explicitly.

The manifest value is not an output directory and cannot escape the project.
The existing public `-o` or `--output` command-line option overrides this default
and retains its current path semantics. The selected manifest is protected as an
input: neither the explicit output, the manifest default, diagnostics, traces,
nor another requested artifact may alias `weave.project`.

## Canonical serialization

A canonical version-1 manifest has:

- UTF-8 text and LF line endings;
- two-space indentation;
- exactly one final newline;
- the root on its own line;
- one complete field per line;
- fields ordered as `format`, `name`, `kind`, `source-roots`, `test-roots`,
  conditional `entry`, then `output`;
- source and test roots sorted by UTF-8 bytes;
- explicit normalized `test-roots` and `output` defaults;
- JSON-compatible quoted strings.

Field order in input is not semantic. A valid noncanonical manifest may be
normalized to the canonical order. Formatting twice must produce byte-identical
output to formatting once.

The project formatter must use the compiler S-expression parser and preserve
semicolon comments through the same deterministic attachment policy documented
for surface formatting. Comments are not semantic and do not participate in the
reference checker model.

A dedicated project-formatting command has not yet been added. When introduced,
it must emit this exact structural normal form.

## Command-line mode precedence

The final compiler implements these precedence rules:

1. Supplying explicit `.weave` source arguments selects existing source-list mode.
   Project discovery does not silently affect that build.
2. `--project` is invalid when combined with explicit source arguments.
3. With no explicit source arguments, `--project PATH` or `--project=PATH` selects
   a project directory or a regular file named exactly `weave.project`.
4. With neither sources nor an explicit project selection, `weavec build`
   discovers the nearest admitted `weave.project` from the current directory
   toward the filesystem root.
5. A nearer malformed or unreadable manifest is authoritative and prevents
   fallback to a more distant parent manifest.
6. `-o` or `--output` overrides the manifest `output` value.
7. Existing target, optimization, CPU, runtime, and tooling options apply to the
   selected project build without changing project identity.
8. Format 1 provides no command-line override for `name`, `kind`, roots, or
   `entry`.

Ambiguous combinations fail rather than selecting a mode heuristically. See
[Command reference](command-reference.md) for the exact invocation forms.

## Diagnostics contract

The production parser uses stable project-manifest diagnostic codes. Version 1
reserves these families:

```text
project.manifest.read
project.manifest.parse
project.manifest.root
project.manifest.format
project.manifest.unknown-field
project.manifest.duplicate-field
project.manifest.missing-field
project.manifest.field-shape
project.manifest.identifier
project.manifest.path
project.manifest.root-overlap
project.manifest.kind
project.manifest.entry
project.manifest.output
```

Diagnostics use the most specific source span available. Structural failures
point at the malformed field or value. A missing conditional field points at the
root because no narrower source span exists. Manifest failure occurs before WIR
or native output publication.

Human diagnostics retain raw driver exit `2`. When `--diagnostics-json` can be
published safely, the same failure is represented by `weavec-diagnostics-v1` with
stable driver exit `15`, the selected manifest path, and an exact byte span where
one exists. Full project protocol publication remains owned by #123.

## Capability and build-evidence representation

The generic stable `build` command in `weavec capabilities --json` remains valid
for source-list and project selection. The exact additive `projects` feature
schema is owned by #123 and must eventually contain at least:

- manifest filename `weave.project`;
- root head `weave-project`;
- supported format version `1`;
- supported kinds `executable` and `library`;
- project-build command availability;
- the absence of external dependencies and lockfiles.

Tools must not infer complete project builds merely from the manifest
specification or command availability. Source discovery remains explicitly
pending until #120.

A project build that requests `weavec-build-manifest-v1` must add a `project`
object rather than reinterpret the existing ordered `sources` field. The object
must distinguish logical project-relative paths from physical paths and include:

- format version;
- project name and kind;
- selected manifest;
- normalized source and test roots;
- selected entry module, or `null` for a library;
- resolved manifest output name;
- whether the output path was overridden by the command line.

The complete discovered source set and module graph are added by #123. Existing
source-list build manifests remain valid and continue to omit the `project`
object.

## Compatibility and implementation boundary

Project selection, nearest-parent discovery, version-1 parsing, command-line
precedence, output-default resolution, manifest protection, human diagnostics,
and diagnostics JSON integration are implemented by #119.

A valid selected project currently ends at the explicit
`project.sources.pending` boundary. Issue #120 replaces that boundary with
deterministic source membership. No current project-selection behavior changes
surface Weave, module semantics, WIR core version 3, runtime packaging, or
existing explicit source-list builds.

Format 1 contains no dependency declarations, lockfile, package registry,
workspace, build script, arbitrary environment interpolation, conditional target
section, or hidden filename conventions.

Implementation continues through #120, #121, #122, and #123. Integrated
qualification is tracked by #124. Incremental compilation in #125 may use only the
stable project semantics and interface facts established by those earlier
slices.
