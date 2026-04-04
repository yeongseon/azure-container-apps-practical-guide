# pyright: reportMissingImports=false
import hashlib
from flask import Flask

app = Flask(__name__)


def cpu_work(iterations: int = 40000) -> str:
    value = b"aca-scale-lab"
    for _ in range(iterations):
        value = hashlib.sha256(value).hexdigest().encode("utf-8")
    return value.decode("utf-8")[:16]


@app.get("/health")
def health() -> tuple[dict[str, str], int]:
    return {"status": "ok"}, 200


@app.get("/load")
def load() -> tuple[dict[str, str], int]:
    digest = cpu_work()
    return {"status": "processed", "digest": digest}, 200
