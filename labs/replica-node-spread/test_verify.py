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

# A syntactically valid, NON-TRIVIAL UUID that differs from the anchor's
# boot_id. It must not be the all-zero sentinel: that value additionally
# refutes the non-trivial-UUID check, so a fixture using it could no longer
# isolate a single refuted check.
FOREIGN_BOOT_ID = "9f3c1d52-7ab4-4e61-8c90-2d5e6f7a1b83"
TRIVIAL_BOOT_ID = "00000000-0000-0000-0000-000000000000"

GENERATED_GATES = (COHORT_GATE, MATRIX_GATE, CLAIM_GATE, PACKAGING_GATE)


@contextlib.contextmanager
def fixture_lab():
    """Yield an isolated copy of the lab directory, deleted on exit.

    The committed gate JSONs are removed from the copy. Without that, a
    test could read a gate file that the repository shipped rather than
    one this run actually emitted, and would keep passing even if the
    verifier stopped producing that gate entirely.
    """
    with tempfile.TemporaryDirectory(prefix="rns-fixture-") as tmp:
        destination = pathlib.Path(tmp) / "replica-node-spread"
        shutil.copytree(
            LAB_DIR,
            destination,
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
        )
        for name in GENERATED_GATES:
            (destination / "evidence" / name).unlink()
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
    path = lab / "evidence" / filename
    if not path.is_file():
        raise AssertionError(
            f"{filename} was not emitted by this verify.sh run; "
            "the assertion that follows would otherwise have read a stale file"
        )
    return json.loads(path.read_text())


def emitted_gates(lab: pathlib.Path) -> list[str]:
    return sorted(
        name for name in GENERATED_GATES if (lab / "evidence" / name).is_file()
    )


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


class VerdictAssertionParityTests(unittest.TestCase):
    """The recomputed checks must be the ones the verdict actually asserts.

    falsify.sh emits exactly four claims: H3a-replica-consistent,
    H3a-boot-consistent, H3a-uptime-monotonic and H3b-boot-nontrivial. A
    sub-gate that recomputes a different set cannot establish that the
    verdict is explainable from raw, however sound its predicate algebra
    is: replica consistency and the non-trivial-UUID guard were simply
    never evaluated, so raw could contradict the verdict on either one and
    still pass.
    """

    def _sub(self, lab: pathlib.Path) -> dict:
        run_verify(lab)
        return gate(lab, MATRIX_GATE)["sub_gate_d_verdict_explainable"]

    def test_replica_name_drift_refutes_the_verdict(self):
        with fixture_lab() as lab:
            records = read_anchor(lab)
            records[2] = {**records[2], "replica_name": "app-consumption--0000001-other"}
            write_anchor(lab, records)
            sub = self._sub(lab)

            self.assertIs(sub["check_replica_consistent"], False)
            self.assertIn("check_replica_consistent", sub["refuted_checks"])
            self.assertIs(sub["d_pass"], False)
            self.assertIs(sub["verdict_contradicts_raw"], True)

    def test_trivial_boot_id_refutes_the_verdict(self):
        with fixture_lab() as lab:
            write_anchor(lab, [
                {**record, "boot_id": TRIVIAL_BOOT_ID}
                for record in read_anchor(lab)
            ])
            sub = self._sub(lab)

            self.assertIs(sub["check_boot_nontrivial"], False)
            self.assertIn("check_boot_nontrivial", sub["refuted_checks"])
            self.assertIs(sub["d_pass"], False)

    def test_pristine_cohort_satisfies_every_asserted_check(self):
        with fixture_lab() as lab:
            sub = self._sub(lab)
            for name in ("check_replica_consistent", "check_boot_id_consistent",
                         "check_uptime_monotonic", "check_boot_nontrivial"):
                self.assertIs(sub[name], True, msg=f"{name} should hold on the pristine anchor")
            self.assertEqual(sub["refuted_checks"], [])
            self.assertIs(sub["d_pass"], True)


class VerdictLineConsistencyTests(unittest.TestCase):
    """The verdict's own status lines must agree with the recomputation.

    Reading only `Overall: PASS` accepts an internally contradictory
    artifact: a verdict whose H3a-replica-consistent line reads `no` while
    its Overall line reads PASS is not explainable from anything, yet it
    passed. Each asserted line is now compared against the recomputed value.
    """

    def _sub(self, lab: pathlib.Path) -> dict:
        run_verify(lab)
        return gate(lab, MATRIX_GATE)["sub_gate_d_verdict_explainable"]

    def _set_line(self, lab: pathlib.Path, key: str, value: str) -> None:
        path = lab / "evidence" / ANCHOR_VERDICT
        out = []
        for line in path.read_text().splitlines():
            if line.startswith(key):
                head, _, tail = line.partition(":")
                note = tail.split("(", 1)
                out.append(f"{head}:  {value}  ({note[1]}" if len(note) > 1 else f"{head}:  {value}")
            else:
                out.append(line)
        path.write_text("\n".join(out) + "\n")

    def test_pristine_lines_agree(self):
        with fixture_lab() as lab:
            sub = self._sub(lab)
            self.assertIs(sub["verdict_lines_consistent"], True)
            self.assertEqual(sub["verdict_line_disagreements"], [])
            self.assertIs(sub["d_pass"], True)

    def test_line_says_no_while_overall_says_pass(self):
        with fixture_lab() as lab:
            self._set_line(lab, "H3a-replica-consistent", "no")
            sub = self._sub(lab)

            self.assertTrue(sub["verdict_overall_pass"])
            self.assertIs(sub["verdict_lines_consistent"], False)
            self.assertIn("check_replica_consistent", sub["verdict_line_disagreements"])
            self.assertIs(sub["d_pass"], False)

    def test_missing_verdict_line_is_not_explainable(self):
        with fixture_lab() as lab:
            path = lab / "evidence" / ANCHOR_VERDICT
            path.write_text("\n".join(
                l for l in path.read_text().splitlines()
                if not l.startswith("H3b-boot-nontrivial")) + "\n")
            sub = self._sub(lab)

            self.assertIs(sub["verdict_lines_consistent"], False)
            self.assertIs(sub["d_pass"], False)


class ContradictionScopeTests(unittest.TestCase):
    """Only checks the verdict asserts may set the contradiction flags."""

    def test_additional_requirement_failure_is_not_a_verdict_contradiction(self):
        with fixture_lab() as lab:
            records = read_anchor(lab)
            records[-1] = {**records[-1],
                           "boot_time_estimate_ms": records[0]["boot_time_estimate_ms"] + 90_000}
            write_anchor(lab, records)
            run_verify(lab)
            sub = gate(lab, MATRIX_GATE)["sub_gate_d_verdict_explainable"]

            self.assertIs(sub["additional_bte_stable"], False)
            self.assertIs(sub["additional_requirements_refuted"], True)
            self.assertIs(
                sub["raw_refutes_verdict"], False,
                msg="falsify.sh never asserts bte stability, so its failure is not raw refuting the verdict",
            )
            self.assertIs(sub["verdict_contradicts_raw"], False)
            self.assertIs(sub["d_pass"], False)


class DisagreementAuditTests(unittest.TestCase):
    """Both directions of verdict/raw disagreement must be visible.

    The sub-gate decides pass/fail from raw, but a reviewer also needs to
    see WHICH way the verdict and the raw records diverged. Recording only
    the "verdict claims PASS while raw refutes it" direction leaves a
    verdict that reads FAIL over clean raw completely invisible.
    """

    def _sub(self, lab: pathlib.Path) -> dict:
        run_verify(lab)
        return gate(lab, MATRIX_GATE)["sub_gate_d_verdict_explainable"]

    def test_pristine_records_no_disagreement(self):
        with fixture_lab() as lab:
            sub = self._sub(lab)
            self.assertIs(sub["verdict_contradicts_raw"], False)
            self.assertIs(sub["raw_contradicts_verdict"], False)

    def test_verdict_claims_pass_while_raw_refutes_it(self):
        with fixture_lab() as lab:
            records = read_anchor(lab)
            records[1], records[2] = records[2], records[1]
            write_anchor(lab, records)
            sub = self._sub(lab)

            self.assertTrue(sub["verdict_overall_pass"])
            self.assertIs(sub["verdict_contradicts_raw"], True)
            self.assertIs(sub["raw_contradicts_verdict"], False)
            self.assertIs(sub["d_pass"], False)

    def test_raw_is_clean_while_verdict_does_not_say_pass(self):
        """A FAIL verdict over clean raw is an unexplained disagreement.

        Raw primacy decides what the COHORT supports, so it is right that
        raw governs pass/fail elsewhere. This sub-gate asks a narrower
        question: is the verdict file explainable from the raw records? A
        verdict reading FAIL while every recomputed check passes is not
        explainable, so it does not pass, and the direction is recorded.
        """
        with fixture_lab() as lab:
            path = lab / "evidence" / ANCHOR_VERDICT
            path.write_text(path.read_text().replace("Overall: PASS", "Overall: FAIL"))
            sub = self._sub(lab)

            self.assertFalse(sub["verdict_overall_pass"])
            self.assertEqual(sub["refuted_checks"], [])
            self.assertIs(sub["raw_contradicts_verdict"], True)
            self.assertIs(sub["verdict_contradicts_raw"], False)
            self.assertIs(sub["d_pass"], False)


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
                sub["check_boot_id_consistent"],
                False,
                msg="fixture did not actually refute boot_id consistency",
            )
            self.assertIs(
                sub["check_uptime_monotonic"],
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
                    "additional_bte_stable",
                    "additional_sample_count_sufficient",
                    "check_boot_id_consistent",
                    "check_boot_nontrivial",
                    "check_replica_consistent",
                    "check_uptime_monotonic",
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
            self.assertIs(sub["additional_sample_count_sufficient"], False)
            self.assertIn("check_uptime_monotonic", sub["inconclusive_checks"])
            self.assertIn("additional_bte_stable", sub["inconclusive_checks"])
            self.assertIs(sub["d_pass"], False)
            # A too-short anchor fails a verifier requirement; it does not
            # refute anything falsify.sh asserted.
            self.assertEqual(sub["d_evidence_level"], "Requirements Not Met")


class RequiredEvidenceTests(unittest.TestCase):
    """S4 - a missing required input must hard-fail, never degrade to PASS."""

    def test_missing_canonical_file_aborts_before_emitting_gates(self):
        with fixture_lab() as lab:
            (lab / "evidence" / "consumption-scale-1-run-1.jsonl").unlink()
            proc = run_verify(lab)

            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("not found", proc.stderr)
            self.assertEqual(
                emitted_gates(lab),
                [],
                msg="no gate may be emitted once a required input is missing",
            )

    def test_missing_anchor_verdict_aborts(self):
        with fixture_lab() as lab:
            (lab / "evidence" / ANCHOR_VERDICT).unlink()
            proc = run_verify(lab)

            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("not found", proc.stderr)
            self.assertEqual(emitted_gates(lab), [])


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


class PerFileDamageTests(unittest.TestCase):
    """Corpus-wide ratios alone let one whole file be destroyed.

    Six bad records inside the smallest scale file are under 1% of the
    1117-record corpus, so a purely corpus-wide tolerance passed every
    gate while an entire canonical matrix cell was invalid. An empty file
    is worse still: it contributes no denominator rows, so every
    corpus-wide ratio reads 1.0. Each case below reproduces one such
    cohort and pins the invariant that now rejects it.
    """

    def _scale_file(self, lab: pathlib.Path) -> pathlib.Path:
        return lab / "evidence" / "consumption-scale-1-run-1.jsonl"

    def _rewrite(self, path: pathlib.Path, mutate) -> None:
        records = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
        path.write_text("".join(json.dumps(mutate(r)) + "\n" for r in records))

    def _rewrite_indexes(self, path: pathlib.Path, mutations: dict) -> None:
        records = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
        for index, mutate in mutations.items():
            records[index] = mutate(records[index])
        path.write_text("".join(json.dumps(r) + "\n" for r in records))

    def test_entire_file_of_invalid_json_fails_cohort_integrity(self):
        with fixture_lab() as lab:
            self._scale_file(lab).write_text("NOT JSON AT ALL\n" * 6)
            proc = run_verify(lab)
            sub = gate(lab, COHORT_GATE)["sub_gate_b_files_parseable"]

            self.assertIn("consumption-scale-1-run-1.jsonl", sub["per_file_parse_violations"])
            self.assertFalse(sub["b_pass"])
            self.assertNotEqual(proc.returncode, 0)

    def test_entire_file_of_foreign_run_ids_fails_cohort_isolation(self):
        with fixture_lab() as lab:
            self._rewrite(
                self._scale_file(lab),
                lambda r: {**r, "run_id": "consumption-n1-r1-20991231-000000"},
            )
            proc = run_verify(lab)
            sub = gate(lab, COHORT_GATE)["sub_gate_c_same_bundle"]

            self.assertIn("consumption-scale-1-run-1.jsonl", sub["per_file_date_prefix_violations"])
            self.assertFalse(sub["c_pass"])
            self.assertNotEqual(proc.returncode, 0)

    def test_entire_file_in_wrong_matrix_cell_fails_coherence(self):
        with fixture_lab() as lab:
            self._rewrite(
                self._scale_file(lab),
                lambda r: {**r, "profile": "Dedicated-D8", "scale_target": 999},
            )
            proc = run_verify(lab)
            sub = gate(lab, MATRIX_GATE)["sub_gate_a_each_file_one_cell"]

            self.assertIn("consumption-scale-1-run-1.jsonl", sub["per_file_cell_violations"])
            self.assertFalse(sub["a_pass"])
            self.assertNotEqual(proc.returncode, 0)

    def test_surplus_summary_entry_fails_reconciliation(self):
        with fixture_lab() as lab:
            path = lab / "evidence" / "analysis-summary.json"
            entries = json.loads(path.read_text())
            entries.append(dict(entries[0]))
            path.write_text(json.dumps(entries, indent=2))

            proc = run_verify(lab)
            sub = gate(lab, MATRIX_GATE)["sub_gate_c_summary_reconciles"]

            self.assertTrue(sub["summary_file_keys_not_unique_or_missing"])
            self.assertFalse(sub["summary_entry_count_matches"])
            self.assertFalse(sub["c_pass"])
            self.assertNotEqual(proc.returncode, 0)

    def test_single_truncated_line_stays_within_declared_tolerance(self):
        with fixture_lab() as lab:
            path = self._scale_file(lab)
            path.write_text(path.read_text() + "{ truncated partial line\n")

            proc = run_verify(lab)
            sub = gate(lab, COHORT_GATE)["sub_gate_b_files_parseable"]

            self.assertEqual(sub["per_file_parse_violations"], [])
            self.assertTrue(sub["b_pass"])
            self.assertEqual(proc.returncode, 0)

    def test_empty_scale_file_cannot_ride_the_strong_path(self):
        """An empty file makes every corpus-wide ratio read 1.0.

        With no denominator rows it satisfies the Strong predicate
        trivially, so the per-file invariant has to sit outside the
        Strong/Fallback choice rather than inside the Fallback.
        """
        with fixture_lab() as lab:
            self._scale_file(lab).write_text("")
            proc = run_verify(lab)

            cohort = gate(lab, COHORT_GATE)
            parse = cohort["sub_gate_b_files_parseable"]
            self.assertEqual(parse["parse_success_ratio"], 1.0)
            self.assertTrue(parse["b_strong_path_all_lines_parse"])
            self.assertIn("consumption-scale-1-run-1.jsonl", parse["per_file_parse_violations"])
            self.assertFalse(parse["b_pass"])
            self.assertFalse(cohort["gate_1_cohort_integrity_all_subgates_pass"])
            self.assertNotEqual(proc.returncode, 0)

    def test_blank_only_scale_file_cannot_ride_the_strong_path(self):
        with fixture_lab() as lab:
            self._scale_file(lab).write_text("\n\n\n")
            proc = run_verify(lab)

            parse = gate(lab, COHORT_GATE)["sub_gate_b_files_parseable"]
            self.assertIn("consumption-scale-1-run-1.jsonl", parse["per_file_parse_violations"])
            self.assertFalse(parse["b_pass"])
            self.assertNotEqual(proc.returncode, 0)

    def test_cell_mismatch_cap_is_absolute_not_proportional(self):
        """Twelve strays in a 240-record file must not outrank one in six.

        The documented fallback admits "one straggling record", which is
        a count. A proportional floor would reject a single bad record in
        the 6-record scale-1 file while accepting twelve in the
        240-record scale-30 file.
        """
        with fixture_lab() as lab:
            path = lab / "evidence" / "consumption-scale-30-run-1.jsonl"
            records = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
            self.assertGreater(len(records), 200)
            for index in range(12):
                records[index] = {**records[index], "profile": "Dedicated-D8"}
            path.write_text("".join(json.dumps(r) + "\n" for r in records))

            proc = run_verify(lab)
            sub = gate(lab, MATRIX_GATE)["sub_gate_a_each_file_one_cell"]

            self.assertGreaterEqual(sub["cell_match_ratio"], 0.95)
            self.assertIn("consumption-scale-30-run-1.jsonl", sub["per_file_cell_violations"])
            self.assertFalse(sub["a_pass"])
            self.assertNotEqual(proc.returncode, 0)

    def test_one_straggling_record_in_a_small_file_is_tolerated(self):
        with fixture_lab() as lab:
            self._rewrite_indexes(
                self._scale_file(lab), {0: lambda r: {**r, "profile": "Dedicated-D8"}}
            )
            proc = run_verify(lab)
            sub = gate(lab, MATRIX_GATE)["sub_gate_a_each_file_one_cell"]

            self.assertEqual(sub["per_file_cell_violations"], [])
            self.assertTrue(sub["a_pass"])
            self.assertEqual(proc.returncode, 0)

    def test_two_straggling_records_exceed_the_cap(self):
        with fixture_lab() as lab:
            self._rewrite_indexes(
                self._scale_file(lab),
                {
                    0: lambda r: {**r, "profile": "Dedicated-D8"},
                    1: lambda r: {**r, "profile": "Dedicated-D8"},
                },
            )
            proc = run_verify(lab)
            sub = gate(lab, MATRIX_GATE)["sub_gate_a_each_file_one_cell"]

            self.assertIn("consumption-scale-1-run-1.jsonl", sub["per_file_cell_violations"])
            self.assertFalse(sub["a_pass"])
            self.assertNotEqual(proc.returncode, 0)


class VerdictSubGateTruthTableTests(unittest.TestCase):
    """Each H3 check must be independently able to fail the sub-gate."""

    def _sub(self, lab: pathlib.Path, expected_returncode: int) -> dict:
        proc = run_verify(lab)
        self.assertEqual(
            proc.returncode,
            expected_returncode,
            msg=f"unexpected verify.sh exit.\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}",
        )
        return gate(lab, MATRIX_GATE)["sub_gate_d_verdict_explainable"]

    def test_only_boot_id_refuted(self):
        with fixture_lab() as lab:
            records = read_anchor(lab)
            records[-1] = {**records[-1], "boot_id": FOREIGN_BOOT_ID}
            write_anchor(lab, records)
            sub = self._sub(lab, expected_returncode=1)

            self.assertEqual(sub["refuted_checks"], ["check_boot_id_consistent"])
            self.assertIs(sub["check_uptime_monotonic"], True)
            self.assertIs(sub["d_pass"], False)

    def test_only_uptime_refuted(self):
        with fixture_lab() as lab:
            records = read_anchor(lab)
            records[1], records[2] = records[2], records[1]
            write_anchor(lab, records)
            sub = self._sub(lab, expected_returncode=1)

            self.assertEqual(sub["refuted_checks"], ["check_uptime_monotonic"])
            self.assertIs(sub["check_boot_id_consistent"], True)
            self.assertIs(sub["d_pass"], False)

    def test_only_bte_span_refuted(self):
        with fixture_lab() as lab:
            records = read_anchor(lab)
            records[-1] = {
                **records[-1],
                "boot_time_estimate_ms": records[0]["boot_time_estimate_ms"] + 90_000,
            }
            write_anchor(lab, records)
            sub = self._sub(lab, expected_returncode=1)

            self.assertEqual(sub["refuted_checks"], ["additional_bte_stable"])
            self.assertIs(sub["d_pass"], False)

    def test_missing_bte_values_are_inconclusive_not_refuted(self):
        with fixture_lab() as lab:
            write_anchor(
                lab,
                [
                    {k: v for k, v in record.items() if k != "boot_time_estimate_ms"}
                    for record in read_anchor(lab)
                ],
            )
            sub = self._sub(lab, expected_returncode=0)

            self.assertEqual(sub["refuted_checks"], [])
            self.assertEqual(sub["inconclusive_checks"], ["additional_bte_stable"])
            self.assertIs(sub["d_pass"], True)
            self.assertEqual(sub["d_evidence_level"], "Inconclusive")

    def test_verdict_not_pass_fails_even_with_clean_raw(self):
        with fixture_lab() as lab:
            path = lab / "evidence" / ANCHOR_VERDICT
            path.write_text(path.read_text().replace("Overall: PASS", "Overall: FAIL"))
            sub = self._sub(lab, expected_returncode=1)

            self.assertFalse(sub["verdict_overall_pass"])
            self.assertEqual(sub["refuted_checks"], [])
            self.assertIs(sub["d_pass"], False)
            self.assertEqual(sub["d_evidence_level"], "Not Proven")


if __name__ == "__main__":
    unittest.main(verbosity=2)
