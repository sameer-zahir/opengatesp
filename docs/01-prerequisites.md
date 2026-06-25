# 01 — Prerequisites

## 1. PowerShell 7.4+

The engine targets PowerShell 7 (cross-platform). Check:

```powershell
$PSVersionTable.PSVersion   # should be 7.4 or higher
```

Install/upgrade from <https://aka.ms/powershell> or `winget install Microsoft.PowerShell`.

> The **GUI** (coming) is Windows-only because it uses WPF. The **module/engine** runs anywhere PowerShell 7 and PnP.PowerShell run (Windows/macOS/Linux).

## 2. PnP.PowerShell

The engine is built on [PnP.PowerShell](https://pnp.github.io/powershell/):

```powershell
Install-Module PnP.PowerShell -Scope CurrentUser
```

## 3. Permission to register an Entra ID app

Since **2024-09-09**, PnP.PowerShell requires you to use **your own** Entra ID app
registration. You need either:

- the ability to register applications in your tenant (Application Developer role or
  self-service app registration enabled), **or**
- an admin who will register one for you.

See [02-entra-app-registration.md](02-entra-app-registration.md).

## 4. Roles needed per operation

| Operation | Minimum access |
|---|---|
| `Get-SPSharingReport`, `Get-SPPermissionReport` | Access to the site being reported on |
| `Get-SPSiteInventory` (tenant-wide) | **SharePoint Administrator** (connects to the admin centre) |
| `Start-SPFileMigration` | Contribute/Edit on the target library |
| `New-SPSiteFromTemplate` | Permission to create sites (or Site Collection Admin for templates) |
| `Set-SPBulkMetadata` | Edit on the target list/library |

Because auth is **delegated**, every operation is additionally bounded by what your own
account can already do — the app's permissions are a ceiling, not a grant.
