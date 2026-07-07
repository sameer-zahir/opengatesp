# 03 — Quickstart

End-to-end, from zero to a report and a dry-run migration.

## 0. Install

**Just want the app?** Grab **`OpenGateSP-Setup.exe`** from the
[latest release](https://github.com/sameer-zahir/opengatesp/releases/latest) (or the portable
zip) — it offers to install PowerShell 7 if needed and walks you through first-run setup. You can
skip the rest of this page; the app guides you.

**For the CLI / scripting** (this guide):

```powershell
Install-Module PnP.PowerShell -Scope CurrentUser
git clone https://github.com/sameer-zahir/opengatesp.git
cd opengatesp
```

## 1. Register your Entra app (one time)

See [02-entra-app-registration.md](02-entra-app-registration.md):

```powershell
Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "OpenGateSP" -Tenant contoso.onmicrosoft.com
# → copy the ClientId it prints
```

## 2. Import and connect

```powershell
Import-Module ./module/OpenGateSP/OpenGateSP.psd1
Connect-SPTool -Url https://contoso.sharepoint.com -ClientId <clientId> -Tenant contoso.onmicrosoft.com -SaveConfig
```

After `-SaveConfig`, later sessions are just `Connect-SPTool`.

### Environments — work with more than one tenant

An **environment** is a saved, named tenant connection (the ShareGate "Connect to your
environments" idea). Connecting to one saves it and makes it active; everything you run
afterwards targets the active environment:

```powershell
# Save each tenant once (the browser signs you in — SSO picks up your session):
Connect-SPTool -Environment "Contoso"  -Url https://contoso.sharepoint.com  -ClientId <id> -Tenant contoso.onmicrosoft.com
Connect-SPTool -Environment "Fabrikam" -Url https://fabrikam.sharepoint.com -ClientId <id> -Tenant fabrikam.onmicrosoft.com

# From then on, switching is one argument:
Connect-SPTool -Environment Contoso
Get-SPEnvironment            # list them; the active one is flagged
Remove-SPEnvironment -Name Fabrikam -WhatIf

# Cross-tenant copies read one line per side:
$src = New-SPMigrationConnection -Environment Contoso  -Url https://contoso.sharepoint.com/sites/A
$dst = New-SPMigrationConnection -Environment Fabrikam -Url https://fabrikam.sharepoint.com/sites/B
```

**Stay signed in (opt-in):** add `-PersistLogin` and the sign-in survives new sessions and
reboots — sign in once, silent afterwards. Turn it off with `-PersistLogin:$false`, and sign
out fully with `Disconnect-SPTool -ClearPersistedLogin`. Note the token cache is per app
registration, so clearing it signs out every environment that shares the app.

**Windows sign-in (optional):** `-OSLogin` uses Windows Hello / your Windows account instead
of a browser — after a one-time app change ([docs/02](02-entra-app-registration.md#optional--windows-native-sign-in-no-browser));
without it, OpenGateSP falls back to the browser automatically.

The GUI's **Environments** page is the same feature with buttons.

## 3. Migration (always dry-run first)

```powershell
# Preview — lists what WOULD be uploaded, changes nothing
Start-SPFileMigration -Source "C:\Shares\Marketing" `
    -SiteUrl https://contoso.sharepoint.com/sites/Marketing `
    -Library "Documents" -WhatIf

# Real run against a TEST site first
Start-SPFileMigration -Source "C:\Shares\Marketing" `
    -SiteUrl https://contoso.sharepoint.com/sites/TestMigration `
    -Library "Documents" -PreserveTimestamps
```

## 4. Reporting (read-only, safe)

```powershell
# External sharing on a site
Get-SPSharingReport -SiteUrl https://contoso.sharepoint.com/sites/Marketing

# Who has access + where inheritance is broken
Get-SPPermissionReport -SiteUrl https://contoso.sharepoint.com/sites/Marketing -IncludeListPermissions

# Tenant-wide inventory (needs SharePoint Admin; connect with -Admin)
Connect-SPTool -Admin
Get-SPSiteInventory -IncludeStorage | Format-Table Url, StorageUsedMB, LastActivity

# Structured output for piping / the future MCP layer
Get-SPSharingReport -SiteUrl https://contoso.sharepoint.com/sites/Marketing -AsJson
```

Export anything to CSV/HTML:

```powershell
Get-SPPermissionReport -SiteUrl https://.../sites/Marketing |
    Export-Csv ./reports/marketing-perms.csv -NoTypeInformation
```

## 5. Provisioning & bulk edits

```powershell
# Create a site/library from a template spec
New-SPSiteFromTemplate -Title "Project Apollo" -Alias "project-apollo" -Type TeamSite -WhatIf

# Bulk metadata from a CSV (preview, then apply)
Set-SPBulkMetadata -SiteUrl https://.../sites/Marketing -List "Documents" -CsvPath ./updates.csv -IdColumn ID -WhatIf
```

## 6. Or use the GUI

```powershell
pwsh -STA -File ./gui/Start-OpenGateSPGui.ps1
```

> **Golden rule:** run write operations with `-WhatIf` first, and never point them at
> production before a throwaway test site has worked end to end.
