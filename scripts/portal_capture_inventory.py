#!/usr/bin/env python3
"""Inventory Portal capture coverage without opening or modifying image files.

Usage:
    python3 scripts/portal_capture_inventory.py --write --base-commit SHA
    python3 scripts/portal_capture_inventory.py --check
    python3 scripts/portal_capture_inventory.py --summary
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import fnmatch
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlsplit

import yaml

ROOT = Path(__file__).resolve().parents[1]
RULES_PATH = ROOT / "scripts/portal_capture_inventory_rules.json"
MANIFEST_PATH = ROOT / "scripts/capture/manifest.yaml"
JSON_PATH = ROOT / "docs/reference/portal-capture-inventory.json"
PAGE_PATH = ROOT / "docs/reference/portal-capture-inventory.md"

SHOT_RE = re.compile(r'''\[\[\[\s*shot\(\s*["']([^"']+)["']\s*\)\s*\]\]\]''')
MARKDOWN_IMAGE_RE = re.compile(r'''!\[([^\]]*)\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)''')
HTML_IMAGE_RE = re.compile(
    r'''<img\b[^>]*?\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>''', re.I
)
HTML_ALT_RE = re.compile(r'''\balt\s*=\s*(?:"([^"]*)"|'([^']*)')''', re.I)
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
GENERIC_ALT = re.compile(r"^(?:image|screenshot|portal|capture|figure|diagram|photo)?\s*$", re.I)


class InventoryError(Exception):
    pass


def load_rules(root: Path = ROOT) -> dict[str, Any]:
    return json.loads((root / RULES_PATH.relative_to(ROOT)).read_text(encoding="utf-8"))


def tracked_files(root: Path) -> list[str]:
    if (root / ".git").exists():
        result = subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            cwd=root,
            check=True,
            capture_output=True,
        )
        return sorted(path for path in result.stdout.decode().split("\0") if path)
    return sorted(
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and ".git" not in path.parts
    )


def without_fences(text: str) -> str:
    output: list[str] = []
    marker: str | None = None
    for line in text.splitlines():
        match = FENCE_RE.match(line)
        if marker is None and match:
            marker = match.group(1)
            output.append("")
            continue
        if marker is not None:
            if re.fullmatch(r" {0,3}" + re.escape(marker[0]) + "{" + str(len(marker)) + r",}\s*", line):
                marker = None
            output.append("")
            continue
        output.append(line)
    return "\n".join(output)


def local_target(root: Path, page: Path, target: str) -> str | None:
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc or target.startswith(("//", "data:")):
        return None
    decoded = unquote(parsed.path)
    if not decoded:
        return None
    candidate = root / decoded.lstrip("/") if decoded.startswith("/") else page.parent / decoded
    try:
        relative = candidate.resolve().relative_to(root.resolve())
    except ValueError:
        return None
    return relative.as_posix()


def markdown_references(root: Path, page_path: str, text: str) -> list[dict[str, Any]]:
    page = root / page_path
    clean = without_fences(text)
    references: list[dict[str, Any]] = []
    for line_number, line in enumerate(clean.splitlines(), 1):
        for match in MARKDOWN_IMAGE_RE.finditer(line):
            references.append(
                {
                    "kind": "raw_markdown",
                    "line": line_number,
                    "target": match.group(2),
                    "resolved_path": local_target(root, page, match.group(2)),
                    "alt": match.group(1).strip(),
                }
            )
        for match in HTML_IMAGE_RE.finditer(line):
            target = next(value for value in match.groups() if value is not None)
            alt_match = HTML_ALT_RE.search(match.group(0))
            alt = next((value for value in alt_match.groups() if value is not None), "") if alt_match else ""
            references.append(
                {
                    "kind": "raw_html",
                    "line": line_number,
                    "target": target,
                    "resolved_path": local_target(root, page, target),
                    "alt": alt.strip(),
                }
            )
        for match in SHOT_RE.finditer(line):
            references.append(
                {
                    "kind": "shot",
                    "line": line_number,
                    "shot_id": match.group(1),
                }
            )
    return references


def manifest_records(root: Path) -> tuple[dict[str, dict[str, Any]], list[str]]:
    path = root / MANIFEST_PATH.relative_to(ROOT)
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    screenshots = data.get("screenshots", [])
    if not isinstance(screenshots, list):
        raise InventoryError("scripts/capture/manifest.yaml screenshots is not a list")
    records: dict[str, dict[str, Any]] = {}
    duplicates: list[str] = []
    for item in screenshots:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str):
            raise InventoryError("manifest screenshot entry lacks a string id")
        shot_id = item["id"]
        if shot_id in records:
            duplicates.append(shot_id)
        records[shot_id] = dict(item)
    return records, sorted(set(duplicates))


def parse_date(value: Any) -> dt.date | None:
    if isinstance(value, dt.date):
        return value
    if isinstance(value, str):
        try:
            return dt.date.fromisoformat(value)
        except ValueError:
            return None
    return None


def is_excluded(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def build_inventory(root: Path, base_commit: str, as_of: dt.date) -> dict[str, Any]:
    rules = load_rules(root)
    tracked = tracked_files(root)
    tracked_set = set(tracked)
    extensions = {suffix.lower() for suffix in rules["image_extensions"]}
    excluded_assets = set(rules["excluded_assets"])
    assets = [
        path for path in tracked
        if path.startswith("docs/assets/")
        and Path(path).suffix.lower() in extensions
        and path not in excluded_assets
    ]
    manifest, duplicate_ids = manifest_records(root)
    manifest_paths = {
        str(item.get("file", "")).lstrip("/"): shot_id
        for shot_id, item in manifest.items()
        if item.get("file")
    }

    pages: list[dict[str, Any]] = []
    refs_by_asset: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    refs_by_shot: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    all_references: list[dict[str, Any]] = []
    portal_terms = [term.casefold() for term in rules["portal_terms"]]
    for path in tracked:
        if not path.startswith("docs/") or not path.endswith(".md"):
            continue
        if path == PAGE_PATH.relative_to(ROOT).as_posix():
            continue
        text = (root / path).read_text(encoding="utf-8")
        clean = without_fences(text)
        refs = markdown_references(root, path, text)
        local_raster = []
        shot_ids = []
        broken = []
        alt_risks = []
        for ref in refs:
            record = {"page": path, **ref}
            all_references.append(record)
            if ref["kind"] == "shot":
                shot_id = ref["shot_id"]
                shot_ids.append(shot_id)
                refs_by_shot[shot_id].append(record)
                if shot_id not in manifest:
                    broken.append({"kind": "unknown_shot_id", "value": shot_id, "line": ref["line"]})
                continue
            resolved = ref.get("resolved_path")
            if resolved and Path(resolved).suffix.lower() in extensions:
                local_raster.append(resolved)
                refs_by_asset[resolved].append(record)
                if resolved not in tracked_set:
                    broken.append({"kind": "missing_asset", "value": resolved, "line": ref["line"]})
                if GENERIC_ALT.fullmatch(ref.get("alt", "")):
                    alt_risks.append({"kind": "empty_or_generic_alt", "line": ref["line"], "asset": resolved})

        excluded = is_excluded(path, rules["excluded_page_globs"])
        portal_instruction = any(term in clean.casefold() for term in portal_terms)
        legacy = sorted({asset for asset in local_raster if asset not in manifest_paths})
        registered = sorted({asset for asset in local_raster if asset in manifest_paths})
        stale_ids = []
        for shot_id in shot_ids:
            item = manifest.get(shot_id)
            if not item:
                continue
            verified = parse_date(item.get("verified"))
            if verified is None or (as_of - verified).days > rules["stale_after_days"]:
                stale_ids.append(shot_id)
        if excluded or not portal_instruction:
            state = "excluded"
            reason = "rule exclusion" if excluded else "no Portal-instruction term"
        elif broken:
            state = "missing"
            reason = "broken local image or unknown shot() reference"
        elif stale_ids:
            state = "stale"
            reason = "manifest verification is absent or older than the configured threshold"
        elif legacy:
            state = "manual-blocked"
            reason = "legacy image bytes exist but final-image and caption verification are not recorded"
        elif registered or shot_ids:
            state = "captured"
            reason = "manifest-backed capture reference exists and is not stale"
        else:
            state = "missing"
            reason = "Portal-instruction page has no local raster or shot() reference"
        pages.append(
            {
                "path": path,
                "portal_instruction": portal_instruction,
                "state": state,
                "state_reason": reason,
                "raw_image_references": sorted(set(local_raster)),
                "shot_ids": sorted(set(shot_ids)),
                "legacy_assets": legacy,
                "manifest_assets": registered,
                "broken_references": broken,
                "caption_alt_review_candidates": alt_risks,
            }
        )

    asset_rows: list[dict[str, Any]] = []
    for path in assets:
        refs = refs_by_asset.get(path, [])
        distinct_pages = sorted({ref["page"] for ref in refs})
        alts = sorted({ref.get("alt", "") for ref in refs})
        risks = []
        if len(distinct_pages) > 1:
            risks.append("reused_across_pages")
        if len(alts) > 1:
            risks.append("inconsistent_alt_text")
        if any(GENERIC_ALT.fullmatch(alt) for alt in alts):
            risks.append("empty_or_generic_alt")
        asset_rows.append(
            {
                "path": path,
                "manifest_id": manifest_paths.get(path),
                "legacy": path not in manifest_paths,
                "referenced_by": distinct_pages,
                "reference_count": len(refs),
                "caption_alt_review_candidates": risks,
                "final_image_visual_verification": "not_collected",
            }
        )

    manifest_rows = []
    for shot_id, item in sorted(manifest.items()):
        file_path = str(item.get("file", "")).lstrip("/") or None
        verified = parse_date(item.get("verified"))
        stale = verified is None or (as_of - verified).days > rules["stale_after_days"]
        manifest_rows.append(
            {
                "id": shot_id,
                "file": file_path,
                "file_exists": bool(file_path and file_path in tracked_set),
                "reference_count": len(refs_by_shot.get(shot_id, [])),
                "referenced_by": sorted({ref["page"] for ref in refs_by_shot.get(shot_id, [])}),
                "stale": stale,
                "verified": str(item.get("verified")) if item.get("verified") is not None else None,
            }
        )

    lab_pages = [
        page for page in pages
        if page["path"].startswith("docs/troubleshooting/lab-guides/")
        and page["path"] != "docs/troubleshooting/lab-guides/index.md"
    ]
    lab_rows = []
    tracked_by_slug = {batch.get("lab_slug"): batch for batch in rules["tracked_batches"]}
    for page in lab_pages:
        slug = Path(page["path"]).stem
        with_evidence = bool(page["raw_image_references"] or page["shot_ids"])
        batch = tracked_by_slug.get(slug)
        lab_rows.append(
            {
                "lab_slug": slug,
                "page": page["path"],
                "portal_evidence": "with" if with_evidence else "without",
                "capture_reference_count": len(page["raw_image_references"]) + len(page["shot_ids"]),
                "tracked_batch": (
                    {"repo": batch["repo"], "issue": batch["issue"], "state": batch["state"]}
                    if batch else None
                ),
            }
        )

    states = ("captured", "missing", "stale", "manual-blocked", "excluded")
    page_counts = collections.Counter(page["state"] for page in pages)
    portal_pages = [page for page in pages if page["portal_instruction"] and page["state"] != "excluded"]
    portal_state_counts = collections.Counter(page["state"] for page in portal_pages)
    reused = [asset for asset in asset_rows if len(asset["referenced_by"]) > 1]
    caption_candidates = [asset for asset in asset_rows if asset["caption_alt_review_candidates"]]
    return {
        "schema_version": 1,
        "pinned_base_commit": base_commit,
        "inventory_as_of": as_of.isoformat(),
        "method": {
            "read_only": True,
            "tracked_files_only": True,
            "portal_instruction_terms": rules["portal_terms"],
            "stale_after_days": rules["stale_after_days"],
            "visual_verification": "not_collected",
            "caption_match_verification": "not_collected; candidates are heuristic review queues, not mismatch findings",
        },
        "summary": {
            "markdown_pages": len(pages),
            "portal_instruction_pages": len(portal_pages),
            "page_states_all": {state: page_counts[state] for state in states},
            "portal_page_states": {state: portal_state_counts[state] for state in states},
            "raster_assets": len(asset_rows),
            "legacy_assets": sum(asset["legacy"] for asset in asset_rows),
            "manifest_ids": len(manifest_rows),
            "shot_references": sum(len(refs) for refs in refs_by_shot.values()),
            "raw_image_references": sum(len(refs) for refs in refs_by_asset.values()),
            "reused_assets": len(reused),
            "caption_alt_review_candidates": len(caption_candidates),
            "labs": len(lab_rows),
            "labs_with_portal_evidence": sum(row["portal_evidence"] == "with" for row in lab_rows),
            "labs_without_portal_evidence": sum(row["portal_evidence"] == "without" for row in lab_rows),
        },
        "manifest": {"duplicate_ids": duplicate_ids, "entries": manifest_rows},
        "tracked_batches": rules["tracked_batches"],
        "pages": pages,
        "assets": asset_rows,
        "labs": lab_rows,
    }


def render_page(data: dict[str, Any]) -> str:
    summary = data["summary"]
    state_rows = "\n".join(
        f"| `{state}` | {count} |" for state, count in data["summary"]["page_states_all"].items()
    )
    reused = [asset for asset in data["assets"] if len(asset["referenced_by"]) > 1]
    reuse_rows = "\n".join(
        f"| `{asset['path']}` | {len(asset['referenced_by'])} | "
        + "<br>".join(f"`{page}`" for page in asset["referenced_by"])
        + " |"
        for asset in reused
    ) or "| _None_ | 0 | — |"
    labs_without = [row for row in data["labs"] if row["portal_evidence"] == "without"]
    lab_rows = "\n".join(
        f"| `{row['lab_slug']}` | "
        + (f"#{row['tracked_batch']['issue']} ({row['tracked_batch']['state']})" if row["tracked_batch"] else "unassigned")
        + " |"
        for row in labs_without
    ) or "| _None_ | — |"
    candidate_rows = "\n".join(
        f"| `{asset['path']}` | {', '.join(asset['caption_alt_review_candidates'])} |"
        for asset in data["assets"] if asset["caption_alt_review_candidates"]
    ) or "| _None_ | — |"
    return f"""---
description: Current Azure Container Apps Portal capture inventory, including manifest coverage, legacy image reuse, lab gaps, and manual review queues.
---
# Portal Capture Inventory

This inventory is generated from tracked repository files at `{data['pinned_base_commit']}`. It records file and reference presence only; no image was opened, captured, changed, or independently re-verified.

## Reproduce the inventory

```bash
python3 scripts/portal_capture_inventory.py --check
```

The detailed machine-readable inventory is [`portal-capture-inventory.json`](portal-capture-inventory.json). Regenerate both files with `--write --base-commit <sha>` only when intentionally pinning a new baseline.

## Current counts

| Measure | Count |
|---|---:|
| Markdown pages scanned | {summary['markdown_pages']} |
| Portal-instruction pages | {summary['portal_instruction_pages']} |
| Raster assets | {summary['raster_assets']} |
| Legacy assets outside the manifest | {summary['legacy_assets']} |
| Manifest IDs | {summary['manifest_ids']} |
| `shot()` references | {summary['shot_references']} |
| Raw local image references | {summary['raw_image_references']} |
| Assets reused across pages | {summary['reused_assets']} |
| Caption/alt review candidates | {summary['caption_alt_review_candidates']} |
| Lab guides with Portal evidence | {summary['labs_with_portal_evidence']} |
| Lab guides without Portal evidence | {summary['labs_without_portal_evidence']} |

| Page state | Count |
|---|---:|
{state_rows}

`manual-blocked` means legacy bytes exist but final-image PII and caption accuracy were **not collected**. `missing` means a Portal-instruction page has no local capture, or has a broken reference. `stale` applies only to manifest-backed captures whose `verified` date is absent or older than {data['method']['stale_after_days']} days. `excluded` means no Portal-instruction term matched or an explicit rule excluded the page. The JSON includes the same five states for every page and a separate Portal-only state count.

## Legacy image reuse

These are deterministic reuse candidates, not proof that a caption is wrong.

| Asset | Pages | Referenced by |
|---|---:|---|
{reuse_rows}

## Caption and alt-text review queue

The script flags reuse, inconsistent alt text, and empty or generic alt text. Actual caption-to-image verification was **not collected** because this task did not open images.

| Asset | Review reason |
|---|---|
{candidate_rows}

## Labs without Portal evidence

The table covers every tracked Markdown file under `docs/troubleshooting/lab-guides/` except the index. Existing issue assignments are shown so a future capture batch is not duplicated.

| Lab | Existing batch |
|---|---|
{lab_rows}

Cross-repo issue `yeongseon/azure-functions-practical-guide#389` was checked directly: it is closed, covers Queue-trigger retry and poison-message assertions, and names no ACA Portal capture path or batch. It therefore creates no duplicate ACA assignment.

## State and verification limits

- Existing PNG or WebP bytes are not treated as independently verified final images.
- Legacy raw image links are inventoried as `manual-blocked`, not migrated or renamed.
- The report does not claim that a heuristic caption/alt candidate is a confirmed mismatch.
- Capture dates, live Azure reproduction, resource cleanup, and visual PII review were not collected.
- The seven ACA lab batches already tracked by #308, #362, #364, #366, #368, #370, and #372 are recorded in the JSON and are not reassigned here.

## See Also

- [Lab Portal Capture Briefs](../contributing/lab-portal-capture-briefs.md)
- [Troubleshooting Labs](../troubleshooting/lab-guides/index.md)
"""


def encoded(data: dict[str, Any]) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def current_head(root: Path) -> str:
    return subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True
    ).stdout.strip()


def run(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--summary", action="store_true")
    parser.add_argument("--base-commit")
    parser.add_argument("--as-of", type=dt.date.fromisoformat)
    args = parser.parse_args(argv)
    if args.write and not args.base_commit:
        parser.error("--write requires --base-commit")
    if args.check:
        if not (root / JSON_PATH.relative_to(ROOT)).exists():
            print(f"missing {JSON_PATH.relative_to(ROOT)}", file=sys.stderr)
            return 1
        expected = json.loads((root / JSON_PATH.relative_to(ROOT)).read_text(encoding="utf-8"))
        base_commit = expected["pinned_base_commit"]
        as_of = dt.date.fromisoformat(expected["inventory_as_of"])
    else:
        base_commit = args.base_commit or current_head(root)
        as_of = args.as_of or dt.date.today()
    data = build_inventory(root, base_commit, as_of)
    if args.summary:
        print(json.dumps(data["summary"], indent=2, sort_keys=True))
        return 0
    json_text = encoded(data)
    page_text = render_page(data)
    json_path = root / JSON_PATH.relative_to(ROOT)
    page_path = root / PAGE_PATH.relative_to(ROOT)
    if args.write:
        json_path.write_text(json_text, encoding="utf-8")
        page_path.write_text(page_text, encoding="utf-8")
        return 0
    failures = []
    if json_path.read_text(encoding="utf-8") != json_text:
        failures.append(str(JSON_PATH.relative_to(ROOT)))
    if page_path.read_text(encoding="utf-8") != page_text:
        failures.append(str(PAGE_PATH.relative_to(ROOT)))
    if failures:
        print("capture inventory drift: " + ", ".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
