# Structured module diagnostics

Explicit module, import, and export failures are published through
`weavec-diagnostics-v1` when `weavec build` receives `--diagnostics-json`.
The self-hosted module validator remains authoritative: it selects the stable
code, exact UTF-8 byte span, operand role, and relevant identifier while the
module registry is live. Human stderr is preserved unchanged.

Every structured module diagnostic has:

- `phase: "frontend"` and `severity: "error"`;
- `span_origin: "compiler-semantic"`;
- `analysis_complete: true`;
- an exact span over the failing module, import, export, or identifier node;
- an `operand_role` naming that node's semantic role;
- `candidates`, `related_locations`, and `repairs` arrays, currently empty.

## Stable codes

| Code | Operand role | Meaning |
|---|---|---|
| `frontend.module.invalid-root` | `root` | The source root is neither `program` nor `module`. |
| `frontend.module.invalid-name` | `module-name` | The module name is missing or is not an identifier. |
| `frontend.module.duplicate` | `module-name` | The source set declares the same module more than once. |
| `frontend.module.mixed-roots` | `module` or `module-name` | Legacy program roots and explicit module roots were mixed. |
| `frontend.module.registration` | `module-name` | The compiler could not register an otherwise valid module declaration. |
| `frontend.module.unregistered` | `module` | Interface validation could not select the module recorded during declaration collection. |
| `frontend.module.import-cycle` | `module-name` | The module participates in a rejected import cycle. |
| `frontend.module.import-shape` | `import` | The import form does not match `(import MODULE (SYMBOL...))`. |
| `frontend.module.import-empty` | `import` | The imported symbol list is empty. |
| `frontend.module.import-invalid-symbol` | `import-symbol` | An imported symbol is not an identifier. |
| `frontend.module.duplicate-import` | `import-symbol` | The same module binding was imported more than once. |
| `frontend.module.conflicting-import` | `import-symbol` | Different modules provide the same imported binding. |
| `frontend.module.import-local-collision` | `import-symbol` | The imported binding conflicts with a declaration in the current module. |
| `frontend.module.import-registration` | `import-symbol` | The compiler could not register an otherwise valid import. |
| `frontend.module.import-missing-module` | `import-module` | The named source module does not exist. |
| `frontend.module.import-missing-symbol` | `import-symbol` | The source module does not declare the requested symbol. |
| `frontend.module.import-private-symbol` | `import-symbol` | The requested symbol exists but is not exported. |
| `frontend.module.export-empty` | `export` | The export form names no symbols. |
| `frontend.module.export-invalid-symbol` | `export-symbol` | An exported symbol is not an identifier. |
| `frontend.module.duplicate-export` | `export-symbol` | The same symbol was exported more than once. |
| `frontend.module.export-registration` | `export-symbol` | The compiler could not register an otherwise valid export. |
| `frontend.module.export-undeclared` | `export-symbol` | The exported name is not declared in the current module. |

## Symbol and span policy

For identifier-specific failures, `symbol` contains the exact identifier text
and `span` covers that identifier. Form-level failures use the complete form or
root as their primary span. A missing structured fact is not reconstructed from
stderr by the host or by external tooling.

The module validator publishes only the first semantic failure for a build,
matching the existing diagnostics sidecar contract. Repeating the same build
with identical inputs produces byte-identical diagnostics JSON.

See [Machine-readable build diagnostics](diagnostics.md) for schema,
publication, exit-code, repair-trust, and compatibility rules, and
[Explicit modules and interfaces](modules.md) for module semantics.
