# Remediation quick-actions

The Explore reports tell you what's wrong; these cmdlets fix it. Every one is **dry-run by
default** (`ConfirmImpact = 'High'`): it reports what it *would* do and writes nothing until you
pass `-Force` (or answer the confirmation prompt). All respect `-WhatIf`. Run the matching Explore
report first, then preview, then apply against a **throwaway site**.

| Cmdlet | Fixes (Explore report) | Engine |
|---|---|---|
| `Invoke-SPCheckIn` | Checked-out files (`Get-SPCheckedOutFiles`) | `Set-PnPFileCheckedIn` (major check-in) |
| `Clear-SPVersionHistory` | Version-history bloat (`Get-SPVersionHistoryReport`) | `Get-`/`Remove-PnPFileVersion`, keeping newest `-Keep` |
| `Restore-SPInheritance` | Broken inheritance (`Get-SPPermissionReport`) | list `ResetRoleInheritance()` / `Set-PnPListItemPermission -InheritPermissions` |
| `Remove-SPOrphanedUsers` | Stale access (`Get-SPOrphanedUsers`) | `Remove-PnPUser` |

## Examples

```powershell
# Preview, then apply, bulk check-in across a site
Invoke-SPCheckIn -SiteUrl https://contoso.sharepoint.com/sites/Marketing -WhatIf
Invoke-SPCheckIn -SiteUrl https://contoso.sharepoint.com/sites/Marketing -Force

# Trim a heavy file to its 5 newest historical versions
Clear-SPVersionHistory -SiteUrl https://contoso.sharepoint.com/sites/Marketing `
  -FileUrl '/sites/Marketing/Shared Documents/big.pptx' -Keep 5 -WhatIf

# Restore inheritance on a library, or one item
Restore-SPInheritance -SiteUrl https://contoso.sharepoint.com/sites/Marketing -List 'Documents' -Force
Restore-SPInheritance -SiteUrl https://contoso.sharepoint.com/sites/Marketing -List 'Documents' -ItemId 42 -Force

# Remove users who no longer exist in the directory (needs Graph User.Read.All)
Remove-SPOrphanedUsers -SiteUrl https://contoso.sharepoint.com/sites/Marketing -WhatIf
```

The decision of which versions to drop is the pure, unit-tested `Select-SPVersionsToTrim`
(`tests/Remediation.Tests.ps1`).

## MCP

`sharepoint_check_in_files`, `sharepoint_clear_version_history`, `sharepoint_restore_inheritance`,
`sharepoint_remove_orphaned_users` — all preview by default; pass `execute=true` to apply.

## GUI

The **Explore** view has a *Remediate* bar (check-in all / remove orphaned users) with
**Preview (WhatIf)** and **Apply** (Apply asks for confirmation before it writes).

## Manual test plan (run against a tenant)

Use a **non-production / dev tenant**. Seed it with `scripts/test/Seed-TestTenant.ps1` (it creates
a checked-out file, a multi-version file, a broken-inheritance list).

1. `Get-SPCheckedOutFiles` shows the seeded checked-out file → `Invoke-SPCheckIn -WhatIf` lists it
   → `-Force` checks it in → re-run the report: gone.
2. `Get-SPVersionHistoryReport` shows the multi-version file → `Clear-SPVersionHistory -Keep 2 -WhatIf`
   lists the versions it would drop → `-Force` → confirm only 2 historical versions remain.
3. `Restore-SPInheritance -List <broken list> -WhatIf` then `-Force` → `Get-SPPermissionReport`
   shows the list now inherits.
4. `Remove-SPOrphanedUsers -WhatIf` then `-Force` (if you have a seeded orphan) → re-run
   `Get-SPOrphanedUsers`: cleared.
