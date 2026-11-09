#!/usr/bin/env python3
"""Validate that Azure CLI code fences have nearby explanation tables."""

from __future__ import annotations

import argparse
from collections import defaultdict
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


def normalize_explanation_skeleton(text: str) -> str:
    """Normalize volatile CLI details while preserving the prose structure.

    The normalization intentionally removes the substitutions commonly used to
    disguise generated prose: command paths, long flags, quoted or inline-code
    values, headings, and digits. Explanations that differ only in those details
    therefore share one skeleton.

    >>> normalize_explanation_skeleton(
    ...     'Requests `200` from `az containerapp logs show`, defining the log slice.'
    ... )
    'requests <value> from <az-command>, defining the log slice.'
    >>> normalize_explanation_skeleton(
    ...     'Requests "30" from az monitor metrics list --offset PT1H.'
    ... )
    'requests <value> from <az-command>.'
    """
    normalized = text.lower()
    normalized = re.sub(r"`az\s+[^`]+`", "<az-command>", normalized)
    normalized = re.sub(
        r"\baz\s+[a-z0-9_-]+(?:\s+[a-z0-9_-]+){1,4}",
        "<az-command>",
        normalized,
    )
    normalized = re.sub(r"`--[a-z0-9-]+`|--[a-z0-9-]+", "<flag>", normalized)
    normalized = re.sub(r'`[^`]+`|"[^"]*"|\'[^\']*\'|\$[a-z_][a-z0-9_]*', "<value>", normalized)
    normalized = re.sub(r"\b\d+(?:\.\d+)?\b", "<number>", normalized)
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return normalized


def find_repeated_explanation_skeletons(
    paths: list[Path], limit: int = 3
) -> list[tuple[str, list[tuple[Path, int]]]]:
    """Return explanation skeletons used more than ``limit`` times.

    >>> from tempfile import TemporaryDirectory
    >>> with TemporaryDirectory() as directory:
    ...     path = Path(directory) / "sample.md"
    ...     _ = path.write_text("\\n".join([
    ...         "| Command | Purpose |", "| --- | --- |",
    ...         "| `az one show` | Requests `10` from `az one show`, defining the log slice. |",
    ...         "| `az two show` | Requests `20` from `az two show`, defining the log slice. |",
    ...         "| `az three show` | Requests `30` from `az three show`, defining the log slice. |",
    ...         "| `az four show` | Requests `40` from `az four show`, defining the log slice. |",
    ...     ]), encoding="utf-8")
    ...     repeated = find_repeated_explanation_skeletons([path])
    ...     len(repeated), len(repeated[0][1])
    (1, 4)
    """
    occurrences: dict[str, list[tuple[Path, int]]] = defaultdict(list)
    for path in paths:
        lines = path.read_text(encoding="utf-8").splitlines()
        in_fence = False
        in_explanation_table = False
        for line_no, line in enumerate(lines, start=1):
            if FENCE_PATTERN.match(line):
                in_fence = not in_fence
                in_explanation_table = False
                continue
            if in_fence:
                continue
            if not line.lstrip().startswith("|"):
                in_explanation_table = False
                continue
            if _is_house_table_header(_table_cells(line)):
                in_explanation_table = True
                continue
            if not in_explanation_table:
                continue
            cells = line.strip().strip("|").split("|")
            if len(cells) < 2:
                continue
            if all(re.fullmatch(r"\s*:?-+:?\s*", cell) for cell in cells):
                continue
            purpose = cells[1].strip()
            if purpose:
                occurrences[normalize_explanation_skeleton(purpose)].append(
                    (path, line_no)
                )
    return sorted(
        (
            (skeleton, locations)
            for skeleton, locations in occurrences.items()
            if len(locations) > limit
        ),
        key=lambda item: (-len(item[1]), item[0]),
    )


def find_duplicate_table_bodies(
    paths: list[Path],
) -> list[tuple[tuple[str, ...], list[tuple[Path, int]]]]:
    """Return identical explanation-table bodies used by multiple fences.

    >>> from tempfile import TemporaryDirectory
    >>> with TemporaryDirectory() as directory:
    ...     path = Path(directory) / "sample.md"
    ...     _ = path.write_text("\\n".join([
    ...         "| Command | Purpose |", "| --- | --- |", "| `az x` | Checks x. |", "",
    ...         "| Command | Purpose |", "| --- | --- |", "| `az x` | Checks x. |", "",
    ...     ]), encoding="utf-8")
    ...     duplicates = find_duplicate_table_bodies([path])
    ...     len(duplicates), len(duplicates[0][1])
    (1, 2)
    """
    occurrences: dict[tuple[str, ...], list[tuple[Path, int]]] = defaultdict(list)
    for path in paths:
        lines = path.read_text(encoding="utf-8").splitlines()
        in_fence = False
        index = 0
        while index < len(lines):
            if FENCE_PATTERN.match(lines[index]):
                in_fence = not in_fence
                index += 1
                continue
            if (
                not in_fence
                and lines[index].lstrip().startswith("|")
                and _is_house_table_header(_table_cells(lines[index]))
            ):
                start = index + 1
                body: list[str] = []
                index += 2
                while index < len(lines) and lines[index].lstrip().startswith("|"):
                    body.append(lines[index].strip())
                    index += 1
                if body:
                    occurrences[tuple(body)].append((path, start))
                continue
            index += 1
    return sorted(
        (
            (body, locations)
            for body, locations in occurrences.items()
            if len(locations) > 1
        ),
        key=lambda item: (-len(item[1]), item[0]),
    )


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


def validate_file(path: Path) -> list[Finding]:
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
            if has_az_command(block_lines) and not has_following_table(
                lines, index + 1
            ):
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
            in_fence = False
            fence_indent = ""
            block_lines = []
            continue

        if in_fence:
            block_lines.append(line)

    return findings


def validate_docs(docs_dir: Path) -> list[Finding]:
    findings: list[Finding] = []
    for path in sorted(docs_dir.glob("**/*.md")):
        findings.extend(validate_file(path))
    return findings


def main() -> None:
    parser = argparse.ArgumentParser()
    _ = parser.add_argument("--docs-dir", type=Path, default=Path("docs"))
    _ = parser.add_argument(
        "--skeleton-files",
        type=Path,
        nargs="*",
        help=(
            "Markdown files whose explanation prose must not reuse a normalized "
            "skeleton more than three times."
        ),
    )
    args = parser.parse_args()
    docs_dir = cast(Path, args.docs_dir)
    skeleton_files = cast(list[Path] | None, args.skeleton_files)

    findings = validate_docs(docs_dir)
    if findings:
        for finding in findings:
            print(f"{finding.path}:{finding.line}: {finding.message}")
        raise SystemExit(
            f"{len(findings)} Azure CLI code fence(s) need explanation tables."
        )

    if skeleton_files:
        repeated = find_repeated_explanation_skeletons(skeleton_files)
        duplicates = find_duplicate_table_bodies(skeleton_files)
        if repeated or duplicates:
            for skeleton, locations in repeated:
                rendered = ", ".join(
                    f"{path}:{line}" for path, line in locations
                )
                print(
                    (
                        f"Repeated explanation skeleton ({len(locations)}x): "
                        f"{skeleton}\n  {rendered}"
                    )
                )
            for _, locations in duplicates:
                rendered = ", ".join(
                    f"{path}:{line}" for path, line in locations
                )
                print(f"Duplicate explanation table body:\n  {rendered}")
            raise SystemExit(
                (
                    f"{len(repeated)} explanation skeleton(s) exceed the limit of 3; "
                    f"{len(duplicates)} duplicate table body or bodies found."
                )
            )

    print("All Azure CLI code fences have following explanation tables.")


if __name__ == "__main__":
    main()
