# OpenGateSP MCP server

Drive OpenGateSP from an AI assistant (Claude, Codex, Gemini, Cursor, …) over the
[Model Context Protocol](https://modelcontextprotocol.io). It runs the same PowerShell engine
the CLI and GUI use — a long-lived `pwsh` host process the server talks to over a JSON-lines
protocol — so there's no duplicated SharePoint logic.

## Tools

| Tool | What it does |
|---|---|
| `sharepoint_status` | Engine/connection status (no SharePoint call) |
| `sharepoint_external_sharing_report` | External users + sharing links for a site |
| `sharepoint_permission_report` | Who has access; broken inheritance |
| `sharepoint_site_inventory` | Tenant-wide sites + storage (needs SharePoint admin) |
| `sharepoint_migrate_files` | Local folder → library. **Preview by default**; `execute: true` to upload |
| `sharepoint_provision_site` | Create a site. **Preview by default**; `execute: true` to create |
| `sharepoint_bulk_metadata` | CSV-driven bulk edits. **Preview by default**; `execute: true` to apply |

Write tools default to a `-WhatIf` preview — an agent must pass `execute: true` to change anything.

## Prerequisites

- **PowerShell 7.4+** (`pwsh`) on `PATH`, with **PnP.PowerShell** installed.
- **Node.js 20+**.
- You have connected once and saved defaults so the host can reconnect:
  ```powershell
  Import-Module ../module/OpenGateSP/OpenGateSP.psd1
  Connect-SPTool -Url https://contoso.sharepoint.com -ClientId <id> -Tenant contoso.onmicrosoft.com -SaveConfig
  ```

## Build

```bash
cd mcp-server
npm install
npm run build      # compiles src/ -> dist/
```

## Connect it to a client

**Claude Desktop / Claude Code** (`claude_desktop_config.json` or your MCP config):

```json
{
  "mcpServers": {
    "opengatesp": {
      "command": "node",
      "args": ["C:/Users/you/Desktop/git/opengatesp/mcp-server/dist/index.js"]
    }
  }
}
```

Then ask: *"Use OpenGateSP to show external sharing on https://contoso.sharepoint.com/sites/Marketing."*

## Auth & safety

- **Delegated:** the first SharePoint call opens a browser once; the connection then persists in
  the host process.
- **Headless:** configure app-only certificate auth ([docs/05](../docs/05-app-only-auth.md)) and
  the server needs no sign-in at all.
- **Delegated** — the agent can never exceed your own SharePoint permissions.
- Engine host output is silenced (`OPENGATESP_QUIET`) so logging can't corrupt the protocol.
- Override the PowerShell executable with the `OPENGATESP_PWSH` environment variable if needed.

## How it works

```
AI client ──MCP/stdio──> index.ts (tools) ──JSON lines──> engine-host.ps1 (pwsh)
                                                              └─ Import-Module OpenGateSP
                                                              └─ Connect-SPTool (once)
                                                              └─ Get-SP* / Start-SP* ...
```
