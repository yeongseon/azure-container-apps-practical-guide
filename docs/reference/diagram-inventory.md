---
title: Diagram Inventory and Migration Manifest
description: Operational inventory of all architectural diagrams, visual assets, and ownership batches for Azure Container Apps.
---

# Diagram Inventory and Migration Manifest

This reference documents the complete inventory of technical diagrams across the Azure Container Apps guide. It establishes an audited baseline for migration tracking under parent issue #399, mapping every diagram to an explicit child issue while recording syntax types, candidate genres, declared provenance, and data-quality findings.

## Purpose and Scope

The diagram inventory provides a mechanical, reproducible accounting of every visual asset in the repository. It serves several specific operational purposes:

1. Tracking migration ownership: Assigns each diagram to exactly one migration task with documented rationale.
2. Surface analysis: Quantifies syntax types, common structural patterns, and candidate genres across documentation sections.
3. Quality auditing: Flags missing identifier comments, frontmatter omissions, and naming collisions before migration begins.

What this inventory is not:

- It is not an automated migration compiler or rendering engine.
- It is not an architectural validation of Microsoft Learn provenance.
- It is not a definitive declaration of semantic genres.

Detailed manifest records are checked in as machine-readable JSON in [`docs/reference/diagram-manifest.json`](diagram-manifest.json), adhering to schema [`docs/reference/diagram-manifest.schema.json`](diagram-manifest.schema.json). For architectural background and alternatives analysis, refer to the companion [Architecture Decision Record](adr-diagram-composition.md).

## Counting Policy

The inventory applies the normative counting policy defined in the manifest baseline:

Every Mermaid fence in a tracked Markdown file is one occurrence. An asset referenced N times is one asset with N usages. Two fences with equal text are two occurrences.

At the baseline commit recorded in the manifest (`baseline.base_commit`), the repository contains the following; the generated tables below are authoritative if prose and tables ever diverge:

- 479 total Mermaid occurrences across 386 tracked Markdown files.
- 475 published occurrences within user-facing documentation under `docs/`.
- 4 repository-only occurrences outside published paths (`AGENTS.md` and lab READMEs).
- 3 excluded occurrences with documented rationales.
- 476 migration-required occurrences requiring active migration.
- 0 non-Mermaid published visuals.

## Inventory Tables

The following summary tables are generated directly from `docs/reference/diagram-manifest.json` by running `python3 scripts/diagram_inventory.py --write`.

### Occurrences by Section

<!-- BEGIN GENERATED: diagram-inventory:section -->
| Section | Count |
|---|---:|
| best-practices | 34 |
| contributing | 1 |
| docs-root | 1 |
| language-guides | 128 |
| operations | 35 |
| platform | 79 |
| reference | 8 |
| repository | 4 |
| start-here | 12 |
| troubleshooting | 177 |
<!-- END GENERATED: diagram-inventory:section -->

### Occurrences by Mermaid Syntax Type

<!-- BEGIN GENERATED: diagram-inventory:type -->
| Type | Count |
|---|---:|
| flowchart | 402 |
| graph | 61 |
| pie | 2 |
| quadrantChart | 1 |
| sequenceDiagram | 9 |
| stateDiagram-v2 | 4 |
<!-- END GENERATED: diagram-inventory:type -->

### Migration-Required Occurrences by Batch

<!-- BEGIN GENERATED: diagram-inventory:batch -->
| Batch | Count |
|---|---:|
| 401 | 2 |
| 402 | 32 |
| 403 | 6 |
| 404 | 48 |
| 405 | 31 |
| 406 | 176 |
| 407 | 181 |
<!-- END GENERATED: diagram-inventory:batch -->

### Asset Exclusions by Group

<!-- BEGIN GENERATED: diagram-inventory:exclusions -->
| Exclusions | Count |
|---|---:|
| branding | 2 |
| lab-evidence | 302 |
| legacy-portal-screenshots | 88 |
| metrics-evidence | 45 |
| portal-screenshots | 0 |
<!-- END GENERATED: diagram-inventory:exclusions -->

### Data-Quality Exceptions Summary

<!-- BEGIN GENERATED: diagram-inventory:exceptions -->
| Exceptions | Count |
|---|---:|
| duplicate_ids_on_page | 0 |
| fences_without_frontmatter_entry | 5 |
| frontmatter_entries_without_fence | 16 |
| frontmatter_unparseable | 1 |
| id_reused_on_other_pages | 18 |
| missing_id_comment | 4 |
| unclassified_assets | 0 |
| unclosed_fences | 0 |
| unresolved_overlaps | 0 |
<!-- END GENERATED: diagram-inventory:exceptions -->

## Batch Map and Ownership Rules

Every migration-required diagram is assigned to exactly one child issue under parent initiative #399. The assignment engine evaluates explicit rules derived from each issue's scope:

- Batch #401 (Phase P1, 2 diagrams): Platform core architecture base diagram in `docs/platform/architecture/index.md` and shared MkDocs composition contract.
- Batch #402 (Phase P3a, 32 diagrams): Core platform networking covering ingress, egress control, virtual network integration, private endpoints, Application Gateway, and internal service routing.
- Batch #403 (Phase P3b, 6 diagrams): Dedicated Azure Container Registry (ACR) network paths A through E (`acr-network-path-selection.md` and lab guides `acr-network-path-*`).
- Batch #404 (Phase P3c, 48 diagrams): Revision lifecycle, scaling mechanisms, event scalers, health probes, and runtime operational flows.
- Batch #405 (Phase P3d, 31 diagrams): Managed identities, Key Vault references, storage mounts, image security, and Dapr component integration.
- Batch #406 (Phase P3e, 176 diagrams): Troubleshooting architecture, methodology decision trees, diagnostic playbooks, KQL query pipelines, and hands-on lab guides.
- Batch #407 (Phase P3f, 181 diagrams): Residual diagrams across Start Here, Language Guides, general operations, Best Practices, Reference, and supporting published documentation.
- Batch #408 (Phase P4, 0 diagrams): CI enforcement, visual regression gates, and build validation. Issue #408 owns zero diagrams directly (`owns_diagrams: false`).

### Rule Priority and Residual Assignments

Assignments follow a deterministic resolution chain: reviewed manual overrides take precedence, followed by highest-priority matching rules, followed by explicit residual allocations.

Residual assignments exist because general sections (notably Language Guides with 128 diagrams) teach implementation workflows across multiple runtimes rather than defining core platform topology. Assigning these to #407 ensures every diagram has a clear, documented owner without obscuring platform ownership.

### ACR Path A–E and Lab Representation Grouping

The five ACR network path scenarios represent distinct architectural topologies:

- Path A: Public ACR with Azure Firewall SNAT and IP allowlisting.
- Path B: Private Endpoint direct to ACR.
- Path C: Private Endpoint with forced inspection routing.
- Path D: Record-level zone authority and split-brain resolution.
- Path E: Custom DNS forwarder bypass topologies.

These five scenarios are assigned specifically to #403 because their diagrams document tightly coupled variations of the same registry connectivity problem. Generic troubleshooting labs and evidence packs remain under #406.

## Non-Mermaid Visuals

An exhaustive search across `docs/` for non-Mermaid drawing and visualization elements (`<svg`, `<img`, `<iframe`, `<script`, `cytoscape`, `d3`, `vis-network`, `plotly`) confirmed zero non-Mermaid published diagrams in the repository:

- Two vector SVG files exist: `docs/assets/logo.svg` and `docs/assets/favicon.svg`. These provide site branding and icons rather than architectural illustrations.
- No embedded `<canvas>` elements, Cytoscape graph datasets, D3 charts, or external visualization scripts are present.
- All 435 raster assets (`.png` and `.webp`) are Azure Portal screenshots, Log Analytics query captures, or command output evidence.

## Quality of Classification

### Heuristic Genre Candidates

Mermaid syntax directly decides unambiguous typed diagrams: sequence diagrams become `sequence`, state diagrams become `state`, and pie or quadrant charts become `chart`.

For the 463 flowchart and graph blocks (96.7 % of all diagrams), genre assignment is an unreviewed heuristic candidate:

- Blocks with decision shapes (`{...}`) or explicit Yes/No edge labels predict `decision`.
- Blocks with `subgraph` boundaries and no decision nodes predict `topology`.
- All other flowcharts predict `flow`.
- Ambiguous signals or conflicting markers predict `unknown` with `needs_review: true`.

A stratified random validation sample (seed 400, sample size n=62) measured agreement between heuristic predictions and manual human review:

- Syntax-decided genres achieved 16/16 agreement (100 %).
- Heuristic flowchart candidates achieved 38/46 agreement (82.6 %).
- Non-agreement occurred primarily when dependency topologies lacked subgraphs (predicting flow) or deployment pipelines used subgraphs for sequencing (predicting topology).

Because the sample was stratified rather than proportional, this measurement is an advisory signal rather than a statistical population estimate. All classifications remain labeled `classification.review_status: unreviewed` until individual migration batches review them.

### Provenance Extraction

The inventory extracts declared frontmatter citations from `content_sources.diagrams[]` verbatim. Across 479 occurrences:

- 474 occurrences declare explicit frontmatter metadata.
- 5 occurrences lack frontmatter metadata (the Mermaid example in `AGENTS.md`, the pie chart of a generated dashboard, and 3 lab READMEs without a diagram ID comment).

In accordance with the repository evidentiary standards, metadata extraction is not source verification. The inventory records what authors declared without verifying external Microsoft Learn URLs or empirical accuracy.

## Data-Quality Findings and Remediation

The scanner detected three specific categories of metadata debt:

1. Frontmatter entries without fences: 16 lab guides declare diagram metadata in frontmatter for diagrams that do not appear in the document body. The reason is not recorded. Child batch owners decide whether to add the diagram or remove the stale entry.
2. Reused diagram IDs across pages: 18 diagram IDs (such as `architecture`, `deployment-workflow`, and `query-pipeline`) are reused across different documents. The manifest resolves collisions by combining page path and diagram ID into a unique primary key (`<page>#<id>`).
3. Fences without frontmatter entries: 5 fences lack frontmatter entries. These are either non-published documentation aids or generated dashboards.

## Initial Rendering Test and Binary Screenshots Decision

A one-time rendering test was run on 2026-10-30 with throwaway tooling outside the repository tree, on `main` at `944b237` (no diagram block changed between it and the baseline commit of the manifest). The site was built and every published Mermaid block was rendered in headless Chrome 145 with the Mermaid library MkDocs Material loads (`mermaid@11`, which resolved to 11.17.2 at the time):

- 474 out of 475 published blocks rendered without errors.
- 1 block failed to parse (`docs/platform/deployment-scenarios.md`, an unquoted label containing parentheses); it was tracked in issue #412 and fixed by PR #414.
- Across the three sibling guides (475 + 398 + 568 = 1,441 published blocks) the same test found 11 parse errors (Container Apps 1, App Service 8, Functions 2; the sibling fixes are tracked in App Service #290 and Functions #218). The regex-based `validate_mermaid_syntax.py` caught none of them, and a blocking render gate belongs to #408.

The rendered PNG images for Container Apps total 15.9 MB (approximately 33 KiB per diagram). Storing these pre-rendered binary files in git was rejected because:

- It would permanently inflate repository size with derived binary artifacts.
- The repository's image merge gates (caption-to-image match and final-image PII verification in `AGENTS.md`) are written for evidence screenshots, so hundreds of derived renderings would add review work for no evidence value.
- A render baseline can be measured again from the commit recorded in `baseline.base_commit` and the per-block `source_sha256` values with any headless-browser harness; this inventory commits no such harness.

## Command Reference

The inventory workflow relies on `scripts/diagram_inventory.py`, requiring Python 3.11 and PyYAML.

### Validating the Inventory (Blocking CI)

Run the consistency check during automated CI validation:

```bash
python3 scripts/diagram_inventory.py --check
```

This verifies that the manifest conforms to the JSON schema, keys are unique, batch counts reconcile with totals, rule hashes match, and markdown blocks in this document match the generated tables.

### Regenerating the Manifest

Update the manifest and generated documentation blocks after adding or modifying diagrams:

```bash
python3 scripts/diagram_inventory.py --write
```

To pin the manifest baseline to a specific commit:

```bash
python3 scripts/diagram_inventory.py --write --base-commit "$(git rev-parse HEAD)"
```

### Checking Tree Drift (Advisory)

Inspect changes between the working tree and the committed baseline:

```bash
python3 scripts/diagram_inventory.py --verify-tree
```

### Displaying Summary Metrics

Print high-level counts and totals:

```bash
python3 scripts/diagram_inventory.py --summary
```

## See Also

- [ADR: Diagram Composition and Shared Topology Strategy](adr-diagram-composition.md)
- [Diagram Manifest (JSON)](diagram-manifest.json)
- [Parent Initiative #399](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/399)
- [Inventory Task Issue #400](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/400)

## Sources

- [Mermaid Documentation](https://mermaid.js.org/)
