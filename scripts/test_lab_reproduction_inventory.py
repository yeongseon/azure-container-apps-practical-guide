#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("lab_reproduction_inventory.py")
SPEC = importlib.util.spec_from_file_location("lab_reproduction_inventory", SCRIPT)
assert SPEC and SPEC.loader
inventory = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inventory)


class LabReproductionInventoryTests(unittest.TestCase):
    def commit_fixture(self, root: Path) -> str:
        subprocess.run(["git", "init"], cwd=root, check=True, capture_output=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        subprocess.run(["git", "commit", "-m", "test fixture"], cwd=root, check=True, capture_output=True)
        return subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True).stdout.strip()

    def make_fixture(self, root: Path, lab: str = "demo") -> None:
        evidence = root / f"labs/{lab}/evidence"
        evidence.mkdir(parents=True)
        (root / "docs/reference").mkdir(parents=True)
        (root / "docs/troubleshooting/lab-guides").mkdir(parents=True)
        readme = root / f"labs/{lab}/README.md"
        readme.write_text("# Demo\nStatus: captured live on 2026-01-02.\nCleanup was not recorded.\nThe raw output records the capture.\n")
        (root / f"labs/{lab}/verify.sh").write_text("#!/bin/bash\n")
        (evidence / "raw.json").write_text(json.dumps({"captured_at_utc": "2026-01-02T03:04:05Z"}))
        curated = {
            "schema_version": 1,
            "labs": [{
                "lab": lab,
                "status_claims": [{"file": f"labs/{lab}/README.md", "line": 2, "quote": "captured live"}],
                "execution_anchor": {"file": f"labs/{lab}/evidence/raw.json", "field_or_line": "$.captured_at_utc", "utc": "2026-01-02T03:04:05Z", "kind": "captured_at"},
                "derived_outputs": [],
                "raw_outputs": [{"file": f"labs/{lab}/evidence/raw.json", "justification": {"file": f"labs/{lab}/README.md", "line": 4, "quote": "raw output"}}],
                "cleanup": {"state": "absent", "evidence": {"file": f"labs/{lab}/README.md", "line": 3, "quote": "not recorded"}},
                "classification": "live-azure-evidence",
                "evidence_basis": "The cited raw capture records the execution anchor.",
                "discrepancies": [],
            }],
        }
        (root / inventory.CURATED_PATH.relative_to(inventory.ROOT)).write_text(json.dumps(curated))

    def test_citation_verification_rejects_stale_line_and_missing_quote(self) -> None:
        for mutation in ("line", "quote"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.make_fixture(root)
                path = root / inventory.CURATED_PATH.relative_to(inventory.ROOT)
                curated = json.loads(path.read_text())
                curated["labs"][0]["status_claims"][0][mutation] = 99 if mutation == "line" else "missing"
                path.write_text(json.dumps(curated))
                commit = self.commit_fixture(root)
                with self.assertRaises(inventory.InventoryError):
                    inventory.build_inventory(root, commit, dt.date(2026, 11, 10))

    def test_citation_verification_rejects_missing_and_extra_lab(self) -> None:
        for mutation in ("missing", "extra"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.make_fixture(root)
                path = root / inventory.CURATED_PATH.relative_to(inventory.ROOT)
                curated = json.loads(path.read_text())
                if mutation == "missing":
                    curated["labs"] = []
                else:
                    extra = dict(curated["labs"][0])
                    extra["lab"] = "extra"
                    curated["labs"].append(extra)
                path.write_text(json.dumps(curated))
                commit = self.commit_fixture(root)
                with self.assertRaises(inventory.InventoryError):
                    inventory.build_inventory(root, commit, dt.date(2026, 11, 10))

    def test_anchor_must_appear_in_cited_field(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_fixture(root)
            path = root / inventory.CURATED_PATH.relative_to(inventory.ROOT)
            curated = json.loads(path.read_text())
            curated["labs"][0]["execution_anchor"]["utc"] = "2026-01-02T03:04:06Z"
            path.write_text(json.dumps(curated))
            commit = self.commit_fixture(root)
            with self.assertRaisesRegex(inventory.InventoryError, "anchor UTC"):
                inventory.build_inventory(root, commit, dt.date(2026, 11, 10))

    def test_duplicate_citation_location_is_rejected_even_with_different_quote(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_fixture(root)
            path = root / inventory.CURATED_PATH.relative_to(inventory.ROOT)
            curated = json.loads(path.read_text())
            curated["labs"][0]["status_claims"].append({
                "file": "labs/demo/README.md", "line": 2, "quote": "live on 2026-01-02"
            })
            path.write_text(json.dumps(curated))
            commit = self.commit_fixture(root)
            with self.assertRaisesRegex(inventory.InventoryError, "duplicated citation"):
                inventory.build_inventory(root, commit, dt.date(2026, 11, 10))

    def test_duplicate_citation_location_is_rejected_across_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_fixture(root)
            path = root / inventory.CURATED_PATH.relative_to(inventory.ROOT)
            curated = json.loads(path.read_text())
            curated["labs"][0]["cleanup"]["evidence"] = {
                "file": "labs/demo/README.md", "line": 4, "quote": "raw output"
            }
            path.write_text(json.dumps(curated))
            commit = self.commit_fixture(root)
            with self.assertRaisesRegex(inventory.InventoryError, "duplicated citation"):
                inventory.build_inventory(root, commit, dt.date(2026, 11, 10))

    def test_grouped_output_justification_and_missing_output_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_fixture(root)
            evidence = root / "labs/demo/evidence"
            (evidence / "second.json").write_text("{}\n")
            path = root / inventory.CURATED_PATH.relative_to(inventory.ROOT)
            curated = json.loads(path.read_text())
            curated["labs"][0]["raw_outputs"] = [{
                "files": ["labs/demo/evidence/raw.json", "labs/demo/evidence/second.json"],
                "justification": {"file": "labs/demo/README.md", "line": 4, "quote": "raw output"},
            }]
            path.write_text(json.dumps(curated))
            commit = self.commit_fixture(root)
            data = inventory.build_inventory(root, commit, dt.date(2026, 11, 10))
            self.assertEqual(len(data["labs"][0]["raw_outputs"]), 2)

            curated["labs"][0]["raw_outputs"][0]["files"].append("labs/demo/evidence/missing.json")
            path.write_text(json.dumps(curated))
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-m", "missing output mutation"], cwd=root, check=True, capture_output=True)
            with self.assertRaisesRegex(inventory.InventoryError, "missing lab file"):
                inventory.build_inventory(root, "HEAD", dt.date(2026, 11, 10))

    def test_status_claim_hygiene_rejects_procedures_and_accepts_results(self) -> None:
        rejected = {
            "### Observed Evidence": "heading",
            "Record the UTC timestamp.": "imperative instruction",
            "Run the verifier.": "imperative instruction",
            "Confirm that the revision is healthy.": "imperative instruction",
            "Expected output: revision should be Healthy.": "expectation without a recorded result",
            "The gates were re-evaluated offline from the same raw files.": "gate or workflow mechanics",
            "The Gate 12 speedup-ratio threshold is intentionally lower than observed.": "gate or workflow mechanics",
            "The Gate 13 ratio threshold is intentionally lower than observed.": "gate or workflow mechanics",
            "The Gate 12 fallback path is intentionally false as defensive design.": "gate or workflow mechanics",
            "This historical snapshot is explicitly non-gating.": "gate or workflow mechanics",
            "All az invocations pin --subscription explicitly to avoid drift.": "gate or workflow mechanics",
        }
        for quote, problem in rejected.items():
            with self.subTest(quote=quote):
                self.assertEqual(inventory.status_claim_problem(quote), problem)
        accepted = [
            "The live run reproduced the failure.",
            "The query returned the expected three rows.",
            "The captured result should be treated as one cohort; the run completed successfully.",
        ]
        for quote in accepted:
            with self.subTest(quote=quote):
                self.assertIsNone(inventory.status_claim_problem(quote))

    def test_status_claim_hygiene_rejects_reviewed_source_quotes(self) -> None:
        fixtures = [
            ("docs/troubleshooting/lab-guides/image-size-startup-delay.md", 212),
            ("docs/troubleshooting/lab-guides/keda-no-metrics-returned.md", 303),
            ("docs/troubleshooting/lab-guides/memory-leak-oomkilled.md", 297),
            ("labs/probe-and-port-mismatch/evidence/README.md", 19),
            ("labs/revision-failover/README.md", 59),
        ]
        for relative, line in fixtures:
            with self.subTest(relative=relative, line=line):
                quote = (inventory.ROOT / relative).read_text().splitlines()[line - 1]
                self.assertEqual(inventory.status_claim_problem(quote), "gate or workflow mechanics")

    def test_full_sha_serialization_determinism_and_scratch_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_fixture(root)
            commit = self.commit_fixture(root)
            first = inventory.build_inventory(root, "HEAD", dt.date(2026, 11, 10))
            second = inventory.build_inventory(root, "HEAD", dt.date(2026, 11, 10))
            self.assertEqual(inventory.encoded(first), inventory.encoded(second))
            self.assertEqual(first["source_commit_sha"], commit)
            self.assertRegex(first["source_commit_sha"], r"^[0-9a-f]{40}$")
            self.assertEqual(inventory.run(["--write", "--source-commit", "HEAD", "--as-of", "2026-11-10"], root=root), 0)
            (root / "labs/demo/README.md").write_text("# scratch mutation\n")
            self.assertEqual(inventory.run(["--check"], root=root), 0)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-m", "later unrelated"], cwd=root, check=True, capture_output=True)
            self.assertEqual(inventory.run(["--check"], root=root), 0)

    def test_markdown_claim_cell_is_capped_and_points_to_json(self) -> None:
        claims = [{"file": f"docs/example-{index}.md", "line": index + 1, "quote": "x" * 400} for index in range(11)]
        rendered = inventory.markdown_claim_cell(claims)
        self.assertLessEqual(len(rendered), inventory.MARKDOWN_CLAIM_CELL_LIMIT)
        self.assertIn("more in JSON", rendered)

    def test_repository_ground_truth(self) -> None:
        data = inventory.build_inventory(inventory.ROOT, inventory.current_head(inventory.ROOT), dt.date(2026, 11, 10))
        labs = {Path(row["lab_path"]).name: row for row in data["labs"]}
        self.assertEqual((len(labs["acr-pull-failure"]["raw_outputs"]), len(labs["acr-pull-failure"]["derived_outputs"])), (22, 6))
        self.assertIn("labs/appgw-to-internal-aca-nsg-mismatch/evidence/verify-result.json", labs["appgw-to-internal-aca-nsg-mismatch"]["derived_outputs"])
        expected_anchors = {
            "acr-pull-failure": "2026-06-22T13:28:23Z",
            "cd-reconnect-rbac-conflict": "2026-06-23T12:32:56.311469Z",
            "cpu-throttling": "2026-06-22T08:51:13Z",
            "image-size-startup-delay": "2026-06-22T02:28:03.376224Z",
            "keda-no-metrics-returned": "2026-06-20T00:50:51Z",
            "memory-leak-oomkilled": "2026-06-20T06:02:57Z",
            "memory-percentage-vs-keda-utilization": "2026-06-24T02:31:25Z",
            "replica-node-spread": "2026-06-14T14:52:07Z",
            "revision-provisioning-failure": "2026-06-20T14:26:09Z",
            "revision-history-limit": "2026-06-22T08:16:46Z",
            "scale-rule-mismatch": "2026-06-22T15:15:39Z",
            "startup-degraded-transient-failure": "2026-06-20T22:51:43Z",
            "appinsights-connection-string-missing": "2026-06-22T05:09:45Z",
            "managed-identity-key-vault-failure": "2026-06-26T08:26:59Z",
        }
        for lab, timestamp in expected_anchors.items():
            self.assertEqual(labs[lab]["last_azure_run_utc"], timestamp)
        for row in labs.values():
            for claim in row["status_claims"]:
                self.assertIsNone(inventory.status_claim_problem(claim["quote"]))
        self.assertEqual(labs["zone-redundancy-best-effort"]["last_azure_run_utc"], "unknown")
        self.assertIn("expiresAt deadline", labs["zone-redundancy-best-effort"]["discrepancies"][0]["detail"])
        appgw_locations = {(row["file"], row["line"]) for row in labs["appgw-to-internal-aca-nsg-mismatch"]["status_claims"]}
        self.assertTrue({("docs/troubleshooting/lab-guides/appgw-to-internal-aca-nsg-mismatch.md", line) for line in (50, 52, 53, 161, 186)} <= appgw_locations)
        self.assertTrue({("labs/appgw-to-internal-aca-nsg-mismatch/evidence/README.md", line) for line in (34, 36)} <= appgw_locations)
        for lab in ("cd-reconnect-rbac-conflict", "probe-and-port-mismatch", "revision-failover", "scale-rule-mismatch"):
            self.assertEqual(labs[lab]["cleanup"]["state"], "initiated-not-confirmed")

    def test_each_cleanup_gap_has_one_follow_up_batch(self) -> None:
        data = inventory.build_inventory(inventory.ROOT, inventory.current_head(inventory.ROOT), dt.date(2026, 11, 10))
        assignments = [(batch["discrepancy_type"], batch["labs"][0]) for batch in data["follow_up_batches"]]
        for row in data["labs"]:
            state = row["cleanup"]["state"]
            if state in {"absent", "initiated-not-confirmed"}:
                lab = Path(row["lab_path"]).name
                self.assertEqual(assignments.count((f"cleanup-{state}", lab)), 1)


if __name__ == "__main__":
    unittest.main()
