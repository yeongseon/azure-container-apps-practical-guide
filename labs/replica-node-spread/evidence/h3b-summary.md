# replica-node-spread evidence analysis

- Input files: labs/replica-node-spread/evidence/h3-restart-20260611-030836.jsonl
- Total raw rows: 12
- Sample rows: 6
- Mode: `h3b`

## H3 Part B — single-replica restart, new boot_id expected

### Set-based view (all pre vs all post)

- Pre-restart replicas: 3
- Post-restart replicas: 3
- NEW replicas (name not in pre-set): **1**
- New replicas with **fresh** boot_id: 1
- New replicas with **recycled** boot_id: 0

### Iteration-by-iteration view (chained pre/post)

- Iterations PASS (boot_id changed): **3**
- Iterations FAIL (boot_id recycled): 0
- Iterations INCOMPLETE (missing pre or post): 0

| iter | pre replica | post replica | pre boot_id | post boot_id | replica changed | boot_id changed | verdict |
|---|---|---|---|---|---|---|---|
| 0 | `ca-diag-consumption--0000001-78b467ff8c-ng8b4` | `ca-diag-consumption--0000001-56f7f6cd88-vrpfv` | `9707751f...` | `4aab3140...` | True | True | **PASS** |
| 1 | `ca-diag-consumption--0000001-56f7f6cd88-vrpfv` | `ca-diag-consumption--0000001-68c799886-c5dlf` | `4aab3140...` | `2323b271...` | True | True | **PASS** |
| 2 | `ca-diag-consumption--0000001-68c799886-c5dlf` | `ca-diag-consumption--0000001-568459d87c-r6sxb` | `2323b271...` | `e92d3da3...` | True | True | **PASS** |

- Overall verdict: **PASS**
