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
    "startup-degraded-transient-failure": (
        "10-canonical-evidence-integrity-gate.json",
        "11-failure-degraded-state-gate.json",
        "12-recovery-fix-gate.json",
        "13-cross-artifact-consistency-gate.json",
    ),
    "keda-no-metrics-returned": (
        "10-h1-slow-not-ready-gate.json",
        "11-h1-crash-not-ready-gate.json",
        "12-h2-healthy-post-ready-gate.json",
        "13-h3-cross-scenario-falsification-gate.json",
    ),
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

    def test_readme_omitting_each_gate_name_fails(self) -> None:
        for omitted in GATE_OUTPUTS[self.lab_name]:
            with self.subTest(omitted=omitted), fixture_lab(self.lab_name) as lab:
                names = [name for name in GATE_OUTPUTS[self.lab_name] if name != omitted]
                _ = (lab / "evidence" / "README.md").write_text("\n".join(names) + "\n")

                result = run_verify(lab)

                self.assert_readme_result(lab, False)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

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


class StartupGateTests(unittest.TestCase):
    lab_name: str = "startup-degraded-transient-failure"

    def test_baseline_falsified_with_perturbation_false_fails(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            path = lab / "evidence" / "qF-run-summary-20260620T224149Z.json"
            records: list[dict[str, str]] = [*json.loads(path.read_text())]
            for record in records:
                if record["run_id"].startswith("baseline-"):
                    record["falsification_triggered"] = "True"
            _ = path.write_text(json.dumps(records))

            result = run_verify(lab)

            data: dict[str, dict[str, bool | int]] = {**json.loads((lab / "evidence" / GATE_OUTPUTS[self.lab_name][2]).read_text())}
            sub = data["sub_gate_b_falsification_rule_not_triggered"]
            self.assertEqual(sub["observed_false_run_count"], 1)
            self.assertIs(sub["b_pass"], False)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_disjoint_ids_fail_even_with_three_qe_ids(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            path = lab / "evidence" / "qA-revision-state-20260620T223951Z.json"
            records: list[dict[str, str]] = [*json.loads(path.read_text())]
            for record in records:
                if record.get("perturbation_id"):
                    record["perturbation_id"] = "disjoint-" + record["perturbation_id"]
            _ = path.write_text(json.dumps(records))
            qe: list[dict[str, str]] = [*json.loads((lab / "evidence" / "qE-perturbation-markers-20260620T224143Z.json").read_text())]
            self.assertEqual(len({record["perturbation_id"] for record in qe}), 3)

            result = run_verify(lab)

            data: dict[str, dict[str, bool | int]] = {**json.loads((lab / "evidence" / GATE_OUTPUTS[self.lab_name][3]).read_text())}
            sub = data["sub_gate_b_perturbation_ids_consistent"]
            self.assertEqual(sub["observed_shared_perturbation_id_count"], 0)
            self.assertIs(sub["b_pass"], False)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_committed_evidence_control_passes(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            result = run_verify(lab)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_emitted_gates_use_evaluation_time(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            result = run_verify(lab)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for name in GATE_OUTPUTS[self.lab_name]:
                with self.subTest(gate=name):
                    data: dict[str, str] = {**json.loads((lab / "evidence" / name).read_text())}
                    self.assertNotIn("utc_captured", data)
                    _ = datetime.strptime(data["evaluated_at_utc"], "%Y-%m-%dT%H:%M:%SZ")


class KedaGateTests(unittest.TestCase):
    lab_name: str = "keda-no-metrics-returned"

    def test_missing_or_unreported_health_state_fails(self) -> None:
        for scenario in ("crash", "slow", "healthy"):
            for replacement in (None, "null", '""', '"None"', '"Unknown"', '"Degraded"', '"Other"'):
                with self.subTest(scenario=scenario, state=replacement), fixture_lab(self.lab_name) as lab:
                    path = next((lab / "evidence" / f"ca-nometrics-{scenario}").glob("report-*.txt"))
                    lines = path.read_text().splitlines(keepends=True)
                    for index, line in enumerate(lines):
                        if '"healthState":' in line:
                            lines[index] = (
                                "" if replacement is None
                                else f'  "healthState": {replacement},\n'
                            )
                            break
                    else:
                        self.fail("fixture has no health state")
                    _ = path.write_text("".join(lines))

                    result = run_verify(lab)

                    data: dict[str, dict[str, bool]] = {**json.loads((lab / "evidence" / GATE_OUTPUTS[self.lab_name][3]).read_text())}
                    sub = data["sub_gate_c_health_state_matches_outcome"]
                    self.assertIs(sub["c_strong_path_exact_state_pattern"], False)
                    self.assertIs(sub["c_fallback_path_crash_not_healthy_and_one_healthy"], False)
                    self.assertIs(sub["c_pass"], False)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_reported_unhealthy_slow_uses_fallback_tier_control(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            path = next((lab / "evidence" / "ca-nometrics-slow").glob("report-*.txt"))
            _ = path.write_text(path.read_text().replace('"healthState": "Healthy"', '"healthState": "Unhealthy"'))

            result = run_verify(lab)

            data: dict[str, dict[str, bool | str]] = {**json.loads((lab / "evidence" / GATE_OUTPUTS[self.lab_name][3]).read_text())}
            sub = data["sub_gate_c_health_state_matches_outcome"]
            self.assertIs(sub["c_strong_path_exact_state_pattern"], False)
            self.assertIs(sub["c_fallback_path_crash_not_healthy_and_one_healthy"], True)
            self.assertIs(sub["c_pass"], True)
            self.assertEqual(sub["c_evidence_level"], "Fallback")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_healthy_crash_fails_both_tiers(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            path = next((lab / "evidence" / "ca-nometrics-crash").glob("report-*.txt"))
            _ = path.write_text(path.read_text().replace('"healthState": "Unhealthy"', '"healthState": "Healthy"'))

            result = run_verify(lab)

            data: dict[str, dict[str, bool]] = {**json.loads((lab / "evidence" / GATE_OUTPUTS[self.lab_name][3]).read_text())}
            sub = data["sub_gate_c_health_state_matches_outcome"]
            self.assertIs(sub["c_strong_path_exact_state_pattern"], False)
            self.assertIs(sub["c_fallback_path_crash_not_healthy_and_one_healthy"], False)
            self.assertIs(sub["c_pass"], False)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_committed_evidence_control_passes(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            result = run_verify(lab)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


def load_tests(loader: unittest.TestLoader, _tests: unittest.TestSuite,
               _pattern: str | None) -> unittest.TestSuite:
    return unittest.TestSuite(
        loader.loadTestsFromTestCase(case)
        for case in (
            AcrPullFailureTests,
            AppInsightsTests,
            CpuThrottlingTests,
            StartupGateTests,
            KedaGateTests,
        )
    )


if __name__ == "__main__":
    _ = unittest.main()
