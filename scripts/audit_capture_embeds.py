#!/usr/bin/env python3
"""
Audit docs/ for capture embedding defects.

Defect classes:
  1. ORPHAN — asset file exists but NO markdown page references it (neither
     embedded nor mentioned).
  2. DOCUMENTED-NOT-EMBEDDED — asset basename is mentioned somewhere in a
     markdown page (in code/text/table cell) but NEVER embedded via
     ![alt](path) or <img src="path">. This is the defect class fixed in PR #211.
  3. BROKEN-EMBED — a markdown page embeds an image via ![](relpath) or
     <img src="relpath"> where relpath does not resolve to a real file.
  4. LAB-MISMATCH — for docs/assets/troubleshooting/<lab>/ directories that
     have PNGs but the corresponding docs/troubleshooting/lab-guides/<lab>.md
     embeds zero of those PNGs.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from collections import defaultdict

REPO = Path(__file__).resolve().parents[1]
DOCS = REPO / "docs"
ASSETS = DOCS / "assets"

EXCLUDE_BASENAMES = {"logo.svg", "favicon.svg"}

IMG_EXTS = {".png", ".jpg", ".jpeg", ".svg", ".webp", ".gif"}

MD_IMG_RE = re.compile(r"!\[[^\]]*\]\(([^)\s]+)(?:\s+[^)]*)?\)")
HTML_IMG_RE = re.compile(
    r"""<img\b[^>]*?\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))""", re.IGNORECASE
)


def find_all_assets():
    assets = []
    for p in ASSETS.rglob("*"):
        if not p.is_file():
            continue
        if p.suffix.lower() not in IMG_EXTS:
            continue
        if p.name in EXCLUDE_BASENAMES:
            continue
        assets.append(p)
    return sorted(assets)


def find_all_markdown():
    return sorted(p for p in DOCS.rglob("*.md") if p.is_file())


def resolve_relpath(md_file: Path, relpath: str) -> Path | None:
    relpath = relpath.split("#", 1)[0].split("?", 1)[0]
    if not relpath:
        return None
    if relpath.startswith(("http://", "https://", "//", "data:", "mailto:")):
        return None
    base = md_file.parent
    try:
        resolved = (base / relpath).resolve()
    except (OSError, RuntimeError):
        return None
    if not resolved.exists():
        return None
    return resolved


def scan_markdown_embeds(md_files):
    embeds_by_target: dict[Path, list[tuple[Path, int]]] = defaultdict(list)
    broken_embeds: list[tuple[Path, int, str, str]] = []

    for md in md_files:
        try:
            text = md.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            for m in MD_IMG_RE.finditer(line):
                relpath = m.group(1)
                if relpath.startswith(("http://", "https://", "data:")):
                    continue
                resolved = resolve_relpath(md, relpath)
                if resolved is None:
                    broken_embeds.append((md, lineno, relpath, "markdown"))
                else:
                    embeds_by_target[resolved].append((md, lineno))
            for m in HTML_IMG_RE.finditer(line):
                relpath = m.group(1) or m.group(2) or m.group(3)
                if not relpath or relpath.startswith(("http://", "https://", "data:")):
                    continue
                resolved = resolve_relpath(md, relpath)
                if resolved is None:
                    broken_embeds.append((md, lineno, relpath, "html"))
                else:
                    embeds_by_target[resolved].append((md, lineno))

    return embeds_by_target, broken_embeds


def scan_filename_mentions(md_files, asset_basenames):
    mentions: dict[str, list[tuple[Path, int, str]]] = defaultdict(list)
    if not asset_basenames:
        return mentions
    escaped = sorted({re.escape(b) for b in asset_basenames}, key=len, reverse=True)
    big_re = re.compile(r"(?<![\w.-])(" + "|".join(escaped) + r")(?![\w])")

    for md in md_files:
        try:
            text = md.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            for m in big_re.finditer(line):
                basename = m.group(1)
                mentions[basename].append((md, lineno, line.strip()[:200]))

    return mentions


def main():
    assets = find_all_assets()
    md_files = find_all_markdown()

    asset_basenames = {a.name for a in assets}

    print(f"# Capture Embedding Audit\n")
    print(f"- Repo: `{REPO}`")
    print(f"- Markdown files scanned: **{len(md_files)}**")
    print(
        f"- Asset files found (PNG/JPG/SVG/WebP/GIF excl. theme): **{len(assets)}**\n"
    )

    embeds_by_target, broken_embeds = scan_markdown_embeds(md_files)
    mentions = scan_filename_mentions(md_files, asset_basenames)

    embedded: list[Path] = []
    documented_not_embedded: list[tuple[Path, list[tuple[Path, int, str]]]] = []
    orphan: list[Path] = []

    for a in assets:
        if embeds_by_target.get(a):
            embedded.append(a)
            continue
        ms = mentions.get(a.name, [])
        if ms:
            documented_not_embedded.append((a, ms))
        else:
            orphan.append(a)

    print(f"## Summary\n")
    print(f"| Status | Count |")
    print(f"|---|---|")
    print(f"| EMBEDDED (file is rendered by at least one page) | **{len(embedded)}** |")
    print(
        f"| DOCUMENTED-BUT-NOT-EMBEDDED (basename mentioned but no `![](...)`) | **{len(documented_not_embedded)}** |"
    )
    print(
        f"| ORPHAN (asset exists, no page references it at all) | **{len(orphan)}** |"
    )
    print(
        f"| BROKEN-EMBED (markdown points to non-existent file) | **{len(broken_embeds)}** |"
    )
    print()

    if documented_not_embedded:
        print(
            f"## Defect Class A — DOCUMENTED-BUT-NOT-EMBEDDED ({len(documented_not_embedded)})\n"
        )
        print(
            "Files that ARE mentioned in markdown but are NEVER actually embedded as images.\n"
        )
        print("| Asset | Mentioned in (file:line) |")
        print("|---|---|")
        for asset, ms in documented_not_embedded:
            rel_asset = asset.relative_to(REPO)
            mention_str = "<br>".join(
                f"`{md.relative_to(REPO)}:{ln}`" for md, ln, _ in ms[:5]
            )
            if len(ms) > 5:
                mention_str += f"<br>... and {len(ms) - 5} more"
            print(f"| `{rel_asset}` | {mention_str} |")
        print()

    if orphan:
        print(f"## Defect Class B — ORPHAN ({len(orphan)})\n")
        print(
            "Files committed under docs/assets/ that NO markdown page references at all.\n"
        )
        orphans_by_dir: dict[Path, list[Path]] = defaultdict(list)
        for o in orphan:
            orphans_by_dir[o.parent].append(o)
        for dirp in sorted(orphans_by_dir.keys()):
            rel_dir = dirp.relative_to(REPO)
            print(f"### `{rel_dir}/` ({len(orphans_by_dir[dirp])} orphan)")
            for o in sorted(orphans_by_dir[dirp]):
                print(f"- `{o.name}`")
            print()

    if broken_embeds:
        print(f"## Defect Class C — BROKEN-EMBED ({len(broken_embeds)})\n")
        print("`![](...)` or `<img>` references that point to non-existent files.\n")
        print("| File | Line | Kind | Relpath |")
        print("|---|---|---|---|")
        for md, lineno, relpath, kind in broken_embeds[:50]:
            print(f"| `{md.relative_to(REPO)}` | {lineno} | {kind} | `{relpath}` |")
        if len(broken_embeds) > 50:
            print(f"\n(... {len(broken_embeds) - 50} more)")
        print()

    print(f"## Defect Class D — LAB-GUIDE PNG vs EMBED MISMATCH\n")
    lab_assets_root = ASSETS / "troubleshooting"
    lab_guides_dir = DOCS / "troubleshooting" / "lab-guides"
    rows = []
    if lab_assets_root.is_dir():
        for sub in sorted(lab_assets_root.iterdir()):
            if not sub.is_dir():
                continue
            pngs = sorted(
                p
                for p in sub.rglob("*")
                if p.is_file() and p.suffix.lower() in IMG_EXTS
            )
            if not pngs:
                continue
            lab_name = sub.name
            candidate = lab_guides_dir / f"{lab_name}.md"
            md_exists = candidate.exists()
            embed_count = 0
            if md_exists:
                for target, refs in embeds_by_target.items():
                    if target.is_relative_to(sub):
                        for md_file, _ln in refs:
                            if md_file == candidate:
                                embed_count += 1
            total_embeds_into_dir = sum(
                len(refs)
                for target, refs in embeds_by_target.items()
                if target.is_relative_to(sub)
            )
            mismatch = (
                "OK"
                if (md_exists and embed_count >= len(pngs))
                else ("LAB-MISSING" if not md_exists else "GAP")
            )
            rows.append(
                (
                    lab_name,
                    len(pngs),
                    md_exists,
                    embed_count,
                    total_embeds_into_dir,
                    mismatch,
                )
            )
    rows.sort(key=lambda r: (r[5] == "OK", -r[1]))
    print(
        "| Lab dir | PNGs | Lab guide exists | Embeds from lab guide | Total embeds (any page) | Status |"
    )
    print("|---|---:|:---:|---:|---:|---|")
    for name, n_png, md_exists, e_lab, e_total, status in rows:
        flag = (
            "" if status == "OK" else ("(GAP)" if status == "GAP" else "(NO LAB GUIDE)")
        )
        print(
            f"| `{name}` | {n_png} | {'yes' if md_exists else 'NO'} | {e_lab} | {e_total} | **{status}** {flag} |"
        )
    print()

    n_defects = len(documented_not_embedded) + len(orphan) + len(broken_embeds)
    print(f"\n---\n**Total defects (A+B+C): {n_defects}**")
    return 0 if n_defects == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
