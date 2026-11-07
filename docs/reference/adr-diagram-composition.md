---
description: Accepted direct-Mermaid authoring default and bounded topology reuse contract for Azure Container Apps diagrams.
title: ADR - Diagram Composition and Shared Topology Strategy
content_sources:
  references:
    - type: self-generated
      justification: Local architecture decision derived from the merged inventory, sibling-guide decisions, a measured composition prototype, and cited Microsoft Learn platform contracts.
---

# ADR: Diagram Composition and Shared Topology Strategy

## Status

**Accepted: literal, typed Mermaid is the default authoring path for Azure Container Apps.** Authors apply the common Azure topology visual grammar directly in Markdown. No composition generator, macro layer, or new shared package is mandatory. The App Service composition prototype remains a measured, opt-in comparator rather than an ACA dependency.

This decision selects an authoring method. It does not migrate a diagram, complete #401 or #408, or record visual approval of any future render.

## Context and Problem Statement

The merged ACA inventory at commit [`de59e3e27aaa8c78714a23704f8f123d0830fd3d`](https://github.com/yeongseon/azure-container-apps-practical-guide/commit/de59e3e27aaa8c78714a23704f8f123d0830fd3d) records 479 Mermaid occurrences in 386 diagram-bearing Markdown files: 475 published occurrences, 4 repository-only occurrences, 3 exclusions, and 476 migration-required occurrences. Its machine-readable snapshot is based on commit `5279b7ba0bc630aad051f956001340b55d53cb39`; the merge commit and snapshot baseline are therefore distinct facts. The inventory assigns 2 occurrences to #401, 32 to #402, 6 to #403, 48 to #404, 31 to #405, 176 to #406, and 181 to #407.

The two #401 base occurrences are exactly:

- `docs/platform/architecture/index.md#architecture-overview`
- `docs/platform/architecture/index.md#control-data-plane`

Both are literal `flowchart` fences, classified as unreviewed topology candidates, and remain `not-started`. The inventory does not establish that they are already a reusable base or that their current internals are authoritative.

There is real downstream reuse to coordinate, but it is not one uniform graph:

- Ingress has two current occurrences, `docs/platform/networking/ingress.md#ingress-decision-tree` and `docs/platform/networking/ingress.md#ingress-request-lifecycle`, owned by #424. They need the environment-to-ingress-to-revision vocabulary while retaining their decision and lifecycle purposes.
- Egress has three current occurrences owned by #425: `managed-identity-acr-egress-dependencies`, `nat-gateway-architecture`, and `route-outbound-traffic-through-azure-firewall`. They reuse environment and dependency boundaries, not an inbound request path.
- Revision pages contain four current occurrences under `docs/platform/revisions/`: two state diagrams and two graph/flowchart diagrams. Reuse applies to revision and replica names and to traffic relationships; state and decision semantics remain typed rather than being converted to topology.
- ACR has six current occurrences: the `acr-path-choice` decision diagram plus five lab `architecture` diagrams for Paths A through E. Issues #427 through #431 each own one lab architecture occurrence. These views reuse an ACA-to-ACR dependency vocabulary while keeping DNS, routing, transport, identity, and image-pull outcomes separate.

The decision must reduce drift without relocating unchanged Azure resource boundaries, turning every diagram into a topology, or drawing undocumented ACA-managed Kubernetes internals.

## Decision Drivers

- Keep the complete reviewed diagram next to its explanation, stable `diagram-id`, and `content_sources.diagrams[]` metadata.
- Preserve the correct Mermaid genre and each page's reader question.
- Reuse a visual and semantic grammar without requiring a second source of truth.
- Keep the current MkDocs, inventory, source-validation, repetition, PII, and strict-build checks effective on literal Markdown.
- Make ACA-specific environment, ingress, revision, replica, workload-profile, and ACR boundaries explicit only where Microsoft Learn documents them.
- Provide a low-cost rollback if a proposed abstraction costs more than coordinated hand authoring.

## Compared Contracts and Pinned Evidence

| Contract | Exact reviewed source | Verified result used here |
|---|---|---|
| Merged ACA inventory and original ADR | ACA merge commit [`de59e3e27aaa8c78714a23704f8f123d0830fd3d`](https://github.com/yeongseon/azure-container-apps-practical-guide/commit/de59e3e27aaa8c78714a23704f8f123d0830fd3d) | 479 total occurrences, 476 migration-required, and the two #401 IDs above are present in the merged manifest. |
| App Service opt-in composition PoC | App Service PR #298 merge commit [`9d9d71ff3247bb29e9a7488c4297c0a734c3c9b1`](https://github.com/yeongseon/azure-app-service-practical-guide/commit/9d9d71ff3247bb29e9a7488c4297c0a734c3c9b1) | One base, two extensions, and a failure overlay regenerate four literal Mermaid fixtures, but the predeclared implementation-size condition failed. Tooling measured 967 nonblank lines versus 136 inline lines; break-even near 45 variants was explicitly inferred, not measured deployment evidence. |
| App Service default | App Service PR #434 merge commit [`e6745876e392888f840c1d28d9fc8927486630a5`](https://github.com/yeongseon/azure-app-service-practical-guide/commit/e6745876e392888f840c1d28d9fc8927486630a5) | Accepted literal, typed Mermaid plus the common visual grammar; the PoC stays optional and no migration completion was claimed. |
| Functions default | Functions PR #562 merge commit [`af27759a02354e0fd63787650e1d2db7e88679fe`](https://github.com/yeongseon/azure-functions-practical-guide/commit/af27759a02354e0fd63787650e1d2db7e88679fe) | Accepted the same literal, typed Mermaid default without adding a generator or macro system; migration and rendered acceptance remain separate work. |

These commits were inspected directly through GitHub. Issue summaries are not treated as the source of the sibling decisions.

## Considered Options

### Option A: Plain Typed Mermaid with a Common Visual Grammar

Authors write the complete diagram as a native Mermaid fence in the owning Markdown page. Shared component names, boundary meanings, arrow taxonomy, layout conventions, and overlay semantics form the reuse contract.

- **Benefits:** no generated source, no new dependency, direct review of the final fence, and immediate compatibility with MkDocs and all current source checks. Sequence, state, decision, and topology diagrams keep their proper types.
- **Costs:** repeated base declarations are maintained by coordinated review rather than compilation. A common change can touch more than one page, and drift prevention depends on manifest ownership, stable IDs, review, and later coverage/visual gates.

### Option B: Versioned Snippets or Macros

A versioned include could provide common node or subgraph fragments while pages supply scenario edges.

- **Benefits:** less repeated text without a full renderer.
- **Costs:** ACA's variants replace or reinterpret edges rather than only adding nodes. Fragment order, indentation, node identifiers, and positional link styles become hidden coupling. Build-time expansion can also hide the assembled graph from source-based inventory and provenance checks. The current repository has no accepted composition-snippet contract, so adopting one would add an unmeasured interface rather than reuse a merged sibling default.

### Option C: Opt-in Minimal Composition Path

A bounded specification can name one base, extensions, and overlays and emit literal Mermaid. The App Service #298 implementation proves this is technically possible and that committed literal fences can remain visible to existing checks.

- **Benefits:** references and overlay targets can be validated structurally, and a base edit can update enrolled variants consistently.
- **Costs:** the measured comparator required a specification, a 434-line generator, and 449 lines of tests for four variants. Its tool-size condition failed, and its inferred break-even was near 45 variants. ACA has only two architecture-base occurrences; ingress, revision, and ACR views also use different diagram purposes and edge semantics. Building or copying a renderer now would cost more than the bounded reuse it can prove.

Option C remains available only as a future, separately measured exception. It is not approved merely because a future family has many diagrams; that family must show a smaller total maintenance cost and preserve literal auditable output.

### Option D: Mandatory Shared Generator or Package

A cross-repository package would centralize composition logic.

- **Rejected:** neither sibling chose it as the default. It introduces publishing, versioning, and synchronized-release costs, and three copied local generators would be worse. No demonstrated ACA need justifies this dependency.

## Decision Outcome

ACA adopts the same default as App Service and Functions: **direct, typed Mermaid in Markdown plus the common visual grammar, with no mandatory generator**.

The smallest topology composition contract is semantic rather than executable:

1. **Stable local IDs:** keep page-qualified inventory keys and stable `diagram-id` comments. The two #401 IDs remain `architecture-overview` and `control-data-plane` unless #401 records a reviewed relocation; this decision does not rename them.
2. **Common vocabulary:** use consistent labels for the Container Apps environment, managed ingress, container app, revision, replica, workload profile, Azure Container Registry, customer VNet/subnet, Private Endpoint, DNS, control/management flow, request/data flow, and fault/evidence overlays.
3. **Boundary preservation:** keep Azure resources outside customer VNets unless the resource is actually represented by a documented private endpoint NIC or environment/infrastructure subnet relationship. Keep revisions and replicas as logical ACA groupings. Do not draw customer-owned pods, hidden cluster nodes, or undocumented managed-network hops.
4. **Typed extensions:** an extension means a reviewed page-specific addition to the visual grammar, not textual inclusion of a base fence. Ingress, egress, revision/scaling, and ACR diagrams may repeat the minimum nodes needed to answer their own question while preserving common names, placement, and line meanings.
5. **Source-visible output:** all final diagrams remain literal fences visible to `diagram_inventory.py`, MkDocs, source metadata validation, and reviewers. No macro-expanded or generated-only graph is accepted as the sole reviewed source.

### Cost Decision

For the two ACA base occurrences, hand-authored Mermaid has the lower demonstrated cost. The App Service comparator's 967 tooling lines for 136 inline lines and inferred break-even near 45 variants are not directly transferable measurements for ACA, but they are strong evidence against creating a local renderer for two base occurrences and heterogeneous extensions. The hand-authored cost is coordinated edits and review; the generated cost adds schema design, generator safety, tests, stale-output checks, layout hints, and an opt-out procedure. ACA accepts the former until a bounded family measures the latter as smaller.

### Compatibility with Current Checks

This choice keeps compatibility without weakening any gate:

- MkDocs consumes the same literal Mermaid fences.
- `scripts/diagram_inventory.py` continues to scan and hash the Markdown source; its schema remains an inventory contract, not a composition API.
- `scripts/validate_content_sources.py` continues to compare diagram fences with canonical `content_sources.diagrams[]` metadata where required.
- YAML frontmatter remains under `scripts/lib/yaml_style.py` and the normalizer check.
- Repetition and PII checks continue to inspect authored documentation.
- #575 may add incremental manifest/ownership protection, and #408/#576 may add render inspection, without depending on a generator.

### Rollback and Exception Path

Rollback requires no source conversion: revert this ADR decision and continue reviewing the existing literal fences. Because this change introduces no generator, specification, macro, generated output, or dependency, rollback leaves no orphaned build path.

If a later owner proposes composition for a bounded family, the proposal must be opt-in and must predeclare a comparison against direct Mermaid. It must count specification, implementation, tests, stale-output enforcement, and layout maintenance; preserve literal auditable fences and stable IDs; prove safe opt-out; and pass the same source and render review. If total complexity exceeds demonstrated reuse, remove the opt-in files and retain the literal fences.

## Consumption by Existing Work

### #401 Base

#401 owns only the two merged-manifest base occurrences. It may align their direct Mermaid declarations around environment, ingress, revision, replica, workload-profile, and control/data-flow vocabulary. It must preserve each diagram's separate question: `architecture-overview` is the product mental model, while `control-data-plane` distinguishes management configuration from runtime behavior. Shared vocabulary does not require identical graphs.

### #424 and #425 Networking

#424 consumes the ingress adapter by keeping environment accessibility, app ingress visibility, managed ingress, revision routing, and replica targets distinct. External app ingress must not automatically imply public internet reachability; the environment's accessibility and public-network configuration remain separate.

#425 consumes the outbound/dependency adapter. It keeps DNS resolution, route selection, firewall/NAT processing, transport, managed-identity authorization, and dependency response as distinct flows. It must not clone the inbound Envoy request path into an egress diagram or place ACR inside the ACA environment.

### #427 through #431 ACR Paths

Each ACR issue uses the same ACA environment and external ACR resource vocabulary while retaining its path-specific extension:

- #427: public ACR through firewall/SNAT; no Private Endpoint implication.
- #428: private DNS plus direct path to the ACR Private Endpoint.
- #429: private DNS plus explicit UDR/firewall inspection of the private destination; no claim that inspection happens automatically.
- #430: record-level DNS authority; a DNS answer is not proof of transport or authorization.
- #431: custom DNS forwarding/bypass decision separated from packet routing and identity.

The `acr-path-choice` decision diagram remains a decision diagram rather than a sixth topology base. None of these consumers may move the ACR resource, customer VNet, subnets, Private Endpoint NIC, or Private DNS zone merely to make diagrams look identical. Unchanged resource boundaries and relative placement should remain stable across the five path variants when that does not obscure the path-specific question.

### Revision and Replica Consumers

Revision state diagrams remain state diagrams. Traffic-split and revision-mode diagrams may reuse ingress, revision, and replica vocabulary, but must not imply that a revision or replica is a separately customer-managed Azure resource. Microsoft Learn documents revisions as immutable snapshots and replicas as runtime instances; it does not expose the managed Kubernetes internals as an authoring contract.

## Consequences and Risks

### Positive Consequences

- ACA matches both sibling defaults and introduces no third renderer.
- The final source stays readable in reviews and visible to all current checks.
- The two base occurrences and their downstream consumers can coordinate semantics without forcing unlike diagrams through one executable graph.
- Rollback is a documentation-only revert.

### Risks and Mitigations

- **Risk: hand-authored copies drift.** Mitigation: preserve stable IDs and manifest ownership, use the common grammar, review related variants together where bounded, and let #575/#408 add coverage and render checks.
- **Risk: “shared base” is read as permission to copy a complete graph.** Mitigation: reuse vocabulary and unchanged placement only; every page keeps the minimum typed diagram needed for its own question.
- **Risk: diagrams imply ACA internals that Microsoft does not document.** Mitigation: label revisions/replicas and scaling relationships as logical platform abstractions, show only documented boundaries, and mark unsupported mechanisms unverified or omit them.
- **Risk: generated composition is rejected forever based on another repository's numbers.** Mitigation: the exception path permits a new bounded measurement, but no family inherits a favorable result without measuring all of its own costs.

## See Also

- [Diagram Inventory](diagram-inventory.md)
- [Diagram Manifest Schema](diagram-manifest.schema.json)
- [Parent Initiative #399](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/399)
- [ACA Base Owner #401](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/401)
- [Composition Decision #580](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/580)
- [App Service Composition PoC #283](https://github.com/yeongseon/azure-app-service-practical-guide/issues/283)

## Sources

- [Azure Container Apps structure](https://learn.microsoft.com/en-us/azure/container-apps/structure)
- [Ingress in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Revisions in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Containers in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/containers)
- [Mermaid documentation](https://mermaid.js.org/)
