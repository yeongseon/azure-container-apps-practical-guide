#!/usr/bin/env python3
"""Validate that Azure CLI code fences have nearby explanation tables."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path
from typing import cast


AZ_PATTERN = re.compile(r"(^|[^A-Za-z0-9_-])az\s+[A-Za-z0-9_-]")
FENCE_PATTERN = re.compile(r"^(\s*)```")

_HOUSE_FIRST_CELLS = {
    "flag",
    "parameter",
    "code",
    "setting",
    "tool",
    "variable",
    "key",
    "key flags",
}


@dataclass(frozen=True)
class Finding:
    path: Path
    line: int
    message: str


def has_az_command(block: list[str]) -> bool:
    return any(AZ_PATTERN.search(line) for line in block)


def parse_az_commands(block: list[str]) -> dict[str, set[str]]:
    """Return Azure CLI command paths and their long flags from a Bash fence.

    The parser treats each ``az`` occurrence as a separate invocation, including
    command substitutions and later pipeline stages. Command examples in this
    repository put options after the command path, so the first long option
    terminates the path and the remaining long options belong to that command.

    >>> parse_az_commands(["az account show --output table"])
    {'az account show': {'--output'}}
    >>> result = parse_az_commands(["ID=$(az account show --query id --output tsv)", "az group show --name x"])
    >>> result == {'az account show': {'--output', '--query'}, 'az group show': {'--name'}}
    True
    >>> parse_az_commands(["az one show --name x | az two list --output table"])
    {'az one show': {'--name'}, 'az two list': {'--output'}}
    """
    text = "\n".join(block).replace("\\\n", " ")
    starts = list(re.finditer(r"(?<![A-Za-z0-9_-])az\s+", text))
    commands: dict[str, set[str]] = {}
    for index, match in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
        invocation = text[match.start() : end]
        first_flag = re.search(r"\s--[A-Za-z0-9][A-Za-z0-9-]*", invocation)
        path_text = invocation[: first_flag.start()] if first_flag else invocation
        path_tokens = re.findall(r"[A-Za-z0-9_-]+", path_text)
        if len(path_tokens) < 2:
            continue
        command = " ".join(path_tokens)
        flags = set(re.findall(r"(?<![A-Za-z0-9_-])--[A-Za-z0-9][A-Za-z0-9-]*", invocation))
        commands.setdefault(command, set()).update(flags)
    return commands


def find_unowned_single_command_flags(
    commands: dict[str, set[str]], table_first_cells: list[str]
) -> list[tuple[str, str]]:
    """Find flags that need an owning-command qualifier in a multi-command fence.

    Flags shared by multiple commands may use an unqualified row. A flag used by
    only one command must name that command in the same first cell.

    >>> commands = {'az extension add': {'--name', '--upgrade'}, 'az account show': {'--output'}}
    >>> cells = ['az extension add', '--name (az extension add)', '--upgrade (az extension add)', 'az account show', '--output']
    >>> find_unowned_single_command_flags(commands, cells)
    [('--output', 'az account show')]
    >>> cells[-1] = '--output (az account show)'
    >>> find_unowned_single_command_flags(commands, cells)
    []
    >>> shared = {'az one show': {'--name'}, 'az two show': {'--name'}}
    >>> find_unowned_single_command_flags(shared, ['az one show', 'az two show', '--name'])
    []
    """
    if len(commands) < 2:
        return []
    owners: dict[str, set[str]] = {}
    for command, flags in commands.items():
        for flag in flags:
            owners.setdefault(flag, set()).add(command)
    normalized_cells = [cell.replace("`", "").lower() for cell in table_first_cells]
    findings: list[tuple[str, str]] = []
    for flag, flag_owners in sorted(owners.items()):
        if len(flag_owners) != 1:
            continue
        owner = next(iter(flag_owners))
        if not any(flag in cell and owner in cell for cell in normalized_cells):
            findings.append((flag, owner))
    return findings


def fence_language(line: str) -> str:
    """Return the language token from a fence opener like '```bash {.copy}'.

    Handles fences of arbitrary length (```, ````, `````, ...) by
    stripping all leading backticks before parsing the language token.
    Returns an empty string for closing fences or unlabeled fences.

    >>> fence_language("```bash")
    'bash'
    >>> fence_language("```bash {.copy}")
    'bash'
    >>> fence_language("    ```python")
    'python'
    >>> fence_language("````bash")
    'bash'
    >>> fence_language("`````bash")
    'bash'
    >>> fence_language("```")
    ''
    >>> fence_language("````")
    ''
    """
    info = line.strip().lstrip("`").strip()
    return info.split(maxsplit=1)[0] if info else ""


def has_following_table(lines: list[str], start_index: int) -> bool:
    """Return True when a Markdown table appears shortly after a fence."""
    checked = 0
    i = start_index
    while i < len(lines) and checked < 8:
        stripped = lines[i].strip()
        if not stripped:
            i += 1
            checked += 1
            continue
        if stripped.startswith(("!!!", "???", "##", "```")):
            return False
        if stripped.startswith("|") and i + 1 < len(lines):
            next_line = lines[i + 1].strip()
            return next_line.startswith("|") and "---" in next_line
        i += 1
        checked += 1
    return False


def following_table_first_cells(lines: list[str], start_index: int) -> list[str]:
    i = start_index
    while i < len(lines) and i < start_index + 8:
        if lines[i].strip().startswith("|") and i + 1 < len(lines):
            if "---" not in lines[i + 1]:
                return []
            cells: list[str] = []
            i += 2
            while i < len(lines) and lines[i].strip().startswith("|"):
                cells.append(lines[i].strip().strip("|").split("|", 1)[0].strip())
                i += 1
            return cells
        if lines[i].strip().startswith(("!!!", "???", "##", "```")):
            return []
        i += 1
    return []


def _table_cells(line: str) -> list[str]:
    """Split a Markdown table row into trimmed, lower-cased cell values.

    Leading and trailing pipes produce empty edge cells, which are dropped.

    >>> _table_cells("| Command | Purpose |")
    ['command', 'purpose']
    >>> _table_cells("| Command/Parameter | Purpose |")
    ['command/parameter', 'purpose']
    >>> _table_cells("| Key flags |")
    ['key flags']
    """
    return [cell.strip().lower() for cell in line.strip().strip("|").split("|")]


def _is_house_table_header(cells: list[str]) -> bool:
    """Return True for an explanation-table header row.

    Recognition is header-agnostic across the series' repository-local
    conventions: any first cell beginning with ``command`` (covering
    ``Command``, ``Command/Parameter``, ``Command/Code``, ``Command/Flag``,
    ``Command part``, ``Command flag``, ``Command or Query``) or one of the
    known callout headers (``Flag``, ``Parameter``, ``Code``, ``Setting``,
    ``Tool``, ``Variable``, ``Key``, ``Key flags``). Column count is not
    constrained, so three-column variants such as ``Command | Purpose | Key
    flags`` and single-column ``Key flags`` callouts are both covered.

    >>> _is_house_table_header(["command", "purpose"])
    True
    >>> _is_house_table_header(["command/parameter", "purpose"])
    True
    >>> _is_house_table_header(["command", "why it is used"])
    True
    >>> _is_house_table_header(["command", "purpose", "key flags"])
    True
    >>> _is_house_table_header(["flag", "description"])
    True
    >>> _is_house_table_header(["key flags"])
    True
    >>> _is_house_table_header(["name", "value"])
    False
    """
    if not cells:
        return False
    first = cells[0]
    return first.startswith("command") or first in _HOUSE_FIRST_CELLS


def find_unterminated_tables(lines: list[str]) -> list[int]:
    """Return the 1-based line numbers where an explanation table is immediately
    followed by a non-blank line.

    python-markdown's ``tables`` extension treats the first non-blank line after
    a table as another table row (a phantom ``<td>...</td>`` cell) unless a blank
    line terminates the table. Fenced code regions are tracked so that pipe-led
    lines inside ```` ```kusto ```` blocks (``| where``, ``| summarize``) are not
    mistaken for table rows.

    >>> ok = ["| Command | Purpose |", "| --- | --- |", "| `az x` | y |", "", "next"]
    >>> find_unterminated_tables(ok)
    []
    >>> bad = ["| Command | Purpose |", "| --- | --- |", "| `az x` | y |", "Example output:"]
    >>> find_unterminated_tables(bad)
    [4]
    >>> variant = ["| Command/Parameter | Purpose |", "| --- | --- |", "| `az x` | y |", "prose"]
    >>> find_unterminated_tables(variant)
    [4]
    >>> why = ["| Command | Why it is used |", "| --- | --- |", "| `az x` | y |", "prose"]
    >>> find_unterminated_tables(why)
    [4]
    >>> eof = ["| Command | Purpose |", "| --- | --- |", "| `az x` | y |"]
    >>> find_unterminated_tables(eof)
    []
    >>> kql = ["```kusto", "AzureActivity", "| where x == 1", "```", "prose"]
    >>> find_unterminated_tables(kql)
    []
    """
    hits: list[int] = []
    i = 0
    n = len(lines)
    in_fence = False
    while i < n:
        if FENCE_PATTERN.match(lines[i]):
            in_fence = not in_fence
            i += 1
            continue
        if (
            not in_fence
            and lines[i].lstrip().startswith("|")
            and _is_house_table_header(_table_cells(lines[i]))
        ):
            j = i
            while j < n and lines[j].lstrip().startswith("|"):
                j += 1
            if j < n and lines[j].strip() != "":
                hits.append(j + 1)
            i = j
            continue
        i += 1
    return hits


def validate_file(path: Path, require_command_ownership: bool = False) -> list[Finding]:
    lines = path.read_text(encoding="utf-8").splitlines()
    findings: list[Finding] = []
    for line_no in find_unterminated_tables(lines):
        findings.append(
            Finding(
                path=path,
                line=line_no,
                message=(
                    "Explanation table must be followed by a blank line "
                    "(otherwise the next line is absorbed as a phantom table row)."
                ),
            )
        )
    in_fence = False
    fence_indent = ""
    block_start = 0
    block_lines: list[str] = []

    for index, line in enumerate(lines):
        fence = FENCE_PATTERN.match(line)
        if not in_fence and fence:
            # Only track ```bash fences. Other languages (mermaid, text, json,
            # kusto, etc.) may legitimately contain `az ...` text in diagram
            # labels or console-output transcripts, and do not need an
            # explanation table per AGENTS.md ("Shell: Use bash for all CLI
            # examples").
            if fence_language(line) != "bash":
                continue
            in_fence = True
            fence_indent = fence.group(1)
            block_start = index + 1
            block_lines = []
            continue

        if in_fence and fence and len(fence.group(1)) <= len(fence_indent):
            if has_az_command(block_lines):
                if not has_following_table(lines, index + 1):
                    findings.append(
                        Finding(
                            path=path,
                            line=block_start,
                            message=(
                                "Azure CLI code fence must be followed by a "
                                "command explanation table."
                            ),
                        )
                    )
                elif require_command_ownership:
                    commands = parse_az_commands(block_lines)
                    table_cells = following_table_first_cells(lines, index + 1)
                    for flag, owner in find_unowned_single_command_flags(
                        commands, table_cells
                    ):
                        findings.append(
                            Finding(
                                path=path,
                                line=block_start,
                                message=(
                                    f"{flag} is used only by `{owner}` in this "
                                    + "multi-command fence; its table row must name "
                                    + "that owning command."
                                ),
                            )
                        )
            in_fence = False
            fence_indent = ""
            block_lines = []
            continue

        if in_fence:
            block_lines.append(line)

    return findings


def validate_docs(
    docs_dir: Path,
    ownership_files: set[Path] | None = None,
) -> list[Finding]:
    findings: list[Finding] = []
    ownership_files = ownership_files or set()
    for path in sorted(docs_dir.glob("**/*.md")):
        findings.extend(validate_file(path, path.resolve() in ownership_files))
    return findings


def main() -> None:
    parser = argparse.ArgumentParser()
    _ = parser.add_argument("--docs-dir", type=Path, default=Path("docs"))
    _ = parser.add_argument(
        "--ownership-file",
        action="append",
        type=Path,
        default=[],
        help="Also enforce command-qualified rows for single-owner flags in this file.",
    )
    args = parser.parse_args()

    ownership_paths = cast(list[Path], args.ownership_file)
    docs_dir = cast(Path, args.docs_dir)
    ownership_files = {path.resolve() for path in ownership_paths}
    findings = validate_docs(docs_dir, ownership_files)
    if findings:
        for finding in findings:
            print(f"{finding.path}:{finding.line}: {finding.message}")
        raise SystemExit(
            f"{len(findings)} Azure CLI code fence(s) need explanation tables."
        )

    print("All Azure CLI code fences have following explanation tables.")


if __name__ == "__main__":
    main()
