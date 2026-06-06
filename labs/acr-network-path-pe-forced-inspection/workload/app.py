"""
Minimal Flask workload for Lab: ACR Network Path C — PE Forced Inspection.

Scenario C central thesis: when ACR is reached via a Private Endpoint and the
consuming subnet has a UDR pointing default-route to an inspection NVA (Azure
Firewall in this lab), PE traffic ONLY flows through the NVA when the UDR has
an EXPLICIT /32 route for each PE NIC IP. The default 0.0.0.0/0 route is
NOT sufficient because the system-injected /32 route for the PE wins on
longest-prefix match.

The falsification toggles the PRESENCE of the /32 UDR entries and observes
the smoking gun in Azure Firewall logs:

  - WITH /32 routes  -> AZFWApplicationRule logs ACR FQDN entries (proves
    the firewall is seeing ACR traffic, inspection is working).
  - WITHOUT /32 routes -> AZFWApplicationRule shows ZERO new entries for
    ACR FQDN even though pulls still succeed (proves traffic bypassed the
    firewall and went directly to PE via the system /32 route).

In BOTH cases the workload pull SUCCEEDS — that is the trap. Without firewall
log evidence, an operator cannot tell that inspection has been silently
bypassed. The whole point of Scenario C is that the failure mode is the
SILENCE in the firewall log, not a broken pull.

The `/` endpoint reports the BUILD_TAG that was baked at image build time.
A successful HTTP response from a given revision proves that revision was
freshly pulled from ACR. The lab uses 3 tags (v1, v-bypass, v-recover) so
that each deployment is content-different and must perform an actual fresh
layer pull rather than serving from the node's image cache.
"""

from __future__ import annotations

import os

from flask import Flask, jsonify

app = Flask(__name__)

BUILD_TAG = os.environ.get("BUILD_TAG", "unknown")


@app.route("/")
def index():
    return jsonify(
        {
            "message": "ACR PE forced inspection lab workload",
            "build_tag": BUILD_TAG,
        }
    )


@app.route("/health")
def health():
    return jsonify({"status": "healthy", "build_tag": BUILD_TAG}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
