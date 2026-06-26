# pyright: reportMissingImports=false, reportUnknownVariableType=false, reportUnknownMemberType=false, reportUntypedFunctionDecorator=false
from flask import Flask

app = Flask(__name__)


@app.get("/")
def index() -> tuple[str, int]:
    return "OK\n", 200


@app.get("/dapr/health")
def dapr_health() -> tuple[str, int]:
    return "OK\n", 200
