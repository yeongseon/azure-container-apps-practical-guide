# replica-node-spread evidence analysis

- Input files: labs/replica-node-spread/evidence/h3-same-replica-20260611-030836.jsonl
- Total raw rows: 4
- Sample rows: 2
- Mode: `h3a`

## H3 Part A — same-replica idempotence

- Replicas verified: 1
- PASS: **1**, FAIL: **0**

| replica | boot_id stable | uptime monotonic | uptime delta (s) | wall delta (s) | within 5s | verdict |
|---|---|---|---|---|---|---|
| `ca-diag-consumption--0000001-78b467ff8c-ng8b4` | True | True | 53.81 | 53.707 | True | **PASS** |
