#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Deterministic mutation-fuzzing lane for surface and WIR inputs (#387).

Seed S-expression fixtures, apply a recorded-seed mutator, and assert that
weavec terminates through documented exits rather than crashing, hanging,
emitting invalid diagnostics, or publishing a partial artifact. Accepted
random programs are not checked for semantic correctness.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import shutil
import stat
import subprocess
import sys
import tempfile
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence, Union

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SEED = 387
PR_BUDGET = 24
NIGHTLY_BUDGET = 192
PR_TIMEOUT_S = 8.0
NIGHTLY_TIMEOUT_S = 10.0
MAX_DEPTH = 64
STABLE_BUILD_EXITS = frozenset({0, 2, 10, 11, 12, 13, 14, 15})
BACKEND_EXITS = frozenset({0, 1, 2})
CRASH_MARKERS = (
    "Segmentation fault",
    "SIGSEGV",
    "SIGBUS",
    "SIGABRT",
    "SIGILL",
    "Bus error",
    "Aborted",
    "stack overflow",
    "AddressSanitizer",
    "UBSAN",
)

SURFACE_HEADS = (
    "program",
    "name",
    "version",
    "entry",
    "fn",
    "params",
    "returns",
    "do",
    "return",
    "let",
    "set",
    "if",
    "condition",
    "then",
    "else",
    "while",
    "call",
    "add_i32",
    "const_i32",
    "i32",
)
WIR_HEADS = (
    "core-module",
    "core-version",
    "decls",
    "fn",
    "params",
    "returns",
    "do",
    "return",
    "let",
    "add_i32",
    "const_i32",
    "i32",
)

Node = Union["Atom", "List"]


class Atom:
    __slots__ = ("text",)

    def __init__(self, text: str) -> None:
        self.text = text


class List:
    __slots__ = ("children",)

    def __init__(self, children: list[Node] | None = None) -> None:
        self.children = children if children is not None else []


class ParseError(Exception):
    pass


class OracleFailure(Exception):
    def __init__(self, message: str, replay: Path | None = None) -> None:
        super().__init__(message)
        self.replay = replay


def skip_ws_and_comments(text: str, index: int) -> int:
    length = len(text)
    while index < length:
        char = text[index]
        if char in " \t\r\n":
            index += 1
            continue
        if char == ";":
            while index < length and text[index] != "\n":
                index += 1
            continue
        break
    return index


def parse_string(text: str, index: int) -> tuple[Atom, int]:
    if text.startswith('"""', index):
        end = text.find('"""', index + 3)
        if end < 0:
            raise ParseError("unterminated multiline string")
        return Atom(text[index : end + 3]), end + 3
    if index >= len(text) or text[index] != '"':
        raise ParseError("expected string")
    start = index
    index += 1
    while index < len(text):
        char = text[index]
        if char == "\\":
            index += 2
            continue
        if char == '"':
            return Atom(text[start : index + 1]), index + 1
        index += 1
    raise ParseError("unterminated string")


def parse_raw_string(text: str, index: int) -> tuple[Atom, int]:
    if not text.startswith('#"', index):
        raise ParseError("expected raw string")
    start = index
    index += 2
    while index < len(text):
        if text[index] == '"':
            return Atom(text[start : index + 1]), index + 1
        index += 1
    raise ParseError("unterminated raw string")


def parse_atom(text: str, index: int) -> tuple[Atom, int]:
    start = index
    length = len(text)
    while index < length and text[index] not in " \t\r\n();":
        index += 1
    if index == start:
        raise ParseError("empty atom")
    return Atom(text[start:index]), index


def parse_list(text: str, index: int) -> tuple[List, int]:
    if index >= len(text) or text[index] != "(":
        raise ParseError("expected '('")
    index += 1
    children: list[Node] = []
    while True:
        index = skip_ws_and_comments(text, index)
        if index >= len(text):
            raise ParseError("unclosed list")
        if text[index] == ")":
            return List(children), index + 1
        node, index = parse_node(text, index)
        children.append(node)


def parse_node(text: str, index: int) -> tuple[Node, int]:
    index = skip_ws_and_comments(text, index)
    if index >= len(text):
        raise ParseError("unexpected end of input")
    if text[index] == "(":
        return parse_list(text, index)
    if text.startswith('"""', index):
        return parse_string(text, index)
    if text.startswith('#"', index):
        return parse_raw_string(text, index)
    if text[index] == '"':
        return parse_string(text, index)
    if text[index] == ")":
        raise ParseError("unexpected ')'")
    return parse_atom(text, index)


def parse_document(text: str) -> Node:
    index = skip_ws_and_comments(text, 0)
    if index >= len(text):
        raise ParseError("empty document")
    node, index = parse_node(text, index)
    index = skip_ws_and_comments(text, index)
    if index != len(text):
        raise ParseError("trailing input after first form")
    return node


def render(node: Node) -> str:
    if isinstance(node, Atom):
        return node.text
    inner = " ".join(render(child) for child in node.children)
    return f"({inner})" if inner else "()"


def clone(node: Node) -> Node:
    if isinstance(node, Atom):
        return Atom(node.text)
    return List([clone(child) for child in node.children])


def depth_of(node: Node) -> int:
    if isinstance(node, Atom):
        return 0
    if not node.children:
        return 1
    return 1 + max(depth_of(child) for child in node.children)


def collect_lists(node: Node) -> list[List]:
    found: list[List] = []

    def walk(current: Node) -> None:
        if isinstance(current, List):
            found.append(current)
            for child in current.children:
                walk(child)

    walk(node)
    return found


def collect_subtrees(node: Node) -> list[Node]:
    found: list[Node] = [node]

    def walk(current: Node) -> None:
        if isinstance(current, List):
            for child in current.children:
                found.append(child)
                walk(child)

    walk(node)
    return found


def is_int_atom(atom: Atom) -> bool:
    text = atom.text
    if text.startswith("-"):
        text = text[1:]
    return bool(text) and text.isdigit()


def is_string_atom(atom: Atom) -> bool:
    return len(atom.text) >= 2 and atom.text[0] == '"' and atom.text[-1] == '"'


def mutate_atom(atom: Atom, rng: random.Random) -> None:
    if is_int_atom(atom):
        value = int(atom.text)
        atom.text = rng.choice(
            [str(-value), str(value + 1), "0", "99999", "not-an-int"]
        )
        return
    if is_string_atom(atom):
        inner = atom.text[1:-1]
        choice = rng.randint(0, 2)
        if choice == 0:
            atom.text = '""'
        elif choice == 1:
            atom.text = f'"{inner}x"'
        else:
            atom.text = f'"{inner[:-1]}"' if inner else '"?"'
        return
    ident = atom.text
    atom.text = rng.choice([ident + "_x", "???", ident[:1] + "Z" + ident[1:]])


def delete_child(target: List, rng: random.Random) -> bool:
    if not target.children:
        return False
    del target.children[rng.randrange(len(target.children))]
    return True


def duplicate_child(target: List, rng: random.Random) -> bool:
    if not target.children:
        return False
    index = rng.randrange(len(target.children))
    target.children.insert(index, clone(target.children[index]))
    return True


def swap_children(target: List, rng: random.Random) -> bool:
    if len(target.children) < 2:
        return False
    left, right = rng.sample(range(len(target.children)), 2)
    target.children[left], target.children[right] = (
        target.children[right],
        target.children[left],
    )
    return True


def change_head(
    target: List, rng: random.Random, heads: Sequence[str]
) -> bool:
    if not target.children or not isinstance(target.children[0], Atom):
        return False
    target.children[0] = Atom(rng.choice(tuple(heads)))
    return True


def mutate_token(target: List, rng: random.Random) -> bool:
    atoms = [child for child in target.children if isinstance(child, Atom)]
    if not atoms:
        return False
    mutate_atom(rng.choice(atoms), rng)
    return True


def nest_list(root: Node, target: List, rng: random.Random) -> bool:
    remaining = MAX_DEPTH - depth_of(root)
    if remaining < 2:
        return False
    extra = rng.randint(1, min(3, remaining))
    if not target.children:
        wrapped: Node = List([])
    else:
        wrapped = clone(rng.choice(target.children))
    for _ in range(extra):
        wrapped = List([wrapped])
    target.children.append(wrapped)
    return depth_of(root) <= MAX_DEPTH


def splice_subtree(
    target: List, rng: random.Random, pool: Sequence[Node]
) -> bool:
    if not pool:
        return False
    grafted = clone(rng.choice(pool))
    if not target.children:
        target.children.append(grafted)
        return True
    index = rng.randrange(len(target.children))
    target.children[index] = grafted
    return True


def perturb_wir_envelope(root: Node, rng: random.Random) -> bool:
    if not isinstance(root, List) or not root.children:
        return False
    if isinstance(root.children[0], Atom):
        choice = rng.randint(0, 3)
        if choice == 0:
            root.children[0] = Atom("not-a-core-module")
            return True
        if choice == 1:
            root.children.insert(1, List([Atom("core-version"), Atom("2")]))
            return True
        if choice == 2 and len(root.children) > 1:
            del root.children[1]
            return True
    for child in root.children:
        if (
            isinstance(child, List)
            and child.children
            and isinstance(child.children[0], Atom)
            and child.children[0].text == "core-version"
        ):
            if len(child.children) < 2:
                child.children.append(Atom("99"))
            else:
                child.children[1] = Atom(rng.choice(["1", "2", "99", "nope"]))
            return True
    return False


def apply_mutation(
    root: Node,
    rng: random.Random,
    pool: Sequence[Node],
    heads: Sequence[str],
    wir: bool,
) -> str:
    lists = collect_lists(root)
    if not lists:
        return "none"
    target = rng.choice(lists)
    names = [
        "delete_child",
        "duplicate_child",
        "swap_children",
        "change_head",
        "mutate_token",
        "nest_list",
        "splice_subtree",
    ]
    if wir:
        names.append("perturb_wir_envelope")
    rng.shuffle(names)
    for name in names:
        if name == "delete_child" and delete_child(target, rng):
            return name
        if name == "duplicate_child" and duplicate_child(target, rng):
            return name
        if name == "swap_children" and swap_children(target, rng):
            return name
        if name == "change_head" and change_head(target, rng, heads):
            return name
        if name == "mutate_token" and mutate_token(target, rng):
            return name
        if name == "nest_list" and nest_list(root, target, rng):
            return name
        if name == "splice_subtree" and splice_subtree(target, rng, pool):
            return name
        if name == "perturb_wir_envelope" and perturb_wir_envelope(root, rng):
            return name
    return "none"


def load_seed_files(root: Path) -> tuple[list[Path], list[Path]]:
    surface = sorted((root / "test/conformance/cases").glob("*/*.weave"))
    extra = root / "test/correctness/surface/01_return_42.weave"
    if extra.is_file():
        surface.append(extra)
    wir = sorted(
        path
        for path in (root / "test/correctness/wir").glob("*.wir")
        if path.is_file()
    )
    if not surface:
        raise SystemExit("mutation-fuzz: no surface seed fixtures")
    if not wir:
        raise SystemExit("mutation-fuzz: no WIR seed fixtures")
    return surface, wir


def parse_seed(path: Path) -> Node | None:
    try:
        return parse_document(path.read_text(encoding="utf-8"))
    except (OSError, ParseError, UnicodeDecodeError):
        return None


def build_pool(paths: Iterable[Path]) -> list[Node]:
    pool: list[Node] = []
    for path in paths:
        node = parse_seed(path)
        if node is None:
            continue
        pool.extend(collect_subtrees(node)[:32])
    return pool


@dataclass
class CaseResult:
    index: int
    lane: str
    seed_path: Path
    mutations: list[str]
    exit_code: int | None
    outcome: str


def is_crash_status(status: int | None) -> bool:
    if status is None:
        return False
    if status < 0:
        return True
    if status >= 128:
        return True
    return False


def stderr_looks_like_crash(text: str) -> bool:
    return any(marker in text for marker in CRASH_MARKERS)


def validate_span(span: object, context: str) -> None:
    if span is None:
        return
    if not isinstance(span, dict):
        raise OracleFailure(f"{context}: span is not an object or null")
    for field in (
        "start_byte",
        "end_byte",
        "start_line",
        "start_column",
        "end_line",
        "end_column",
    ):
        if field not in span:
            raise OracleFailure(f"{context}: span missing {field}")
        if not isinstance(span[field], int):
            raise OracleFailure(f"{context}: span.{field} is not an integer")


def validate_diagnostic(entry: object, index: int) -> None:
    context = f"diagnostics[{index}]"
    if not isinstance(entry, dict):
        raise OracleFailure(f"{context} is not an object")
    required = (
        "code",
        "severity",
        "phase",
        "message",
        "source",
        "span_origin",
        "span",
        "analysis_complete",
        "candidates",
        "related_locations",
        "repairs",
    )
    for field in required:
        if field not in entry:
            raise OracleFailure(f"{context} missing {field}")
    for field in ("code", "severity", "phase", "message", "span_origin"):
        if not isinstance(entry[field], str) or not entry[field]:
            raise OracleFailure(f"{context}.{field} must be a non-empty string")
    if entry["source"] is not None and not isinstance(entry["source"], str):
        raise OracleFailure(f"{context}.source must be a string or null")
    if not isinstance(entry["analysis_complete"], bool):
        raise OracleFailure(f"{context}.analysis_complete must be a boolean")
    validate_span(entry["span"], context)
    if not isinstance(entry["candidates"], list):
        raise OracleFailure(f"{context}.candidates must be an array")
    if not isinstance(entry["related_locations"], list):
        raise OracleFailure(f"{context}.related_locations must be an array")
    if not isinstance(entry["repairs"], list):
        raise OracleFailure(f"{context}.repairs must be an array")


def validate_diagnostics_document(document: object, process_exit: int) -> None:
    if not isinstance(document, dict):
        raise OracleFailure("diagnostics document is not an object")
    for field in (
        "format",
        "status",
        "phase",
        "exit_code",
        "raw_exit_code",
        "diagnostics",
    ):
        if field not in document:
            raise OracleFailure(f"diagnostics missing {field}")
    if document["format"] != "weavec-diagnostics-v1":
        raise OracleFailure("diagnostics format is not weavec-diagnostics-v1")
    if document["status"] not in ("succeeded", "failed"):
        raise OracleFailure("diagnostics status is not succeeded or failed")
    if not isinstance(document["phase"], str) or not document["phase"]:
        raise OracleFailure("diagnostics phase must be a non-empty string")
    if not isinstance(document["exit_code"], int):
        raise OracleFailure("diagnostics exit_code must be an integer")
    if not isinstance(document["raw_exit_code"], int):
        raise OracleFailure("diagnostics raw_exit_code must be an integer")
    if document["exit_code"] != process_exit:
        raise OracleFailure(
            "diagnostics exit_code "
            f"{document['exit_code']} does not match process exit {process_exit}"
        )
    if document["exit_code"] not in STABLE_BUILD_EXITS:
        raise OracleFailure(
            f"diagnostics exit_code {document['exit_code']} is not a "
            "documented weavec build phase exit"
        )
    succeeded = document["status"] == "succeeded"
    if succeeded and process_exit != 0:
        raise OracleFailure("succeeded diagnostics with a non-zero process exit")
    if not succeeded and process_exit == 0:
        raise OracleFailure("failed diagnostics with a zero process exit")
    entries = document["diagnostics"]
    if not isinstance(entries, list):
        raise OracleFailure("diagnostics.diagnostics must be an array")
    if not succeeded and not entries:
        raise OracleFailure("failed diagnostics document has no entries")
    for index, entry in enumerate(entries):
        validate_diagnostic(entry, index)


def write_failure(
    dump_dir: Path,
    case: CaseResult,
    source_text: str,
    stdout: str,
    stderr: str,
) -> Path:
    dump_dir.mkdir(parents=True, exist_ok=True)
    suffix = ".weave" if case.lane == "surface" else ".wir"
    replay = dump_dir / f"fail-{case.index:04d}{suffix}"
    meta = dump_dir / f"fail-{case.index:04d}.txt"
    replay.write_text(source_text, encoding="utf-8")
    meta.write_text(
        "\n".join(
            [
                f"index={case.index}",
                f"lane={case.lane}",
                f"seed={case.seed_path}",
                f"mutations={' '.join(case.mutations)}",
                f"exit={case.exit_code}",
                f"outcome={case.outcome}",
                "stdout:",
                stdout,
                "stderr:",
                stderr,
                "",
            ]
        ),
        encoding="utf-8",
    )
    return replay


def run_compiler(
    command: list[str],
    timeout: float,
    cwd: Path,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            cwd=str(cwd),
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise OracleFailure(
            f"compiler exceeded {timeout:.1f}s timeout (hang)"
        ) from exc


def oracle_surface(
    weavec: Path,
    source: Path,
    work: Path,
    timeout: float,
) -> int:
    output = work / "program"
    diagnostics = work / "diagnostics.json"
    for path in (output, diagnostics):
        if path.exists():
            path.unlink()
    result = run_compiler(
        [
            str(weavec),
            "build",
            str(source),
            "-o",
            str(output),
            "--diagnostics-json",
            str(diagnostics),
        ],
        timeout,
        work,
    )
    stderr = result.stderr or ""
    if is_crash_status(result.returncode) or stderr_looks_like_crash(stderr):
        raise OracleFailure(
            f"compiler crashed (exit {result.returncode})\n{stderr}"
        )
    if result.returncode not in STABLE_BUILD_EXITS:
        raise OracleFailure(
            f"undocumented weavec build exit {result.returncode}\n{stderr}"
        )
    if result.returncode != 0 and output.exists():
        raise OracleFailure(f"failed build published output {output}")
    if result.returncode == 0 and not output.exists():
        raise OracleFailure("successful build did not publish the executable")
    if not diagnostics.is_file():
        raise OracleFailure("diagnostics JSON was not published")
    try:
        document = json.loads(diagnostics.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise OracleFailure(f"diagnostics JSON is not valid: {exc}") from exc
    validate_diagnostics_document(document, result.returncode)
    return result.returncode


def oracle_wir(
    weavec: Path,
    source: Path,
    work: Path,
    timeout: float,
) -> int:
    output = work / "out.ll"
    if output.exists():
        output.unlink()
    result = run_compiler(
        [str(weavec), "--backend", str(source), str(output)],
        timeout,
        work,
    )
    stderr = result.stderr or ""
    if is_crash_status(result.returncode) or stderr_looks_like_crash(stderr):
        raise OracleFailure(
            f"backend crashed (exit {result.returncode})\n{stderr}"
        )
    if result.returncode not in BACKEND_EXITS:
        raise OracleFailure(
            f"undocumented --backend exit {result.returncode}\n{stderr}"
        )
    if result.returncode != 0 and output.exists():
        raise OracleFailure(f"failed backend published {output}")
    if result.returncode == 0 and not output.is_file():
        raise OracleFailure("successful backend did not publish LLVM")
    return result.returncode


def resolve_budget(value: str) -> tuple[int, float]:
    if value in ("pr", "smoke"):
        return PR_BUDGET, PR_TIMEOUT_S
    if value in ("nightly", "ladder"):
        return NIGHTLY_BUDGET, NIGHTLY_TIMEOUT_S
    count = int(value)
    if count < 1:
        raise SystemExit("mutation-fuzz: budget must be at least 1")
    timeout = PR_TIMEOUT_S if count <= PR_BUDGET else NIGHTLY_TIMEOUT_S
    return count, timeout


def campaign(
    root: Path,
    weavec: Path,
    seed: int,
    budget: int,
    timeout: float,
    dump_dir: Path,
) -> int:
    surface_files, wir_files = load_seed_files(root)
    surface_pool = build_pool(surface_files)
    wir_pool = build_pool(wir_files)
    rng = random.Random(seed)
    print(
        f"mutation-fuzz: seed={seed} budget={budget} timeout={timeout:.1f}s "
        f"surface_seeds={len(surface_files)} wir_seeds={len(wir_files)}"
    )
    accepted = 0
    rejected = 0
    produced = 0
    attempts = 0
    while produced < budget:
        attempts += 1
        if attempts > budget * 32:
            raise SystemExit(
                "mutation-fuzz: could not produce the requested number of cases"
            )
        wir = produced % 2 == 1
        files = wir_files if wir else surface_files
        pool = wir_pool if wir else surface_pool
        heads = WIR_HEADS if wir else SURFACE_HEADS
        seed_path = files[rng.randrange(len(files))]
        parsed = parse_seed(seed_path)
        if parsed is None:
            continue
        tree = clone(parsed)
        mutations = [
            apply_mutation(tree, rng, pool, heads, wir)
            for _ in range(rng.randint(1, 4))
        ]
        work = dump_dir / f"case-{produced:04d}"
        if work.exists():
            shutil.rmtree(work)
        work.mkdir(parents=True, exist_ok=True)
        suffix = ".wir" if wir else ".weave"
        source = work / f"input{suffix}"
        text = render(tree) + "\n"
        source.write_text(text, encoding="utf-8")
        case = CaseResult(
            index=produced,
            lane="wir" if wir else "surface",
            seed_path=seed_path,
            mutations=mutations,
            exit_code=None,
            outcome="ok",
        )
        try:
            if wir:
                status = oracle_wir(weavec, source, work, timeout)
            else:
                status = oracle_surface(weavec, source, work, timeout)
        except OracleFailure as exc:
            case.outcome = str(exc)
            replay = write_failure(dump_dir, case, text, "", str(exc))
            print(
                f"mutation-fuzz: FAIL case {produced} lane={case.lane} "
                f"seed={seed} file={replay}",
                file=sys.stderr,
            )
            print(
                "mutation-fuzz: replay: python3 scripts/mutation_fuzz.py "
                f"--replay={replay} --weavec={weavec}",
                file=sys.stderr,
            )
            raise SystemExit(1) from exc
        case.exit_code = status
        if status == 0:
            accepted += 1
        else:
            rejected += 1
        produced += 1
    print(
        f"mutation-fuzz: passed {produced} cases "
        f"(accepted={accepted} rejected={rejected})"
    )
    return 0


def replay_one(weavec: Path, path: Path, timeout: float, dump_dir: Path) -> int:
    work = dump_dir / "replay"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True, exist_ok=True)
    source = work / path.name
    shutil.copy2(path, source)
    try:
        if path.suffix == ".wir":
            status = oracle_wir(weavec, source, work, timeout)
        else:
            status = oracle_surface(weavec, source, work, timeout)
    except OracleFailure as exc:
        print(f"mutation-fuzz: replay failed: {exc}", file=sys.stderr)
        return 1
    print(f"mutation-fuzz: replay ok exit={status} path={path}")
    return 0


def replay_regressions(
    root: Path, weavec: Path, timeout: float, dump_dir: Path
) -> int:
    directory = root / "test/mutation-fuzz/regressions"
    if not directory.is_dir():
        return 0
    files = sorted(
        [
            path
            for path in directory.iterdir()
            if path.is_file() and path.suffix in {".weave", ".wir"}
        ]
    )
    for path in files:
        if replay_one(weavec, path, timeout, dump_dir) != 0:
            print(
                f"mutation-fuzz: regression still fails: {path}",
                file=sys.stderr,
            )
            return 1
    if files:
        print(f"mutation-fuzz: {len(files)} promoted regressions passed")
    return 0


def write_stub(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def self_test(root: Path) -> int:
    sample = '(program (name "n") (do (return (const_i32 1))))'
    tree = parse_document(sample)
    if render(tree) != sample:
        raise SystemExit("mutation-fuzz: parse/print round-trip failed")
    raw = parse_document('(write #"raw\\n")')
    if render(raw) != '(write #"raw\\n")':
        raise SystemExit("mutation-fuzz: raw string round-trip failed")
    multiline = parse_document('(write """\nline\n""")')
    if render(multiline) != '(write """\nline\n""")':
        raise SystemExit("mutation-fuzz: multiline string round-trip failed")
    rng_a = random.Random(DEFAULT_SEED)
    rng_b = random.Random(DEFAULT_SEED)
    first = clone(tree)
    second = clone(tree)
    pool = collect_subtrees(tree)
    mut_a = apply_mutation(first, rng_a, pool, SURFACE_HEADS, False)
    mut_b = apply_mutation(second, rng_b, pool, SURFACE_HEADS, False)
    if mut_a != mut_b or render(first) != render(second):
        raise SystemExit("mutation-fuzz: identical seeds diverged")

    work = Path(tempfile.mkdtemp(prefix="weavec-mutation-oracle-"))
    try:
        crash = work / "stub-crash"
        hang = work / "stub-hang"
        partial = work / "stub-partial"
        bad_json = work / "stub-bad-json"
        good = work / "stub-good"
        shebang = f"#!{sys.executable}\n"
        write_stub(
            crash,
            shebang
            + "import os, signal\n"
            "os.kill(os.getpid(), signal.SIGSEGV)\n",
        )
        write_stub(
            hang,
            shebang + "import time\n" "time.sleep(30)\n",
        )
        write_stub(
            partial,
            shebang
            + "import sys\n"
            "from pathlib import Path\n"
            "args = sys.argv\n"
            "output = Path(args[args.index('-o') + 1])\n"
            "output.write_text('partial\\n', encoding='utf-8')\n"
            "sys.exit(10)\n",
        )
        write_stub(
            bad_json,
            shebang
            + "import sys\n"
            "from pathlib import Path\n"
            "args = sys.argv\n"
            "diag = Path(args[args.index('--diagnostics-json') + 1])\n"
            "diag.write_text('not-json\\n', encoding='utf-8')\n"
            "sys.exit(10)\n",
        )
        write_stub(
            good,
            shebang
            + "import json, sys\n"
            "from pathlib import Path\n"
            "args = sys.argv\n"
            "diag = Path(args[args.index('--diagnostics-json') + 1])\n"
            "diag.write_text(json.dumps({\n"
            '  "format": "weavec-diagnostics-v1",\n'
            '  "status": "failed",\n'
            '  "phase": "frontend",\n'
            '  "exit_code": 10,\n'
            '  "raw_exit_code": 1,\n'
            '  "diagnostics": [{\n'
            '    "code": "frontend.parse.unclosed-list",\n'
            '    "severity": "error",\n'
            '    "phase": "frontend",\n'
            '    "message": "unclosed list",\n'
            '    "source": "input.weave",\n'
            '    "span_origin": "parser",\n'
            '    "span": None,\n'
            '    "analysis_complete": False,\n'
            '    "candidates": [],\n'
            '    "related_locations": [],\n'
            '    "repairs": []\n'
            "  }]\n"
            "}), encoding='utf-8')\n"
            "sys.exit(10)\n",
        )
        source = work / "input.weave"
        source.write_text(sample + "\n", encoding="utf-8")

        def expect_fail(label: str, binary: Path, timeout: float = 2.0) -> None:
            case_dir = work / label
            case_dir.mkdir()
            try:
                oracle_surface(binary, source, case_dir, timeout)
            except OracleFailure:
                return
            raise SystemExit(f"mutation-fuzz: oracle missed {label}")

        expect_fail("crash", crash)
        expect_fail("hang", hang, timeout=0.2)
        expect_fail("partial", partial)
        expect_fail("bad-json", bad_json)

        ok_dir = work / "good-run"
        ok_dir.mkdir()
        status = oracle_surface(good, source, ok_dir, 2.0)
        if status != 10:
            raise SystemExit(
                f"mutation-fuzz: good reject stub returned {status}"
            )
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print("mutation-fuzz: self-test passed")
    _ = root
    return 0


def check_wiring(root: Path) -> int:
    problems: list[str] = []
    required = (
        root / "scripts/pr-compile.sh",
        root / "scripts/test-all.sh",
        root / "docs/mutation-fuzz.md",
        root / "docs/index.md",
        root / "test/mutation-fuzz/test.sh",
        root / "test/EXECUTION-MANIFEST",
    )
    for path in required:
        if not path.is_file():
            problems.append(f"missing {path.relative_to(root)}")
    compile_text = (root / "scripts/pr-compile.sh").read_text(encoding="utf-8")
    ladder_text = (root / "scripts/test-all.sh").read_text(encoding="utf-8")
    index_text = (root / "docs/index.md").read_text(encoding="utf-8")
    manifest = (root / "test/EXECUTION-MANIFEST").read_text(encoding="utf-8")
    if "mutation-fuzz" not in compile_text:
        problems.append("scripts/pr-compile.sh does not run mutation-fuzz")
    if "mutation-fuzz" not in ladder_text:
        problems.append("scripts/test-all.sh does not run mutation-fuzz")
    if "mutation-fuzz.md" not in index_text:
        problems.append("docs/index.md does not link mutation-fuzz.md")
    if "mutation-fuzz" not in manifest:
        problems.append("test/EXECUTION-MANIFEST does not classify mutation-fuzz")
    if problems:
        for problem in problems:
            print(f"mutation-fuzz: {problem}", file=sys.stderr)
        return 1
    print("mutation-fuzz: wiring check passed")
    return 0


def default_dump_dir(root: Path) -> Path:
    env = os.environ.get("WEAVEC_MUTATION_FUZZ_DUMP")
    if env:
        return Path(env)
    return root / "build/mutation-fuzz"


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Deterministic mutation-fuzzing lane for weavec (#387)."
    )
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument(
        "--budget",
        default=os.environ.get("WEAVEC_MUTATION_FUZZ_BUDGET", "pr"),
        help="pr, nightly, or a positive integer",
    )
    parser.add_argument("--weavec", type=Path, default=None)
    parser.add_argument("--dump-dir", type=Path, default=None)
    parser.add_argument("--replay", type=Path, default=None)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--check-wiring", action="store_true")
    parser.add_argument("--timeout", type=float, default=None)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.self_test:
        return self_test(ROOT)
    if args.check_wiring:
        return check_wiring(ROOT)
    dump_dir = args.dump_dir or default_dump_dir(ROOT)
    budget, default_timeout = resolve_budget(str(args.budget))
    timeout = args.timeout if args.timeout is not None else default_timeout
    weavec = args.weavec or Path(os.environ.get("WEAVEC", ROOT / "build/weavec"))
    if not weavec.is_file() or not os.access(weavec, os.X_OK):
        print(f"mutation-fuzz: compiler not found: {weavec}", file=sys.stderr)
        return 1
    if args.replay is not None:
        return replay_one(weavec, args.replay, timeout, dump_dir)
    regressions = replay_regressions(ROOT, weavec, timeout, dump_dir)
    if regressions != 0:
        return regressions
    return campaign(ROOT, weavec, args.seed, budget, timeout, dump_dir)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        raise SystemExit(1)
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)
