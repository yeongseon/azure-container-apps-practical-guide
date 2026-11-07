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
    def assert_replay_rejects_tampered_raw(self, replacement: str) -> None:
        with tempfile.TemporaryDirectory(prefix="gate-replay-tamper-") as tmp:
            root = Path(tmp)
            lab = root / "labs" / "fixture"
            evidence = lab / "evidence"
            evidence.mkdir(parents=True)
            gate = evidence / "gate.json"
            gate.write_text(json.dumps({"evaluated_at_utc": "2000-01-01T00:00:00Z", "anchor": "2026-06-29T00:00:00Z"}))
            raw = evidence / "raw.json"
            raw.write_text(json.dumps({"anchor": "2026-06-29T00:00:00Z"}))
            (lab / "verify.sh").write_text(
                "#!/usr/bin/env bash\n"
                "set -eu\n"
                "anchor=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[\"anchor\"])' \"$(dirname \"$0\")/evidence/raw.json\")\n"
                "if [ -n \"${GATE_REPLAY_BASELINE_DIR:-}\" ]; then\n"
                "  anchor=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[\"anchor\"])' \"$GATE_REPLAY_BASELINE_DIR/gate.json\")\n"
                "fi\n"
                "printf '{\"evaluated_at_utc\": \"%s\", \"anchor\": \"%s\"}\\n' \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" \"$anchor\" > \"$(dirname \"$0\")/evidence/gate.json\"\n"
            )
            for command in (
                ["git", "init", "--quiet"],
                ["git", "add", "."],
                ["git", "-c", "user.name=Replay fixture", "-c", "user.email=fixture@example.com",
                 "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "test: fixture"],
            ):
                subprocess.run(command, cwd=root, check=True, capture_output=True)
            raw.write_text(replacement)

            result = subprocess.run(
                [sys.executable, str(SCRIPT), "fixture", "gate.json"],
                cwd=root, capture_output=True, text=True, check=False,
            )

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_replay_rejects_changed_embedded_raw_timestamp_when_baseline_exists(self) -> None:
        self.assert_replay_rejects_tampered_raw(json.dumps({"anchor": "2026-07-06T00:00:00Z"}))

    def test_replay_rejects_replaced_raw_file_when_baseline_exists(self) -> None:
        self.assert_replay_rejects_tampered_raw(json.dumps({"anchor": "1999-12-31T23:59:59Z", "replacement": True}))

    def test_replay_rejects_stale_missing_invalid_and_changed_outputs(self) -> None:
        for case in (
            "noop", "valid", "invalid", "changed", "boolean-as-count", "old-stamp",
            "bad-committed-stamp", "legacy-capture-key", "reordered-keys",
        ):
            with self.subTest(case=case), tempfile.TemporaryDirectory(prefix="gate-replay-") as tmp:
                root = Path(tmp)
                lab = root / "labs" / "fixture"
                evidence = lab / "evidence"
                evidence.mkdir(parents=True)
                stamp = "bad" if case == "bad-committed-stamp" else "2000-01-01T00:00:00Z"
                gate = evidence / "gate.json"
                document = {"evaluated_at_utc": stamp, "pass": True, "count": 1}
                if case == "legacy-capture-key":
                    document["utc_captured"] = stamp
                gate.write_text(json.dumps(document))
                raw = evidence / "raw.txt"
                raw.write_text("unchanged raw fixture\n")
                verifier = "exit 0\n"
                if case != "noop":
                    payload = '{"evaluated_at_utc": "' + '$(date -u +%Y-%m-%dT%H:%M:%SZ)' + '", "pass": true, "count": 1}'
                    if case == "invalid":
                        payload = "not-json"
                    if case == "changed":
                        payload = payload.replace("true", "false")
                    if case == "boolean-as-count":
                        payload = payload.replace("true", "1")
                    if case == "old-stamp":
                        payload = payload.replace("$(date -u +%Y-%m-%dT%H:%M:%SZ)", stamp)
                    if case == "legacy-capture-key":
                        payload = payload[:-1] + ', "utc_captured": "' + stamp + '"}'
                    if case == "reordered-keys":
                        payload = payload.replace('"pass": true, "count": 1', '"count": 1, "pass": true')
                    verifier = "test \"$1\" = --offline || exit 1\ncat > \"$(dirname \"$0\")/evidence/gate.json\" <<EOF\n" + payload + "\nEOF\n"
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

                self.assertEqual(result.returncode == 0, case in ("valid", "reordered-keys"), result.stdout + result.stderr)
                self.assertEqual(raw.read_text(), "unchanged raw fixture\n")
                if case == "noop":
                    self.assertFalse(gate.exists())


if __name__ == "__main__":
    unittest.main()
