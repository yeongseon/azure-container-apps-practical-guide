#!/usr/bin/env python3
"""Regression cases for the title check in ``.github/workflows/pr-title.yml``.

The check is inline in the workflow because its job checks out nothing, so this
test extracts the step's script from the YAML and runs it the way the runner
does: ``bash -e`` with the step's own ``env`` entries and the title in
``TITLE``. Verdict cases run under a UTF-8 and a plain ``C`` locale because the
runner's locale must not change what is accepted.

Usage:
    python3 scripts/test_pr_title_check.py
"""

from __future__ import annotations

import ast
import os
import pathlib
import subprocess
import tempfile
import unicodedata
import unittest

import yaml

WORKFLOW = pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows" / "pr-title.yml"
ERROR_ANNOTATION = "::error::The pull request title does not follow the Title Convention in CONTRIBUTING.md."
LOCALES = ("C.UTF-8", "C")

TYPES = ("feat", "fix", "docs", "test", "perf", "refactor", "ci", "build", "chore", "style", "revert")

# Whitespace (Unicode Zs) and zero-width/format (Cf) characters that bash's
# `[[:space:]]` misses or that are invisible at the edge of a description.
EDGE_CHARACTERS = {
    "no-break space": "\u00a0",
    "ogham space mark": "\u1680",
    "en quad": "\u2000",
    "em space": "\u2003",
    "figure space": "\u2007",
    "thin space": "\u2009",
    "hair space": "\u200a",
    "zero-width space": "\u200b",
    "zero-width non-joiner": "\u200c",
    "zero-width joiner": "\u200d",
    "left-to-right mark": "\u200e",
    "right-to-left mark": "\u200f",
    "narrow no-break space": "\u202f",
    "right-to-left override": "\u202e",
    "medium mathematical space": "\u205f",
    "word joiner": "\u2060",
    "ideographic space": "\u3000",
    "byte order mark": "\ufeff",
    "soft hyphen": "\u00ad",
    "mongolian vowel separator": "\u180e",
}

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
    "fix: use the :: operator",
    "fix: handle ünïcödé names",
    "fix: keep the family emoji \U0001f468\u200d\U0001f469\u200d\U0001f467 intact",
    "fix: trailing ellipsis\u2026",
    "fix: ends with a paren)",
    'fix: ends with a quote"',
    "fix: " + "long " * 50 + "end",
    "fix: a#123",
    "fix: 0#123",
    "fix: #\u0661\u0662\u0663",
    "fix: #\uff11\uff12\uff13",
    "fix: the # key",
    "fix: trailing hash #",
)

# Editorial guidance in CONTRIBUTING.md that the check does not verify.
NOT_ENFORCED = (
    "fix: Resolve crash",
    "fix: 修复崩溃",
    "fix: two  spaces inside",
)

FORMAT = 'must be "type: description"'
EDGE = "must not start or end with a space or an invisible character"
PERIOD = "must not end with a period"
ISSUE = "must not contain an issue number"
BRACKET = "must not start with a bracket marker"
CONTROL = "control characters"

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
    ("fix:no space", FORMAT),
    ("fix:\u00a0no ascii space after the colon", FORMAT),
    ("[Bug] crash on save", FORMAT),
    ("feature: add export", FORMAT),
    ("fix:  two spaces after the colon", EDGE),
    ("fix: trailing space ", EDGE),
    *((f"fix: {char}x", EDGE) for char in EDGE_CHARACTERS.values()),
    *((f"fix: x{char}", EDGE) for char in EDGE_CHARACTERS.values()),
    ("fix: \u00a0[WIP] hidden bracket marker", EDGE),
    ("fix: .", PERIOD),
    ("fix: crash on save.", PERIOD),
    ("fix: wait...", PERIOD),
    ("fix: resolve crash (#123)", ISSUE),
    ("fix: resolve #123", ISSUE),
    ("fix: #123 resolve", ISSUE),
    ("fix: #12", ISSUE),
    ("fix: \u00e9#123", ISSUE),
    ("fix: \u6f22#123", ISSUE),
    ("fix: \u0662#123", ISSUE),
    ("fix: _#123", ISSUE),
    ("fix: ##123", ISSUE),
    ("fix: #123abc", ISSUE),
    ("fix: [WIP] resolve crash", BRACKET),
    ("fix: [Bug] crash", BRACKET),
    ("fix:\ttab separator", CONTROL),
    ("fix: valid\n::warning::injected annotation", CONTROL),
    ("fix: valid\r", CONTROL),
    ("fix: bell\x07", CONTROL),
    ("fix: escape\x1b[31m", CONTROL),
    ("fix: delete\x7f", CONTROL),
    ("fix: next line\u0085", CONTROL),
    ("fix: line\u2028separator", CONTROL),
    ("fix: paragraph\u2029separator", CONTROL),
    ("fix: vertical\x0btab", CONTROL),
    ("fix: form\x0cfeed", CONTROL),
    ("fix: file\x1cseparator", CONTROL),
    ("fix: x\n::add-mask::secret", CONTROL),
    ("fix: x\n::stop-commands::token", CONTROL),
    ("fix: x\r::error::forged", CONTROL),
    ("fix: x\u2028::warning::forged", CONTROL),
)


def load_workflow() -> dict:
    return yaml.safe_load(WORKFLOW.read_text())


def title_step() -> dict:
    steps = load_workflow()["jobs"]["pr-title"]["steps"]
    return next(step for step in steps if "TITLE" in step.get("env", {}))


def heredoc_python() -> str:
    lines = title_step()["run"].splitlines()
    return "\n".join(lines[1:-1])


def run_check(title: str | bytes, cwd: pathlib.Path, locale: str = LOCALES[0]) -> subprocess.CompletedProcess[str]:
    step = title_step()
    static_env = {key: str(value) for key, value in step["env"].items() if key != "TITLE"}
    # PYTHONUTF8=0 is the ambient setting the step's own env must override.
    return subprocess.run(
        ["bash", "-e", "-c", step["run"]],
        env={"PATH": os.environ["PATH"], "LC_ALL": locale, "PYTHONUTF8": "0", **static_env, "TITLE": title},
        cwd=cwd,
        capture_output=True,
        text=True,
        errors="replace",
        timeout=30,
        check=False,
    )


class TitleCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self._directory = tempfile.TemporaryDirectory()
        self.addCleanup(self._directory.cleanup)
        self.cwd = pathlib.Path(self._directory.name)

    def test_accepts_titles_that_follow_the_convention(self) -> None:
        for locale in LOCALES:
            for title in ACCEPTED + NOT_ENFORCED:
                with self.subTest(locale=locale, title=title):
                    proc = run_check(title, self.cwd, locale)
                    self.assertEqual(proc.returncode, 0, proc.stdout)
                    self.assertEqual(proc.stdout, f"Title OK: {title}\n")
                    self.assertEqual(proc.stderr, "")

    def test_rejects_titles_and_names_the_broken_rule(self) -> None:
        for locale in LOCALES:
            for title, reason in REJECTED:
                with self.subTest(locale=locale, title=title):
                    proc = run_check(title, self.cwd, locale)
                    self.assertEqual(proc.returncode, 1, proc.stdout)
                    self.assertIn(reason, proc.stdout)
                    self.assertIn('See "Title Convention" in CONTRIBUTING.md', proc.stdout)
                    self.assertEqual(proc.stderr, "")

    def test_every_broken_rule_is_named_at_once(self) -> None:
        proc = run_check("fix: \u00a0[WIP] crash (#12).", self.cwd)
        self.assertEqual(proc.returncode, 1)
        for reason in (EDGE, PERIOD, ISSUE):
            self.assertIn(reason, proc.stdout)
        proc = run_check("fix: [WIP] crash.", self.cwd)
        for reason in (BRACKET, PERIOD):
            self.assertIn(reason, proc.stdout)

    def test_log_cannot_gain_a_workflow_command_from_the_title(self) -> None:
        for title, _ in REJECTED:
            with self.subTest(title=title):
                proc = run_check(title, self.cwd)
                commands = [line for line in proc.stdout.splitlines() if line.lstrip().startswith("::")]
                self.assertEqual(commands, [ERROR_ANNOTATION])

    def test_rejected_title_is_printed_without_control_characters(self) -> None:
        masked = ("Cc", "Cs", "Zl", "Zp")
        for title, _ in REJECTED:
            with self.subTest(title=title):
                proc = run_check(title, self.cwd)
                leaked = [char for char in proc.stdout if char != "\n" and unicodedata.category(char) in masked]
                self.assertEqual(leaked, [])

    def test_accepted_title_cannot_start_a_workflow_command(self) -> None:
        for title in ACCEPTED + NOT_ENFORCED:
            with self.subTest(title=title):
                proc = run_check(title, self.cwd)
                commands = [line for line in proc.stdout.splitlines() if line.lstrip().startswith("::")]
                self.assertEqual(commands, [])

    def test_invalid_utf8_title_is_rejected_without_a_traceback(self) -> None:
        for locale in LOCALES:
            with self.subTest(locale=locale):
                proc = run_check(b"fix: bad \xff byte", self.cwd, locale)
                self.assertEqual(proc.returncode, 1)
                self.assertIn(CONTROL, proc.stdout)
                self.assertNotIn("Traceback", proc.stdout + proc.stderr)

    def test_title_is_data_and_never_executed(self) -> None:
        marker = self.cwd / "executed"
        for title in (
            f"fix: $(touch {marker}) stays data",
            f"fix: `touch {marker}` stays data",
            f"fix: ok\n$(touch {marker})",
            f'fix: "; touch {marker}; echo "',
            f"fix: '; touch {marker}; echo '",
            f"fix: {{touch,{marker}}}",
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
        self.assertTrue(step["run"].startswith("python3 - <<'PY'\n"))

    def test_script_needs_only_the_standard_library(self) -> None:
        tree = ast.parse(heredoc_python())
        imported = {
            alias.name.split(".")[0]
            for node in ast.walk(tree)
            if isinstance(node, (ast.Import, ast.ImportFrom))
            for alias in (node.names if isinstance(node, ast.Import) else [ast.alias(name=node.module or "")])
        }
        self.assertEqual(imported, {"os", "re", "sys", "unicodedata"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
