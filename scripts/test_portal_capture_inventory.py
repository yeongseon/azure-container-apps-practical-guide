#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any, final

SCRIPT = Path(__file__).with_name("portal_capture_inventory.py")
SPEC = importlib.util.spec_from_file_location("portal_capture_inventory", SCRIPT)
assert SPEC and SPEC.loader
inventory = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inventory)


@final
class PortalCaptureInventoryTests(unittest.TestCase):
    directory: tempfile.TemporaryDirectory[str] | None = None
    root: Path = Path()

    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "scripts/capture").mkdir(parents=True)
        (self.root / "docs/assets/troubleshooting/demo").mkdir(parents=True)
        (self.root / "docs/troubleshooting/lab-guides").mkdir(parents=True)
        (self.root / "scripts/portal_capture_inventory_rules.json").write_text(
            json.dumps(
                {
                    "version": 1,
                    "image_extensions": [".png", ".webp"],
                    "excluded_assets": [],
                    "excluded_page_globs": ["docs/contributing/**"],
                    "portal_terms": ["portal evidence", "azure portal"],
                    "stale_after_days": 180,
                    "tracked_batches": [],
                }
            )
        )

    def write_manifest(self, screenshots: list[dict[str, Any]] | None = None) -> None:
        (self.root / "scripts/capture/manifest.yaml").write_text(
            "meta:\n  version: 1\nscreenshots:\n"
            + ("".join(f"  - {json.dumps(item)}\n" for item in screenshots) if screenshots else "  []\n")
        )

    def test_inventory_separates_legacy_missing_and_manifest_captures(self) -> None:
        self.write_manifest(
            [{"id": "registered", "file": "docs/assets/troubleshooting/demo/registered.webp", "verified": "2026-10-01"}]
        )
        (self.root / "docs/assets/troubleshooting/demo/legacy.png").write_bytes(b"legacy")
        (self.root / "docs/assets/troubleshooting/demo/registered.webp").write_bytes(b"registered")
        (self.root / "docs/legacy.md").write_text(
            "# Legacy\n\n## Portal Evidence\n\n![Useful state](assets/troubleshooting/demo/legacy.png)\n"
        )
        (self.root / "docs/missing.md").write_text("# Missing\n\nUse the Azure Portal.\n")
        (self.root / "docs/registered.md").write_text(
            '# Registered\n\n## Portal Evidence\n\n[[[ shot("registered") ]]]\n'
        )
        data = inventory.build_inventory(self.root, "abc123", dt.date(2026, 11, 7))
        states = {page["path"]: page["state"] for page in data["pages"]}
        self.assertEqual(states["docs/legacy.md"], "manual-blocked")
        self.assertEqual(states["docs/missing.md"], "missing")
        self.assertEqual(states["docs/registered.md"], "captured")
        self.assertEqual(data["summary"]["legacy_assets"], 1)

    def test_unknown_shot_and_stale_manifest_are_not_captured(self) -> None:
        self.write_manifest(
            [{"id": "old", "file": "docs/assets/troubleshooting/demo/old.webp", "verified": "2025-01-01"}]
        )
        (self.root / "docs/assets/troubleshooting/demo/old.webp").write_bytes(b"old")
        (self.root / "docs/unknown.md").write_text(
            '# Unknown\n\nPortal evidence: [[[ shot("missing-id") ]]]\n'
        )
        (self.root / "docs/stale.md").write_text('# Stale\n\nPortal evidence: [[[ shot("old") ]]]\n')
        data = inventory.build_inventory(self.root, "abc123", dt.date(2026, 11, 7))
        pages = {page["path"]: page for page in data["pages"]}
        self.assertEqual(pages["docs/unknown.md"]["state"], "missing")
        self.assertEqual(pages["docs/stale.md"]["state"], "stale")

    def test_fenced_examples_do_not_create_references(self) -> None:
        self.write_manifest()
        (self.root / "docs/example.md").write_text(
            '# Example\n\nAzure Portal example:\n\n```markdown\n![Example](assets/missing.png)\n```\n'
        )
        data = inventory.build_inventory(self.root, "abc123", dt.date(2026, 11, 7))
        page = next(page for page in data["pages"] if page["path"] == "docs/example.md")
        self.assertEqual(page["state"], "missing")
        self.assertEqual(page["broken_references"], [])

    def test_reuse_and_inconsistent_alt_are_review_candidates(self) -> None:
        self.write_manifest()
        image = self.root / "docs/assets/troubleshooting/demo/legacy.png"
        image.write_bytes(b"legacy")
        (self.root / "docs/one.md").write_text(
            "# One\n\nPortal evidence.\n\n![First claim](assets/troubleshooting/demo/legacy.png)\n"
        )
        (self.root / "docs/two.md").write_text(
            "# Two\n\nPortal evidence.\n\n![Second claim](assets/troubleshooting/demo/legacy.png)\n"
        )
        data = inventory.build_inventory(self.root, "abc123", dt.date(2026, 11, 7))
        asset = next(asset for asset in data["assets"] if asset["path"].endswith("legacy.png"))
        self.assertEqual(asset["reference_count"], 2)
        self.assertEqual(
            asset["caption_alt_review_candidates"],
            ["reused_across_pages", "inconsistent_alt_text"],
        )
        self.assertEqual(asset["final_image_visual_verification"], "not_collected")


if __name__ == "__main__":
    unittest.main()
