#!/usr/bin/env python3
import json
import pathlib
import sys


def load(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def entry(root: pathlib.Path, name: str) -> tuple[dict, bytes]:
    document = load(root / f"{name}.diagnostics.json")
    assert document["format"] == "weavec-diagnostics-v1"
    assert document["status"] == "failed"
    assert document["phase"] == "frontend"
    assert document["exit_code"] == 10
    assert len(document["diagnostics"]) == 1
    diagnostic = document["diagnostics"][0]
    assert diagnostic["phase"] == "frontend"
    assert diagnostic["severity"] == "error"
    assert diagnostic["span_origin"] == "compiler-semantic"
    assert diagnostic["analysis_complete"] is True
    assert diagnostic["span"] is not None
    assert diagnostic["candidates"] == []
    assert diagnostic["related_locations"] == []
    source_path = pathlib.Path(diagnostic["source"])
    return diagnostic, source_path.read_bytes()


def span_text(diagnostic: dict, source: bytes) -> bytes:
    span = diagnostic["span"]
    return source[span["start_byte"] : span["end_byte"]]


def replacement_span_text(repair: dict, source: bytes) -> bytes:
    span = repair["replacement_span"]
    return source[span["start_byte"] : span["end_byte"]]


def main() -> None:
    root = pathlib.Path(sys.argv[1])
    schema = load(pathlib.Path(sys.argv[2]))
    assert schema["$id"] == "urn:weavec:schema:diagnostics:v1"
    assert schema["properties"]["format"]["const"] == "weavec-diagnostics-v1"
    diagnostic_schema = schema["$defs"]["diagnostic"]
    for field in (
        "analysis_complete",
        "candidates",
        "related_locations",
        "repairs",
    ):
        assert field in diagnostic_schema["required"]
    assert schema["additionalProperties"] is True
    assert diagnostic_schema["additionalProperties"] is True

    unresolved, source = entry(root, "unresolved")
    assert unresolved["code"] == "frontend.symbol.unresolved"
    assert unresolved["symbol"] == "missing"
    assert span_text(unresolved, source) == b"missing"
    assert unresolved["repairs"] == []

    wrong_arity, source = entry(root, "wrong-arity")
    assert wrong_arity["code"] == "frontend.call.wrong-arity"
    assert wrong_arity["symbol"] == "add-two"
    assert wrong_arity["expected_count"] == 2
    assert wrong_arity["actual_count"] == 1
    assert span_text(wrong_arity, source) == b"(call add-two 40)"
    assert wrong_arity["repairs"] == []

    argument, source = entry(root, "argument-type")
    assert argument["code"] == "frontend.call.argument-type-mismatch"
    assert argument["symbol"] == "consume"
    assert argument["expected_type"] == "i32"
    assert argument["actual_type"] == "i64"
    assert argument["argument_index"] == 0
    assert argument["operand_role"] == "argument"
    assert span_text(argument, source) == b"wide"
    assert len(argument["repairs"]) == 1
    repair = argument["repairs"][0]
    assert repair["kind"] == "replace"
    assert repair["replacement"] == "(cast i32 wide)"
    assert repair["confidence"] == "guaranteed-local"
    assert replacement_span_text(repair, source) == b"wide"

    operator, source = entry(root, "operator-type")
    assert operator["code"] == "frontend.operator.operand-type-mismatch"
    assert operator["symbol"] == "add"
    assert operator["expected_type"] == "i32"
    assert operator["actual_type"] == "i64"
    assert operator["operand_role"] == "right"
    assert span_text(operator, source) == b"wide"
    assert len(operator["repairs"]) == 1
    repair = operator["repairs"][0]
    assert repair["replacement"] == "(cast i32 wide)"
    assert repair["confidence"] == "guaranteed-local"
    assert replacement_span_text(repair, source) == b"wide"

    invalid_cast, source = entry(root, "invalid-cast")
    assert invalid_cast["code"] == "frontend.cast.invalid"
    assert invalid_cast["symbol"] == "ptr"
    assert invalid_cast["expected_type"] == "ptr"
    assert invalid_cast["actual_type"] == "i32"
    assert invalid_cast["operand_role"] == "value"
    assert span_text(invalid_cast, source) == b"(cast ptr (const_i32 1))"
    assert invalid_cast["repairs"] == []

    first = (root / "unresolved.diagnostics.json").read_bytes()
    second = (root / "unresolved-second.diagnostics.json").read_bytes()
    assert first == second


if __name__ == "__main__":
    main()
