#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

python3 - <<'PY'
import base64
from pathlib import Path

path = Path("src/llvm/expr.weave")
text = path.read_text(encoding="utf-8")
old = """      ; collect arg nodes and evaluate them first
      (let name_node i64 (call_i64 nth_child (local_get tree) (param_get node) (const_i64 1)))
      ; count args (children after name)"""
new = """      ; Reject a missing callee before any source-text access. Typed calls
      ; require child 1 to name the target; malformed calls must produce the
      ; normal backend diagnostic instead of forming a source pointer at -1.
      (let name_node i64 (call_i64 nth_child
        (local_get tree) (param_get node) (const_i64 1)))
      (if
        (condition (eq_i64 (local_get name_node) (const_i64 -1)))
        (then (do
          (call_void diag_unknown_identifier
            (param_get ctx) (local_get name_node))
          (return (const_i64 -1))))
        (else (do)))
      ; collect arg nodes and evaluate them first
      ; count args (children after name)"""
if text.count(old) != 1:
    raise SystemExit("emit_call_expr pattern changed")
patched = text.replace(old, new)
print("BEGIN_EXPR_B64")
print(base64.b64encode(patched.encode("utf-8")).decode("ascii"))
print("END_EXPR_B64")
raise SystemExit(1)
PY
