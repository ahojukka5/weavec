#!/usr/bin/env python3
"""Validate weavec commit messages against CONTRIBUTING.md."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

SUBJECT_RE = re.compile(
    r"^(feat|fix|docs|test|refactor|perf|build|ci|chore)"
    r"(?:\([a-z0-9][a-z0-9._/-]*\))?!?: [^\s].*$"
)
BULLET_RE = re.compile(r"^- .+")
CONTINUATION_RE = re.compile(r"^  \S.*")
TRAILER_RE = re.compile(
    r"^(?:BREAKING CHANGE|[A-Za-z][A-Za-z-]+-by|"
    r"Co-authored-by|Signed-off-by|Reviewed-by|Acked-by|"
    r"Fixes|Closes|Refs):",
    re.IGNORECASE,
)


@dataclass
class Commit:
    sha: str
    message: str


def read_commits(revision_range: str) -> list[Commit]:
    result = subprocess.run(
        ["git", "log", "--reverse", "--format=%H%x00%B%x00", revision_range],
        check=True,
        stdout=subprocess.PIPE,
    )
    fields = result.stdout.decode("utf-8", errors="replace").split("\x00")
    commits: list[Commit] = []
    for index in range(0, len(fields) - 1, 2):
        sha = fields[index].strip()
        message = fields[index + 1].rstrip("\n")
        if sha:
            commits.append(Commit(sha=sha, message=message))
    return commits


def read_message_file(path: Path) -> list[Commit]:
    return [
        Commit(
            sha=str(path),
            message=path.read_text(encoding="utf-8").rstrip("\n"),
        )
    ]


def sentence_count(text: str) -> int:
    return len(re.findall(r"[.!?](?=\s|$)", text))


def validate(commit: Commit) -> list[str]:
    errors: list[str] = []
    lines = commit.message.splitlines()
    if not lines:
        return ["message is empty"]

    subject = lines[0]
    if len(subject) >= 72:
        errors.append(
            f"subject is {len(subject)} characters; it must be under 72"
        )
    if subject.endswith("."):
        errors.append("subject must not end with a period")
    if not SUBJECT_RE.fullmatch(subject):
        errors.append("subject must use an allowed Conventional Commit type")

    if len(lines) < 3 or lines[1] != "":
        errors.append("message must contain a blank line followed by a body")
        return errors

    body = lines[2:]
    while body and body[-1] == "":
        body.pop()
    if not body:
        errors.append("body is required")
        return errors

    for number, line in enumerate(body, start=3):
        if len(line) > 80:
            errors.append(
                f"line {number} is {len(line)} characters; maximum is 80"
            )
        if TRAILER_RE.match(line):
            errors.append(f"line {number} is a forbidden trailer or footer")

    bullet_start = next(
        (i for i, line in enumerate(body) if BULLET_RE.match(line)),
        None,
    )
    if bullet_start is None:
        summary_lines = body
        if any(line == "" for line in summary_lines):
            errors.append("body without bullets must contain only the summary")
    else:
        if bullet_start == 0:
            errors.append("body must open with a prose summary before bullets")
            summary_lines = []
        else:
            if body[bullet_start - 1] != "":
                errors.append("optional bullet details must follow one blank line")
                summary_lines = body[:bullet_start]
            else:
                summary_lines = body[: bullet_start - 1]
            if any(line == "" for line in summary_lines):
                errors.append("summary must be one continuous paragraph")

        detail_lines = body[bullet_start:]
        for index, line in enumerate(detail_lines, start=bullet_start + 3):
            if line == "":
                errors.append(
                    "blank lines are not allowed inside or after bullet details"
                )
            elif not BULLET_RE.match(line) and not CONTINUATION_RE.match(line):
                errors.append(
                    f"line {index} must be a bullet or a two-space "
                    "bullet continuation"
                )

    summary = " ".join(line.strip() for line in summary_lines if line.strip())
    count = sentence_count(summary)
    if count < 1 or count > 3:
        errors.append(
            "summary must contain one to three sentences ending in '.', '!' or '?'"
        )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--range", dest="revision_range")
    source.add_argument("--message-file", type=Path)
    args = parser.parse_args()

    try:
        commits = (
            read_commits(args.revision_range)
            if args.revision_range
            else read_message_file(args.message_file)
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        print(
            f"commit-policy: unable to read commits: {exc}",
            file=sys.stderr,
        )
        return 2

    if not commits:
        print("commit-policy: no commits found", file=sys.stderr)
        return 2

    failed = False
    for commit in commits:
        errors = validate(commit)
        if errors:
            failed = True
            print(f"commit-policy: {commit.sha}", file=sys.stderr)
            for error in errors:
                print(f"  - {error}", file=sys.stderr)

    if failed:
        return 1
    print(f"commit-policy: validated {len(commits)} commit(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
