# pyright: reportMissingImports=false
import os

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from flask import Flask

app = Flask(__name__)

KEY_VAULT_URL = os.getenv("KEY_VAULT_URL", "")
SECRET_NAME = os.getenv("SECRET_NAME", "demo-secret")


def read_secret() -> str:
    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=KEY_VAULT_URL, credential=credential)
    return client.get_secret(SECRET_NAME).value


@app.get("/health")
def health() -> tuple[dict[str, str], int]:
    try:
        value = read_secret()
        return {"status": "ok", "secretLength": str(len(value))}, 200
    except Exception as exc:
        return {
            "status": "error",
            "message": f"Access denied or Key Vault read failed: {exc}",
        }, 500


@app.get("/")
def index() -> tuple[dict[str, str], int]:
    return {"message": "managed-identity-key-vault-failure lab workload"}, 200
