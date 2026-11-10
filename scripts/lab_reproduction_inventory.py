#!/usr/bin/env python3
from __future__ import annotations

import argparse
import collections
import datetime as dt
import email.utils
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "docs/reference/lab-reproduction-inventory.json"
PAGE_PATH = ROOT / "docs/reference/lab-reproduction-inventory.md"

HISTORICAL_LABS = {
    "aca-secret-kv-ref-mi-network-path", "aca-secret-kv-ref-mi-network-path-h4b",
    "aca-secret-kv-ref-mi-network-path-h4c", "aca-secret-kv-ref-mi-network-path-h4d",
    "aca-secret-kv-ref-mi-network-path-h4e", "aca-secret-kv-ref-mi-network-path-h4f",
    "aca-secret-kv-ref-mi-network-path-h4g", "acr-network-path-dns-forwarder-bypass",
    "acr-network-path-firewall-allowlist", "acr-network-path-pe-direct",
    "acr-network-path-pe-forced-inspection", "acr-network-path-record-split-brain",
    "acr-pull-failure", "appgw-to-internal-aca-nsg-mismatch",
    "appinsights-connection-string-missing", "cd-reconnect-rbac-conflict",
    "cpu-throttling", "dapr-integration", "diagnostic-settings-missing",
    "image-size-startup-delay", "ingress-target-port-mismatch",
    "keda-no-metrics-returned", "managed-identity-key-vault-failure",
    "memory-leak-oomkilled", "memory-percentage-vs-keda-utilization",
    "metrics-load-test", "observability-tracing", "probe-and-port-mismatch",
    "replica-node-spread", "revision-failover", "revision-history-limit",
    "revision-provisioning-failure", "scale-rule-mismatch",
    "startup-degraded-transient-failure", "traffic-routing-canary",
    "zone-redundancy-best-effort",
}
POLICY_BLOCKED = {name for name in HISTORICAL_LABS if name.startswith("aca-secret-kv-ref-mi-network-path")}
POLICY_BLOCKED.add("managed-identity-key-vault-failure")
EXPENSIVE = {
    "aca-secret-kv-ref-mi-network-path-h4d", "acr-network-path-dns-forwarder-bypass",
    "acr-network-path-firewall-allowlist", "acr-network-path-pe-direct",
    "acr-network-path-pe-forced-inspection", "acr-network-path-record-split-brain",
}

ISO_RE = re.compile(r"\b20\d\d-\d\d-\d\d[T ][0-2]\d:[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)?\b")
FILENAME_TS_RE = re.compile(r"(?<!\d)(20\d{6})[T_-]?(\d{6})Z?(?!\d)")
STATUS_RE = re.compile(
    r"(?:status:\s*(?:verified|reproduced(?:_partial)?|pending_review|blocked)"
    r"|reproduced (?:live|in|on|against)"
    r"|live[- ]azure (?:capture|cohort|deployment|environment|evidence|experiment|reproduction|run|test|window)"
    r"|live (?:azure )?run|live-executed"
    r"|(?:captured|executed|ran|validated)[^.\n]{0,120}live[- ]azure"
    r"|historical[^\n]{0,160}performed the live[- ]azure data collection"
    r"|historical[^\n]{0,160}(?:owned|executed|ran)[^\n]{0,80}live[- ]azure (?:checks|health checks|data collection)"
    r"|(?:historical|pre-Phase-B)[^\n]{0,160}(?:live[- ]azure|live Azure)[^\n]{0,80}(?:capture|checks|health-check|output|script)"
    r"|re-executed(?: live)? run|executed end-to-end against a live Azure subscription"
    r"|committed evidence pack captured"
    r"|live reproduction was executed"
    r"|live Azure experiment captured"
    r"|reproduction ran end-to-end"
    r"|wall-clock for the live[- ]Azure portion)",
    re.I,
)
MARKDOWN_QUOTE_LIMIT = 240
MARKDOWN_CLAIM_COUNT_LIMIT = 3
MARKDOWN_CLAIM_CELL_LIMIT = 600
CAPTURE_KEYS = {
    "captured_at_utc", "captured_before_utc", "captured_after_utc", "utc_captured",
}
OBSERVATION_KEYS = {
    "observation_time_utc", "observation_utc", "observed_at_utc", "observed_time_utc",
}
RUN_LOG_RE = re.compile(r"^00-(?:trigger|verify)-run\.txt$")
DECLARED_CAPTURE_FILE_RE = re.compile(
    r"(?:report|summary|revisions|health-snapshot|capture)[-_].*20\d{6}[T_-]?\d{6}Z?",
    re.I,
)
EMAIL_RE = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
GUID_RE = re.compile(r"(?<![0-9a-f])[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}(?![0-9a-f])", re.I)
IPV4_RE = re.compile(r"(?<!\d)(?:10|192\.168|172\.(?:1[6-9]|2\d|3[01]))(?:\.\d{1,3}){2}(?!\d)")


class InventoryError(Exception):
    pass


def resolve_revision(root: Path, revision: str) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "--verify", f"{revision}^{{commit}}"],
        cwd=root, capture_output=True, text=True,
    )
    commit = result.stdout.strip()
    if result.returncode or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise InventoryError(f"source commit does not exist: {revision}")
    return commit


def git_snapshot(root: Path, commit: str) -> None:
    result = subprocess.run(["git", "merge-base", "--is-ancestor", commit, "HEAD"], cwd=root)
    if result.returncode:
        raise InventoryError(f"source commit is not an ancestor of HEAD: {commit}")


def tracked_files(root: Path, commit: str) -> list[str]:
    git_snapshot(root, commit)
    result = subprocess.run(
        ["git", "ls-tree", "-r", "--name-only", "-z", commit, "--", "labs", "docs/troubleshooting/lab-guides"],
        cwd=root, check=True, capture_output=True,
    )
    return sorted(path for path in result.stdout.decode().split("\0") if path)


def snapshot_bytes(root: Path, commit: str, path: str) -> bytes:
    return subprocess.run(
        ["git", "show", f"{commit}:{path}"], cwd=root, check=True, capture_output=True
    ).stdout


def safe_quote(text: str) -> str:
    text = IPV4_RE.sub("<private-ip>", GUID_RE.sub("<identifier>", EMAIL_RE.sub("<email>", text.strip())))
    return text


def normalized_timestamp(value: str) -> str | None:
    candidate = value.replace(" ", "T")
    if candidate.endswith("Z"):
        candidate = candidate[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(candidate)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def normalized_http_date(value: str) -> str | None:
    if not value.lower().startswith("date:"):
        return None
    try:
        parsed = email.utils.parsedate_to_datetime(value.split(":", 1)[1].strip())
    except (TypeError, ValueError):
        return None
    if parsed is None:
        return None
    return parsed.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def _json_capture_anchors(value: Any, location: str = "$") -> list[dict[str, str]]:
    anchors: list[dict[str, str]] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_location = f"{location}.{key}"
            if key.lower() in CAPTURE_KEYS and isinstance(child, str):
                timestamp = normalized_timestamp(child)
                if timestamp:
                    anchors.append({"timestamp_utc": timestamp, "anchor_kind": f"explicit-field:{key}", "location": child_location})
            if key.lower() in OBSERVATION_KEYS and isinstance(child, str):
                timestamp = normalized_timestamp(child)
                if timestamp:
                    anchors.append({"timestamp_utc": timestamp, "anchor_kind": f"observation-field:{key}", "location": child_location})
            anchors.extend(_json_capture_anchors(child, child_location))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            child_location = f"{location}[{index}]"
            if isinstance(child, str) and (timestamp := normalized_http_date(child)):
                anchors.append({"timestamp_utc": timestamp, "anchor_kind": "http-date-header", "location": child_location})
            anchors.extend(_json_capture_anchors(child, child_location))
    return anchors


def capture_anchors(path: str, content: bytes) -> list[dict[str, str]]:
    anchors: list[dict[str, str]] = []
    text = content.decode("utf-8", errors="ignore")
    if path.endswith(".json"):
        try:
            anchors.extend(_json_capture_anchors(json.loads(text)))
        except json.JSONDecodeError:
            pass
    name = Path(path).name
    if RUN_LOG_RE.fullmatch(name):
        first_line = text.splitlines()[0] if text.splitlines() else ""
        match = ISO_RE.search(first_line)
        if match and (value := normalized_timestamp(match.group(0))):
            anchors.append({"timestamp_utc": value, "anchor_kind": "run-log-first-line", "location": "line:1"})
    name_match = FILENAME_TS_RE.search(name)
    if name_match and DECLARED_CAPTURE_FILE_RE.search(name):
        raw = name_match.group(1) + "T" + name_match.group(2) + "Z"
        anchors.append({
            "timestamp_utc": dt.datetime.strptime(raw, "%Y%m%dT%H%M%SZ").replace(tzinfo=dt.timezone.utc).isoformat().replace("+00:00", "Z"),
            "anchor_kind": "declared-capture-filename",
            "location": "filename",
        })
    unique = {(row["timestamp_utc"], row["anchor_kind"], row["location"]): row for row in anchors}
    return [unique[key] for key in sorted(unique)]


def is_execution_claim(line: str) -> bool:
    if re.search(r"\b(?:no|without) (?:live[- ]Azure|Azure) (?:calls?|queries|lookups?)\b", line, re.I):
        return False
    if re.search(r"\b(?:run|re-run) (?:the )?live[- ]Azure (?:call|query|lookup)\b", line, re.I):
        return False
    if re.search(r"\bcaptures? [A-Z_`]+ from the live Azure lookup\b", line, re.I):
        return False
    return STATUS_RE.search(line) is not None


def validation_claim_rows(path: str, lines: list[str]) -> list[dict[str, Any]]:
    if not lines or lines[0].strip() != "---":
        return []
    end = next((index for index, line in enumerate(lines[1:], 1) if line.strip() == "---"), None)
    if end is None:
        return []
    rows: list[dict[str, Any]] = []
    in_validation = False
    component: str | None = None
    fields: dict[str, str] = {}
    field_lines: dict[str, int] = {}

    def emit() -> None:
        if not component or fields.get("result", "").lower() != "pass":
            return
        details = []
        for key in ("last_tested", "cli_version"):
            if fields.get(key):
                details.append(f"{key}: {fields[key]}")
        suffix = f" ({'; '.join(details)})" if details else ""
        rows.append({
            "file": path,
            "line": field_lines["result"],
            "quote": f"validation.{component} result: pass{suffix}",
            "claim_kind": "validation-result",
        })

    for line_number, line in enumerate(lines[1:end], 2):
        if line == "validation:":
            in_validation = True
            continue
        if not in_validation:
            continue
        if line and not line.startswith(" "):
            break
        match = re.fullmatch(r"  ([A-Za-z0-9_-]+):\s*", line)
        if match:
            emit()
            component = match.group(1)
            fields = {}
            field_lines = {}
            continue
        match = re.fullmatch(r"    ([A-Za-z0-9_-]+):\s*(.*?)\s*", line)
        if match and component:
            fields[match.group(1)] = match.group(2).strip("'\"")
            field_lines[match.group(1)] = line_number
    emit()
    return rows


def claim_rows(root: Path, commit: str, lab: str, tracked: set[str]) -> list[dict[str, Any]]:
    candidates = [
        f"docs/troubleshooting/lab-guides/{lab}.md",
        f"labs/{lab}/README.md",
        f"labs/{lab}/evidence/README.md",
    ]
    rows: list[dict[str, Any]] = []
    for path in candidates:
        if path not in tracked:
            continue
        lines = snapshot_bytes(root, commit, path).decode(errors="replace").splitlines()
        if path.startswith("docs/troubleshooting/lab-guides/"):
            rows.extend(validation_claim_rows(path, lines))
        for line_number, line in enumerate(lines, 1):
            if is_execution_claim(line):
                rows.append({"file": path, "line": line_number, "quote": safe_quote(line)})
    return sorted(rows, key=lambda row: (row["file"], row["line"], row["quote"]))


def declared_derived_files(readme_path: str, text: str, evidence_files: set[str]) -> set[str]:
    prefix = str(Path(readme_path).parent) + "/"
    declared: set[str] = set()
    verify_section = False
    for line in text.splitlines():
        if line.startswith("## "):
            verify_section = bool(re.search(r"produced by `verify\.sh`|derived", line, re.I))
        names = re.findall(r"`([^`]+\.(?:json|jsonl|txt|md))`", line)
        verifier_context = verify_section or bool(re.search(r"(?:verify\.sh|verifier).*(?:emit|produc|writ)|derived (?:gate|output)", line, re.I))
        analyzer_context = bool(re.search(r"analy(?:ze\.py|sis)[^\n]*(?:emit|produc)", line, re.I))
        for name in names:
            candidate = prefix + Path(name).name
            if candidate in evidence_files and (verifier_context or analyzer_context):
                declared.add(candidate)
    return declared


def discrepancy_batches(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[str]] = collections.defaultdict(list)
    for row in records:
        lab = Path(row["lab_path"]).name
        for discrepancy_type in row["discrepancy_types"]:
            grouped[discrepancy_type].append(lab)
    batches: list[dict[str, Any]] = []
    number = 1
    for discrepancy_type in sorted(grouped):
        names = sorted(grouped[discrepancy_type])
        for cost_class, candidates, prerequisite in (
            ("blocked-no-run", [name for name in names if name in POLICY_BLOCKED], "Policy-free subscription or a Key Vault Private Endpoint redesign; explicit authorization before deployment."),
            ("high", [name for name in names if name in EXPENSIVE and name not in POLICY_BLOCKED], "Explicit cost and cleanup approval; Azure Firewall/Private Endpoint prerequisites."),
            ("low-to-moderate", [name for name in names if name not in POLICY_BLOCKED | EXPENSIVE], "Azure subscription access, per-lab prerequisites, and a plan to retain raw capture plus teardown output."),
        ):
            for offset in range(0, len(candidates), 8):
                subset = candidates[offset:offset + 8]
                if subset:
                    batches.append({
                        "batch": number,
                        "discrepancy_type": discrepancy_type,
                        "labs": subset,
                        "size": len(subset),
                        "prerequisites": prerequisite,
                        "cost_class": cost_class,
                    })
                    number += 1
    return batches


def markdown_table_text(text: str) -> str:
    return text.replace("|", "&#124;").replace("[", "&#91;").replace("]", "&#93;")


def markdown_claim_quote(text: str) -> str:
    if len(text) > MARKDOWN_QUOTE_LIMIT:
        text = text[:MARKDOWN_QUOTE_LIMIT - 1].rstrip() + "…"
    return markdown_table_text(text)


def markdown_claim_cell(claims: list[dict[str, Any]]) -> str:
    if not claims:
        return "No explicit status line found"
    displayed: list[str] = []
    candidates = claims[:MARKDOWN_CLAIM_COUNT_LIMIT]
    for row in candidates:
        item = f"`{row['file']}:{row['line']}` — {markdown_claim_quote(row['quote'])}"
        omitted = len(claims) - len(displayed) - 1
        suffix = f"<br>_{omitted} more in JSON_" if omitted else ""
        separator = "<br>" if displayed else ""
        available = MARKDOWN_CLAIM_CELL_LIMIT - len("<br>".join(displayed)) - len(separator) - len(suffix)
        if available <= 1:
            break
        if len(item) > available:
            item = item[:available - 1].rstrip() + "…"
        displayed.append(item)
        if len(item) >= available:
            break
    omitted = len(claims) - len(displayed)
    suffix = f"<br>_{omitted} more in JSON_" if omitted else ""
    return "<br>".join(displayed) + suffix


def build_inventory(root: Path, commit: str, as_of: dt.date) -> dict[str, Any]:
    commit = resolve_revision(root, commit)
    files = tracked_files(root, commit)
    tracked = set(files)
    current = sorted({Path(path).parts[1] for path in files if path.startswith("labs/") and len(Path(path).parts) > 2})
    records: list[dict[str, Any]] = []
    for lab in current:
        prefix = f"labs/{lab}/"
        lab_files = [path for path in files if path.startswith(prefix)]
        shell = sorted(path for path in lab_files if path.endswith(".sh"))
        verify = f"labs/{lab}/verify.sh" in tracked
        reproduction = [path for path in shell if Path(path).name not in {"verify.sh", "cleanup.sh"}]
        evidence_files = [path for path in lab_files if path.startswith(prefix + "evidence/") and not path.endswith("/README.md")]
        evidence_readme = prefix + "evidence/README.md"
        derived_files = {
            path for path in evidence_files
            if path.endswith(".json") and "gate" in Path(path).stem.lower()
        }
        if evidence_readme in tracked:
            derived_files |= declared_derived_files(
                evidence_readme,
                snapshot_bytes(root, commit, evidence_readme).decode(errors="replace"),
                set(evidence_files),
            )
        gate_files = sorted(derived_files)
        raw_files = [path for path in evidence_files if path not in derived_files and "cleanup" not in Path(path).name.lower()]
        raw_rows = []
        all_raw_anchors: list[dict[str, str]] = []
        for path in raw_files:
            anchors = capture_anchors(path, snapshot_bytes(root, commit, path))
            all_raw_anchors.extend({"path": path, **anchor} for anchor in anchors)
            values = sorted({anchor["timestamp_utc"] for anchor in anchors})
            raw_rows.append({
                "path": path,
                "capture_time_first_utc": values[0] if values else "unknown",
                "capture_time_last_utc": values[-1] if values else "unknown",
                "capture_anchors": anchors,
            })
        gate_rows = []
        for path in gate_files:
            try:
                document = json.loads(snapshot_bytes(root, commit, path))
            except (json.JSONDecodeError, UnicodeDecodeError):
                document = {}
            evaluated_at = document.get("evaluated_at_utc", "unknown") if isinstance(document, dict) else "unknown"
            gate_rows.append({"path": path, "evaluated_at_utc": evaluated_at})
        cleanup_script = f"labs/{lab}/cleanup.sh"
        cleanup_outputs = sorted(path for path in evidence_files if "cleanup" in Path(path).name.lower())
        cleanup_rows = []
        for path in cleanup_outputs:
            anchors = capture_anchors(path, snapshot_bytes(root, commit, path))
            cleanup_rows.append({"path": path, "recorded_times_utc": sorted({anchor["timestamp_utc"] for anchor in anchors})})
        claims = claim_rows(root, commit, lab, tracked)
        claim_text = " ".join(row["quote"] for row in claims).lower()
        if raw_rows and all_raw_anchors:
            classification = "live-azure-evidence"
            basis = "Committed non-gate evidence records capture timestamps; derived verifier gates are listed separately."
        elif gate_rows and not raw_rows:
            classification = "offline-replay-only"
            basis = "Committed derived gates exist without a committed non-gate raw cohort; replay is not a live Azure run."
        elif lab in POLICY_BLOCKED and not raw_rows:
            classification = "blocked"
            basis = "The historical #375 baseline identifies a Key Vault public-endpoint policy blocker, and no timestamped raw cohort is committed."
        elif not reproduction and not raw_rows:
            classification = "documentation-only"
            basis = "No reproduction orchestration or committed raw evidence is present."
        else:
            classification = "unknown"
            basis = "Repository artifacts do not establish a timestamped live Azure capture or a gate-only replay cohort."
        discrepancies = []
        discrepancy_types = []
        if ("verified" in claim_text or "reproduced" in claim_text) and not raw_rows:
            discrepancies.append("Documentation claims verified or reproduced status, but no committed non-gate raw evidence is present.")
            discrepancy_types.append("status-claim-without-raw-evidence")
        if raw_rows and not all_raw_anchors:
            discrepancies.append("Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.")
            discrepancy_types.append("raw-evidence-without-explicit-capture-anchor")
        if cleanup_script in tracked and not cleanup_outputs:
            discrepancies.append("A cleanup script exists, but no committed teardown output proves cleanup ran or completed.")
            discrepancy_types.append("missing-teardown-proof")
        if classification != "live-azure-evidence":
            discrepancies.append("Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.")
            discrepancy_types.append("missing-live-run-proof")
        records.append({
            "lab_path": f"labs/{lab}",
            "reproduction_scripts": reproduction,
            "verify_sh_present": verify,
            "status_claimed_in_docs": claims,
            "raw_evidence": raw_rows,
            "committed_gate_files": gate_rows,
            "last_azure_run_utc": max((anchor["timestamp_utc"] for anchor in all_raw_anchors), default="unknown"),
            "last_azure_run_anchor_kinds": sorted({anchor["anchor_kind"] for anchor in all_raw_anchors}),
            "cleanup_evidence": {
                "script_present": cleanup_script in tracked,
                "script": cleanup_script if cleanup_script in tracked else None,
                "recorded_teardown_outputs": cleanup_rows,
                "completion": "recorded-output-present-not-assumed-complete" if cleanup_rows else "absent",
            },
            "classification": classification,
            "evidence_basis": basis,
            "discrepancies": discrepancies,
            "discrepancy_types": discrepancy_types,
        })
    counts = collections.Counter(row["classification"] for row in records)
    return {
        "schema_version": 1,
        "source_commit_sha": commit,
        "inventory_as_of": as_of.isoformat(),
        "scope": "Static repository inventory only; no Azure resources were queried or changed.",
        "classification_values": ["live-azure-evidence", "offline-replay-only", "documentation-only", "blocked", "unknown"],
        "historical_reconciliation": {
            "issue": 375,
            "historical_count": len(HISTORICAL_LABS),
            "current_count": len(current),
            "added": sorted(set(current) - HISTORICAL_LABS),
            "removed": sorted(HISTORICAL_LABS - set(current)),
            "renamed": [],
            "rename_note": "No rename is asserted without repository evidence linking an old and new directory.",
        },
        "summary": {"labs": len(records), "classifications": dict(sorted(counts.items()))},
        "follow_up_batches": discrepancy_batches(records),
        "labs": records,
    }


def render_page(data: dict[str, Any]) -> str:
    reconciliation = data["historical_reconciliation"]
    counts = "\n".join(f"| `{name}` | {count} |" for name, count in data["summary"]["classifications"].items())
    rows = []
    for lab in data["labs"]:
        claims = markdown_claim_cell(lab["status_claimed_in_docs"])
        rows.append(f"| `{lab['lab_path']}` | `{lab['classification']}` | `{lab['last_azure_run_utc']}` | {claims} | {len(lab['raw_evidence'])} | {len(lab['committed_gate_files'])} | `{lab['cleanup_evidence']['completion']}` |")
    batch_rows = "\n".join(
        f"| {batch['batch']} | `{batch['discrepancy_type']}` | {', '.join(f'`{name}`' for name in batch['labs'])} | {batch['size']} | `{batch['cost_class']}` | {batch['prerequisites']} |"
        for batch in data["follow_up_batches"]
    ) or "| — | _None_ | — | — |"
    discrepancies = []
    for lab in data["labs"]:
        discrepancies.extend(f"- `{lab['lab_path']}`: {item}" for item in lab["discrepancies"])
    discrepancy_text = "\n".join(discrepancies) or "- No deterministic discrepancy was found."
    return f"""---
description: Source-pinned inventory of Azure Container Apps lab reproduction scripts, raw evidence, replay gates, run timestamps, cleanup proof, and gaps.
---
# Lab Reproduction Inventory

This static inventory is dated **{data['inventory_as_of']}** and pinned to source commit `{data['source_commit_sha']}`. It queried no Azure resource and incurred no Azure cost. A passing offline `verify.sh` replay is never treated as a fresh Azure reproduction, and cleanup script presence is never treated as cleanup completion.

The machine-readable record is [`lab-reproduction-inventory.json`](lab-reproduction-inventory.json). Regenerate both files intentionally with `python3 scripts/lab_reproduction_inventory.py --write --source-commit <sha> --as-of <date>`; detect drift with `python3 scripts/lab_reproduction_inventory.py --check`.

## Historical reconciliation

Issue #375 named {reconciliation['historical_count']} historical labs. The pinned tree contains {reconciliation['current_count']} `labs/` directories.

- Added: {', '.join(f'`{name}`' for name in reconciliation['added']) or 'none'}
- Removed: {', '.join(f'`{name}`' for name in reconciliation['removed']) or 'none'}
- Renamed: none. {reconciliation['rename_note']}

## Classification summary

| Classification | Labs |
|---|---:|
{counts}

`live-azure-evidence` means the committed non-gate cohort records a capture timestamp; it does not mean this inventory reran the lab. `offline-replay-only` is gate evidence without a raw cohort. `blocked`, `documentation-only`, and `unknown` preserve missing proof rather than promoting claims.

## Current lab matrix

| Lab | Classification | Last raw Azure time | Status claimed in docs | Raw files | Gate files | Cleanup proof |
|---|---|---|---|---:|---:|---|
{chr(10).join(rows)}

Per-file raw capture ranges, gate `evaluated_at_utc` values, reproduction scripts, exact status quotes, evidence bases, and discrepancy arrays are retained in the JSON.

## Discrepancies

{discrepancy_text}

## Bounded follow-up batches

These are proof-collection queues, not authorization to deploy. This inventory PR has cost class **none** because it performs no Azure work.

| Batch | Discrepancy type | Labs | Size | Future cost class | Prerequisites |
|---:|---|---|---:|---|---|
{batch_rows}

## See Also

- [Contributing Guide](../contributing/index.md)
- [Lab Gate Evaluation-Time Audit](../contributing/lab-gate-evaluation-time-audit.md)
- [Troubleshooting Labs](../troubleshooting/lab-guides/index.md)

## Sources

- [Issue #422](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/422)
- [Historical issue #375](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/375)
"""


def encoded(data: dict[str, Any]) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def current_head(root: Path) -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True).stdout.strip()


def run(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument("--source-commit")
    parser.add_argument("--as-of", type=dt.date.fromisoformat)
    args = parser.parse_args(argv)
    if args.write and (not args.source_commit or not args.as_of):
        parser.error("--write requires --source-commit and --as-of")
    json_path = root / JSON_PATH.relative_to(ROOT)
    page_path = root / PAGE_PATH.relative_to(ROOT)
    if args.check:
        if not json_path.exists():
            print(f"missing {JSON_PATH.relative_to(ROOT)}", file=sys.stderr)
            return 1
        saved = json.loads(json_path.read_text())
        commit = saved["source_commit_sha"]
        as_of = dt.date.fromisoformat(saved["inventory_as_of"])
    else:
        commit = args.source_commit or current_head(root)
        as_of = args.as_of or dt.date.today()
    try:
        data = build_inventory(root, commit, as_of)
    except InventoryError as error:
        print(error, file=sys.stderr)
        return 1
    json_text, page_text = encoded(data), render_page(data)
    if args.write:
        json_path.write_text(json_text)
        page_path.write_text(page_text)
        return 0
    failures = []
    if json_path.read_text() != json_text:
        failures.append(str(JSON_PATH.relative_to(ROOT)))
    if page_path.read_text() != page_text:
        failures.append(str(PAGE_PATH.relative_to(ROOT)))
    if failures:
        print("lab reproduction inventory drift: " + ", ".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
