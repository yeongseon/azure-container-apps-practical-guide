# replica-node-spread evidence analysis

- Input files: labs/replica-node-spread/evidence/consumption-20260611-033404.jsonl
- Total raw rows: 110
- Sample rows: 41
- Mode: `scale`

## Profile: Consumption

### Consumption — `scale-1-run1` (replicas sampled: 1)

- Unique `boot_id`: **1**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **1**
- Uptime range: 370.4s - 370.4s (spread 0.0s)

| boot_id (truncated) | count |
|---|---|
| `3401a9fc...` | 1 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 1 | 1781148517.692 | 0.0 |

### Consumption — `scale-10-run1` (replicas sampled: 4)

- Unique `boot_id`: **4**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **4**
- Uptime range: 407.1s - 607.9s (spread 200.8s)

| boot_id (truncated) | count |
|---|---|
| `2323b271...` | 1 |
| `32a24eee...` | 1 |
| `7b161726...` | 1 |
| `ef36eca4...` | 1 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 1 | 1781148574.15 | 0.0 |
| 2 | 1 | 1781148598.891 | 0.0 |
| 3 | 1 | 1781148635.055 | 0.0 |
| 4 | 1 | 1781148685.033 | 0.0 |

### Consumption — `scale-3-run1` (replicas sampled: 3)

- Unique `boot_id`: **3**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **3**
- Uptime range: 311.1s - 837.8s (spread 526.7s)

| boot_id (truncated) | count |
|---|---|
| `fe127cc4...` | 1 |
| `e92d3da3...` | 1 |
| `c1616d62...` | 1 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 1 | 1781148145.564 | 0.0 |
| 2 | 1 | 1781148341.497 | 0.0 |
| 3 | 1 | 1781148667.817 | 0.0 |

### Consumption — `scale-30-run1` (replicas sampled: 13)

- Unique `boot_id`: **13**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **11**
- Uptime range: 187.8s - 59829.6s (spread 59641.7s)

| boot_id (truncated) | count |
|---|---|
| `1c654ccb...` | 1 |
| `217f2e92...` | 1 |
| `6eb3515e...` | 1 |
| `660e7eb1...` | 1 |
| `da466be6...` | 1 |
| `35703076...` | 1 |
| `f8d24d60...` | 1 |
| `b53bbbc3...` | 1 |
| `a7076add...` | 1 |
| `253c9260...` | 1 |
| `c28288b6...` | 1 |
| `a8df6c20...` | 1 |
| `b0d5cd2e...` | 1 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 1 | 1781089681.008 | 0.0 |
| 2 | 1 | 1781109326.948 | 0.0 |
| 3 | 1 | 1781134873.059 | 0.0 |
| 4 | 1 | 1781143918.758 | 0.0 |
| 5 | 1 | 1781148497.328 | 0.0 |
| 6 | 1 | 1781148578.862 | 0.0 |
| 7 | 1 | 1781148611.553 | 0.0 |
| 8 | 2 | 1781148675.174 | 4.789 |
| 9 | 1 | 1781149061.086 | 0.0 |
| 10 | 1 | 1781149081.87 | 0.0 |
| 11 | 2 | 1781149102.976 | 1.8 |

### Consumption — `scale-30-run2` (replicas sampled: 10)

- Unique `boot_id`: **10**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **10**
- Uptime range: 791.7s - 17155.5s (spread 16363.8s)

| boot_id (truncated) | count |
|---|---|
| `e92d3da3...` | 1 |
| `f72c0dc5...` | 1 |
| `8f791585...` | 1 |
| `35703076...` | 1 |
| `1cd32519...` | 1 |
| `378155dd...` | 1 |
| `253c9260...` | 1 |
| `68ef66f6...` | 1 |
| `b2154e2b...` | 1 |
| `b0d5cd2e...` | 1 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 1 | 1781132693.744 | 0.0 |
| 2 | 1 | 1781139064.673 | 0.0 |
| 3 | 1 | 1781148020.362 | 0.0 |
| 4 | 1 | 1781148497.989 | 0.0 |
| 5 | 1 | 1781148578.849 | 0.0 |
| 6 | 1 | 1781148805.109 | 0.0 |
| 7 | 1 | 1781148821.09 | 0.0 |
| 8 | 1 | 1781148938.643 | 0.0 |
| 9 | 1 | 1781149003.54 | 0.0 |
| 10 | 1 | 1781149103.483 | 0.0 |

### Consumption — `scale-30-run3` (replicas sampled: 10)

- Unique `boot_id`: **10**
- Unique `machine_id`: 0
- Unique kernel release: 1
- Unique microcode: 1
- `boot_time_estimate` clusters (±5s): **10**
- Uptime range: 1125.0s - 40755.7s (spread 39630.7s)

| boot_id (truncated) | count |
|---|---|
| `1c654ccb...` | 1 |
| `e92d3da3...` | 1 |
| `8f791585...` | 1 |
| `660e7eb1...` | 1 |
| `1cd32519...` | 1 |
| `5e52bccd...` | 1 |
| `f8d24d60...` | 1 |
| `253c9260...` | 1 |
| `b2154e2b...` | 1 |
| `c1616d62...` | 1 |

| cluster | size | center epoch | internal spread (s) |
|---|---|---|---|
| 1 | 1 | 1781109326.999 | 0.0 |
| 2 | 1 | 1781139064.562 | 0.0 |
| 3 | 1 | 1781143876.946 | 0.0 |
| 4 | 1 | 1781143918.723 | 0.0 |
| 5 | 1 | 1781148020.11 | 0.0 |
| 6 | 1 | 1781148805.427 | 0.0 |
| 7 | 1 | 1781148821.089 | 0.0 |
| 8 | 1 | 1781148999.851 | 0.0 |
| 9 | 1 | 1781149061.181 | 0.0 |
| 10 | 1 | 1781149103.042 | 0.0 |

