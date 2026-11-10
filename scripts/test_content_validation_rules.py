#!/usr/bin/env python3
"""Regression tests; run with python3 scripts/test_content_validation_rules.py."""

from __future__ import annotations

import tempfile
import unittest
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import date
from pathlib import Path
from typing import Any

import validate_doc_quality as validator


TODAY = date(2026, 11, 10)
LEARN_SOURCE = "https://learn.microsoft.com/en-us/azure/container-apps/revisions"


def claim(*, source: str | None = LEARN_SOURCE, verified: bool | str = True) -> dict[str, Any]:
    return {
        "claim": "Container Apps revisions are immutable snapshots.",
        "source": source,
        "verified": verified,
    }


def metadata(
    *,
    status: str = "verified",
    last_reviewed: str | None = "2026-11-10",
    reviewer: str | None = "agent",
    claims: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    return {
        "content_validation": {
            "status": status,
            "last_reviewed": last_reviewed,
            "reviewer": reviewer,
            "core_claims": claims if claims is not None else [claim(), claim()],
        }
    }


@contextmanager
def parsed_fixture(frontmatter: dict[str, Any]) -> Iterator[tuple[Path, dict[str, Any]]]:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        path = root / "docs/platform/fixture.md"
        path.parent.mkdir(parents=True)
        import yaml

        path.write_text(f"---\n{yaml.safe_dump(frontmatter)}---\n# Fixture\n", encoding="utf-8")
        previous_root, previous_docs = validator.ROOT, validator.DOCS
        validator.ROOT, validator.DOCS = root, root / "docs"
        try:
            parsed, _ = validator.load_frontmatter(path.read_text(encoding="utf-8"))
            yield path, parsed
        finally:
            validator.ROOT, validator.DOCS = previous_root, previous_docs


def messages(frontmatter: dict[str, Any]) -> list[str]:
    with parsed_fixture(frontmatter) as (path, parsed):
        findings: list[validator.Finding] = []
        validator.validate_content_validation(findings, path, parsed, today=TODAY)
    return [finding.message for finding in findings]


class ContentValidationRuleTests(unittest.TestCase):
    def test_valid_verified_state_passes(self) -> None:
        self.assertEqual(messages(metadata()), [])

    def test_honest_unverified_state_passes(self) -> None:
        state = metadata(
            status="unverified",
            last_reviewed=None,
            reviewer=None,
            claims=[claim(verified=False), claim(verified=False)],
        )
        self.assertEqual(messages(state), [])

    def test_honest_pending_review_state_passes(self) -> None:
        state = metadata(
            status="pending_review",
            claims=[claim(), claim(verified=False)],
        )
        self.assertEqual(messages(state), [])

    def test_future_review_date_is_rejected(self) -> None:
        self.assertIn(
            "content_validation.last_reviewed must not be in the future",
            messages(metadata(last_reviewed="2026-11-11")),
        )

    def test_invalid_review_date_is_rejected(self) -> None:
        self.assertIn(
            "content_validation.last_reviewed must be a valid ISO date for status verified",
            messages(metadata(last_reviewed="not-a-date")),
        )

    def test_placeholder_reviewer_is_rejected(self) -> None:
        self.assertIn(
            "content_validation.reviewer must not be a placeholder",
            messages(metadata(reviewer="TBD")),
        )

    def test_unknown_reviewer_is_rejected(self) -> None:
        self.assertIn(
            "content_validation.reviewer must be 'human' or 'agent' for status verified",
            messages(metadata(reviewer="bot")),
        )

    def test_missing_claim_source_is_rejected(self) -> None:
        self.assertIn(
            "content_validation.core_claims[0].source is required",
            messages(metadata(claims=[claim(source=None), claim()])),
        )

    def test_placeholder_claim_source_is_rejected(self) -> None:
        self.assertIn(
            "content_validation.core_claims[0].source must not be a placeholder",
            messages(metadata(claims=[claim(source="TODO"), claim()])),
        )

    def test_verified_claim_with_non_learn_source_is_rejected(self) -> None:
        self.assertIn(
            "content_validation.core_claims[0] with verified: true must cite an https://learn.microsoft.com/en-us/ URL",
            messages(metadata(claims=[claim(source="https://example.com/source"), claim()])),
        )

    def test_unknown_status_is_rejected(self) -> None:
        self.assertIn(
            "content_validation.status must be verified, pending_review, or unverified",
            messages(metadata(status="unknown")),
        )

    def test_unknown_claim_result_is_rejected(self) -> None:
        self.assertIn(
            "content_validation.core_claims[0].verified must be true or false",
            messages(metadata(claims=[claim(verified="unknown"), claim()])),
        )

    def test_verified_empty_claim_list_is_rejected(self) -> None:
        self.assertIn(
            "content_validation.core_claims must contain 2 to 5 claims",
            messages(metadata(claims=[])),
        )


if __name__ == "__main__":
    unittest.main()
