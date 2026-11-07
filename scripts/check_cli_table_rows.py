#!/usr/bin/env python3
"""Check that each Azure CLI fence documents every command path and long flag.

This supplements ``validate_cli_explanations.py``, which verifies table presence
and termination. Pass the Markdown files to audit as positional arguments.
"""

from __future__ import annotations

import argparse
import re
import shlex
from dataclasses import dataclass
from pathlib import Path
from typing import cast


FENCE = re.compile(r"^\s*```(?P<language>\S*)")
LONG_FLAG = re.compile(r"(?<![A-Za-z0-9_-])(--[A-Za-z0-9][A-Za-z0-9-]*)")


@dataclass(frozen=True)
class Finding:
    path: Path
    line: int
    message: str


def command_requirements(block: list[str]) -> tuple[set[str], set[str]]:
    """Return distinct ``az`` command paths and long flags in a bash fence.

    >>> command_requirements(["az containerapp show \\\\", "  --name app --output json"])
    ({'az containerapp show'}, {'--name', '--output'})
    >>> command_requirements(["az group list", "", "az account show --query name"])
    ({'az account show', 'az group list'}, {'--query'})
    """
    commands: set[str] = set()
    flags: set[str] = set()
    for line in block:
        flags.update(LONG_FLAG.findall(line))
        stripped = line.strip()
        if not stripped.startswith("az "):
            continue
        try:
            tokens = shlex.split(stripped.removesuffix("\\").strip())
        except ValueError:
            tokens = stripped.removesuffix("\\").split()
        path: list[str] = []
        for token in tokens:
            if token.startswith("-"):
                break
            path.append(token)
        if len(path) >= 3:
            commands.add(" ".join(path))
    return commands, flags


def following_table(lines: list[str], start: int) -> tuple[int, list[str]] | None:
    """Return the first nearby explanation table's start and body rows."""
    index = start
    while index < len(lines) and not lines[index].strip():
        index += 1
    if index + 1 >= len(lines) or not lines[index].lstrip().startswith("|"):
        return None
    if "---" not in lines[index + 1]:
        return None
    rows: list[str] = []
    cursor = index + 2
    while cursor < len(lines) and lines[cursor].lstrip().startswith("|"):
        rows.append(lines[cursor])
        cursor += 1
    return index, rows


def first_cell(row: str) -> str:
    cells = row.strip().strip("|").split("|")
    return cells[0].strip().strip("`") if cells else ""


def validate_file(path: Path) -> list[Finding]:
    lines = path.read_text(encoding="utf-8").splitlines()
    findings: list[Finding] = []
    index = 0
    while index < len(lines):
        match = FENCE.match(lines[index])
        if not match or match.group("language") != "bash":
            index += 1
            continue
        start = index + 1
        cursor = start
        while cursor < len(lines) and not FENCE.match(lines[cursor]):
            cursor += 1
        block = lines[start:cursor]
        commands, flags = command_requirements(block)
        if not commands:
            index = cursor + 1
            continue
        table = following_table(lines, cursor + 1)
        if table is None:
            findings.append(Finding(path, start + 1, "missing explanation table"))
            index = cursor + 1
            continue
        _, rows = table
        cells = {first_cell(row) for row in rows}
        missing_commands = sorted(
            command for command in commands if not any(cell.startswith(command) for cell in cells)
        )
        missing_flags = sorted(flag for flag in flags if flag not in cells)
        if missing_commands:
            findings.append(
                Finding(path, start + 1, "missing command rows: " + ", ".join(missing_commands))
            )
        if missing_flags:
            findings.append(
                Finding(path, start + 1, "missing flag rows: " + ", ".join(missing_flags))
            )
        index = cursor + 1
    return findings


def main() -> None:
    parser = argparse.ArgumentParser()
    _ = parser.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args()
    files = cast(list[Path], args.files)
    findings = [finding for path in files for finding in validate_file(path)]
    if findings:
        for finding in findings:
            print(f"{finding.path}:{finding.line}: {finding.message}")
        raise SystemExit(f"{len(findings)} incomplete CLI explanation table(s).")
    print("Every Azure CLI fence documents each command path and long flag.")


if __name__ == "__main__":
    main()
