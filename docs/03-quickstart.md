# 03 — Quickstart

End-to-end, from zero to a report and a dry-run migration.

## 0. Install

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
