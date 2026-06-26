# 07 — SharePoint → SharePoint migration

`Copy-SPSite` copies a site's **structure** (and optionally its **content**) to another site
in the **same tenant** — the open equivalent of ShareGate's "Copy structure and content". This
is **Phase 1** of a phased program (see the roadmap below); it's dry-run by default and
same-tenant only for now.

> **Status:** the planning, conflict-resolution, and reporting logic is unit-tested; the live
> PnP copy path is verified with the manual test plan below. Run a `-WhatIf` plan first, always.

## What it copies

| Area | How | Fidelity |
|---|---|---|
| Lists, libraries, fields, content types, views, navigation, pages | PnP provisioning template (`Get-/Invoke-PnPSiteTemplate`) | Good for standard structures |
| List items | Batched `Add-PnPListItem` | Simple columns clean; lookup/user/managed-metadata values are Phase 2 |
| Library files + folders | `Copy-PnPFolder` + `Copy-PnPFileMetadata` (restores Created/Modified/Author) | Latest version only |

## Honest limits (this release)

- **Same-tenant only.** Tenant-to-tenant is Phase 3 (cross-tenant needs download/upload, not `Copy-PnPFile`).
- **No version history** — latest version of each file only.
- **Managed-metadata item values, complex/3rd-party web parts** — lossy or skipped.
- **Permissions** — `Copy-SPPermissions` (or `Copy-SPSite -CopyPermissions`) copies site and unique-list role assignments and remaps users/groups via a mapping CSV or a domain swap. Deep per-file ACLs are still coarse.
- **Incremental** — `-Since <date>` copies only items modified at/after a watermark (PnP has no native change-feed, so it's timestamp-based). Pair with `-ConflictMode IfNewer` for converging re-runs.
- Out of scope entirely: Exchange/Gmail mailboxes, Google Drive, classic 2013 workflows.

## Use it

```powershell
# Always dry-run first — prints the plan, writes nothing:
Copy-SPSite -SourceUrl https://contoso.sharepoint.com/sites/Source `
            -DestinationUrl https://contoso.sharepoint.com/sites/Dest -WhatIf

# Structure only (real):
Copy-SPSite -SourceUrl .../sites/Source -DestinationUrl .../sites/Dest

# Structure + content, skipping anything newer at the destination:
Copy-SPSite -SourceUrl .../sites/Source -DestinationUrl .../sites/Dest -IncludeContent -ConflictMode IfNewer

# Just one list or library (schema scoped to that list — not the whole site):
Copy-SPList -SourceUrl .../sites/Source -DestinationUrl .../sites/Dest -List "Documents" -IncludeContent
```

`Copy-SPSite` copies the whole site's structure; `Copy-SPList` is the granular form — it extracts a
template scoped to a single list/library, so the destination gets only that list's columns, content
types, and views. Both are dry-run by default and share the same conflict modes: `Replace`, `Skip`,
`KeepBoth`, `IfNewer` (default). Limit a site copy's content scope with `-Lists "Documents","Tasks"`.

Also available as the MCP tools **`sharepoint_copy_site`** and **`sharepoint_copy_list`**
(dry-run by default; `execute=true` to run).

## Permissions & incremental (Phase 2)

Copy role assignments and remap principals — the path for tenant-to-tenant, where domains differ:

```powershell
# Preview which grants would apply (flags anything that can't be mapped):
Copy-SPPermissions -SourceUrl .../sites/A -DestinationUrl .../sites/B -IncludeListPermissions -WhatIf

# Apply, swapping every @contoso.com principal to @fabrikam.com:
Copy-SPPermissions -SourceUrl .../sites/A -DestinationUrl .../sites/B -DomainFrom contoso.com -DomainTo fabrikam.com -Force

# Explicit per-principal mapping from a CSV (columns: Source,Destination):
Copy-SPPermissions -SourceUrl .../sites/A -DestinationUrl .../sites/B -MappingCsv .\map.csv -Force

# Incremental content: only items changed at/after a watermark:
Copy-SPSite -SourceUrl .../sites/A -DestinationUrl .../sites/B -IncludeContent -Since '2026-06-01'
```

`Copy-SPSite -CopyPermissions` runs the permission copy as a final step after structure + content.
In the **same tenant**, SharePoint groups and site grants already arrive with the structure template —
so permission copy mainly adds unique list permissions and (cross-tenant) principal remapping.
Also available as the MCP tool **`sharepoint_copy_permissions`**.

## Manual test plan (run against a tenant)

Do this against a **non-production / dev tenant** (the free Microsoft 365 Developer Program tenant is ideal), not your live enterprise tenant.

1. **Set up:** `Connect-SPTool -Url <root> -ClientId <id> -Tenant <tenant> -SaveConfig` once. Create two test sites: a **Source** with a couple of lists, a document library with some files/folders, and a **Dest** (empty).
2. **Plan:** `Copy-SPSite -SourceUrl <Source> -DestinationUrl <Dest> -WhatIf`. Confirm the report lists every non-hidden list/library with the right `Action` (all `Create` into an empty dest).
3. **Structure:** run without `-WhatIf` (structure only). Open Dest — lists, libraries, columns, content types, views should be there.
4. **Content:** `Copy-SPSite ... -IncludeContent`. Confirm items landed in the lists, and files + folders in the library with their **Created/Modified/Author** preserved.
5. **Conflicts:** re-run with `-ConflictMode IfNewer` and again with `-Skip` / `-Replace`; confirm the report's actions match (skipped vs overwritten).
6. **Record** what worked and any field-fidelity gaps (lookup/managed-metadata/user columns) so they can be prioritised for Phase 2.

## Roadmap

Phase 1 (this) same-tenant copy structure + content → Phase 2 mappings/permissions/conflict modes/incremental → Phase 3 tenant-to-tenant → Phase 4 Teams + Planner → Phase 5 deeper governance. See `docs/roadmap.md`.
