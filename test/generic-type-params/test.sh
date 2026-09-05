#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Explicit type parameters and type applications (#145). Generic declarations
# resolve as surface/semantic facts; they do not emit specialized WIR.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-generic-type-params-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'generic-type-params: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

expect_rejected() {
  local name="$1"
  local needle="$2"

  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$TMP/$name.weave" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e

  if [[ "$status" -eq 0 ]]; then
    printf 'generic-type-params: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$TMP/$name.wir" ]]; then
    printf 'generic-type-params: %s published WIR after failure\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'generic-type-params: %s missing expected diagnostic\n' "$name" >&2
    printf 'expected to contain: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

# A generic function that is never called can sit beside an ordinary main.
# It must not appear in the emitted WIR.
cat > "$TMP/unused-generic.weave" <<'EOF'
(program
  (name "unused-generic")
  (version "0.1")
  (fn identity
    (type-params T)
    (params (value T))
    (returns T)
    (do (return value)))
  (entry main (params) (returns i32) (do (return 0))))
EOF
"$WEAVEC" --frontend "$TMP/unused-generic.wir" "$TMP/unused-generic.weave" \
  2>"$TMP/unused-generic.stderr" || {
  printf 'generic-type-params: unused generic declaration was rejected\n' >&2
  cat "$TMP/unused-generic.stderr" >&2
  exit 1
}
if grep -Fq 'identity' "$TMP/unused-generic.wir"; then
  printf 'generic-type-params: generic function was emitted to WIR\n' >&2
  cat "$TMP/unused-generic.wir" >&2
  exit 1
fi
if ! grep -Fq '(fn main' "$TMP/unused-generic.wir"; then
  printf 'generic-type-params: ordinary main was not emitted\n' >&2
  cat "$TMP/unused-generic.wir" >&2
  exit 1
fi

# Formatter keeps the type-params clause after the name.
"$WEAVEC" fmt --output "$TMP/unused-generic.fmt" "$TMP/unused-generic.weave"
if ! grep -Fq '(type-params T)' "$TMP/unused-generic.fmt"; then
  printf 'generic-type-params: formatter dropped type-params\n' >&2
  cat "$TMP/unused-generic.fmt" >&2
  exit 1
fi
if ! grep -Fq '(fn identity (type-params T) ((value T)) T' \
  "$TMP/unused-generic.fmt"; then
  printf 'generic-type-params: type-params is not the clause after the name\n' >&2
  cat "$TMP/unused-generic.fmt" >&2
  exit 1
fi

# The canonical form the formatter produces must compile.
"$WEAVEC" --frontend "$TMP/unused-generic.refmt.wir" "$TMP/unused-generic.fmt" \
  2>"$TMP/unused-generic.refmt.stderr" || {
  printf 'generic-type-params: formatted generic source was rejected\n' >&2
  cat "$TMP/unused-generic.refmt.stderr" >&2
  exit 1
}

# Formatting is a fixed point: the canonical form reformats to itself.
"$WEAVEC" fmt --output "$TMP/unused-generic.fmt2" "$TMP/unused-generic.fmt"
if ! cmp -s "$TMP/unused-generic.fmt" "$TMP/unused-generic.fmt2"; then
  printf 'generic-type-params: formatting a generic fn is not idempotent\n' >&2
  diff "$TMP/unused-generic.fmt" "$TMP/unused-generic.fmt2" >&2 || true
  exit 1
fi
"$WEAVEC" fmt --check "$TMP/unused-generic.fmt" || {
  printf 'generic-type-params: canonical generic fn failed fmt --check\n' >&2
  exit 1
}

# Several type parameters survive alongside derived headers, and the header
# order stays name, type-params, parameters, return type.
cat > "$TMP/multi-generic.weave" <<'EOF'
(program
  (name "multi-generic")
  (version "0.1")
  (fn pick
    (type-params T E)
    (params (a T) (b E))
    (returns T)
    (doc "Return the first argument.")
    (pure)
    (do (return a)))
  (entry main (params) (returns i32) (do (return 0))))
EOF
"$WEAVEC" fmt --output "$TMP/multi-generic.fmt" "$TMP/multi-generic.weave"
if ! grep -Fq '(fn pick (type-params T E) ((a T) (b E)) T' \
  "$TMP/multi-generic.fmt"; then
  printf 'generic-type-params: multiple type parameters were not preserved\n' >&2
  cat "$TMP/multi-generic.fmt" >&2
  exit 1
fi
"$WEAVEC" --frontend "$TMP/multi-generic.wir" "$TMP/multi-generic.fmt" \
  2>"$TMP/multi-generic.stderr" || {
  printf 'generic-type-params: formatted multi-parameter source was rejected\n' >&2
  cat "$TMP/multi-generic.stderr" >&2
  exit 1
}
"$WEAVEC" fmt --output "$TMP/multi-generic.fmt2" "$TMP/multi-generic.fmt"
if ! cmp -s "$TMP/multi-generic.fmt" "$TMP/multi-generic.fmt2"; then
  printf 'generic-type-params: multi-parameter formatting is not idempotent\n' >&2
  diff "$TMP/multi-generic.fmt" "$TMP/multi-generic.fmt2" >&2 || true
  exit 1
fi

# A generic whose parameter is used through a nested type application keeps
# both the clause and the application.
cat > "$TMP/nested-generic.weave" <<'EOF'
(program
  (name "nested-generic")
  (version "0.1")
  (struct Box
    (type-params T)
    (field value T))
  (fn unwrap
    (type-params T)
    (params (boxed (type-app Box T)))
    (returns i32)
    (do (return 0)))
  (entry main (params) (returns i32) (do (return 0))))
EOF
"$WEAVEC" fmt --output "$TMP/nested-generic.fmt" "$TMP/nested-generic.weave"
if ! grep -Fq '(fn unwrap (type-params T) ((boxed (type-app Box T))) i32' \
  "$TMP/nested-generic.fmt"; then
  printf 'generic-type-params: nested type application was not preserved\n' >&2
  cat "$TMP/nested-generic.fmt" >&2
  exit 1
fi
"$WEAVEC" --frontend "$TMP/nested-generic.wir" "$TMP/nested-generic.fmt" \
  2>"$TMP/nested-generic.stderr" || {
  printf 'generic-type-params: formatted nested generic source was rejected\n' >&2
  cat "$TMP/nested-generic.stderr" >&2
  exit 1
}

# An ordinary function must not gain a clause it never declared.
cat > "$TMP/plain-fn.weave" <<'EOF'
(program
  (name "plain-fn")
  (version "0.1")
  (fn double
    (params (value i32))
    (returns i32)
    (do (return (op add value value))))
  (entry main (params) (returns i32) (do (return 0))))
EOF
"$WEAVEC" fmt --output "$TMP/plain-fn.fmt" "$TMP/plain-fn.weave"
if grep -Fq 'type-params' "$TMP/plain-fn.fmt"; then
  printf 'generic-type-params: non-generic fn gained a type-params clause\n' >&2
  cat "$TMP/plain-fn.fmt" >&2
  exit 1
fi

# Semantic index includes type-params in the public signature.
"$WEAVEC" analyze "$TMP/unused-generic.weave" \
  --semantic-index-json "$TMP/unused-generic.json"
python3 - "$TMP/unused-generic.json" <<'PY'
import json, sys
document = json.loads(open(sys.argv[1], encoding="utf-8").read())
symbols = {item["name"]: item for item in document["symbols"]}
signature = symbols["identity"]["signature"]["canonical"]
assert "(type-params T)" in signature, signature
PY

# Generic struct + type-app in a non-generic signature lowers the application
# as ptr and does not emit Box helpers.
cat > "$TMP/type-app-sig.weave" <<'EOF'
(program
  (name "type-app-sig")
  (version "0.1")
  (struct Box
    (type-params T)
    (field value T))
  (fn tag
    (params (value (type-app Box i32)))
    (returns i32)
    (do (return 7)))
  (entry main (params) (returns i32) (do (return 0))))
EOF
"$WEAVEC" --frontend "$TMP/type-app-sig.wir" "$TMP/type-app-sig.weave" \
  2>"$TMP/type-app-sig.stderr" || {
  printf 'generic-type-params: type-app signature was rejected\n' >&2
  cat "$TMP/type-app-sig.stderr" >&2
  exit 1
}
if grep -Fq 'Box_new' "$TMP/type-app-sig.wir"; then
  printf 'generic-type-params: generic struct helpers were emitted\n' >&2
  cat "$TMP/type-app-sig.wir" >&2
  exit 1
fi
if ! grep -Fq '(params (value ptr))' "$TMP/type-app-sig.wir"; then
  printf 'generic-type-params: type-app did not lower to ptr\n' >&2
  cat "$TMP/type-app-sig.wir" >&2
  exit 1
fi

# Calling a generic function is rejected until specialization exists.
cat > "$TMP/call-generic.weave" <<'EOF'
(program
  (name "call-generic")
  (version "0.1")
  (fn identity
    (type-params T)
    (params (value T))
    (returns T)
    (do (return value)))
  (entry main (params) (returns i32)
    (do (return (call identity 1)))))
EOF
expect_rejected call-generic 'requires explicit (type-args ...)'

# Malformed declarations.
cat > "$TMP/empty-params.weave" <<'EOF'
(program
  (name "empty-params")
  (version "0.1")
  (fn identity
    (type-params)
    (params (value i32))
    (returns i32)
    (do (return value)))
  (entry main (params) (returns i32) (do (return 0))))
EOF
expect_rejected empty-params 'must name at least one parameter'

cat > "$TMP/duplicate-param.weave" <<'EOF'
(program
  (name "duplicate-param")
  (version "0.1")
  (fn identity
    (type-params T T)
    (params (value T))
    (returns T)
    (do (return value)))
  (entry main (params) (returns i32) (do (return 0))))
EOF
expect_rejected duplicate-param 'duplicate type parameter T'

cat > "$TMP/reserved-param.weave" <<'EOF'
(program
  (name "reserved-param")
  (version "0.1")
  (fn identity
    (type-params i32)
    (params (value i32))
    (returns i32)
    (do (return value)))
  (entry main (params) (returns i32) (do (return 0))))
EOF
expect_rejected reserved-param 'shadows a reserved type'

cat > "$TMP/owned-still-rejected.weave" <<'EOF'
(program
  (name "owned-still-rejected")
  (version "0.1")
  (entry main (params) (returns i32)
    (do
      (let v (owned i32) 1)
      (return 0))))
EOF
expect_rejected owned-still-rejected \
  'type must be a name, not a compound expression'

cat > "$TMP/not-generic.weave" <<'EOF'
(program
  (name "not-generic")
  (version "0.1")
  (struct Point (field x i32) (field y i32))
  (fn use
    (params (value (type-app Point i32)))
    (returns i32)
    (do (return 0)))
  (entry main (params) (returns i32) (do (return 0))))
EOF
expect_rejected not-generic 'is not a generic type'

cat > "$TMP/arity.weave" <<'EOF'
(program
  (name "arity")
  (version "0.1")
  (struct Box
    (type-params T)
    (field value T))
  (fn use
    (params (value (type-app Box i32 i32)))
    (returns i32)
    (do (return 0)))
  (entry main (params) (returns i32) (do (return 0))))
EOF
expect_rejected arity 'expects 1 type argument(s), got 2'

cat > "$TMP/entry-generic.weave" <<'EOF'
(program
  (name "entry-generic")
  (version "0.1")
  (entry main
    (type-params T)
    (params)
    (returns i32)
    (do (return 0))))
EOF
expect_rejected entry-generic 'entry and extern cannot have type parameters'

printf 'generic-type-params: passed\n'
