# Lab Guides

Hands-on troubleshooting labs for Azure Container Apps with deployable infrastructure and scripted failure/recovery flows.

## Available Labs

| Lab | Description | Difficulty | Duration | Guide | Lab Files |
|---|---|---|---|---|---|
| ACR Image Pull Failure | Reproduces `ImagePullBackOff` from a non-existent image tag, then fixes image publishing/update. | Beginner | 20-30 min | [Guide](./acr-pull-failure.md) | [Directory](https://github.com/yeongseon/azure-container-apps-python-guide/tree/main/labs/acr-pull-failure) |
| Revision Failover and Rollback | Deploys a healthy revision, then breaks ingress port on a new revision and restores traffic. | Intermediate | 20-30 min | [Guide](./revision-failover.md) | [Directory](https://github.com/yeongseon/azure-container-apps-python-guide/tree/main/labs/revision-failover) |
| Scale Rule Mismatch | Uses unrealistic HTTP scaling thresholds to show non-scaling under load, then corrects KEDA settings. | Intermediate | 25-35 min | [Guide](./scale-rule-mismatch.md) | [Directory](https://github.com/yeongseon/azure-container-apps-python-guide/tree/main/labs/scale-rule-mismatch) |
| Probe and Port Mismatch | App listens on port 3000 while ingress targets 8000, causing probe failures until target port is fixed. | Beginner | 20-25 min | [Guide](./probe-and-port-mismatch.md) | [Directory](https://github.com/yeongseon/azure-container-apps-python-guide/tree/main/labs/probe-and-port-mismatch) |
| Managed Identity Key Vault Failure | App uses managed identity to read Key Vault secret but fails without `Key Vault Secrets User` role assignment. | Intermediate | 25-35 min | [Guide](./managed-identity-key-vault-failure.md) | [Directory](https://github.com/yeongseon/azure-container-apps-python-guide/tree/main/labs/managed-identity-key-vault-failure) |
| Revision Provisioning Failure | Revision fails because container env var references a missing secret; fixed by setting secret and deploying new revision. | Intermediate | 20-30 min | [Guide](./revision-provisioning-failure.md) | [Directory](https://github.com/yeongseon/azure-container-apps-python-guide/tree/main/labs/revision-provisioning-failure) |

## Suggested Learning Path

1. [ACR Image Pull Failure](./acr-pull-failure.md)
2. [Probe and Port Mismatch](./probe-and-port-mismatch.md)
3. [Revision Failover and Rollback](./revision-failover.md)
4. [Revision Provisioning Failure](./revision-provisioning-failure.md)
5. [Scale Rule Mismatch](./scale-rule-mismatch.md)
6. [Managed Identity Key Vault Failure](./managed-identity-key-vault-failure.md)

## See Also

- [Playbooks](../playbooks/index.md)
- [First 10 Minutes: Quick Triage Checklist](../first-10-minutes/index.md)
- [Troubleshooting Methodology](../methodology/index.md)
