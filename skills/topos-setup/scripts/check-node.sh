#!/bin/sh
# check-node.sh — the eight setup checks c1–c8, one JSON line each.
#
#   sh check-node.sh --client claude-code [--source claude_code_sessions] \
#                    [--plugin-root DIR] [--out checks.jsonl]
#
# The ids and pass rules mirror the house QA skill's Path C observer
# (topos-install-qa/scripts/qa-path-c.sh) exactly, so the agent and a person
# report the same eight things the same way. Read-only: it runs `topos-node
# --version`, `pair --help`, `service status`, `status --json`, `agents list
# --json`, stats (never reads) the agent label file, and speaks MCP to the
# plugin's own launcher. It never writes under ~/.topos, never reads
# ~/.topos/.env or ~/.topos/agents/*.token, and never records an answer's text.
#
# Statuses: pass | fail | blocked | skip. Unobserved is `blocked`, never `pass`.
# c8 (no secret in the transcripts, compared by hash) needs the node's secret
# values; this agent never reads them, so c8 is ALWAYS blocked here — a person
# runs qa-path-c.sh for it. The agent's best verdict is therefore INCOMPLETE
# with c8 as the only blocked check.
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
STATUS_TIMEOUT=20
PROBE_TIMEOUT=120
QUERY_TIMEOUT=${TOPOS_SETUP_QUERY_TIMEOUT:-180}
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
WORK=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/topos-setup.$$")
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

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
    "$@" </dev/null >"$_o" 2>&1 &
    _pid=$!
    _i=0
    while kill -0 "$_pid" 2>/dev/null && [ "$_i" -lt $((_t * 10)) ]; do
        sleep 0.1
        _i=$((_i + 1))
    done
    if kill -0 "$_pid" 2>/dev/null; then
        kill "$_pid" 2>/dev/null; sleep 0.2; kill -9 "$_pid" 2>/dev/null
        wait "$_pid" 2>/dev/null
        return 124
    fi
    wait "$_pid"
}

# first_line <file> — at most 200 bytes of the first line, no newlines
first_line() { head -c 200 "$1" 2>/dev/null | head -n 1 | tr -d '\r\n'; }

printf '== Topos setup checks (%s / %s) ==\n' "$CLIENT" "$SOURCE"

# ---- c1: binary by the candidate list, with the on-ramp commands ------------
NODE=$(topos_resolve_node "$PLUGIN_ROOT/bin/topos-node") || NODE=""
C1=fail
if [ -z "$NODE" ]; then
    record c1 fail "topos-node resolves by the candidate list" \
        "no executable at \$TOPOS_NODE_BIN, ~/.local/bin, ~/.topos/runtime/bin, /opt/homebrew/bin or /usr/local/bin"
else
    run_with_timeout 20 "$WORK/version" "$NODE" --version
    VER=$(first_line "$WORK/version")
    if run_with_timeout 20 "$WORK/pairhelp" "$NODE" pair --help; then
        record c1 pass "topos-node resolves and has the on-ramp commands" "$NODE ($VER)"
        C1=pass
    else
        record c1 blocked "topos-node resolves and has the on-ramp commands" \
            "$NODE ($VER) has no 'pair' subcommand: the on-ramp node release is not installed here (uv tool upgrade topos-node)"
        C1=blocked
    fi
fi

if [ "$C1" = pass ]; then
    # ---- c2: runs as a service (never started by this script) ----------------
    run_with_timeout 20 "$WORK/svc" "$NODE" service status
    SVC_RC=$?
    SVC_OUT=$(head -c 200 "$WORK/svc" 2>/dev/null | tr '\r\n' '  ')
    if [ "$SVC_RC" = 0 ]; then
        record c2 pass "Node runs as a background service" "$SVC_OUT"
    elif printf '%s' "$SVC_OUT" | grep -qi 'Topos.app\|managed'; then
        record c2 skip "Node runs as a background service" "managed by Topos.app: $SVC_OUT"
    elif [ "$SVC_RC" = 124 ]; then
        record c2 blocked "Node runs as a background service" "service status did not answer within 20 s"
    else
        record c2 fail "Node runs as a background service" "service status exit $SVC_RC: $SVC_OUT"
    fi

    # ---- c3: paired, connected, owner key persisted (status --json, exit 0) --
    run_with_timeout "$STATUS_TIMEOUT" "$WORK/status.json" "$NODE" status --json
    STATUS_RC=$?
    if [ "$STATUS_RC" = 124 ]; then
        record c3 blocked "Node is paired, control plane connected, owner key persisted" "status --json did not answer within ${STATUS_TIMEOUT} s"
        C3=blocked
    else
        C3=$("$PY" -I - "$WORK/status.json" "$STATUS_RC" <<'PY'
import json, sys
rc = sys.argv[2]
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    assert isinstance(d, dict)
except Exception:
    print("fail\tstatus --json is not JSON (exit %s)" % rc); raise SystemExit
paired = d.get("paired"); cp = d.get("control_plane"); okp = (d.get("node") or {}).get("owner_key_persisted")
ok = paired is True and cp == "connected" and okp is True and rc == "0"
print(("pass" if ok else "fail") + "\tpaired=%s control_plane=%s owner_key_persisted=%s exit=%s" % (paired, cp, okp, rc))
PY
)
        record c3 "${C3%%	*}" "Node is paired, control plane connected, owner key persisted" "${C3#*	}"
        C3=${C3%%	*}
    fi

    # ---- c4: agent approved; label file 0600 in a 0700 folder (never read) ---
    run_with_timeout 20 "$WORK/agents.json" "$NODE" agents list --json
    LABEL="${HOME:-/}/.topos/agents/$CLIENT.token"
    if [ "$(uname -s 2>/dev/null)" = Darwin ]; then
        FMODE=$(stat -f '%Lp' "$LABEL" 2>/dev/null || echo missing); DMODE=$(stat -f '%Lp' "${HOME:-/}/.topos/agents" 2>/dev/null || echo missing)
    else
        FMODE=$(stat -c '%a' "$LABEL" 2>/dev/null || echo missing); DMODE=$(stat -c '%a' "${HOME:-/}/.topos/agents" 2>/dev/null || echo missing)
    fi
    C4=$("$PY" -I - "$WORK/agents.json" "$CLIENT" "$FMODE" "$DMODE" <<'PY'
import json, sys
c, fm, dm = sys.argv[2], sys.argv[3], sys.argv[4]
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    d = None
rows = d if isinstance(d, list) else (d or {}).get("agents") or []
row = next((r for r in rows if isinstance(r, dict) and r.get("client") == c), None)
enrolled = row is not None and not row.get("revoked")
modes_ok = fm == "600" and dm == "700"
print(("pass" if enrolled and modes_ok else "fail") + "\tenrolled=%s revoked=%s label_mode=%s dir_mode=%s" % (row is not None, (row or {}).get("revoked"), fm, dm))
PY
)
    record c4 "${C4%%	*}" "Agent $CLIENT is approved and its label file is 0600 in a 0700 folder" "${C4#*	}"

    # ---- c5 / c7: through the plugin's own launcher -------------------------
    PROBE="$here/mcp_probe.py"
    if [ -x "$PLUGIN_ROOT/bin/topos-mcp" ]; then
        set -- --launcher "$PLUGIN_ROOT/bin/topos-mcp"
    else
        set -- --node "$NODE"
    fi
    "$PY" -I "$PROBE" "$@" --client "$CLIENT" --timeout "$PROBE_TIMEOUT" context > "$WORK/ctx.json" 2>/dev/null
    C5=$("$PY" -I - "$WORK/ctx.json" "$CLIENT" <<'PY'
import json, sys
c = sys.argv[2]
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("fail\tprobe printed no JSON"); raise SystemExit
if d.get("error"):
    print("fail\t" + d["error"]); raise SystemExit
ctx = d.get("context") or {}
ok = d.get("tools_match_contract") is True and ctx.get("contract_version") == 1 and ctx.get("paired") is True and ctx.get("agent_client") == c
print(("pass" if ok else "fail") + "\ttools=%s contract_version=%s paired=%s agent=%s control_plane=%s" % (",".join(d.get("tools") or []), ctx.get("contract_version"), ctx.get("paired"), ctx.get("agent_client"), ctx.get("control_plane")))
PY
)
    record c5 "${C5%%	*}" "Topos tools answer through the agent's own server (mcp_session_context, v1 tool set)" "${C5#*	}"

    # ---- c6: source enabled, not paused, has synced -------------------------
    if [ "$C3" = blocked ]; then
        record c6 blocked "Source $SOURCE is enabled and has synced" "status --json did not answer"
    else
        C6=$("$PY" -I - "$WORK/status.json" "$SOURCE" <<'PY'
import json, sys
s = sys.argv[2]
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    assert isinstance(d, dict)
except Exception:
    print("fail\tstatus --json is not JSON"); raise SystemExit
row = next((r for r in d.get("sources") or [] if isinstance(r, dict) and r.get("source_id") == s), None)
if row is None:
    print("fail\tsource %s absent from status" % s); raise SystemExit
ok = row.get("enabled") is True and not row.get("paused") and bool(row.get("last_sync_at"))
print(("pass" if ok else "fail") + "\tenabled=%s paused=%s last_sync_at=%s last_error=%s" % (row.get("enabled"), row.get("paused"), row.get("last_sync_at"), row.get("last_error")))
PY
)
        record c6 "${C6%%	*}" "Source $SOURCE is enabled and has synced" "${C6#*	}"
    fi

    # ---- c7: the first answer, shape only -----------------------------------
    if [ "${C5%%	*}" = pass ]; then
        "$PY" -I "$PROBE" "$@" --client "$CLIENT" --timeout "$PROBE_TIMEOUT" --query-timeout "$QUERY_TIMEOUT" query > "$WORK/q.json" 2>/dev/null
        C7=$("$PY" -I - "$WORK/q.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("fail\tprobe printed no JSON"); raise SystemExit
if d.get("error"):
    print("fail\t" + d["error"]); raise SystemExit
q = d.get("query") or {}
ok = q.get("public_result_present") is True and not q.get("refused")
print(("pass" if ok else "fail") + "\tturn_outcome=%s public_result=%s (%s) — answer text deliberately not recorded" % (q.get("turn_outcome"), q.get("public_result_present"), q.get("public_result_kind")))
PY
)
        record c7 "${C7%%	*}" "First answer comes from the person's own coding history (ai_coding_sessions:read)" "${C7#*	}"
    else
        record c7 blocked "First answer comes from the person's own coding history (ai_coding_sessions:read)" "c5 did not pass"
    fi
else
    for id in c2 c3 c4 c5 c6 c7; do
        record "$id" blocked "(not observed)" "c1 did not pass: $C1"
    done
fi

# ---- c8: no secret in the transcripts, by hash — needs the secrets; never here
record c8 blocked "No node secret appears in the session transcripts or shell history (compared by hash)" \
    "needs the node's secret values to compare; this agent never reads ~/.topos/.env or ~/.topos/agents/*.token — a person runs topos-install-qa scripts/qa-path-c.sh"

printf 'checks written to %s\n' "$OUT"
exit 0
