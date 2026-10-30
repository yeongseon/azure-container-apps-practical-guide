"""Unit regressions for issue-quality structure, form/API and legacy cases."""
import unittest

from validate_issue_spec import check_issue


def issue(body, title="fix(labs): correct evaluation timestamp", created_at="2026-11-01T00:00:00Z"):
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


if __name__ == "__main__":
    unittest.main()
