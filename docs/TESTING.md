# Testing OpenGateSP

Two layers: **unit tests** (no tenant, run in CI) and a **manual end-to-end pass** against a
throwaway tenant. The golden rule for every write operation: **run `-WhatIf` first**, on a
**free [Microsoft 365 Developer Program](https://developer.microsoft.com/microsoft-365/dev-program)
tenant** — never production.

## 1. Unit tests (no tenant)

```powershell
Invoke-Pester ./tests            # all pure Private/ helpers
Invoke-ScriptAnalyzer ./module,./gui,./scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
npm --prefix mcp-server run build  # MCP TypeScript compiles
```

These cover the decision logic (conflict modes, principal mapping, incremental selection, explore
grading, inactive-site selection, version-bloat, structure diff, version-trim, field-value
resolution). They do **not** touch PnP.PowerShell.

## 2. Seed a dev tenant

```powershell
Connect-SPTool -Url https://contoso-admin.sharepoint.com -ClientId <id> -Tenant contoso.onmicrosoft.com -Admin -SaveConfig
./scripts/test/Seed-TestTenant.ps1 -BaseUrl https://contoso.sharepoint.com -WhatIf   # preview
./scripts/test/Seed-TestTenant.ps1 -BaseUrl https://contoso.sharepoint.com           # create
```

It creates a **Source** site (lists, a library with nested folders + files, a multi-version file, a
checked-out file, a larger file, a Person column with values, a broken-inheritance list) and an
empty **Dest** site — the fixtures the matrix below exercises. Idempotent; re-running skips what
exists.

## 3. End-to-end matrix (run against the seeded tenant)

| Area | Cmdlet(s) | Check |
|---|---|---|
| Pre-check (local) | `Test-SPMigrationReadiness` | Flags bad names / long paths / big files in a local folder |
| **Explore** | `Invoke-SPExplore`, `Get-SPCheckedOutFiles`, `Get-SPLargeFiles` (`-MinSizeMB 1`), `Get-SPVersionHistoryReport`, `Get-SPContentInsights`, `Get-SPInactiveSites`, `Get-SPWorkflowReport` | Surface the seeded checked-out / large / multi-version files, graded Error/Warning |
| Copy (same-tenant) | `Copy-SPSite`, `Copy-SPList` | Structure then `-IncludeContent`; conflict modes Replace/Skip/KeepBoth/IfNewer |
| **Fidelity** | `Copy-SPList -IncludeContent` | Person + managed-metadata column values land on the destination; `-IncludeVersions` rebuilds history (experimental) |
| **Validate** | `Compare-SPSite` | After a copy, reports Match / CountMismatch / Missing |
| Permissions | `Copy-SPPermissions`, `Get-SPPermissionReport`, `Get-SPPermissionsMatrix` | Role assignments copy + remap; matrix pivots access |
| Governance | `Get-SPSharingReport`, `Get-SPOrphanedUsers`, `Set-SPSiteLifecycle` | External users / stale access; lock / archive / unlock |
| **Remediation** | `Invoke-SPCheckIn`, `Clear-SPVersionHistory`, `Restore-SPInheritance`, `Remove-SPOrphanedUsers` | `-WhatIf` then `-Force`; re-run the matching report to confirm it cleared |
| Cross-tenant | `New-SPMigrationConnection`, `Copy-SPSite -CrossTenant`, `Copy-SPTermGroup` | App-only cert per tenant; structure + files + principals |
| Collaboration | `Copy-SPM365Group`, `Copy-SPTeam`, `Copy-SPPlannerPlan` | Group/Team/Plan cloned (dry-run first; needs Graph scopes) |
| Provisioning | `New-SPSiteFromTemplate`, `Set-SPBulkMetadata` | Site created; CSV metadata applied |
| Scheduled | `Run-GovernanceReport.ps1` | Headless app-only run drops CSVs |

Per-feature step-by-step plans live in the feature docs:
[migration](07-sharepoint-migration.md), [Teams/Groups/Planner](08-teams-groups-planner.md),
[governance](09-governance.md), [remediation](11-remediation.md).

## 4. Surfaces

Test each feature through all three surfaces where it's exposed:
- **PowerShell** — `Import-Module ./module/OpenGateSP/OpenGateSP.psd1`, call the cmdlet.
- **MCP** — `npm --prefix mcp-server start`, drive the `sharepoint_*` tools from an AI client (write tools preview unless `execute=true`).
- **GUI** — `./gui/Start-OpenGateSPGui.ps1`; every nav view runs its cmdlet and renders/export results.

## 5. Runtime checks to confirm on a dev tenant (PnP behaviour)

Static introspection confirmed every PnP cmdlet/parameter OpenGateSP uses exists in PnP.PowerShell
3.2.0. These few behaviours can only be confirmed at runtime — verify them once on the seeded tenant:

- **Field fidelity — People & Managed-Metadata** (`Copy-SPListItems` → `Resolve-SPFieldValue`):
  confirm a copied item's **Person** field resolves from the email/login string, and a
  **Managed-Metadata** field round-trips from the `"Label|TermGuid"` string passed to
  `Add-PnPListItem -Values`. **If taxonomy doesn't take that string form**, the confirmed fix is a
  post-add pass with `Set-PnPTaxonomyFieldValue -ListItem <item> -InternalFieldName <field> -TermId <guid>`
  (the cmdlet is present in 3.2.0) — wire it into `Copy-SPListItems` once a tenant shows it's needed.
- **Version history** (`Copy-SPFileVersions`, `-IncludeVersions`): confirm `Get-PnPFileVersion -Url`
  returns objects with `.Url`/`.Size`/`.ID`, and that downloading each version's `.Url` and
  re-uploading rebuilds the chain (content/order preserved; per-version author/date are not).
- **Checked-out detection** (`Get-SPCheckedOutFiles`): confirm `FieldValues['CheckoutUser'].LookupValue`
  yields the holder on the seeded checked-out file.
- **Workflows** (`Get-SPWorkflowReport`): `Get-PnPWorkflowSubscription` is absent in 3.2.0 — confirm
  the cmdlet's guard returns empty + a warning (no error).

## 6. v0.10.0 GUI / install smoke checks

- **First run:** delete `%APPDATA%\OpenGateSP\spconfig.json`, launch → the **Welcome** onboarding
  modal appears (Copy command, paste Client ID + tenant, Save) → main window opens, Connect prefilled.
- **Polish:** nav icons render; the app-bar **cog** opens **Settings**; the connection pill opens
  Settings; a **toast** fires on a copy/remediation; **`?`** shows the shortcuts overlay; **Tab**
  shows a focus ring; **Check for updates** in Settings reports latest/newer.
- **Install:** `installer\Build-Installer.ps1` → run `OpenGateSP-Setup.exe` on a clean VM → PS7
  *offer* if missing → app launches → onboarding. `winget validate installer\winget\`.
