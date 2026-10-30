"""Exercise the CI replay runner against an isolated, committed fixture."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("check_gate_replay.py")


class ReplayRunnerTests(unittest.TestCase):
    def test_replay_rejects_stale_missing_invalid_and_changed_outputs(self) -> None:
        for case in ("noop", "valid", "invalid", "changed", "boolean-as-count", "old-stamp", "bad-committed-stamp"):
            with self.subTest(case=case), tempfile.TemporaryDirectory(prefix="gate-replay-") as tmp:
                root = Path(tmp)
                lab = root / "labs" / "fixture"
                evidence = lab / "evidence"
                evidence.mkdir(parents=True)
                stamp = "bad" if case == "bad-committed-stamp" else "2000-01-01T00:00:00Z"
                gate = evidence / "gate.json"
                gate.write_text(json.dumps({"evaluated_at_utc": stamp, "pass": True}))
                raw = evidence / "raw.txt"
                raw.write_text("unchanged raw fixture\n")
                verifier = "exit 0\n"
                if case != "noop":
                    payload = '{"evaluated_at_utc": "' + '$(date -u +%Y-%m-%dT%H:%M:%SZ)' + '", "pass": true}'
                    if case == "invalid":
                        payload = "not-json"
                    if case == "changed":
                        payload = payload.replace("true", "false")
                    if case == "boolean-as-count":
                        payload = payload.replace("true", "1")
                    if case == "old-stamp":
                        payload = payload.replace("$(date -u +%Y-%m-%dT%H:%M:%SZ)", stamp)
                    verifier = "test \"$1\" = --offline\ncat > \"$(dirname \"$0\")/evidence/gate.json\" <<EOF\n" + payload + "\nEOF\n"
                (lab / "verify.sh").write_text(verifier)
                for command in (
                    ["git", "init", "--quiet"],
                    ["git", "add", "."],
                    ["git", "-c", "user.name=Replay fixture", "-c", "user.email=fixture@example.com",
                     "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "test: fixture"],
                ):
                    subprocess.run(command, cwd=root, check=True, capture_output=True)

                result = subprocess.run(
                    [sys.executable, str(SCRIPT), "fixture", "gate.json", "--verify-arg=--offline"],
                    cwd=root, capture_output=True, text=True, check=False,
                )

                self.assertEqual(result.returncode == 0, case == "valid", result.stdout + result.stderr)
                self.assertEqual(raw.read_text(), "unchanged raw fixture\n")
                if case == "noop":
                    self.assertFalse(gate.exists())


if __name__ == "__main__":
    unittest.main()
