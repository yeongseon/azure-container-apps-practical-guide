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
            (evidence / "01-raw.json").write_text(json.dumps({"TimeStamp": "2026-06-01T01:02:03Z"}))
            (evidence / "10-result-gate.json").write_text(json.dumps({"evaluated_at_utc": "2026-11-01T00:00:00Z"}))
            (guide / "demo.md").write_text("---\nvalidation:\n  status: reproduced\n---\n# Demo\n")
            subprocess.run(["git", "init"], cwd=root, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-m", "test fixture"], cwd=root, check=True, capture_output=True)
            commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True).stdout.strip()

            data = inventory.build_inventory(root, commit, dt.date(2026, 11, 10))
            record = data["labs"][0]

            self.assertEqual(record["classification"], "live-azure-evidence")
            self.assertEqual(record["last_azure_run_utc"], "2026-06-01T01:02:03Z")
            self.assertEqual(record["committed_gate_files"][0]["evaluated_at_utc"], "2026-11-01T00:00:00Z")
            self.assertEqual(record["cleanup_evidence"]["completion"], "absent")
            self.assertIn("cleanup script exists", record["discrepancies"][0].lower())


if __name__ == "__main__":
    unittest.main()
