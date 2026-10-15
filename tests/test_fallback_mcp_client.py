#!/usr/bin/env python3
"""Drive bin/topos-mcp with the official `mcp` Python stdio client (skipped when the
package is missing). Fake HOME, empty PATH, no topos-node anywhere: the stand-in must
initialize, list the five tools, and answer a call with the "set up Topos" sentence.

    <python-with-mcp> tests/test_fallback_mcp_client.py
"""
from __future__ import annotations

import asyncio
import os
import sys
import tempfile
from pathlib import Path

try:
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client
except ImportError:  # pragma: no cover
    print("SKIP: the mcp package is not installed in this interpreter")
    sys.exit(0)

ROOT = Path(__file__).resolve().parent.parent
EXPECT = "This agent isn't connected to Topos yet — say \"set up Topos\"."


async def main() -> int:
    fake_home = tempfile.mkdtemp()
    env = {"HOME": fake_home, "PATH": "", "TOPOS_NODE_BIN": ""}
    params = StdioServerParameters(command=str(ROOT / "bin" / "topos-mcp"), args=["--client", "claude-code"], env=env)
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            init = await session.initialize()
            tools = await session.list_tools()
            names = [t.name for t in tools.tools]
            result = await session.call_tool("query_scope", {"scope_id": "ai_coding_sessions:read", "intent": "x"})
            text = result.content[0].text if result.content else ""
    ok = True
    for cond, msg in [
        (init.serverInfo.name == "topos", f"serverInfo.name == topos ({init.serverInfo.name}, protocol {init.protocolVersion})"),
        (names == ["mcp_session_context", "list_scopes", "query_scope", "aggregate_scope", "sources_status"], f"five tools listed: {names}"),
        (text == EXPECT, f"tools/call answered: {text!r}"),
        (bool(result.isError), "the stand-in marks the answer isError=true"),
    ]:
        print(("  ok   " if cond else "  FAIL ") + msg)
        ok = ok and cond
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
