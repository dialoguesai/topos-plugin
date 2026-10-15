#!/bin/sh
# Handover: the stand-in answers "start Topos" while the socket is absent, then —
# once a (fake) node binary and its socket exist — spawns `topos-node mcp --client X`,
# replays initialize, and forwards the next tools/call to it. Fake HOME; the "node"
# is a tiny python echo MCP server; the socket is a real unix socket in the fake HOME.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$here/.." && pwd)
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT
PY=$(command -v python3 || echo /usr/bin/python3)
mkdir -p "$FAKE_HOME/.local/bin" "$FAKE_HOME/.topos"

# The fake node: `topos-node mcp --client NAME` answers initialize and echoes tool calls.
cat > "$FAKE_HOME/.local/bin/topos-node" <<EOF
#!/bin/sh
exec "$PY" -I "$FAKE_HOME/fake_mcp.py" "\$@"
EOF
chmod +x "$FAKE_HOME/.local/bin/topos-node"
cat > "$FAKE_HOME/fake_mcp.py" <<'PY'
import json, sys
client = sys.argv[sys.argv.index("--client") + 1] if "--client" in sys.argv else "?"
for line in sys.stdin:
    if not line.strip():
        continue
    m = json.loads(line)
    if "id" not in m:
        continue
    if m["method"] == "initialize":
        r = {"protocolVersion": m["params"].get("protocolVersion", "2025-06-18"), "capabilities": {"tools": {}}, "serverInfo": {"name": "topos-real", "version": "9.9.9"}}
    elif m["method"] == "tools/call":
        r = {"content": [{"type": "text", "text": f"REAL SERVER ({client}) answered {m['params']['name']}"}]}
    elif m["method"] == "tools/list":
        r = {"tools": []}
    else:
        r = {}
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": r}) + "\n"); sys.stdout.flush()
PY

HOME="$FAKE_HOME" PATH="" TOPOS_NODE_BIN="" TOPOS_UDS_PATH="$FAKE_HOME/.topos/engine.sock" "$PY" - "$ROOT/bin/topos-mcp" "$FAKE_HOME" <<'PY'
import json, os, socket, subprocess, sys, time
launcher, home = sys.argv[1], sys.argv[2]
sock_path = os.path.join(home, ".topos", "engine.sock")

def send(p, m):
    p.stdin.write((json.dumps(m) + "\n").encode()); p.stdin.flush()

def recv(p, want_id, limit=30):
    t0 = time.time()
    while time.time() - t0 < limit:
        line = p.stdout.readline()
        if not line:
            raise SystemExit("server closed")
        m = json.loads(line)
        if m.get("id") == want_id:
            return m
        print("  (note)", json.dumps(m)[:120])
    raise SystemExit("timeout waiting for id %r" % want_id)

t0 = time.time()
p = subprocess.Popen([launcher, "--client", "cursor"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
send(p, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t", "version": "0"}}})
r1 = recv(p, 1, limit=60)
print(f"  ok   initialize answered by {r1['result']['serverInfo']} after {time.time()-t0:.1f}s (launcher waited for the socket first)")
send(p, {"jsonrpc": "2.0", "method": "notifications/initialized"})
send(p, {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "list_scopes", "arguments": {}}})
r2 = recv(p, 2)
text = r2["result"]["content"][0]["text"]
ok = text == "Topos isn't running — say \"start Topos\"."
print(("  ok   " if ok else "  FAIL ") + f"before the socket exists: {text!r}")
# Now "start the node": create the unix socket.
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(sock_path); s.listen(1)
send(p, {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "query_scope", "arguments": {"scope_id": "x", "intent": "y"}}})
r3 = recv(p, 3)
text3 = r3["result"]["content"][0]["text"]
ok3 = text3 == "REAL SERVER (cursor) answered query_scope"
print(("  ok   " if ok3 else "  FAIL ") + f"after the socket exists: {text3!r}")
send(p, {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "sources_status", "arguments": {}}})
r4 = recv(p, 4)
ok4 = r4["result"]["content"][0]["text"].startswith("REAL SERVER")
print(("  ok   " if ok4 else "  FAIL ") + f"later calls stay with the real server: {r4['result']['content'][0]['text']!r}")
p.stdin.close(); p.wait(timeout=10)
print(f"  ok   launcher exit {p.returncode}")
sys.exit(0 if ok and ok3 and ok4 and p.returncode == 0 else 1)
PY
