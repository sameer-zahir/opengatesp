# 07 — SharePoint → SharePoint migration

`Copy-SPSite` copies a site's **structure** (and optionally its **content**) to another site —
the open equivalent of ShareGate's "Copy structure and content". It's **dry-run by default**:
same-tenant by default, with **tenant-to-tenant** via `-CrossTenant` (see below).

> **Status:** the planning, conflict-resolution, and reporting logic is unit-tested; the live
> PnP copy path is verified with the manual test plan below. Run a `-WhatIf` plan first, always.

## What it copies

| Area | How | Fidelity |
|---|---|---|
| Lists, libraries, fields, content types, views, navigation, pages | PnP provisioning template (`Get-/Invoke-PnPSiteTemplate`) | Good for standard structures |
| List items | Batched `Add-PnPListItem` | Simple columns clean; lookup/user/managed-metadata values may not round-trip |
| Library files + folders | Same-tenant: `Copy-PnPFolder` + `Copy-PnPFileMetadata` (restores Created/Modified/Author). Cross-tenant: download + re-upload | Latest version only |
| Role assignments | `Copy-SPPermissions` with principal remapping | Site + unique-list grants |
| Managed-metadata terms | `Copy-SPTermGroup` (export/import XML) | Whole term group |

## Honest limits (this release)

- **Cross-tenant** works via `-CrossTenant` + two `New-SPMigrationConnection` connections (files copy by download/upload). Same-tenant uses the faster `Copy-PnPFolder`.
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

## Tenant-to-tenant (Phase 3)

Source and destination in **different tenants** (different Entra apps). Open a connection to
each with `New-SPMigrationConnection`, then pass both to `Copy-SPSite -CrossTenant`. Library
files copy by **download + re-upload** (`Copy-PnPFolder` can't cross tenants), and principals
remap via the Phase 2 mapping:

```powershell
$src = New-SPMigrationConnection -Url https://contoso.sharepoint.com/sites/A  -ClientId $contosoApp  -Tenant contoso.onmicrosoft.com
$dst = New-SPMigrationConnection -Url https://fabrikam.sharepoint.com/sites/B -ClientId $fabrikamApp -Tenant fabrikam.onmicrosoft.com

# Preview, then run: structure + content + remapped permissions across tenants:
Copy-SPSite -SourceUrl $src.Url -DestinationUrl $dst.Url -SourceConnection $src -DestinationConnection $dst `
            -CrossTenant -IncludeContent -CopyPermissions -DomainFrom contoso.com -DomainTo fabrikam.com -WhatIf

# Bring managed-metadata terms across first (so content can bind to them):
Copy-SPTermGroup -SourceConnection $src -DestinationConnection $dst -TermGroup "Corporate Taxonomy" -Force
```

**Cross-tenant caveats:** you need an Entra app registered in **each** tenant; user/lookup/
managed-metadata column *values* may not resolve across tenants (different directories/term
ids) — copy the term group first and supply a principal mapping. Headless (MCP/scheduled)
cross-tenant runs need **app-only** auth (a certificate per tenant). MCP tool:
**`sharepoint_copy_site_cross_tenant`**.

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
