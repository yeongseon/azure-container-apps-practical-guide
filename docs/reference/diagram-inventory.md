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

Non-Mermaid visuals are reported separately; `totals.by_batch` counts Mermaid migration-required occurrences only, not visual records.

At the baseline commit recorded in the manifest (`baseline.base_commit`), the repository contains the following; the generated tables below are authoritative if prose and tables ever diverge:

- 479 occurrences in 386 diagram-bearing Markdown files. The current tracked tree has 495 Markdown files (`git ls-files '*.md' | wc -l`).
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

Asset groups are path-based claims, not visual verification. Wildcard `paths` entries claim only raster images (`.png`, `.webp`, `.jpg`, `.jpeg`, `.gif`); vector or diagram-source assets require an exact path without wildcard characters, or a matching path rule whose optional `extensions` array explicitly lists dotted suffixes (for example, `[".svg", ".mmd"]`). Asset suffixes and `extensions` entries are case-insensitive (`[".SVG"]` opts into `.svg`); path matching remains case-sensitive. Otherwise they remain in `exceptions.unclassified_assets` for review.

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
| frontmatter_duplicate_ids | 0 |
| frontmatter_entries_without_fence | 16 |
| frontmatter_unparseable | 1 |
| id_reused_on_other_pages | 18 |
| missing_id_comment | 4 |
| unclassified_assets | 0 |
| unclosed_fences | 0 |
| unrecognized_mermaid_fences | 0 |
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

The current inventory classifies no non-Mermaid published visual as detected by the searched mechanisms across `docs/` (`<svg`, `<img`, `<iframe`, `<script`, `cytoscape`, `d3`, `vis-network`, `plotly`). This textual search is not an exhaustive visual classification of raster assets:

- Two vector SVG files exist: `docs/assets/logo.svg` and `docs/assets/favicon.svg`. They are classified as branding by file name only, not by visual inspection.
- No embedded `<canvas>` elements, Cytoscape graph datasets, D3 charts, or external visualization scripts are present.
- The 435 raster assets (`.png` and `.webp`) are grouped as Portal screenshots or evidence captures by path and alt-text screening. The historical visual sample covered 88 images across all 45 raster directories; it does not classify all 435 raster assets visually.

## Quality of Classification

### Heuristic Genre Candidates

Mermaid syntax directly decides unambiguous typed diagrams: sequence diagrams become `sequence`, state diagrams become `state`, and pie or quadrant charts become `chart`.

For the 463 flowchart and graph blocks (96.7 % of all diagrams), genre assignment is an unreviewed heuristic candidate:

- Blocks with decision shapes (`{...}`) or explicit Yes/No edge labels predict `decision`.
- Blocks with `subgraph` boundaries and no decision nodes predict `topology`.
- All other flowcharts predict `flow`.
- Ambiguous signals or conflicting markers predict `unknown` with `needs_review: true`.

A stratified random validation sample (seed 400, sample size n=62) was drawn and labelled against `main` at `944b237`, before PR #414. It measured agreement between heuristic predictions and manual labels assigned by reading each diagram (by an AI agent, not an independent human review). The only sampled diagram changed since, `docs/platform/deployment-scenarios.md#scenario-overview`, had only a label quoted by PR #414 and keeps its genre:

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

A one-time rendering test was run on 2026-10-30 with throwaway tooling outside the repository tree, on `main` at `944b237`, before PR #414 fixed the failing block in `docs/platform/deployment-scenarios.md`. That is the only measured block that has changed since the test; the measurement is not a rendering result for the manifest baseline. The site was built and every published Mermaid block was rendered in headless Chrome 145 with the Mermaid library MkDocs Material loads (`mermaid@11`, which resolved to 11.17.2 at the time):

- 474 out of 475 published blocks rendered without errors.
- 1 block failed to parse (`docs/platform/deployment-scenarios.md`, an unquoted label containing parentheses); it was tracked in issue #412 and fixed by PR #414.
- Across the three sibling guides (475 + 398 + 568 = 1,441 published blocks) the same test found 11 parse errors (Container Apps 1, App Service 8, Functions 2; the sibling fixes are tracked in App Service #290 and Functions #218). The regex-based `validate_mermaid_syntax.py` caught none of them, and a blocking render gate belongs to #408.

The rendered PNG images for Container Apps total 15.9 MB (approximately 33 KiB per diagram). Storing these pre-rendered binary files in git was rejected because:

- It would permanently inflate repository size with derived binary artifacts.
- The repository's image merge gates (caption-to-image match and final-image PII verification in `AGENTS.md`) are written for evidence screenshots, so hundreds of derived renderings would add review work for no evidence value.
- A render baseline can be measured again from the commit recorded in `baseline.base_commit` and the per-block `source_sha256` values with any headless-browser harness; this inventory commits no such harness.

## Command Reference

The inventory workflow relies on `scripts/diagram_inventory.py`, requiring Python 3.11 and PyYAML. It never renders, converts, or verifies source provenance. `--write` writes the manifest and this page's generated blocks; `--check` performs consistency validation, not provenance verification.

Files are decoded as UTF-8 with optional BOM. An undecodable file is skipped and recorded in `frontmatter_unparseable` with its path and decoding error, like unparseable frontmatter; this exception means extraction is incomplete, not that no diagram exists. Duplicate usable frontmatter IDs appear in `frontmatter_duplicate_ids`; only the first entry supplies declared provenance. Missing, null, empty, or non-string frontmatter IDs never attach to a fence.

The scanner is a line-based approximation of how the site renders indentation, not a full Markdown container parser. It errs toward reporting Mermaid-opener-like lines in `unrecognized_mermaid_fences` rather than silently dropping them:

- `html-comment` and `indented-code` are informational: the fence is hidden by a multiline HTML comment or shown as plain indented code. Plain-code state starts at an indented line (at least four columns, with tabs expanded) after a blank line or at document start without a less-indented container/HTML ancestor. It continues across blank or indented lines and ends at the first nonblank line with fewer than four columns. `--check` prints each finding without failing.
- `blockquote`, `list-marker`, and `indented` are blocking findings. The last reason covers container indentation, including HTML tag lines in the less-indented ancestor chain, or a lazy continuation directly after prose without a blank line. The HTML heuristic recognizes a line starting with `<` followed by a letter, `/`, or `!`, except a single-line HTML comment; it does not parse HTML. `--write` succeeds and warns once per page, listing only blocking findings; `--check` fails. Move the fence to the top level with at most three spaces of indentation, or show it inside a longer outer fence, then regenerate.
- Fence recognition precedes comment detection. Inline code spans containing comment tokens do not open comments. A multiline comment needs a closing `-->`: an unclosed one is shown as literal text by the site, so it hides nothing, and text inside any fence never closes a comment because the site extracts fences first. Unsupported blocks, including indented generic fences of any language or no language, are consumed through their matching closing fence (even a dedented closer) so later canonical fences remain in sync; only Mermaid openers produce findings. Another fence opener before a closing fence, or no closing fence, means the block is unclosed and the scan resumes on the next line instead of swallowing the page.
- Recognized outer non-Mermaid fences contain examples, not rendered diagrams, and do not produce unsupported-fence findings. The separate `scripts/validate_mermaid_format.py` policy already rejects indented Mermaid fences, including plain indented code examples; use a longer outer fence for examples.

This classification was checked against Python-Markdown 3.10.2 and pymdownx 10.21.3 on 2026-10-30 in local experiments whose harnesses and evidence are not committed. The repeated 3,300-document grammar corpus had zero documents where rendered diagrams exceeded recognized non-example occurrences plus blocking findings, and zero plain-code documents with blocking findings. The repeated mutation fuzzer (seeds 11, 12, and 13; 4,000 documents each) found 60, 72, and 62 under-accounted documents respectively (194 of 12,000); the remaining minimized cases use corrupted or unbalanced fence syntax. It is not a rendering guarantee.

Known limitations:

- Info strings with extra words are counted by the first-word `mermaid` rule, but the site shows them as code rather than diagrams.
- A comment that starts after a list marker or blockquote prefix is not tracked.
- Nested list/container structure beyond the less-indented ancestor heuristic may be reported as `indented` when the site shows code. HTML ancestor detection is deliberately conservative, including balanced wrappers, and does not establish whether a tag remains open. Plain-code continuation is tracked explicitly, but this is not a full container parser.
- Corrupted or unbalanced fence syntax, for example an opener that is never closed, bare marker lines of a different kind, tilde/backtick mixes, or fence markers and comment tokens inside an info string, is parsed differently by CommonMark and by the site's renderer. The scanner uses CommonMark-style boundaries for recognized top-level fences and records their unclosed fences in `unclosed_fences`, but the site can show more diagrams than the scanner accounts for on such a page.

### Validating the Inventory (Blocking CI)

Run the consistency check during automated CI validation:

```bash
python3 scripts/diagram_inventory.py --check
```

This validates that the manifest conforms to the JSON schema, keys are unique, batch counts reconcile with totals, rule hashes match, and markdown blocks in this document match the generated tables. It does not compare the current diagram tree with the frozen baseline. Deterministic fixture reproduction remains blocking; current-tree baseline reproduction is opt-in with `DIAGRAM_INVENTORY_REPRODUCE=1` when the tree is unchanged.

### Regenerating the Manifest

`--write` reads the current working tree and regenerates the whole manifest, recording `baseline.base_commit` as metadata (pass `--base-commit` to pin it); it does not read the tree at that commit or retain separate baseline records and current-tree observations. Run `--verify-tree` before rewriting to see removed and changed records. Reviewed planning fields are preserved by key, while a reviewed classification is preserved only when the diagram body's `baseline.source_sha256` is unchanged; a changed body receives a fresh, unreviewed heuristic classification and must be reviewed again.

Update the manifest and generated documentation blocks after adding or modifying diagrams:

```bash
python3 scripts/diagram_inventory.py --write
```

To pin the manifest baseline to a specific commit:

```bash
python3 scripts/diagram_inventory.py --write --base-commit "$(git rev-parse HEAD)"
```

### Migration Progress States

Batch owners edit `target`, `context.reader_intent`, and `migration` by key; these planning fields survive body changes and regeneration.

| Migration state | Meaning | `exception` |
|---|---|---|
| `not-started` | Migration has not begun. | `null` |
| `in-progress` | The owning batch is migrating the diagram. | `null` |
| `completed` | The owning batch records migration as complete. | `null` |
| `exception` | Migration has an explicitly recorded exception. | Nonblank explanation string |

These are owner-maintained progress states, not proof of rendering, source verification, or review approval.

### Checking Tree Drift (Advisory)

Inspect changes between the working tree and the committed baseline:

```bash
python3 scripts/diagram_inventory.py --verify-tree
```

This compares extracted diagram records with the baseline; it does not report extraction completeness. Consult `unrecognized_mermaid_fences` through `--check` for blocking extraction findings. A drift-free result alone does not establish a complete inventory.

The JSON categories are `added` and `removed` keys; `moved` key changes with identical bodies; `changed` body hashes; `reclassified` genre, syntax type, or assignment changes; `provenance` changes to the complete provenance record; and `relocated` changes to the same key's line, end line, or heading path. `assets` lists changed exclusion-group path sets as `{group, added, removed}` records, with `group: null` for the unclassified-asset set; `visuals` lists keys added, removed, or changed in non-Mermaid visual records. Paths are compared as sets, not list order. Drift remains advisory (exit zero); adding `--strict` makes any non-empty category fail.

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
