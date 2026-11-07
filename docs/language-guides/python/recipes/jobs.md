---
content_sources:
  diagrams:
    - id: python-jobs-recipe-flow
      type: flowchart
      source: self-generated
      justification: Language recipe flow synthesized from repository Python job example and Microsoft Learn Jobs guidance.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/jobs
        - https://learn.microsoft.com/en-us/python/api/overview/azure/identity-readme
        - https://learn.microsoft.com/en-us/python/api/overview/azure/servicebus-readme
---
# Recipe: Jobs in Python on Azure Container Apps

Use this recipe to package a Python script as a manual Job, adapt it to a one-message Service Bus consumer, and add a dedup table pattern for safe replay.

## Prerequisites

- Azure Container Apps environment (`$ACA_ENV_NAME`)
- Azure Container Registry (`$ACR_NAME`)
- Azure Service Bus namespace and queue for the event-driven example
- Python 3.11+, Docker, and Azure CLI

```bash
export RG="rg-aca-python-prod"
export ACA_ENV_NAME="aca-env-python-prod"
export ACR_NAME="acrpythonprod"
export JOB_NAME="job-python-manual"
export EVENT_JOB_NAME="job-python-servicebus"
export SERVICEBUS_NAMESPACE="sb-aca-prod"
export SERVICEBUS_QUEUE="orders"
```

## What You'll Build

- a manual Python Job with a script entrypoint
- an event-driven Service Bus consumer that processes one message and exits
- a dedup-table pattern you can move to a durable database in production

## Steps

<!-- diagram-id: python-jobs-recipe-flow -->
```mermaid
flowchart TD
    accTitle: Build manual and event-driven Python jobs
    accDescr: Package a finite Python task as an image and create a manual job for on-demand execution. For a Service Bus event job, configure an authenticated scale rule, start one or more executions when messages are available, and make processing idempotent for retries.

    CODE[Finite Python task]
    IMAGE[Container image]
    JOB[Container Apps job definition]
    TRIGGER{Trigger type}
    MANUAL[Manual start]
    EVENT[Authenticated Service Bus<br/>scale rule]
    EXECUTION[Job execution]
    PROCESS[Process finite work<br/>and exit]
    DEDUP[Shared durable<br/>idempotency record]
    HISTORY[Execution history and logs]

    CODE --> IMAGE
    IMAGE --> JOB
    JOB --> TRIGGER
    TRIGGER -->|Manual| MANUAL
    TRIGGER -->|Event| EVENT
    MANUAL --> EXECUTION
    EVENT -->|Queue threshold met| EXECUTION
    EXECUTION ==>|Runs image| PROCESS
    PROCESS -.->|Checks and records message ID| DEDUP
    PROCESS --> HISTORY
```

Thick arrows show job execution. Thin and dotted arrows show trigger, evidence, and idempotency relationships.

### 1. Package a manual Python job

`job.py`:

```python
import json
import os
import sys
from datetime import datetime, timezone


def main() -> int:
    payload = {
        "event": "job-start",
        "execution": os.getenv("CONTAINER_APP_JOB_EXECUTION_NAME", "local"),
        "task": os.getenv("TASK_NAME", "reconcile-orders"),
        "started_at": datetime.now(timezone.utc).isoformat(),
    }
    print(json.dumps(payload))

    print(json.dumps({"event": "job-work", "message": "processing batch"}))
    print(json.dumps({"event": "job-end", "status": "Succeeded"}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

`requirements.txt`:

```text
azure-identity==1.17.1
azure-servicebus==7.13.0
```

`Dockerfile`:

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY job.py .

CMD ["python", "job.py"]
```

Build and deploy the manual Job:

```bash
az acr build \
  --registry "$ACR_NAME" \
  --image "python-jobs/manual:v1" \
  --file "Dockerfile" \
  "."

az containerapp job create \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --environment "$ACA_ENV_NAME" \
  --trigger-type "Manual" \
  --image "$ACR_NAME.azurecr.io/python-jobs/manual:v1" \
  --parallelism 1 \
  --replica-completion-count 1 \
  --replica-retry-limit 1 \
  --replica-timeout 600

az containerapp job start \
  --name "$JOB_NAME" \
  --resource-group "$RG"
```

| Command | Why it is used |
|---|---|
| `az acr build ...` | Builds and pushes the container image to Azure Container Registry. |

### 2. Adapt the container to an event-driven Service Bus consumer

Replace `job.py` with:

```python
import json
import os
from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient


fully_qualified_namespace = f"{os.environ['SERVICEBUS_NAMESPACE']}.servicebus.windows.net"
queue_name = os.environ["SERVICEBUS_QUEUE"]

credential = DefaultAzureCredential()
client = ServiceBusClient(fully_qualified_namespace=fully_qualified_namespace, credential=credential)

with client:
    receiver = client.get_queue_receiver(queue_name=queue_name, max_wait_time=15)
    with receiver:
        messages = receiver.receive_messages(max_message_count=1, max_wait_time=15)
        if not messages:
            print(json.dumps({"event": "empty-queue"}))
        else:
            message = messages[0]
            print(json.dumps({"event": "message-received", "message_id": message.message_id}))
            receiver.complete_message(message)
            print(json.dumps({"event": "message-completed", "message_id": message.message_id}))
```

Create the event-driven Job, assign its system identity, grant that identity the required Service Bus data roles on the queue or namespace, and then configure the scaler to use the same identity:

```bash
az acr build \
  --registry "$ACR_NAME" \
  --image "python-jobs/servicebus:v1" \
  --file "Dockerfile" \
  "."

az containerapp job create \
  --name "$EVENT_JOB_NAME" \
  --resource-group "$RG" \
  --environment "$ACA_ENV_NAME" \
  --trigger-type "Event" \
  --image "$ACR_NAME.azurecr.io/python-jobs/servicebus:v1" \
  --scale-rule-name "orders-queue" \
  --scale-rule-type "azure-servicebus" \
  --scale-rule-metadata "queueName=$SERVICEBUS_QUEUE" "messageCount=1" "namespace=$SERVICEBUS_NAMESPACE.servicebus.windows.net" \
  --replica-timeout 300 \
  --replica-retry-limit 1 \
  --env-vars SERVICEBUS_NAMESPACE="$SERVICEBUS_NAMESPACE" SERVICEBUS_QUEUE="$SERVICEBUS_QUEUE"

az containerapp job identity assign \
  --name "$EVENT_JOB_NAME" \
  --resource-group "$RG" \
  --system-assigned

# Grant this identity the least-privilege Service Bus data roles required by
# both the scaler and the message receiver before enabling identity auth.

az containerapp job update \
  --name "$EVENT_JOB_NAME" \
  --resource-group "$RG" \
  --scale-rule-name "orders-queue" \
  --scale-rule-type "azure-servicebus" \
  --scale-rule-metadata "queueName=$SERVICEBUS_QUEUE" "messageCount=1" "namespace=$SERVICEBUS_NAMESPACE.servicebus.windows.net" \
  --scale-rule-identity "system"
```

| Command | Why it is used |
|---|---|
| `az acr build ...` | Builds and pushes the container image to Azure Container Registry. |
| `az containerapp job create` | Creates the event-driven job and Service Bus scaling rule. |
| `--name` | Sets the job name. |
| `--resource-group` | Selects the resource group. |
| `--environment` | Selects the Container Apps environment. |
| `--trigger-type` | Configures the job to start from events. |
| `--image` | Selects the image that each execution runs. |
| `--scale-rule-name` | Names the Service Bus scale rule. |
| `--scale-rule-type` | Selects the Azure Service Bus scaler. |
| `--scale-rule-metadata` | Supplies the queue, threshold, and namespace metadata. |
| `--replica-timeout` | Limits execution duration. |
| `--replica-retry-limit` | Limits failed replica retries. |
| `--env-vars` | Passes non-secret namespace and queue settings to the Python process. |
| `az containerapp job identity assign` | Assigns the system identity used by the scaler and Python SDK. |
| `--system-assigned` | Enables the job's system-assigned identity. |
| `az containerapp job update` | Updates the existing job after its identity and Service Bus roles are ready. |
| `--scale-rule-identity` | Uses the job's system-assigned identity to authenticate the scaler. |

### 3. Add an idempotency guard with a dedup table

For a runnable local example, add a SQLite-backed dedup table. In production, move the same pattern to Azure SQL, PostgreSQL, or another shared durable store.

```python
import sqlite3


def should_process(message_id: str) -> bool:
    conn = sqlite3.connect("/tmp/dedup.db")
    conn.execute("create table if not exists processed_messages (message_id text primary key)")
    cursor = conn.execute(
        "insert or ignore into processed_messages(message_id) values (?)",
        (message_id,),
    )
    conn.commit()
    conn.close()
    return cursor.rowcount == 1
```

Call it before completing the message:

```python
if should_process(str(message.message_id)):
    print(json.dumps({"event": "process-message", "message_id": message.message_id}))
    receiver.complete_message(message)
else:
    print(json.dumps({"event": "duplicate-message", "message_id": message.message_id}))
    receiver.complete_message(message)
```

## Verification

```bash
az containerapp job execution list \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --output table

az containerapp job execution list \
  --name "$EVENT_JOB_NAME" \
  --resource-group "$RG" \
  --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp job execution ...` | Creates, updates, starts, or inspects a Container Apps job. |

### Verify job in Azure Portal

![cj-sample-d38538 | Container App Job | Run now | Suspend | Refresh | Delete | Resource group | Container Apps Environment | Workload profile | Provisioning status | Trigger Type | Execution history | Replica timeout | Replica retry limit | Parallelism | Completion count](../../../assets/language-guides/python/recipes/jobs-overview-blade.png)

**[Observed]** `cj-sample-d38538`. `Container App Job`. `Run now`. `Suspend`. `Refresh`. `Delete`. `Resource group`. `rg-aca-basics-d38538`. `Location`. `Korea Central`. `Subscription`. `Visual Studio Enterprise Subscription`. `Subscription ID`. `00000000-0000-0000-0000-000000000000`. `Container Apps Environme...`. `cae-basics-d38538`. `Log Analytics`. `law-basics-d38538`. `Workload profile`. `Consumption`. `Properties`. `Job`. `Provisioning status`. `Succeeded`. `Trigger Type`. `Manual`. `Execution history`. `View`. `Configuration`. `Replica timeout`. `300`. `Replica retry limit`. `1`. `Advanced`. `Parallelism`. `1`. `Completion count`. `1`.

**[Inferred]** The `Trigger Type` field reading `Manual` appears to map to the `--trigger-type "Manual"` lever passed to `az containerapp job create` in [Steps](#steps) Step 1. The `Replica timeout` value `300` appears to map to the `--replica-timeout 300` lever passed to `az containerapp job create` in [Steps](#steps) Step 2. The `Replica retry limit` value `1` appears to map to the `--replica-retry-limit 1` lever passed in [Steps](#steps) Steps 1 and 2. The `Parallelism` value `1` and `Completion count` value `1` appear to map to `--parallelism 1` and `--replica-completion-count 1` passed in [Steps](#steps) Step 1. The `Run now` toolbar action is consistent with the `az containerapp job start` invocation in [Steps](#steps) Step 1.

**[Not Proven]** Additional job trigger configuration, runtime parameter, and execution detail are not visible on this view.

## Next Steps / Clean Up

- Move the dedup table from SQLite to a shared durable database.
- Add Application Insights correlation fields to every log line.
- Revisit [Jobs Operations](../../../operations/jobs/index.md) before production rollout.

## See Also

- [Python Recipes Index](index.md)
- [Container Apps Jobs Overview](../../../platform/jobs/index.md)
- [Job Design](../../../best-practices/job-design.md)

## Sources

- [Jobs in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/jobs)
- [Azure Identity client library for Python](https://learn.microsoft.com/en-us/python/api/overview/azure/identity-readme)
- [Azure Service Bus client library for Python](https://learn.microsoft.com/en-us/python/api/overview/azure/servicebus-readme)
