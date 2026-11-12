# Topos plugin for Claude Code, Codex and Cursor

One plugin, three clients. It turns your coding agent into your Topos: say **"set up
Topos"** and the agent installs or finds the Topos node on this computer, starts it, lets
you approve the agent once in a Terminal window, and turns on your own session history as a
source. No account is needed: the node runs on this computer alone. Then ask it things like
*"What have I been building this week, and where did I get stuck?"*

- Your transcript files never leave the computer; the node reads them here.
- Answers you ask for go to the AI company behind the tool you asked in.
- No key is ever typed into a chat, a config file or this plugin.
- **Connect an account later, if you want to.** Say "connect my Topos account": the agent
  shows a code to approve in the browser, Topos restarts, and everything it has collected
  moves to that account. An account adds sharing, the web and phone apps and cloud sources.

Plugin name `topos`, marketplace `topos`, Claude Code install id `topos@topos`. Layout
follows [Agent Plugins 1.0.0](https://agent-plugins.org) (`plugin.json`, `skills/`,
`mcp.json`) with each client's own manifest beside it.

## Requirements

Branding uses the same committed `assets/logo.png` across Cursor's `logo`, OpenAI's
`interface.logo` / `composerIcon`, and Anthropic's directory `icon`. Installing an updated
package makes these fields available to the host; it does not update a separately configured
remote MCP connector. See [remote branding](skills/topos-setup/references/remote-clients.md#branding)
for the server metadata and known Claude rendering limitation.

- A Topos node **1.5.15 or later** for the one-command setup (`topos-node setup`). On an
  older node the setup skill says so and offers to update it; everything else works.
- Running **without an account** needs the node release after 1.5.44: its
  `topos-node setup --help` lists `--connect`, and `topos-node status --json` reports
  `mode: local`. An earlier node pairs an account first and cannot start without a key; the
  setup skill follows whichever node is installed.
- What each client does after setup: Claude Code syncs a session the moment it ends
  (`Stop` hook) and hourly; Cursor syncs at `stop` when transcripts are on, and hourly;
  Codex syncs hourly (no hooks by design). The node reads the transcript files locally.
- The agent connects as your own agent on the node's local socket, approved once by you:
  it can read your Topos through five tools and change nothing. Revoke it any time with
  `topos-node agents revoke <client>`.

## Install

No plugin yet, or a client where the plugin is awkward to install first (Codex Desktop,
Cursor)? Paste one sentence into the agent: **"Set up Topos by following
topos.dialogues.ai/setup/agent.md"**. That agent-readable page
([`https://topos.dialogues.ai/setup/agent.md`](https://topos.dialogues.ai/setup/agent.md))
is the same journey in the owner's order — install Topos, create it, add the tool as a
source — and installs this plugin last.

### Claude Code (v2.1.275 or later)

In a session, one line — the review panel lists the skills, the MCP server and the hooks,
and the plugin reloads by itself:

```
/plugin install topos --marketplace dialoguesai/topos-plugin
```

Two steps on older versions, or from the shell:

```
/plugin marketplace add dialoguesai/topos-plugin
/plugin install topos@topos
```

```bash
claude plugin marketplace add dialoguesai/topos-plugin
claude plugin install topos@topos        # then /reload-plugins in an open session
```

Then type **`/topos:setup`** (or say "set up Topos"). It asks you once, runs
`topos-node setup` until everything is done, and stops only for the step that is yours:
approving Claude Code once in a Terminal window. No account, no code, no browser. To add an
account later, say "connect my Topos account" (`/topos:setup --connect`): then a code to
approve in the browser and "is that you?" are yours too, Topos restarts, and what it has
collected moves to the account. After setup, terminal users run `/mcp reconnect all`
(v2.1.284+) if the Topos tools have not attached; the desktop app and VS Code pick the
server up in the next session. Plugin auto-update is off by default for third-party
marketplaces: enable it under `/plugin → Marketplaces`, or run
`claude plugin update topos@topos`.

Note: this plugin ships a `bin/` directory (the launcher). claude.ai and Cowork do not
install plugins with a top-level `bin/`; cloud sessions have no local node to talk to
anyway, and they are not captured.

Connecting **Claude web or a cloud scheduled task** is a separate remote MCP setup;
local plugin enrollment or `claude_desktop_config.json` does not carry over to it.
The setup skill can guide that workflow from a local agent: see
[remote client setup and OAuth troubleshooting](skills/topos-setup/references/remote-clients.md).
This guidance does not make the local launcher a cloud plugin or turn on cloud-session capture.

### Codex

```bash
codex plugin marketplace add dialoguesai/topos-plugin
```

Then run `codex`, type `/plugins`, pick **topos** from marketplace **topos**, install it,
and **start a new session**. Codex Desktop: Plugins tab → marketplace **topos** → install,
then restart the app. The Codex manifest carries **no hooks**; your sessions are picked up
by the node's hourly sync. The node's MCP tools can take longer than Codex's default
per-tool timeout of 60 s on a slow question; the setup skill tells you if that bites.

### Cursor

Cursor's plugin list shows **topos** by Dialogues from this repository's marketplace file;
install it there when it is offered. Otherwise clone into the local plugins folder, then
reload:

```bash
git clone https://github.com/dialoguesai/topos-plugin ~/.cursor/plugins/local/topos
```

Run **Developer: Reload Window**, then enable the `topos` MCP server when Cursor asks.
Keep one install, not both. Say "set up Topos" in a chat: Cursor's agent runs the same
`topos-node setup` journey and stops for the one approval that is yours. The `stop` hook
carries a transcript only when transcripts are enabled in Cursor's settings; otherwise the
hourly sync does the work. Enterprise workspaces block local plugins by default.

### Gemini CLI (untested)

`gemini-extension.json` is generated from the Claude Code manifest and has not been
tried: `gemini extensions install https://github.com/dialoguesai/topos-plugin --consent`.

## Skills

<!-- BEGIN_SKILLS_TABLE -->
| Skill | What it does | File |
|---|---|---|
| `topos-add-fact-pack` | Turn a plain request ("keep track of the books I read", "remember my workouts") into a fact pack on the person's own Topos. Draft the pack YAML, check it and its trigger words, try its examples on the local model, then open one owner approval that adds the pack and switches it on (and reads history only if the person asks). Works without a Dialogues account. Use when someone wants Topos to start noticing a new kind of fact in their own records; connecting a new data source is the topos-add-source skill. | [SKILL.md](skills/topos-add-fact-pack/SKILL.md) |
| `topos-add-source` | Create a private local Topos source from JSON, JSONL or CSV through the node CLI. Inspect a sample, prepare and validate its definition, open the owner's approval prompt, and verify installation and import. Works without a Dialogues account, developer API key or Sheaf registration. Use for adding a new custom source to a person's Topos; existing connector setup and public registry publishing are separate workflows. | [SKILL.md](skills/topos-add-source/SKILL.md) |
| `topos-ask` | Answer a question from the user's own Topos (their messages, mail, chat history, coding sessions and the facts and goals derived from them) through the plugin's Topos tools. Use whenever the user asks about their own history, data, contacts, projects or past conversations — "what have I been building", "what did I ask Claude Code yesterday", "who did I talk to about X", "how many sessions last month", "what's in my Topos" — or names Topos. | [SKILL.md](skills/topos-ask/SKILL.md) |
| `topos-setup` | Set up Topos for the requested AI client. For local coding agents, find or install the node, start it on this computer with no account, connect the agent and enable approved session capture; connecting a Dialogues account is a separate, optional step (`--connect`) that keeps everything collected. For Claude web or cloud tasks, guide the separate remote connector and OAuth setup. Use for Topos installation, connection, updates, "connect my Topos account", or setup failures. | [SKILL.md](skills/topos-setup/SKILL.md) |
| `topos-shadow` | Explain and control how this tool's own session history becomes a Topos source — what the node reads from the transcript files, what it leaves out, which folders to skip, how to pause or resume, how to disconnect this tool, and why cloud sessions are not captured. Use when the user asks "what does Topos keep from my sessions", "what gets uploaded", "skip this folder", "pause Topos", "stop syncing", "disconnect Claude Code from Topos", "delete what Topos read", or before enabling the source. | [SKILL.md](skills/topos-shadow/SKILL.md) |
<!-- END_SKILLS_TABLE -->

Clients without plugin support can use [`agentsmd/AGENTS.md`](agentsmd/AGENTS.md) as the
instruction bundle.

## What is in the box

| Path | Client | What |
|---|---|---|
| `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Claude Code | manifest and the `topos` marketplace |
| `.mcp.json` | Claude Code | `${CLAUDE_PLUGIN_ROOT}/bin/topos-mcp --client claude-code` |
| `hooks/hooks.json` | Claude Code | `Stop` (async) → `bin/topos-sync`; `SessionStart` → `bin/topos-health` |
| `plugin.json`, `mcp.json`, `.agents/plugins/marketplace.json`, `.codex-plugin/plugin.json` | Codex | Agent Plugins root, portable MCP file (`./bin/topos-mcp --client codex`), marketplace, overlay (no hooks) |
| `.cursor-plugin/plugin.json`, `.cursor-plugin/marketplace.json`, `mcp.cursor.json`, `hooks/cursor.hooks.json` | Cursor | manifest, marketplace, MCP file (`${CURSOR_PLUGIN_ROOT}/bin/topos-mcp --client cursor`), `stop` hook |
| `gemini-extension.json` | Gemini CLI | generated, untested |
| `bin/topos-mcp` | all | POSIX launcher: resolves `topos-node` by the fixed list (`$TOPOS_NODE_BIN`, `~/.local/bin`, `~/.topos/runtime/bin`, `/opt/homebrew/bin`, `/usr/local/bin`), waits for the node's socket, execs `topos-node mcp --client NAME`; otherwise serves a stand-in that answers every call with "say set up Topos" / "say start Topos" and hands over to the real server when the node appears |
| `bin/topos-sync` | Claude Code, Cursor | reads `transcript_path` from the hook's stdin (nothing else), starts `topos-node sources sync <source> --session PATH --quiet` detached, exits at once |
| `bin/topos-health` | Claude Code | one line at session start when Topos is not running, has no identity, this agent is not enrolled, or the node is out of date; a node running without an account gets one soft "connect later" line, once per computer, never a nag |
| `bin/topos-node` | Claude Code's Bash tool | wrapper so `topos-node …` works even when `~/.local/bin` is not on PATH |
| `skills/` | all | `topos-setup`, `topos-ask`, `topos-shadow` |
| `evals/` | Claude Code | `claude plugin eval .` cases with mocked Topos tools |
| `scripts/` | maintainers | `publish.sh`, `generate_manifests.py`, `generate_agents.py`, `plugin_versions.py`, `check_schema.py` |

No secret lives anywhere in this repository, and the plugin asks for none: the node
authenticates the agent over its local socket with a label it mints itself.

## Develop

```bash
./scripts/publish.sh            # regenerate manifests, AGENTS.md, README table; bump if needed
./scripts/publish.sh --check    # CI: everything current, versions in sync, schemas valid
claude plugin validate .        # Claude Code's own validator
claude --plugin-dir .           # try it in a session without installing
claude plugin eval .            # run the eval suite against mocked Topos tools
sh tests/test_fallback_mcp.sh   # the stand-in MCP server with no node on this machine
sh tests/test_hook_budget.sh    # the Stop hook exits inside 1.5 s
sh tests/test_health_hook.sh    # the SessionStart line: silent, once for a local node, never a nag
sh tests/test_check_node.sh     # the setup checks c1–c8 against a fake node (account and local)
```

Release: bump with `python3 -I scripts/plugin_versions.py bump patch`, run
`./scripts/publish.sh`, commit, tag `v<version>` and `topos--v<version>`
(`claude plugin tag .`).

## License

MIT — see [LICENSE](LICENSE).
