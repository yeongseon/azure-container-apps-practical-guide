---
content_sources:
  diagrams:
    - id: generated-2026-04-09
      type: pie
      source: self-generated
      justification: "Repository validation dashboard derived from local tutorial verification metadata; Microsoft Learn links identify the Azure Container Apps tutorials being tracked."
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/overview
        - https://learn.microsoft.com/en-us/azure/container-apps/get-started
---

# Tutorial Validation Status

This page tracks which tutorials have been validated against real Azure deployments. Each tutorial can be tested via **az-cli** (manual CLI commands) or **Bicep** (infrastructure as code). Tutorials not tested within 90 days are marked as stale.

## Summary

*Generated: 2026-04-09*

| Metric | Count |
|---|---:|
| Total tutorials | 28 |
| ✅ Validated | 0 |
| ⚠️ Stale (>90 days) | 0 |
| ❌ Failed | 0 |
| ➖ Not tested | 28 |

<!-- diagram-id: generated-2026-04-09 -->
```mermaid
pie title Tutorial Validation Status
    "Not Tested" : 28
```

## Validation Matrix

### .NET

| Tutorial | az-cli | Bicep | Last Tested | Status |
|---|---|---|---|---|
| [01 Local Development](../language-guides/dotnet/01-local-development.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [02 First Deploy](../language-guides/dotnet/02-first-deploy.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [03 Configuration](../language-guides/dotnet/03-configuration.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [04 Logging Monitoring](../language-guides/dotnet/04-logging-monitoring.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [05 Infrastructure As Code](../language-guides/dotnet/05-infrastructure-as-code.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [06 Ci Cd](../language-guides/dotnet/06-ci-cd.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [07 Revisions Traffic](../language-guides/dotnet/07-revisions-traffic.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |

### Java

| Tutorial | az-cli | Bicep | Last Tested | Status |
|---|---|---|---|---|
| [01 Local Development](../language-guides/java/01-local-development.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [02 First Deploy](../language-guides/java/02-first-deploy.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [03 Configuration](../language-guides/java/03-configuration.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [04 Logging Monitoring](../language-guides/java/04-logging-monitoring.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [05 Infrastructure As Code](../language-guides/java/05-infrastructure-as-code.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [06 Ci Cd](../language-guides/java/06-ci-cd.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [07 Revisions Traffic](../language-guides/java/07-revisions-traffic.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |

### Node.js

| Tutorial | az-cli | Bicep | Last Tested | Status |
|---|---|---|---|---|
| [01 Local Development](../language-guides/nodejs/01-local-development.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [02 First Deploy](../language-guides/nodejs/02-first-deploy.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [03 Configuration](../language-guides/nodejs/03-configuration.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [04 Logging Monitoring](../language-guides/nodejs/04-logging-monitoring.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [05 Infrastructure As Code](../language-guides/nodejs/05-infrastructure-as-code.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [06 Ci Cd](../language-guides/nodejs/06-ci-cd.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [07 Revisions Traffic](../language-guides/nodejs/07-revisions-traffic.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |

### Python

| Tutorial | az-cli | Bicep | Last Tested | Status |
|---|---|---|---|---|
| [01 Local Development](../language-guides/python/01-local-development.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [02 First Deploy](../language-guides/python/02-first-deploy.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [03 Configuration](../language-guides/python/03-configuration.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [04 Logging Monitoring](../language-guides/python/04-logging-monitoring.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [05 Infrastructure As Code](../language-guides/python/05-infrastructure-as-code.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [06 Ci Cd](../language-guides/python/06-ci-cd.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [07 Revisions Traffic](../language-guides/python/07-revisions-traffic.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |

## How to Update

To mark a tutorial as validated, add a `validation` block to its YAML frontmatter:

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

Then regenerate this page:

```bash
python3 scripts/generate_validation_status.py
```

!!! info "Validation fields"
    - `result`: `pass`, `fail`, or `not_tested`
    - `last_tested`: ISO date (YYYY-MM-DD) or `null`
    - `cli_version`: Azure CLI version used
    - Tutorials older than 90 days are flagged as **stale**

## See Also

- [Language Guides](../language-guides/index.md)
- [CLI Reference](cli-reference.md)
- [Environment Variables](environment-variables.md)
- [Platform Limits](platform-limits.md)

