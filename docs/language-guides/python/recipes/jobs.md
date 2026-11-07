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
- A user-assigned identity (`$JOB_PULL_IDENTITY_ID`) attached to each job and granted the registry pull role appropriate to the registry permission mode
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
    TRIGGER[Select trigger type]
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
  --mi-user-assigned "$JOB_PULL_IDENTITY_ID" \
  --registry-server "$ACR_NAME.azurecr.io" \
  --registry-identity "$JOB_PULL_IDENTITY_ID" \
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
| `az acr build` | Builds the recipe image and pushes its tag to Azure Container Registry. |
| `az containerapp job create` | Creates the Container Apps job with the trigger and runtime settings shown here. |
| `az containerapp job start` | Starts one on-demand execution of the manual job. |
| `--registry` | Selects the Azure Container Registry used by this build or configuration step. |
| `--image` | Selects or tags the container image used by this recipe step. |
| `--file` | Selects the Dockerfile used to build this recipe image. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--resource-group` | Selects the resource group that contains this step's target resource. |
| `--environment` | Places the app or job in the specified Container Apps environment. |
| `--trigger-type` | Configures the job for manual or event-driven execution. |
| `--mi-user-assigned` | Attaches the preauthorized image-pull identity to the job. |
| `--registry-server` | Identifies the Azure Container Registry login server for the private image. |
| `--registry-identity` | Uses the attached managed identity to authenticate the private image pull. |
| `--parallelism` | Runs the documented number of replicas per job execution. |
| `--replica-completion-count` | Requires this number of replicas to complete successfully. |
| `--replica-retry-limit` | Limits retries for a failed job replica. |
| `--replica-timeout` | Stops a job replica after the documented execution limit. |



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
  --mi-user-assigned "$JOB_PULL_IDENTITY_ID" \
  --registry-server "$ACR_NAME.azurecr.io" \
  --registry-identity "$JOB_PULL_IDENTITY_ID" \
  --scale-rule-name "orders-queue" \
  --scale-rule-type "azure-servicebus" \
  --scale-rule-metadata "queueName=$SERVICEBUS_QUEUE" "messageCount=1" "namespace=$SERVICEBUS_NAMESPACE" \
  --replica-timeout 300 \
  --replica-retry-limit 1 \
  --env-vars SERVICEBUS_NAMESPACE="$SERVICEBUS_NAMESPACE" SERVICEBUS_QUEUE="$SERVICEBUS_QUEUE"

az containerapp job identity assign \
  --name "$EVENT_JOB_NAME" \
  --resource-group "$RG" \
  --system-assigned

# Grant this identity the least-privilege Service Bus data roles required by
# both the scaler and the message receiver before enabling identity auth.
export EVENT_JOB_PRINCIPAL_ID=$(az containerapp job show \
  --name "$EVENT_JOB_NAME" \
  --resource-group "$RG" \
  --query "identity.principalId" \
  --output tsv)

export SERVICEBUS_NAMESPACE_ID=$(az servicebus namespace show \
  --name "$SERVICEBUS_NAMESPACE" \
  --resource-group "$RG" \
  --query "id" \
  --output tsv)

az role assignment create \
  --assignee-object-id "$EVENT_JOB_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Azure Service Bus Data Receiver" \
  --scope "$SERVICEBUS_NAMESPACE_ID"

az containerapp job update \
  --name "$EVENT_JOB_NAME" \
  --resource-group "$RG" \
  --scale-rule-name "orders-queue" \
  --scale-rule-type "azure-servicebus" \
  --scale-rule-metadata "queueName=$SERVICEBUS_QUEUE" "messageCount=1" "namespace=$SERVICEBUS_NAMESPACE" \
  --scale-rule-identity "system"
```

| Command | Why it is used |
|---|---|
| `az acr build` | Builds the recipe image and pushes its tag to Azure Container Registry. |
| `az containerapp job create` | Creates the Container Apps job with the trigger and runtime settings shown here. |
| `az containerapp job identity assign` | Assigns the system identity used by the Service Bus scaler and worker. |
| `az containerapp job show` | Reads the event job's managed-identity principal ID. |
| `az servicebus namespace show` | Reads the Service Bus namespace resource ID used as the role scope. |
| `az role assignment create` | Grants the managed identity the data-plane role required by this step. |
| `az containerapp job update` | Enables managed-identity authentication on the event job's scaler. |
| `--registry` | Selects the Azure Container Registry used by this build or configuration step. |
| `--image` | Selects or tags the container image used by this recipe step. |
| `--file` | Selects the Dockerfile used to build this recipe image. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--resource-group` | Selects the resource group that contains this step's target resource. |
| `--environment` | Places the app or job in the specified Container Apps environment. |
| `--trigger-type` | Configures the job for manual or event-driven execution. |
| `--mi-user-assigned` | Attaches the preauthorized image-pull identity to the job. |
| `--registry-server` | Identifies the Azure Container Registry login server for the private image. |
| `--registry-identity` | Uses the attached managed identity to authenticate the private image pull. |
| `--scale-rule-name` | Names the event job's Service Bus scaling rule. |
| `--scale-rule-type` | Selects the KEDA Azure Service Bus scaler. |
| `--scale-rule-metadata` | Supplies the Service Bus namespace name, queue name, and message threshold. |
| `--replica-timeout` | Stops a job replica after the documented execution limit. |
| `--replica-retry-limit` | Limits retries for a failed job replica. |
| `--env-vars` | Passes these non-secret runtime settings to the Python container. |
| `--system-assigned` | Enables the system identity used by the app, job, or scaler. |
| `--query` | Extracts the exact resource property consumed by the next command. |
| `--output` | Returns the result in the format consumed by the shell or verification table. |
| `--assignee-object-id` | Targets the managed identity principal without a Microsoft Graph lookup. |
| `--assignee-principal-type` | Declares the managed identity as a service principal. |
| `--role` | Selects the least-privilege data-plane role required by this identity. |
| `--scope` | Limits the role or policy assignment to the resource used by this recipe. |
| `--scale-rule-identity` | Uses the job's system identity to authenticate the Service Bus scaler. |



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
| `az containerapp job execution list` | Lists recent executions for the selected job. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--resource-group` | Selects the resource group that contains this step's target resource. |
| `--output` | Returns the result in the format consumed by the shell or verification table. |



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
