---
description: Repository-local rules for honest content_validation scope, states, evidence dates, claim sources, and adoption measurement.
---

# Honest Content Validation States

Use `content_validation` to record a **source review** of an in-scope factual-claim page. It does not record a deployment, tutorial test, lab run, screenshot capture, or other real Azure execution.

## Scope by Document Type

The executable scope rule is [`scripts/lib/content_scope.py`](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/scripts/lib/content_scope.py). Check a path with `is_in_scope()` instead of inferring scope from the presence of a token in frontmatter.

| Document type | `content_validation` state | Evidence model |
|---|---|---|
| Platform factual-claim page | Required | Source review of core claims against Microsoft Learn |
| Best-practices factual-claim page | Required | Source review of core claims against Microsoft Learn |
| Operations factual-claim page | Required | Source review of core claims against Microsoft Learn |
| Troubleshooting playbook or factual methodology page | Required | Source review; evidence tags may supplement it |
| Troubleshooting lab guide | Not applicable | Experiment log, observed evidence, and required falsification |
| KQL query pack | Not applicable by default | Query purpose, required tables, assumptions, and result interpretation |
| Language tutorial | Not applicable | Tutorial `validation` frontmatter records an actual end-to-end test |
| Reference or Start Here page | Not applicable | Reference sourcing or orientation content; no `content_validation` block |

Navigation-only indexes and generated dashboards are also out of scope. A legacy block on an out-of-scope page does not make that page part of the denominator and must not be copied to new pages.

## Canonical Fields and Meaning

| Field | Meaning |
|---|---|
| `status` | `verified`, `pending_review`, or `unverified`; describes source-review completeness only |
| `last_reviewed` | Date on which the recorded source review actually occurred, or YAML `null` when no review occurred |
| `reviewer` | `human` or `agent` when a review occurred, or YAML `null` for an unreviewed state |
| `core_claims` | Two to five concrete, falsifiable assertions that represent the page's important Azure behavior claims |
| `core_claims[].claim` | The factual assertion being checked; never a statement about the page or its sourcing process |
| `core_claims[].source` | Direct, locale-qualified Microsoft Learn URL supporting the claim; every listed claim must cite one |
| `core_claims[].verified` | `true` only after the cited source was read and found to support that claim; otherwise `false` |

The statuses mean:

- `verified`: every listed core claim has `verified: true` and a supporting Microsoft Learn URL.
- `pending_review`: a source review has begun but at least one listed claim with a Microsoft Learn citation remains unverified. Like every in-scope state it still lists 2-5 cited claims.
- `unverified`: no source review has been performed. Use `null` for unknown review metadata and list 2-5 cited core claims with `verified: false`; never omit the Microsoft Learn citation.

### Source Review Is Not Azure Execution

Source review answers, "Does current Microsoft Learn documentation support this claim?" Real Azure execution answers, "Did this procedure or hypothesis work in an Azure environment?" These are separate assertions with separate evidence:

- Tutorial execution belongs in tutorial `validation` frontmatter, and only after the tutorial was run end to end.
- Lab execution belongs in experiment logs, raw evidence, verification queries, captures, and falsification results.
- Screenshot and evidence timestamps describe capture or experiment events, not source review.

Never infer source verification from a populated `content_validation` token, a `content_sources` entry, a successful build, or existing execution evidence. Never derive `last_reviewed` from build time, generation time, commit time, or file modification time. When editing metadata, leave historical tutorial validation dates, lab evidence dates, and capture dates unchanged unless new execution actually produced replacement evidence.

## Decision Table

| Document type | Valid | Incomplete | Not applicable |
|---|---|---|---|
| Platform, best practices, or operations factual page | `verified` with all claims supported, or honest `pending_review`/`unverified` metadata | Missing block; `verified` with a false, missing, or unsupported claim; review date or reviewer absent after a review | Never, unless the exact path is excluded by `is_in_scope()` |
| Troubleshooting playbook or factual methodology page | Same source-review states as other in-scope pages | Evidence exists but core factual claims have not been source-reviewed | Lab guides and KQL packs only; ordinary playbooks remain in scope |
| Lab guide | Falsifiable hypothesis, observed evidence, and post-fix falsification | Missing evidence or falsification; do not compensate with `content_validation` | `content_validation` is omitted |
| KQL query pack | Purpose, tables, assumptions, and interpretation documented | Query contract is incomplete; do not compensate with `content_validation` | `content_validation` is omitted unless a separate factual platform page is created |
| Tutorial | `validation` records a real completed test with the actual date and tool result | `not_tested` or an honestly recorded failure is acceptable; a fabricated pass is not | `content_validation` is omitted |
| Reference or Start Here page | Appropriate source links or orientation content | Fix missing sourcing or unclear orientation directly | `content_validation` is omitted |

## Example Frontmatter States

### In-Scope: Verified

Use this state only after reading each cited page and confirming every claim.

```yaml
---
content_validation:
  status: verified
  last_reviewed: 2026-11-10
  reviewer: human
  core_claims:
    - claim: Container Apps revisions are immutable snapshots of an application version.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: A Container Apps scale rule can use an HTTP, TCP, or custom event-driven trigger.
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: true
---
```

### In-Scope: Pending Review

Use this state when a real review has started but is incomplete. A listed claim still cites the Microsoft Learn page to be checked; keep `verified: false` until that page has been read and found to support the claim. Every listed claim must still cite a Microsoft Learn page; never add a null source.

```yaml
---
content_validation:
  status: pending_review
  last_reviewed: 2026-11-10
  reviewer: agent
  core_claims:
    - claim: Container Apps revisions are immutable snapshots of an application version.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: Container Apps applies a default cooldown period to event-driven scale rules.
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: false
---
```

### In-Scope: Unverified

Use an honest unknown state for an in-scope page whose source review has not happened yet. `AGENTS.md` requires 2-5 core claims per in-scope page, each citing Microsoft Learn, so list the claims the page makes with the Microsoft Learn page that should support each one and keep every `verified` value `false`. Leave `last_reviewed` and `reviewer` null because no review has occurred.

```yaml
---
content_validation:
  status: unverified
  last_reviewed: null
  reviewer: null
  core_claims:
    - claim: Container Apps revisions are immutable snapshots of an application version.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: false
    - claim: Container Apps supports scale rules based on HTTP traffic, CPU, memory, and event sources.
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: false
---
```

Allowing `core_claims[].source: null` would require a deliberate change to the repository contract in `AGENTS.md`; it is a proposal for [issue #574](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/574) and the cross-repository work tracked by [issue #380](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/380), not a valid state today.

### Tutorial: Tested and Not Tested

Tutorials omit `content_validation`. A completed real-Azure test may record a pass; an unexecuted path remains `not_tested` with a null date.

```yaml
---
validation:
  az_cli:
    last_tested: 2026-11-10
    cli_version: "2.79.0"
    result: pass
  bicep:
    last_tested: null
    result: not_tested
---
```

### Lab: Evidence Model

Lab guides omit `content_validation`. Their document body records the state instead of adding substitute frontmatter:

```markdown
## 4) Experiment Log

[Observed] Record the direct failure evidence and artifact path.

### Post-fix evidence

[Measured] Record the bounded result that falsifies the original failure condition.
```

An incomplete lab says that evidence was not collected or the hypothesis is not proven; it does not invent a date or mark a source review as a lab pass.

### KQL, Reference, and Start Here: Not Applicable

These pages omit the block entirely. KQL packs document their query contract in the body; reference and Start Here pages use their own templates and source links.

```yaml
---
description: A page-specific description appropriate to this document.
---
```

## Invalid Values and Claims

### Enforced Today

Scratch copies exercised against the current validators confirm these blocking checks:

- `scripts/generate_content_validation_status.py` rejects an in-scope claim containing the phrase `primary source basis`. A core claim must assert Azure behavior rather than describe the documentation process.
- `scripts/validate_doc_quality.py` rejects unknown statuses and non-boolean claim results.
- For `verified` and `pending_review`, the validator requires a valid, non-future ISO review date and a non-placeholder reviewer of `human` or `agent`.
- Every in-scope block must list 2-5 claims. Every listed claim must have a non-placeholder source. A claim marked `verified: true` must cite an `https://learn.microsoft.com/en-us/` URL.
- `status: verified` is rejected when an explicitly listed claim has `verified: false`.
- `unverified` remains an honest state with YAML `null` review date and reviewer; the same null values are rejected when a review is claimed.

### Planned for Issue #574

[Issue #574](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/574) adds the fail-closed structural checks listed above to the existing changed-document quality gate. The validator does not fetch or interpret cited pages, so it still cannot prove that a Microsoft Learn page supports the assertion. Reviewers must continue to verify claim-to-source support directly; validator acceptance is not evidence that a claim is truthful.

## Adoption Denominator

Report adoption as both a numerator and denominator, with an as-of date and commit. Do not compare percentages that use different denominators.

| Denominator | Definition | Use |
|---|---|---|
| All Markdown | Every `*.md` file under `docs/`, including out-of-scope and generated pages | Repository inventory only; not the policy adoption rate |
| Published pages | Markdown inputs published by the current MkDocs configuration, including pages omitted from navigation but excluding configured build exclusions | Reader-visible inventory; currently equal to All Markdown because no Markdown pages are excluded from the build |
| In-scope factual-claim pages | Files for which `scripts.lib.content_scope.is_in_scope()` returns `True` | Canonical `content_validation` adoption denominator |

Run this read-only measurement from the repository root. It inspects only the opening YAML frontmatter block, so a page that merely mentions the key in its body is not counted:

```bash
python3 - <<'PY'
import re
from pathlib import Path
from scripts.lib.content_scope import is_in_scope

pages = sorted(Path("docs").rglob("*.md"))

def has_metadata(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    match = re.match(r"---\n(.*?)\n---(?:\n|$)", text, re.DOTALL)
    return bool(match and re.search(r"^content_validation:\s*$", match.group(1), re.MULTILINE))

in_scope = [path for path in pages if is_in_scope(path.relative_to("docs"))]
print("all_markdown", sum(map(has_metadata, pages)), len(pages))
print("published_pages", sum(map(has_metadata, pages)), len(pages))
print("in_scope", sum(map(has_metadata, in_scope)), len(in_scope))
PY
```

Measured on **2026-11-10** at commit **`5a712e819c5895e9c18e0b5f9c0b152e895b6418`** (the commit before this page was added; running the command on a tree that contains this page reports one more Markdown file and the same `content_validation` counts):

| Denominator | Pages with `content_validation` | Total pages | Interpretation |
|---|---:|---:|---|
| All Markdown | 255 | 395 | Token presence across the docs tree, not review completeness |
| Published pages | 255 | 395 | Same count under the current no-exclusion MkDocs configuration |
| In-scope factual-claim pages | 161 | 164 | Canonical adoption count; status and claim integrity still require separate evaluation |

These numbers are a repository-local snapshot, not a rollout claim for other repositories. Re-run the command whenever the commit or build configuration changes.

## Usage Notes

- Regenerate [`docs/reference/content-validation-status.md`](../reference/content-validation-status.md) with `python3 scripts/generate_content_validation_status.py` after changing in-scope metadata.
- Use [`scripts/validate_content_sources.py`](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/scripts/validate_content_sources.py) for Mermaid provenance. It does not prove `content_validation` claim review.
- Use [`scripts/generate_content_validation_status.py`](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/scripts/generate_content_validation_status.py) for the in-scope dashboard. Dashboard inclusion and status display do not independently validate metadata truthfulness.
- Preserve existing historical evidence. Correct inaccurate metadata explicitly rather than silently replacing dates with today's date.

## See Also

- [Contributing Guide](index.md)
- [Content Validation Status](../reference/content-validation-status.md)
- [Tutorial Validation Status](../reference/validation-status.md)

## Sources

- [Revisions in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Set scaling rules in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
