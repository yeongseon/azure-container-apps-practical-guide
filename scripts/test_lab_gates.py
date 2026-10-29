from __future__ import annotations

import contextlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Iterator
from datetime import datetime
from pathlib import Path
from typing import Final

REPO_ROOT: Final = Path(__file__).resolve().parents[1]
GATE_OUTPUTS: Final = {
    "acr-pull-failure": (
        "30-cohort-integrity-gate.json",
        "31-failure-attribution-gate.json",
        "32-recovery-materialization-gate.json",
        "33-in-place-recovery-continuity-gate.json",
    ),
    "appinsights-connection-string-missing": (
        "16-cohort-integrity-gate.json",
        "17-failure-attribution-gate.json",
        "18-recovery-materialization-gate.json",
        "19-single-variable-falsification-gate.json",
    ),
    "cpu-throttling": (
        "14-cohort-integrity-gate.json",
        "15-baseline-cpu-pressure-gate.json",
        "16-recovery-materialization-gate.json",
        "17-single-variable-falsification-gate.json",
    ),
}


@contextlib.contextmanager
def fixture_lab(name: str) -> Iterator[Path]:
    with tempfile.TemporaryDirectory(prefix="lab-gates-") as tmp:
        destination = Path(tmp) / "labs" / name
        _ = shutil.copytree(
            REPO_ROOT / "labs" / name,
            destination,
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
        )
        yield destination


def run_verify(lab: Path) -> subprocess.CompletedProcess[str]:
    # Remove only derived outputs so a no-op verifier cannot reuse committed gates.
    for name in GATE_OUTPUTS[lab.name]:
        (lab / "evidence" / name).unlink(missing_ok=True)
    env = {
        **os.environ,
        "PATH": f"{Path(sys.executable).parent}{os.pathsep}{os.environ.get('PATH', '')}",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    return subprocess.run(
        ["bash", "verify.sh"],
        cwd=lab,
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )


class GateTests(unittest.TestCase):
    lab_name: str = ""

    def test_readme_without_gate_names_fails(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            _ = (lab / "evidence" / "README.md").write_text("Evidence index pending.\n")

            result = run_verify(lab)

            self.assert_readme_result(lab, False)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_readme_missing_one_gate_name_fails(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            names = GATE_OUTPUTS[self.lab_name]
            _ = (lab / "evidence" / "README.md").write_text("\n".join(names[:-1]) + "\n")

            result = run_verify(lab)

            self.assert_readme_result(lab, False)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_committed_readme_passes(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            result = run_verify(lab)

            self.assert_readme_result(lab, True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_emitted_gates_use_evaluation_time(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            result = run_verify(lab)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for name in GATE_OUTPUTS[self.lab_name]:
                with self.subTest(gate=name):
                    data: dict[str, str] = {**json.loads((lab / "evidence" / name).read_text())}
                    self.assertNotIn("utc_captured", data)
                    self.assertIn("evaluated_at_utc", data)
                    _ = datetime.strptime(data["evaluated_at_utc"], "%Y-%m-%dT%H:%M:%SZ")

    def assert_readme_result(self, lab: Path, expected: bool) -> None:
        data: dict[str, dict[str, bool]] = {
            **json.loads((lab / "evidence" / GATE_OUTPUTS[self.lab_name][0]).read_text())
        }
        key = (
            "sub_gate_d_readme_xref" if self.lab_name == "cpu-throttling"
            else "sub_gate_d_readme_references_gate_outputs"
        )
        self.assertIs(data[key]["d_pass"], expected)


class AcrPullFailureTests(GateTests):
    lab_name: str = "acr-pull-failure"


class AppInsightsTests(GateTests):
    lab_name: str = "appinsights-connection-string-missing"


class CpuThrottlingTests(GateTests):
    lab_name: str = "cpu-throttling"


def load_tests(loader: unittest.TestLoader, _tests: unittest.TestSuite,
               _pattern: str | None) -> unittest.TestSuite:
    return unittest.TestSuite(
        loader.loadTestsFromTestCase(case)
        for case in (AcrPullFailureTests, AppInsightsTests, CpuThrottlingTests)
    )


if __name__ == "__main__":
    _ = unittest.main()
