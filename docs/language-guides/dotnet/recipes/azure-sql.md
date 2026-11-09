---
content_sources:
  diagrams:
    - id: architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview
        - https://learn.microsoft.com/en-us/sql/connect/ado-net/sql/azure-active-directory-authentication
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
---
# Azure SQL Integration (Managed Identity)

Use this recipe to connect Azure Container Apps to Azure SQL Database with Microsoft Entra authentication first and SQL authentication only as a fallback.

## Architecture

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    accTitle: Passwordless Azure SQL request from an ASP.NET Core container app
    accDescr: A client request reaches the app through managed ingress. SqlClient obtains a database access token through the app's managed identity, then opens an encrypted SQL connection. Azure SQL separately authorizes the contained database user and roles.
    CLIENT[Client]
    INGRESS[Managed ingress]
    APP[ASP.NET Core app<br/>Microsoft.Data.SqlClient]
    ENDPOINT[Container Apps identity endpoint]
    ENTRA[Microsoft Entra ID]
    SQL[Azure SQL Database]
    AUTHZ[Database authorization result]
    RESULT[Query result]
    DENIED[Authorization failure]

    CLIENT ==>|"HTTPS request"| INGRESS
    INGRESS ==>|"Routed request"| APP
    APP ==>|"Request database token"| ENDPOINT
    ENDPOINT ==>|"Token request"| ENTRA
    ENTRA ==>|"Access token response"| ENDPOINT
    ENDPOINT ==>|"Return access token"| APP
    APP ==>|"Encrypted SQL connection + token"| SQL
    SQL -->|"Evaluate database permissions"| AUTHZ
    AUTHZ -->|"Allowed"| RESULT
    AUTHZ -.->|"Denied"| DENIED
    RESULT ==>|"Query response"| APP
    DENIED -.->|"Authorization error"| APP
    APP ==>|"Application response"| INGRESS
    INGRESS ==>|"HTTPS response"| CLIENT
```

*Figure: Token acquisition, SQL transport, and database authorization are separate steps. Network reachability through a firewall rule, VNet path, or Private Link must already exist.*

## Prerequisites

- Existing Container App: `$APP_NAME` in `$RG`
- Existing Azure SQL logical server and database
- Azure SQL server configured with a Microsoft Entra admin
- Firewall rules, VNet integration, or Private Link already configured for your connectivity model

## Step 1: Enable managed identity on the Container App

```bash
az containerapp identity assign \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --system-assigned
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp identity assign` | For Azure SQL connectivity, enables the Container App identity that authenticates to the target Azure service. |
| `--name` | Targets Container App `$APP_NAME` for system-assigned identity enablement. |
| `--resource-group` | For Azure SQL connectivity, limits the operations in this block to resource group `$RG`. |
| `--system-assigned` | For Azure SQL connectivity, enables the system-assigned identity on the selected Container App. |

## Step 2: Grant SQL access to the app identity

From a Microsoft Entra-authenticated SQL session, create a contained user for the managed identity.

```sql
CREATE USER [<container-app-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [<container-app-name>];
ALTER ROLE db_datawriter ADD MEMBER [<container-app-name>];
```

## Step 3: Configure non-secret settings

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars SQL_SERVER="$SQL_SERVER.database.windows.net" SQL_DATABASE="$SQL_DATABASE"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp update` | Creates a revision of the app with its Azure SQL server and database settings. |
| `--name` | Updates the SQL client configuration on `$APP_NAME`. |
| `--resource-group` | For Azure SQL connectivity, limits the operations in this block to resource group `$RG`. |
| `--set-env-vars` | Sets `SQL_SERVER` to the logical-server FQDN and `SQL_DATABASE` to the target database. |

## Step 4: .NET code (managed identity)

Add the SQL client dependency:

```bash
dotnet add package Microsoft.Data.SqlClient
```

Use `Authentication=Active Directory Default` for passwordless access:

```csharp
using Microsoft.Data.SqlClient;

var builder = new SqlConnectionStringBuilder
{
    DataSource = Environment.GetEnvironmentVariable("SQL_SERVER"),
    InitialCatalog = Environment.GetEnvironmentVariable("SQL_DATABASE"),
    Encrypt = true,
    TrustServerCertificate = false,
    Authentication = SqlAuthenticationMethod.ActiveDirectoryDefault,
};

if (!string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SQL_USER")) &&
    !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SQL_PASSWORD")))
{
    builder.UserID = Environment.GetEnvironmentVariable("SQL_USER");
    builder.Password = Environment.GetEnvironmentVariable("SQL_PASSWORD");
    builder.Authentication = SqlAuthenticationMethod.SqlPassword;
}

await using var connection = new SqlConnection(builder.ConnectionString);
await connection.OpenAsync();

await using var command = new SqlCommand("SELECT TOP (1) name FROM sys.tables ORDER BY name", connection);
await using var reader = await command.ExecuteReaderAsync();

while (await reader.ReadAsync())
{
    Console.WriteLine(reader.GetString(0));
}
```

## Step 5: SQL authentication fallback

```bash
az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets sql-password="<sql-password>"

az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars SQL_SERVER="$SQL_SERVER.database.windows.net" SQL_DATABASE="$SQL_DATABASE" SQL_USER="$SQL_USER" SQL_PASSWORD=secretref:sql-password
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp secret set` | For Azure SQL connectivity, creates the Container Apps secret consumed by the application through `secretref:`. |
| `--name` | Stores the fallback credential and configures its reference on `$APP_NAME`. |
| `--resource-group` | For Azure SQL connectivity, limits the operations in this block to resource group `$RG`. |
| `--secrets` | For Azure SQL connectivity, stores the literal `sql-password="<sql-password>"` value as a Container Apps secret. |
| `az containerapp update` | Creates a revision that uses SQL authentication instead of the passwordless path. |
| `--set-env-vars` | Supplies the SQL endpoint, database, user, and `secretref:sql-password` password reference. |

## Verification

1. Confirm identity assignment.
2. Confirm runtime connectivity by checking application logs.
3. Confirm Azure SQL firewall or private endpoint connectivity before blaming authentication.

## See Also

- [Managed Identity](managed-identity.md)
- [VNet Integration](../../../platform/networking/vnet-integration.md)
- [Private Endpoints](../../../platform/networking/private-endpoints.md)

## Sources

- [Azure SQL and Microsoft Entra authentication overview](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview)
- [Microsoft Entra authentication with SqlClient](https://learn.microsoft.com/en-us/sql/connect/ado-net/sql/azure-active-directory-authentication)
- [Managed identities in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
