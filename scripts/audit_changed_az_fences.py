#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
from collections import defaultdict
from pathlib import Path


BASE = "origin/main"
FENCE = re.compile(r"^```bash\s*$")
AZ = re.compile(r"(?<![\w-])az\s+((?:[a-z][\w-]*\s+)+?)(?=--|[\"'$.(]|$)", re.M)
FLAG = re.compile(r"(?<!\S)(--[a-z][\w-]*)")
ROW = re.compile(r"^\|\s*`([^`]+)`\s*\|\s*(.*?)\s*\|\s*$")


def changed_pages() -> list[Path]:
    output = subprocess.check_output(
        ["git", "diff", "--name-only", f"{BASE}...HEAD", "--", "*.md"], text=True
    )
    return [Path(line) for line in output.splitlines() if line]


def normalize_command(raw: str) -> str:
    return "az " + " ".join(raw.split())


def audit(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    errors: list[str] = []
    index = 0
    while index < len(lines):
        if not FENCE.match(lines[index]):
            index += 1
            continue
        start = index + 1
        index += 1
        block: list[str] = []
        while index < len(lines) and not lines[index].startswith("```"):
            block.append(lines[index])
            index += 1
        text = "\n".join(block).replace("\\\n", " ")
        commands = {normalize_command(match.group(1)) for match in AZ.finditer(text)}
        if not commands:
            index += 1
            continue

        flag_commands: dict[str, set[str]] = defaultdict(set)
        for line in text.splitlines():
            active: dict[int, str] = {}
            depth = 0
            events = sorted(
                [(match.start(), "command", match) for match in AZ.finditer(line)]
                + [(match.start(), "flag", match) for match in FLAG.finditer(line)]
            )
            cursor = 0
            for position, kind, match in events:
                depth += line[cursor:position].count("$(")
                depth -= line[cursor:position].count(")")
                if kind == "command":
                    active[depth] = normalize_command(match.group(1))
                elif depth in active:
                    flag_commands[match.group(1)].add(active[depth])
                cursor = match.end()

        table_index = index + 1
        while table_index < len(lines) and not lines[table_index].strip():
            table_index += 1
        rows: dict[str, str] = {}
        if table_index + 1 < len(lines) and lines[table_index].lstrip().startswith("|"):
            table_index += 2
            while table_index < len(lines) and lines[table_index].lstrip().startswith("|"):
                match = ROW.match(lines[table_index])
                if match:
                    rows[match.group(1)] = match.group(2)
                table_index += 1

        expected = commands | set(flag_commands)
        actual = set(rows)
        for missing in sorted(expected - actual):
            errors.append(f"{path}:{start}: missing row `{missing}`")
        for extra in sorted(actual - expected):
            errors.append(f"{path}:{start}: extra row `{extra}`")

        if len(commands) > 1:
            for flag, owners in sorted(flag_commands.items()):
                if owners != commands and flag in rows:
                    description = rows[flag].lower()
                    absent = [owner for owner in owners if owner not in description]
                    if absent:
                        owners_text = ", ".join(sorted(owners))
                        errors.append(f"{path}:{start}: `{flag}` applies only to {owners_text}; description must name the command")
        index += 1
    return errors


def main() -> None:
    errors = [error for path in changed_pages() for error in audit(path)]
    if errors:
        print("\n".join(errors))
        raise SystemExit(1)
    print("All changed Markdown pages have exact Azure CLI row sets and attribution.")


if __name__ == "__main__":
    main()
