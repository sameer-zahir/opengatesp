# Explore & post-migration validation

ShareGate's "Explore" is *browse + report + remediate* a SOURCE environment. OpenGateSP's
`Invoke-SPExplore` is the read-only, consolidated **pre-migration assessment** of a SharePoint
source — the SharePoint-side companion to `Test-SPMigrationReadiness` (which scans local folders).
After a copy, `Compare-SPSite` validates the result.

## Assess a source

```powershell
Connect-SPTool -Url https://contoso.sharepoint.com/sites/Marketing -ClientId <id> -Tenant contoso.onmicrosoft.com
Invoke-SPExplore -SiteUrl https://contoso.sharepoint.com/sites/Marketing
Invoke-SPExplore -SiteUrl https://contoso.sharepoint.com/sites/Marketing -IncludeVersions -AsJson
```

`Invoke-SPExplore` runs several read-only checks and returns one severity-graded table
(`Category, ItemType, Name, Severity, Detail, Count`), sorted Error → Warning → Info:

| Check | Severity | Cmdlet behind it |
|---|---|---|
| Checked-out files (a migration blocker) | Error | `Get-SPCheckedOutFiles` |
| Large files (≥ `-LargeFileMB`, default 100) | Warning | `Get-SPLargeFiles` |
| External sharing (guests + links) | Warning | `Get-SPSharingReport` |
| Orphaned users (stale access; needs Graph) | Warning | `Get-SPOrphanedUsers` |
| 2013-platform workflows (don't migrate) | Warning | `Get-SPWorkflowReport` |
| Version-history bloat (`-IncludeVersions`, slower) | Warning | `Get-SPVersionHistoryReport` → `Measure-SPVersionBloat` |

## The discovery reports (standalone)

Each check is also its own cmdlet for detail, all read-only and `-AsJson`-capable:

- `Get-SPCheckedOutFiles -SiteUrl <url> [-Library <name>]`
- `Get-SPLargeFiles -SiteUrl <url> [-MinSizeMB 100] [-Library <name>]`
- `Get-SPVersionHistoryReport -SiteUrl <url> [-MinSizeMB 25] [-Library <name>]` — per-file version
  calls; gated by size to bound cost on large libraries.
- `Get-SPContentInsights -SiteUrl <url> [-Library <name>]` — file-type breakdown (count + total MB).
- `Get-SPWorkflowReport -SiteUrl <url>` — 2013-platform workflow subscriptions (best-effort).
- `Get-SPInactiveSites -InactiveDays 180` — tenant-wide; needs `Connect-SPTool -Admin`.

## Post-migration validation

```powershell
Copy-SPSite -SourceUrl <src> -DestinationUrl <dst> -IncludeContent
Compare-SPSite -SourceUrl <src> -DestinationUrl <dst>
```

`Compare-SPSite` enumerates the non-hidden lists/libraries on each site (with item counts) and diffs
them — `Match` / `CountMismatch` / `Missing` (source-only) / `ExtraInDest` — so you can confirm a
copy landed. Same-tenant; reuses your saved connection for each side.

## MCP

`sharepoint_explore`, `sharepoint_checked_out_files`, `sharepoint_large_files`,
`sharepoint_version_report`, `sharepoint_content_insights`, `sharepoint_workflow_report`,
`sharepoint_inactive_sites`, and `sharepoint_compare_site` — all read-only.

## GUI

The **Explore** view runs the full assessment or any single report, with CSV/HTML export and a
*Remediate* bar (see [docs/11](11-remediation.md)). The Copy-site view has a **Validate copy**
action (`Compare-SPSite`).

## Manual test plan (run against a tenant)

Use a **non-production / dev tenant**; seed it with `scripts/test/Seed-TestTenant.ps1`.

1. `Invoke-SPExplore -SiteUrl <Source>` — confirm the seeded checked-out file shows as **Error**,
   the large and (with `-IncludeVersions`) multi-version files as **Warning**, plus any external
   share / orphaned users.
2. Run each discovery cmdlet standalone (use `Get-SPLargeFiles -MinSizeMB 1` against the ~3 MB seed
   file) and confirm the rows.
3. `Get-SPInactiveSites -InactiveDays 1` (admin) — the seeded sites' activity is reported.
4. After a `Copy-SPSite ... -IncludeContent`, run `Compare-SPSite` and confirm every list is
   `Match` (counts equal).
