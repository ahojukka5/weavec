#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Standalone `(comment ...)` surface statements (#373). A comment is a reserved
# surface head with zero executable semantics: it is admitted in statement and
# declaration-body positions, its children are string literals, and lowering
# erases it after admission. WIR/LLVM preservation is issue #374 and is
# intentionally not exercised here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-comment-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'comment-statement: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

fail() {
  printf 'comment-statement: %s\n' "$*" >&2
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
  [[ "$status" -ne 0 ]] || fail "$name was accepted"
  grep -Fq "$needle" "$TMP/$name.stderr" || {
    printf 'expected: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    fail "$name missing diagnostic"
  }
}

# --------------------------------------------------------------------------
# Admission: comments parse and lower in every statement and declaration-body
# position, and leave nothing behind in WIR.
# --------------------------------------------------------------------------

cat > "$TMP/admit.weave" <<'EOF'
(program
  (name "admit")
  (version "0.1")
  (comment "A standalone declaration-body annotation.")
  (fn helper ((value i32)) i32
    (doc "Double the input.")
    (comment "The caller relies on the doubled value.")
    (return (* value 2)))
  (entry main () i32
    (comment "One line of text.")
    (comment
      "The next iteration deliberately uses the previous residual."
      "Do not reassociate this update.")
    (let total i32 0)
    (when (< total 1)
      (comment "A no-op statement inside a variadic control body.")
      (set total (helper 21)))
    (while (< total 0)
      (comment "A no-op statement inside a compact while body.")
      (set total 0))
    (for (range index 0 1)
      (do
        (comment "A no-op statement inside a for body.")
        (set total total)))
    (return total)))
EOF
"$WEAVEC" --frontend "$TMP/admit.wir" "$TMP/admit.weave" \
  2>"$TMP/admit.stderr" || {
  cat "$TMP/admit.stderr" >&2
  fail 'admitted comments were rejected'
}
grep -Fq 'comment' "$TMP/admit.wir" && fail 'erased comment reached WIR'
grep -Fq 'residual' "$TMP/admit.wir" && fail 'comment text reached WIR'

# A trailing comment is invisible to the returning rule: appending one must not
# turn a returning body into a fall-through body.
cat > "$TMP/trailing.weave" <<'EOF'
(program
  (name "trailing")
  (version "0.1")
  (entry main () i32
    (return 0)
    (comment "Nothing follows this return.")))
EOF
"$WEAVEC" --frontend "$TMP/trailing.wir" "$TMP/trailing.weave" \
  2>"$TMP/trailing.stderr" || {
  cat "$TMP/trailing.stderr" >&2
  fail 'a trailing comment broke the returning rule'
}

# Semicolon comments remain accepted compatibility input alongside the form.
cat > "$TMP/lexical.weave" <<'EOF'
; A lexical comment before the module.
(program
  (name "lexical")
  (version "0.1")
  (entry main () i32
    ; A lexical comment inside the body.
    (comment "An explicit tree node beside lexical trivia.")
    (return 0)))
EOF
"$WEAVEC" --frontend "$TMP/lexical.wir" "$TMP/lexical.weave" \
  2>"$TMP/lexical.stderr" || {
  cat "$TMP/lexical.stderr" >&2
  fail 'lexical comments stopped working'
}

# --------------------------------------------------------------------------
# Zero semantics: a native before/after pair differing only in comments
# produces identical WIR, identical stdout, and the same exit code.
# --------------------------------------------------------------------------

cat > "$TMP/before.weave" <<'EOF'
(program
  (name "runtime-effect")
  (version "0.1")
  (fn classify ((value i32)) i32
    (when (< value 0)
      (return 0))
    (return 1))
  (entry main () i32
    (call write_stdout "classified\n")
    (return (classify 7))))
EOF
cat > "$TMP/after.weave" <<'EOF'
(program
  (name "runtime-effect")
  (version "0.1")
  (comment "Classification is a pure predicate.")
  (fn classify ((value i32)) i32
    (comment "A negative input is not classifiable.")
    (when (< value 0)
      (comment "Report the unclassifiable case as zero.")
      (return 0))
    (return 1))
  (entry main () i32
    (comment
      "Adding or removing these annotations must not change the program."
      "They carry no executable semantics at all.")
    (call write_stdout "classified\n")
    (return (classify 7))))
EOF

command -v clang >/dev/null 2>&1 || fail 'clang is required for the native fixture'

for variant in before after; do
  "$WEAVEC" --frontend "$TMP/$variant.wir" \
    "$ROOT/stdlib/io.weave" "$TMP/$variant.weave" \
    2>"$TMP/$variant.fe.stderr" || {
    cat "$TMP/$variant.fe.stderr" >&2
    fail "$variant: frontend failed"
  }
  "$WEAVEC" --backend "$TMP/$variant.wir" "$TMP/$variant.ll" \
    2>"$TMP/$variant.be.stderr" || {
    cat "$TMP/$variant.be.stderr" >&2
    fail "$variant: backend failed"
  }
  clang "$TMP/$variant.ll" -o "$TMP/$variant.bin" \
    2>"$TMP/$variant.link.stderr" || {
    cat "$TMP/$variant.link.stderr" >&2
    fail "$variant: link failed"
  }
  set +e
  "$TMP/$variant.bin" >"$TMP/$variant.out" 2>"$TMP/$variant.err"
  printf '%s\n' "$?" > "$TMP/$variant.exit"
  set -e
done

cmp "$TMP/before.wir" "$TMP/after.wir" || fail 'comments changed emitted WIR'
# The generated header records the input path, which differs by construction.
for variant in before after; do
  grep -v '^; source: ' "$TMP/$variant.ll" > "$TMP/$variant.ll.body"
done
cmp "$TMP/before.ll.body" "$TMP/after.ll.body" || \
  fail 'comments changed generated LLVM IR'
cmp "$TMP/before.out" "$TMP/after.out" || fail 'comments changed program stdout'
cmp "$TMP/before.exit" "$TMP/after.exit" || fail 'comments changed the exit code'
grep -Fq 'classified' "$TMP/after.out" || fail 'program produced no stdout'
[[ "$(cat "$TMP/after.exit")" == "1" ]] || {
  printf 'exit: %s\n' "$(cat "$TMP/after.exit")" >&2
  fail 'unexpected program exit code'
}

# --------------------------------------------------------------------------
# Canonical formatting: complete-form inline within 80 columns, otherwise one
# string literal per line. Both shapes are byte-idempotent.
# --------------------------------------------------------------------------

cat > "$TMP/fmt.weave" <<'EOF'
(program
  (name "fmt")
  (version "0.1")
  (entry main () i32
    (comment      "one line"     )
    (comment "The next iteration deliberately uses the previous residual." "Do not reassociate this update.")
    (return 0)))
EOF
"$WEAVEC" fmt "$TMP/fmt.weave" || fail 'fmt failed'
grep -Fq '    (comment "one line")' "$TMP/fmt.weave" || {
  cat "$TMP/fmt.weave" >&2
  fail 'a short comment was not rendered inline'
}
grep -Fq '    (comment' "$TMP/fmt.weave" || fail 'missing multiline comment head'
grep -Fq '      "The next iteration deliberately uses the previous residual."' \
  "$TMP/fmt.weave" || {
  cat "$TMP/fmt.weave" >&2
  fail 'multiline comment text is not one literal per line'
}
grep -Fq '      "Do not reassociate this update.")' "$TMP/fmt.weave" || {
  cat "$TMP/fmt.weave" >&2
  fail 'multiline comment does not close after the last literal'
}
python3 - "$TMP/fmt.weave" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
for line in text.splitlines():
    assert len(line) <= 80, f"line exceeds 80 columns: {line!r}"
assert '(comment "The next iteration' not in text, \
    "long comment stayed on the head line"
PY
cp "$TMP/fmt.weave" "$TMP/fmt.once"
"$WEAVEC" fmt "$TMP/fmt.weave"
cmp "$TMP/fmt.once" "$TMP/fmt.weave" || fail 'formatting comments is not idempotent'
"$WEAVEC" fmt --check "$TMP/fmt.weave" || fail 'canonical comments failed --check'

# A one-line comment stays adjacent to the following multiline sibling; the
# blank separator moves before the comment. This is printer presentation only.
cat > "$TMP/adjacent.weave" <<'EOF'
(program
  (name "adjacent")
  (version "0.1")
  (entry main () i32
    (let value i32 1)
    (comment "Equal roots represent the repeated-root case.")
    (when (= value 1)
      (call write_stdout "the repeated-root branch deliberately exceeds eighty")
      (return 1))
    (return 0)))
EOF
"$WEAVEC" fmt "$TMP/adjacent.weave" || fail 'fmt failed on the adjacency case'
python3 - "$TMP/adjacent.weave" <<'PY'
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
index = next(i for i, line in enumerate(lines) if "repeated-root case" in line)
assert lines[index - 1].strip() == "", "no blank line before the comment"
assert lines[index + 1].lstrip().startswith("(when"), \
    f"comment is not adjacent to the multiline sibling: {lines[index + 1]!r}"
PY
cp "$TMP/adjacent.weave" "$TMP/adjacent.once"
"$WEAVEC" fmt "$TMP/adjacent.weave"
cmp "$TMP/adjacent.once" "$TMP/adjacent.weave" || \
  fail 'comment adjacency is not idempotent'

# --------------------------------------------------------------------------
# Deterministic diagnostics with stable exact spans.
# --------------------------------------------------------------------------

cat > "$TMP/no-text.weave" <<'EOF'
(program
  (name "no-text")
  (version "0.1")
  (entry main () i32
    (comment)
    (return 0)))
EOF
expect_rejected no-text \
  'weavec: surface comment: (comment) needs at least one string literal'

cat > "$TMP/non-string.weave" <<'EOF'
(program
  (name "non-string")
  (version "0.1")
  (entry main () i32
    (comment "text" 42)
    (return 0)))
EOF
expect_rejected non-string \
  'weavec: surface comment: comment text must be a string literal'

cat > "$TMP/non-string-form.weave" <<'EOF'
(program
  (name "non-string-form")
  (version "0.1")
  (entry main () i32
    (comment (+ 1 2))
    (return 0)))
EOF
expect_rejected non-string-form \
  'weavec: surface comment: comment text must be a string literal'

cat > "$TMP/value-position.weave" <<'EOF'
(program
  (name "value-position")
  (version "0.1")
  (entry main () i32
    (let value i32 (comment "no value"))
    (return value)))
EOF
expect_rejected value-position \
  'weavec: surface comment: comment is a statement, not an expression'

cat > "$TMP/return-position.weave" <<'EOF'
(program
  (name "return-position")
  (version "0.1")
  (entry main () i32
    (return (comment "no value"))))
EOF
expect_rejected return-position \
  'weavec: surface comment: comment is a statement, not an expression'

# `comment` is a reserved head, so direct-call resolution never sees it and a
# function may not claim the name.
cat > "$TMP/declared.weave" <<'EOF'
(program
  (name "declared")
  (version "0.1")
  (fn comment ((value i32)) i32
    (return value))
  (entry main () i32
    (return (comment 0))))
EOF
expect_rejected declared \
  'weavec: surface declaration: function name collides with reserved syntax comment'
grep -Fq 'unresolved function comment' "$TMP/declared.stderr" && \
  fail 'comment was resolved as a call target'
for name in no-text non-string non-string-form value-position; do
  grep -Fq 'unresolved function comment' "$TMP/$name.stderr" && \
    fail "$name: comment reached call resolution"
done

check_span() {
  local name="$1"
  local code="$2"
  local fragment="$3"
  set +e
  "$WEAVEC" build "$TMP/$name.weave" -o "$TMP/$name.bin" \
    --diagnostics-json "$TMP/$name.json" \
    >"$TMP/$name.build" 2>&1
  set -e
  python3 - "$TMP/$name.json" "$TMP/$name.weave" "$code" "$fragment" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
source = pathlib.Path(sys.argv[2]).read_bytes()
code = sys.argv[3]
fragment = sys.argv[4]
assert document["status"] == "failed", document["status"]
assert document["phase"] == "frontend", document["phase"]
entries = [item for item in document["diagnostics"] if item["code"] == code]
assert entries, [item["code"] for item in document["diagnostics"]]
entry = entries[0]
assert entry["span_origin"] == "compiler-semantic", entry["span_origin"]
span = entry["span"]
start = span["start_byte"]
end = span["end_byte"]
assert 0 <= start < end <= len(source), (start, end, len(source))
actual = source[start:end].decode("utf-8")
assert actual == fragment, (actual, fragment)
PY
}

check_span no-text frontend.comment.missing-text '(comment)'
check_span non-string frontend.comment.non-string-text '42'
check_span non-string-form frontend.comment.non-string-text '(+ 1 2)'
check_span value-position frontend.comment.expression-position \
  '(comment "no value")'
check_span declared frontend.declaration.reserved-syntax-name 'comment'

# --------------------------------------------------------------------------
# Capabilities publish the reserved canonical form.
# --------------------------------------------------------------------------

"$WEAVEC" capabilities --json > "$TMP/capabilities.json"
python3 - "$TMP/capabilities.json" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
forms = {item["head"]: item for item in document["surface"]["forms"]}
assert "comment" in forms, sorted(forms)
form = forms["comment"]
assert form["status"] == "canonical", form["status"]
assert form["arity"]["min_children"] == 1, form["arity"]
assert form["arity"]["max_children"] is None, form["arity"]
assert form["type_information"] == "none", form["type_information"]
assert form["feature"] == "source-comments", form["feature"]
assert form["canonical_replacement"] is None, form["canonical_replacement"]
roles = form["roles"]
assert len(roles) == 1, roles
assert roles[0]["name"] == "text", roles[0]
assert roles[0]["cardinality"] == "one-or-more", roles[0]
assert roles[0]["kind"] == "string", roles[0]
features = {item["id"]: item for item in document["features"]}
assert features["source-comments"]["status"] == "experimental"
assert features["source-comments"]["issue"] == 337
PY

printf 'comment-statement: admission, erasure, formatting, and diagnostics passed\n'
