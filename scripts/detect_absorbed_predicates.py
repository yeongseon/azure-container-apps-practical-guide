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

KNOWN-DEFECT #397 declarations track defects, not deliberate exceptions.
Exit 1 on undeclared findings, stale entries, or ambiguous assignments.
Non-name disjunctions are reported as advisory unanalysed forms: many are
ordinary value defaults, not gate alternatives (74 in the initial corpus).
Coverage counts include every top-level disjunction and malformed *_pass
expression, not only findings. Calls other than bool and literal all/any
reducers remain opaque atoms. Builtins are assumed not to be shadowed.

This is bounded textual analysis, not a general Python data-flow engine.
Only positive bare-name ``if`` guards with a preceding False initializer
are incorporated. Other control-flow-dependent assignments are not resolved;
multiple non-constant assignments are ambiguous and fail closed. Heredocs
have separate assignment scopes. Relational implications (e.g. len(x) == n
implies len(x) > 0), arithmetic/comparison implications, and relationships
between opaque calls are NOT detected.
Name aliases are not recursively expanded: ``s = referenced; result = s or f``
can hide absorption inside the earlier ``referenced`` assignment.
"""

from __future__ import annotations

import ast
import pathlib
import re
import sys
from collections import Counter
from itertools import permutations
from lib.absorbed_report import Finding, main

ASSIGNMENT = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*(.+?)\s*$")


def flatten_continuations(text: str) -> str:
    """Join parenthesised multi-line predicates onto single lines.

    >>> flatten_continuations("x = (\\n    a\\n    or b\\n)")
    'x = ( a or b )'
    """
    lines = iter(text.splitlines())
    joined = []
    for line in lines:
        match = ASSIGNMENT.match(line)
        if match:
            expression = match.group(2)
            while True:
                try:
                    ast.parse(expression, mode="eval")
                    break
                except SyntaxError as exc:
                    if "was never closed" not in exc.msg and "unexpected EOF" not in exc.msg:
                        break
                    following = next(lines, None)
                    if following is None:
                        break
                    expression += " " + following.strip()
            line = line[:match.start(2)] + expression
        joined.append(line)
    return "\n".join(joined)


def parse_expression(expression: str) -> ast.expr | None:
    """Parse a predicate into an AST node, or None when it is not Python.

    """
    try:
        return ast.parse(expression, mode="eval").body
    except SyntaxError:
        return None


def boolean_node(node: ast.expr) -> ast.expr:
    """Unwrap bool and lower literal reducers without expanding opaque calls."""
    match node:
        case ast.Call(func=ast.Name(id="bool"), args=[arg], keywords=[]):
            return boolean_node(arg)
        case ast.Call(func=ast.Name(id=kind), args=[ast.List(elts=elts) | ast.Tuple(elts=elts) | ast.Set(elts=elts)], keywords=[]) if kind in {"all", "any"} and elts:
            return ast.BoolOp(op=ast.And() if kind == "all" else ast.Or(), values=elts)
        case _:
            return node


def conjuncts(expression: str) -> set[str]:
    """Flatten a predicate into its normalised ``and`` operands, recursively.

    >>> sorted(conjuncts("a and b and c"))
    ['a', 'b', 'c']
    >>> sorted(conjuncts("a and (b and c)"))
    ['a', 'b', 'c']
    >>> sorted(conjuncts("(a and b)")) == sorted(conjuncts("a and b"))
    True
    """
    node = parse_expression(expression)
    if node is None:
        return {expression.strip()}
    operands: set[str] = set()

    def walk(current: ast.expr) -> None:
        match boolean_node(current):
            case ast.BoolOp(op=ast.And(), values=values):
                for value in values:
                    walk(value)
            case atom:
                operands.add(ast.unparse(atom))

    walk(node)
    return operands


def normalise(expression: str) -> str:
    """Render a predicate in a canonical form for comparison.

    """
    node = parse_expression(expression)
    return ast.unparse(boolean_node(node)) if node is not None else expression.strip()


def disjunct_names(expression: str) -> list[str]:
    """Return names of a bool-wrapped, literal any, or n-ary disjunction.

    >>> disjunct_names("x or y")
    ['x', 'y']
    >>> disjunct_names("(x or y)")
    ['x', 'y']
    >>> disjunct_names("x and y")
    []
    """
    node = parse_expression(expression)
    node = boolean_node(node) if node is not None else None
    if not isinstance(node, ast.BoolOp) or not isinstance(node.op, ast.Or):
        return []
    if not all(isinstance(value, ast.Name) for value in node.values):
        return []
    return [value.id for value in node.values if isinstance(value, ast.Name)]


def find_absorbed(text: str) -> list[Finding]:
    """Report ``or`` predicates that boolean absorption collapses.

    >>> [f["result"] for f in find_absorbed(
    ...     "strong = a and b\\nfallback = b\\nresult = strong or fallback\\n")]
    ['result']
    >>> [f["result"] for f in find_absorbed(
    ...     "strong = a and b\\nfallback = b\\nresult = fallback or strong\\n")]
    ['result']

    >>> [f["result"] for f in find_absorbed(
    ...     "strong = (a and b)\\nfallback = b\\nresult = strong or fallback\\n")]
    ['result']

    >>> [f["result"] for f in find_absorbed(
    ...     "wide = a and b and c\\nnarrow = b and c\\nresult = wide or narrow\\n")]
    ['result']
    >>> [f["result"] for f in find_absorbed(
    ...     "wide = a and (b and c)\\nnarrow = b and c\\nresult = narrow or wide\\n")]
    ['result']

    >>> find_absorbed("strong = a\\nfallback = b\\nresult = strong or fallback\\n")
    []
    >>> find_absorbed("wide = a and b\\nnarrow = c and d\\nresult = wide or narrow\\n")
    []
    """
    return analyse(text)[0]


def analyse(text: str) -> tuple[list[Finding], Counter[str], list[str]]:
    """Fail closed on uncertain operands; retain coverage and skipped reasons."""
    assignments: dict[str, str] = {}
    counts: Counter[str] = Counter()
    coverage: Counter[str] = Counter()
    skipped: list[str] = []
    findings: list[Finding] = []
    guards: list[tuple[int, str]] = []
    for line in flatten_continuations(text).splitlines():
        if re.fullmatch(r"[A-Z][A-Z0-9_]*", line):
            assignments.clear()
            counts.clear()
            guards.clear()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        guards = [(depth, guard) for depth, guard in guards if depth < indent]
        guard_match = re.fullmatch(r"\s*if ([A-Za-z_]\w*):", line)
        if guard_match:
            guards.append((indent, guard_match.group(1)))
        match = ASSIGNMENT.match(line)
        if not match:
            continue
        name, expression = match.group(1), match.group(2)
        node = parse_expression(expression)
        previous = assignments.get(name)
        guarded = bool(guards) and previous == "False"
        effective = " and ".join([g for _, g in guards] + [f"({expression})"]) if guarded else expression
        names = disjunct_names(expression)
        reduced = boolean_node(node) if node is not None else None
        candidate = isinstance(reduced, ast.BoolOp) and isinstance(reduced.op, ast.Or)
        reason = ""
        if candidate or (node is None and name.endswith("_pass")):
            if not candidate:
                reason = "unsupported construct"
            elif not names:
                reason = "not a name"
            elif any(n not in assignments for n in names):
                reason = "name without assignment"
            elif any(counts[n] > 1 for n in names):
                reason = "ambiguous assignment"
            elif any(parse_expression(assignments[n]) is None for n in names):
                reason = "unsupported construct"
            coverage[reason or "analysed"] += 1
            if reason:
                skipped.append(f"{name}: unanalysed: {reason}: {expression}")
        for wide, narrow in permutations(names if candidate and not reason else [], 2):
            wide_expr = normalise(assignments[wide])
            narrow_expr = normalise(assignments[narrow])
            # Subset, not membership: `(a and b and c) or (b and c)` absorbs
            # just as surely as `(a and b) or b`, and comparing the whole
            # narrow expression against individual wide operands would miss it.
            if narrow_expr != wide_expr and conjuncts(narrow_expr) < conjuncts(wide_expr):
                findings.append({
                    "result": name,
                    "wide": wide,
                    "wide_expr": wide_expr,
                    "narrow": narrow,
                    "narrow_expr": narrow_expr,
                })
        assignments[name] = effective
        counts[name] += int(node is not None and not isinstance(node, ast.Constant))
    return findings, coverage, skipped


def load_allowlist(path: pathlib.Path | None) -> dict[str, str]:
    """Read declared exceptions as ``{key: reason}``.

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

    >>> with tempfile.TemporaryDirectory() as directory:
    ...     path = pathlib.Path(directory) / 'allowlist.txt'
    ...     _ = path.write_text('labs/x/verify.sh::d_pass::s::f # KNOWN-DEFECT: broken\\n')
    ...     load_allowlist(path)
    Traceback (most recent call last):
        ...
    ValueError: KNOWN-DEFECT entry requires an issue number: labs/x/verify.sh::d_pass::s::f
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
        if reason.startswith("KNOWN-DEFECT") and not re.match(r"KNOWN-DEFECT #\d+:", reason):
            raise ValueError(f"KNOWN-DEFECT entry requires an issue number: {key}")
        entries[key] = reason
    return entries


if __name__ == "__main__":
    sys.exit(main(analyse, load_allowlist))
