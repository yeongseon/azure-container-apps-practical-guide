"""Shared scope policy for ``content_validation`` enforcement.

Defines which markdown files in ``docs/`` are required to carry the
``content_validation:`` frontmatter block (factual-claim pages) versus those
that are out of scope for the dashboard and cleanup tool (navigation indexes,
KQL packs, lab guides, tutorials, reference look-ups, and other non-claim
content).

Out-of-scope pages are not counted by
``scripts/generate_content_validation_status.py`` and are not required to
carry a ``content_validation`` block. Legacy blocks may still exist on some
out-of-scope pages from before this scope policy was formalized; they are
accepted but not tracked, and will be reviewed in a follow-up editorial pass.
New out-of-scope pages should not add the block.

Imported by:

- ``scripts/generate_content_validation_status.py``
- ``scripts/remove_tautological_validation.py``

The policy MUST stay in sync with ``AGENTS.md`` §Text Content Validation.
If you change the rules here, update ``AGENTS.md`` in the same commit.
"""

from __future__ import annotations

from pathlib import Path
from typing import Union

# ---------------------------------------------------------------------------
# Scope policy
# ---------------------------------------------------------------------------

# Sections under ``docs/`` that may contain factual-claim pages. Files outside
# these sections (for example ``docs/start-here/``, ``docs/language-guides/``,
# ``docs/reference/``, ``docs/contributing/``, ``docs/index.md``) are out of
# scope regardless of their name.
SCANNED_SECTIONS: frozenset[str] = frozenset(
    {
        "platform",
        "best-practices",
        "operations",
        "troubleshooting",
    }
)

# Subpaths under ``SCANNED_SECTIONS`` that are EXEMPT because they are
# reference-lookup query packs or lab evidence with their own integrity model.
# Paths use forward-slash form and a trailing slash to make prefix matches
# unambiguous (``troubleshooting/kql/`` matches ``troubleshooting/kql/foo.md``
# but not a hypothetical ``troubleshooting/kqlnotes.md``).
EXCLUDED_SUBPATHS: tuple[str, ...] = (
    "troubleshooting/kql/",
    "troubleshooting/lab-guides/",
)

# Navigation landing pages within ``SCANNED_SECTIONS`` that are EXEMPT.
# These pages introduce a section but make no factual assertions of their own.
#
# Factual subsection landing pages (for example
# ``platform/architecture/index.md`` and ``platform/networking/index.md``) are
# intentionally NOT in this list -- they carry verifiable claims and therefore
# REQUIRE ``content_validation`` like any other factual-claim page.
NAVIGATION_INDEXES: frozenset[str] = frozenset(
    {
        "platform/index.md",
        "best-practices/index.md",
        "operations/index.md",
        "operations/deployment/index.md",
        "troubleshooting/index.md",
        "troubleshooting/first-10-minutes/index.md",
        "troubleshooting/playbooks/index.md",
    }
)

# ---------------------------------------------------------------------------
# Tautological-claim policy
# ---------------------------------------------------------------------------

# Marker text for placeholder ``core_claims`` such as
# "This page uses Microsoft Learn as the primary source basis ...".
# Matched case-insensitively via :func:`is_tautological_text`.
TAUTOLOGICAL_CLAIM_MARKER: str = "primary source basis"


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------


def is_in_scope(rel_path: Union[Path, str]) -> bool:
    """Return ``True`` if ``rel_path`` requires a ``content_validation`` block.

    ``rel_path`` must be relative to ``docs/``. The policy is applied in this
    order:

    1. The first path component must be a ``SCANNED_SECTION``.
    2. The path must NOT start with any ``EXCLUDED_SUBPATHS`` prefix.
    3. The path must NOT be a ``NAVIGATION_INDEXES`` entry.

    Examples:

    >>> from pathlib import Path
    >>> is_in_scope("platform/scaling.md")
    True
    >>> is_in_scope("platform/architecture/index.md")  # factual subsection landing
    True
    >>> is_in_scope("platform/networking/index.md")  # factual subsection landing
    True
    >>> is_in_scope("platform/index.md")  # navigation
    False
    >>> is_in_scope("troubleshooting/playbooks/cold-start.md")
    True
    >>> is_in_scope("troubleshooting/kql/restarts/index.md")  # excluded subpath
    False
    >>> is_in_scope("troubleshooting/lab-guides/memory-pressure.md")
    False
    >>> is_in_scope("language-guides/python/tutorial/01-deploy.md")  # outside sections
    False
    >>> is_in_scope("start-here/overview.md")  # outside sections
    False
    """
    rel = Path(rel_path)
    parts = rel.parts
    if not parts or parts[0] not in SCANNED_SECTIONS:
        return False

    posix = rel.as_posix()
    if any(posix.startswith(prefix) for prefix in EXCLUDED_SUBPATHS):
        return False

    if posix in NAVIGATION_INDEXES:
        return False

    return True


def is_tautological_text(text: object) -> bool:
    """Return ``True`` if ``text`` contains the tautological marker.

    The match is case-insensitive (uses :py:meth:`str.casefold`) so variants
    like ``"Primary Source Basis"`` or ``"PRIMARY SOURCE BASIS"`` are caught.
    Non-string inputs return ``False``.

    >>> is_tautological_text("uses Microsoft Learn as the primary source basis")
    True
    >>> is_tautological_text("PRIMARY SOURCE BASIS")
    True
    >>> is_tautological_text("Container Apps supports KEDA-based autoscaling")
    False
    >>> is_tautological_text(None)
    False
    """
    if not isinstance(text, str):
        return False
    return TAUTOLOGICAL_CLAIM_MARKER.casefold() in text.casefold()


__all__ = [
    "SCANNED_SECTIONS",
    "EXCLUDED_SUBPATHS",
    "NAVIGATION_INDEXES",
    "TAUTOLOGICAL_CLAIM_MARKER",
    "is_in_scope",
    "is_tautological_text",
]
