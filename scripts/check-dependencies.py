#!/usr/bin/env python3
"""Fail closed if SwiftPM selects a revision without a reviewed, aged release."""
import datetime
import json
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parent.parent
lock = json.loads((root / "Package.resolved").read_text())
audit = json.loads((root / "docs/dependency-audit.json").read_text())
now = datetime.datetime.now(datetime.timezone.utc)
for pin in lock["pins"]:
    identity = pin["identity"]
    approved = audit.get(identity)
    if not approved or approved["revision"] != pin["state"]["revision"] or approved["version"] != pin["state"].get("version"):
        sys.exit(f"Unreviewed dependency: {identity}. Review it and verify release age before updating the audit.")
    published = datetime.datetime.fromisoformat(approved["publishedAt"].replace("Z", "+00:00"))
    if (now - published).total_seconds() < 86400:
        sys.exit(f"Dependency is less than 24 hours old: {identity}")
    print(f"Verified {identity} {approved['version']} ({approved['revision'][:12]})")
