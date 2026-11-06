#!/bin/sh
# bin/topos-health against a fake node (fake HOME, empty PATH; nothing real is touched):
#  (a) account node, agent enrolled, current     → silent
#  (b) LOCAL node (mode local, paired false)      → the soft "runs without an account" line ONCE,
#                                                   then silent on the next session (marker in the data dir)
#  (c) local node, agent NOT enrolled             → the agent line, never the account line
#  (d) paired false with NO mode (older node)     → the "isn't connected to your account" line, every session
#  (e) node not running                           → the "isn't running" line
# Every line is read from `status --json` only; no secret-shaped text may appear.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$here/.." && pwd)
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT
fail=0

mkdir -p "$FAKE_HOME/.local/bin" "$FAKE_HOME/data"
cat > "$FAKE_HOME/.local/bin/topos-node" <<EOF2
#!/bin/sh
case "\$1" in
  status) cat "$FAKE_HOME/status.json" ;;
esac
EOF2
chmod +x "$FAKE_HOME/.local/bin/topos-node"

write_status() {  # write_status <paired> <mode-json> <control_plane> <agents-json> <running>
    cat > "$FAKE_HOME/status.json" <<JSON
{"node": {"running": $5, "version": "1.6.0", "pid": 4242, "socket": true, "owner_key_persisted": true},
 "paired": $1, "mode": $2, "topos_id": "t_1", "user_id_present": true,
 "control_plane": "$3", "outdated": false, "latest_version": "1.6.0",
 "agents": $4, "sources": [], "pairing": null, "exit_code": 0}
JSON
}
ENROLLED='[{"client": "claude-code", "enrolled_at": "2026-11-05T18:00:00Z", "revoked": false}]'

run_hook() {
    HOME="$FAKE_HOME" PATH="" TOPOS_NODE_BIN="" CLAUDE_PLUGIN_DATA="$FAKE_HOME/data" \
        /bin/sh "$ROOT/bin/topos-health" --client claude-code 2>/dev/null
}
expect() {  # expect <label> <want> <got>
    if [ "$2" = "$3" ]; then printf '  ok   %s → %s\n' "$1" "${3:-(silent)}"
    else printf '  FAIL %s: wanted %s, got %s\n' "$1" "${2:-(silent)}" "${3:-(silent)}"; fail=1; fi
}

echo "== (a) account node, all good → silent =="
write_status true '"account"' connected "$ENROLLED" true
expect "account node" "" "$(run_hook)"

echo "== (b) local node → the soft line once, then silent =="
write_status false '"local"' local_only "$ENROLLED" true
expect "local node, first session" 'Topos runs without an account; say "connect my Topos account" to add one.' "$(run_hook)"
[ -f "$FAKE_HOME/data/connect-later.said" ] && echo "  ok   marker written" || { echo "  FAIL no marker"; fail=1; }
expect "local node, second session" "" "$(run_hook)"
case "$(run_hook)" in *"account yet"*) echo "  FAIL the account nag was said about a local node"; fail=1 ;; esac

echo "== (c) local node, agent not enrolled → the agent line =="
write_status false '"local"' local_only '[]' true
expect "local node, no agent" 'This agent isn'"'"'t connected to Topos yet — say "set up Topos".' "$(run_hook)"

echo "== (d) paired false, no mode → the account line =="
write_status false null offline "$ENROLLED" true
expect "unpaired, no mode" 'Topos isn'"'"'t connected to your account yet — say "set up Topos".' "$(run_hook)"

echo "== (e) node down =="
write_status false '"local"' local_only "$ENROLLED" false
expect "node down" 'Topos isn'"'"'t running — say "start Topos".' "$(run_hook)"

exit $fail
