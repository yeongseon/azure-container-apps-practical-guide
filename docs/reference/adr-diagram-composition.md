---
title: ADR - Diagram Composition and Shared Topology Strategy
description: Architecture decision record proposing the diagram composition approach and reuse boundaries for Azure Container Apps.
---

# ADR: Diagram Composition and Shared Topology Strategy

## Status

Proposed (pending results of App Service proof of concept #283)

## Context and Problem Statement

The Azure practical guide series maintains hundreds of diagrams to explain cloud architectures, operational workflows, and failure modes. Across the three sibling guides, the diagram footprint measured on 2026-10-30 at each guide's `main` (Container Apps `9e11a97`, App Service `3fd0626`, Functions `f643166`) is:

| Guide | Tracked Mermaid Occurrences | Published Blocks under docs/ | flowchart and graph Share | sequence, state, chart Share |
|---|---:|---:|---:|---:|
| Azure Container Apps | 479 | 475 | 463 (96.7 %) | 16 (3.3 %) |
| Azure App Service | 399 | 398 | 355 (89.0 %) | 44 (11.0 %) |
| Azure Functions | 569 | 568 | 526 (92.4 %) | 43 (7.6 %) |

Today, every diagram is hand-authored as inline Mermaid within Markdown documents. This brings maintenance challenges:

1. Repeated topology fragments: Container Apps diagrams repeatedly define identical resource clusters such as `Container Apps Environment`, `Microsoft Entra ID`, `Azure Container Registry`, and `Azure Key Vault`. In the manifest candidate component extraction, `microsoft entra id` appears in 61 diagrams, `container apps environment` in 44, and `azure container registry` in 41. Updating a core platform topology requires editing dozens of independent files.
2. Divergent visual conventions: Sibling repositories use slightly different shapes, styling classes, and edge notations for the same Azure primitives.
3. Data quality debt: The initial inventory identified 16 frontmatter entries without corresponding fences, 18 diagram IDs reused across multiple pages, and 5 fences missing frontmatter provenance entries.

The parent issue (#399) aims to replace diagrams using reusable topology and scenario overlays. However, umbrella issue instructions state clearly: never maintain three divergent copied generators, reconcile reuse decisions through a small cross-guide contract rather than copied code, and adopt a shared package only after demonstrated reuse.

We need an architectural strategy that balances reuse against preserving each diagram's original semantics without over-engineering the documentation toolchain.

## Decision Drivers

- Preserve diagram semantics: Every diagram conveys a specific instructional goal, troubleshooting step, or failure mode. Shared composition must not flatten subtle scenario-specific wiring into generic box drawings.
- Avoid premature abstraction: Building a bespoke diagram compiler before proving actual reuse across guides creates technical debt.
- Toolchain simplicity and local preview: Authors and reviewers must be able to edit Markdown and preview documentation locally without complex build pipelines or external runtimes.
- Safe cross-guide contract: Sibling repositories must share interchange schemas and inventory tools without tight code coupling.

## Considered Options

### Option A: Keep Inline Mermaid as Reviewed Source of Truth

Maintain all diagrams as native Mermaid code blocks directly inside Markdown documents. Improve consistency solely through linting and authoring guidelines.

- Good: Zero build overhead. Works natively with MkDocs Material, GitHub web preview, and editor extensions. Full freedom to tailor every edge and label to the immediate instructional text.
- Bad: High maintenance duplication. Fixes to a common subnet topology or service endpoint pattern must be manually applied across dozens of documents. Drift between guides is inevitable.

### Option B: MkDocs Macros or Snippets for Shared Topology Fragments

Use MkDocs plugins (such as `mkdocs-macros-plugin` or `pymdownx.snippets`) to inject shared Mermaid subgraphs or node definitions into page templates.

- Good: Minimal toolchain changes. Reuses existing Markdown preprocessing mechanisms.
- Bad: Snippet concatenation inside Mermaid blocks creates fragile syntax boundaries. Indentation errors and identifier clashes between snippet fragments make debugging difficult. It does not provide structural validation or typed overlays.

### Option C: Small YAML-to-Mermaid Composition Renderer

Define base topologies (such as a Container Apps environment with Virtual Network integration) and scenario overlays (such as normal traffic, ingress failure, or DNS split-brain) in structured YAML. A small renderer compiles these declarations into native Mermaid blocks.

- Good: Clear separation between topology definitions and scenario overlays. Enables mechanical consistency, automated accessibility checks, and structured diffs.
- Bad: Adds a compilation step to documentation generation. Authors must learn an intermediate schema instead of writing familiar Mermaid code.

### Option D: Standalone Shared Package Across Repositories

Build an independent npm or Python library published to a registry, consumed by all three guides as an external build dependency.

- Good: Strongest code deduplication. Enforces a unified schema across all guides.
- Bad: Violates umbrella issue guidelines. A shared package is explicitly ruled out until cross-guide reuse is demonstrated in practice. It introduces release lifecycle overhead, version pinning friction, and cross-repo coordination delays.

## Decision Outcome

Proposed: Keep inline Mermaid as the reviewed source of truth, keep typed genres hand-authored, and evaluate Option B versus Option C within the App Service proof of concept (#283) before adopting any generator for Container Apps.

Specifically:

1. Inventory first: For P0, maintain `scripts/diagram_inventory.py` as a scanning, consistency-validation, and reporting tool that never renders, converts, or verifies source provenance. `--write` writes the manifest and generated inventory-page blocks; `--check` validates consistency, not provenance. `--verify-tree` compares extracted records with the baseline, not extraction completeness; `--check` reports `unrecognized_mermaid_fences`. The script is copied byte-identically into sibling repositories and pinned by its SHA-256 digest in each repository's manifest (`docs/reference/diagram-manifest.json`).
2. Interchange contract: Schema v1 (`docs/reference/diagram-manifest.schema.json`) serves as the immutable cross-guide contract. All repositories share the same baseline manifest structure, primary key format, and provenance rules. Repository-specific batch assignments and path rules stay separated in `scripts/diagram_inventory_rules.json`.
3. Hand-authored typed genres: Specialized genres (sequenceDiagram, stateDiagram-v2, pie charts, quadrant charts) represent 3.3 % of Container Apps diagrams (16 blocks). These convey precise temporal or state-machine semantics and will permanently remain hand-authored Mermaid.
4. Heuristic candidate genres: The remaining 96.7 % (463 flowcharts and graphs) are classified heuristically into flow, decision, or topology candidates. These classifications are advisory work-routing candidates, not confirmed architectural genres. Each child migration batch (#401 to #407) will evaluate and confirm genre during implementation.
5. Defer shared package and renderer: No composition renderer, macro framework, or shared package will be introduced in Container Apps until the App Service prototype (#283) proves viable on one base topology, two extensions, and failure overlays.

## Over-Engineering Assessment

What this project deliberately does not do in P0:

1. No diagram-as-code compiler: We do not introduce a custom domain-specific language, abstract syntax tree parser, or diagram generation runtime.
2. No bulk diagram conversion: Existing Mermaid blocks remain untouched during P0. Migration proceeds in controlled thematic batches (#401 through #407).
3. No committed derived PNG screenshots: Storing pre-rendered PNG screenshots for all 475 published diagrams would add approximately 15.9 MB of derived binary artifacts to git history (measured average of 33 KiB per diagram in headless Chrome 145). The repository's image merge gates (caption-to-image match and final-image PII verification in `AGENTS.md`) are written for evidence screenshots, so hundreds of derived renderings would add review work for no evidence value. A render baseline can be measured again from the commit recorded in `baseline.base_commit` and the per-block `source_sha256` values with any headless-browser harness; P0 commits no such harness.
4. No automated provenance verification: The scanner extracts verbatim frontmatter citations but does not claim that source documentation URLs or justifications are empirically verified.

## Consequences and Risks

### Positive Consequences

- Clean baseline: Provides a mechanical inventory of all 479 Mermaid occurrences: one owning batch for each of the 476 migration-required occurrences, a stated reason for each of the 3 exclusions, zero unresolved rule overlaps and counted data-quality exceptions.
- Toolchain stability: Python standard library plus PyYAML require no external binary dependencies for inventory scanning.
- Independent execution: Container Apps child batches can proceed with clear boundaries without waiting for cross-repository package releases.

### Risks and Mitigations

- Risk: The App Service prototype (#283) may find that composition macros or YAML overlays are too rigid for nuanced operational diagrams.
  - Mitigation: The fallback position is Option A (curated inline Mermaid with shared style guidelines), which carries zero migration lock-in.
- Risk: Reused diagram IDs across multiple pages cause confusion during migration tracking.
  - Mitigation: The manifest primary key combines page path and diagram ID (`<page>#<id>`), ensuring global uniqueness regardless of local naming collisions.
- Risk: Heuristic classification mislabels topology diagrams as flows or decisions.
  - Mitigation: The manifest marks all genre classifications as unreviewed candidates (`classification.review_status: unreviewed`). Child batch owners review actual diagram semantics before refactoring.
- Risk: A line-based scanner cannot fully reproduce the site's Markdown container rendering.
  - Mitigation: It errs toward reporting: `blockquote`, `list-marker`, and `indented` findings block `--check`; `html-comment` and plain `indented-code` findings are informational. `--write` warns once per page for blocking findings only. The separate Mermaid format validator already rejects indented Mermaid fences; examples belong inside longer outer fences. See the [inventory's known limitations](diagram-inventory.md#command-reference), including extra info words, prefixed comments, and conservative nested-container over-reporting. Classification was checked locally against Python-Markdown 3.10.2 / pymdownx 10.21.3 on 2026-10-30; the experiment is not committed.

## See Also

- [Diagram Inventory](diagram-inventory.md)
- [Diagram Manifest Schema](diagram-manifest.schema.json)
- [Parent Initiative #399](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/399)
- [App Service Shared PoC #283](https://github.com/yeongseon/azure-app-service-practical-guide/issues/283)

## Sources

- [Mermaid Documentation](https://mermaid.js.org/)
