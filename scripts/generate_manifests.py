#!/usr/bin/env python3
"""Generate the per-client manifests from the Claude Code sources of truth.

Sources (hand-edited):
  .claude-plugin/plugin.json   name, version, description, author, …
  plugin.json                  the Agent Plugins 1.0.0 root (extensions.com.openai)
  .mcp.json                    the Claude Code MCP entry (launcher + "--client claude-code")
  hooks/hooks.json             Claude Code hooks (reference only; Cursor's file is hand-kept)

Generated (never edit by hand; `scripts/publish.sh --check` fails when stale):
  .cursor-plugin/plugin.json   Cursor manifest → skills, mcp.cursor.json, hooks/cursor.hooks.json
  .codex-plugin/plugin.json    Codex compatibility overlay (NO hooks; interface copied)
  mcp.json                     Agent Plugins / Codex spelling: "./bin/topos-mcp", client codex
  mcp.cursor.json              Cursor spelling: "${CURSOR_PLUGIN_ROOT}/bin/topos-mcp", client cursor
  gemini-extension.json        Gemini CLI manifest (generated, untested)

Why three MCP files: the launcher takes `--client NAME` and the node keys the agent
label by that name, so each client needs its own args; Agent Plugins forbids placeholder
expansion in `command` and wants "./"-relative paths (spec §7.2.1), Cursor expands only
${CURSOR_PLUGIN_ROOT}/${CLAUDE_PLUGIN_ROOT}, and Codex reads only the root mcp.json
(its overlay has no mcpServers field), so Cursor is the one redirected via its manifest.

Run with `python3 -I scripts/generate_manifests.py [--check]`. Stdlib only.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLAUDE_MANIFEST = ROOT / ".claude-plugin" / "plugin.json"
ROOT_MANIFEST = ROOT / "plugin.json"
CLAUDE_MCP = ROOT / ".mcp.json"

CURSOR_MANIFEST = ROOT / ".cursor-plugin" / "plugin.json"
CODEX_MANIFEST = ROOT / ".codex-plugin" / "plugin.json"
PORTABLE_MCP = ROOT / "mcp.json"
CURSOR_MCP = ROOT / "mcp.cursor.json"
GEMINI_MANIFEST = ROOT / "gemini-extension.json"

AGENT_PLUGINS_MCP_SCHEMA = "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json"
META_KEYS = ("description", "version", "author", "homepage", "repository", "license", "keywords")


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def render(data: dict) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def launcher_from_claude_mcp() -> tuple[str, str, list[str]]:
    """Return (server_name, launcher path relative to the plugin root, args without --client)."""
    servers = load(CLAUDE_MCP).get("mcpServers", {})
    if len(servers) != 1:
        raise ValueError(".mcp.json must declare exactly one server")
    (name, cfg), = servers.items()
    command = cfg.get("command", "")
    prefix = "${CLAUDE_PLUGIN_ROOT}/"
    if not command.startswith(prefix):
        raise ValueError(".mcp.json command must start with ${CLAUDE_PLUGIN_ROOT}/")
    rel = command[len(prefix):]
    args = list(cfg.get("args", []))
    if "--client" in args:
        i = args.index("--client")
        del args[i:i + 2]
    return name, rel, args


def for_client(src: dict, client_label: str) -> dict:
    """The Claude Code manifest's text names Claude Code; each client reads its own name."""
    out = dict(src)
    if isinstance(out.get("description"), str):
        out["description"] = out["description"].replace("Claude Code", client_label)
    return out


def build_cursor_manifest(src: dict) -> dict:
    src = for_client(src, "Cursor")
    m: dict = {"name": src["name"]}
    for k in META_KEYS:
        if k in src:
            m[k] = src[k]
    if isinstance(m.get("author"), dict):
        m["author"] = {k: v for k, v in m["author"].items() if k in ("name", "email")}
    m["skills"] = "./skills"
    m["mcpServers"] = "./mcp.cursor.json"
    m["hooks"] = "./hooks/cursor.hooks.json"
    return m


def build_codex_overlay(src: dict, root: dict) -> dict:
    src = for_client(src, "Codex")
    m: dict = {"name": src["name"]}
    for k in META_KEYS:
        if k in src:
            m[k] = src[k]
    if isinstance(m.get("author"), dict):
        m["author"] = {k: v for k, v in m["author"].items() if k in ("name", "email", "url")}
    m["skills"] = "./skills/"
    openai = root.get("extensions", {}).get("com.openai", {})
    # Codex gets NO hooks in v1; the empty hooks file stops default discovery of hooks/hooks.json.
    m["hooks"] = openai.get("hooks", "./hooks/codex.hooks.json")
    if "onboardingSkill" in openai:
        m["onboardingSkill"] = openai["onboardingSkill"]
    if "interface" in openai:
        m["interface"] = openai["interface"]
    return m


def build_portable_mcp(name: str, rel: str, args: list[str]) -> dict:
    return {
        "$schema": AGENT_PLUGINS_MCP_SCHEMA,
        "mcpServers": {name: {"type": "stdio", "command": "./" + rel, "args": args + ["--client", "codex"]}},
    }


def build_cursor_mcp(name: str, rel: str, args: list[str]) -> dict:
    return {"mcpServers": {name: {"command": "${CURSOR_PLUGIN_ROOT}/" + rel, "args": args + ["--client", "cursor"]}}}


def build_gemini(src: dict, name: str, rel: str, args: list[str]) -> dict:
    src = for_client(src, "Gemini CLI")
    return {
        "name": src["name"],
        "version": src.get("version", "0.0.0"),
        "description": (src.get("description", "") + " (Gemini CLI manifest generated from the Claude Code plugin; untested.)").strip(),
        "contextFileName": "agentsmd/AGENTS.md",
        "mcpServers": {name: {"command": "${extensionPath}/" + rel, "args": args + ["--client", "gemini"]}},
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="fail when a generated file is stale")
    a = ap.parse_args()

    src = load(CLAUDE_MANIFEST)
    root = load(ROOT_MANIFEST)
    if src.get("name") != root.get("name"):
        print(f"name mismatch: .claude-plugin/plugin.json={src.get('name')!r} plugin.json={root.get('name')!r}", file=sys.stderr)
        return 1
    if src.get("version") != root.get("version"):
        print("version mismatch between .claude-plugin/plugin.json and plugin.json (run plugin_versions.py bump)", file=sys.stderr)
        return 1
    name, rel, args = launcher_from_claude_mcp()

    outputs = {
        CURSOR_MANIFEST: render(build_cursor_manifest(src)),
        CODEX_MANIFEST: render(build_codex_overlay(src, root)),
        PORTABLE_MCP: render(build_portable_mcp(name, rel, args)),
        CURSOR_MCP: render(build_cursor_mcp(name, rel, args)),
        GEMINI_MANIFEST: render(build_gemini(src, name, rel, args)),
    }
    stale = []
    for path, content in outputs.items():
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == content:
            continue
        if a.check:
            stale.append(path.relative_to(ROOT).as_posix())
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT).as_posix()}")
    if a.check:
        if stale:
            print("Generated manifests are out of date:", file=sys.stderr)
            for s in stale:
                print(f"  - {s}", file=sys.stderr)
            print("Run: python3 -I scripts/generate_manifests.py", file=sys.stderr)
            return 1
        print("Generated manifests are up to date.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
