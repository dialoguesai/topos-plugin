# Connect a remote AI client to Topos

Use this path for Claude web/cloud tasks, or when a desktop-local connection is missing
from the browser account. This is setup guidance, not an automatic installer or a claim
that the live server supports every authentication option. Keep the local setup unchanged
unless the requested connection actually depends on a missing node.

## Establish what is being connected

- Identify the destination AI account/surface, intended Topos account and node, and access
  purpose. Distinguish owner-agent access from a restricted app/share grant. For a scoped
  task, record the allowed data and operations; an instruction saying "business only"
  does not establish an enforced permission boundary.
- Inspect the actual destination's connector inventory and reuse an existing entry.
  A local adapter or token file proves only that configuration exists. Never copy a local
  owner credential into a cloud connector to work around a failed scoped connection.
- Verify sign-in in the browser session being controlled. A user's sign-in in another
  browser or desktop app may not carry over. Reopen the intended page once if needed;
  if it still shows login, clarify which session they used rather than repeating login.
- Get the remote URL from the deployed service or documented existing configuration.
  The production CP used on 2026-10-22 was `https://cp.logu3s.com/mcp/`; verify the current
  host for this account. Localhost and a local stdio launcher are not cloud endpoints.

## Add or repair the Claude connector

Use the current supported UI/API. In Claude's October 2026 UI: Customize → Connectors →
Yours; Add → Add custom connector accepts a name and remote MCP URL, then detects auth.
Configure only the requested connector. Adding an entry, signing in and approving access
are distinct actions; follow the host's approval policy at each boundary and reuse prior
authorization when it covers the exact action. Do not interpret setup consent as consent
to broader data access, a different account or distribution.

Claude offers OAuth client registration automatically, its published identity (CIMD), or
a pre-registered client ID. Choose based on the deployed authorization server's support,
not the option's label. Do not assume CIMD works merely because Claude offers it. For a
pre-registered client, first inspect the identity provider's existing clients; a missing
Sheaf listing alone does not prove that no OAuth client exists in Keycloak.

For Keycloak, Claude's documented callback is
`https://claude.ai/api/mcp/auth_callback` (recheck current Claude documentation before
changing registration). It belongs in **Valid redirect URIs on Claude's OAuth client**.
It is not a callback route to implement in Topos or Keycloak, and a Sheaf app record alone
does not prove this OAuth registration is ready. Use the supported registration workflow,
exact redirects and compatible authorization-code/PKCE and client-auth settings; do not
invent a client ID or assume a secret is required. Enter any required secret through the
approved credential flow, never through chat or evidence files.

If Claude says it **couldn't register with the sign-in service**:

1. Preserve the existing connector and record the error, time and support reference without
   tokens or authorization codes. Registration failed before user sign-in; this does not
   diagnose a missing redirect, bad password, missing node or denied data grant.
2. Read public protected-resource / authorization-server discovery and, where authorized,
   the identity provider's registration logs and policy. A blocked diagnostic fetch is not
   evidence that Claude received the same error. Keycloak's anonymous registration policies
   can reject DCR, but confirm the actual cause before changing them.
3. Repair the demonstrated issue, or use an existing/dedicated pre-registered OAuth client
   through Claude's "Use your own OAuth client" option. Prepare the exact configuration
   before any approval needed to create/change it. Do not globally relax registration
   policies, use wildcard redirects, or paste the desktop bearer as a shortcut.
4. Retry when there is a meaningful change or evidence of a transient failure. Do not
   recreate connectors or clients repeatedly. If administrative access is unavailable,
   give the responsible person the precise configuration/log request and stop that branch.

## OpenAI and Cursor callbacks

Do not add other AI clients' redirects to Claude's client. Inspect each intended client's
registration and transport first; a local stdio connection needs no remote OAuth callback.

- **ChatGPT:** copy the exact production redirect from the MCP server's management page.
  Current OpenAI documentation distinguishes the stable
  `https://chatgpt.com/connector_platform_oauth_redirect` from
  `https://chatgpt.com/connector/oauth/{callback_id}`. The stable callback is used for
  eligible issuer-identification flows and older registrations. Never register the
  placeholder, guess the ID, or confuse a CIMD `client.json` identity with a redirect.
  An existing allowed stable callback proves only that registration entry exists;
  verify the actual connection before declaring authentication working.
- **Cursor remote MCP:** current documented callbacks are
  `https://www.cursor.com/agents/mcp/oauth/callback` for web/Agents and
  `http://localhost:8787/callback` for desktop. Register only the requested surfaces on
  Cursor's client. For desktop-only static OAuth, configure the issued `CLIENT_ID`;
  dynamic registration can also use the web handoff. Do not create a remote client
  merely because the local Topos plugin is installed.

## Verify each outcome separately

Report what was observed and what remains unknown:

| Outcome | Evidence |
|---|---|
| Connector added | Entry in the intended AI account, actual endpoint and connector ID/link |
| Authentication works | Completed sign-in and connected state; no unresolved registration error |
| Intended access works | Supported identity/share discovery establishes caller, intended owner/node and permitted operations; unknown fields remain unknown |
| Useful read works | One authorized bounded request through that actual client, with its result/receipt; another agent's answer is not a substitute |
| Source ingestion works, if requested | Enabled source plus successful sync/checkpoint; queued work or a client read is not collection |
| Scheduled task works, if requested | Existing task inspected, correct prompt/cadence/timezone/permissions, real run ID and result |

Discover the tools exposed by that connection; do not force the local five-tool contract
or `ai_coding_sessions:read` onto an outside client. Some deployed outside-client paths use
`list_shared_with_me` and `ask_shared`; use them only when actually exposed and authorized.
Keep access tests within approved data. Do not probe unrelated personal records to test a
denial. If stronger acceptance is required, use an explicitly approved synthetic fixture.

"Added but disconnected" is **INCOMPLETE**, not a working integration. Record a real run
as manual or scheduled; an editorial preview made by the setup agent is neither proof of
the destination client's access nor a completed scheduled run. Inspect a task before
creating a duplicate or assuming its saved prompt and schedule match a local artifact.
Connecting Topos does not itself authorize a schedule change or sending its output.

## Branding

The local plugin already carries `assets/logo.png`. That manifest asset is separate from
the remote MCP server's branding. A server can advertise `serverInfo.icons` and host public
icon assets, but Claude decides what its connector tile displays. As of 2026-10-22,
Anthropic's tracker has an open report that custom connector icons are ignored or replaced
with cached favicons. Verify current behavior before promising a logo change. Do not
generate a replacement logo, change production domains or recreate connectors merely to
try to refresh the tile. Icon work is not an authentication fix.

## References

- [Claude remote connector setup](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
- [Claude local versus remote connectors](https://support.claude.com/en/articles/11725091-when-to-use-desktop-and-web-connectors)
- [Claude callback documentation](https://support.anthropic.com/en/articles/11503834-building-custom-integrations-via-remote-mcp-servers)
- [Keycloak client registration policies](https://www.keycloak.org/securing-apps/client-registration)
- [OpenAI OAuth and redirect configuration](https://developers.openai.com/plugins/build/auth)
- [Cursor MCP and static OAuth configuration](https://prod.cursor.com/docs/mcp)
- [Claude custom connector icon issue](https://github.com/anthropics/claude-ai-mcp/issues/152)

These external interfaces can change. Treat the dated observations as troubleshooting
evidence, not permanent product constraints or a claim about every deployment.
