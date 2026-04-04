# Lab Guides

Practice incident handling with short, reproducible labs designed for Azure Container Apps troubleshooting.

Each lab is scoped to complete in 15-30 minutes and mirrors production failure patterns.

## Available Labs

### 1) ACR Image Pull Failure

- **Description**: Reproduce `ImagePullBackOff` and fix registry/image/authentication problems.
- **Difficulty**: Beginner
- **Time estimate**: 20-25 minutes
- **What you'll learn**:
  - How to confirm image-tag and manifest issues
  - How managed identity and `AcrPull` affect startup
  - How private networking impacts registry access
- **Lab link**: [labs/acr-pull-failure/README.md](https://github.com/yeongseon/azure-container-apps-python-guide/blob/main/labs/acr-pull-failure/README.md)

### 2) Revision Failover and Rollback

- **Description**: Deploy a bad revision, observe health/traffic behavior, and restore service.
- **Difficulty**: Intermediate
- **Time estimate**: 20-30 minutes
- **What you'll learn**:
  - Revision lifecycle and health transitions
  - Safe rollback using traffic control
  - Multi-revision weighted rollout basics
- **Lab link**: [labs/revision-failover/README.md](https://github.com/yeongseon/azure-container-apps-python-guide/blob/main/labs/revision-failover/README.md)

### 3) Scale Rule Mismatch

- **Description**: Diagnose why app replicas do not scale as expected and correct KEDA rules.
- **Difficulty**: Intermediate
- **Time estimate**: 20-30 minutes
- **What you'll learn**:
  - HTTP and event-driven scaling behavior
  - Threshold/metric mismatch detection
  - Validation with logs and replica observations
- **Lab link**: [labs/scale-rule-mismatch/README.md](https://github.com/yeongseon/azure-container-apps-python-guide/blob/main/labs/scale-rule-mismatch/README.md)

## Recommended Order

1. Start with **ACR Image Pull Failure** to build baseline triage confidence.
2. Continue with **Revision Failover and Rollback** for deployment safety patterns.
3. Finish with **Scale Rule Mismatch** for production load behavior.

## Operational Habit

!!! tip "Capture evidence first"
    For every lab, record revision name, replica behavior, and exact error strings before applying a fix.

This mirrors real incident response and avoids guess-driven debugging.

## See Also

- [First 10 Minutes: Quick Triage Checklist](../first-10-minutes/index.md)
- [Troubleshooting Methodology](../methodology/index.md)
- [Playbooks](../playbooks/index.md)
