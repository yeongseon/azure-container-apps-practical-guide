#!/usr/bin/env python3
"""Regression tests; run with python3 scripts/test_content_validation_rules.py."""

from __future__ import annotations

import re
import tempfile
import unittest
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import date
from pathlib import Path
from typing import Any

import validate_doc_quality as validator
import generate_content_validation_status as status_generator


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
def parsed_fixture(
    frontmatter: dict[str, Any], *, relative_path: str = "platform/fixture.md"
) -> Iterator[tuple[Path, dict[str, Any]]]:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        path = root / "docs" / relative_path
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


def messages(
    frontmatter: dict[str, Any], *, relative_path: str = "platform/fixture.md"
) -> list[str]:
    with parsed_fixture(frontmatter, relative_path=relative_path) as (path, parsed):
        findings: list[validator.Finding] = []
        validator.validate_content_validation(findings, path, parsed, today=TODAY)
    return [finding.message for finding in findings]


class ContentValidationRuleTests(unittest.TestCase):
    def test_factual_subsection_index_requires_metadata(self) -> None:
        self.assertIn(
            "in-scope factual-claim docs require content_validation metadata",
            messages({}, relative_path="platform/new/index.md"),
        )

    def test_navigation_index_does_not_require_metadata(self) -> None:
        self.assertEqual(messages({}, relative_path="platform/index.md"), [])

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
        for placeholder in (
            "TBD",
            "todo",
            "placeholder",
            "example",
            "none",
            "n-a",
            "unknown",
            "foo",
            "bar",
            "xxx",
            "lorem",
            "<reviewer>",
            "[reviewer]",
            "{reviewer}",
            "...",
            "   ",
        ):
            with self.subTest(placeholder=placeholder):
                self.assertIn(
                    "content_validation.reviewer must not be a placeholder",
                    messages(metadata(reviewer=placeholder)),
                )

    def test_valid_reviewer_values_are_not_placeholders(self) -> None:
        for reviewer in ("agent", "human"):
            with self.subTest(reviewer=reviewer):
                self.assertEqual(messages(metadata(reviewer=reviewer)), [])

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

    def test_missing_claim_text_is_rejected(self) -> None:
        invalid_claim = claim()
        del invalid_claim["claim"]
        self.assertIn(
            "content_validation.core_claims[0].claim is required",
            messages(metadata(claims=[invalid_claim, claim()])),
        )

    def test_empty_or_whitespace_claim_text_is_rejected(self) -> None:
        for value in ("", "   "):
            with self.subTest(value=value):
                invalid_claim = claim()
                invalid_claim["claim"] = value
                self.assertIn(
                    "content_validation.core_claims[0].claim is required",
                    messages(metadata(claims=[invalid_claim, claim()])),
                )

    def test_placeholder_claim_text_is_rejected(self) -> None:
        for placeholder in ("TODO", "placeholder", "<claim>", "[claim]", "{claim}"):
            with self.subTest(placeholder=placeholder):
                invalid_claim = claim()
                invalid_claim["claim"] = placeholder
                self.assertIn(
                    "content_validation.core_claims[0].claim must not be a placeholder",
                    messages(metadata(claims=[invalid_claim, claim()])),
                )

    def test_tautological_claim_text_is_rejected(self) -> None:
        invalid_claim = claim()
        invalid_claim["claim"] = "This page uses Microsoft Learn as the primary source basis."
        self.assertIn(
            "content_validation.core_claims[0].claim must assert Azure behavior, not describe the sourcing process",
            messages(metadata(claims=[invalid_claim, claim()])),
        )

    def test_placeholder_words_inside_real_claims_are_allowed(self) -> None:
        example_claim = claim()
        example_claim["claim"] = (
            "For example, Container Apps can keep the prior revision active until a new revision is ready."
        )
        todo_claim = claim()
        todo_claim["claim"] = (
            "A todo application can use HTTP scaling based on concurrent requests."
        )
        todo_claim["source"] = "https://learn.microsoft.com/en-us/azure/container-apps/scale-app"
        self.assertEqual(messages(metadata(claims=[example_claim, todo_claim])), [])

    def test_placeholder_claim_source_is_rejected(self) -> None:
        for placeholder in (
            "TODO",
            "placeholder",
            "<source>",
            "[source]",
            "{source}",
            "xxx",
            "...",
        ):
            with self.subTest(placeholder=placeholder):
                self.assertIn(
                    "content_validation.core_claims[0].source must not be a placeholder",
                    messages(metadata(claims=[claim(source=placeholder), claim()])),
                )

    def test_every_claim_requires_locale_qualified_learn_source(self) -> None:
        self.assertIn(
            "content_validation.core_claims[0].source must be an https://learn.microsoft.com/en-us/ URL",
            messages(
                metadata(
                    status="pending_review",
                    claims=[claim(source="https://example.com/source", verified=False), claim()],
                )
            ),
        )

    def test_learn_source_host_is_case_insensitive_and_allows_query_fragment(self) -> None:
        source = "HTTPS://LEARN.MICROSOFT.COM/en-us/azure/container-apps/example?view=azure#section"
        self.assertEqual(messages(metadata(claims=[claim(source=source), claim()])), [])

    def test_example_in_real_learn_path_is_not_a_placeholder(self) -> None:
        source = "https://learn.microsoft.com/en-us/azure/container-apps/example-configuration"
        self.assertEqual(messages(metadata(claims=[claim(source=source), claim()])), [])

    def test_unverified_requires_null_review_metadata(self) -> None:
        state = metadata(
            status="unverified",
            claims=[claim(verified=False), claim(verified=False)],
        )
        result = messages(state)
        self.assertIn("content_validation.last_reviewed must be null for status unverified", result)
        self.assertIn("content_validation.reviewer must be null for status unverified", result)

    def test_unverified_rejects_verified_claim(self) -> None:
        state = metadata(
            status="unverified",
            last_reviewed=None,
            reviewer=None,
            claims=[claim(verified=True), claim(verified=False)],
        )
        self.assertIn(
            "status is unverified but at least one core_claim has verified: true",
            messages(state),
        )

    def test_pending_review_requires_an_unverified_claim(self) -> None:
        self.assertIn(
            "status is pending_review but no core_claim has verified: false",
            messages(metadata(status="pending_review")),
        )

    def test_verified_rejects_unverified_claim(self) -> None:
        self.assertIn(
            "status is verified but at least one core_claim has verified: false",
            messages(metadata(claims=[claim(), claim(verified=False)])),
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

    def test_generated_validation_example_passes_validator(self) -> None:
        dashboard = status_generator.generate_dashboard([], Path("docs"), TODAY)
        match = re.search(
            r"## How to Add Validation.*?```yaml\n(.*?)\n```",
            dashboard,
            re.DOTALL,
        )
        if match is None:
            self.fail("generated dashboard does not contain a validation YAML example")
        import yaml

        frontmatter = yaml.safe_load(match.group(1).removeprefix("---\n").removesuffix("\n---"))
        self.assertEqual(messages(frontmatter), [])


if __name__ == "__main__":
    unittest.main()
