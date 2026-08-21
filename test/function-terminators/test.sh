#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# A function body that can reach its end without returning must be rejected by
# the frontend, naming the function. Before this check the backend emitted a
# basic block with no terminator and the failure surfaced as an LLVM parse error
# against generated text.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-terminators-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'function-terminators: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

expect_rejected() {
  local name="$1"
  local needle="$2"

  set +e
  "$WEAVEC" build "$TMP/$name.weave" -o "$TMP/$name" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e

  if [[ "$status" -eq 0 ]]; then
    printf 'function-terminators: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if [[ -e "$TMP/$name" ]]; then
    printf 'function-terminators: %s published an executable\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'function-terminators: %s missing expected diagnostic\n' "$name" >&2
    printf 'expected to contain: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
  # The failure must be described against this source, not against generated IR.
  if grep -Fq '<stdin>' "$TMP/$name.stderr"; then
    printf 'function-terminators: %s reported a generated-IR position\n' "$name" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

expect_accepted() {
  local name="$1"
  local expected_status="$2"

  set +e
  "$WEAVEC" build "$TMP/$name.weave" -o "$TMP/$name" 2>"$TMP/$name.stderr"
  local build_status="$?"
  set -e
  if [[ "$build_status" -ne 0 ]]; then
    printf 'function-terminators: %s failed to build\n' "$name" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
  if [[ -s "$TMP/$name.stderr" ]]; then
    printf 'function-terminators: %s wrote unexpected stderr\n' "$name" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
  set +e
  "$TMP/$name"
  local status="$?"
  set -e
  if [[ "$status" -ne "$expected_status" ]]; then
    printf 'function-terminators: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected_status" >&2
    exit 1
  fi
}

# 1. A void function with no terminator.
cat > "$TMP/void-fallthrough.weave" <<'EOF'
(program
  (name "void-fallthrough")
  (version "0.1")
  (fn note
    (params (value i32))
    (returns void)
    (do
      (let doubled i32 (op mul value 2))))
  (entry main (params) (returns i32) (do (call note 21) (return 0))))
EOF
expect_rejected void-fallthrough 'note can reach the end of its body'

# 2. A non-void function with no return at all. This is the shape that cannot be
# repaired by inserting a terminator, because there is no value to invent.
cat > "$TMP/value-fallthrough.weave" <<'EOF'
(program
  (name "value-fallthrough")
  (version "0.1")
  (fn compute
    (params (value i32))
    (returns i32)
    (do
      (let doubled i32 (op mul value 2))))
  (entry main (params) (returns i32) (do (return (call compute 21)))))
EOF
expect_rejected value-fallthrough 'compute can reach the end of its body'

# 3. Only one branch returns, so the other falls through.
cat > "$TMP/partial-return.weave" <<'EOF'
(program
  (name "partial-return")
  (version "0.1")
  (fn note
    (params (flag bool))
    (returns void)
    (do
      (if (condition flag)
        (then (do (return_void)))
        (else (do)))))
  (entry main (params) (returns i32) (do (call note true) (return 0))))
EOF
expect_rejected partial-return 'note can reach the end of its body'

# 4. An entry point is checked the same way.
cat > "$TMP/entry-fallthrough.weave" <<'EOF'
(program
  (name "entry-fallthrough")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let value i32 7))))
EOF
expect_rejected entry-fallthrough 'main can reach the end of its body'

# 5. Both branches return, and the `if` is the last statement. This must keep
# working: a check that only looked at the last statement would reject it.
cat > "$TMP/both-branches.weave" <<'EOF'
(program
  (name "both-branches")
  (version "0.1")
  (fn pick
    (params (flag bool))
    (returns i32)
    (do
      (if (condition flag)
        (then (do (return 7)))
        (else (do (return 9))))))
  (entry main (params) (returns i32) (do (return (call pick true)))))
EOF
expect_accepted both-branches 7

# 6. Nested fully-returning branches.
cat > "$TMP/nested-branches.weave" <<'EOF'
(program
  (name "nested-branches")
  (version "0.1")
  (fn pick
    (params (a bool) (b bool))
    (returns i32)
    (do
      (if (condition a)
        (then (do
          (if (condition b)
            (then (do (return 3)))
            (else (do (return 4))))))
        (else (do (return 5))))))
  (entry main (params) (returns i32) (do (return (call pick true false)))))
EOF
expect_accepted nested-branches 4

# 7. A bare (return) is the void spelling and is accepted.
cat > "$TMP/bare-return.weave" <<'EOF'
(program
  (name "bare-return")
  (version "0.1")
  (fn note
    (params (value i32))
    (returns void)
    (do
      (let doubled i32 (op mul value 2))
      (return)))
  (entry main (params) (returns i32) (do (call note 21) (return 0))))
EOF
expect_accepted bare-return 0

# 8. A bare (return) in a value-returning function is not, and says why.
cat > "$TMP/bare-return-value.weave" <<'EOF'
(program
  (name "bare-return-value")
  (version "0.1")
  (fn compute (params) (returns i32) (do (return)))
  (entry main (params) (returns i32) (do (return (call compute)))))
EOF
expect_rejected bare-return-value 'this function returns a value'

# A loop is not a terminator: it may run zero times.
cat > "$TMP/loop-only.weave" <<'EOF'
(program
  (name "loop-only")
  (version "0.1")
  (fn note
    (params (limit i32))
    (returns void)
    (do
      (let index i32 0)
      (while (condition (op less-than index limit))
        (do (set index (op add index 1))))))
  (entry main (params) (returns i32) (do (call note 3) (return 0))))
EOF
expect_rejected loop-only 'note can reach the end of its body'

# Compact surface: a tail expression is not a return.
cat > "$TMP/compact-tail.weave" <<'EOF'
(program
  (name "compact-tail")
  (version "0.1")
  (fn compute ((value i32)) i32
    (let doubled i32 (* value 2)))
  (entry main () i32
    (return (compute 21))))
EOF
expect_rejected compact-tail 'compute can reach the end of its body'

# Compact if with both branches returning remains accepted.
cat > "$TMP/compact-both-branches.weave" <<'EOF'
(program
  (name "compact-both-branches")
  (version "0.1")
  (fn pick ((flag bool)) i32
    (if flag
      (return 7)
      (return 9)))
  (entry main () i32
    (return (pick true))))
EOF
expect_accepted compact-both-branches 7

# Compact roots: every discriminant branch returns explicitly.
cat > "$TMP/compact-roots.weave" <<'EOF'
(program
  (name "compact-roots")
  (version "0.1")
  (fn roots ((a f64) (b f64) (c f64)) i32
    (doc "Classify the discriminant: 0 two roots, 1 one root, 2 none.")
    (let d f64 (- (* b b) (* 4.0 (* a c))))
    (if (< d 0.0)
      (return 2)
      (if (= d 0.0)
        (return 1)
        (return 0))))
  (entry main () i32
    (return (roots 1.0 -3.0 2.0))))
EOF
expect_accepted compact-roots 0

# Falling off the end publishes an exact-span diagnostics document.
cat > "$TMP/missing-return-span.weave" <<'EOF'
(program
  (name "missing-return-span")
  (version "0.1")
  (fn compute ((value i32)) i32
    (let doubled i32 (* value 2)))
  (entry main () i32
    (return (compute 21))))
EOF
set +e
"$WEAVEC" build "$TMP/missing-return-span.weave" -o "$TMP/missing-return-span" \
  --diagnostics-json "$TMP/missing-return-span.json" \
  >"$TMP/missing-return-span.stdout" 2>"$TMP/missing-return-span.stderr"
set -e
python3 - "$TMP/missing-return-span.json" "$TMP/missing-return-span.weave" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
source = pathlib.Path(sys.argv[2]).read_bytes()
assert doc["status"] == "failed"
assert doc["phase"] == "frontend"
diags = doc["diagnostics"]
assert len(diags) >= 1
diag = diags[0]
assert diag["code"] == "frontend.function.missing-return"
assert diag["symbol"] == "compute"
span = diag["span"]
start = span["start_byte"]
end = span["end_byte"]
assert 0 <= start < end <= len(source)
fragment = source[start:end]
assert b"let doubled" in fragment, fragment
assert b"(return" not in fragment
PY

# Formatter does not wrap a tail expression in return, and does not strip
# an explicit return that already occupies tail position.
cat > "$TMP/fmt-tail-input.weave" <<'EOF'
(program
  (name "fmt-tail")
  (version "0.1")
  (fn compute ((value i32)) i32
    (* value 2))
  (entry main () i32
    (return 0)))
EOF
"$WEAVEC" fmt --output "$TMP/fmt-tail-out.weave" "$TMP/fmt-tail-input.weave"
if grep -Fq '(return (* value 2))' "$TMP/fmt-tail-out.weave"; then
  printf 'function-terminators: formatter invented a tail return\n' >&2
  cat "$TMP/fmt-tail-out.weave" >&2
  exit 1
fi
if ! grep -Fq '(* value 2)' "$TMP/fmt-tail-out.weave"; then
  printf 'function-terminators: formatter dropped the tail expression\n' >&2
  cat "$TMP/fmt-tail-out.weave" >&2
  exit 1
fi

cat > "$TMP/fmt-explicit-input.weave" <<'EOF'
(program
  (name "fmt-explicit")
  (version "0.1")
  (fn compute ((value i32)) i32
    (return (* value 2)))
  (entry main () i32
    (return (compute 21))))
EOF
"$WEAVEC" fmt --output "$TMP/fmt-explicit-out.weave" "$TMP/fmt-explicit-input.weave"
if ! grep -Fq '(return (* value 2))' "$TMP/fmt-explicit-out.weave"; then
  printf 'function-terminators: formatter removed an explicit return\n' >&2
  cat "$TMP/fmt-explicit-out.weave" >&2
  exit 1
fi

printf 'function-terminators: passed\n'
