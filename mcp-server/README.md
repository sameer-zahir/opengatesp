# OpenGateSP MCP server

Drive OpenGateSP from an AI assistant (Claude, Codex, Gemini, Cursor, …) over the
[Model Context Protocol](https://modelcontextprotocol.io). It runs the same PowerShell engine
the CLI and GUI use — a long-lived `pwsh` host process the server talks to over a JSON-lines
protocol — so there's no duplicated SharePoint logic.

## Tools

Write tools are **preview-first, enforced server-side**: every write defaults to a `-WhatIf`
preview, and `execute: true` is only honored after the **identical call** (same tool, same
arguments) was previewed earlier in the same session — otherwise it runs as another preview and
the result says so. Approvals are single-use: applying consumes the preview, so a repeat apply
needs a fresh preview. Even an MCP client configured to auto-approve tools can't one-shot a write.

**Status & reports (read-only)**

| Tool | What it does |
|---|---|
| `sharepoint_status` | Engine/connection status (no SharePoint call) |
| `sharepoint_external_sharing_report` | External users + sharing links for a site |
| `sharepoint_permission_report` | Who has access; broken inheritance |
| `sharepoint_permissions_matrix` | Per-principal access matrix — who can touch what |
| `sharepoint_orphaned_users` | Users with access who no longer exist in the directory |
| `sharepoint_site_inventory` | Tenant-wide sites + storage (needs SharePoint admin) |

**Governance (Protect-style)**

| Tool | What it does |
|---|---|
| `sharepoint_everyone_claims` | Where "Everyone"/EEEU has access — oversharing, graded Error/Warning |
| `sharepoint_ownerless_groups` | Microsoft 365 Groups with no owner (needs Graph `Group.Read.All`) |
| `sharepoint_governance_review` | Consolidated severity-graded review: broad grants + sharing + stale access |
| `sharepoint_set_site_lifecycle` | Lock / archive / unlock a site. Preview by default |

**Explore & discovery (read-only)**

| Tool | What it does |
|---|---|
| `sharepoint_explore` | Consolidated pre-migration source assessment, graded Error/Warning |
| `sharepoint_checked_out_files` | Files left checked out (migration blocker) |
| `sharepoint_large_files` | Largest files at/above a size threshold |
| `sharepoint_version_report` | Files with heavy version history |
| `sharepoint_content_insights` | Library contents by file type (count + MB) |
| `sharepoint_workflow_report` | SharePoint 2013-platform workflows (don't migrate) |
| `sharepoint_inactive_sites` | Sites with no changes for N days (needs admin) |

**Remediation** — all preview by default

| Tool | What it does |
|---|---|
| `sharepoint_check_in_files` | Bulk check-in of checked-out files |
| `sharepoint_clear_version_history` | Trim a file's version history to the newest N |
| `sharepoint_restore_inheritance` | Restore permission inheritance on a list or item |
| `sharepoint_remove_orphaned_users` | Remove stale-access users (needs Graph `User.Read.All`) |

**Migration & copy** — writes preview by default

| Tool | What it does |
|---|---|
| `sharepoint_precheck_migration` | Pre-check a local folder for blockers (local, read-only) |
| `sharepoint_migrate_files` | Local folder → library, preserving structure + timestamps |
| `sharepoint_copy_site` | Same-tenant site copy (structure + optional content/permissions/versions) |
| `sharepoint_copy_list` | Single list/library copy (schema + optional content) |
| `sharepoint_copy_permissions` | Role-assignment copy with principal remapping |
| `sharepoint_copy_site_cross_tenant` | Cross-tenant site copy (app-only cert per tenant) |
| `sharepoint_copy_term_group` | Cross-tenant managed-metadata term-group copy (app-only cert per tenant) |
| `sharepoint_compare_site` | Post-migration validation — diff destination vs source (read-only) |

**Identity copy (Entra tenant-to-tenant)** — the [docs/14](../docs/14-identity-copy.md) pipeline; app-only cert per tenant

| Tool | What it does |
|---|---|
| `sharepoint_identity_inventory` | Inventory the source tenant's users, guests, and groups (read-only) |
| `sharepoint_identity_map` | Propose the source→destination map as a hand-editable CSV (read-only) |
| `sharepoint_identity_validate` | Validate the edited map: collisions, unverified domains (read-only) |
| `sharepoint_identity_copy` | Create users/guests/groups + sync rosters. Preview by default; passwords/MFA/licenses never migrate |

**Collaboration & provisioning** — writes preview by default

| Tool | What it does |
|---|---|
| `sharepoint_copy_m365_group` | Clone a Microsoft 365 Group (description + roster) |
| `sharepoint_copy_team` | Clone a Team (channels + membership) |
| `sharepoint_copy_planner_plan` | Recreate a Planner plan (buckets + tasks) |
| `sharepoint_provision_site` | Create a site |
| `sharepoint_bulk_metadata` | CSV-driven bulk metadata edits |

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
- **Writes are preview-gated in the engine host** (not just in tool descriptions): an apply that
  wasn't previewed in this session is downgraded to a preview, and approvals are single-use. Still,
  don't blanket-auto-approve OpenGateSP's write tools in your MCP client — reviewing the preview is
  the point.
- Engine host output is silenced (`OPENGATESP_QUIET`) so logging can't corrupt the protocol.
- Override the PowerShell executable with the `OPENGATESP_PWSH` environment variable if needed.

## How it works

```
AI client ──MCP/stdio──> index.ts (tools) ──JSON lines──> engine-host.ps1 (pwsh)
                                                              └─ Import-Module OpenGateSP
                                                              └─ Connect-SPTool (once)
                                                              └─ Get-SP* / Start-SP* ...
```
