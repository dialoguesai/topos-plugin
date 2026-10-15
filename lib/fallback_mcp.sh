#!/bin/sh
# Last-resort stand-in MCP server, used only when no python3 can run
# (lib/fallback_mcp.py is the normal stand-in). POSIX sh + sed; no handover.
#
#   fallback_mcp.sh "<sentence to answer every tool call with>"
#
# Speaks newline-delimited JSON-RPC 2.0 over stdio: initialize, ping,
# tools/list (names only, permissive inputs), tools/call (the sentence),
# resources/prompts lists (empty). Notifications are ignored.
set -u
# PATH may be EMPTY (GUI-launched hosts): sed/head need one.
PATH="/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"; export PATH
MSG=${1:-'This agent isn'"'"'t connected to Topos yet — say "set up Topos".'}

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
MSG_JSON=$(json_escape "$MSG")

TOOLS='{"tools":[{"name":"mcp_session_context","description":"Who this Topos belongs to and what it holds. Call first.","inputSchema":{"type":"object","properties":{}}},{"name":"list_scopes","description":"The scopes this Topos can answer about.","inputSchema":{"type":"object","properties":{"scope_id":{"type":"string"}}}},{"name":"query_scope","description":"Ask one scope a question.","inputSchema":{"type":"object","properties":{"scope_id":{"type":"string"},"intent":{"type":"string"},"access_mode":{"type":"string","enum":["raw","summary","inference"]},"query":{"type":"string"},"now":{"type":"string"},"retrieval_text":{"type":"string"},"query_session_id":{"type":"string"}},"required":["scope_id","intent"]}},{"name":"aggregate_scope","description":"Counts and groupings over one scope.","inputSchema":{"type":"object","properties":{"scope_id":{"type":"string"},"intent":{"type":"string"}},"required":["scope_id"]}},{"name":"sources_status","description":"Every source on this Topos and its sync state.","inputSchema":{"type":"object","properties":{}}}]}'

while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    method=$(printf '%s' "$line" | sed -n 's/.*"method"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    # id: a number, or a string (kept with its quotes). Absent → notification.
    # Two sed calls because BSD sed (macOS) has no \| alternation in a BRE.
    id=$(printf '%s' "$line" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9][0-9]*\).*/\1/p' | head -n 1)
    [ -n "$id" ] || id=$(printf '%s' "$line" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\("[^"]*"\).*/\1/p' | head -n 1)
    [ -n "$id" ] || continue
    case "$method" in
        initialize)
            printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"topos","version":"0.1.0+standin-sh"},"instructions":"%s"}}\n' "$id" "$MSG_JSON" ;;
        ping)
            printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id" ;;
        tools/list)
            printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$id" "$TOOLS" ;;
        tools/call)
            printf '{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"%s"}],"isError":true}}\n' "$id" "$MSG_JSON" ;;
        resources/list)
            printf '{"jsonrpc":"2.0","id":%s,"result":{"resources":[]}}\n' "$id" ;;
        resources/templates/list)
            printf '{"jsonrpc":"2.0","id":%s,"result":{"resourceTemplates":[]}}\n' "$id" ;;
        prompts/list)
            printf '{"jsonrpc":"2.0","id":%s,"result":{"prompts":[]}}\n' "$id" ;;
        *)
            printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":"Method not found"}}\n' "$id" ;;
    esac
done
exit 0
