# AGENTS.md

Guidance for AI agents working in this repository.

## Project Overview

**Azure Container Apps Practical Guide** — a comprehensive, hands-on guide for running containerized applications on Azure Container Apps, covering everything from initial deployment to advanced production troubleshooting.

- **Live site**: <https://yeongseon.github.io/azure-container-apps-practical-guide/>
- **Repository**: <https://github.com/yeongseon/azure-container-apps-practical-guide>

## Repository Structure

```text
.
├── .github/
│   └── workflows/              # GitHub Pages deployment
├── apps/
│   ├── python/                 # Flask + Gunicorn implementation
│   ├── nodejs/                 # Express.js implementation
│   ├── java-springboot/        # Spring Boot implementation
│   └── dotnet-aspnetcore/      # ASP.NET Core implementation
├── docs/
│   ├── assets/                 # Images, icons
│   ├── best-practices/         # Production patterns and anti-patterns
│   ├── language-guides/        # Per-language step-by-step tutorials
│   ├── operations/             # Day-2 operational execution
│   ├── platform/               # Architecture and design decisions
│   ├── reference/              # CLI reference, environment variables, limits
│   ├── start-here/             # Overview, learning paths, repository map
│   └── troubleshooting/        # Playbooks, lab guides, KQL query packs
│       ├── playbooks/          # Detailed guides for specific failure scenarios
│       ├── lab-guides/         # Step-by-step instructions for reproducing issues
│       └── kql/                # KQL snippets for diagnostics
├── infra/                      # Bicep/Terraform templates for provisioning
├── labs/                       # Lab infrastructure + scripts for scenarios
└── mkdocs.yml                  # MkDocs Material configuration
```

## Content Categories

The documentation is organized by intent and lifecycle stage:

| Section | Purpose | Page Count |
|---|---|---|
| **Start Here** | Entry points, learning paths, repository map | 3+ |
| **Platform** | Architecture, design decisions — WHAT and HOW it works | 7+ |
| **Best Practices** | Production patterns — HOW to use the platform well | 7+ |
| **Language Guides** | Per-language step-by-step tutorials and recipes | 28+ |
| **Operations** | Day-2 execution — HOW to run in production | 6+ |
| **Troubleshooting** | Diagnosis and resolution — hypothesis-driven | 20+ |
| **Reference** | Quick lookup — CLI, environment variables, platform limits | 3+ |

!!! info "Platform vs Best Practices vs Operations"
    - **Platform** = Understand the concepts and architecture.
    - **Best Practices** = Apply practical patterns and avoid common mistakes.
    - **Operations** = Execute day-2 tasks in production.

## Content Types & Methodology

### Troubleshooting Experiments (Labs)

All labs in `docs/troubleshooting/lab-guides/` must follow this 16-section structure:

1. **Question**: The specific problem being investigated.
2. **Setup**: Infrastructure and environment preparation.
3. **Hypothesis**: The expected cause and behavior.
4. **Prediction**: What should happen if the hypothesis is true.
5. **Experiment**: The steps taken to reproduce the issue.
6. **Execution**: The actual running of the experiment.
7. **Observation**: Raw data and logs collected.
8. **Measurement**: Quantified metrics (e.g., latency, error rates).
9. **Analysis**: Interpreting the observations and measurements.
10. **Conclusion**: Confirming or refuting the hypothesis.
11. **Falsification**: Proving that the fix works and the original theory was correct.
12. **Evidence**: Compiled logs, screenshots, or KQL results.
13. **Solution**: The final fix or mitigation.
14. **Prevention**: How to avoid this issue in the future.
15. **Takeaway**: The core lesson learned.
16. **Support Takeaway**: Key points for support engineers or developers.

### Evidence Levels

When documenting troubleshooting steps or analysis, use these tags to specify the strength of the evidence:

- `[Observed]`: Directly seen in logs, metrics, or UI (e.g., 503 errors in Log Analytics).
- `[Measured]`: Quantified data (e.g., 99th percentile latency is 4.5s).
- `[Correlated]`: Two events happening together without proven causation.
- `[Inferred]`: Conclusion based on logic and multiple pieces of evidence.
- `[Strongly Suggested]`: High confidence inference but missing the "smoking gun".
- `[Not Proven]`: Hypothesis that has not yet been validated.
- `[Unknown]`: Missing data or ambiguous behavior.

## Documentation Conventions

### File Naming

- Tutorial: `XX-topic-name.md` (numbered for sequence)
- All others: `topic-name.md` (kebab-case)

### CLI Command Style

```bash
# ALWAYS use long flags for readability
az containerapp create --resource-group $RG --name $APP_NAME --environment $CONTAINER_ENV --image myregistry.azurecr.io/myapp:latest

# NEVER use short flags in documentation
az containerapp create -g $RG -n $APP_NAME  # ❌ Don't do this
```

### Variable Naming Convention

| Variable | Description | Example |
|----------|-------------|---------|
| `$RG` | Resource group name | `rg-containerapps-demo` |
| `$APP_NAME` | Container app name | `ca-demo-app` |
| `$CONTAINER_ENV` | Container Apps environment | `cae-demo-env` |
| `$LOCATION` | Azure region | `koreacentral` |
| `$SUBSCRIPTION_ID` | Subscription identifier placeholder | `<subscription-id>` |

### Language Usage

- **Shell**: Use `bash` for all CLI examples.
- **Python**: Use `python` for all script examples.
- **KQL**: Use `kusto` for all Kusto Query Language blocks.
- **Mermaid**: Use `mermaid` for all architecture and flow diagrams.

### PII Removal (Quality Gate)

**CRITICAL**: All CLI output examples MUST have PII removed.

**Must mask (real Azure identifiers):**

- Subscription IDs: `<subscription-id>`
- Tenant IDs: `<tenant-id>`
- Object IDs: `<object-id>`
- Resource IDs containing real subscription/tenant
- Emails: Remove or mask as `user@example.com`
- Secrets/Tokens: NEVER include

**OK to keep (synthetic example values):**

- Demo correlation IDs: `a1b2c3d4-e5f6-7890-abcd-ef1234567890`
- Example request IDs in logs
- Placeholder domains: `example.com`, `contoso.com`
- Sample resource names used consistently in docs

The goal is to prevent leaking **real Azure account information**, not to mask obviously-fake example values that aid readability.

### Admonition Indentation Rule

For MkDocs admonitions (`!!!` / `???`), every line in the body must be indented by **4 spaces**.

```markdown
!!! warning "Important"
    This line is correctly indented.

    - List item also inside
```

### Mermaid Diagrams

All architectural diagrams use Mermaid. Every documentation page should include at least one diagram. Test with `mkdocs build --strict`.

### Nested List Indentation

All nested list items MUST use **4-space indent** (Python-Markdown standard).

### Tail Section Naming

Every document ends with these tail sections (in this order):

| Section | Purpose | Content |
|---|---|---|
| `## See Also` | Internal cross-links within this repository | Links to other pages in this guide |
| `## Sources` | External authoritative references | Links to Microsoft Learn (primary) |

- `## See Also` is required on every page.
- `## Sources` is required when external references are cited. Omit if none exist.
- Order is always `## See Also` → `## Sources` (never reversed).
- All content must be based on Microsoft Learn with cited sources.

### Canonical Document Templates

Every document follows one of 7 templates based on its section. Do not invent new structures.

#### Platform docs

```text
# Title
Brief introduction (1-2 sentences)
## Main Content
### Subsections
## See Also
## Sources
```

#### Best Practices docs

```text
# Title
Brief introduction
## Why This Matters
## Recommended Practices
## Common Mistakes / Anti-Patterns
## Validation Checklist
## See Also
## Sources
```

#### Operations docs

```text
# Title
Brief introduction
## Prerequisites
## When to Use
## Procedure
## Verification
## Rollback / Troubleshooting
## See Also
## Sources
```

#### Tutorial docs (Language Guides)

```text
# Title
Brief introduction
## Prerequisites
## What You'll Build
## Steps
## Verification
## Next Steps / Clean Up (optional)
## See Also
## Sources (optional)
```

#### Troubleshooting docs

```text
# Title
## Symptom
## Possible Causes
## Diagnosis Steps
## Resolution
## Prevention
## See Also
## Sources
```

#### Lab Guides

```text
# Title
Brief introduction
## Lab Metadata (table: difficulty, duration, tier, etc.)
## 1) Background
## 2) Hypothesis
## 3) Runbook
## 4) Experiment Log
## Expected Evidence
## Clean Up
## Related Playbook
## See Also
## Sources
```

#### Reference docs

```text
# Title
Brief introduction
## Topic/Command Groups
## Usage Notes
## See Also
## Sources
```

## Content Source Requirements

### MSLearn-First Policy

All content MUST be traceable to official Microsoft Learn documentation:

- Platform content (`docs/platform/`): MUST have direct MSLearn source URLs
- Architecture diagrams: MUST reference official Microsoft documentation
- Troubleshooting playbooks: MAY synthesize MSLearn content with clear attribution
- Self-generated content: MUST have justification explaining the source basis

### Source Types

| Type | Description | Allowed? |
|---|---|---|
| `mslearn` | Directly from Microsoft Learn | Required for platform content |
| `mslearn-adapted` | MSLearn content adapted for this guide | Allowed with source URL |
| `self-generated` | Original content for this guide | Requires justification |
| `community` | From community sources | Not for core content |
| `unknown` | Source not documented | Must be validated |

### Diagram Source Documentation

Every Mermaid diagram MUST have source metadata in frontmatter:

```yaml
content_sources:
  diagrams:
    - id: architecture-overview
      type: flowchart
      source: mslearn
      mslearn_url: https://learn.microsoft.com/en-us/azure/container-apps/...
    - id: troubleshooting-flow
      type: flowchart
      source: self-generated
      justification: "Synthesized from MSLearn articles X, Y, Z"
      based_on:
        - https://learn.microsoft.com/...
```

### Content Validation Tracking

- See [Content Validation Status](docs/reference/content-validation-status.md) for current status
- See [Tutorial Validation Status](docs/reference/validation-status.md) for tutorial testing

### Text Content Validation

Every non-tutorial document should include a `content_validation` block in frontmatter to track the verification status of its core claims.

```yaml
---
content_sources:
  - type: mslearn-adapted
    url: https://learn.microsoft.com/azure/container-apps/...
content_validation:
  status: verified  # verified | pending_review | unverified
  last_reviewed: 2026-04-12
  reviewer: agent  # agent | human
  core_claims:
    - claim: "Container Apps supports automatic scaling based on HTTP traffic, CPU, memory, and custom metrics."
      source: https://learn.microsoft.com/azure/container-apps/scale-app
      verified: true
    - claim: "Revisions are immutable snapshots of a container app version."
      source: https://learn.microsoft.com/azure/container-apps/revisions
      verified: true
---
```

#### Validation Status Values

| Status | Description |
|--------|-------------|
| `verified` | All core claims have been traced to Microsoft Learn sources |
| `pending_review` | Document exists but claims need source verification |
| `unverified` | New document, no validation performed |

#### Agent Rules for Content Validation

1. When creating or modifying Platform, Best Practices, or Operations documents, add `content_validation` frontmatter.
2. List 2-5 core claims that are factual assertions (not opinions or procedures).
3. Each claim must have a Microsoft Learn source URL.
4. Set `status: verified` only when ALL core claims have verified sources.
5. Run `python3 scripts/generate_content_validation_status.py` after updates.

## Quality Gates & Verification

1. **PII Check**: Manually verify no subscription IDs, tenant IDs, or private IP addresses are in the documentation.
2. **Link Validation**: Use `mkdocs build --strict` to ensure no broken internal or external links.
3. **Evidence Integrity**: Ensure every troubleshooting lab has a "Falsification" step that proves the hypothesis.
4. **Content Source Validation**: All diagrams and platform content must have documented MSLearn sources.

## Mandatory Oracle Review (AI Agent Rule)

**ALL work performed by AI agents MUST undergo Oracle quality review before completion.**

### Review Protocol

1. **Work Completion**: Agent completes assigned task
2. **Build Verification**: Run `mkdocs build --strict` (must pass)
3. **Oracle Review Request**: Submit all changes to Oracle for quality review
4. **Quality Criteria**:
    - MSLearn-first policy compliance
    - Code explanation tables present for all CLI commands
    - Mermaid diagrams with proper `<!-- diagram-id: -->` comments
    - Long CLI flags only (no `-g`, `-n` shortcuts)
    - No PII in examples
    - Proper frontmatter with `content_sources`
5. **Iteration**: If Oracle identifies issues → fix and re-submit
6. **Completion**: Only mark done when Oracle approves (100% quality)

### Review Loop

```
while not oracle_approved:
    fix_identified_issues()
    run_build_verification()
    submit_to_oracle()
```

**NO WORK IS CONSIDERED COMPLETE WITHOUT ORACLE APPROVAL.**

## Tutorial Validation Tracking

Every tutorial document supports **validation frontmatter** that records when and how it was last tested against a real Azure deployment.

### Frontmatter Schema

Add a `validation` block inside the YAML frontmatter (`---` fences) of any tutorial file:

```yaml
---
hide:
  - toc
validation:
  az_cli:
    last_tested: 2026-04-09
    cli_version: "2.83.0"
    result: pass
  bicep:
    last_tested: null
    result: not_tested
---
```

### Agent Rules for Validation

1. **After deploying a tutorial end-to-end**, add or update the `validation` frontmatter with the current date, CLI version, and `result: pass`.
2. **If a tutorial step fails during validation**, set `result: fail` and note the issue.
3. **Never fabricate validation dates.** Only stamp a tutorial after actually executing all steps against a real Azure environment.
4. **After updating frontmatter**, regenerate the dashboard:
    ```bash
    python3 scripts/generate_validation_status.py
    ```
5. **Include the regenerated dashboard** (`docs/reference/validation-status.md`) in the same commit as the frontmatter change.
6. **Do not manually edit** `docs/reference/validation-status.md` — it is auto-generated.

## Build & Preview

```bash
# Install MkDocs dependencies
pip install mkdocs-material mkdocs-minify-plugin

# Build documentation (strict mode catches broken links)
mkdocs build --strict

# Local preview
mkdocs serve
```

## Git Commit Style

```text
type: short description
```

Allowed types: `feat`, `fix`, `docs`, `chore`, `refactor`

## Related Projects

| Repository | Description |
|---|---|
| [azure-virtual-machine-practical-guide](https://github.com/yeongseon/azure-virtual-machine-practical-guide) | Azure Virtual Machines practical guide |
| [azure-networking-practical-guide](https://github.com/yeongseon/azure-networking-practical-guide) | Azure Networking practical guide |
| [azure-storage-practical-guide](https://github.com/yeongseon/azure-storage-practical-guide) | Azure Storage practical guide |
| [azure-app-service-practical-guide](https://github.com/yeongseon/azure-app-service-practical-guide) | Azure App Service practical guide |
| [azure-functions-practical-guide](https://github.com/yeongseon/azure-functions-practical-guide) | Azure Functions practical guide |
| [azure-kubernetes-service-practical-guide](https://github.com/yeongseon/azure-kubernetes-service-practical-guide) | Azure Kubernetes Service (AKS) practical guide |
| [azure-architecture-practical-guide](https://github.com/yeongseon/azure-architecture-practical-guide) | Azure Architecture practical guide |
| [azure-monitoring-practical-guide](https://github.com/yeongseon/azure-monitoring-practical-guide) | Azure Monitoring practical guide |
