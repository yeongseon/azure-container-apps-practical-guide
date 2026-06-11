# replica-node-spread evidence analysis

- Input files: labs/replica-node-spread/evidence/dedicated-20260611-040440.jsonl, labs/replica-node-spread/evidence/dedicated-rev0000004-20260611-051517.jsonl
- Total raw rows: 74
- Sample rows: 58
- Mode: `scale`

## Profile: Dedicated-D8

### Dedicated-D8 — `rev0000004-scale-24` (replicas sampled: 21)

- Unique `boot_id`: **1**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **1**
- Uptime range: 9404.8s - 10127.5s (spread 722.8s)

| boot_id (truncated) | count |
|---|---|
| `353c41a2...` | 21 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 21 | 1781145614.92 | 3.31 |

### Dedicated-D8 — `scale-1-run1` (replicas sampled: 1)

- Unique `boot_id`: **1**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **1**
- Uptime range: 5105.7s - 5105.7s (spread 0.0s)

| boot_id (truncated) | count |
|---|---|
| `353c41a2...` | 1 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 1 | 1781145618.749 | 0.0 |

### Dedicated-D8 — `scale-10-run1` (replicas sampled: 8)

- Unique `boot_id`: **1**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **1**
- Uptime range: 5317.5s - 5655.9s (spread 338.4s)

| boot_id (truncated) | count |
|---|---|
| `353c41a2...` | 8 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 8 | 1781145618.506 | 1.074 |

### Dedicated-D8 — `scale-24-run1` (replicas sampled: 9)

- Unique `boot_id`: **1**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **1**
- Uptime range: 5991.6s - 6205.4s (spread 213.8s)

| boot_id (truncated) | count |
|---|---|
| `353c41a2...` | 9 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 9 | 1781145614.88 | 1.47 |

### Dedicated-D8 — `scale-24-run2` (replicas sampled: 9)

- Unique `boot_id`: **1**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **1**
- Uptime range: 6289.7s - 6624.5s (spread 334.8s)

| boot_id (truncated) | count |
|---|---|
| `353c41a2...` | 9 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 9 | 1781145614.765 | 1.064 |

### Dedicated-D8 — `scale-24-run3` (replicas sampled: 7)

- Unique `boot_id`: **1**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **1**
- Uptime range: 6673.3s - 6967.4s (spread 294.1s)

| boot_id (truncated) | count |
|---|---|
| `353c41a2...` | 7 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 7 | 1781145614.983 | 1.663 |

### Dedicated-D8 — `scale-3-run1` (replicas sampled: 3)

- Unique `boot_id`: **1**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **1**
- Uptime range: 5204.1s - 5220.9s (spread 16.8s)

| boot_id (truncated) | count |
|---|---|
| `353c41a2...` | 3 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 3 | 1781145618.469 | 1.423 |


## Cross-revision boot_id check (key finding)

The Dedicated app went through **two scale ladders on two revisions**:

| Revision | Top scale reached | Sample count | Unique boot_id | Same boot_id as other revs? |
|---|---|---|---|---|
| `ca-diag-dedicated--0000003` | 10 (workload profile) | 37 | 1 (`353c41a2...`) | n/a (first rev) |
| `ca-diag-dedicated--0000004` | 24 (workload profile) | 21 | 1 (`353c41a2...`) | **YES — identical** |

**Interpretation (Inferred):** The D8 node identified by `boot_id=353c41a2-8e44-4b63-a877-9277bf184dbe` persisted across both revision rollouts and absorbed all 24 replicas of revision 0000004. Consistent with the D8 workload profile being backed by a single node in this environment for the duration of the experiment. This is NOT direct node identification — the proxy signal is the kernel boot identifier, which is unique per boot but invariant within one running kernel.

**Correction of earlier hypothesis:** The original `trigger.sh` wait loop timed out at 300s when the dedicated app was asked to scale to 24 replicas, leaving the app at the 10-replica intermediate state (revision 0000003 row above). A new revision 0000004 was then created via a follow-up `az containerapp update` for forensic capture; it successfully reached 24/24 ready replicas, demonstrating that the 300s timeout — not D8 capacity — was the bottleneck.
