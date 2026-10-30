"""Check the minimum structure of new GitHub issues without re-triaging history.

Forms enforce required fields in the web UI; agents and REST callers bypass forms.
The gate cannot block issue creation. It reports actionable workflow failures.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

# The 28-issue backlog and the umbrella issue predate this policy rollout.
# Review them under #419; do not fail edits of historical issues.
POLICY_START = datetime(2026, 10, 31, tzinfo=timezone.utc)
HEADING = re.compile(r"^#{2,4}\s+(.+?)\s*$", re.MULTILINE)

REQUIRED = {
    "problem / context": ("summary", "problem", "context", "background", "details"),
    "evidence / rationale": ("evidence", "observed evidence", "context and evidence"),
    "affected scope": ("affected scope", "scope and", "scope", "affected page"),
    "acceptance / decision": ("acceptance", "completion criteria", "decision or tracking outcome"),
    "verification / closure": ("verification", "validation plan", "closure evidence", "evidence of completion"),
}
TITLE = re.compile(r"^(fix|feat|docs|chore|ci|test|build|refactor|perf|style)(\([a-z0-9._-]+\))?:\s+\S", re.I)
PLACEHOLDER = re.compile(r"^(?:[-*]\s*)?(?:\[\s*\]\s*)?(?:\.\.\.|tbd|todo|n/a|none|placeholder)\.?$", re.I)


def sections(body: str) -> list[tuple[str, str]]:
    matches = list(HEADING.finditer(body))
    return [
        (m.group(1).lower().strip(), body[m.end():matches[i + 1].start() if i + 1 < len(matches) else len(body)].strip())
        for i, m in enumerate(matches)
    ]


def meaningful(value: str) -> bool:
    lines = [line.strip() for line in value.splitlines() if line.strip()]
    return bool(lines) and any(not PLACEHOLDER.fullmatch(line) for line in lines)


def check_issue(issue: dict, *, force: bool = False) -> list[str]:
    created = issue.get("created_at")
    if not force and created:
        try:
            created_at = datetime.fromisoformat(created.replace("Z", "+00:00"))
            if created_at < POLICY_START:
                return []
        except ValueError:
            pass  # Do not silently exempt a malformed timestamp.
    errors: list[str] = []
    title = issue.get("title") or ""
    body = issue.get("body") or ""
    if not TITLE.match(title):
        errors.append("title: use type(scope): concise description (see CONTRIBUTING.md)")
    parts = sections(body)
    for field, labels in REQUIRED.items():
        found = [content for heading, content in parts if any(heading.startswith(label) for label in labels)]
        if not any(meaningful(content) for content in found):
            errors.append(f"{field}: add a non-placeholder section with concrete detail")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json-env", default="ISSUE_EVENT_JSON")
    args = parser.parse_args()
    try:
        issue = json.loads(os.environ[args.json_env])
    except (KeyError, json.JSONDecodeError) as exc:
        print(f"Cannot read issue payload: {exc}", file=sys.stderr)
        return 2
    errors = check_issue(issue)
    if errors:
        for item in errors:
            print(f"::error::{item}")
        print("This workflow reports missing fields; it cannot prevent opening an issue.")
        return 1
    print("Issue structure OK, or existing pre-policy issue is grandfathered for #419 triage.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
