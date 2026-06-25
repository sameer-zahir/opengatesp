# OpenGateSP

> **The free, open-source [ShareGate](https://sharegate.com) alternative** for SharePoint Online — **migrate** file shares into SharePoint, **audit** permissions and external sharing, and **provision** sites. A PowerShell engine + a Windows GUI (MCP server on the roadmap). MIT-licensed.

> **Status: v0.1.0 — early.** The engine (a PowerShell module) and the GUI ship first; an MCP server (so Claude / Codex / Gemini can drive it) is on the roadmap. Built as a real day-job utility for one enterprise tenant and open-sourced.

## Why this exists

ShareGate is, under the hood, *scripts behind a GUI* — and it costs thousands per year. OpenGateSP is those scripts, free and modern: one engine that does the migration, governance, and provisioning work, with a GUI on top and an AI-driven interface to come.

```
PowerShell module (OpenGateSP)   ← the engine (built on PnP.PowerShell)
   ├── Windows GUI               ← loads the module, calls its functions
   └── MCP server (roadmap)      ← exposes the same functions to Claude / Codex / Gemini
```

## What it does (v0.1.0)

| Area | Function | What it does |
|---|---|---|
| **Migration** | `Start-SPFileMigration` | Local file share / folder → SharePoint library, preserving folder structure and timestamps. Dry-run by default. |
| **Reporting / governance** | `Get-SPSiteInventory` | Sites + storage + last activity (tenant-wide) |
| | `Get-SPPermissionReport` | Who has access to a site/library, and where inheritance is broken |
| | `Get-SPSharingReport` | External users and sharing links |
| **Provisioning / bulk** | `New-SPSiteFromTemplate` | Create a site or library from a template spec |
| | `Set-SPBulkMetadata` | CSV-driven bulk column updates across a list/library |

Every function supports `-AsJson` for clean, structured output (the same contract the GUI and the future MCP server consume).

## What it is — and isn't

- **It is:** a toolkit you run against *your own* tenant, with *your own* Entra ID app, bounded by *your own* permissions.
- **It isn't:** a hosted service or a paid product with a support contract. There are already plenty of "SharePoint MCP servers" that let an AI *read files* — OpenGateSP does the migration and administration work that ShareGate actually charges for.

## Requirements

- **PowerShell 7.4+** (the GUI is Windows-only; the engine is cross-platform)
- **[PnP.PowerShell](https://pnp.github.io/powershell/)** module
- **Your own Entra ID app** — one command creates it (see [docs/02](docs/02-entra-app-registration.md))
- For tenant-wide reports: the **SharePoint Administrator** role

## Quickstart

```powershell
# 1. Install the engine dependency
Install-Module PnP.PowerShell -Scope CurrentUser

# 2. Register your own Entra ID app (one time; opens a browser to consent)
Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "OpenGateSP" -Tenant contoso.onmicrosoft.com
#    → note the ClientId it prints

# 3. Import the module and connect (saves your defaults)
Import-Module ./module/OpenGateSP/OpenGateSP.psd1
Connect-SPTool -Url https://contoso.sharepoint.com -ClientId <clientId> -Tenant contoso.onmicrosoft.com -SaveConfig

# 4. Preview a migration (nothing is written without -Confirm / removing -WhatIf)
Start-SPFileMigration -Source "C:\Shares\Marketing" -SiteUrl https://contoso.sharepoint.com/sites/Marketing -WhatIf
```

Prefer a window? Launch the GUI:

```powershell
pwsh -STA -File ./gui/Start-OpenGateSPGui.ps1
```

Full walkthrough: [docs/03-quickstart.md](docs/03-quickstart.md).

## Safety

- **Delegated auth** — OpenGateSP can never exceed what your own account can already do in SharePoint.
- **Write operations are cautious** — `Start-SPFileMigration`, `Set-SPBulkMetadata`, and `New-SPSiteFromTemplate` support `-WhatIf`/`-Confirm` and ask once before a real run. **Always test against a throwaway site before production.**
- No client secret exists in this setup, so there is nothing secret to leak. `spconfig.json` (your tenant/client id) is git-ignored.

## Roadmap

MCP server (drive it from Claude / Codex / Gemini) · app-only certificate auth for scheduled/unattended runs · tenant-to-tenant and full-site migration · Teams/Group migration · PowerShell Gallery publish. See [docs/roadmap.md](docs/roadmap.md).

## License

[MIT](LICENSE) — do whatever you want with it.

---

<sub>OpenGateSP is an independent open-source project and is not affiliated with or endorsed by ShareGate or Workleap. "ShareGate" is a trademark of its respective owner.</sub>
