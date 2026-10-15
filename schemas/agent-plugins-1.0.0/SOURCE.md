# Vendored Agent Plugins 1.0.0 schemas

Fetched 2026-10-15 (UTC) for `scripts/check_schema.py`:

- `plugin.schema.json` — `https://agent-plugins.org/schemas/1.0.0/plugin.schema.json`
  (served content returned verbatim by the fetch on the second attempt; the first
  attempt summarised it. Byte-identity with the live file is NOT asserted;
  `scripts/check_schema.py --refresh` re-downloads and diffs when a network is allowed).
- `mcp.schema.json` — `https://raw.githubusercontent.com/agentplugins/agent-plugins-spec/main/schemas/1.0.0/mcp.schema.json`
  (returned verbatim). The canonical URL is `https://agent-plugins.org/schemas/1.0.0/mcp.schema.json`.

Spec repository: `https://github.com/agentplugins/agent-plugins-spec` (`spec/1.0.0.md`).
Rules that matter for this plugin, quoted from the spec on 2026-10-15:

- stdio `command` "MUST be either a bare executable name or a plugin-relative path
  beginning with `./`"; "Clients MUST NOT perform placeholder expansion in `command`";
  `${PLUGIN_ROOT}` / `${PLUGIN_DATA}` expand only in `args`, `env` values and `cwd`.
- Hooks are not part of the portable core ("Agent Plugins v1 defines exactly two
  component types", skills and MCP servers); client-specific files live under a
  reverse-domain directory or the client's own conventions.
- `version` is optional ("Semantic Versioning RECOMMENDED").
