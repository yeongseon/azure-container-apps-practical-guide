"""Exercise report completeness and signal-scoped correlation on evidence copies."""

from __future__ import annotations

import json
import re
import unittest
from typing import Final

from test_lab_gates import GATE_OUTPUTS, fixture_lab, run_verify

MEMORY_LAB: Final = "memory-leak-oomkilled"
KEDA_LAB: Final = "keda-no-metrics-returned"
MEMORY_SECTION: Final = (
    "=== 5. System logs: exit code 137 / OOM / ProcessExited / ContainerTerminated ==="
)
SIGNAL: Final = "no metrics returned from resource metrics API"
TIMESTAMP: Final = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z")


class MemoryReportTests(unittest.TestCase):
    def test_incomplete_healthy_report_fails(self) -> None:
        for case in ("missing", "empty", "headerless"):
            with self.subTest(case=case), fixture_lab(MEMORY_LAB) as lab:
                path = lab / "evidence/ca-oom-healthy/report-20260620T042246Z.txt"
                if case == "missing":
                    path.unlink()
                else:
                    text = "" if case == "empty" else path.read_text().replace(MEMORY_SECTION, "")
                    _ = path.write_text(text)

                result = run_verify(lab)

                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                for name in GATE_OUTPUTS[MEMORY_LAB]:
                    self.assertFalse((lab / "evidence" / name).exists(), name)

    def test_committed_healthy_report_passes(self) -> None:
        with fixture_lab(MEMORY_LAB) as lab:
            result = run_verify(lab)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for name in GATE_OUTPUTS[MEMORY_LAB]:
                data = json.loads((lab / "evidence" / name).read_text())
                verdicts = [value for key, value in data.items() if key.endswith("all_subgates_pass")]
                self.assertEqual(verdicts, [True], name)


class KedaSignalWindowTests(unittest.TestCase):
    def test_unrelated_timestamp_cannot_correlate_disjoint_signal_rows(self) -> None:
        with fixture_lab(KEDA_LAB) as lab:
            path = next((lab / "evidence/ca-nometrics-slow").glob("report-*.txt"))
            prefix, rest = path.read_text().split("=== 5. System logs: metric errors ===", 1)
            section, suffix = rest.split("=== 6.", 1)
            signal_rows = [line for line in section.splitlines() if SIGNAL in line]
            self.assertTrue(signal_rows)
            section = "\n".join(
                TIMESTAMP.sub("2026-06-20T00:00:00Z", line) if SIGNAL in line else line
                for line in section.splitlines()
            )
            section += "\nUnrelated lifecycle note  PrimaryResult  2026-06-20T00:37:40Z\n\n"
            _ = path.write_text(prefix + "=== 5. System logs: metric errors ===" + section + "=== 6." + suffix)

            result = run_verify(lab)

            data = json.loads((lab / "evidence" / GATE_OUTPUTS[KEDA_LAB][0]).read_text())
            sub = data["sub_gate_b_not_ready_correlated"]
            self.assertIs(sub["windows_comparable"], True)
            self.assertIs(sub["windows_overlap_strong_path"], False)
            self.assertEqual(sub["window_timestamps"]["s5_last"], "2026-06-20T00:00:00Z")
            self.assertEqual(sub["b_correlation_evidence_level"], "Refuted")
            self.assertIs(sub["b_pass"], False)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    _ = unittest.main()
