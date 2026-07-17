# AGENTS.md

Guidance for AI agents working in this repository.

## Project Overview

**Azure Container Apps Practical Guide** — a comprehensive, hands-on guide for running containerized applications on Azure Container Apps, covering everything from initial deployment to advanced production troubleshooting.

- **Live site**: <https://yeongseon.github.io/azure-container-apps-practical-guide/>
- **Repository**: <https://github.com/yeongseon/azure-container-apps-practical-guide>

## Series-Wide Documentation Contract

This repository is part of the Azure Practical Guide series. All repositories in the series must preserve a consistent reader experience while allowing repository-specific extensions.

### Core Sections

Every service-focused repository SHOULD use these core sections unless the repository-specific addendum explains an exception.

| Section | Required | Purpose |
|---|---:|---|
| `Start Here` | Yes | Entry points, overview, learning paths, repository map |
| `Platform` | Yes | Service concepts, architecture, core behavior |
| `Best Practices` | Yes | Production patterns, anti-patterns, design guidance |
| `Operations` | Yes | Day-2 operational procedures and verification |
| `Troubleshooting` | Yes | Symptom-based diagnosis, playbooks, evidence collection |
| `Reference` | Yes | CLI, KQL, limits, glossary, decision tables |

### Approved Extension Sections

| Section | Use When |
|---|---|
| `Tutorials` | The repository provides hands-on learning or lab sequences |
| `Lab Guides` | Reproducible experiments or validation exercises are first-class content |
| `Language Guides` | The service has language/runtime-specific implementation tutorials |
| `SDK Guides` | The service is primarily consumed through SDKs |
| `Service Guides` | The repository configures or monitors multiple Azure services |
| `Workload Guides` | The repository is architecture/workload oriented |
| `Architecture Reviews` | The repository includes architecture review methodology and playbooks |
| `Design Labs` | The repository includes architecture design exercises |
| `Visualization` | Visual maps are a deliberate learning surface, not generated leftovers |
| `Meta` | Repository taxonomy, content model, or generated metadata |

Do not create a new top-level section if the content can fit under one of the core or approved extension sections.

## Container Apps Specific Addendum

This repository extends the series contract with the following content patterns specific to Container Apps:

- **Language Guides** — Per-runtime step-by-step tutorials for Python (Flask + Gunicorn), Node.js (Express), Java (Spring Boot), and .NET (ASP.NET Core), each covering local development through revisions and traffic splitting. Located under `docs/language-guides/*/tutorial/` with companion recipes under `docs/language-guides/*/recipes/`.
- **Reference Applications** — Minimal working applications under `apps/*/` (Python, Node.js, Java, .NET) that back the language-guide tutorials.
- **Reference Jobs** — Container Apps Jobs samples under `jobs/python/` (Python scheduled job with managed identity).
- **Troubleshooting Labs** — Reproducible Bicep-based labs under `labs/*/` that reproduce real-world failure modes. Every lab satisfies the 16 methodology concepts documented under [Content Types & Methodology](#content-types--methodology).
- **KQL Query Packs** — Production-ready Log Analytics and App Insights queries under `docs/troubleshooting/kql/`.
- **ACR Network Path Series** — A focused 5-lab family under `labs/acr-network-path-*` that reproduces the five distinct network paths a Container App can take to reach Azure Container Registry. See the [ACR Network Path Selection](docs/platform/networking/acr-network-path-selection.md) platform doc for the naming taxonomy.

These extensions live alongside the core sections and do not replace them.

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

## Start Here Rules

`Start Here` is orientation content. It must not become a language tutorial, SDK tutorial, operations runbook, troubleshooting playbook, or lab guide.

Required pages:

| Page | Purpose |
|---|---|
| `overview.md` | Who this guide is for, what is in scope, and what is out of scope |
| `learning-paths.md` | Role-based and experience-based reading paths |
| `repository-map.md` | Map of major sections and when to use them |

Optional pages:

| Page Pattern | Purpose |
|---|---|
| `when-to-use-*.md` | Service selection guidance |
| `prerequisites.md` | Required tools, permissions, and accounts |
| `common-scenarios.md` | Common use cases |
| `*-vs-other-compute.md` | Positioning against neighboring Azure services |
| `how-to-use-this-guide.md` | Reader navigation guidance |

`learning-paths.md` MUST:

- Start with role-based or goal-based paths.
- Link to tutorials instead of embedding a full tutorial sequence.
- Avoid service-specific code walkthroughs except short examples.
- Avoid `content_validation` unless this repository explicitly includes Start Here pages in content validation scope.

Preferred title:

```markdown
# Learning Paths
```

Avoid:

```markdown
# Tutorial: {Service} for {Language}
```

## Navigation Budget

The left navigation should help orientation, not expose every file.

Recommended:

- Top-level sections SHOULD stay between 6 and 9 items.
- Direct children under a top-level section SHOULD stay between 5 and 8 items.
- Large collections such as tutorials, recipes, KQL packs, lab guides, and playbooks SHOULD be listed on index pages rather than fully expanded in `mkdocs.yml`.
- Use hub pages, tables, tags, and search for deep inventory.
- Keep `mkdocs.yml` readable enough that a contributor can understand the site structure without scrolling through hundreds of deep links.

Preferred troubleshooting structure:

```text
Troubleshooting
├─ Overview
├─ Quick Diagnosis
├─ Decision Tree
├─ First 10 Minutes
├─ Playbooks
├─ KQL Query Packs
└─ Labs
```

Avoid exposing every individual playbook, KQL query, and lab guide in `mkdocs.yml` unless the repository is intentionally small.

## Content Validation Scope

`content_validation` is required for factual-claim pages, not for every Markdown file.

Required by default:

- `docs/platform/**`
- `docs/best-practices/**`
- `docs/operations/**`
- factual troubleshooting methodology/playbook pages

Usually out of scope:

- `docs/start-here/**`
- `docs/reference/**`
- `docs/language-guides/**`
- `docs/sdk-guides/**`
- `docs/tutorials/**`
- `docs/troubleshooting/kql/**`
- `docs/troubleshooting/lab-guides/**`
- generated dashboards
- navigation-only index pages

Content-type-specific rules:

- Tutorials use `validation`.
- Labs use evidence and falsification integrity.
- KQL packs document query purpose, expected interpretation, required tables, and assumptions.
- KQL packs do not need `content_validation` unless they make factual platform claims outside the query explanation.
- Never fabricate validation dates or test results.

## Mermaid Diagrams

Use Mermaid diagrams when they clarify architecture, flow, dependency, decision logic, or troubleshooting paths.

Required for:

- Platform architecture pages
- Complex operations pages
- Decision trees
- Troubleshooting playbooks with multi-step diagnosis
- Lab guides with failure progression or evidence timelines
- Architecture review or design decision flows

Optional for:

- Reference tables
- CLI cheatsheets
- Glossary pages
- Generated validation dashboards
- Short landing pages
- Simple tutorial steps where prose is clearer

Do not add a diagram just to satisfy a checkbox. A diagram must explain something better than prose or a table.

## Image and Screenshot Rules

Images must support the reader's task. Do not add screenshots only for decoration.

Every referenced image MUST have:

- Descriptive alt text.
- A nearby explanation of what the reader should verify.
- No real subscription IDs, tenant IDs, object IDs, emails, phone numbers, secrets, keys, connection strings, or customer data.
- Visual verification before merge when the image is referenced from Markdown.

Recommended explanation pattern:

```markdown
![Container App overview showing a healthy revision](../assets/example.png)

Purpose: Confirm why this image exists.
Look for: Tell the reader what values or states to confirm.
Expected result: State the healthy or expected condition.
Next step: Link the image to the next action.
```

Portal screenshots:

- Prefer text replacement over black-box redaction.
- Use black-box masking only for unavoidable avatar/profile pixels and only with the repository-approved mask color.
- If a screenshot cannot be visually verified, remove the Markdown reference or disclose the debt explicitly in the PR.

### Manifest-driven capture pipeline

Portal screenshots are managed as **build artifacts driven by a manifest** (`scripts/capture/`), not hand-placed files. Docs reference a screenshot by a **stable ID** via the `shot()` macro, so re-capturing a blade overwrites the same `.webp` and never requires editing markdown.

- Register every capture in `scripts/capture/manifest.yaml` with a stable `id` (equal to the file stem), `file` path under `docs/assets/`, and accurate `alt` text.
- Reference it in markdown with `[[[ shot("<id>") ]]]` (custom Jinja delimiters `[[[ ]]]` / `[[% %]]` / `[[# #]]`, configured in `mkdocs.yml`, avoid collisions with `{{ }}`).
- Encode/downscale raw PNGs to WebP with the `capture-optimize-webp` CLI; refresh existing captures through the `capture-diff-gate` CLI (both provided by the `azure-guide-capture-toolkit` package; below `diff_threshold` only `verified` is bumped, image bytes untouched).
- Screenshots may be committed as WebP produced by this pipeline. When a capture is optimized to WebP, the **final rendered `.webp`** — not only the raw PNG — MUST be visually verified for PII and caption accuracy before merge. A PII or caption defect introduced or hidden by re-encoding is treated the same as one in a raw PNG.
- See `scripts/capture/README.md` for the full workflow.

## Microsoft Learn URL Locale

All `learn.microsoft.com` URLs SHOULD use the `en-us` locale prefix.

Canonical form:

```text
https://learn.microsoft.com/en-us/azure/container-apps/...
```

Avoid locale-less URLs (URLs missing the `/en-us/` segment immediately after the hostname):

```text
https://learn.microsoft.com/<missing-locale>/azure/container-apps/...
```

The `<missing-locale>` placeholder marks the position where `/en-us/` must appear. A real locale-less URL would omit that segment entirely; the placeholder is used here only so this anti-pattern example does not trip the `scripts/normalize_mslearn_locale.py` CI gate.

Reason:

- Stable reader experience.
- Stable reviewer experience.
- Easier link checking.
- Less URL drift across repositories.

## Related Projects

| Repository | Description |
|---|---|
| [azure-virtual-machine-practical-guide](https://github.com/yeongseon/azure-virtual-machine-practical-guide) | Azure Virtual Machines practical guide |
| [azure-networking-practical-guide](https://github.com/yeongseon/azure-networking-practical-guide) | Azure Networking practical guide |
| [azure-storage-practical-guide](https://github.com/yeongseon/azure-storage-practical-guide) | Azure Storage practical guide |
| [azure-app-service-practical-guide](https://github.com/yeongseon/azure-app-service-practical-guide) | Azure App Service practical guide |
| [azure-functions-practical-guide](https://github.com/yeongseon/azure-functions-practical-guide) | Azure Functions practical guide |
| [azure-communication-services-practical-guide](https://github.com/yeongseon/azure-communication-services-practical-guide) | Azure Communication Services practical guide |
| [azure-container-apps-practical-guide](https://github.com/yeongseon/azure-container-apps-practical-guide) | Azure Container Apps practical guide |
| [azure-kubernetes-service-practical-guide](https://github.com/yeongseon/azure-kubernetes-service-practical-guide) | Azure Kubernetes Service (AKS) practical guide |
| [azure-architecture-practical-guide](https://github.com/yeongseon/azure-architecture-practical-guide) | Azure Architecture practical guide |
| [azure-monitoring-practical-guide](https://github.com/yeongseon/azure-monitoring-practical-guide) | Azure Monitoring practical guide |

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

Lab guides in `docs/troubleshooting/lab-guides/` MUST cover all 16 methodology concepts below. **These are *conceptual elements*** (the scientific-method skeleton of a reproducible experiment), **not literal Markdown headings.** The canonical H2 heading structure is the **Lab Guides template** in [Canonical Document Templates](#canonical-document-templates) below — that template lists the actual heading names AND the two evidence-section variants the repository accepts today (legacy: `## Expected Evidence`; richer: `## 5) Verification Queries` + `## 6) Portal Evidence`). The 16 methodology concepts below are distributed across whichever variant the lab uses.

The 16 methodology concepts (with the canonical section that typically carries each — section names below assume the richer evidence-section variant, parenthetical notes mark where the legacy variant differs):

1. **Question**: The specific problem being investigated. *(Page title + intro paragraph.)*
2. **Setup**: Infrastructure and environment preparation. *(`## 3) Runbook` → "Deploy infrastructure" subsection.)*
3. **Hypothesis**: The expected cause and behavior. *(`## 2) Hypothesis`.)*
4. **Prediction**: What should happen if the hypothesis is true. *(`## 2) Hypothesis`, "IF ... THEN ..." clauses.)*
5. **Experiment**: The steps taken to reproduce the issue. *(`## 3) Runbook`.)*
6. **Execution**: The actual running of the experiment. *(`## 4) Experiment Log`.)*
7. **Observation**: Raw data and logs collected. *(`## 4) Experiment Log` per-scenario evidence blocks tagged `[Observed]`.)*
8. **Measurement**: Quantified metrics (e.g., latency, error rates). *(Richer variant: `## 5) Verification Queries` KQL results + `## 6) Portal Evidence` metric captures. Legacy variant: `## Expected Evidence` table rows.)*
9. **Analysis**: Interpreting the observations and measurements. *(`## 4) Experiment Log` post-evidence prose; richer variant adds `## 6) Portal Evidence` Diagnose-and-Solve captures.)*
10. **Conclusion**: Confirming or refuting the hypothesis. *(`## 4) Experiment Log` summary.)*
11. **Falsification**: Proving that the fix works and the original theory was correct. *(`## 4) Experiment Log` → "Post-fix evidence" subsection. **Required.**)*
12. **Evidence**: Compiled logs, screenshots, or KQL results. *(Richer variant: `## 6) Portal Evidence` + `## 5) Verification Queries`. Legacy variant: `## Expected Evidence`. Both cite raw artifacts in `labs/<lab>/evidence/`.)*
13. **Solution**: The final fix or mitigation. *(`## 3) Runbook` → "Apply the fix" subsection or the fix trigger script.)*
14. **Prevention**: How to avoid this issue in the future. *(Richer variant: `## 6) Portal Evidence` operator takeaways. Both variants: the linked playbook.)*
15. **Takeaway**: The core lesson learned. *(`## Related Playbook` cross-link and/or the lab's `README.md` "Operator Takeaway".)*
16. **Support Takeaway**: Key points for support engineers or developers. *(`## Related Playbook` cross-link or `README.md` "Support Takeaway".)*

> Why this two-axis framing: every lab is both a Markdown document (needs a consistent heading structure for navigation, search, and CI link-checking) and a reproducible experiment (needs the scientific-method skeleton above). Restructuring all existing labs to use the 16 concepts as literal H2 headings would break the established navigation pattern that 19+ lab guides already follow. The methodology is enforced by reviewing whether each concept is *present*, not by counting H2 headings.
>
> Why two evidence-section variants: most labs (~27) use the legacy single `## Expected Evidence` section. Newer labs (memory-leak-oomkilled, keda-no-metrics-returned) split evidence into `## 5) Verification Queries` (KQL packs) and `## 6) Portal Evidence` (annotated screenshots) for richer reader UX. New labs SHOULD prefer the richer variant; existing labs MAY stay on the legacy variant.

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
az containerapp create --resource-group $RG --name $APP_NAME --environment $ACA_ENV_NAME --image myregistry.azurecr.io/myapp:latest

# NEVER use short flags in documentation
az containerapp create -g $RG -n $APP_NAME  # ❌ Don't do this
```

### Variable Naming Convention

| Variable | Description | Example |
|----------|-------------|---------|
| `$RG` | Resource group name | `rg-containerapps-demo` |
| `$APP_NAME` | Container app name | `ca-demo-app` |
| `$ACA_ENV_NAME` | Container Apps environment name | `cae-demo-env` |
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

#### Authenticating the capture browser (Conditional Access)

The capture browser MUST reuse a **device-compliant, interactively signed-in** session. A fresh, isolated Chromium — whether launched by standalone Playwright or by the MCP browser tool — is **not** an Intune-enrolled / device-compliant browser, so it CANNOT pass Microsoft Entra Conditional Access for the MSIT (`ms.portal.azure.com`) tenant. It loops on the sign-in / `ConditionalAccess/Enrollment` ("install Company Portal") wall. **Do not** burn cycles trying to defeat this from automation — it is a device-level security control, not a cookie problem.

Working pattern (attach to a real, human-authenticated Chrome over CDP — Chrome is the tested path for this repo; the same flow works for Edge/Chromium by substituting the binary path and `--user-data-dir`):

1. **Launch the user's Chrome with a dedicated debug profile and a remote-debugging port.** A dedicated `--user-data-dir` avoids Chrome's block on debugging the default profile, and OS-level Platform SSO / Company Portal still satisfies device compliance:
    ```bash
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
      --remote-debugging-port=9222 \
      --user-data-dir="$HOME/.chrome-portal-capture" \
      --no-first-run --no-default-browser-check \
      "https://ms.portal.azure.com/"
    ```
2. **The human signs in interactively (including MFA) and navigates to the target blade.** The agent CANNOT complete MFA — hand this step to the user explicitly and wait.
3. **Verify the port is bound before attaching:** `curl -s http://localhost:9222/json/version`, and poll `http://localhost:9222/json` to detect when the target blade URL has loaded.
4. **Attach Playwright over CDP** with `chromium.connectOverCDP('http://localhost:9222')`, pick the page whose URL contains `portal.azure.com`, apply the PII helper, then screenshot. `browser.close()` on a CDP-attached browser only detaches the debugger; it does NOT close the user's Chrome.

Security: the remote-debugging port grants full local control over an authenticated Portal session. Bind it only for the duration of the capture, never expose it beyond `localhost`, and close the debug-profile Chrome when finished.

Common failure: relaunching the Chrome binary while Chrome is already running (without a distinct `--user-data-dir`, via `open`, or against an already-locked profile) just opens a tab in the existing (non-debug) process and silently ignores `--remote-debugging-port`. With the dedicated debug profile shown above a separate instance usually starts correctly, but always confirm the port with `curl`/`nc` before assuming the debug instance is up.

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
4. **Verify** with the `read` tool on the PNG — this step is mandatory, not optional, and must happen before the PNG is referenced by any markdown file in the same change. Read the image **one PNG per Read call**; reading multiple large PNGs in parallel will exceed the provider's media-attachment size limit and the verification will silently truncate. Confirm visually:
    - **Blade content matches the caption claim.** The blade renders the resource named in the markdown caption (not a 401 "You don't have access" page, not a 403 "Forbidden" page, not a generic Portal error blade, not a different resource than claimed, not an empty/scaled-to-zero state when the caption claims populated content). A 401/403/blank-error capture is a hard P0 failure even when PII rules pass.
    - No `MICROSOFT NON-PRODUCTION` badge in top-right
    - No `ychoe@microsoft.com` or `Yeongseon Choe` anywhere
    - Subscription ID rendered as `00000000-0000-0000-0000-000000000000`
    - Subscription name rendered as `Visual Studio Enterprise Subscription`
    - Any Custom Domain Verification ID (or other long uppercase hex token) rendered as `AAAA…A`, never as a real value
    - Account avatar masked with solid Portal-blue (`#0078d4`), not a black rectangle
5. **If verification fails** → fix the helper / inline snippet / Portal navigation and re-capture. Never ship a capture with raw PII, a black-box mask, a 401/403 error page, or content that does not match what the markdown caption claims.

#### Text-only review disclosure

If a referenced PNG cannot be visually verified for any reason — `look_at` tool unavailable, Read tool repeatedly failing, multimodal model offline — that PNG is **not approved**. Three options, in order of preference:

1. **Block the merge** until visual verification is possible. This is the default.
2. **Remove the affected PNG reference** from the markdown and replace the visual evidence with structured prose plus reproducible `az` CLI commands. The PNG file may stay in the repo as raw evidence; the rule is about markdown-referenced captures only.
3. **Merge with explicit disclosure** in the PR description: state which PNG(s) were not visually verified, why, and what the follow-up plan is. This option exists for emergencies (urgent security fix, time-boxed customer escalation) and creates a debt that must be closed in a follow-up PR.

Oracle text-only review (Oracle reading the markdown caption and surrounding prose without seeing the PNG) is **not** a substitute for visual verification of the PNG itself. If Oracle approved a PR before visual verification happened, that approval is conditional on the visual step being completed before merge, and the PR author is responsible for explicitly confirming that step in the PR description.

**What the helper does NOT mask (and why it is acceptable):**

- URL bar / browser chrome — not part of the PNG output.
- `href` attribute values in the DOM — not rendered visually.
- Avatar image pixels — masked with solid Portal-blue rectangle (the only acceptable mask color).

If any of the above ever becomes visible in a capture, treat it as a P0 issue: fail the capture, fix the helper, and re-shoot.

**Per-lab capture matrices.** For the canonical list of Portal blades to capture in each troubleshooting lab — including filenames, blade selectors, and per-lab caveats (such as the `acr-pull-failure` manifest-missing-before-revision case and the `managed-identity-key-vault-failure` Log-stream-is-empty caveat) — see [`docs/contributing/lab-portal-capture-briefs.md`](docs/contributing/lab-portal-capture-briefs.md). That file is contributor- and agent-facing only; the rules above remain authoritative for *how* to capture, while the per-lab file documents *what* to capture for each lab.

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

3. **CI enforces drift:** the `Validate Content Sources` workflow runs `python scripts/normalize_yaml_frontmatter.py --check` and fails if any frontmatter would change. The workflow triggers on changes to `docs/**`, `scripts/**`, `apps/**`, `labs/**`, `infra/**`, `jobs/**`, the repo-root markdown files (`AGENTS.md`, `README*.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`), or the workflow itself, so that updates to the shared library or the normalizer always re-run the check. The trigger surface intentionally mirrors the `EXTENSIONS` scan set in `scripts/normalize_mslearn_locale.py` (`.md`, `.py`, `.yml`, `.yaml`, `.json`, `.bicep`, `.tf`, `.txt`) so a PR touching only `.json`/`.bicep`/`.tf` files under those paths cannot bypass the locale check. `ruamel.yaml` is pinned to a specific version in CI so the canonical bytes are reproducible across runs.
4. **Body is preserved byte-exact for the repo invariant (UTF-8, no BOM, LF line endings).** The normalizer only rewrites the YAML region between the two `---` delimiters; the blank line (or its absence) between the closing `---` and the first body line is preserved as-is. Files with a UTF-8 BOM are silently skipped (the regex won't match), and files with CRLF line endings would be converted to LF on `--apply` -- no such files exist in this repo today, but if that ever changes, update this policy first.

#### When to update this section

If [`scripts/lib/yaml_style.py`](scripts/lib/yaml_style.py) changes (different indent, width, or quoting policy), the table above MUST be updated in the same commit. The shared library is the source of truth; this section is the human-readable mirror.

### Per-Page SEO Description

MkDocs Material reads the `description:` field from page frontmatter and emits it as the page-level `<meta name="description">`, `<meta property="og:description">`, and `<meta name="twitter:description">` tags. Without this field, every page falls back to the global `site_description` from `mkdocs.yml`, which makes search engine and social card previews indistinguishable across pages.

**Required for:**

- All section landing pages (`docs/index.md`, `docs/<section>/index.md`, and subsection index pages).
- Top-level navigation hubs that are not literal `index.md` files (for example `docs/start-here/overview.md` is the canonical entry into the `start-here/` section even though it is not named `index.md`).
- Top-traffic content pages (homepage, learning paths, evidence-rich playbooks and labs as they get high-value Portal captures).

**Optional for:**

- Detail/reference pages — adding a unique description is encouraged but not required. The fallback to `site_description` is acceptable for low-traffic deep pages.

**Style:**

- 1-2 sentences, 120-160 characters preferred. Search engines truncate around 155-160 characters on desktop.
- Lead with the concrete topic ("Azure Container Apps platform concepts", "Day-2 production operations for Azure Container Apps") so the page is distinguishable from the homepage.
- Use plain prose, not keyword stuffing. The description is shown verbatim in search results.
- Place `description:` as the FIRST key in frontmatter (above `content_sources`, `content_validation`, etc.) for grep-ability.

**Example:**

```yaml
---
description: Azure Container Apps platform concepts — architecture, environments, revisions, scaling rules, networking, jobs, identity, and security.
content_sources:
  diagrams:
    - id: documents
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/
---
```

After adding or changing descriptions, rebuild with `mkdocs build --strict` and verify the resulting `<meta name=description>` in `site/<page>/index.html` matches the frontmatter.

### Admonition Indentation Rule

For MkDocs admonitions (`!!!` / `???`), every line in the body must be indented by **4 spaces**.

```markdown
!!! warning "Important"
    This line is correctly indented.

    - List item also inside
```

### Diagram Orientation Rule

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

A lab guide accepts one of two evidence-section variants. New labs SHOULD prefer the richer variant.

**Legacy variant** (used by ~27 existing labs):

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

**Richer variant** (used by `memory-leak-oomkilled`, `keda-no-metrics-returned`; recommended for new labs):

```text
# Title
Brief introduction
## Lab Metadata (table: difficulty, duration, tier, etc.)
## 1) Background
## 2) Hypothesis
## 3) Runbook
## 4) Experiment Log
## 5) Verification Queries   ← KQL pack with rule + falsification
## 6) Portal Evidence         ← annotated screenshots in docs/assets/troubleshooting/<lab>/
## Clean Up
## Related Playbook
## See Also
## Sources
```

A lab MAY include both `## Expected Evidence` AND `## 5) Verification Queries` + `## 6) Portal Evidence` (as `keda-no-metrics-returned.md` does). When a lab uses both, `## Expected Evidence` carries the pass/fail rule table and the richer sections carry the KQL + Portal artifacts.

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

#### Validator alignment with sibling repositories

The Container Apps validator (`scripts/validate_content_sources.py`) enforces the canonical `content_sources.diagrams[…]` shape on every Mermaid page. Legacy list-form `content_sources: [...]` and dict-form `{references: [...]}` (no `diagrams:` key) are both rejected on Mermaid pages; only `content-validation-status.md` and `validation-status.md` are filename-level skips, since those are generator-owned dashboards.

This repository completed migration to the canonical shape during Phase 2d (356 Mermaid pages audited, 0 validation errors as of Phase 2d Final).

The sibling Azure Functions guide does NOT enforce this policy yet: its `scripts/validate_content_sources.py` has a `get_diagram_sources()` helper that accepts the dict-form `{references: [...]}` escape on Mermaid pages, because the Functions guide carries approximately 295 Mermaid pages that pre-date the per-diagram provenance schema and rely on document-level provenance only. See the [Functions Phase 2d Final audit artifact](https://github.com/yeongseon/azure-functions-practical-guide/blob/main/docs/reference/phase-2d-final-audit.md) for cross-repository state. The sibling Azure App Service guide is at the same canonical-only state as this Container Apps guide.

A contributor moving a Mermaid page from the Functions guide into this repository MUST populate the canonical `diagrams:` list before opening the PR; copying a `references`-only page across will fail validation here. This is the intended cross-repo contract, not a misalignment.

#### Deferred to a future phase (no committed timeline)

Tightening the Functions validator to remove its `references` legacy escape — which would expose the ~295-page Functions backlog as hard errors and would block contributors who move Mermaid pages between the three sibling guides until the backlog is closed — is intentionally deferred. There is no committed timeline. That phase opens only when the Functions repository owner explicitly decides per-diagram provenance is now required policy.

Doctests covering the in-scope policy live in [`scripts/lib/content_scope.py`](scripts/lib/content_scope.py) (14 tests across `is_in_scope` and `is_tautological_text`) and are wired into the `validate-content-sources.yml` workflow as the first strict gate. If the in-scope policy is ever modified, those doctests MUST be updated in the same commit. A doctest gate is also wired for `scripts/validate_content_sources.py` for forward-compatibility, even though that file currently carries no doctests in this repository (the Functions sibling has its own doctests covering `get_diagram_sources()` behavior).

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

## Pre-Work State Verification (AI Agent Rule)

**Every AI agent starting work in this repository MUST run the following checklist BEFORE proposing or executing any action.** Session summaries — including summaries produced by prior turns of the same agent — may be stale, out of order, or partially reflect uncommitted intent. Never trust a summary without verifying against the actual repository state. This applies both to brand-new sessions (where the agent has zero prior context and must establish baseline state) and to continuation sessions (where the agent inherits a summary that may not match the current repository state).

### Pre-Work Checklist

1. **`git status`** — Is the working tree clean? Are there untracked files or directories?
2. **`git log --oneline -5`** — Has HEAD moved since the last summary claimed? What is the actual latest commit SHA?
3. **`git rev-parse HEAD origin/main`** — Is the local branch ahead of, behind, or diverged from the remote?
4. **`git diff --stat`** — If modified files exist, what is the scope? Which files? How many lines?
5. **For each modified file**: Read the actual diff before deciding what to do with it. Do not assume prior context described it correctly.
6. **For each untracked directory or file**: List its contents and understand the intent before deleting, ignoring, or acting on it.
7. **Report the observed state to the user** BEFORE proposing next steps. State what you found — do not paraphrase what a prior summary claimed.
8. **NEVER start mass changes** (rename sweeps, refactors touching 10+ files, cross-cutting formatting fixes) without first confirming there are zero uncommitted conflicts in the touched paths.

### Anti-Patterns Prevented

- **Trusting a stale summary**: A prior session summary said `HEAD = X` but a later commit was made outside the agent's visibility. Acting on the stale SHA can overwrite or contradict the newer commit.
- **Losing untracked evidence**: Untracked files (Portal screenshots, evidence pack captures, in-progress artifacts) can be silently destroyed by `git checkout`, `git clean`, or scripted resets triggered by a "let's start fresh" instinct.
- **Silently rebasing over an unpushed commit**: An unpushed local commit is invisible on the remote but not lost — a mass-refactor commit built on the wrong parent creates painful merge conflicts later.
- **Amending someone else's commit**: The HEAD commit may have been created by the user directly (not by the agent), in which case amending violates the amend-safety rules. Verify commit authorship via `git log -1 --format='%an %ae'` before considering any amend.

### When to Repeat

Re-run the checklist at the start of every continuation session, and again whenever any of these happens mid-session:

- A `<system-reminder>` fires (background task completes, todo continuation triggers).
- The user provides a new instruction that changes scope.
- Any `git` operation was performed by a subagent or external tool between agent turns.
- Before starting a commit, rebase, reset, or any mass file mutation.

**Violation of this checklist that results in destructive action against uncommitted work is a P0 mistake and MUST be reported to the user immediately.**

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

## Merge Policy (AI Agent Rule)

AI agents MAY merge their own pull requests **autonomously**, but ONLY after ALL of the mandatory gates below pass. There is no separate human approval step — passing every gate IS the approval. If any gate cannot be satisfied, the agent MUST stop and hand the PR to the user instead of merging.

### Mandatory merge gates (ALL required)

| # | Gate | How it is verified |
|---|---|---|
| 1 | **Oracle review ≥ 90/100** | Submit the final diff to Oracle for quality review. Score must be **90 or higher with no merge-blocking issues**. Any must-fix item is a blocker even at ≥ 90. |
| 2 | **CI fully green** | Every required GitHub Actions check on the PR head SHA passes. Verify with `gh pr checks <pr> --watch`; do not merge on `pending` or `failure`. |
| 3 | **Caption ↔ image match** | For every added/changed image referenced from markdown, the caption/alt text MUST accurately describe the actual rendered image. |
| 4 | **Final-image PII verification** | Every added/changed `.png`/`.webp` referenced from markdown MUST be visually verified (Read/`look_at`) for PII on the **final committed bytes** — zeroed subscription/tenant IDs, no employee identifiers, no black-box masks. WebP re-encodes are re-verified, not assumed from the raw PNG. |

### Merge procedure

1. Confirm gates 1-4 above, in order. Record the Oracle score and the visual-verification result in the PR thread or the final summary.
2. Merge with **squash-and-merge** only:

    ```bash
    gh pr merge <pr> --squash --delete-branch
    ```

3. Never use merge-commit or rebase-merge; squash keeps `main` history linear and collapses fixup commits.
4. Never bypass a failing or pending gate. Never merge with `--admin` to skip checks.

### When to stop instead of merging

- Oracle score < 90, or any unresolved must-fix.
- Any CI check failing or still pending.
- Any referenced image that cannot be visually verified.
- The PR touches something outside the agent's stated scope.

In these cases, report the blocking gate and hand off to the user.

## Git Commit Style

```text
type: short description
```

Allowed types: `feat`, `fix`, `docs`, `chore`, `refactor`
