#!/usr/bin/env python3
"""Detect strong/fallback gate predicates that the absorption law collapses.

Lab verifiers in this series express each sub-gate as a Strong path and a
Fallback path combined with ``or``. When the Fallback is exactly one of the
Strong path's conjuncts, boolean absorption applies::

    strong   = A and B
    fallback = B
    result   = strong or fallback     # (A and B) or B  ==  B

The result is identically ``B``, so every conjunct unique to the Strong path
is dead code and the sub-gate silently stops checking it. That is how a
verdict file was able to pass a gate whose raw recomputation contradicted it.

Absorption is not always a defect: a Strong path that is merely a stricter
variant of a substantive Fallback is a deliberate design. Those cases must be
declared in the allowlist with a reason, so the decision is reviewed rather
than assumed.

Usage::

    python3 scripts/detect_absorbed_predicates.py labs
    python3 scripts/detect_absorbed_predicates.py labs --allowlist scripts/absorbed-predicate-allowlist.txt

Exit codes: ``0`` when every finding is allowlisted, ``1`` when an
undeclared absorbed predicate is found.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

ASSIGNMENT = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*(.+?)\s*$")
DISJUNCTION = re.compile(
    r"^\(?\s*([A-Za-z_]\w*)\s*\)?\s+or\s+\(?\s*([A-Za-z_]\w*)\s*\)?$"
)


def flatten_continuations(text: str) -> str:
    """Join parenthesised multi-line predicates onto single lines.

    >>> flatten_continuations("x = (\\n    a\\n    or b\\n)")
    'x = (a or b)'
    """
    text = re.sub(r"\(\s*\n\s*", "(", text)
    text = re.sub(r"\s*\n\s*\)", ")", text)
    return re.sub(r"\n\s+(and|or)\s+", r" \1 ", text)


def conjuncts(expression: str) -> set[str]:
    """Split a predicate into its top-level ``and`` operands.

    >>> sorted(conjuncts("a and b and c"))
    ['a', 'b', 'c']
    >>> sorted(conjuncts("only_one"))
    ['only_one']
    """
    return {part.strip() for part in re.split(r"\band\b", expression) if part.strip()}


def find_absorbed(text: str) -> list[tuple[str, str, str, str, str]]:
    """Return ``(result, strong, strong_expr, fallback, fallback_expr)`` tuples.

    >>> src = "strong = a and b\\nfallback = b\\nresult = strong or fallback\\n"
    >>> [f[0] for f in find_absorbed(src)]
    ['result']

    A fallback that is a genuinely different predicate is not absorption:

    >>> src = "strong = a\\nfallback = b\\nresult = strong or fallback\\n"
    >>> find_absorbed(src)
    []

    Identical paths are reported by other review, not here:

    >>> src = "strong = b\\nfallback = b\\nresult = strong or fallback\\n"
    >>> find_absorbed(src)
    []
    """
    assignments: dict[str, str] = {}
    findings = []
    for line in flatten_continuations(text).splitlines():
        match = ASSIGNMENT.match(line)
        if not match:
            continue
        name, expression = match.group(1), match.group(2)
        assignments[name] = expression
        disjunction = DISJUNCTION.match(expression)
        if not disjunction:
            continue
        strong, fallback = disjunction.group(1), disjunction.group(2)
        strong_expr = assignments.get(strong)
        fallback_expr = assignments.get(fallback)
        if not strong_expr or not fallback_expr:
            continue
        if fallback_expr != strong_expr and fallback_expr in conjuncts(strong_expr):
            findings.append((name, strong, strong_expr, fallback, fallback_expr))
    return findings


def load_allowlist(path: pathlib.Path | None) -> set[str]:
    """Read ``<relative-path>::<result-name>`` keys, ignoring comments.

    >>> import tempfile, pathlib
    >>> with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as handle:
    ...     _ = handle.write("# note\\nlabs/x/verify.sh::b_pass  # justified\\n")
    ...     name = handle.name
    >>> sorted(load_allowlist(pathlib.Path(name)))
    ['labs/x/verify.sh::b_pass']
    """
    if path is None or not path.is_file():
        return set()
    entries = set()
    for line in path.read_text().splitlines():
        entry = line.split("#", 1)[0].strip()
        if entry:
            entries.add(entry)
    return entries


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", help="Directory to scan for verify.sh files")
    parser.add_argument("--allowlist", help="File of declared, justified exceptions")
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Base used to render allowlist keys as repository-relative paths",
    )
    args = parser.parse_args()

    allowed = load_allowlist(pathlib.Path(args.allowlist) if args.allowlist else None)
    repo_root = pathlib.Path(args.repo_root).resolve()
    undeclared = 0
    declared = 0

    for script in sorted(pathlib.Path(args.root).rglob("verify.sh")):
        try:
            relative = script.resolve().relative_to(repo_root).as_posix()
        except ValueError:
            relative = script.as_posix()
        for result, strong, strong_expr, fallback, fallback_expr in find_absorbed(
            script.read_text(errors="replace")
        ):
            key = f"{relative}::{result}"
            if key in allowed:
                declared += 1
                continue
            undeclared += 1
            print(f"{relative}: {result} = {strong} or {fallback}")
            print(f"    {strong} = {strong_expr}")
            print(f"    {fallback} = {fallback_expr}")
            print(
                f"    absorbed: '{result}' reduces to '{fallback_expr}' alone, so every "
                "other conjunct of the strong path is dead code"
            )
            print(f"    fix the predicate, or declare it as: {key}")

    print(f"\nundeclared absorbed predicates: {undeclared} (declared exceptions: {declared})")
    return 1 if undeclared else 0


if __name__ == "__main__":
    sys.exit(main())
