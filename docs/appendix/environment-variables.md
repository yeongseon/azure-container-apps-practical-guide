# Environment Variables and Configuration Reference

This reference lists common environment variables used by the Python application and Azure Container Apps.

## Application-specific Variables

These variables are defined in your Python application and passed to the container at runtime.

| Variable Name | Description | Default Value | Example Value |
| --- | --- | --- | --- |
| `FLASK_ENV` | Sets the application environment (Flask) | `production` | `development` |
| `LOG_LEVEL` | Minimum log level (DEBUG, INFO, etc.) | `INFO` | `DEBUG` |
| `DB_CONNECTION_STRING` | Azure SQL or PostgreSQL connection string | - | `secretref:db-connection` |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Connection string for App Insights | - | `InstrumentationKey=...` |
| `STORAGE_ACCOUNT_NAME` | Name of the Azure Storage Account | - | `mystorageaccount` |

## Container Apps System Variables

Azure Container Apps provides several system-defined environment variables that your Python application can use.

| Variable Name | Description | Example |
| --- | --- | --- |
| `CONTAINER_APP_NAME` | The name of your Container App | `my-python-app` |
| `CONTAINER_APP_REVISION` | The name of the current active Revision | `my-python-app--v1` |
| `CONTAINER_APP_REPLICA_NAME` | The unique name of the current replica | `my-python-app--v1-abc123` |
| `CONTAINER_APP_ENV_DNS_SUFFIX` | The DNS suffix for the ACA Environment | `eastus.azurecontainerapps.io` |

## Best Practices

- **Use Secrets for sensitive data:** Use the `secretref:` prefix to pull secrets from ACA into environment variables.
- **Reference Managed Identity:** For Azure services that support it, use Managed Identity instead of connection strings with passwords.
- **Define Defaults:** In your Python code, provide sensible defaults for optional environment variables using `os.environ.get('VAR_NAME', 'default_value')`.
