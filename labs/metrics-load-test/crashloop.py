from __future__ import annotations

import os
import sys
import time


# Intentional OOM-killer trigger: allocate 16 MiB chunks every 200ms until cgroup memory limit kills the container.
# Container Apps will record a restart in RestartCount; new replica starts; loop repeats. Used for metrics demo only.
def grow_until_oomkilled() -> None:
    held: list[bytearray] = []
    chunk_mb = int(os.environ.get("CHUNK_MB", "16"))
    interval_ms = int(os.environ.get("INTERVAL_MS", "200"))
    sys.stdout.write(f"crashloop: chunk={chunk_mb}MiB interval={interval_ms}ms\n")
    sys.stdout.flush()
    while True:
        block = bytearray(chunk_mb * 1024 * 1024)
        for i in range(0, len(block), 4096):
            block[i] = 1
        held.append(block)
        held_mb = sum(len(b) for b in held) // (1024 * 1024)
        sys.stdout.write(f"crashloop: held={held_mb}MiB\n")
        sys.stdout.flush()
        time.sleep(interval_ms / 1000.0)


if __name__ == "__main__":
    grow_until_oomkilled()
