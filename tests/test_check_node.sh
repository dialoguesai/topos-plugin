#!/bin/sh
# check-node.sh + verdict.py against (a) no binary → FAILED with c2–c7 blocked, never
# GOOD TO GO; (b) a fake binary whose `status --json` is the CONTRACTS §4 schema with
# everything good → GOOD TO GO; (c) the same with the agent revoked → FAILED.
# Fake HOME; nothing real is touched.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$here/.." && pwd)
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT
PY=$(command -v python3 || echo /usr/bin/python3)
CHECK="$ROOT/skills/topos-setup/scripts/check-node.sh"
VERDICT="$ROOT/skills/topos-setup/scripts/verdict.py"
fail=0

run_case() {
    _label=$1
    HOME="$FAKE_HOME" PATH="" TOPOS_NODE_BIN="" /bin/sh "$CHECK" --client claude-code --plugin-root "$ROOT" --out "$FAKE_HOME/checks.jsonl" >/dev/null 2>&1
    HOME="$FAKE_HOME" "$PY" -I "$VERDICT" "$FAKE_HOME/checks.jsonl" > "$FAKE_HOME/verdict.txt"
    _rc=$?
    _line=$(head -n 1 "$FAKE_HOME/verdict.txt")
    printf '  %s → %s (exit %s)\n' "$_label" "$_line" "$_rc" >&2
    printf '%s' "$_line"
}

echo "== (a) no binary =="
v=$(run_case "no binary")
case "$v" in *"FAILED"*) ;; *) echo "  FAIL expected FAILED"; fail=1 ;; esac
grep -c '"status": "blocked"' "$FAKE_HOME/checks.jsonl" | grep -q '^6$' && echo "  ok   c2–c7 blocked (6)" || { echo "  FAIL expected 6 blocked"; fail=1; }
grep -q '"id": "c8", "status": "pass"' "$FAKE_HOME/checks.jsonl" && echo "  ok   c8 pass (hooks.json has Stop)" || { echo "  FAIL c8"; fail=1; }

echo "== (b) fake binary, everything good =="
mkdir -p "$FAKE_HOME/.local/bin"
cat > "$FAKE_HOME/.local/bin/topos-node" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo "topos-node 1.6.0" ;;
  status) cat <<'JSON'
{"node": {"running": true, "version": "1.6.0", "pid": 4242, "socket": true, "owner_key_persisted": true},
 "paired": true, "topos_id": "t_1", "user_id_present": true,
 "control_plane": "connected", "outdated": false, "latest_version": "1.6.0",
 "agents": [{"client": "claude-code", "enrolled_at": "2026-10-15T18:00:00Z", "revoked": false}],
 "sources": [{"source_id": "claude_code_sessions", "enabled": true, "paused": false, "last_sync_at": "2026-10-15T20:00:00Z", "last_error": null}],
 "pairing": null, "exit_code": 0}
JSON
  ;;
esac
EOF
chmod +x "$FAKE_HOME/.local/bin/topos-node"
v=$(run_case "all good")
case "$v" in *"GOOD TO GO"*) ;; *) echo "  FAIL expected GOOD TO GO"; fail=1 ;; esac

echo "== (c) agent revoked =="
sed -i.bak 's/"revoked": false/"revoked": true/' "$FAKE_HOME/.local/bin/topos-node"
v=$(run_case "agent revoked")
case "$v" in *"FAILED"*) ;; *) echo "  FAIL expected FAILED"; fail=1 ;; esac

echo "== (d) status hangs → blocked, INCOMPLETE at best =="
printf '#!/bin/sh\ncase "$1" in --version) echo x;; status) sleep 30;; esac\n' > "$FAKE_HOME/.local/bin/topos-node"
v=$(run_case "status hangs")
case "$v" in *"GOOD TO GO"*) echo "  FAIL rounded up"; fail=1 ;; *"INCOMPLETE"*|*"FAILED"*) ;; esac
grep -q 'did not answer' "$FAKE_HOME/checks.jsonl" && echo "  ok   timeout recorded as blocked" || { echo "  FAIL timeout not recorded"; fail=1; }

sed -n '1,12p' "$FAKE_HOME/verdict.txt" | sed 's/^/    /'
exit $fail
