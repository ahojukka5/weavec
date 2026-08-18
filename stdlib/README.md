# Weave standard library

Each module is `stdlib/<id>.weave` and is named `std.<id>`. That path
is the same in a repository checkout and in an extracted release
package. The full contract is in the repository document
`docs/stdlib.md`.

| Path | Identity |
|---|---|
| `stdlib/memory.weave` | `std.memory` |
| `stdlib/process.weave` | `std.process` |
| `stdlib/parse.weave` | `std.parse` |
| `stdlib/io.weave` | `std.io` |
| `stdlib/math.weave` | `std.math` |
| `stdlib/option.weave` | `std.option` |
| `stdlib/result.weave` | `std.result` |
| `stdlib/vector.weave` | `std.vector` |
| `stdlib/matrix.weave` | `std.matrix` |
| `stdlib/statistics.weave` | `std.statistics` |
| `stdlib/file.weave` | `std.file` |
| `stdlib/bytes.weave` | `std.bytes` |
| `stdlib/string.weave` | `std.string` |

Pass the files a program needs, dependencies first. `std.memory` comes
before anything that allocates. Do not link the private target runtime
or declare `weave_rt_` / `__weave_` names from application source.
