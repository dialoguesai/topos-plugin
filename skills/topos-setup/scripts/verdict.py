#!/usr/bin/env python3
"""Turn checks.jsonl (from check-node.sh) into one verdict line. Run with `python3 -I`.

Verdict rules, deliberately strict (mirrors the house topos-install-qa skill):
  FAILED       any check failed.
  GOOD TO GO   every check passed, nothing blocked or skipped.
  INCOMPLETE   nothing failed, but something was blocked or skipped.

INCOMPLETE exists because "no failures" and "verified" are different claims. A
check that could not be observed must not be reported as working. Exit 1 on
FAILED so a script can gate on it.
"""
from __future__ import annotations

import json
import pathlib
import sys

ORDER = {"fail": 0, "blocked": 1, "skip": 2, "pass": 3}
VALID = set(ORDER)


def verdict(checks: list[dict]) -> tuple[str, str]:
    if not checks:
        return "INCOMPLETE", "no checks recorded"
    bad = [c for c in checks if c.get("status") not in VALID]
    if bad:
        return "FAILED", f"{len(bad)} check(s) carry an unknown status"
    fails = sum(1 for c in checks if c["status"] == "fail")
    if fails:
        return "FAILED", f"{fails} check{'s' if fails != 1 else ''} failed"
    blocked = sum(1 for c in checks if c["status"] == "blocked")
    skipped = sum(1 for c in checks if c["status"] == "skip")
    if blocked or skipped:
        bits = []
        if blocked:
            bits.append(f"{blocked} blocked")
        if skipped:
            bits.append(f"{skipped} skipped")
        return "INCOMPLETE", ", ".join(bits) + " — not verified"
    return "GOOD TO GO", f"all {len(checks)} checks passed"


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: verdict.py checks.jsonl [--client NAME]", file=sys.stderr)
        return 2
    src = pathlib.Path(sys.argv[1])
    client = "agent"
    if "--client" in sys.argv[2:]:
        i = sys.argv.index("--client")
        if i + 1 < len(sys.argv):
            client = sys.argv[i + 1]
    checks: list[dict] = []
    for line in src.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            checks.append({"id": "?", "status": "corrupt", "name": "unreadable check line", "detail": line[:80]})
            continue
        if isinstance(obj, dict):
            checks.append(obj)
    # A client name recorded in the checks (c4's name) wins over the flag.
    import re

    for c in checks:
        m = re.match(r"Agent (\S+) is approved", str(c.get("name", "")))
        if m:
            client = m.group(1)
            break

    v, why = verdict(checks)
    print(f"Topos setup ({client}): {v} ({why})")
    for c in sorted(checks, key=lambda c: (ORDER.get(c.get("status"), -1), str(c.get("id")))):
        print(f"  {str(c.get('status', '?')).upper():7} {c.get('id', '?')}  {c.get('name', '')} — {str(c.get('detail', ''))[:300]}")
    return 1 if v == "FAILED" else 0


if __name__ == "__main__":
    raise SystemExit(main())
