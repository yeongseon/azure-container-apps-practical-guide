#!/usr/bin/env python3
"""Regression cases for the title check in ``.github/workflows/pr-title.yml``.

The check is inline in the workflow because its job checks out nothing, so this
test extracts the step's script from the YAML and runs it the way the runner
does: ``bash -e`` with the title in the ``TITLE`` environment variable.

Usage:
    python3 scripts/test_pr_title_check.py
"""

from __future__ import annotations

import os
import pathlib
import subprocess
import tempfile
import unittest

import yaml

WORKFLOW = pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows" / "pr-title.yml"
ERROR_ANNOTATION = "::error::The pull request title does not follow the Title Convention in CONTRIBUTING.md."

TYPES = ("feat", "fix", "docs", "test", "perf", "refactor", "ci", "build", "chore", "style", "revert")

ACCEPTED = (
    *(f"{kind}: change the thing" for kind in TYPES),
    "fix: a",
    "feat(cli): add a JSON output option",
    "fix(api.v2): keep the response shape",
    "docs(a/b,c): clarify the setup",
    "feat(api)!: drop the v1 endpoints",
    "refactor!: rename the public configuration keys",
    "fix: HTTP 503 handling",
    "fix: decode nonempty NULL-only collection results",
    "fix: handle C#7 syntax",
    "fix: bump the parser to v1.2.3",
    "chore(main): release 1.2.3",
    "build(deps): bump actions/checkout from 4 to 5",
    "chore(deps-dev): bump pytest from 8 to 9",
    "fix: preserve `backticks` literally",
    'fix: preserve "quotes" literally',
    "fix: preserve 'quotes' literally",
    "fix: ${TITLE} and $HOME stay literal",
    "fix: semicolon; ampersand & pipe | stay data",
)

# Editorial guidance in CONTRIBUTING.md that the check does not verify.
NOT_ENFORCED = (
    "fix: Resolve crash",
    "fix: 修复崩溃",
    "fix: two  spaces inside",
)

FORMAT = 'must be "type: description"'
REJECTED = (
    ("add export", FORMAT),
    ("unknown: add export", FORMAT),
    ("Fix: resolve crash", FORMAT),
    ("FIX: resolve crash", FORMAT),
    ("fix(API): resolve crash", FORMAT),
    ("fix(): empty scope", FORMAT),
    ("fix(scope)!!: bad breaking", FORMAT),
    ("fix:", FORMAT),
    ("fix: ", FORMAT),
    ("fix:  two spaces after the colon", FORMAT),
    ("fix:no space", FORMAT),
    ("fix: trailing space ", FORMAT),
    ("[Bug] crash on save", FORMAT),
    ("feature: add export", FORMAT),
    ("fix: .", "must not end with a period"),
    ("fix: crash on save.", "must not end with a period"),
    ("fix: wait...", "must not end with a period"),
    ("fix: resolve crash (#123)", "must not contain an issue number"),
    ("fix: resolve #123", "must not contain an issue number"),
    ("fix: #123 resolve", "must not contain an issue number"),
    ("fix: [WIP] resolve crash", "must not start with a bracket marker"),
    ("fix: [Bug] crash", "must not start with a bracket marker"),
    ("fix:\ttab separator", "control characters"),
    ("fix: valid\n::warning::injected annotation", "control characters"),
    ("fix: valid\r", "control characters"),
    ("fix: bell\x07", "control characters"),
    ("fix: escape\x1b[31m", "control characters"),
)


def load_workflow() -> dict:
    return yaml.safe_load(WORKFLOW.read_text())


def title_step() -> dict:
    steps = load_workflow()["jobs"]["pr-title"]["steps"]
    return next(step for step in steps if "TITLE" in step.get("env", {}))


def run_check(title: str, cwd: pathlib.Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "-e", "-c", title_step()["run"]],
        env={"PATH": os.environ["PATH"], "TITLE": title, "LC_ALL": "C.UTF-8"},
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )


class TitleCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self._directory = tempfile.TemporaryDirectory()
        self.addCleanup(self._directory.cleanup)
        self.cwd = pathlib.Path(self._directory.name)

    def test_accepts_titles_that_follow_the_convention(self) -> None:
        for title in ACCEPTED + NOT_ENFORCED:
            with self.subTest(title=title):
                proc = run_check(title, self.cwd)
                self.assertEqual(proc.returncode, 0, proc.stdout)
                self.assertEqual(proc.stdout, f"Title OK: {title}\n")

    def test_rejects_titles_and_names_the_broken_rule(self) -> None:
        for title, reason in REJECTED:
            with self.subTest(title=title):
                proc = run_check(title, self.cwd)
                self.assertEqual(proc.returncode, 1, proc.stdout)
                self.assertIn(reason, proc.stdout)
                self.assertIn('See "Title Convention" in CONTRIBUTING.md', proc.stdout)

    def test_log_cannot_gain_a_workflow_command_from_the_title(self) -> None:
        for title, _ in REJECTED:
            with self.subTest(title=title):
                proc = run_check(title, self.cwd)
                commands = [line for line in proc.stdout.splitlines() if line.startswith("::")]
                self.assertEqual(commands, [ERROR_ANNOTATION])

    def test_title_is_data_and_never_executed(self) -> None:
        marker = self.cwd / "executed"
        for title in (
            f"fix: $(touch {marker}) stays data",
            f"fix: `touch {marker}` stays data",
            f"fix: ok\n$(touch {marker})",
            f'fix: "; touch {marker}; echo "',
        ):
            with self.subTest(title=title):
                run_check(title, self.cwd)
                self.assertFalse(marker.exists())


class WorkflowShapeTests(unittest.TestCase):
    """The workflow keeps the least-privilege shape the title check relies on."""

    def test_runs_on_pull_request_events_with_no_permissions(self) -> None:
        workflow = load_workflow()
        triggers = workflow.get("on", workflow.get(True))
        self.assertEqual(set(triggers), {"pull_request"})
        self.assertEqual(
            set(triggers["pull_request"]["types"]),
            {"opened", "edited", "reopened", "synchronize"},
        )
        self.assertEqual(workflow["permissions"], {})

    def test_checks_out_nothing_and_uses_no_secrets(self) -> None:
        steps = load_workflow()["jobs"]["pr-title"]["steps"]
        self.assertTrue(all("uses" not in step for step in steps))
        self.assertNotIn("secrets.", WORKFLOW.read_text())

    def test_title_reaches_the_script_only_through_the_environment(self) -> None:
        step = title_step()
        self.assertEqual(step["env"]["TITLE"], "${{ github.event.pull_request.title }}")
        self.assertNotIn("${{", step["run"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
