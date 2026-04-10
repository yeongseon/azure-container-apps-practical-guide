# AGENTS.md

## Project Overview
**Project Name:** Azure Container Apps Practical Guide
**Description:** A comprehensive, hands-on guide for running containerized applications on Azure Container Apps, covering everything from initial deployment to advanced production troubleshooting.
**Core Mission:** Provide reproducible, evidence-based troubleshooting labs and playbooks that bridge the gap between "it's broken" and "it's fixed" using a structured methodology.

## Repository Structure
- `apps/`: Minimal reference applications demonstrating Container Apps patterns.
    - `python/`: Flask + Gunicorn implementation.
    - `nodejs/`: Express.js implementation.
    - `java-springboot/`: Spring Boot implementation.
    - `dotnet-aspnetcore/`: ASP.NET Core implementation.
- `docs/`: Markdown documentation source for the MkDocs site.
    - `troubleshooting/`: Primary area for methodology, playbooks, and KQL query packs.
        - `playbooks/`: Detailed guides for specific failure scenarios.
        - `lab-guides/`: Step-by-step instructions for reproducing and solving issues.
        - `kql/`: Repository of Kusto Query Language (KQL) snippets for diagnostics.
    - `platform/`, `best-practices/`, `language-guides/`, `operations/`: General guide content.
- `infra/`: Bicep/Terraform templates for infrastructure provisioning.
- `labs/`: Infrastructure and scripts used to reproduce troubleshooting scenarios in the labs.
- `mkdocs.yml`: Configuration for the documentation site, including navigation and plugins.

## Content Types & Methodology

### 1. Troubleshooting Experiments (Labs)
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

### 2. Evidence Levels
When documenting troubleshooting steps or analysis, use these tags to specify the strength of the evidence:
- `[Observed]`: Directly seen in logs, metrics, or UI (e.g., 503 errors in Log Analytics).
- `[Measured]`: Quantified data (e.g., 99th percentile latency is 4.5s).
- `[Correlated]`: Two events happening together without proven causation.
- `[Inferred]`: Conclusion based on logic and multiple pieces of evidence.
- `[Strongly Suggested]`: High confidence inference but missing the "smoking gun".
- `[Not Proven]`: Hypothesis that has not yet been validated.
- `[Unknown]`: Missing data or ambiguous behavior.

## Technical Standards & Conventions

### 1. Language Usage
- **Shell**: Use `bash` for all CLI examples.
- **Python**: Use `python` for all script examples.
- **KQL**: Use `kusto` for all Kusto Query Language blocks.
- **Mermaid**: Use `mermaid` for all architecture and flow diagrams.

### 2. CLI Standards
- Always use long flags for Azure CLI commands (e.g., `--resource-group` instead of `-g`).
- Ensure no Personally Identifiable Information (PII) is included in CLI output examples.

### 3. Documentation Style
- All content must reference official Microsoft Learn documentation with source URLs where applicable.
- Use `admonitions` (note, warning, tip) for highlighting critical information.
- Ensure all documents include a Mermaid diagram to visualize the concept or flow.

## Content Source Requirements

### 1. MSLearn-First Policy
All content MUST be traceable to official Microsoft Learn documentation:

- **Platform content** (`docs/platform/`): MUST have direct MSLearn source URLs
- **Architecture diagrams**: MUST reference official Microsoft documentation
- **Troubleshooting playbooks**: MAY synthesize MSLearn content with clear attribution
- **Self-generated content**: MUST have justification explaining the source basis

### 2. Source Types
| Type | Description | Allowed? |
|---|---|---|
| `mslearn` | Directly from Microsoft Learn | ✅ Required for platform content |
| `mslearn-adapted` | MSLearn content adapted for this guide | ✅ With source URL |
| `self-generated` | Original content for this guide | ⚠️ Requires justification |
| `community` | From community sources | ❌ Not for core content |
| `unknown` | Source not documented | ❌ Must be validated |

### 3. Diagram Source Documentation
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

### 4. Content Validation Tracking
- See [Content Validation Status](docs/reference/content-validation-status.md) for current status
- See [Tutorial Validation Status](docs/reference/validation-status.md) for tutorial testing

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

## Build & Contribution
- **Build Command**: `pip install mkdocs-material mkdocs-minify-plugin && mkdocs build`
- **Development Server**: `mkdocs serve`
- **Git Commit Types**:
    - `feat`: New lab, playbook, or guide section.
    - `fix`: Correction of technical inaccuracies or broken links.
    - `docs`: General documentation improvements (typos, clarity).
    - `chore`: Updates to build scripts, dependencies, or metadata.
    - `refactor`: Restructuring existing content without changing the technical meaning.
