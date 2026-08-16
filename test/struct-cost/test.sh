#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# What struct operations cost, per escape class, in two profiles.
#
# `opt` is what actually runs: measured on --emit-optimized-llvm inside @main,
# after the optimizer has inlined the constructor and accessors and removed a
# non-escaping allocation entirely. Every fixture takes its values from the
# command line so nothing is constant-foldable.
#
# `raw` is what the compiler asked for, before any optimization, inside
# @program_main. It exists because "the optimizer removes it" and "the compiler
# never emitted it" are different claims, and only the second is a property of
# the compiler. Work that stops emitting an allocation shows up here while
# leaving `opt` unchanged -- which is exactly the shape of the stack-allocation
# work this baseline was extended for.
#
# Baseline: test/struct-cost/baseline.tsv. Regenerate with --write-baseline
# after an intentional change, and say in the commit why each number moved.
#
# Only allocation and memory traffic are recorded in `opt`. A call count was
# tried there and removed: it differs between platforms because inlining
# decisions do, so it measured the optimizer's judgement rather than what a
# struct costs. `raw` does count calls, and portably, because nothing has been
# inlined yet -- there is no optimizer judgement in it to differ. The columns
# kept here were identical on macOS arm64 and both Linux targets.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
BASELINE="${WEAVEC_STRUCT_COST_BASELINE:-$ROOT/test/struct-cost/baseline.tsv}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-struct-cost-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

MODE=check
case "${1:-}" in
  "") ;;
  --write-baseline) MODE=write ;;
  *) printf 'usage: %s [--write-baseline]\n' "$0" >&2; exit 2 ;;
esac

[[ -x "$WEAVEC" ]] || {
  printf 'struct-cost: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

# Announce before doing anything, so a failure producing no other output is
# still distinguishable from the suite never having started.
printf 'struct-cost: measuring raw and optimized profiles\n'

PRELUDE='(program
  (name "PROGRAM")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (extern free (params (value ptr)) (returns void))
  (struct Point (field x f64) (field y f64))
  (fn dot (params (a Point) (b Point)) (returns f64)
    (do (return (op add (op mul (field-get a x) (field-get b x))
                        (op mul (field-get a y) (field-get b y))))))'

# 1. Local, non-escaping. The control: this class is known to cost nothing, so a
# non-zero result here means the harness is measuring the wrong thing.
cat > "$TMP/local.weave" <<EOF
${PRELUDE/PROGRAM/struct-cost-local}
  (fn program_main (params) (returns i32)
    (do
      (let p Point (new Point (x (call parse_f64 (call arg 0))) (y (call parse_f64 (call arg 1)))))
      (let q Point (new Point (x (call parse_f64 (call arg 2))) (y (call parse_f64 (call arg 3)))))
      (let d f64 (call dot p q))
      (call free p)
      (call free q)
      (return (cast i32 d)))))
EOF

# 2. Escaped through an opaque boundary: the value is handed to a function the
# optimizer cannot see through, so it can no longer prove non-escape.
cat > "$TMP/escaped.weave" <<EOF
${PRELUDE/PROGRAM/struct-cost-escaped}
  (fn program_main (params) (returns i32)
    (do
      (let p Point (new Point (x (call parse_f64 (call arg 0))) (y (call parse_f64 (call arg 1)))))
      (call write_stdout_bytes p 16)
      (let d f64 (field-get p x))
      (call free p)
      (return (cast i32 d)))))
EOF

# 3. Stored in a container that outlives the constructing scope.
cat > "$TMP/stored.weave" <<EOF
${PRELUDE/PROGRAM/struct-cost-stored}
  (struct Holder (field first ptr) (field second ptr))
  (fn program_main (params) (returns i32)
    (do
      (let p Point (new Point (x (call parse_f64 (call arg 0))) (y (call parse_f64 (call arg 1)))))
      (let q Point (new Point (x (call parse_f64 (call arg 2))) (y (call parse_f64 (call arg 3)))))
      (let h Holder (new Holder (first p) (second q)))
      (call write_stdout_bytes h 16)
      (let d f64 (call dot p q))
      (call free p)
      (call free q)
      (call free h)
      (return (cast i32 d)))))
EOF

# 4. Built in a loop, so allocation count scales with input rather than being
# a fixed set the optimizer can unroll away.
cat > "$TMP/loop.weave" <<EOF
${PRELUDE/PROGRAM/struct-cost-loop}
  (fn program_main (params) (returns i32)
    (do
      (let limit i32 (cast i32 (call parse_f64 (call arg 0))))
      (let total f64 0.0)
      (let index i32 0)
      (while (condition (op less-than index limit))
        (do
          (let p Point (new Point (x (cast f64 index)) (y 2.0)))
          (set total (op add total (call dot p p)))
          (call free p)
          (set index (op add index 1))))
      (return (cast i32 total)))))
EOF

# Count what the class requests before any optimization, inside program_main.
#
# At this stage nothing is inlined, so the allocation itself is inside the
# generated NAME_new constructor rather than here. What is visible here, and
# what stack allocation would remove, is the *request*: one constructor call per
# struct value. So this counts constructor calls and stack slots rather than
# malloc directly.
#
# A call count is portable here for the reason it was not portable in the
# optimized measurement below: with no inlining there is no optimizer judgement
# to differ between platforms.
measure_raw() {
  awk '
    /^define[^@]*@program_main\(/ { inside = 1; found = 1; next }
    inside && /^}/ { inside = 0; next }
    inside {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line == "" || line ~ /^;/ || line ~ /^[A-Za-z0-9_.-]+:$/) next
      if (line ~ /call[^@]*@[A-Za-z_][A-Za-z0-9_]*_new\(/) new_calls++
      if (line ~ /call[^@]*@free\(/) free++
      if (line ~ /(^|= )alloca[[:space:]]/) alloca++
      if (line ~ /(^|= )load[[:space:]]/) load++
      if (line ~ /^store[[:space:]]/) store++
    }
    END {
      if (!found) { print "MISSING" > "/dev/stderr"; exit 3 }
      printf "%d\t%d\t%d\t%d\t%d\n", new_calls, free, alloca, load, store
    }
  ' "$1"
}

# Count what the class actually pays for, inside program_main only.
# program_main is internal with one caller, so the optimizer inlines it into
# main. Measuring it by name would silently measure nothing, so measure main and
# fail loudly if it is not there.
measure() {
  awk '
    /^define[^@]*@main\(/ { inside = 1; found = 1; next }
    inside && /^}/ { inside = 0; next }
    inside {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line == "" || line ~ /^;/ || line ~ /^[A-Za-z0-9_.-]+:$/) next
      if (line ~ /call[^@]*@malloc\(/) malloc++
      if (line ~ /call[^@]*@free\(/) free++
      if (line ~ /(^|= )alloca[[:space:]]/) alloca++
      if (line ~ /(^|= )load[[:space:]]/) load++
      if (line ~ /^store[[:space:]]/) store++
    }
    END {
      if (!found) { print "MISSING" > "/dev/stderr"; exit 3 }
      printf "%d\t%d\t%d\t%d\t%d\n", malloc, free, alloca, load, store
    }
  ' "$1"
}

collect() {
  for class in local escaped stored loop; do
    "$WEAVEC" build \
      "$ROOT/stdlib/process.weave" \
      "$ROOT/stdlib/parse.weave" \
      "$ROOT/stdlib/io.weave" \
      "$TMP/$class.weave" \
      -o "$TMP/$class.bin" \
      --emit-llvm "$TMP/$class.raw.ll" \
      --emit-optimized-llvm "$TMP/$class.opt.ll" >/dev/null 2>"$TMP/$class.err" || {
        printf 'struct-cost: %s failed to build\n' "$class" >&2
        cat "$TMP/$class.err" >&2
        exit 1
      }
  done

  printf '# weavec-struct-cost-v2\n'
  printf '#\n'
  printf '# raw: before optimization, inside program_main. new_calls is one per\n'
  printf '# struct value requested; stack allocation would remove them.\n'
  printf '# raw\tclass\tnew_calls\tfree\talloca\tload\tstore\n'
  for class in local escaped stored loop; do
    row="$(measure_raw "$TMP/$class.raw.ll")" || {
      printf 'struct-cost: no @program_main in raw output for %s\n' "$class" >&2
      exit 1
    }
    printf 'raw\t%s\t%s\n' "$class" "$row"
  done

  printf '#\n'
  printf '# optimized: what actually runs, inside @main after inlining.\n'
  printf '# opt\tclass\tmalloc\tfree\talloca\tload\tstore\n'
  for class in local escaped stored loop; do
    row="$(measure "$TMP/$class.opt.ll")" || {
      printf 'struct-cost: no @main in optimized output for %s\n' "$class" >&2
      exit 1
    }
    printf 'opt\t%s\t%s\n' "$class" "$row"
  done
}

collect > "$TMP/measured.tsv"

if [[ "$MODE" == write ]]; then
  cp "$TMP/measured.tsv" "$BASELINE"
  printf 'struct-cost: baseline written to %s\n' "$BASELINE"
  cat "$BASELINE"
  exit 0
fi

[[ -f "$BASELINE" ]] || {
  printf 'struct-cost: missing baseline %s; run with --write-baseline\n' \
    "$BASELINE" >&2
  exit 1
}

if ! cmp -s "$BASELINE" "$TMP/measured.tsv"; then
  # Printed on stdout, not only stderr: when this fails in CI the diff is the
  # whole diagnosis, and a harness whose failure detail is hard to recover is
  # not much of a harness.
  printf 'struct-cost: measured cost differs from the recorded baseline\n'
  printf '=== measured ===\n'
  cat "$TMP/measured.tsv"
  printf '=== recorded ===\n'
  cat "$BASELINE"
  printf '=== diff ===\n'
  diff -u "$BASELINE" "$TMP/measured.tsv" || true
  printf '\nIf this change is intentional, rerun with --write-baseline and say\n' >&2
  printf 'in the commit message why each number moved.\n' >&2
  exit 1
fi

# The local class is the control. If it ever costs something, either the
# optimizer stopped promoting non-escaping structs or this harness is measuring
# the wrong function.
local_row="$(awk -F'\t' '$1 == "opt" && $2 == "local"' "$BASELINE")"
local_malloc="$(printf '%s' "$local_row" | cut -f3)"
local_load="$(printf '%s' "$local_row" | cut -f6)"
if [[ "$local_malloc" -ne 0 || "$local_load" -ne 0 ]]; then
  printf 'struct-cost: the local class is no longer free (malloc=%s load=%s)\n' \
    "$local_malloc" "$local_load" >&2
  exit 1
fi

printf 'struct-cost: passed\n'
