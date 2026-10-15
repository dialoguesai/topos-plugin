#!/bin/sh
# The stand-in MCP server: with NO topos-node anywhere (fake HOME, EMPTY PATH,
# TOPOS_NODE_BIN unset — the GUI-host condition from spike P0.5), bin/topos-mcp
# must start and answer initialize, tools/list (five tools) and tools/call (the
# "set up Topos" sentence). With a fake binary but no socket it must answer the
# "start Topos" sentence after its wait. Never touches the real ~/.topos.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$here/.." && pwd)
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT
PY=$(command -v python3 || echo /usr/bin/python3)

# run_exchange <label> <client> <expect_text> ; the launcher's env is built in python
run_exchange() {
    "$PY" - "$ROOT/bin/topos-mcp" "$1" "$2" "$3" "$FAKE_HOME" <<'PY'
import json, os, subprocess, sys, time
launcher, label, client, expect, home = sys.argv[1:6]
env = {"HOME": home, "PATH": "", "TOPOS_NODE_BIN": "", "TOPOS_UDS_PATH": os.path.join(home, ".topos", "engine.sock")}
msgs = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "0"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
    {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "mcp_session_context", "arguments": {}}},
    {"jsonrpc": "2.0", "id": 4, "method": "ping"},
]
t0 = time.time()
p = subprocess.Popen([launcher, "--client", client], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
out, err = p.communicate("".join(json.dumps(m) + "\n" for m in msgs).encode(), timeout=60)
dt = time.time() - t0
lines = [json.loads(l) for l in out.decode().splitlines() if l.strip()]
by_id = {m.get("id"): m for m in lines if "id" in m}
ok = True
def want(cond, msg):
    global ok
    print(("  ok   " if cond else "  FAIL ") + msg)
    ok = ok and cond
want(p.returncode == 0, f"{label}: launcher exited 0 (got {p.returncode}) in {dt:.1f}s")
want(1 in by_id and "result" in by_id[1] and by_id[1]["result"].get("serverInfo", {}).get("name") == "topos", f"{label}: initialize answered by server 'topos'")
tools = by_id.get(2, {}).get("result", {}).get("tools", [])
want([t["name"] for t in tools] == ["mcp_session_context", "list_scopes", "query_scope", "aggregate_scope", "sources_status"], f"{label}: tools/list names the five v1 tools ({[t['name'] for t in tools]})")
text = by_id.get(3, {}).get("result", {}).get("content", [{}])[0].get("text", "")
want(text == expect, f"{label}: tools/call answered {text!r}")
want(by_id.get(4, {}).get("result") == {}, f"{label}: ping answered")
want(b"tpn_" not in out and b"tpa_" not in out and b"TOPOS_KEY" not in out, f"{label}: no secret-shaped text in output")
if err:
    print(f"  stderr: {err.decode()[:200]!r}")
sys.exit(0 if ok else 1)
PY
}

echo "== stand-in MCP: no binary anywhere, empty PATH =="
run_exchange "no-binary" claude-code 'This agent isn'"'"'t connected to Topos yet — say "set up Topos".' || exit 1

echo "== stand-in MCP: fake binary, no socket (codex budget 8 s) =="
mkdir -p "$FAKE_HOME/.local/bin"
printf '#!/bin/sh\nexit 0\n' > "$FAKE_HOME/.local/bin/topos-node"
chmod +x "$FAKE_HOME/.local/bin/topos-node"
run_exchange "fake-binary-no-socket" codex 'Topos isn'"'"'t running — say "start Topos".' || exit 1

echo "== stand-in MCP: sh-only responder (no python3) =="
"$PY" - "$ROOT/lib/fallback_mcp.sh" <<'PY'
import json, subprocess, sys
p = subprocess.Popen(["/bin/sh", sys.argv[1], "This agent isn't connected to Topos yet — say \"set up Topos\"."], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env={"PATH": ""})
msgs = [{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}},{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","id":"abc","method":"tools/list"},{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"query_scope","arguments":{}}}]
out, _ = p.communicate("".join(json.dumps(m)+"\n" for m in msgs).encode(), timeout=30)
lines = [json.loads(l) for l in out.decode().splitlines() if l.strip()]
by_id = {m.get("id"): m for m in lines}
ok = by_id[1]["result"]["serverInfo"]["name"] == "topos" and len(by_id["abc"]["result"]["tools"]) == 5 and "set up Topos" in by_id[3]["result"]["content"][0]["text"]
print(("  ok   " if ok else "  FAIL ") + f"sh responder (empty PATH): {len(lines)} replies, exit {p.returncode}")
sys.exit(0 if ok else 1)
PY
