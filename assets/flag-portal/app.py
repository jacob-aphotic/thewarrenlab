#!/usr/bin/env python3
"""Lapin Logistics — Golden Carrot Submission portal.

Accepts flag submissions via a web form on 0.0.0.0:1337.
Validates by comparing SHA-256 of the submitted value against known digests.
No plaintext flag appears anywhere in this file.

Run (dev):  python3 app.py
Run (prod): gunicorn -w 1 -b 0.0.0.0:1337 app:app
"""

from __future__ import annotations

import hashlib
import hmac

from flask import Flask, render_template, request, session

app = Flask(__name__)
# Secret key for signed session cookies.  Generated at authoring time; not
# derived from or related to any flag value.
app.secret_key = "ll-golden-carrot-portal-8a2c9f4e1d7b"

# ---------------------------------------------------------------------------
# Flag slot definitions.
# Each entry: (slot_id, display_label, sha256_hex_digest)
# NO plaintext flag value appears here or anywhere in this app.
# Digests were computed as:
#   hashlib.sha256(<flag_bytes>).hexdigest()
# ---------------------------------------------------------------------------
_FLAG_SLOTS: list[tuple[str, str, str]] = [
    (
        "flag1",
        "Rabbit Run",
        "1b3794ea79416debdb034b9cd2edf255325a311336f1abc82c47b94d00abe7af",
    ),
    (
        "flag2",
        "Thumper's Tip",
        "1052822fc164967b89dddb701b008c8c0ccc8bcde8551edabfdc82e3dbee9f30",
    ),
    (
        "flag3",
        "Golden Carrot",
        "f9e849def21673ba270a85b801133eb04da5739747e016c58dd5f62858b0c9e5",
    ),
]

# Mapping from slot_id -> (label, digest) for O(1) lookup.
_SLOT_MAP: dict[str, tuple[str, str]] = {
    sid: (label, digest) for sid, label, digest in _FLAG_SLOTS
}


def _check_flag(submitted: str) -> str | None:
    """Return the slot_id if *submitted* matches any known flag digest, else None.

    Uses hmac.compare_digest for timing-safe comparison so an attacker cannot
    measure response time to learn anything about partial matches.
    """
    candidate = hashlib.sha256(submitted.strip().encode()).hexdigest()
    for slot_id, (_label, digest) in _SLOT_MAP.items():
        if hmac.compare_digest(candidate, digest):
            return slot_id
    return None


def _get_captured() -> set[str]:
    """Return the set of captured slot_ids from the signed session cookie."""
    raw = session.get("captured")
    if isinstance(raw, list):
        return set(raw)
    return set()


def _set_captured(captured: set[str]) -> None:
    session["captured"] = list(captured)
    session.modified = True


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/healthz")
def healthz():
    return "ok", 200


@app.route("/", methods=["GET", "POST"])
def index():
    captured = _get_captured()
    message: str | None = None
    message_type: str = "neutral"   # "success" | "error" | "neutral"
    matched_label: str | None = None

    if request.method == "POST":
        submitted = request.form.get("flag", "")
        if not submitted.strip():
            message = "Please enter a flag before submitting."
            message_type = "error"
        else:
            slot_id = _check_flag(submitted)
            if slot_id is None:
                message = "Not a valid flag. Keep digging."
                message_type = "error"
            elif slot_id in captured:
                label = _SLOT_MAP[slot_id][0]
                message = f"You already captured \"{label}\" — well done again."
                message_type = "success"
            else:
                captured.add(slot_id)
                _set_captured(captured)
                label = _SLOT_MAP[slot_id][0]
                matched_label = label
                message = f"Flag captured: \"{label}\"!"
                message_type = "success"

    slots = [
        {
            "id": sid,
            "label": label,
            "captured": sid in captured,
        }
        for sid, label, _digest in _FLAG_SLOTS
    ]
    total = len(_FLAG_SLOTS)
    count = len(captured)

    return render_template(
        "index.html",
        slots=slots,
        total=total,
        count=count,
        message=message,
        message_type=message_type,
        matched_label=matched_label,
    )


# ---------------------------------------------------------------------------
# Dev entry point — never reached under gunicorn
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=1337, debug=False)
