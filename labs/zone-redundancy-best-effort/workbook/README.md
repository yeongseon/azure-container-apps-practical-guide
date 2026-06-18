---
title: Workbook: Zone Redundancy Mass Reschedule
description: Deploy the Azure Monitor workbook for the zone-redundancy mass-reschedule lab.
---

# Workbook: Zone Redundancy Mass Reschedule

This folder packages an Azure Monitor workbook that turns Q3, Q4, and Q7 from the
[zone-redundancy mass-reschedule KQL pack](../../../docs/troubleshooting/kql/scaling-and-replicas/zone-redundancy-mass-reschedule.md)
into three saved visuals for the lab workspace.

## Prerequisites

- Azure CLI signed in to the subscription that hosts the lab resource group.
- The Log Analytics workspace resource ID for the lab environment, using this format:

```text
/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/<resource-group-name>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>
```

- A resource group variable for deployment:

```bash
export RG="<resource-group-name>"
export LAW_ID="/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/<resource-group-name>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>"
```

## Deploy

Run the workbook deployment from this directory:

```bash
az deployment group create \
  --resource-group "$RG" \
  --template-file workbook-arm.json \
  --parameters workbookSourceId="$LAW_ID"
```

The deployment creates a shared `Microsoft.Insights/workbooks` resource associated
with the supplied Log Analytics workspace so it appears in the workspace workbook gallery.

## Expected UI Behavior

### Panel 1 — Q3 Clustered Churn Detection

The table lists every 60-second window where the same app lost two or more replicas.
An empty result during a quiet baseline is expected; populated rows indicate concentrated churn.

### Panel 2 — Q4 Recovery Duration After Churn

The line chart plots `RecoverySecs` over time using `ChurnStart` as the time axis.
Separate app series make it easy to compare whether one app consistently recovers more slowly.

### Panel 3 — Q7 Multi-App Comparison

The bar chart compares `ClusteredChurnEvents` across `app-min2`, `app-min3`, and `app-min6`.
Higher bars indicate more frequent clustered churn for that app over the 24-hour query window.

## Cleanup

To remove the workbook resource directly:

```bash
az resource delete \
  --resource-group "$RG" \
  --resource-type "Microsoft.Insights/workbooks" \
  --name "<workbook-guid>"
```

If you only want to remove the deployment record after deleting the workbook resource:

```bash
az deployment group delete \
  --resource-group "$RG" \
  --name "<deployment-name>"
```

## See Also

- [Lab: Zone redundancy is best-effort](../../../docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md)
- [KQL pack: Zone-Redundancy Mass-Reschedule](../../../docs/troubleshooting/kql/scaling-and-replicas/zone-redundancy-mass-reschedule.md)
- [Lab infrastructure template](../infra/main.bicep)

## Sources

- [Microsoft.Insights/workbooks template reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.insights/workbooks)
- [Create Azure Monitor workbooks](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-create-workbook)
- [Azure Monitor workbooks and ARM templates](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-automate)
