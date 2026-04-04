# pyright: reportMissingImports=false
import os
from flask import Flask

app = Flask(__name__)

PORT = int(os.getenv("APP_PORT", "3000"))


@app.get("/health")
def health() -> tuple[dict[str, str], int]:
    return {"status": "ok", "port": str(PORT)}, 200


@app.get("/")
def index() -> tuple[dict[str, str], int]:
    return {"message": "probe-and-port-mismatch lab workload"}, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
