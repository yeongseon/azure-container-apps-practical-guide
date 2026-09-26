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
import ast
import pathlib
import re
import sys

ASSIGNMENT = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*(.+?)\s*$")


def flatten_continuations(text: str) -> str:
    """Join parenthesised multi-line predicates onto single lines.

    >>> flatten_continuations("x = (\\n    a\\n    or b\\n)")
    'x = (a or b)'
    """
    text = re.sub(r"\(\s*\n\s*", "(", text)
    text = re.sub(r"\s*\n\s*\)", ")", text)
    return re.sub(r"\n\s+(and|or)\s+", r" \1 ", text)


def parse_expression(expression: str):
    """Parse a predicate into an AST node, or None when it is not Python.

    Parsing rather than string-splitting is what makes parenthesised and
    reordered predicates comparable; ``(a and b)`` and ``a and b`` produce
    the same node, and operand order is read from the tree rather than
    assumed.

    >>> parse_expression("a and b") is None
    False
    >>> parse_expression("not a valid ==== expression") is None
    True
    """
    try:
        return ast.parse(expression, mode="eval").body
    except SyntaxError:
        return None


def conjuncts(expression: str) -> set[str]:
    """Split a predicate into normalised top-level ``and`` operands.

    Outer parentheses are irrelevant to the boolean structure:

    >>> sorted(conjuncts("a and b")) == sorted(conjuncts("(a and b)"))
    True
    >>> sorted(conjuncts("a and b"))
    ['a', 'b']
    >>> sorted(conjuncts("only_one"))
    ['only_one']
    """
    node = parse_expression(expression)
    if node is None:
        return {expression.strip()}
    if isinstance(node, ast.BoolOp) and isinstance(node.op, ast.And):
        return {ast.unparse(operand) for operand in node.values}
    return {ast.unparse(node)}


def normalise(expression: str) -> str:
    """Render a predicate in a canonical form for comparison.

    >>> normalise("(a and b)")
    'a and b'
    """
    node = parse_expression(expression)
    return ast.unparse(node) if node is not None else expression.strip()


def disjunct_names(expression: str) -> list[str]:
    """Return the operand names of a two-name ``or``, in source order.

    >>> disjunct_names("x or y")
    ['x', 'y']
    >>> disjunct_names("(x or y)")
    ['x', 'y']
    >>> disjunct_names("x and y")
    []
    """
    node = parse_expression(expression)
    if not isinstance(node, ast.BoolOp) or not isinstance(node.op, ast.Or):
        return []
    if len(node.values) != 2:
        return []
    if not all(isinstance(value, ast.Name) for value in node.values):
        return []
    return [value.id for value in node.values]


def find_absorbed(text: str) -> list[dict]:
    """Report ``or`` predicates that boolean absorption collapses.

    Either operand may be the absorbing one, so both orders are checked:

    >>> [f["result"] for f in find_absorbed(
    ...     "strong = a and b\\nfallback = b\\nresult = strong or fallback\\n")]
    ['result']
    >>> [f["result"] for f in find_absorbed(
    ...     "strong = a and b\\nfallback = b\\nresult = fallback or strong\\n")]
    ['result']

    Parentheses do not hide it:

    >>> [f["result"] for f in find_absorbed(
    ...     "strong = (a and b)\\nfallback = b\\nresult = strong or fallback\\n")]
    ['result']

    Genuinely different predicates are not absorption:

    >>> find_absorbed("strong = a\\nfallback = b\\nresult = strong or fallback\\n")
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
        names = disjunct_names(expression)
        if not names:
            continue
        left, right = names
        if left not in assignments or right not in assignments:
            continue
        for wide, narrow in ((left, right), (right, left)):
            wide_expr = normalise(assignments[wide])
            narrow_expr = normalise(assignments[narrow])
            if narrow_expr != wide_expr and narrow_expr in conjuncts(wide_expr):
                findings.append({
                    "result": name,
                    "wide": wide,
                    "wide_expr": wide_expr,
                    "narrow": narrow,
                    "narrow_expr": narrow_expr,
                })
                break
    return findings


def load_allowlist(path):
    """Read declared exceptions as ``{key: reason}``.

    A key is ``<path>::<result>::<wide>::<narrow>`` so an exception cannot
    leak onto an unrelated predicate that happens to reuse a common result
    name such as ``b_pass``. A reason is mandatory: an undocumented waiver is
    indistinguishable from an unnoticed defect.

    >>> import tempfile, pathlib
    >>> with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as handle:
    ...     _ = handle.write("# note\\nlabs/x/verify.sh::b_pass::s::f  # justified\\n")
    ...     name = handle.name
    >>> load_allowlist(pathlib.Path(name))
    {'labs/x/verify.sh::b_pass::s::f': 'justified'}

    >>> with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as handle:
    ...     _ = handle.write("labs/x/verify.sh::b_pass::s::f\\n")
    ...     name = handle.name
    >>> load_allowlist(pathlib.Path(name))
    Traceback (most recent call last):
        ...
    ValueError: allowlist entry has no reason: labs/x/verify.sh::b_pass::s::f
    """
    entries = {}
    if path is None or not path.is_file():
        return entries
    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, _, reason = line.partition("#")
        key, reason = key.strip(), reason.strip()
        if not key:
            continue
        if not reason:
            raise ValueError(f"allowlist entry has no reason: {key}")
        entries[key] = reason
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

    try:
        allowed = load_allowlist(pathlib.Path(args.allowlist) if args.allowlist else None)
    except ValueError as exc:
        print(f"{exc}", file=sys.stderr)
        return 1

    repo_root = pathlib.Path(args.repo_root).resolve()
    undeclared = 0
    matched = set()

    for script in sorted(pathlib.Path(args.root).rglob("verify.sh")):
        try:
            relative = script.resolve().relative_to(repo_root).as_posix()
        except ValueError:
            relative = script.as_posix()
        for finding in find_absorbed(script.read_text(errors="replace")):
            key = "::".join(
                (relative, finding["result"], finding["wide"], finding["narrow"])
            )
            if key in allowed:
                matched.add(key)
                continue
            undeclared += 1
            print(f"{relative}: {finding['result']} = {finding['wide']} or {finding['narrow']}")
            print(f"    {finding['wide']} = {finding['wide_expr']}")
            print(f"    {finding['narrow']} = {finding['narrow_expr']}")
            print(
                f"    absorbed: '{finding['result']}' reduces to "
                f"'{finding['narrow_expr']}' alone, so every other conjunct of "
                f"'{finding['wide']}' is dead code"
            )
            print(f"    fix the predicate, or declare it with a reason as: {key}")

    stale = sorted(set(allowed) - matched)
    for key in stale:
        print(f"stale allowlist entry no longer matches any predicate: {key}", file=sys.stderr)

    print(
        f"\nundeclared absorbed predicates: {undeclared} "
        f"(declared: {len(matched)}, stale: {len(stale)})"
    )
    return 1 if undeclared or stale else 0


if __name__ == "__main__":
    sys.exit(main())
