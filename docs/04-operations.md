# 04 — Operations reference

Every function returns rich objects and supports `-AsJson`. Write operations support
`-WhatIf`/`-Confirm`. For full detail on any function, run `Get-Help <Name> -Full`.

## Connect-SPTool
Connect to SharePoint Online (interactive delegated auth). Saves defaults with `-SaveConfig`.
```powershell
Connect-SPTool -Url https://contoso.sharepoint.com -ClientId <id> -Tenant contoso.onmicrosoft.com -SaveConfig
Connect-SPTool -Admin        # admin centre, for tenant-wide reports
```

## Migration

### Test-SPMigrationReadiness
Pre-flight a local folder before you migrate — a local, read-only scan that flags what SharePoint will reject or skip (illegal/reserved names, blocked file types, over-long projected URLs, oversized and empty files), graded **Error**/**Warning**. No connection needed.
```powershell
Test-SPMigrationReadiness -Source C:\Shares\Mktg
Test-SPMigrationReadiness -Source C:\Shares\Mktg -SiteUrl https://contoso.sharepoint.com/sites/Mktg -Library Documents
```
Key params: `-SiteUrl`, `-Library`, `-TargetFolder`, `-MaxPathLength` (default 400), `-MaxFileSizeMB`, `-BlockedExtension`.

### Start-SPFileMigration
Local folder → SharePoint library, mirroring the folder tree. Skips existing files (resume-friendly) unless `-Overwrite`. **Dry-run with `-WhatIf` first.**
```powershell
Start-SPFileMigration -Source C:\Shares\Mktg -SiteUrl https://contoso.sharepoint.com/sites/Mktg -Library Documents -WhatIf
Start-SPFileMigration -Source C:\Shares\Mktg -SiteUrl https://contoso.sharepoint.com/sites/Mktg -PreserveTimestamps
```
Key params: `-TargetFolder`, `-PreserveTimestamps`, `-Overwrite`, `-ExcludeExtension`, `-Force`, `-LogPath`.

## Reporting / governance

### Get-SPSiteInventory
Tenant-wide sites + storage + last activity. Needs `Connect-SPTool -Admin`.
```powershell
Get-SPSiteInventory -IncludeStorage | Sort-Object StorageUsedMB -Descending
```

### Get-SPPermissionReport
Who has access, with SharePoint groups expanded to members; `-IncludeListPermissions` adds broken-inheritance lists.
```powershell
Get-SPPermissionReport -SiteUrl https://contoso.sharepoint.com/sites/Mktg -IncludeListPermissions
```

### Get-SPSharingReport
External/guest users; `-IncludeLinks` also scans a library's items for sharing links.
```powershell
Get-SPSharingReport -SiteUrl https://contoso.sharepoint.com/sites/Mktg -IncludeLinks
```

## Provisioning / bulk

### New-SPSiteFromTemplate
Create a Team or Communication site; optionally apply a PnP template and create libraries.
```powershell
New-SPSiteFromTemplate -Title "Project Apollo" -Alias project-apollo -Type TeamSite -Libraries 'Specs','Designs'
```

### Set-SPBulkMetadata
CSV-driven bulk column updates. Header = field internal names; one column is the item id.
```powershell
Set-SPBulkMetadata -SiteUrl https://contoso.sharepoint.com/sites/Mktg -List Documents -CsvPath ./updates.csv -WhatIf
```

## Scheduled reports

Run sharing/permission reports unattended (app-only auth) on a daily or weekly Windows task — see [06 — Scheduled reports](06-scheduled-reports.md) for the full setup.
```powershell
./scripts/scheduled/Register-GovernanceReportTask.ps1 -SiteUrl https://contoso.sharepoint.com/sites/Mktg -Frequency Weekly -At 06:30 -WhatIf
```
