"""CLI reporting and declaration policy for the absorption detector."""

from __future__ import annotations

import argparse
import pathlib
import sys
from collections import Counter
from collections.abc import Callable
from typing import TypedDict


class Finding(TypedDict):
    result: str
    wide: str
    wide_expr: str
    narrow: str
    narrow_expr: str


def main(
    analyse: Callable[[str], tuple[list[Finding], Counter[str], list[str]]],
    load_allowlist: Callable[[pathlib.Path | None], dict[str, str]],
) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", help="Directory to scan for verify.sh files")
    parser.add_argument("--allowlist", help="File of deliberate exceptions or tracked defects")
    parser.add_argument("--repo-root", default=".")
    args = parser.parse_args()
    try:
        allowed = load_allowlist(pathlib.Path(args.allowlist) if args.allowlist else None)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    repo_root = pathlib.Path(args.repo_root).resolve()
    undeclared = 0
    matched: set[str] = set()
    known: set[str] = set()
    coverage: Counter[str] = Counter()
    for script in sorted(pathlib.Path(args.root).rglob("verify.sh")):
        try:
            relative = script.resolve().relative_to(repo_root).as_posix()
        except ValueError:
            relative = script.as_posix()
        findings, counts, skipped = analyse(script.read_text(errors="replace"))
        coverage.update(counts)
        for detail in skipped:
            print(f"{relative}: {detail}")
        for finding in findings:
            key = "::".join((relative, finding["result"], finding["wide"], finding["narrow"]))
            if key in allowed:
                matched.add(key)
                if allowed[key].startswith("KNOWN-DEFECT"):
                    known.add(key)
                    print(f"{key}  # {allowed[key]}")
                continue
            undeclared += 1
            print(f"{relative}: {finding['result']} = {finding['wide']} or {finding['narrow']}")
            print(f"    {finding['wide']} = {finding['wide_expr']}")
            print(f"    {finding['narrow']} = {finding['narrow_expr']}")
            print(f"    absorbed pair: {finding['wide']} contributes no additional passing cases")
            print(f"    fix the predicate, or declare it with a reason as: {key}")
    stale = sorted(set(allowed) - matched)
    for key in stale:
        print(f"stale allowlist entry no longer matches any predicate: {key}", file=sys.stderr)
    print(
        f"\nundeclared absorbed predicates: {undeclared} "
        f"(declared: {len(matched - known)}, stale: {len(stale)})\n"
        f"known defects: {len(known)} (tracked in #397)"
    )
    print(f"disjunctions analysed: {coverage.pop('analysed', 0)}; skipped: {sum(coverage.values())}")
    for reason in ("not a name", "name without assignment", "ambiguous assignment", "unsupported construct"):
        print(f"    {reason}: {coverage[reason]}")
    return 1 if undeclared or stale or coverage["ambiguous assignment"] else 0
