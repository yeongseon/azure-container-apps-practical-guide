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
CURATED_PATH = ROOT / "docs/reference/lab-reproduction-inventory.curated.json"

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
CLASSIFICATIONS = {"live-azure-evidence", "offline-replay-only", "documentation-only", "blocked", "unknown"}
ANCHOR_KINDS = {"captured_at", "capture_window_end", "run_log", "http_date", "filename_timestamp", "readme_declared"}
CLEANUP_STATES = {"confirmed", "initiated-not-confirmed", "absent", "not-applicable"}
IMPERATIVE_STATUS_CLAIM = re.compile(r"^(?:Record|Run|Confirm)\b", re.IGNORECASE)
MARKDOWN_QUOTE_LIMIT = 240
MARKDOWN_CLAIM_COUNT_LIMIT = 3
MARKDOWN_CLAIM_CELL_LIMIT = 600


class InventoryError(Exception):
    pass


def git_text(root: Path, *args: str) -> str:
    result = subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, text=True)
    return result.stdout


def git_bytes(root: Path, *args: str) -> bytes:
    result = subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)
    return result.stdout


def resolve_revision(root: Path, revision: str) -> str:
    try:
        commit = git_text(root, "rev-parse", "--verify", f"{revision}^{{commit}}").strip()
    except subprocess.CalledProcessError as error:
        raise InventoryError(f"source commit does not exist: {revision}") from error
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise InventoryError(f"source commit does not exist: {revision}")
    return commit


def tracked_files(root: Path, commit: str) -> list[str]:
    if subprocess.run(["git", "merge-base", "--is-ancestor", commit, "HEAD"], cwd=root).returncode:
        raise InventoryError(f"source commit is not an ancestor of HEAD: {commit}")
    raw = git_bytes(root, "ls-tree", "-r", "--name-only", "-z", commit, "--", "labs", "docs/troubleshooting/lab-guides")
    return sorted(path for path in raw.decode().split("\0") if path)


def snapshot_bytes(root: Path, commit: str, path: str) -> bytes:
    return git_bytes(root, "show", f"{commit}:{path}")


def snapshot_size(root: Path, commit: str, path: str) -> int:
    return len(snapshot_bytes(root, commit, path))


def normalize_utc(value: str) -> str:
    candidate = value.strip().replace(" ", "T")
    if candidate.endswith("Z"):
        candidate = candidate[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(candidate)
    except ValueError:
        try:
            parsed = email.utils.parsedate_to_datetime(value)
        except (TypeError, ValueError) as error:
            raise InventoryError(f"invalid UTC timestamp: {value}") from error
    if parsed is None or parsed.tzinfo is None:
        raise InventoryError(f"timestamp must include a timezone: {value}")
    return parsed.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def load_curated(root: Path) -> dict[str, Any]:
    path = root / CURATED_PATH.relative_to(ROOT)
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise InventoryError(f"cannot read curated inventory: {path.relative_to(root)}") from error
    if not isinstance(data, dict) or not isinstance(data.get("labs"), list):
        raise InventoryError("curated inventory must contain a labs array")
    return data


def cited_line(root: Path, commit: str, citation: dict[str, Any], tracked: set[str], label: str) -> str:
    path = citation.get("file")
    line = citation.get("line")
    quote = citation.get("quote")
    if not isinstance(path, str) or path not in tracked:
        raise InventoryError(f"{label}: cited file does not exist at source commit: {path}")
    if not isinstance(line, int) or line < 1:
        raise InventoryError(f"{label}: citation line must be a positive integer")
    if not isinstance(quote, str) or not quote:
        raise InventoryError(f"{label}: citation quote must be non-empty")
    lines = snapshot_bytes(root, commit, path).decode("utf-8", errors="replace").splitlines()
    if line > len(lines):
        raise InventoryError(f"{label}: stale line {path}:{line}")
    if quote not in lines[line - 1]:
        raise InventoryError(f"{label}: quote is not present at {path}:{line}")
    return lines[line - 1]


def json_field(document: Any, selector: str) -> Any:
    value = document
    for part in selector.removeprefix("$.").split("."):
        match = re.fullmatch(r"([^\[]+)(?:\[(\d+)\])?", part)
        if not match or not isinstance(value, dict) or match.group(1) not in value:
            raise InventoryError(f"JSON field does not exist: {selector}")
        value = value[match.group(1)]
        if match.group(2) is not None:
            if not isinstance(value, list) or int(match.group(2)) >= len(value):
                raise InventoryError(f"JSON field does not exist: {selector}")
            value = value[int(match.group(2))]
    return value


def status_claim_problem(quote: str) -> str | None:
    stripped = quote.lstrip()
    lowered = stripped.lower()
    if stripped.startswith("#"):
        return "heading"
    if IMPERATIVE_STATUS_CLAIM.match(stripped):
        return "imperative instruction"
    if any(marker in lowered for marker in ("re-evaluated offline", "pure file processor", "replay-only", "this split is deliberate")):
        return "gate or workflow mechanics"
    if ("should" in lowered or "expected" in lowered) and not re.search(r"\b(?:observed|returned|produced|completed|reproduced|captured|measured)\b", lowered):
        return "expectation without a recorded result"
    return None


def validate_curated(root: Path, commit: str, current: list[str], tracked: set[str], data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    rows: dict[str, dict[str, Any]] = {}
    citations: set[tuple[str, int]] = set()
    for index, row in enumerate(data["labs"]):
        if not isinstance(row, dict) or not isinstance(row.get("lab"), str):
            raise InventoryError(f"curated labs[{index}] has no lab name")
        lab = row["lab"]
        if lab in rows:
            raise InventoryError(f"duplicate curated lab entry: {lab}")
        rows[lab] = row
        if row.get("classification") not in CLASSIFICATIONS:
            raise InventoryError(f"{lab}: invalid classification")
        if not isinstance(row.get("evidence_basis"), str) or not row["evidence_basis"]:
            raise InventoryError(f"{lab}: evidence_basis is required")
        claims = row.get("status_claims")
        if not isinstance(claims, list):
            raise InventoryError(f"{lab}: status_claims must be an array")
        for claim_index, claim in enumerate(claims):
            cited_line(root, commit, claim, tracked, f"{lab} status_claims[{claim_index}]")
            problem = status_claim_problem(claim["quote"])
            if problem:
                raise InventoryError(f"{lab} status_claims[{claim_index}] is not a declarative result: {problem}")
            key = (claim["file"], claim["line"])
            if key in citations:
                raise InventoryError(f"duplicated citation: {claim['file']}:{claim['line']}")
            citations.add(key)
        anchor = row.get("execution_anchor")
        if anchor is None:
            if row.get("execution_anchor_reason") != "unknown":
                raise InventoryError(f"{lab}: null execution_anchor requires reason 'unknown'")
        else:
            if not isinstance(anchor, dict) or anchor.get("kind") not in ANCHOR_KINDS:
                raise InventoryError(f"{lab}: invalid execution anchor")
            normalized = normalize_utc(str(anchor.get("utc", "")))
            if normalized != anchor.get("utc"):
                raise InventoryError(f"{lab}: execution anchor must use normalized UTC: {normalized}")
            field_or_line = anchor.get("field_or_line")
            path = anchor.get("file")
            if not isinstance(path, str) or path not in tracked:
                raise InventoryError(f"{lab}: anchor file does not exist: {path}")
            content = snapshot_bytes(root, commit, path).decode("utf-8", errors="replace")
            if isinstance(field_or_line, int):
                lines = content.splitlines()
                if field_or_line < 1 or field_or_line > len(lines) or str(anchor["utc"]) not in lines[field_or_line - 1]:
                    raise InventoryError(f"{lab}: anchor UTC is not present at {path}:{field_or_line}")
            elif field_or_line == "filename":
                compact = str(anchor["utc"]).replace("-", "").replace(":", "")
                if compact not in path:
                    raise InventoryError(f"{lab}: anchor UTC is not present in filename {path}")
            elif isinstance(field_or_line, str) and path.endswith(".json"):
                try:
                    field_value = json_field(json.loads(content), field_or_line)
                except json.JSONDecodeError as error:
                    raise InventoryError(f"{lab}: anchor JSON is invalid: {path}") from error
                raw = str(field_value)
                try:
                    field_utc = normalize_utc(raw.removeprefix("date:").strip())
                except InventoryError:
                    field_utc = ""
                if anchor["utc"] != field_utc and anchor["utc"] not in raw:
                    raise InventoryError(f"{lab}: anchor UTC is not present in {path} {field_or_line}")
            else:
                raise InventoryError(f"{lab}: invalid anchor field_or_line")
        lab_prefix = f"labs/{lab}/"
        for kind in ("derived_outputs", "raw_outputs"):
            values = row.get(kind)
            if not isinstance(values, list):
                raise InventoryError(f"{lab}: {kind} must be an array")
            seen: set[str] = set()
            for output_index, output in enumerate(values):
                if not isinstance(output, dict) or output.get("file") not in tracked or not str(output.get("file", "")).startswith(lab_prefix):
                    raise InventoryError(f"{lab}: {kind}[{output_index}] refers to a missing lab file")
                if output["file"] in seen:
                    raise InventoryError(f"{lab}: duplicate {kind} file: {output['file']}")
                seen.add(output["file"])
                justification = output.get("justification")
                if not isinstance(justification, dict):
                    raise InventoryError(f"{lab}: {kind}[{output_index}] requires a cited justification")
                cited_line(root, commit, justification, tracked, f"{lab} {kind}[{output_index}]")
        overlap = {item["file"] for item in row["derived_outputs"]} & {item["file"] for item in row["raw_outputs"]}
        if overlap:
            raise InventoryError(f"{lab}: output classified as both raw and derived: {sorted(overlap)[0]}")
        cleanup = row.get("cleanup")
        if not isinstance(cleanup, dict) or cleanup.get("state") not in CLEANUP_STATES or not isinstance(cleanup.get("evidence"), dict):
            raise InventoryError(f"{lab}: invalid cleanup record")
        cited_line(root, commit, cleanup["evidence"], tracked, f"{lab} cleanup")
        discrepancies = row.get("discrepancies")
        if not isinstance(discrepancies, list) or any(not isinstance(item, dict) or not item.get("type") or not item.get("detail") for item in discrepancies):
            raise InventoryError(f"{lab}: discrepancies must contain typed details")
    missing = sorted(set(current) - set(rows))
    extra = sorted(set(rows) - set(current))
    if missing:
        raise InventoryError("missing curated lab entries: " + ", ".join(missing))
    if extra:
        raise InventoryError("extra curated lab entries: " + ", ".join(extra))
    return rows


def discrepancy_batches(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[str]] = collections.defaultdict(list)
    for row in records:
        lab = Path(row["lab_path"]).name
        for discrepancy in row["discrepancies"]:
            grouped[discrepancy["type"]].append(lab)
        state = row["cleanup"]["state"]
        if state in {"absent", "initiated-not-confirmed"}:
            grouped[f"cleanup-{state}"].append(lab)
    batches: list[dict[str, Any]] = []
    for number, (kind, lab) in enumerate(sorted((kind, lab) for kind, labs in grouped.items() for lab in sorted(set(labs))), 1):
        if lab in POLICY_BLOCKED:
            cost, prerequisite = "blocked-no-run", "Policy-free subscription or a Key Vault Private Endpoint redesign; explicit authorization before deployment."
        elif lab in EXPENSIVE:
            cost, prerequisite = "high", "Explicit cost and cleanup approval; Azure Firewall/Private Endpoint prerequisites."
        else:
            cost, prerequisite = "low-to-moderate", "Azure subscription access, per-lab prerequisites, and a plan to retain raw capture plus teardown output."
        batches.append({"batch": number, "discrepancy_type": kind, "labs": [lab], "size": 1, "cost_class": cost, "prerequisites": prerequisite})
    return batches


def gate_row(root: Path, commit: str, path: str) -> dict[str, Any] | None:
    if not path.endswith(".json"):
        return None
    try:
        document = json.loads(snapshot_bytes(root, commit, path))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    if not isinstance(document, dict) or "evaluated_at_utc" not in document:
        return None
    return {"path": path, "evaluated_at_utc": document["evaluated_at_utc"]}


def build_inventory(root: Path, commit: str, as_of: dt.date) -> dict[str, Any]:
    commit = resolve_revision(root, commit)
    files = tracked_files(root, commit)
    tracked = set(files)
    current = sorted({Path(path).parts[1] for path in files if path.startswith("labs/") and len(Path(path).parts) > 2})
    curated = validate_curated(root, commit, current, tracked, load_curated(root))
    records: list[dict[str, Any]] = []
    for lab in current:
        semantic = curated[lab]
        prefix = f"labs/{lab}/"
        lab_files = sorted(path for path in files if path.startswith(prefix))
        evidence_files = sorted(path for path in lab_files if path.startswith(prefix + "evidence/") and not path.endswith("/README.md"))
        mechanical_gates = [row for path in evidence_files if (row := gate_row(root, commit, path)) is not None]
        derived_overrides = {row["file"] for row in semantic["derived_outputs"]}
        raw_overrides = {row["file"] for row in semantic["raw_outputs"]}
        mechanical_gate_paths = {row["path"] for row in mechanical_gates}
        derived = sorted(mechanical_gate_paths | derived_overrides)
        raw = sorted((set(evidence_files) - set(derived)) | raw_overrides)
        raw = [path for path in raw if path not in derived]
        records.append({
            "lab_path": f"labs/{lab}",
            "directory_listing": lab_files,
            "reproduction_scripts": sorted(path for path in lab_files if path.endswith(".sh") and Path(path).name not in {"verify.sh", "cleanup.sh"}),
            "verify_sh_present": f"labs/{lab}/verify.sh" in tracked,
            "committed_evidence_files": [{"path": path, "size_bytes": snapshot_size(root, commit, path)} for path in evidence_files],
            "committed_gate_files": sorted(mechanical_gates, key=lambda row: row["path"]),
            "status_claims": semantic["status_claims"],
            "execution_anchor": semantic["execution_anchor"],
            "execution_anchor_reason": semantic.get("execution_anchor_reason"),
            "last_azure_run_utc": semantic["execution_anchor"]["utc"] if semantic["execution_anchor"] else "unknown",
            "derived_outputs": derived,
            "raw_outputs": raw,
            "cleanup": semantic["cleanup"],
            "classification": semantic["classification"],
            "evidence_basis": semantic["evidence_basis"],
            "discrepancies": semantic["discrepancies"],
        })
    counts = collections.Counter(row["classification"] for row in records)
    return {
        "schema_version": 2,
        "source_commit_sha": commit,
        "inventory_as_of": as_of.isoformat(),
        "scope": "Static repository inventory only; no Azure resources were queried or changed.",
        "classification_values": sorted(CLASSIFICATIONS),
        "historical_reconciliation": {"issue": 375, "historical_count": len(HISTORICAL_LABS), "current_count": len(current), "added": sorted(set(current) - HISTORICAL_LABS), "removed": sorted(HISTORICAL_LABS - set(current)), "renamed": [], "rename_note": "No rename is asserted without repository evidence linking an old and new directory."},
        "summary": {"labs": len(records), "status_claims": sum(len(row["status_claims"]) for row in records), "execution_anchors": sum(row["execution_anchor"] is not None for row in records), "classifications": dict(sorted(counts.items()))},
        "follow_up_batches": discrepancy_batches(records),
        "labs": records,
    }


def markdown_text(text: str) -> str:
    return text.replace("|", "&#124;").replace("[", "&#91;").replace("]", "&#93;")


def markdown_claim_cell(claims: list[dict[str, Any]]) -> str:
    if not claims:
        return "No curated status claim"
    displayed: list[str] = []
    for row in claims[:MARKDOWN_CLAIM_COUNT_LIMIT]:
        quote = row["quote"]
        if len(quote) > MARKDOWN_QUOTE_LIMIT:
            quote = quote[:MARKDOWN_QUOTE_LIMIT - 1].rstrip() + "…"
        item = f"`{row['file']}:{row['line']}` — {markdown_text(quote)}"
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


def render_page(data: dict[str, Any]) -> str:
    reconciliation = data["historical_reconciliation"]
    counts = "\n".join(f"| `{name}` | {count} |" for name, count in data["summary"]["classifications"].items())
    rows = [f"| `{lab['lab_path']}` | `{lab['classification']}` | `{lab['last_azure_run_utc']}` | {markdown_claim_cell(lab['status_claims'])} | {len(lab['raw_outputs'])} | {len(lab['derived_outputs'])} | `{lab['cleanup']['state']}` |" for lab in data["labs"]]
    batch_rows = "\n".join(f"| {batch['batch']} | `{batch['discrepancy_type']}` | `{batch['labs'][0]}` | {batch['size']} | `{batch['cost_class']}` | {batch['prerequisites']} |" for batch in data["follow_up_batches"]) or "| — | _None_ | — | — | — | — |"
    discrepancy_text = "\n".join(f"- `{lab['lab_path']}` (`{item['type']}`): {item['detail']}" for lab in data["labs"] for item in lab["discrepancies"]) or "- No curated discrepancy is recorded."
    return f'''---
description: Curated, citation-verified inventory of Azure Container Apps lab evidence, execution anchors, cleanup proof, and reproduction gaps.
---
# Lab Reproduction Inventory

This static inventory is dated **{data['inventory_as_of']}** and pinned to source commit `{data['source_commit_sha']}`. It queried no Azure resource and incurred no Azure cost.

Mechanical fields (tree listings, scripts, evidence files and byte sizes, and gate `evaluated_at_utc` values) are computed from the pinned tree. Semantic fields are hand-authored in [`lab-reproduction-inventory.curated.json`](lab-reproduction-inventory.curated.json) after reading the lab sources. The generator verifies each citation and never infers status, execution time, evidence provenance, cleanup, or classification from prose.

## Historical reconciliation

Issue #375 named {reconciliation['historical_count']} historical labs. The pinned tree contains {reconciliation['current_count']} `labs/` directories.

- Added: {', '.join(f'`{name}`' for name in reconciliation['added']) or 'none'}
- Removed: {', '.join(f'`{name}`' for name in reconciliation['removed']) or 'none'}
- Renamed: none. {reconciliation['rename_note']}

## Classification summary

| Classification | Labs |
|---|---:|
{counts}

## Current lab matrix

| Lab | Classification | Last Azure observation | Curated status claims | Raw files | Derived files | Cleanup |
|---|---|---|---|---:|---:|---|
{chr(10).join(rows)}

Complete citations, file listings and sizes, output overrides, evidence bases, and discrepancy arrays are retained in the JSON.

## Discrepancies

{discrepancy_text}

## Bounded follow-up batches

Each cleanup gap and each curated discrepancy has exactly one per-lab batch. These queues are not authorization to deploy.

| Batch | Discrepancy type | Lab | Size | Future cost class | Prerequisites |
|---:|---|---|---:|---|---|
{batch_rows}

## See Also

- [Contributing Guide](../contributing/index.md)
- [Lab Gate Evaluation-Time Audit](../contributing/lab-gate-evaluation-time-audit.md)
- [Troubleshooting Labs](../troubleshooting/lab-guides/index.md)

## Sources

- [Issue #422](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/422)
- [Historical issue #375](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/375)
'''


def encoded(data: dict[str, Any]) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def current_head(root: Path) -> str:
    return git_text(root, "rev-parse", "HEAD").strip()


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
        commit, as_of = saved["source_commit_sha"], dt.date.fromisoformat(saved["inventory_as_of"])
    else:
        commit, as_of = args.source_commit or current_head(root), args.as_of or dt.date.today()
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
