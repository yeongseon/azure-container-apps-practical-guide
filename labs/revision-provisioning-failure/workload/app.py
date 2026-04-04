# pyright: reportMissingImports=false
from flask import Flask

app = Flask(__name__)


@app.get("/health")
def health() -> tuple[dict[str, str], int]:
    return {"status": "ok"}, 200


@app.get("/")
def index() -> tuple[dict[str, str], int]:
    return {"message": "revision-provisioning-failure lab workload"}, 200
