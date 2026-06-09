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

### Portal Screenshot Capture (PII Replacement Rules)

Azure Portal screenshots in `docs/assets/troubleshooting/**/*.png` MUST use **text replacement** (not black-box redaction). Black rectangles look like leaks and break visual continuity; replaced placeholders read as documentation examples.

#### Capture method

Use the reusable helper at [`scripts/portal-capture-helpers.js`](scripts/portal-capture-helpers.js). Usage instructions for both standalone Playwright and MCP `browser_run_code_unsafe` are in [`scripts/portal-capture-helpers.md`](scripts/portal-capture-helpers.md).

The helper applies replacements to text nodes **and** `aria-label` attributes across the main frame and every nested iframe (Portal blades render inside iframes), then masks only the Account-menu avatar using Playwright's native `mask` option with Portal blue (`#0078d4`) so the masked region blends into the UI.

#### PII Replacement Rules

| Pattern | Replacement | Rationale |
|---|---|---|
| GUID (subscription, tenant, object, resource ID) | `00000000-0000-0000-0000-000000000000` | Zero-GUID is the documented Azure placeholder convention. Boundary-anchored to avoid eating GUID-shaped substrings inside longer hex tokens. |
| `MCAPS-*` / `MCAPS*` subscription names | `Visual Studio Enterprise Subscription` | MCAPS prefixes leak internal subscription naming. Word-bounded so identifiers like `XMCAPSinternal` are not partially rewritten. |
| `Microsoft Non-Production` tenant badge | `Contoso` | Tenant display name visible in the top-right Account button leaks the internal environment. |
| `*@microsoft.com` | `user@example.com` | Employee emails. Case-insensitive; trailing negative lookahead prevents `user@microsoft.com.uk`-style partial rewrites. |
| `*@*.onmicrosoft.com` | `user@example.com` | Tenant-scoped user emails. Case-insensitive; trailing negative lookahead prevents partial rewrites of longer hostnames. |
| `*.onmicrosoft.com` (bare domain) | `contoso.onmicrosoft.com` | Tenant domains. Trailing negative lookahead prevents partial rewrites of longer hostnames such as `tenant.onmicrosoft.com.uk`. |
| `ychoe` (employee alias) | `demouser` | Author alias, word-bounded so unrelated tokens are not touched. |
| `Yeongseon Choe` (display name) | `Demo User` | Author display name. |
| `yeongseon` (GitHub handle, bare token) | `demouser` | Author GitHub username surfaced in Deployment Center "Signed in as" panels and similar source-control integrations. Case-insensitive and word-bounded; runs AFTER the `Yeongseon Choe` rule so the full display-name form is preserved. |
| Uppercase hex token ≥ 32 chars (Custom Domain Verification ID, other SHA-256-style identifiers) | 64-char `AAAA…A` placeholder | Custom Domain Verification IDs and similar long uppercase hex strings are real account-scoped tokens that the GUID regex does not match. Boundary-anchored so shorter hex substrings inside other tokens are not partially rewritten. |
| Account-menu avatar (cannot be rewritten) | Native Playwright mask, `maskColor='#0078d4'` | Blends with Portal command bar. The helper throws if the avatar selector matches nothing. |

The replacement scope covers text nodes, `aria-label`, `title`, and the visible value of `input` / `textarea` controls so search bars and filter chips do not leak resource names.

#### Capture workflow rules

- **Re-navigate between captures.** Portal CSS is cumulative; leftover style injections from a previous capture leak into the next page (e.g. left-nav appearing as a black box). Always call `browser_navigate` to reload before applying the helper.
- **Use the Portal MSIT URL with tenant hint.** `https://ms.portal.azure.com/#@<tenant>.onmicrosoft.com/resource/...`. Plain `portal.azure.com` triggers a login redirect.
- **Prefer the English-language Portal.** The primary avatar selector keys off the English `aria-label` "Account menu"; a localized Portal may still match the `button.fxs-menu-account` fallback class, but that fallback is best-effort and not a stable contract. The helper throws if neither selector matches, so non-English captures should be reviewed manually.
- **Close every transient flyout, drawer, and command-bar dropdown** before capture. Account panel, Recent menu, notifications, and tenant switcher each surface PII the helper cannot fully rewrite (avatar thumbnails, embedded canvases, late-rendered iframe content).
- **Wait for the target blade to finish rendering** before applying replacements. The helper's 400 ms post-replacement pause is not a substitute for a per-blade `browser_wait_for` against stable text or an element on the blade.
- **Viewport: 1600 x 1000.** Captures the standard blade layout without horizontal scrollbars.
- **No black-box masking.** If a value cannot be rewritten and is not a known avatar/badge, fail the capture and update `PII_RULES` rather than fall back to a black rectangle.

If `PII_RULES` in the helper is updated, this table MUST be updated in the same commit.

#### Inline capture pattern (Playwright MCP `browser_run_code_unsafe`)

When capturing via the Playwright MCP `browser_run_code_unsafe` tool (no `require()` access), the PII helper must be **inlined** in the snippet. The inline rules MUST match `scripts/portal-capture-helpers.js` exactly; do not omit or alter any rule.

**Mandatory inline structure (per capture):**

```javascript
async (page) => {
  const PII_SCRIPT = `(() => {
    const subs = [
      { re: /(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])/gi, val: '00000000-0000-0000-0000-000000000000' },
      { re: /\\bMCAPS[-A-Za-z0-9_]*\\b/g, val: 'Visual Studio Enterprise Subscription' },
      { re: /Microsoft\\s+Non-Production/gi, val: 'Contoso' },
      { re: /\\b[A-Za-z0-9._%+-]+@microsoft\\.com(?![A-Za-z0-9.-])/gi, val: 'user@example.com' },
      { re: /\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.onmicrosoft\\.com(?![A-Za-z0-9.-])/gi, val: 'user@example.com' },
      { re: /\\b[A-Za-z0-9-]+\\.onmicrosoft\\.com(?![A-Za-z0-9.-])/gi, val: 'contoso.onmicrosoft.com' },
      { re: /\\bychoe\\b/gi, val: 'demouser' },
      { re: /Yeongseon\\s+Choe/g, val: 'Demo User' },
      { re: /\\byeongseon\\b/gi, val: 'demouser' },
      { re: /\\b[0-9A-F]{32,}\\b/g, val: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' },
    ];
    const apply = (s) => { let o=s; for (const {re,val} of subs){ re.lastIndex=0; o=o.replace(re,val);} return o; };
    const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    const nodes=[]; let n; while ((n=w.nextNode())) nodes.push(n);
    for (const node of nodes){ const o=node.textContent||''; const x=apply(o); if (x!==o) node.textContent=x; }
    document.querySelectorAll('[aria-label]').forEach(el=>{const o=el.getAttribute('aria-label')||'';const x=apply(o);if(x!==o)el.setAttribute('aria-label',x);});
    document.querySelectorAll('[title]').forEach(el=>{const o=el.getAttribute('title')||'';const x=apply(o);if(x!==o)el.setAttribute('title',x);});
    document.querySelectorAll('input, textarea').forEach(el=>{const o=el.value||'';const x=apply(o);if(x!==o)el.value=x;});
    return 'ok';
  })()`;
  const mf = page.mainFrame();
  await mf.evaluate(PII_SCRIPT);
  for (const f of page.frames()) { if (f===mf) continue; try { await f.evaluate(PII_SCRIPT); } catch(e){} }
  await page.waitForTimeout(500);
  const avatar = page.locator('button[aria-label*="Account menu"]').first();
  await page.screenshot({
    path: 'docs/assets/troubleshooting/<lab>/<NN>-<blade>-<state>.png',
    fullPage: false,
    mask: [avatar],
    maskColor: '#0078d4',
  });
  return 'captured';
}
```

**Backslash escaping rule (`browser_run_code_unsafe` JSON):**

- Regex escapes (`\b`, `\s`, `\.`) must be written as `\\b`, `\\s`, `\\.` in the inline string literal.
- The template literal itself goes inside the JSON `code` parameter, so the entire snippet is double-escaped one more level when passed as JSON.

**Per-capture mandatory steps (in order):**

1. **Navigate** to the target blade URL (`https://ms.portal.azure.com/#@<tenant>.onmicrosoft.com/resource/...`). Always re-navigate; never reuse a stale page.
2. **Wait** for blade-specific text (`browser_wait_for` with stable text on the blade) before applying replacements. The 500 ms post-replacement pause inside the snippet is not a substitute.
3. **Run the inline snippet** above via `browser_run_code_unsafe`. Replace `<lab>`, `<NN>`, `<blade>`, `<state>` in the screenshot path.
4. **Verify** with the `read` tool on the PNG. Confirm visually:
    - No `MICROSOFT NON-PRODUCTION` badge in top-right
    - No `ychoe@microsoft.com` or `Yeongseon Choe` anywhere
    - Subscription ID rendered as `00000000-0000-0000-0000-000000000000`
    - Subscription name rendered as `Visual Studio Enterprise Subscription`
    - Any Custom Domain Verification ID (or other long uppercase hex token) rendered as `AAAA…A`, never as a real value
    - Account avatar masked with solid Portal-blue (`#0078d4`), not a black rectangle
5. **If verification fails** → fix the helper / inline snippet and re-capture. Never ship a capture with raw PII or a black-box mask.

**What the helper does NOT mask (and why it is acceptable):**

- URL bar / browser chrome — not part of the PNG output.
- `href` attribute values in the DOM — not rendered visually.
- Avatar image pixels — masked with solid Portal-blue rectangle (the only acceptable mask color).

If any of the above ever becomes visible in a capture, treat it as a P0 issue: fail the capture, fix the helper, and re-shoot.

### Frontmatter YAML Style

Every Markdown file in `docs/` begins with a YAML frontmatter block delimited by `---`. The serialization style is **enforced by CI** and centralized in [`scripts/lib/yaml_style.py`](scripts/lib/yaml_style.py). Any script that mutates frontmatter MUST import `dump_frontmatter()` (preferred single-call API) or `build_yaml()` (for tools that need to call `load()` and `dump()` on the same instance) from that module — direct use of PyYAML's `yaml.dump()` is forbidden because it silently reformats files on every run (quoting dates, flattening nested sequences, folding multi-line strings), producing noisy diffs and unstable history.

#### Canonical style

| Setting | Value | Why |
|---|---|---|
| Library | `ruamel.yaml` (`typ='rt'`, round-trip mode) | Preserves comments, quoting, and key order across load/dump cycles. PyYAML cannot. |
| `indent(mapping=2, sequence=4, offset=2)` | `mapping=2`, `sequence=4`, `offset=2` | Matches the historical repository layout: list hyphens sit at column 4 under their parent key, list-item content at column 6. |
| `preserve_quotes` | `True` | Existing files are normalized for *structure* only; intentionally quoted dates and strings are kept as-is to avoid surprising semantic changes (e.g., `"2026-04-12"` becoming a `datetime.date` object). |
| `width` | `4096` | Practically disables line folding so long `claim`, `summary`, and `justification` strings stay on one line. Folding produces fragile diffs and harms grep-ability. |
| `explicit_end` | `False` | Frontmatter is delimited by a single closing `---` (no `...` document terminator). |

Example of correct style (matches the canonical output):

```yaml
---
content_sources:
  diagrams:
    - id: shift-traffic-only-when-release-criteria
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
        - https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting
        - https://learn.microsoft.com/en-us/azure/container-apps/blue-green-deployment
---
```

#### Workflow

1. **Never write frontmatter with PyYAML.** Any new generator or mutation tool MUST import `build_yaml()` (or the higher-level `dump_frontmatter()` helper) from `scripts/lib/yaml_style.py`. `dump_frontmatter()` is the public single-call API used by `scripts/normalize_yaml_frontmatter.py` itself; prefer it over instantiating `build_yaml()` and managing a `StringIO` buffer manually.
2. **Bulk normalize when needed:**

    ```bash
    python3 scripts/normalize_yaml_frontmatter.py --apply
    ```

3. **CI enforces drift:** the `Validate Content Sources` workflow runs `python scripts/normalize_yaml_frontmatter.py --check` and fails if any frontmatter would change. The workflow triggers on changes to `docs/**`, `scripts/**`, or the workflow itself, so that updates to the shared library or the normalizer always re-run the check. `ruamel.yaml` is pinned to a specific version in CI so the canonical bytes are reproducible across runs.
4. **Body is preserved byte-exact for the repo invariant (UTF-8, no BOM, LF line endings).** The normalizer only rewrites the YAML region between the two `---` delimiters; the blank line (or its absence) between the closing `---` and the first body line is preserved as-is. Files with a UTF-8 BOM are silently skipped (the regex won't match), and files with CRLF line endings would be converted to LF on `--apply` -- no such files exist in this repo today, but if that ever changes, update this policy first.

#### When to update this section

If [`scripts/lib/yaml_style.py`](scripts/lib/yaml_style.py) changes (different indent, width, or quoting policy), the table above MUST be updated in the same commit. The shared library is the source of truth; this section is the human-readable mirror.

### Admonition Indentation Rule

For MkDocs admonitions (`!!!` / `???`), every line in the body must be indented by **4 spaces**.

```markdown
!!! warning "Important"
    This line is correctly indented.

    - List item also inside
```

### Mermaid Diagrams

All architectural diagrams use Mermaid. Every documentation page should include at least one diagram. Test with `mkdocs build --strict`.

#### Diagram Orientation Rule

- **Sequential flows with 5+ nodes**: Use `flowchart TD` (top-down) to prevent horizontal overflow.
- **Short diagrams with fewer than 5 nodes**: `flowchart LR` (left-right) is acceptable.
- **Layered architecture diagrams** (e.g., network layers, stack diagrams): Always use `flowchart TD`.

```mermaid
%% CORRECT — 5+ node sequential flow uses TD
flowchart TD
    A[Commit] --> B[Build and test]
    B --> C[Package artifact]
    C --> D[Deploy to staging]
    D --> E[Validation]
    E --> F[Swap to production]

%% WRONG — long horizontal overflow
flowchart LR
    A[Commit] --> B[Build and test] --> C[Package] --> D[Deploy] --> E[Validate] --> F[Swap]
```

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

Factual-claim documents include a `content_validation` block in frontmatter to track the verification status of their core technical assertions.

The single source of truth for "is this page in scope?" is [`scripts/lib/content_scope.py`](scripts/lib/content_scope.py) — specifically the `is_in_scope(rel_path)` function. Both `scripts/generate_content_validation_status.py` and `scripts/remove_tautological_validation.py` import this helper, so the dashboard generator and the cleanup tool are guaranteed to agree on scope. If you change the scope policy, update both `scripts/lib/content_scope.py` AND this section in the same commit.

#### Scope

The `content_validation` block is **required** on factual-claim pages under these sections:

| Section | Required? | Examples |
|---|---|---|
| `docs/platform/` | Required (including factual subsection landing pages such as `platform/architecture/index.md`, `platform/networking/index.md`, and `platform/security/index.md`) | Architecture, environments, revisions, scaling, networking, jobs, security |
| `docs/best-practices/` | Required | Container design, revision strategy, scaling, networking, reliability |
| `docs/operations/` | Required (including factual subsection landing pages such as `operations/monitoring/index.md` and `operations/scaling/index.md`) | Deployment, monitoring, alerts, recovery, revision management, secret rotation |
| `docs/troubleshooting/` | Required, except for the `EXCLUDED_SUBPATHS` and `NAVIGATION_INDEXES` listed below | Playbooks, methodology pages, first-10-minutes runbooks |

The block is **out of scope** on these pages — the dashboard does not count them, the cleanup tool does not require them, and new pages added in these locations should not introduce a `content_validation` block:

- **Out-of-scope sections** — any path that does not start with `platform/`, `best-practices/`, `operations/`, or `troubleshooting/`. This covers `docs/start-here/`, `docs/reference/`, `docs/contributing/`, `docs/language-guides/` (tutorials and recipes), and `docs/index.md`.
- **`EXCLUDED_SUBPATHS`** under `troubleshooting/`:
    - `troubleshooting/kql/` — KQL query packs make no factual assertions of their own
    - `troubleshooting/lab-guides/` — labs use the evidence-integrity model (Falsification step) instead
- **`NAVIGATION_INDEXES`** — section landing pages that only introduce a section and make no factual claims:
    - `platform/index.md`
    - `best-practices/index.md`
    - `operations/index.md`
    - `operations/deployment/index.md`
    - `troubleshooting/index.md`
    - `troubleshooting/first-10-minutes/index.md`
    - `troubleshooting/playbooks/index.md`

Subsection landing pages that DO make factual claims (for example `platform/architecture/index.md`, `platform/networking/index.md`, `platform/security/index.md`, `operations/monitoring/index.md`, `operations/scaling/index.md`, and `troubleshooting/methodology/index.md`) are intentionally NOT in `NAVIGATION_INDEXES` — they are treated like any other factual-claim page.

Legacy `content_validation` blocks may still exist on a number of out-of-scope pages (notably under `docs/reference/`, `docs/start-here/`, `docs/troubleshooting/kql/`, and `docs/troubleshooting/lab-guides/`) from before this scope policy was formalized. These blocks are accepted but are not counted by the dashboard and were not touched by the tautological-claim cleanup; they will be reviewed in a follow-up editorial pass.

#### Schema

```yaml
---
content_sources:
  - type: mslearn-adapted
    url: https://learn.microsoft.com/en-us/azure/container-apps/...
content_validation:
  status: verified  # verified | pending_review | unverified
  last_reviewed: 2026-04-12
  reviewer: agent  # agent | human
  core_claims:
    - claim: "Container Apps supports automatic scaling based on HTTP traffic, CPU, memory, and custom metrics."
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: true
    - claim: "Revisions are immutable snapshots of a container app version."
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
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

1. Add `content_validation` only when the page is in scope per `scripts/lib/content_scope.is_in_scope`. Do NOT add it to out-of-scope pages (tutorials, recipes, reference look-ups, KQL packs, lab guides, navigation indexes).
2. If you create a new in-scope page, you MUST add `content_validation` to it.
3. Each `core_claim` MUST be a verifiable factual assertion about Azure behavior (a quoted limit, a documented feature behavior, a configuration default). Meta-statements such as "this page uses Microsoft Learn as the primary source basis" are tautological and forbidden — the marker text `primary source basis` (case-insensitive) is rejected by `scripts/generate_content_validation_status.py`. To clean up existing tautological blocks, run `python3 scripts/remove_tautological_validation.py --apply`.
4. List 2-5 core claims per page; each MUST cite a Microsoft Learn URL.
5. Set `status: verified` only when ALL core claims have verified sources.
6. Run `python3 scripts/generate_content_validation_status.py` after updates to regenerate `docs/reference/content-validation-status.md`.

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
| [azure-communication-services-practical-guide](https://github.com/yeongseon/azure-communication-services-practical-guide) | Azure Communication Services practical guide |
| [azure-kubernetes-service-practical-guide](https://github.com/yeongseon/azure-kubernetes-service-practical-guide) | Azure Kubernetes Service (AKS) practical guide |
| [azure-architecture-practical-guide](https://github.com/yeongseon/azure-architecture-practical-guide) | Azure Architecture practical guide |
| [azure-monitoring-practical-guide](https://github.com/yeongseon/azure-monitoring-practical-guide) | Azure Monitoring practical guide |
