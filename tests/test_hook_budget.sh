#!/bin/sh
# Hook budget tests. Never touches the real ~/.topos or any real topos-node:
# HOME is a temp dir, PATH is empty, and the "node" is a fake script.
#
#  1. Stop hook with NO binary: topos-sync exits 0 within 1.5 s.
#  2. Stop hook with a fake slow binary: topos-sync still exits within 1.5 s,
#     and the detached sync runs to completion afterwards with the transcript
#     path and --quiet, output discarded.
#  3. Cursor payload: user_email is never written anywhere; a null transcript
#     path means no sync.
#  4. SessionStart (topos-health) with no binary prints one line and exits 0
#     within 1.5 s; with a fake slow `status --json` it says nothing and exits.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$here/.." && pwd)
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT
PY=$(command -v python3 || echo /usr/bin/python3)
fail=0

timed() {
    # timed <label> <max_seconds> <stdin-file> <cmd...> ; prints elapsed, sets $rc
    _label=$1; _max=$2; _in=$3; shift 3
    _t0=$("$PY" -c 'import time; print(time.time())')
    HOME="$FAKE_HOME" PATH="" "$@" < "$_in" > "$FAKE_HOME/out" 2> "$FAKE_HOME/err"
    rc=$?
    _dt=$("$PY" -c "import time; print(round(time.time() - $_t0, 3))")
    if "$PY" -c "import sys; sys.exit(0 if $_dt <= $_max else 1)"; then
        printf '  ok   %s: exit %s in %ss (budget %ss)\n' "$_label" "$rc" "$_dt" "$_max"
    else
        printf '  FAIL %s: exit %s in %ss (budget %ss)\n' "$_label" "$rc" "$_dt" "$_max"; fail=1
    fi
}

TRANSCRIPT="$FAKE_HOME/session.jsonl"
printf '{"type":"user"}\n' > "$TRANSCRIPT"
printf '{"session_id":"s1","transcript_path":"%s","cwd":"/tmp","hook_event_name":"Stop","stop_hook_active":false}\n' "$TRANSCRIPT" > "$FAKE_HOME/stop.json"

echo "== 1. Stop hook, no binary =="
timed "topos-sync (no binary)" 1.5 "$FAKE_HOME/stop.json" "$ROOT/bin/topos-sync" --source claude_code_sessions --client claude-code
[ "$rc" = 0 ] || { echo "  FAIL exit code $rc"; fail=1; }

echo "== 2. Stop hook, fake slow binary: hook returns at once, sync completes detached =="
mkdir -p "$FAKE_HOME/.local/bin"
cat > "$FAKE_HOME/.local/bin/topos-node" <<EOF
#!/bin/sh
sleep 2
printf '%s\n' "\$*" > "$FAKE_HOME/sync-args"
echo "this output must be discarded"
EOF
chmod +x "$FAKE_HOME/.local/bin/topos-node"
timed "topos-sync (slow fake binary)" 1.5 "$FAKE_HOME/stop.json" "$ROOT/bin/topos-sync" --source claude_code_sessions --client claude-code
[ -s "$FAKE_HOME/out" ] && { echo "  FAIL hook printed to stdout: $(head -c 100 "$FAKE_HOME/out")"; fail=1; }
i=0; while [ ! -f "$FAKE_HOME/sync-args" ] && [ $i -lt 60 ]; do sleep 0.1; i=$((i+1)); done
if [ -f "$FAKE_HOME/sync-args" ] && grep -q "sources sync claude_code_sessions --session $TRANSCRIPT --quiet" "$FAKE_HOME/sync-args"; then
    printf '  ok   detached sync ran: %s\n' "$(cat "$FAKE_HOME/sync-args")"
else
    printf '  FAIL detached sync did not run with the expected arguments: %s\n' "$(cat "$FAKE_HOME/sync-args" 2>/dev/null)"; fail=1
fi

echo "== 3. Cursor payload: user_email dropped, null transcript → no sync =="
rm -f "$FAKE_HOME/sync-args"
printf '{"conversation_id":"c1","generation_id":"g1","hook_event_name":"stop","status":"completed","user_email":"someone@example.com","transcript_path":null,"workspace_roots":["/tmp"],"cursor_version":"2.0"}\n' > "$FAKE_HOME/cursor-stop.json"
timed "topos-sync (cursor, null transcript)" 1.5 "$FAKE_HOME/cursor-stop.json" "$ROOT/bin/topos-sync" --source cursor_sessions --client cursor
sleep 2.5
[ -f "$FAKE_HOME/sync-args" ] && { echo "  FAIL a sync ran without a transcript path"; fail=1; } || echo "  ok   no sync without a transcript path"
if grep -rq "someone@example.com" "$FAKE_HOME" 2>/dev/null; then
    hits=$(grep -rl "someone@example.com" "$FAKE_HOME" | grep -v cursor-stop.json || true)
    [ -n "$hits" ] && { echo "  FAIL user_email reached disk: $hits"; fail=1; } || echo "  ok   user_email written nowhere (only the test's own input file holds it)"
fi

echo "== 4. SessionStart (topos-health) =="
rm -rf "$FAKE_HOME/.local"
: > "$FAKE_HOME/empty.json"
timed "topos-health (no binary)" 1.5 "$FAKE_HOME/empty.json" "$ROOT/bin/topos-health" --client claude-code
grep -q 'set up Topos' "$FAKE_HOME/out" && echo "  ok   said: $(cat "$FAKE_HOME/out")" || { echo "  FAIL expected the 'set up Topos' line, got: $(cat "$FAKE_HOME/out")"; fail=1; }
mkdir -p "$FAKE_HOME/.local/bin"
printf '#!/bin/sh\nsleep 3\necho "{}"\n' > "$FAKE_HOME/.local/bin/topos-node"
chmod +x "$FAKE_HOME/.local/bin/topos-node"
timed "topos-health (slow status --json)" 1.5 "$FAKE_HOME/empty.json" "$ROOT/bin/topos-health" --client claude-code
[ -s "$FAKE_HOME/out" ] && { echo "  FAIL printed while status was still running: $(cat "$FAKE_HOME/out")"; fail=1; } || echo "  ok   said nothing while status was still running"
printf '#!/bin/sh\necho "{\\"node\\":{\\"running\\":true},\\"paired\\":true,\\"agents\\":[],\\"outdated\\":true}"\n' > "$FAKE_HOME/.local/bin/topos-node"
timed "topos-health (fast status, agent missing)" 1.5 "$FAKE_HOME/empty.json" "$ROOT/bin/topos-health" --client claude-code
grep -q "isn.t connected to Topos yet" "$FAKE_HOME/out" && echo "  ok   said: $(cat "$FAKE_HOME/out")" || { echo "  FAIL expected the not-enrolled line, got: $(cat "$FAKE_HOME/out")"; fail=1; }

exit $fail
