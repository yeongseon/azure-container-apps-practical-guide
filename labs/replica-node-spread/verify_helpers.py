"""Shared offline input boundaries and strict gate serialization.

Unusable JSONL lines count against the per-file parse policy. Supplied malformed
consumed fields additionally fail their owning gate, even for one record.
Summary validation returns diagnostics rather than trusting arbitrary JSON shapes.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Final, TypedDict

Json = None | bool | int | float | str | list["Json"] | dict[str, "Json"]
JSON_EXACT_MAX: Final = 2**53
REQUIRED_RECORD_KEYS: Final = ("boot_id", "replica_name", "uptime_seconds", "run_id")
SUMMARY_COUNTS: Final = ("unique_replicas", "unique_boot_ids", "boot_time_clusters")


class ParseStats(TypedDict):
    total_lines: int
    blank_lines: int
    json_parse_failures: int
    missing_keys_failures: int
    malformed_records: int
    malformed_fields: dict[str, int]
    successful_records: int


class SummaryIssue(TypedDict, total=False):
    reason: str
    index: int
    field: str


def is_bounded_number(value: Json) -> bool:
    """Bound the decoded value, not the original decimal token; exclude bools."""
    return isinstance(value, (int, float)) and not isinstance(value, bool) and abs(value) <= JSON_EXACT_MAX


def parse_jsonl_records(path: str) -> tuple[list[dict[str, Json]], ParseStats]:
    """Exclude unusable records, retaining per-field counts without input values."""
    records = []
    stats: ParseStats = {
        "total_lines": 0, "blank_lines": 0, "json_parse_failures": 0,
        "missing_keys_failures": 0, "malformed_records": 0,
        "malformed_fields": {}, "successful_records": 0,
    }
    numeric_fields = ("boot_time_estimate_ms",)
    if Path(path).name.startswith("h3-"):
        numeric_fields += ("uptime_seconds",)
    with open(path) as source:
        for line in source:
            stats["total_lines"] += 1
            if not line.strip():
                stats["blank_lines"] += 1
                continue
            try:
                record = json.loads(line)
            except (ValueError, RecursionError):
                stats["json_parse_failures"] += 1
                continue
            if not isinstance(record, dict):
                stats["missing_keys_failures"] += 1
                continue
            malformed = [
                field for field in ("boot_id", "replica_name")
                if field in record and (not isinstance(record[field], str) or not record[field].strip())
            ] + [
                field for field in numeric_fields
                if field in record and not is_bounded_number(record[field])
            ]
            if malformed:
                stats["malformed_records"] += 1
                for field in malformed:
                    stats["malformed_fields"][field] = stats["malformed_fields"].get(field, 0) + 1
                continue
            if not all(k in record for k in REQUIRED_RECORD_KEYS):
                stats["missing_keys_failures"] += 1
                continue
            records.append(record)
            stats["successful_records"] += 1
    return records, stats


def load_summary(path: str) -> tuple[list[dict[str, Json]], dict[str, dict[str, Json]], list[SummaryIssue]]:
    """Accept list or legacy runs-list roots; index only validated consumed fields.

    Unconsumed metadata never enters a gate. Invalid members remain represented
    in the list length, but not the lookup, so duplicates cannot disappear.
    """
    try:
        with open(path) as source:
            data = json.load(source)
    except (ValueError, RecursionError) as error:
        return [], {}, [{"reason": type(error).__name__}]
    if isinstance(data, dict):
        data = data.get("runs")
    if not isinstance(data, list):
        return [], {}, [{"reason": "summary root must be a list or runs-list object"}]
    issues: list[SummaryIssue] = []
    by_filename = {}
    for index, member in enumerate(data):
        if not isinstance(member, dict):
            issues.append({"index": index, "reason": "summary member must be an object"})
            continue
        filename = member.get("file")
        if not isinstance(filename, str) or not filename.strip():
            issues.append({"index": index, "field": "file", "reason": "filename must be a nonempty string"})
            continue
        if filename in by_filename:
            issues.append({"index": index, "field": "file", "reason": "duplicate filename"})
            continue
        invalid_counts = [
            field for field in SUMMARY_COUNTS
            if type(member.get(field)) not in (int, float)
            or member[field] < 0
            or (isinstance(member[field], float)
                and (not math.isfinite(member[field]) or not member[field].is_integer()))
        ]
        if invalid_counts:
            issues.extend({"index": index, "field": field, "reason": "count must be a finite nonnegative integer"}
                          for field in invalid_counts)
            continue
        by_filename[filename] = {"file": filename, **{field: member[field] for field in SUMMARY_COUNTS}}
    return data, by_filename, issues


def serialize_gate(payload: Json) -> str:
    """Reject non-standard JSON constants at the actual gate writer seam."""
    return json.dumps(payload, indent=2, allow_nan=False)
