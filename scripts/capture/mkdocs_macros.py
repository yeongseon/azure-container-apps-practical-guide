"""mkdocs-macros module exposing the `shot()` macro.

Configured in mkdocs.yml with custom Jinja delimiters `[[[ ]]]` (see the
`macros` plugin block) so it never collides with the many `{{ ... }}` sequences
already in the docs (GitHub Actions `${{ }}`, Mermaid hexagon nodes `X{{ }}`).

Docs reference a screenshot by its stable manifest id:

    [[[ shot("01-storage-networking-all-networks") ]]]

which renders the correct relative image path plus alt text, so re-capturing a
blade never requires editing any markdown.
"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from .screenshot_lib import Manifest
except ImportError:
    Manifest = importlib.import_module("screenshot_lib").Manifest

_manifest = Manifest()


def define_env(env: Any) -> None:
    @env.macro
    def shot(shot_id: str) -> str:
        entry = _manifest.get(shot_id)
        src_uri = env.page.file.src_uri
        depth = src_uri.count("/")
        prefix = "../" * depth
        alt = entry.alt.replace("\\", r"\\").replace("]", r"\]").replace("\n", " ")
        return f"![{alt}]({prefix}assets/{entry.file})"
