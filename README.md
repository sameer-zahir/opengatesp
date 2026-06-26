# OpenGateSP

[![CI](https://github.com/sameer-zahir/opengatesp/actions/workflows/ci.yml/badge.svg)](https://github.com/sameer-zahir/opengatesp/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/sameer-zahir/opengatesp?color=82aaff)](https://github.com/sameer-zahir/opengatesp/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![PowerShell 7.4+](https://img.shields.io/badge/PowerShell-7.4%2B-5391FE?logo=powershell&logoColor=white)

> **The free, open-source [ShareGate](https://sharegate.com) alternative** for SharePoint Online and Microsoft 365 — **migrate** file shares into SharePoint, **pre-check** sources before you move them, **audit** permissions and external sharing, **provision** sites, and **schedule** governance reports. A themed Windows app, a PowerShell engine, and an MCP server so your AI assistant can drive it. MIT-licensed.

![OpenGateSP — themed SharePoint admin GUI](docs/screenshot-dark.png)

## Install

**Easiest — the installer.** [Download **`OpenGateSP-Setup.exe`**](https://github.com/sameer-zahir/opengatesp/releases/latest) and double-click it. It installs per-user (no admin), drops a **Start Menu + desktop shortcut**, and registers an uninstaller — like any normal app. First launch shows the one-time (free) Entra app registration, then opens the app.

**Portable — no install.** Prefer to keep it in a folder? Download the `.zip`, unzip, and run **`OpenGateSP.exe`** (or `Start-OpenGateSP.cmd`).

> Needs **Windows + PowerShell 7.4+** (the installer points you to it if it's missing). The build is currently *unsigned*, so Windows SmartScreen shows a one-time **"More info → Run anyway"** — free open-source signing (SignPath) is in progress to remove that, and `winget install` is on the way.

## OpenGateSP vs ShareGate

ShareGate is a polished, expensive tool for work that ultimately comes down to SharePoint API calls anyone can script. OpenGateSP does that work with open PowerShell you can read and run yourself, for free. It's an independent project, built from scratch on [PnP PowerShell](https://pnp.github.io/powershell/) — not affiliated with ShareGate.

| | ShareGate | OpenGateSP |
|---|---|---|
| **Price** | thousands / year | **Free (MIT)** |
| File share / folder → SharePoint migration | ✅ | ✅ |
| Pre-migration readiness check | ✅ | ✅ |
| Permissions & external-sharing audit | ✅ | ✅ |
| Site provisioning + CSV bulk metadata | ✅ | ✅ |
| Scheduled governance reports | ✅ | ✅ |
| Drive it from an AI assistant (MCP) | — | **✅ built in** |
| Open source you can read, fork, and own | — | **✅** |
| Tenant-to-tenant, Teams, full content reorg | ✅ | on the roadmap |

OpenGateSP doesn't (yet) match ShareGate's full migration surface — it nails the common 80%: file-share migration, governance reporting, and provisioning, free and scriptable.

## Light & dark, built in

The GUI defaults to a clean **Microsoft Fluent**-style light theme, with Fluent dark and the warm **Gruvbox** / deep **Tokyo Night Moon** ([Squintless](https://github.com/sameer-zahir/squintless)) themes a click away in the picker.

![OpenGateSP light theme](docs/screenshot-light.png)

## What it does (v0.6.0)

| Area | Function | What it does |
|---|---|---|
| **Migration** | `Test-SPMigrationReadiness` | Pre-flight a local folder for SharePoint blockers (illegal names, over-long paths, oversized/empty files). Local, read-only. |
| | `Start-SPFileMigration` | Local file share / folder → SharePoint library, preserving structure + timestamps. Dry-run by default. |
| | `Copy-SPSite` | Copy a site's structure (lists, libraries, columns, views) and optionally its content to another site in the **same tenant**. Dry-run by default ([docs/07](docs/07-sharepoint-migration.md)). |
| | `Copy-SPPermissions` | Copy role assignments to another site, remapping users/groups via a mapping CSV or domain swap. Dry-run by default. |
| | `Copy-SPSite -CrossTenant` | Copy a site to a **different tenant** (files by download/upload, principals remapped). With `New-SPMigrationConnection` + `Copy-SPTermGroup`. |
| **Collaboration** | `Copy-SPM365Group` | Clone a Microsoft 365 Group (description + owner/member roster) |
| | `Copy-SPTeam` | Clone a Team (channels + membership) |
| | `Copy-SPPlannerPlan` | Recreate a Planner plan (buckets + tasks) on a group |
| **Reporting** | `Get-SPSiteInventory` | Tenant-wide sites + storage + last activity |
| | `Get-SPPermissionReport` | Who has access; where inheritance is broken |
| | `Get-SPSharingReport` | External users and sharing links |
| | `Get-SPPermissionsMatrix` | Per-principal access matrix — who can touch what |
| | `Get-SPOrphanedUsers` | Users with access no longer in the directory (stale access) |
| | `Set-SPSiteLifecycle` | Lock / archive (read-only) / unlock a site |
| **Provisioning** | `New-SPSiteFromTemplate` | Create a site or library from a template |
| | `Set-SPBulkMetadata` | CSV-driven bulk column updates |
| **Scheduled** | `Run-GovernanceReport.ps1` | Unattended sharing/permission CSVs on a daily/weekly task ([docs/06](docs/06-scheduled-reports.md)). |

Same engine, three ways to use it: the **GUI**, the **PowerShell** module, or the **MCP server**.

## Drive it from an AI assistant

The [MCP server](mcp-server/) lets Claude / Codex / Gemini run OpenGateSP conversationally — *"show external sharing on /sites/Marketing"*, *"preview migrating C:\Shares\HR into the HR site."* Write tools preview by default. Setup: [mcp-server/README.md](mcp-server/README.md).

## Prefer the CLI?

```powershell
Install-Module PnP.PowerShell -Scope CurrentUser
Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "OpenGateSP" -Tenant contoso.onmicrosoft.com
Import-Module ./module/OpenGateSP/OpenGateSP.psd1
Connect-SPTool -Url https://contoso.sharepoint.com -ClientId <id> -Tenant contoso.onmicrosoft.com -SaveConfig
Get-SPSharingReport -SiteUrl https://contoso.sharepoint.com/sites/Marketing
```

Full guide: [docs/03-quickstart.md](docs/03-quickstart.md) · setup: [docs/01](docs/01-prerequisites.md), [docs/02](docs/02-entra-app-registration.md), headless/scheduled: [docs/05](docs/05-app-only-auth.md).

## Safety

- **Delegated auth** — the tool can never exceed your own SharePoint permissions. **App-only certificate** auth ([docs/05](docs/05-app-only-auth.md)) for headless / scheduled runs.
- **Write operations are cautious** — migration, bulk metadata, and provisioning support `-WhatIf`/`-Confirm` and the MCP tools preview by default. **Test against a throwaway site before production.**
- No client secret in the default setup, so there's nothing secret to leak.

## Roadmap

Site-to-site copy, **permissions + identity mapping**, and **tenant-to-tenant** have shipped (Phases 1–3). Next: **Teams + Planner + M365 Groups**, deeper governance, PowerShell Gallery publish. See [docs/roadmap.md](docs/roadmap.md).

## License

[MIT](LICENSE).

---

<sub>OpenGateSP is an independent open-source project, not affiliated with or endorsed by ShareGate or Workleap. "ShareGate" is a trademark of its respective owner.</sub>
