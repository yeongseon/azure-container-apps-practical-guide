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


if __name__ == "__main__":
    unittest.main(verbosity=2)
