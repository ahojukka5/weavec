#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independent statevector oracle for dumped ZX pipeline cases.

Compares IN vs OPT circuits up to global phase. This is not the same
implementation that performed the rewrite.
"""
from __future__ import annotations

import cmath
import math
import sys
from pathlib import Path

TOL = 1e-8

KIND = {
    1: "H",
    2: "X",
    4: "Z",
    5: "CNOT",
    6: "CZ",
    9: "RX",
    11: "RZ",
    12: "S",
    13: "Sdg",
    14: "T",
    15: "Tdg",
}


def mat_mul(a: list[list[complex]], b: list[list[complex]]) -> list[list[complex]]:
    n = len(a)
    out = [[0j] * n for _ in range(n)]
    for i in range(n):
        for k in range(n):
            if a[i][k] == 0:
                continue
            for j in range(n):
                out[i][j] += a[i][k] * b[k][j]
    return out


def ident(n: int) -> list[list[complex]]:
    return [[1 if i == j else 0 for j in range(n)] for i in range(n)]


def rz(ticks: int) -> list[list[complex]]:
    half = ticks * math.pi / 8
    return [[cmath.exp(-1j * half), 0], [0, cmath.exp(1j * half)]]


def rx(ticks: int) -> list[list[complex]]:
    half = ticks * math.pi / 8
    c = math.cos(half)
    s = math.sin(half)
    return [[c, -1j * s], [-1j * s, c]]


def h() -> list[list[complex]]:
    s = 1 / math.sqrt(2)
    return [[s, s], [s, -s]]


def x() -> list[list[complex]]:
    return [[0, 1], [1, 0]]


def z() -> list[list[complex]]:
    return [[1, 0], [0, -1]]


def embed(nq: int, q: int, g: list[list[complex]]) -> list[list[complex]]:
    dim = 1 << nq
    out = [[0j] * dim for _ in range(dim)]
    for i in range(dim):
        for j in range(dim):
            bits_ok = True
            for b in range(nq):
                if b == q:
                    continue
                if ((i >> b) & 1) != ((j >> b) & 1):
                    bits_ok = False
                    break
            if not bits_ok:
                continue
            out[i][j] = g[(i >> q) & 1][(j >> q) & 1]
    return out


def cnot(nq: int, c: int, t: int) -> list[list[complex]]:
    dim = 1 << nq
    out = [[0j] * dim for _ in range(dim)]
    for i in range(dim):
        j = i
        if (i >> c) & 1:
            j ^= 1 << t
        out[j][i] = 1
    return out


def gate_u(kind: int, q0: int, q1: int, param: int, nq: int) -> list[list[complex]]:
    if kind == 1:
        return embed(nq, q0, h())
    if kind == 2:
        return embed(nq, q0, x())
    if kind == 4:
        return embed(nq, q0, z())
    if kind == 11:
        return embed(nq, q0, rz(param))
    if kind == 9:
        return embed(nq, q0, rx(param))
    if kind == 12:
        return embed(nq, q0, rz(2))
    if kind == 13:
        return embed(nq, q0, rz(-2))
    if kind == 14:
        return embed(nq, q0, rz(1))
    if kind == 15:
        return embed(nq, q0, rz(-1))
    if kind == 5:
        return cnot(nq, q0, q1)
    raise ValueError(f"unsupported kind {kind}")


def circuit_nq(gates: list[tuple[int, int, int, int, int]]) -> int:
    nq = 0
    for kind, q0, q1, q2, param in gates:
        nq = max(nq, q0 + 1, (q1 + 1 if q1 >= 0 else 1), (q2 + 1 if q2 >= 0 else 1))
    return nq


def circuit_u(
    gates: list[tuple[int, int, int, int, int]], nq: int
) -> list[list[complex]]:
    u = ident(1 << nq)
    for kind, q0, q1, q2, param in gates:
        u = mat_mul(gate_u(kind, q0, q1, param, nq), u)
    return u


def equal_up_to_phase(a: list[list[complex]], b: list[list[complex]]) -> bool:
    if len(a) != len(b):
        return False
    n = len(a)
    ref = None
    for i in range(n):
        for j in range(n):
            if abs(a[i][j]) > TOL or abs(b[i][j]) > TOL:
                if abs(a[i][j]) > TOL:
                    ref = b[i][j] / a[i][j] if a[i][j] != 0 else None
                    if ref is not None:
                        break
        if ref is not None:
            break
    if ref is None:
        return True
    if abs(ref) < TOL:
        return False
    ref = ref / abs(ref)
    for i in range(n):
        for j in range(n):
            if abs(a[i][j] * ref - b[i][j]) > 1e-6:
                return False
    return True


def parse(text: str) -> dict[str, tuple[list, list]]:
    cases: dict[str, tuple[list, list]] = {}
    name = None
    section = None
    inn: list = []
    opt: list = []
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("CASE "):
            name = line[5:].strip()
            inn, opt = [], []
            section = None
        elif line == "IN":
            section = "in"
        elif line == "OPT":
            section = "opt"
        elif line == "END":
            if name is not None:
                cases[name] = (inn, opt)
            name = None
            section = None
        elif section in ("in", "opt") and line:
            parts = line.split()
            kind, q0, q1, q2, param = (int(parts[0]), int(parts[1]), int(parts[2]),
                                       int(parts[3]), int(parts[4]))
            row = (kind, q0, q1, q2, param)
            if section == "in":
                inn.append(row)
            else:
                opt.append(row)
    return cases


def main() -> int:
    text = Path(sys.argv[1]).read_text(encoding="utf-8") if len(sys.argv) > 1 else sys.stdin.read()
    cases = parse(text)
    if not cases:
        print("oracle: no cases", file=sys.stderr)
        return 1
    for name, (inn, opt) in cases.items():
        nq = max(circuit_nq(inn), circuit_nq(opt), 1)
        if not equal_up_to_phase(circuit_u(inn, nq), circuit_u(opt, nq)):
            print(f"oracle: {name} not equivalent", file=sys.stderr)
            return 1
        print(f"oracle: {name} equivalent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
