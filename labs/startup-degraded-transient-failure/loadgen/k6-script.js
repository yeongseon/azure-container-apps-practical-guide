/* k6 load generator for startup-degraded-transient-failure lab.
 *
 * Sustains TARGET_RPS requests per second against SUBJECT_URL for
 * DURATION_SECONDS, with connection reuse disabled (each VU iteration
 * opens a fresh TCP connection). Emits per-request results and 10-second
 * client-side success/failure buckets to stdout as JSON lines, which
 * Container Apps ships to Log Analytics (ContainerAppConsoleLogs_CL).
 *
 * Environment variables:
 *   SUBJECT_URL        Full URL (e.g. https://app.<env-fqdn>/) to hammer.
 *   TARGET_RPS         Sustained requests-per-second (default 200).
 *   DURATION_SECONDS   Total test duration in seconds (default 1800).
 *   PERTURBATION_ID    Free-form tag (e.g. "rollout-event-3") that is
 *                      embedded in every JSON line for KQL join.
 *   RUN_ID             Free-form tag (e.g. "preflight" or "baseline" or
 *                      "perturbation") tying the run to its evidence file.
 *
 * Output schema:
 *   Per-request:      {"kind":"req","ts":...,"code":...,"dur_ms":...,...}
 *   Per-10s bucket:   {"kind":"bucket","ts":...,"window_s":10,
 *                      "ok":...,"err":...,"err_pct":...,...}
 *   Run header:       {"kind":"meta","ts":...,"phase":"start",...}
 *   Run footer:       {"kind":"meta","ts":...,"phase":"end",...}
 *
 * Falsification rule (issue #205): a single perturbation event is
 * considered a violation if there exists any window of >=3 consecutive
 * 10s buckets with err_pct > 0.5 during the event window.
 */

import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';
import exec from 'k6/execution';

const SUBJECT_URL = __ENV.SUBJECT_URL || 'http://localhost:8080/';
const TARGET_RPS = parseInt(__ENV.TARGET_RPS || '200', 10);
const DURATION_SECONDS = parseInt(__ENV.DURATION_SECONDS || '1800', 10);
const PERTURBATION_ID = __ENV.PERTURBATION_ID || 'none';
const RUN_ID = __ENV.RUN_ID || 'unspecified';

const BUCKET_WINDOW_S = 10;

const okCounter = new Counter('subject_ok');
const errCounter = new Counter('subject_err');

const buckets = {};

export const options = {
  scenarios: {
    constant_rps: {
      executor: 'constant-arrival-rate',
      rate: TARGET_RPS,
      timeUnit: '1s',
      duration: `${DURATION_SECONDS}s`,
      preAllocatedVUs: Math.max(50, Math.ceil(TARGET_RPS / 4)),
      maxVUs: Math.max(200, TARGET_RPS * 2),
      gracefulStop: '5s',
    },
  },
  thresholds: {
    'subject_err': ['count<999999999'],
  },
  noConnectionReuse: true,
  discardResponseBodies: true,
  insecureSkipTLSVerify: false,
};

function emit(obj) {
  obj.ts = new Date().toISOString();
  obj.run_id = RUN_ID;
  obj.perturbation_id = PERTURBATION_ID;
  obj.target_rps = TARGET_RPS;
  console.log(JSON.stringify(obj));
}

function bucketKey(epochMs) {
  return Math.floor(epochMs / (BUCKET_WINDOW_S * 1000)) * BUCKET_WINDOW_S;
}

export function setup() {
  emit({
    kind: 'meta',
    phase: 'start',
    subject_url: SUBJECT_URL,
    duration_s: DURATION_SECONDS,
    bucket_window_s: BUCKET_WINDOW_S,
  });
  return {};
}

export default function () {
  const nowMs = Date.now();
  const bk = bucketKey(nowMs);

  const params = {
    headers: { Connection: 'close' },
    tags: { perturbation_id: PERTURBATION_ID, run_id: RUN_ID },
    timeout: '10s',
  };

  const res = http.get(SUBJECT_URL, params);
  const ok = check(res, {
    'status is 2xx': (r) => r.status >= 200 && r.status < 300,
  });

  if (ok) {
    okCounter.add(1);
  } else {
    errCounter.add(1);
  }

  emit({
    kind: 'req',
    code: res.status,
    dur_ms: res.timings.duration,
    err_msg: res.error || '',
    ok: ok,
    iter: exec.scenario.iterationInTest,
  });

  if (!buckets[bk]) {
    buckets[bk] = { ok: 0, err: 0, count: 0 };
  }
  buckets[bk].count += 1;
  if (ok) {
    buckets[bk].ok += 1;
  } else {
    buckets[bk].err += 1;
  }

  // Flush any bucket older than the current window. Each bucket is
  // emitted exactly once, when a request from the NEXT window arrives,
  // which guarantees the bucket is complete (no late writes).
  for (const k of Object.keys(buckets)) {
    const kn = parseInt(k, 10);
    if (kn < bk) {
      const b = buckets[k];
      const errPct = b.count > 0 ? (b.err / b.count) * 100.0 : 0;
      emit({
        kind: 'bucket',
        window_s: BUCKET_WINDOW_S,
        bucket_start_epoch_s: kn,
        bucket_start_iso: new Date(kn * 1000).toISOString(),
        ok: b.ok,
        err: b.err,
        count: b.count,
        err_pct: Math.round(errPct * 1000) / 1000,
      });
      delete buckets[k];
    }
  }
}

export function teardown() {
  for (const k of Object.keys(buckets)) {
    const kn = parseInt(k, 10);
    const b = buckets[k];
    const errPct = b.count > 0 ? (b.err / b.count) * 100.0 : 0;
    emit({
      kind: 'bucket',
      window_s: BUCKET_WINDOW_S,
      bucket_start_epoch_s: kn,
      bucket_start_iso: new Date(kn * 1000).toISOString(),
      ok: b.ok,
      err: b.err,
      count: b.count,
      err_pct: Math.round(errPct * 1000) / 1000,
      final_flush: true,
    });
  }
  emit({ kind: 'meta', phase: 'end' });
}
