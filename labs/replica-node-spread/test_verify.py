#!/usr/bin/env python3
"""Offline regression tests for ``labs/replica-node-spread/verify.sh``.

These tests use SYNTHETIC fixtures only. They are never Azure execution
evidence and they never mutate the committed canonical cohort: every test
copies the whole lab directory into an isolated temporary directory,
mutates the COPY, runs the COPIED ``verify.sh``, and asserts on the gate
JSON that copy emits.

Why a whole-directory copy is required: ``verify.sh`` computes
``EVIDENCE_DIR`` from ``dirname "${BASH_SOURCE[0]}"`` unconditionally, so
exporting ``EVIDENCE_DIR`` from the caller cannot redirect it, and the
script writes its four gate JSONs back into that same directory. Running
it in place would overwrite preserved evidence.

Run:
    python3 labs/replica-node-spread/test_verify.py
"""

from __future__ import annotations

import contextlib
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest

LAB_DIR = pathlib.Path(__file__).resolve().parent
ANCHOR_JSONL = "h3-20260614-143432.jsonl"
ANCHOR_VERDICT = "h3-20260614-143432.verdict.txt"
COHORT_GATE = "10-cohort-integrity-gate.json"
MATRIX_GATE = "11-matrix-coherence-gate.json"
CLAIM_GATE = "12-claim-eligibility-gate.json"
PACKAGING_GATE = "13-packaging-gate.json"

# A syntactically valid UUID that is not the anchor's boot_id, used to
# introduce a second kernel context and thereby refute "boot_id consistent".
FOREIGN_BOOT_ID = "00000000-0000-0000-0000-000000000000"


@contextlib.contextmanager
def fixture_lab():
    """Yield an isolated copy of the lab directory, deleted on exit."""
    with tempfile.TemporaryDirectory(prefix="rns-fixture-") as tmp:
        destination = pathlib.Path(tmp) / "replica-node-spread"
        shutil.copytree(
            LAB_DIR,
            destination,
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
        )
        yield destination


def run_verify(lab: pathlib.Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(lab / "verify.sh")],
        capture_output=True,
        text=True,
        timeout=600,
        check=False,
    )


def gate(lab: pathlib.Path, filename: str) -> dict:
    return json.loads((lab / "evidence" / filename).read_text())


def read_anchor(lab: pathlib.Path) -> list[dict]:
    raw = (lab / "evidence" / ANCHOR_JSONL).read_text()
    return [json.loads(line) for line in raw.splitlines() if line.strip()]


def write_anchor(lab: pathlib.Path, records: list[dict]) -> None:
    payload = "".join(json.dumps(record) + "\n" for record in records)
    (lab / "evidence" / ANCHOR_JSONL).write_text(payload)


def verdict_says_pass(lab: pathlib.Path) -> bool:
    text = (lab / "evidence" / ANCHOR_VERDICT).read_text()
    return any(line.strip() == "Overall: PASS" for line in text.splitlines())


class PristineCohortTests(unittest.TestCase):
    """S1 - the committed cohort must still verify cleanly."""

    def test_pristine_cohort_passes_all_four_gates(self):
        with fixture_lab() as lab:
            proc = run_verify(lab)
            self.assertEqual(
                proc.returncode,
                0,
                msg=f"pristine cohort should exit 0.\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}",
            )
            self.assertTrue(gate(lab, COHORT_GATE)["gate_1_cohort_integrity_all_subgates_pass"])
            self.assertTrue(gate(lab, MATRIX_GATE)["gate_2_matrix_coherence_all_subgates_pass"])
            self.assertTrue(gate(lab, CLAIM_GATE)["gate_3_claim_eligibility_all_subgates_pass"])
            self.assertTrue(gate(lab, PACKAGING_GATE)["gate_4_packaging_all_subgates_pass"])

    def test_pristine_verdict_subgate_is_fully_recomputed(self):
        with fixture_lab() as lab:
            run_verify(lab)
            sub = gate(lab, MATRIX_GATE)["sub_gate_d_verdict_explainable"]
            self.assertTrue(sub["d_pass"])
            self.assertTrue(sub["verdict_overall_pass"])
            self.assertTrue(sub["all_four_checks_recomputable"])


class RawPrimacyTests(unittest.TestCase):
    """S2 - a verdict file must never overrule contradictory raw records.

    verify.sh's own header states the rule it has to obey:
      line 34 "if analysis-summary or the H3 verdict conflicts with raw
               JSONL, raw JSONL wins."
      line 38 "Do not let the H3 verdict overrule contradictory raw files."
    """

    def test_contradictory_raw_is_not_rescued_by_verdict_overall_pass(self):
        with fixture_lab() as lab:
            records = read_anchor(lab)
            # Refute "uptime monotonic": swap two adjacent samples so the
            # sequence decreases in the middle.
            records[1], records[2] = records[2], records[1]
            # Refute "boot_id consistent": plant a second kernel context.
            records[-1] = {**records[-1], "boot_id": FOREIGN_BOOT_ID}
            write_anchor(lab, records)

            # The verdict text is deliberately left untouched: it still
            # asserts "Overall: PASS" while the raw records now refute it.
            self.assertTrue(verdict_says_pass(lab))

            run_verify(lab)
            sub = gate(lab, MATRIX_GATE)["sub_gate_d_verdict_explainable"]

            self.assertIs(
                sub["check_2_boot_id_consistent"],
                False,
                msg="fixture did not actually refute boot_id consistency",
            )
            self.assertIs(
                sub["check_3_uptime_monotonic"],
                False,
                msg="fixture did not actually refute uptime monotonicity",
            )
            self.assertIs(
                sub["d_pass"],
                False,
                msg=(
                    "REGRESSION: sub-gate d passed while raw records refute the "
                    "verdict. A verdict.txt line 'Overall: PASS' must not "
                    "overrule contradictory raw JSONL (verify.sh header lines "
                    "34 and 38)."
                ),
            )
            self.assertEqual(sub["d_evidence_level"], "Refuted")

    def test_contradictory_raw_fails_gate_2_and_the_script_exit_code(self):
        with fixture_lab() as lab:
            records = read_anchor(lab)
            records[1], records[2] = records[2], records[1]
            records[-1] = {**records[-1], "boot_id": FOREIGN_BOOT_ID}
            write_anchor(lab, records)

            proc = run_verify(lab)
            self.assertFalse(
                gate(lab, MATRIX_GATE)["gate_2_matrix_coherence_all_subgates_pass"],
                msg="gate 2 must fail when its verdict sub-gate is refuted",
            )
            self.assertNotEqual(
                proc.returncode,
                0,
                msg=f"verify.sh must exit non-zero when a gate fails.\nstdout:\n{proc.stdout}",
            )


class InconclusiveEvidenceTests(unittest.TestCase):
    """S3 - uncontradicted-but-unrecomputable evidence is kept, downgraded.

    The governing rule is that a fallback may not launder a contradiction
    into a PASS. It does NOT say every fallback must be deleted: evidence
    that is merely too thin to recompute stays admissible, but has to be
    reported at a lower evidence level so a reviewer can see the claim
    rests on the verdict file.
    """

    def test_empty_anchor_is_inconclusive_not_refuted(self):
        with fixture_lab() as lab:
            write_anchor(lab, [])
            self.assertTrue(verdict_says_pass(lab))

            run_verify(lab)
            sub = gate(lab, MATRIX_GATE)["sub_gate_d_verdict_explainable"]

            self.assertEqual(sub["refuted_checks"], [])
            self.assertEqual(
                sorted(sub["inconclusive_checks"]),
                [
                    "check_1_n_samples_ge_4",
                    "check_2_boot_id_consistent",
                    "check_3_uptime_monotonic",
                    "check_4_bte_stable",
                ],
            )
            self.assertFalse(sub["all_four_checks_recomputable"])
            self.assertIs(sub["d_pass"], True)
            self.assertEqual(sub["d_evidence_level"], "Inconclusive")

    def test_empty_anchor_still_fails_cohort_integrity_and_exit_code(self):
        with fixture_lab() as lab:
            write_anchor(lab, [])
            proc = run_verify(lab)

            self.assertFalse(
                gate(lab, COHORT_GATE)["sub_gate_a_anchor_exists"]["a_pass"],
                msg="an unreadable anchor must still fail cohort integrity",
            )
            self.assertNotEqual(proc.returncode, 0)

    def test_single_sample_anchor_does_not_claim_observed(self):
        with fixture_lab() as lab:
            write_anchor(lab, read_anchor(lab)[:1])
            run_verify(lab)
            sub = gate(lab, MATRIX_GATE)["sub_gate_d_verdict_explainable"]

            # One sample cannot establish monotonicity or a bte span, and
            # it refutes "samples >= 4" outright.
            self.assertIs(sub["check_1_n_samples_ge_4"], False)
            self.assertIn("check_3_uptime_monotonic", sub["inconclusive_checks"])
            self.assertIn("check_4_bte_stable", sub["inconclusive_checks"])
            self.assertIs(sub["d_pass"], False)
            self.assertEqual(sub["d_evidence_level"], "Refuted")


class RequiredEvidenceTests(unittest.TestCase):
    """S4 - a missing required input must hard-fail, never degrade to PASS."""

    def test_missing_canonical_file_aborts_before_emitting_gates(self):
        with fixture_lab() as lab:
            (lab / "evidence" / "consumption-scale-1-run-1.jsonl").unlink()
            proc = run_verify(lab)

            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("not found", proc.stderr)

    def test_missing_anchor_verdict_aborts(self):
        with fixture_lab() as lab:
            (lab / "evidence" / ANCHOR_VERDICT).unlink()
            proc = run_verify(lab)

            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("not found", proc.stderr)


class CohortIsolationTests(unittest.TestCase):
    """S5 - records from another capture window must not be admitted."""

    def _contaminate(self, lab: pathlib.Path, filename: str, count: int) -> None:
        path = lab / "evidence" / filename
        records = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
        for index in range(min(count, len(records))):
            records[index] = {**records[index], "run_id": "consumption-n1-r1-20991231-000000"}
        path.write_text("".join(json.dumps(r) + "\n" for r in records))

    def test_bulk_foreign_run_ids_fail_cohort_isolation(self):
        with fixture_lab() as lab:
            self._contaminate(lab, "consumption-scale-30-run-1.jsonl", 10_000)
            proc = run_verify(lab)
            sub = gate(lab, COHORT_GATE)["sub_gate_c_same_bundle"]

            self.assertLess(sub["date_prefix_ratio"], 1.0)
            self.assertFalse(
                sub["c_pass"],
                msg="records from a foreign capture window must fail same_bundle",
            )
            self.assertNotEqual(proc.returncode, 0)

    def test_declared_stray_record_tolerance_is_pinned(self):
        """Characterization test for the declared 99% fallback tolerance.

        The cohort-isolation fallback deliberately admits up to 1% stray
        records. That tolerance is a published threshold, not an accident,
        so it is pinned here rather than silently tightened. If anyone
        changes DATE_PREFIX_MIN_FALLBACK this test must be updated in the
        same commit.
        """
        with fixture_lab() as lab:
            self._contaminate(lab, "consumption-scale-1-run-1.jsonl", 1)
            run_verify(lab)
            gate_json = gate(lab, COHORT_GATE)
            sub = gate_json["sub_gate_c_same_bundle"]

            self.assertLess(sub["date_prefix_ratio"], 1.0)
            self.assertFalse(sub["c_strong_path_all_records_dated"])
            self.assertTrue(sub["c_fallback_path_most_records_dated"])
            self.assertEqual(
                gate_json["thresholds"]["date_prefix_min_fallback"], 0.99
            )


class AdjacentSurfaceRegressionTests(unittest.TestCase):
    """S6 - the fix must not perturb any other gate on the pristine cohort."""

    def test_untouched_subgates_keep_their_verdicts(self):
        with fixture_lab() as lab:
            run_verify(lab)

            cohort = gate(lab, COHORT_GATE)
            self.assertEqual(
                cohort["gate_1_cohort_integrity_sub_gates"],
                {
                    "a_anchor_exists": True,
                    "b_files_parseable": True,
                    "c_same_bundle": True,
                    "d_no_extras": True,
                },
            )
            self.assertEqual(cohort["sub_gate_b_files_parseable"]["parse_success_ratio"], 1.0)
            self.assertEqual(cohort["sub_gate_c_same_bundle"]["date_prefix_ratio"], 1.0)

            matrix = gate(lab, MATRIX_GATE)
            self.assertEqual(matrix["sub_gate_a_each_file_one_cell"]["cell_match_ratio"], 1.0)
            self.assertEqual(matrix["sub_gate_b_no_duplicates"]["duplicate_count"], 0)
            self.assertEqual(matrix["sub_gate_c_summary_reconciles"]["matches_count"], 11)

            self.assertTrue(gate(lab, CLAIM_GATE)["gate_3_claim_eligibility_all_subgates_pass"])
            self.assertTrue(gate(lab, PACKAGING_GATE)["gate_4_packaging_all_subgates_pass"])

    def test_claim_ceiling_is_still_strongly_suggested(self):
        with fixture_lab() as lab:
            run_verify(lab)
            claim = gate(lab, CLAIM_GATE)
            self.assertNotEqual(
                claim["claim_level"],
                "Observed",
                msg="node-placement claims must stay below [Observed]",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
