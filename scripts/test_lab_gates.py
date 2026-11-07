from __future__ import annotations

import contextlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Callable, Iterator, Mapping
from datetime import datetime, timezone
from pathlib import Path
from typing import Final

REPO_ROOT: Final = Path(__file__).resolve().parents[1]
REPLAY_LABS: Final = {
    "acr-network-path-dns-forwarder-bypass": (
        (
            "14-cohort-integrity-gate.json",
            "15-h1-trigger-produces-failure-gate.json",
            "16-h2-fix-restores-recovery-gate.json",
            "17-bounded-falsification-gate.json",
        ),
        (),
    ),
    "acr-network-path-firewall-allowlist": (
        (
            "14-cohort-integrity-gate.json",
            "15-h1-trigger-produces-failure-gate.json",
            "16-h2-fix-restores-recovery-gate.json",
            "17-bounded-falsification-gate.json",
        ),
        (),
    ),
    "acr-network-path-pe-direct": (
        (
            "14-cohort-integrity-gate.json",
            "15-h1-trigger-produces-failure-gate.json",
            "16-h2-fix-restores-recovery-gate.json",
            "17-bounded-falsification-gate.json",
        ),
        (),
    ),
    "acr-network-path-record-split-brain": (
        (
            "14-cohort-integrity-gate.json",
            "15-h1-trigger-produces-failure-gate.json",
            "16-h2-fix-restores-recovery-gate.json",
            "17-bounded-falsification-gate.json",
        ),
        (),
    ),
    "dapr-integration": (
        (
            "14-cohort-integrity-gate.json",
            "15-h1-trigger-produces-failure-gate.json",
            "16-h2-fix-restores-recovery-gate.json",
            "17-bounded-falsification-gate.json",
        ),
        (),
    ),
    "image-size-startup-delay": (
        (
            "10-h1-a-large-cold-pull-gate.json",
            "11-h1-b-small-cold-pull-gate.json",
            "12-h1-c-speedup-ratio-gate.json",
            "13-h2-falsification-gate.json",
        ),
        (),
    ),
    "zone-redundancy-best-effort": (
        (
            "14-cohort-integrity-gate.json",
            "15-negative-control-baseline-validity-gate.json",
            "16-positive-control-perturbation-validity-gate.json",
            "17-bounded-coverage-uncertainty-gate.json",
        ),
        ("--phase-b-only",),
    ),
}
GATE_OUTPUTS: Final = {
    "memory-leak-oomkilled": (
        "10-h1-hard-oom-immediate-gate.json",
        "11-h1-leak-delayed-oom-gate.json",
        "12-h2-healthy-control-gate.json",
        "13-h3-cross-scenario-falsification-gate.json",
    ),
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


def run_verify(lab: Path, extra_env: Mapping[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    # Remove only derived outputs so a no-op verifier cannot reuse committed gates.
    for name in GATE_OUTPUTS[lab.name]:
        (lab / "evidence" / name).unlink(missing_ok=True)
    env = {
        **os.environ,
        "PATH": f"{Path(sys.executable).parent}{os.pathsep}{os.environ.get('PATH', '')}",
        "PYTHONDONTWRITEBYTECODE": "1",
        **(extra_env or {}),
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

    def test_unexpected_run_mix_fails(self) -> None:
        def rename_baseline(records: list[dict[str, str]]) -> list[dict[str, str]]:
            return [
                {**record, "run_id": "perturbation-FAKE"} if record["run_id"].startswith("baseline-") else record
                for record in records
            ]

        def duplicate_baseline(records: list[dict[str, str]]) -> list[dict[str, str]]:
            baseline = next(record for record in records if record["run_id"].startswith("baseline-"))
            return [*records, {**baseline, "run_id": "baseline-20260620213448"}]

        def remove_baseline(records: list[dict[str, str]]) -> list[dict[str, str]]:
            return [record for record in records if not record["run_id"].startswith("baseline-")]

        for name, mutate, baseline_count, perturbation_count in (
            ("baseline renamed to a second perturbation", rename_baseline, 0, 2),
            ("duplicate baseline appended", duplicate_baseline, 2, 1),
            ("baseline removed", remove_baseline, 0, 1),
        ):
            with self.subTest(case=name), fixture_lab(self.lab_name) as lab:
                path = lab / "evidence" / "qF-run-summary-20260620T224149Z.json"
                _ = path.write_text(json.dumps(mutate([*json.loads(path.read_text())])))

                result = run_verify(lab)

                data: dict[str, dict[str, bool | int]] = {**json.loads((lab / "evidence" / GATE_OUTPUTS[self.lab_name][2]).read_text())}
                sub = data["sub_gate_b_falsification_rule_not_triggered"]
                self.assertEqual(sub["observed_baseline_run_count"], baseline_count)
                self.assertEqual(sub["observed_perturbation_run_count"], perturbation_count)
                self.assertIs(sub["b_pass"], False)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_gate_10_scenario_mapping_requires_named_run_prefixes(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            path = lab / "evidence" / "qF-run-summary-20260620T224149Z.json"
            records: list[dict[str, object]] = [*json.loads(path.read_text())]
            for index, record in enumerate(records):
                record["run_id"] = f"unmapped-{index}"
            _ = path.write_text(json.dumps(records))

            result = run_verify(lab)

            data: dict[str, dict[str, object]] = {**json.loads((lab / "evidence" / GATE_OUTPUTS[self.lab_name][0]).read_text())}
            sub = data["sub_gate_c_scenario_mapping_explicit"]
            self.assertEqual(sub["observed_distinct_run_id_count"], 2)
            self.assertEqual(sub["c_path_tier"], "failed_scenario_mapping")
            self.assertIs(sub["c_pass"], False)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_perturbation_run_emits_all_failed_gate_reports(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            path = lab / "evidence" / "qF-run-summary-20260620T224149Z.json"
            records: list[dict[str, object]] = [*json.loads(path.read_text())]
            _ = path.write_text(json.dumps([
                record for record in records
                if not str(record.get("run_id", "")).startswith("perturbation-")
            ]))

            result = run_verify(lab)

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            for name in GATE_OUTPUTS[self.lab_name]:
                with self.subTest(gate=name):
                    self.assertTrue((lab / "evidence" / name).exists())
            gate_12: dict[str, dict[str, object]] = {**json.loads(
                (lab / "evidence" / GATE_OUTPUTS[self.lab_name][2]).read_text()
            )}
            self.assertIs(gate_12["sub_gate_a_k6_client_observed_error_rate_zero"]["a_pass"], False)
            self.assertIs(gate_12["sub_gate_b_falsification_rule_not_triggered"]["b_pass"], False)

    def test_empty_qa_emits_all_failed_gate_reports(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            path = lab / "evidence" / "qA-revision-state-20260620T223951Z.json"
            _ = path.write_text("[]")

            result = run_verify(lab)

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            for name in GATE_OUTPUTS[self.lab_name]:
                with self.subTest(gate=name):
                    self.assertTrue((lab / "evidence" / name).exists())
            gate_12: dict[str, object] = {**json.loads(
                (lab / "evidence" / GATE_OUTPUTS[self.lab_name][2]).read_text()
            )}
            self.assertIs(gate_12["startup_degraded_transient_failure_h0_partb_recovery_no_client_impact_all_subgates_pass"], True)
            gate_13: dict[str, dict[str, object]] = {**json.loads(
                (lab / "evidence" / GATE_OUTPUTS[self.lab_name][3]).read_text()
            )}
            self.assertIs(gate_13["sub_gate_b_perturbation_ids_consistent"]["b_pass"], False)

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

    @staticmethod
    def set_error_rate(value: object) -> Callable[[dict[str, object]], object]:
        def apply(record: dict[str, object]) -> None:
            record["err_pct"] = value

        return apply

    def error_rate_subgate(
        self, mutate: Callable[[dict[str, object]], object], literal: str | None = None
    ) -> tuple[subprocess.CompletedProcess[str], dict[str, object]]:
        """Run the verifier on a mutated perturbation row and return its Gate 12(a) sub-gate.

        A literal replaces the placeholder err_pct with a raw JSON token, so values that json.dumps
        or a float round trip would alter reach the verifier exactly as written.
        """
        def reject_constant(name: str) -> object:
            raise AssertionError(f"non-standard JSON constant in a gate output: {name}")

        with fixture_lab(self.lab_name) as lab:
            path = lab / "evidence" / "qF-run-summary-20260620T224149Z.json"
            records: list[dict[str, object]] = [*json.loads(path.read_text())]
            for record in records:
                if str(record["run_id"]).startswith("perturbation-"):
                    _ = mutate(record)
            text = json.dumps(records)
            if literal is not None:
                text = text.replace('"@@LITERAL@@"', literal)
            _ = path.write_text(text)

            result = run_verify(lab)

            for name in GATE_OUTPUTS[self.lab_name]:
                emitted = lab / "evidence" / name
                if emitted.exists():
                    _ = json.loads(emitted.read_text(), parse_constant=reject_constant)
            data: dict[str, dict[str, object]] = {**json.loads((lab / "evidence" / GATE_OUTPUTS[self.lab_name][2]).read_text())}
            return result, data["sub_gate_a_k6_client_observed_error_rate_zero"]

    def test_missing_or_invalid_error_rate_fails_the_owning_subgate(self) -> None:
        for name, mutate, literal in (
            ("key missing", lambda record: record.pop("err_pct"), None),
            ("null", self.set_error_rate(None), None),
            ("empty string", self.set_error_rate(""), None),
            ("blank string", self.set_error_rate("   "), None),
            ("boolean", self.set_error_rate(True), None),
            ("non-numeric text", self.set_error_rate("abc"), None),
            ("not a number", self.set_error_rate("nan"), None),
            ("infinity", self.set_error_rate("inf"), None),
            ("negative", self.set_error_rate("-1"), None),
            ("negative below float range", self.set_error_rate("-1e-400"), None),
            ("underscore padded zero", self.set_error_rate("_0_"), None),
            ("underscore inside a decimal", self.set_error_rate("0_._3"), None),
            ("underscore grouped zero", self.set_error_rate("0_0"), None),
            ("arabic-indic digit", self.set_error_rate("\u0660"), None),
            ("fullwidth digit", self.set_error_rate("\uff10"), None),
            ("JSON number negative below float range", self.set_error_rate("@@LITERAL@@"), "-1e-400"),
            ("bare NaN token", self.set_error_rate("@@LITERAL@@"), "NaN"),
            ("bare Infinity token", self.set_error_rate("@@LITERAL@@"), "Infinity"),
            ("bare negative Infinity token", self.set_error_rate("@@LITERAL@@"), "-Infinity"),
        ):
            with self.subTest(case=name):
                result, sub = self.error_rate_subgate(mutate, literal)

                self.assertIsNone(sub["observed_perturbation_err_pct"])
                self.assertIs(sub["a_pass"], False)
                self.assertIn("a_input_problem", sub)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_valid_error_rate_forms_keep_their_documented_tiers(self) -> None:
        for name, value, strong, fallback, expected_pass in (
            ("integer zero", 0, True, True, True),
            ("string zero", "0", True, True, True),
            ("decimal zero", "0.0", True, True, True),
            ("JSON float zero", 0.0, True, True, True),
            ("inside the lower-evidence tier", "0.3", False, True, True),
            ("JSON float inside the lower-evidence tier", 0.3, False, True, True),
            ("at the fallback bound", "0.5", False, False, False),
        ):
            with self.subTest(case=name):
                result, sub = self.error_rate_subgate(self.set_error_rate(value))

                self.assertIs(sub["a_strong_path_err_pct_equals_zero"], strong)
                self.assertIs(sub["a_fallback_path_err_pct_below_point_five"], fallback)
                self.assertIs(sub["a_pass"], expected_pass)
                self.assertNotIn("a_input_problem", sub)
                self.assertNotIn("observed_perturbation_err_pct_exact", sub)
                self.assertEqual(result.returncode == 0, expected_pass, result.stdout + result.stderr)

    def test_error_rates_beyond_float_resolution_are_compared_exactly(self) -> None:
        for name, value, literal, strong, fallback, expected_pass, exact in (
            ("string below float range", "1e-400", None, False, True, True, "1E-400"),
            ("string just below the fallback bound", "0.49999999999999999", None, False, True, True, "0.49999999999999999"),
            ("string beyond float range", "1e309", None, False, False, False, "1E+309"),
            ("JSON number below float range", "@@LITERAL@@", "1e-400", False, True, True, "1E-400"),
            ("JSON number just below the fallback bound", "@@LITERAL@@", "0.49999999999999999", False, True, True, "0.49999999999999999"),
            ("JSON number beyond float range", "@@LITERAL@@", "1e309", False, False, False, "1E+309"),
        ):
            with self.subTest(case=name):
                result, sub = self.error_rate_subgate(self.set_error_rate(value), literal)

                self.assertIs(sub["a_strong_path_err_pct_equals_zero"], strong)
                self.assertIs(sub["a_fallback_path_err_pct_below_point_five"], fallback)
                self.assertIs(sub["a_pass"], expected_pass)
                self.assertEqual(sub["observed_perturbation_err_pct_exact"], exact)
                self.assertNotIn("a_input_problem", sub)
                self.assertEqual(result.returncode == 0, expected_pass, result.stdout + result.stderr)

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

    def test_gate_11_sidecar_requires_explicit_unhealthy_state(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            report = next((lab / "evidence" / "ca-nometrics-crash").glob("report-*.txt"))
            _ = report.write_text(
                report.read_text()
                .replace('"provisioningState": "Failed"', '"provisioningState": "Succeeded"')
                .replace('"runningState": "Failed"', '"runningState": "Running"')
            )
            revisions = next((lab / "evidence" / "ca-nometrics-crash").glob("revisions-*.json"))
            records: list[dict[str, object]] = [*json.loads(revisions.read_text())]
            records[0]["healthState"] = "Degraded"
            _ = revisions.write_text(json.dumps(records))

            result = run_verify(lab)

            data: dict[str, dict[str, object]] = {**json.loads(
                (lab / "evidence" / GATE_OUTPUTS[self.lab_name][1]).read_text()
            )}
            sub = data["sub_gate_b_unready_state"]
            self.assertEqual(sub["sidecar_first_health_state"], "Degraded")
            self.assertIs(sub["b_fallback_path_sidecar_unhealthy_or_provisioning_failed"], False)
            self.assertEqual(sub["b_path_tier"], "failed_unready_state")
            self.assertIs(sub["b_pass"], False)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_gate_12_zero_parsed_bins_fails_closed(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            report = next((lab / "evidence" / "ca-nometrics-healthy").glob("report-*.txt"))
            before, rest = report.read_text().split("=== 6. Metric error count timeline (5-min bins) ===", 1)
            _, after = rest.split("=== 7.", 1)
            _ = report.write_text(before + "=== 6. Metric error count timeline (5-min bins) ===\n=== 7." + after)

            result = run_verify(lab)

            data: dict[str, dict[str, object]] = {**json.loads(
                (lab / "evidence" / GATE_OUTPUTS[self.lab_name][2]).read_text()
            )}
            sub = data["sub_gate_b_single_bin"]
            self.assertEqual(sub["section_6_bin_count"], 0)
            self.assertIs(sub["b_fallback_path_few_bins_le_2"], False)
            self.assertEqual(sub["b_path_tier"], "failed_bounded_bin_count")
            self.assertIs(sub["b_pass"], False)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_gate_12_zero_parsed_signal_lines_fails_closed(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            report = next((lab / "evidence" / "ca-nometrics-healthy").glob("report-*.txt"))
            before, rest = report.read_text().split("=== 5. System logs: metric errors ===", 1)
            _, after = rest.split("=== 6.", 1)
            _ = report.write_text(before + "=== 5. System logs: metric errors ===\n=== 6." + after)

            result = run_verify(lab)

            data: dict[str, dict[str, object]] = {**json.loads(
                (lab / "evidence" / GATE_OUTPUTS[self.lab_name][2]).read_text()
            )}
            sub = data["sub_gate_c_silent_after_warmup"]
            self.assertEqual(sub["signal_line_count_section_5"], 0)
            self.assertIs(sub["c_fallback_path_few_lines_le_threshold"], False)
            self.assertEqual(sub["c_path_tier"], "failed_bounded_signal_window")
            self.assertIs(sub["c_pass"], False)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_committed_evidence_control_passes(self) -> None:
        with fixture_lab(self.lab_name) as lab:
            result = run_verify(lab)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class EvaluationReplayTests(unittest.TestCase):
    batch_b_payload_anchors: Final = {
        "acr-network-path-dns-forwarder-bypass": {
            "07-system-logs-pre-fix.json": ("pre_anchor_timestamps", "2026-06-29T00:52:42+00:00", "payload.window_end_utc"),
            "08-probe-response-pre-fix.json": ("pre_anchor_timestamps", "2026-06-29T00:49:37+00:00", "payload.captured_after_utc"),
            "12-recovery-surface-post-fix.json": ("post_anchor_timestamps", "2026-06-29T00:52:56+00:00", "capture_metadata.post_window_start_utc"),
        },
        "acr-network-path-record-split-brain": {
            "06-system-logs-pre-fix.json": ("pre_anchor_timestamps", "2026-06-28T22:34:36+00:00", "payload.window_end_utc"),
            "08-probe-response-pre-fix.json": ("pre_anchor_timestamps", "2026-06-28T22:34:36+00:00", "payload.captured_after_utc"),
            "11-probe-response-post-fix.json": ("post_anchor_timestamps", "2026-06-28T22:36:42+00:00", "payload.captured_after_utc"),
            "12-pe-nic-config-post-fix.json": ("post_anchor_timestamps", "2026-06-28T22:37:05+00:00", "capture_metadata.post_window_start_utc"),
        },
    }

    @contextlib.contextmanager
    def replay_fixture(self, name: str) -> Iterator[Path]:
        with fixture_lab(name) as lab:
            guide = Path("docs/troubleshooting/lab-guides") / f"{name}.md"
            destination = lab.parents[1] / guide
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPO_ROOT / guide, destination)
            snapshots = lab.parent / "committed-gates"
            snapshots.mkdir()
            for output in REPLAY_LABS[name][0]:
                shutil.copy2(lab / "evidence" / output, snapshots / output)
            yield lab

    def assert_replay(self, lab: Path, clean: bool = True) -> None:
        outputs, arguments = REPLAY_LABS[lab.name]
        if clean:
            for name in outputs:
                (lab / "evidence" / name).unlink(missing_ok=True)
        start = datetime.now(timezone.utc).replace(microsecond=0)
        result = subprocess.run(
            ["bash", "verify.sh", *arguments], cwd=lab,
            env={**os.environ, "GATE_REPLAY_BASELINE_DIR": str(lab.parent / "committed-gates")},
            capture_output=True, text=True, timeout=60, check=False,
        )
        end = datetime.now(timezone.utc).replace(microsecond=0)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in outputs:
            path = lab / "evidence" / name
            self.assertTrue(path.is_file(), f"missing newly emitted output: {name}")
            current = json.loads(path.read_text())
            self.assertIsInstance(current, dict)
            self.assertNotIn("utc_captured", current)
            value = current.pop("evaluated_at_utc")
            stamp = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            self.assertEqual(stamp.strftime("%Y-%m-%dT%H:%M:%SZ"), value)
            self.assertLessEqual(start, stamp)
            self.assertLessEqual(stamp, end)
            expected = json.loads((lab.parent / "committed-gates" / name).read_text())
            expected.pop("evaluated_at_utc", None)
            expected.pop("utc_captured", None)
            self.assertEqual(json.dumps(current, sort_keys=True), json.dumps(expected, sort_keys=True), name)

    def test_two_clean_replays_preserve_every_non_stamp_field(self) -> None:
        for name, (outputs, _) in REPLAY_LABS.items():
            with self.subTest(lab=name), self.replay_fixture(name) as lab:
                self.assert_replay(lab)
                first = {}
                for output in outputs:
                    data = json.loads((lab / "evidence" / output).read_text())
                    data.pop("evaluated_at_utc")
                    first[output] = data
                self.assert_replay(lab)
                for output in outputs:
                    data = json.loads((lab / "evidence" / output).read_text())
                    data.pop("evaluated_at_utc")
                    self.assertEqual(json.dumps(data, sort_keys=True), json.dumps(first[output], sort_keys=True))

    def test_existing_old_stamps_cannot_pin_the_replay_clock(self) -> None:
        for name, (outputs, _) in REPLAY_LABS.items():
            for key in ("evaluated_at_utc", "utc_captured"):
                with self.subTest(lab=name, key=key), self.replay_fixture(name) as lab:
                    for output in outputs:
                        path = lab / "evidence" / output
                        data = json.loads(path.read_text())
                        data.pop("evaluated_at_utc", None)
                        data.pop("utc_captured", None)
                        data[key] = "2000-01-01T00:00:00Z"
                        path.write_text(json.dumps(data))
                    self.assert_replay(lab, clean=False)

    def test_noop_verifier_cannot_reuse_committed_outputs(self) -> None:
        for name in REPLAY_LABS:
            with self.subTest(lab=name), self.replay_fixture(name) as lab:
                (lab / "verify.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
                with self.assertRaisesRegex(AssertionError, "missing newly emitted output"):
                    self.assert_replay(lab)

    def test_previous_verifier_capture_stamp_is_rejected(self) -> None:
        for name in (
            "acr-network-path-dns-forwarder-bypass",
            "acr-network-path-firewall-allowlist",
            "acr-network-path-pe-direct",
            "acr-network-path-record-split-brain",
        ):
            with self.subTest(lab=name), self.replay_fixture(name) as lab:
                verify = lab / "verify.sh"
                original = verify.read_text()
                stale = original.replace(
                    "evaluated_at_utc': EVALUATED_AT_UTC,",
                    "utc_captured': EVALUATED_AT_UTC,",
                ).replace(
                    '"evaluated_at_utc": EVALUATED_AT_UTC,',
                    '"utc_captured": EVALUATED_AT_UTC,',
                )
                self.assertNotEqual(stale, original)
                _ = verify.write_text(stale)

                with self.assertRaisesRegex(AssertionError, "utc_captured"):
                    self.assert_replay(lab)

    def test_acr_replay_rejects_changed_embedded_raw_timestamp(self) -> None:
        timestamp_files = {
            "acr-network-path-dns-forwarder-bypass": "08-probe-response-pre-fix.json",
            "acr-network-path-record-split-brain": "08-probe-response-pre-fix.json",
        }
        for name, raw_name in timestamp_files.items():
            with self.subTest(lab=name), tempfile.TemporaryDirectory(prefix="lab-gate-tamper-") as tmp:
                root = Path(tmp)
                lab = root / "labs" / name
                _ = shutil.copytree(REPO_ROOT / "labs" / name, lab)
                guide = Path("docs/troubleshooting/lab-guides") / f"{name}.md"
                destination = root / guide
                destination.parent.mkdir(parents=True)
                _ = shutil.copy2(REPO_ROOT / guide, destination)
                scripts = root / "scripts"
                scripts.mkdir()
                _ = shutil.copy2(REPO_ROOT / "scripts" / "check_gate_replay.py", scripts)
                for command in (
                    ["git", "init", "--quiet"],
                    ["git", "add", "."],
                    [
                        "git", "-c", "user.name=Replay fixture",
                        "-c", "user.email=fixture@example.com",
                        "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "test: fixture",
                    ],
                ):
                    _ = subprocess.run(command, cwd=root, check=True, capture_output=True)
                raw = lab / "evidence" / raw_name
                original = raw.read_text()
                changed = original.replace("2026-06-", "2026-07-", 1)
                self.assertNotEqual(changed, original)
                _ = raw.write_text(changed)

                result = subprocess.run(
                    [
                        sys.executable,
                        str(scripts / "check_gate_replay.py"),
                        name,
                        *REPLAY_LABS[name][0],
                    ],
                    cwd=root,
                    capture_output=True,
                    text=True,
                    timeout=60,
                    check=False,
                )

                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("current raw input bytes differ from HEAD", result.stderr)

    def test_batch_b_payload_timestamps_override_shifted_baseline_anchors(self) -> None:
        for name, anchors in self.batch_b_payload_anchors.items():
            with self.subTest(lab=name), self.replay_fixture(name) as lab:
                gate14 = lab.parent / "committed-gates" / REPLAY_LABS[name][0][0]
                baseline = json.loads(gate14.read_text())
                observed = baseline["sub_gates"][1]["observed_values"]
                for anchor_class in ("pre_anchor_timestamps", "post_anchor_timestamps"):
                    for anchor in observed[anchor_class].values():
                        anchor["timestamp_utc"] = "2026-07-30T00:00:00+00:00"
                _ = gate14.write_text(json.dumps(baseline))
                for output in REPLAY_LABS[name][0]:
                    (lab / "evidence" / output).unlink(missing_ok=True)

                result = subprocess.run(
                    ["bash", "verify.sh"],
                    cwd=lab,
                    env={**os.environ, "GATE_REPLAY_BASELINE_DIR": str(lab.parent / "committed-gates")},
                    capture_output=True,
                    text=True,
                    timeout=60,
                    check=False,
                )

                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                emitted = json.loads((lab / "evidence" / REPLAY_LABS[name][0][0]).read_text())
                observed = emitted["sub_gates"][1]["observed_values"]
                for raw_name, (anchor_class, expected, source) in anchors.items():
                    with self.subTest(lab=name, raw=raw_name):
                        actual = observed[anchor_class][raw_name]
                        self.assertEqual(actual["timestamp_utc"], expected)
                        self.assertEqual(actual["time_source"], source)

    def test_batch_b_direct_invocation_ignores_local_gate_anchors(self) -> None:
        for name, anchors in self.batch_b_payload_anchors.items():
            with self.subTest(lab=name), self.replay_fixture(name) as lab:
                gate14 = lab / "evidence" / REPLAY_LABS[name][0][0]
                local = json.loads(gate14.read_text())
                observed = local["sub_gates"][1]["observed_values"]
                for anchor_class in ("pre_anchor_timestamps", "post_anchor_timestamps"):
                    for anchor in observed[anchor_class].values():
                        anchor["timestamp_utc"] = "2026-07-30T00:00:00+00:00"
                _ = gate14.write_text(json.dumps(local))

                result = subprocess.run(
                    ["bash", "verify.sh"],
                    cwd=lab,
                    env={key: value for key, value in os.environ.items() if key != "GATE_REPLAY_BASELINE_DIR"},
                    capture_output=True,
                    text=True,
                    timeout=60,
                    check=False,
                )

                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                emitted = json.loads(gate14.read_text())
                observed = emitted["sub_gates"][1]["observed_values"]
                for raw_name, (anchor_class, expected, source) in anchors.items():
                    with self.subTest(lab=name, raw=raw_name):
                        actual = observed[anchor_class][raw_name]
                        self.assertEqual(actual["timestamp_utc"], expected)
                        self.assertEqual(actual["time_source"], source)


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
            EvaluationReplayTests,
        )
    )


if __name__ == "__main__":
    _ = unittest.main()
