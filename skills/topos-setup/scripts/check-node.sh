#!/bin/sh
# check-node.sh — the eight setup checks (c1–c8), one JSON line each.
#
#   sh check-node.sh --client claude-code --source claude_code_sessions \
#                    [--plugin-root DIR] [--out checks.jsonl]
#
# Read-only: it runs `topos-node --version` and `topos-node status --json` and
# reads files. It never writes to ~/.topos, never reads ~/.topos/.env, and the
# lines it records never carry a secret (`status --json` has none by contract).
#
# Statuses: pass | fail | blocked | skip. A check that could not be observed is
# `blocked`, never `pass` (house rule, topos-install-qa).
set -u

# PATH may be EMPTY here (GUI-launched hosts, spike P0.5): no external command
# before this line; the directory comes from parameter expansion + cd/pwd builtins.
PATH="/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"; export PATH
case "$0" in */*) here=$(CDPATH= cd -- "${0%/*}" && pwd) ;; *) here=$(pwd) ;; esac
. "$here/../../../lib/resolve.sh"
topos_sane_path

CLIENT=claude-code
SOURCE=""
PLUGIN_ROOT=$(CDPATH= cd -- "$here/../../.." && pwd)
OUT="${TOPOS_SETUP_OUT:-${TMPDIR:-/tmp}/topos-setup-checks.jsonl}"
while [ $# -gt 0 ]; do
    case "$1" in
        --client) CLIENT=${2:-}; shift 2 ;;
        --source) SOURCE=${2:-}; shift 2 ;;
        --plugin-root) PLUGIN_ROOT=${2:-}; shift 2 ;;
        --out) OUT=${2:-}; shift 2 ;;
        *) shift ;;
    esac
done
if [ -z "$SOURCE" ]; then
    case "$CLIENT" in
        claude-code) SOURCE=claude_code_sessions ;;
        codex) SOURCE=codex_sessions ;;
        cursor) SOURCE=cursor_sessions ;;
        *) SOURCE="${CLIENT}_sessions" ;;
    esac
fi

PY=$(topos_python) || { printf 'check-node.sh: no python3 found; cannot evaluate checks\n' >&2; exit 2; }
: > "$OUT" || { printf 'check-node.sh: cannot write %s\n' "$OUT" >&2; exit 2; }

# record <id> <status> <name> <detail>
record() {
    case "$2" in pass|fail|blocked|skip) ;; *) printf 'record(): bad status %s\n' "$2" >&2; exit 2 ;; esac
    "$PY" -I -c 'import json,sys; print(json.dumps({"id":sys.argv[1],"status":sys.argv[2],"name":sys.argv[3],"detail":sys.argv[4][:400]}))' \
        "$1" "$2" "$3" "$4" >> "$OUT"
    case "$2" in
        pass)    printf '  PASS   %s — %s\n' "$3" "$4" ;;
        fail)    printf '  FAIL   %s — %s\n' "$3" "$4" ;;
        blocked) printf '  BLOCK  %s — %s\n' "$3" "$4" ;;
        skip)    printf '  SKIP   %s — %s\n' "$3" "$4" ;;
    esac
}

# run_with_timeout <seconds> <outfile> <cmd...>  → exit status (124 on timeout)
run_with_timeout() {
    _t=$1; _o=$2; shift 2
    "$@" </dev/null >"$_o" 2>/dev/null &
    _pid=$!
    _i=0
    while kill -0 "$_pid" 2>/dev/null && [ "$_i" -lt $((_t * 10)) ]; do
        sleep 0.1
        _i=$((_i + 1))
    done
    if kill -0 "$_pid" 2>/dev/null; then
        kill "$_pid" 2>/dev/null
        sleep 0.2
        kill -9 "$_pid" 2>/dev/null
        wait "$_pid" 2>/dev/null
        return 124
    fi
    wait "$_pid"
}

printf '== Topos setup checks (%s, source %s) ==\n' "$CLIENT" "$SOURCE"

# --- c1: the binary, by the fixed candidate list -------------------------
WORK=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/topos-setup.$$")
mkdir -p "$WORK"
NODE=$(topos_resolve_node "$PLUGIN_ROOT/bin/topos-node") || NODE=""
if [ -n "$NODE" ]; then
    run_with_timeout 20 "$WORK/version" "$NODE" --version
    VER=$(head -c 200 "$WORK/version" | tr -d '\r' | head -n 1)
    record c1 pass "topos-node binary found" "$NODE${VER:+ ($VER)}"
else
    record c1 fail "topos-node binary found" "none of: \$TOPOS_NODE_BIN, ~/.local/bin, ~/.topos/runtime/bin, /opt/homebrew/bin, /usr/local/bin"
fi

# --- status --json (one call feeds c2–c7) --------------------------------
STATUS_OK=0
if [ -n "$NODE" ]; then
    run_with_timeout 20 "$WORK/status.json" "$NODE" status --json
    rc=$?
    if "$PY" -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d,dict) else 1)' "$WORK/status.json" 2>/dev/null; then
        STATUS_OK=1
    else
        [ "$rc" = 124 ] && STATUS_WHY="status --json did not answer within 20 s" || STATUS_WHY="status --json exited $rc without JSON"
    fi
fi

if [ "$STATUS_OK" = 1 ]; then
    "$PY" -I - "$WORK/status.json" "$CLIENT" "$SOURCE" "$OUT" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
client, source, out = sys.argv[2], sys.argv[3], sys.argv[4]

def rec(cid, status, name, detail):
    with open(out, "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"id": cid, "status": status, "name": name, "detail": detail[:400]}) + "\n")
    tag = {"pass": "PASS ", "fail": "FAIL ", "blocked": "BLOCK", "skip": "SKIP "}[status]
    print(f"  {tag}  {name} — {detail}")

node = s.get("node") if isinstance(s.get("node"), dict) else {}
running = node.get("running")
if running is True:
    rec("c2", "pass", "node running", f"pid {node.get('pid')} version {node.get('version')} socket={node.get('socket')}")
elif running is False:
    rec("c2", "fail", "node running", "status says the node is not running (exit 4) — service install or Topos.app")
else:
    rec("c2", "blocked", "node running", "status --json has no node.running field")

paired = s.get("paired")
if paired is True:
    rec("c3", "pass", "paired with a Topos", f"topos_id present={bool(s.get('topos_id'))} user_id_present={s.get('user_id_present')}")
elif paired is False:
    rec("c3", "fail", "paired with a Topos", "not paired — run the pairing step (journey A6–A9)")
else:
    rec("c3", "blocked", "paired with a Topos", "status --json has no paired field")

cp = s.get("control_plane")
if cp == "connected":
    rec("c4", "pass", "control plane connected", "connected")
elif cp in ("rejected", "degraded", "offline"):
    rec("c4", "fail", "control plane connected", f"control_plane={cp} — doctor names the fix; 'rejected' means the key was refused (exit 5)")
elif running is False:
    rec("c4", "blocked", "control plane connected", "node not running, so not observed")
else:
    rec("c4", "blocked", "control plane connected", f"control_plane={cp!r} (unknown)")

okp = node.get("owner_key_persisted")
if okp is True:
    rec("c5", "pass", "owner key persisted by the node", "node.owner_key_persisted=true")
elif okp is False:
    rec("c5", "fail", "owner key persisted by the node", "the node has no persisted owner key — pairing did not finish")
else:
    rec("c5", "blocked", "owner key persisted by the node", "status --json has no node.owner_key_persisted field")

sources = s.get("sources") if isinstance(s.get("sources"), list) else []
mine = [x for x in sources if isinstance(x, dict) and x.get("source_id") == source]
if mine and mine[0].get("enabled") is True and not mine[0].get("paused"):
    m = mine[0]
    rec("c6", "pass", f"source {source} enabled", f"last_sync_at={m.get('last_sync_at')} last_error={m.get('last_error')}")
elif mine and mine[0].get("paused"):
    rec("c6", "fail", f"source {source} enabled", "enabled but paused — resume it or leave it paused on purpose")
elif mine:
    rec("c6", "fail", f"source {source} enabled", "present but not enabled — journey A10")
elif not sources:
    rec("c6", "blocked", f"source {source} enabled", "status --json lists no sources (node may not know this source id yet)")
else:
    rec("c6", "fail", f"source {source} enabled", f"not listed; known: {', '.join(str(x.get('source_id')) for x in sources)[:200]}")

agents = s.get("agents") if isinstance(s.get("agents"), list) else []
me = [a for a in agents if isinstance(a, dict) and a.get("client") == client]
if me and not me[0].get("revoked"):
    rec("c7", "pass", f"agent {client} enrolled", f"enrolled_at={me[0].get('enrolled_at')}")
elif me:
    rec("c7", "fail", f"agent {client} enrolled", "enrolled but revoked (disconnected) — reconnect through the approve page")
else:
    rec("c7", "fail", f"agent {client} enrolled", "not enrolled — `topos-node agents add <client>` (journey B2) or pair --add-agent")

if s.get("outdated") is True:
    print(f"  note   node is outdated (latest {s.get('latest_version')}) — say 'update Topos'")
PY
else
    why="${STATUS_WHY:-binary missing, so not observed}"
    record c2 blocked "node running" "$why"
    record c3 blocked "paired with a Topos" "$why"
    record c4 blocked "control plane connected" "$why"
    record c5 blocked "owner key persisted by the node" "$why"
    record c6 blocked "source $SOURCE enabled" "$why"
    record c7 blocked "agent $CLIENT enrolled" "$why"
fi

# --- c8: the turn-end hook ---------------------------------------------------
case "$CLIENT" in
    claude-code)
        f="$PLUGIN_ROOT/hooks/hooks.json"
        if [ -f "$f" ] && "$PY" -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if "Stop" in d.get("hooks",{}) else 1)' "$f" 2>/dev/null; then
            record c8 pass "turn-end hook registered" "hooks/hooks.json declares Stop (Claude Code registers plugin hooks on load)"
        else
            record c8 fail "turn-end hook registered" "hooks/hooks.json missing or without a Stop hook at $PLUGIN_ROOT"
        fi ;;
    cursor)
        f="$PLUGIN_ROOT/hooks/cursor.hooks.json"
        if [ -f "$f" ] && "$PY" -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if "stop" in d.get("hooks",{}) else 1)' "$f" 2>/dev/null; then
            record c8 pass "turn-end hook registered" "hooks/cursor.hooks.json declares stop (needs transcripts enabled in Cursor to carry a file)"
        else
            record c8 fail "turn-end hook registered" "hooks/cursor.hooks.json missing or without a stop hook at $PLUGIN_ROOT"
        fi ;;
    codex)
        f="$PLUGIN_ROOT/hooks/codex.hooks.json"
        if [ -f "$f" ] && "$PY" -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("hooks")=={} else 1)' "$f" 2>/dev/null; then
            record c8 pass "no hook by design (Codex v1)" "hooks/codex.hooks.json is empty; the node's hourly sync is the guarantee"
        else
            record c8 fail "no hook by design (Codex v1)" "hooks/codex.hooks.json missing or not empty at $PLUGIN_ROOT"
        fi ;;
    *)
        record c8 skip "turn-end hook registered" "no hook contract for client $CLIENT" ;;
esac

rm -rf "$WORK" 2>/dev/null
printf 'checks written to %s\n' "$OUT"
exit 0
