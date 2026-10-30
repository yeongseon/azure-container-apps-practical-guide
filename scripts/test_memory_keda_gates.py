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
    def test_unusable_section_is_rejected_before_gate_emission(self) -> None:
        for case in ("header-only", "truncated", "empty-section", "error-only", "duplicate",
                     "relocated", "malformed-row", "quoted", "suffixed", "indented",
                     "no-table-header", "no-separator", "no-rows", "no-table-name"):
            with self.subTest(case=case), fixture_lab(MEMORY_LAB) as lab:
                path = lab / "evidence/ca-oom-healthy/report-20260620T042246Z.txt"
                original = path.read_text()
                prefix, rest = original.split(MEMORY_SECTION, 1)
                body, suffix = rest.split("=== 6.", 1)
                variants = {
                    "header-only": MEMORY_SECTION + "\n",
                    "truncated": prefix + MEMORY_SECTION,
                    "empty-section": prefix + MEMORY_SECTION + "\n=== 6." + suffix,
                    "error-only": prefix + MEMORY_SECTION + "\nERROR: collection failed\n=== 6." + suffix,
                    "duplicate": prefix + MEMORY_SECTION + "\n" + MEMORY_SECTION + body + "=== 6." + suffix,
                    "relocated": prefix + "=== 6." + suffix + "\n=== 7. Appended ===\n" + MEMORY_SECTION + body + "=== 6." + suffix,
                    "malformed-row": prefix + MEMORY_SECTION + "\n".join(body.splitlines()[:5] + ["truncated row"] + body.splitlines()[5:]) + "\n=== 6." + suffix,
                    "quoted": original.replace(MEMORY_SECTION, "> " + MEMORY_SECTION),
                    "suffixed": original.replace(MEMORY_SECTION, MEMORY_SECTION + " extra"),
                    "indented": original.replace(MEMORY_SECTION, "  " + MEMORY_SECTION),
                    "no-table-header": re.sub(r"^Log_s.*Reason_s.*\n", "", original, flags=re.MULTILINE),
                    "no-separator": re.sub(r"^-+  -+  -+  -+\n", "", original, flags=re.MULTILINE),
                    "no-rows": prefix + MEMORY_SECTION + "\n" + "\n".join(body.splitlines()[1:4]) + "\n=== 6." + suffix,
                    "no-table-name": original.replace("PrimaryResult", ""),
                }
                _ = path.write_text(variants[case])

                result = run_verify(lab)

                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("ERROR:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)
                self.assertFalse(any((lab / "evidence" / name).exists() for name in GATE_OUTPUTS[MEMORY_LAB]))
                self.assertNotIn("Phase 10", result.stdout)

    def test_unreadable_or_undecodable_report_has_concise_error(self) -> None:
        for case in ("invalid-utf8", "unreadable"):
            with self.subTest(case=case), fixture_lab(MEMORY_LAB) as lab:
                path = lab / "evidence/ca-oom-healthy/report-20260620T042246Z.txt"
                if case == "invalid-utf8":
                    _ = path.write_bytes(b"\xff")
                else:
                    path.chmod(0)
                try:
                    result = run_verify(lab)
                finally:
                    path.chmod(0o644)

                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("ERROR:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)
                self.assertFalse(any((lab / "evidence" / name).exists() for name in GATE_OUTPUTS[MEMORY_LAB]))

    def test_normalized_report_layout_passes(self) -> None:
        for case in ("crlf", "trailing-spaces", "bom"):
            with self.subTest(case=case), fixture_lab(MEMORY_LAB) as lab:
                path = lab / "evidence/ca-oom-healthy/report-20260620T042246Z.txt"
                text = path.read_text()
                variants = {"crlf": text.replace("\n", "\r\n"),
                            "trailing-spaces": "\n".join(line + "  " for line in text.split("\n")),
                            "bom": "\ufeff" + text}
                _ = path.write_bytes(variants[case].encode())

                result = run_verify(lab)

                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_incomplete_failure_scenario_report_is_rejected(self) -> None:
        for app, stamp in (("hard", "20260620T060257Z"), ("leak", "20260620T042200Z")):
            with self.subTest(app=app), fixture_lab(MEMORY_LAB) as lab:
                path = lab / f"evidence/ca-oom-{app}/report-{stamp}.txt"
                _ = path.write_text(MEMORY_SECTION + "\n")

                result = run_verify(lab)

                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertFalse(any((lab / "evidence" / name).exists() for name in GATE_OUTPUTS[MEMORY_LAB]))

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
    def test_only_declared_event_times_can_establish_overlap(self) -> None:
        for section_number, needle in ((5, SIGNAL), (9, "Probe of StartUp failed")):
            for case in ("message-time", "extra-column", "missing-table-name", "invalid-month"):
                with self.subTest(section=section_number, case=case), fixture_lab(KEDA_LAB) as lab:
                    path = next((lab / "evidence/ca-nometrics-slow").glob("report-*.txt"))
                    prefix, rest = path.read_text().split(f"=== {section_number}.", 1)
                    body, suffix = rest.split(f"=== {section_number + 1}.", 1)
                    rows = []
                    for line in body.splitlines():
                        if needle in line:
                            line = TIMESTAMP.sub("2026-06-20T00:00:00Z", line)
                            if case == "message-time":
                                line = line.replace(needle, needle + " (reference 2026-06-20T00:37:40Z)")
                            elif case == "extra-column":
                                line += "  2026-06-20T00:37:40Z"
                            elif case == "missing-table-name":
                                line = line.replace("PrimaryResult", "")
                            else:
                                line = line.replace("2026-06-20T00:00:00Z", "2026-13-20T00:00:00Z")
                        rows.append(line)
                    _ = path.write_text(prefix + f"=== {section_number}." + "\n".join(rows) + f"\n=== {section_number + 1}." + suffix)

                    result = run_verify(lab)

                    data = json.loads((lab / "evidence" / GATE_OUTPUTS[KEDA_LAB][0]).read_text())
                    sub = data["sub_gate_b_not_ready_correlated"]
                    self.assertIs(sub["b_pass"], False)
                    self.assertNotEqual(sub["b_correlation_evidence_level"], "Correlated")
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertNotIn("Traceback", result.stderr)
                    if case != "message-time":
                        self.assertEqual(sub["b_correlation_evidence_level"], "Not Proven")
                        self.assertIn("ERROR:", result.stderr)

    def test_shared_endpoint_is_inclusive(self) -> None:
        with fixture_lab(KEDA_LAB) as lab:
            path = next((lab / "evidence/ca-nometrics-slow").glob("report-*.txt"))
            prefix, rest = path.read_text().split("=== 5. System logs: metric errors ===", 1)
            body, suffix = rest.split("=== 6.", 1)
            body = "\n".join(TIMESTAMP.sub("2026-06-20T00:37:22.0675678Z", line)
                             if SIGNAL in line else line for line in body.splitlines())
            _ = path.write_text(prefix + "=== 5. System logs: metric errors ===" + body + "\n=== 6." + suffix)

            result = run_verify(lab)

            data = json.loads((lab / "evidence" / GATE_OUTPUTS[KEDA_LAB][0]).read_text())
            self.assertIs(data["sub_gate_b_not_ready_correlated"]["b_pass"], True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_committed_scenarios_reproduce_gates(self) -> None:
        with fixture_lab(KEDA_LAB) as lab:
            expected = {name: json.loads((lab / "evidence" / name).read_text()) for name in GATE_OUTPUTS[KEDA_LAB]}

            result = run_verify(lab)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for name, committed in expected.items():
                actual = json.loads((lab / "evidence" / name).read_text())
                _ = committed.pop("evaluated_at_utc")
                _ = actual.pop("evaluated_at_utc")
                self.assertEqual(actual, committed, name)

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
