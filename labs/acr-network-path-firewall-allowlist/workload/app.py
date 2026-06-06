"""
Minimal Flask workload for Lab: ACR Network Path A — Firewall Allowlist.

Scenario A central thesis: ACR's selected-networks IP rule must contain the
*firewall's outbound public IP*, NOT the replica's internal IP. The
falsification toggles this single value and observes fresh-pull behavior on
new revisions. The workload itself does not need to probe DNS or run a
4-layer reachability test — the evidence for this lab lives at three places
outside the replica:

  1. ACR network rule set (`az acr show --query networkRuleSet`)
  2. Azure Firewall application-rule logs in Log Analytics
  3. Container App revision health + system logs (PullingImage / PulledImage
     / FailedPulling for the new tag during the broken window)

The `/` endpoint reports the BUILD_TAG that was baked in at image build time,
so a successful HTTP response from a given revision proves that a fresh pull
of THAT tag from ACR has occurred. This is the simplest possible signal that
the image-pull data path through the firewall is working end-to-end.
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
            "message": "ACR firewall allowlist lab workload",
            "build_tag": BUILD_TAG,
        }
    )


@app.route("/health")
def health():
    return jsonify({"status": "healthy", "build_tag": BUILD_TAG}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
