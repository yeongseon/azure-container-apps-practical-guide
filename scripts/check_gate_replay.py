"""Delete declared outputs, replay, and compare with gates committed at HEAD."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from time import perf_counter
from typing import Final

STAMP: Final = "evaluated_at_utc"
STAMP_FORMAT: Final = "%Y-%m-%dT%H:%M:%SZ"


def check_replay(lab_name: str, gates: list[str], verify_args: list[str]) -> int:
    """Run from the repository root; only the declared derived files are deleted."""
    lab = Path("labs") / lab_name
    evidence = lab / "evidence"
    committed = {}
    for name in gates:
        path = evidence / name
        show = subprocess.run(
            ["git", "show", f"HEAD:{path.as_posix()}"],
            capture_output=True, text=True, check=False,
        )
        if show.returncode:
            print(f"{name}: not committed at HEAD, so it cannot be compared", file=sys.stderr)
            return 1
        committed[name] = json.loads(show.stdout)

    for name in gates:
        (evidence / name).unlink(missing_ok=True)
    start = datetime.now(timezone.utc).replace(microsecond=0)
    timer = perf_counter()
    result = subprocess.run(["bash", str(lab / "verify.sh"), *verify_args], check=False, timeout=60)
    end = datetime.now(timezone.utc).replace(microsecond=0)
    print(f"{lab_name}: replay took {perf_counter() - timer:.3f} seconds")
    if result.returncode:
        return result.returncode

    failures: list[str] = []
    for name in gates:
        path = evidence / name
        try:
            current = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as error:
            failures.append(f"{name}: missing or invalid newly emitted JSON: {error}")
            continue
        expected = committed[name]
        for label, document in (("emitted", current), ("committed", expected)):
            if not isinstance(document, dict):
                failures.append(f"{name}: {label} document is not a JSON object")
                continue
            value = document.pop(STAMP, None)
            try:
                stamp = datetime.strptime(value, STAMP_FORMAT).replace(tzinfo=timezone.utc)
            except (TypeError, ValueError):
                failures.append(f"{name}: {label} {STAMP}={value!r} is not an ISO-8601 UTC timestamp")
                continue
            if stamp.strftime(STAMP_FORMAT) != value:
                failures.append(f"{name}: {label} {STAMP} is not in canonical UTC format")
            if label == "emitted" and not start <= stamp <= end:
                failures.append(f"{name}: emitted {STAMP} is outside the invocation window")
            if "utc_captured" in document:
                failures.append(f"{name}: {label} document has a top-level utc_captured")
        if json.dumps(current, sort_keys=True) != json.dumps(expected, sort_keys=True):
            failures.append(f"{name}: re-verification changed the gate beyond {STAMP}")

    if failures:
        print("The committed evidence pack no longer matches the verifier:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print(f"All {len(gates)} gate JSONs reproduce exactly, modulo {STAMP}.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lab")
    parser.add_argument("gates", nargs="+")
    parser.add_argument("--verify-arg", action="append", default=[])
    args = parser.parse_args()
    return check_replay(args.lab, args.gates, args.verify_arg)


if __name__ == "__main__":
    sys.exit(main())
