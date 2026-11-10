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

    def test_inventory_separates_raw_capture_gate_evaluation_and_cleanup_proof(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            evidence = root / "labs/demo/evidence"
            guide = root / "docs/troubleshooting/lab-guides"
            evidence.mkdir(parents=True)
            guide.mkdir(parents=True)
            (root / "labs/demo/trigger.sh").write_text("#!/bin/bash\n")
            (root / "labs/demo/verify.sh").write_text("#!/bin/bash\n")
            (root / "labs/demo/cleanup.sh").write_text("#!/bin/bash\n")
            (root / "labs/demo/README.md").write_text("# Demo\n")
            (evidence / "README.md").write_text("# Evidence\n")
            (evidence / "01-raw.json").write_text(json.dumps({"captured_at_utc": "2026-06-01T01:02:03Z"}))
            (evidence / "10-result-gate.json").write_text(json.dumps({"evaluated_at_utc": "2026-11-01T00:00:00Z"}))
            (guide / "demo.md").write_text("---\nvalidation:\n  status: reproduced\n---\n# Demo\n")
            commit = self.commit_fixture(root)

            data = inventory.build_inventory(root, commit, dt.date(2026, 11, 10))
            record = data["labs"][0]

            self.assertEqual(record["classification"], "live-azure-evidence")
            self.assertEqual(record["last_azure_run_utc"], "2026-06-01T01:02:03Z")
            self.assertEqual(record["last_azure_run_anchor_kinds"], ["explicit-field:captured_at_utc"])
            self.assertEqual(record["committed_gate_files"][0]["evaluated_at_utc"], "2026-11-01T00:00:00Z")
            self.assertEqual(record["cleanup_evidence"]["completion"], "absent")
            self.assertIn("cleanup script exists", record["discrepancies"][0].lower())

    def test_claim_rows_include_live_run_quotes_from_guide_and_evidence_readme(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            guide = root / "docs/troubleshooting/lab-guides"
            evidence = root / "labs/appgw-to-internal-aca-nsg-mismatch/evidence"
            guide.mkdir(parents=True)
            evidence.mkdir(parents=True)
            (root / "labs/appgw-to-internal-aca-nsg-mismatch/README.md").write_text("# Lab\n")
            (guide / "appgw-to-internal-aca-nsg-mismatch.md").write_text(
                "# Guide\nNo claim.\nThe evidence pack was captured on the re-executed live run.\n"
            )
            (evidence / "README.md").write_text(
                "# Evidence\n\n## Committed evidence pack (2026-07-04 re-executed live run)\n"
            )
            commit = self.commit_fixture(root)
            tracked = set(inventory.tracked_files(root, commit))

            self.assertEqual(inventory.claim_rows(root, commit, "appgw-to-internal-aca-nsg-mismatch", tracked), [
                {
                    "file": "docs/troubleshooting/lab-guides/appgw-to-internal-aca-nsg-mismatch.md",
                    "line": 3,
                    "quote": "The evidence pack was captured on the re-executed live run.",
                },
                {
                    "file": "labs/appgw-to-internal-aca-nsg-mismatch/evidence/README.md",
                    "line": 3,
                    "quote": "## Committed evidence pack (2026-07-04 re-executed live run)",
                },
            ])

    def test_status_pattern_rejects_live_azure_command_explanations(self) -> None:
        for prose in (
            "Captures APP_NAME from the live Azure lookup so later commands reuse it.",
            "The verifier makes no live Azure calls.",
            "Run the live Azure query to inspect current revisions.",
        ):
            with self.subTest(prose=prose):
                self.assertIsNone(inventory.STATUS_RE.search(prose))

    def test_status_pattern_accepts_historical_live_azure_collection_claims(self) -> None:
        for claim in (
            "The historical `verify.sh` from the 2026-06-20 capture also performed the live-Azure data collection (the queries that populate the report).",
            "The historical verifier also performed the live Azure data collection before the refactor.",
        ):
            with self.subTest(claim=claim):
                self.assertIsNotNone(inventory.STATUS_RE.search(claim))

    def test_status_pattern_accepts_repository_execution_claims(self) -> None:
        for claim in (
            "status: reproduced",
            "Phase A — Live-Azure reproduction.",
            "### Observed Evidence (Live Azure Test — 2026-06-06)",
            "The cohort was captured in a single live-Azure window.",
            "This subsection validates the lab against a live Azure environment.",
            "The historical verifier executed nine live Azure checks against the deployment.",
            "The evidence pack was captured on the re-executed live run.",
            "Live-executed on 2026-07-04.",
            "The full lab was executed end-to-end against a live Azure subscription.",
            "[Observed] On the 2026-07-04 re-executed live run all gates passed.",
        ):
            with self.subTest(claim=claim):
                self.assertIsNotNone(inventory.STATUS_RE.search(claim))

    def test_markdown_claim_quote_caps_long_rows_without_changing_json_quote(self) -> None:
        quote = "[Observed] " + "x" * 400 + " | [verified]"
        rendered = inventory.markdown_claim_quote(quote)

        unescaped_brackets = rendered.replace("&#91;", "[").replace("&#93;", "]")
        self.assertLessEqual(len(unescaped_brackets), inventory.MARKDOWN_QUOTE_LIMIT)
        self.assertTrue(rendered.endswith("…"))
        self.assertIn("&#91;Observed&#93;", rendered)
        self.assertNotIn(" | ", rendered)
        self.assertEqual(quote, "[Observed] " + "x" * 400 + " | [verified]")

    def test_markdown_claim_cell_bounds_many_claims_and_points_to_json(self) -> None:
        claims = [
            {"file": f"docs/troubleshooting/lab-guides/example-{index}.md", "line": index, "quote": "x" * 400}
            for index in range(11)
        ]

        rendered = inventory.markdown_claim_cell(claims)

        self.assertLessEqual(len(rendered), inventory.MARKDOWN_CLAIM_CELL_LIMIT)
        self.assertIn("more in JSON", rendered)
        self.assertLessEqual(rendered.count("` — "), inventory.MARKDOWN_CLAIM_COUNT_LIMIT)

        page = inventory.render_page({
            "inventory_as_of": "2026-11-10",
            "source_commit_sha": "a" * 40,
            "historical_reconciliation": {
                "historical_count": 1, "current_count": 1,
                "added": [], "removed": [], "rename_note": "None.",
            },
            "summary": {"classifications": {"unknown": 1}},
            "labs": [{
                "lab_path": "labs/example", "classification": "unknown",
                "last_azure_run_utc": "unknown", "status_claimed_in_docs": claims,
                "raw_evidence": [], "committed_gate_files": [],
                "cleanup_evidence": {"completion": "absent"}, "discrepancies": [],
            }],
            "follow_up_batches": [],
        })
        matrix_row = next(line for line in page.splitlines() if line.startswith("| `labs/example`"))
        claim_cell = matrix_row.split(" | ")[3]
        self.assertLessEqual(len(claim_cell), inventory.MARKDOWN_CLAIM_CELL_LIMIT)

    def test_symbolic_source_revision_is_pinned_and_check_uses_recorded_tree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "labs/demo").mkdir(parents=True)
            (root / "docs/reference").mkdir(parents=True)
            (root / "docs/troubleshooting/lab-guides").mkdir(parents=True)
            (root / "labs/demo/README.md").write_text("# Demo\n")
            commit = self.commit_fixture(root)
            branch = subprocess.run(
                ["git", "branch", "--show-current"], cwd=root, check=True,
                capture_output=True, text=True,
            ).stdout.strip()

            for revision in ("HEAD", branch):
                with self.subTest(revision=revision):
                    self.assertEqual(
                        inventory.build_inventory(root, revision, dt.date(2026, 11, 10))["source_commit_sha"],
                        commit,
                    )

            self.assertEqual(inventory.run([
                "--write", "--source-commit", "HEAD", "--as-of", "2026-11-10",
            ], root=root), 0)
            saved = json.loads((root / "docs/reference/lab-reproduction-inventory.json").read_text())
            self.assertRegex(saved["source_commit_sha"], r"^[0-9a-f]{40}$")
            self.assertEqual(saved["source_commit_sha"], commit)

            (root / "labs/demo/README.md").write_text("# Uncommitted mutation\n")
            self.assertEqual(inventory.run(["--check"], root=root), 0)

    def test_appgw_live_run_claims_preserve_repository_file_lines_and_quotes(self) -> None:
        commit = inventory.current_head(inventory.ROOT)
        tracked = set(inventory.tracked_files(inventory.ROOT, commit))
        rows = inventory.claim_rows(
            inventory.ROOT, commit, "appgw-to-internal-aca-nsg-mismatch", tracked
        )
        selected = {(row["file"], row["line"], row["quote"]) for row in rows}
        selected_locations = {(row["file"], row["line"]) for row in rows}
        expected_locations = {
            ("docs/troubleshooting/lab-guides/appgw-to-internal-aca-nsg-mismatch.md", line)
            for line in (50, 52, 53, 161, 186)
        } | {
            ("labs/appgw-to-internal-aca-nsg-mismatch/evidence/README.md", line)
            for line in (32, 34, 36)
        }
        self.assertTrue(expected_locations <= selected_locations)
        self.assertIn((
            "docs/troubleshooting/lab-guides/appgw-to-internal-aca-nsg-mismatch.md",
            50,
            "- `evidence/` carries the committed `2026-07-04` evidence pack captured on the re-executed live run in Korea Central; see [`labs/appgw-to-internal-aca-nsg-mismatch/evidence/README.md`](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/labs/appgw-to-internal-aca-nsg-mismatch/evidence/README.md) for the per-file provenance and PII sanitization notes. Every artifact can also be regenerated on demand by re-running `trigger.sh` and `fix.sh` against a fresh deployment.",
        ), selected)
        self.assertIn((
            "labs/appgw-to-internal-aca-nsg-mismatch/evidence/README.md",
            32,
            "## Committed evidence pack (2026-07-04 re-executed live run)",
        ), selected)
        self.assertIn((
            "labs/appgw-to-internal-aca-nsg-mismatch/evidence/README.md",
            36,
            "The `2026-07-04` re-executed run yielded `verify-result.json` with all seven gates `true`, `verdict = HYPOTHESIS_CONFIRMED`, `falsification = FIX_VERIFIED`, and `verify.sh` exit `0`. The lab guide's `## 4) Experiment Log` cites each committed file above by name.",
        ), selected)

    def test_historical_collectors_remain_status_claims_in_repository_inventory(self) -> None:
        commit = inventory.current_head(inventory.ROOT)
        tracked = set(inventory.tracked_files(inventory.ROOT, commit))

        for lab, line in (("keda-no-metrics-returned", 132), ("memory-leak-oomkilled", 151)):
            with self.subTest(lab=lab):
                locations = {
                    (row["file"], row["line"])
                    for row in inventory.claim_rows(inventory.ROOT, commit, lab, tracked)
                }
                self.assertIn((f"labs/{lab}/evidence/README.md", line), locations)

    def test_only_explicit_capture_anchors_can_set_last_azure_run(self) -> None:
        negative = json.dumps({
            "createdTime": "2026-06-01T01:00:00Z",
            "query_window": {"start": "2026-06-01T02:00:00Z", "end": "2026-06-01T03:00:00Z"},
            "TimeGenerated": "2026-06-01T04:00:00Z",
        }).encode()
        self.assertEqual(inventory.capture_anchors("labs/demo/evidence/events.json", negative), [])
        anchors = inventory.capture_anchors(
            "labs/demo/evidence/capture-manifest.json",
            json.dumps({"captured_at_utc": "2026-06-01T05:00:00Z", "TimeGenerated": "2026-06-01T06:00:00Z"}).encode(),
        )
        self.assertEqual(anchors, [{
            "timestamp_utc": "2026-06-01T05:00:00Z",
            "anchor_kind": "explicit-field:captured_at_utc",
            "location": "$.captured_at_utc",
        }])

    def test_every_discrepancy_is_assigned_once_to_a_bounded_batch(self) -> None:
        records = [
            {"lab_path": "labs/demo-a", "discrepancy_types": ["missing-teardown-proof", "missing-anchor"]},
            {"lab_path": "labs/demo-b", "discrepancy_types": ["missing-teardown-proof"]},
        ]
        batches = inventory.discrepancy_batches(records)
        assignments = [(batch["discrepancy_type"], lab) for batch in batches for lab in batch["labs"]]
        self.assertCountEqual(assignments, [
            ("missing-teardown-proof", "demo-a"),
            ("missing-anchor", "demo-a"),
            ("missing-teardown-proof", "demo-b"),
        ])
        self.assertTrue(all(batch["size"] == len(batch["labs"]) <= 8 for batch in batches))


if __name__ == "__main__":
    unittest.main()
