# Roadmap

OpenGateSP v0.2.0 adds a pre-migration readiness check, scheduled governance reports, and a
redesigned GUI (sidebar navigation + card home), on top of the engine (PowerShell module), the
MCP server, and app-only certificate auth (headless/unattended). What's next, roughly in
priority order:

## SharePoint → SharePoint migration (the big build, phased)
The path toward ShareGate-style site migration, grounded in what PnP PowerShell actually supports. Each phase ships independently.
- **Phase 1 — same-tenant copy structure + content (shipped, 0.2.0):** `Copy-SPSite` / `Copy-SPList` copy a site's lists, libraries, fields, content types, views, navigation, pages, items, and files (with timestamps) to another site in the same tenant. Dry-run by default, with a GUI Copy-site wizard. See [docs/07](07-sharepoint-migration.md).
- **Phase 2 — mappings, permissions, incremental (shipped, 0.3.0):** `Copy-SPPermissions` copies role assignments and remaps users/groups (mapping CSV or domain swap); `-CopyPermissions` folds it into a site copy; `-Since` makes content copy incremental. Conflict modes (Replace/Skip/KeepBoth/IfNewer) shipped in Phase 1.
- **Phase 3 — tenant-to-tenant (shipped, 0.4.0):** `New-SPMigrationConnection` opens a connection per tenant; `Copy-SPSite -CrossTenant` copies structure + content across tenants (library files by download/upload) with principal remapping; `Copy-SPTermGroup` moves managed-metadata terms.
- **Phase 4 — Teams + Planner + M365 Groups (shipped, 0.5.0):** `Copy-SPM365Group`, `Copy-SPTeam` (channels + membership), and `Copy-SPPlannerPlan` (buckets + tasks). Dry-run by default; need Graph scopes. See [docs/08](08-teams-groups-planner.md).
- **Phase 5 — deeper governance (shipped, 0.6.0):** `Get-SPPermissionsMatrix` (who-can-touch-what), `Get-SPOrphanedUsers` (stale access), `Set-SPSiteLifecycle` (lock / archive / unlock). See [docs/09](09-governance.md).
- **Phase 6 — Explore + validation (shipped, 0.7.0):** `Invoke-SPExplore` source assessment + discovery reports (checked-out, large files, version bloat, inactive sites, workflows, content insights); `Compare-SPSite` post-migration validation. See [docs/10](10-explore.md) and [docs/TESTING.md](TESTING.md).
- **Phase 7 — remediation + fidelity (shipped, 0.8.0):** remediation quick-actions (`Invoke-SPCheckIn`, `Clear-SPVersionHistory`, `Restore-SPInheritance`, `Remove-SPOrphanedUsers`); Person/Managed-Metadata column round-tripping and best-effort `-IncludeVersions` version history. See [docs/11](11-remediation.md).
- Maybe later: **Box** import.

## Also planned
- **Full per-version history fidelity** via the SharePoint Migration API (today's `-IncludeVersions` is best-effort — content/order preserved, per-version author/date are not).
- **ShareGate-Protect-style governance automation** — EEEU / public-group detection, ownerless-group and inactive-workspace cleanup policies, access-review campaigns.
- **More provisioning templates**; **PowerShell Gallery** (`Install-Module OpenGateSP`).

## Out of scope
- Exchange/Gmail **mailboxes**, **Google Drive** import, classic **2013 workflows** — different APIs or deprecated.
- A hosted SaaS or paid tier. OpenGateSP stays a tool you run against your own tenant; the durable edge is free + open + scriptable + AI-driven.

Contributions welcome — open an issue describing the operation you need.
