"""Unit regressions for issue-quality structure, form/API and legacy cases."""
import unittest
from pathlib import Path

import yaml

from test_pr_title_check import ACCEPTED, NOT_ENFORCED, REJECTED
from validate_issue_spec import Issue, check_issue, sections


def issue(
    body: str,
    title: str = "fix(labs): correct evaluation timestamp",
    created_at: str = "2026-11-01T00:00:00Z",
) -> Issue:
    return {"title": title, "body": body, "created_at": created_at}


GOOD = """### Summary
Wrong timestamp misrepresents a prior offline replay.
### Evidence and as-of baseline
At commit abc123, labs/example/verify.sh writes the capture clock.
### Affected scope
Only the Phase B gate and tests; raw evidence is excluded.
### Acceptance criteria
- [ ] A stale capture-time field fails the gate test.
### Verification plan
python3 scripts/test_lab_gates.py, record exit result.
"""


class IssueQualityTests(unittest.TestCase):
    def test_all_issue_templates_parse_as_yaml(self) -> None:
        # Given every issue template, including the non-form config file.
        templates = sorted((Path(__file__).resolve().parents[1] / ".github/ISSUE_TEMPLATE").glob("*.yml"))
        self.assertTrue(templates)
        for template in templates:
            with self.subTest(template=template.name):
                # When parsing the actual file, then invalid YAML fails the test.
                self.assertIsInstance(yaml.safe_load(template.read_text(encoding="utf-8")), dict)

    def test_good_api_issue(self):
        self.assertEqual(check_issue(issue(GOOD)), [])

    def test_missing_acceptance_detected(self):
        self.assertTrue(any("acceptance" in e for e in check_issue(issue(GOOD.replace("### Acceptance criteria", "### Other")))))

    def test_placeholder_section_rejected(self):
        self.assertTrue(any("verification" in e for e in check_issue(issue(GOOD.replace("python3 scripts/test_lab_gates.py, record exit result.", "TBD")))))

    def test_manual_decision_not_forced_to_have_code_test(self):
        body = """### Context and evidence
Two valid URLs, as of 2026-10-30.
### Scope and exclusions
This decision only, no migrations.
### Decision or tracking outcome
Record pilot-only or rollout with rationale.
### Closure evidence
Signed decision record and owner.
"""
        self.assertEqual(check_issue(issue(body, "chore(domain): choose rollout")), [])

    def test_old_issue_edit_exempt(self):
        self.assertEqual(check_issue(issue("", "Old title", "2026-10-20T00:00:00Z")), [])

    def test_can_force_backlog_audit(self):
        self.assertNotEqual(check_issue(issue("", "Old title", "2026-10-20T00:00:00Z"), force=True), [])

    def test_title_convention(self):
        self.assertTrue(any("title" in e for e in check_issue(issue(GOOD, "Fix the thing"))))

    def test_accepts_documented_title_grammar(self) -> None:
        # Given the title convention's accepted syntax and editorial exceptions.
        for title in (*ACCEPTED, *NOT_ENFORCED):
            with self.subTest(title=title):
                # When a complete issue uses that title, then it passes.
                self.assertEqual(check_issue(issue(GOOD, title)), [])

    def test_rejects_titles_outside_documented_grammar(self) -> None:
        # Given titles rejected by the existing PR-title contract.
        for title, _reason in REJECTED:
            with self.subTest(title=title):
                # When validating a complete issue, then the title is rejected.
                self.assertTrue(any(e.startswith("title:") for e in check_issue(issue(GOOD, title))))

    def test_accepts_verification_under_descendant_headings(self) -> None:
        # Given verification content under both deeper Markdown heading levels.
        body = GOOD.replace("### Verification plan\n", "### Verification plan\n#### Manual checks\n##### Commands\n###### Expected results\n")
        # When checking the issue, then descendant content satisfies verification.
        self.assertEqual(check_issue(issue(body)), [])

    def test_section_ends_at_same_or_higher_heading_level(self) -> None:
        # Given sections with descendant, sibling, and ancestor headings.
        body = "### Verification plan\n#### Manual checks\nRun tests\n### Notes\nSibling\n## Parent\nAncestor\n# End\nOutside"
        # When extracting sections, then only descendant content is retained.
        self.assertEqual(sections(body)[0], ("verification plan", "#### Manual checks\nRun tests"))

    def test_empty_nested_heading_does_not_satisfy_verification(self) -> None:
        # Given a nested heading with only placeholder content.
        body = GOOD.replace("python3 scripts/test_lab_gates.py, record exit result.", "#### Manual checks\nTBD")
        # When checking the issue, then the heading itself is not evidence.
        self.assertTrue(any(e.startswith("verification") for e in check_issue(issue(body))))

    def test_verification_does_not_borrow_from_h1_section(self) -> None:
        # Given an empty verification section followed directly by an unrelated H1 section.
        body = GOOD.replace("python3 scripts/test_lab_gates.py, record exit result.", "# Unrelated\nRun tests elsewhere")
        # When extracting sections, then the H1 ends the verification section.
        self.assertEqual(dict(sections(body))["verification plan"], "")
        # When checking the issue, then the later H1 cannot satisfy verification.
        self.assertTrue(any(e.startswith("verification") for e in check_issue(issue(body))))

    def test_verification_does_not_borrow_from_shallower_section(self) -> None:
        # Given an empty verification section followed by unrelated content.
        body = GOOD.replace("python3 scripts/test_lab_gates.py, record exit result.", "## Unrelated\nRun tests elsewhere")
        # When checking the issue, then the later section cannot satisfy it.
        self.assertTrue(any(e.startswith("verification") for e in check_issue(issue(body))))


if __name__ == "__main__":
    unittest.main()
