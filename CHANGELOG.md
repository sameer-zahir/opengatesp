# Changelog

All notable changes to this project are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project aims to
follow [Semantic Versioning](https://semver.org/).

## [0.5.0]

ShareGate-parity **Phase 4** — Teams, Microsoft 365 Groups, and Planner.

### Added
- **`Copy-SPM365Group`** — create a new Microsoft 365 Group modelled on an existing one
  (description + owner/member roster).
- **`Copy-SPTeam`** — create a new Team modelled on an existing one: channels (except the
  auto-created General) and the owner/member roster. Tabs/apps/messages aren't copied.
- **`Copy-SPPlannerPlan`** — recreate a Planner plan's buckets and tasks on a destination group.
- **MCP** — `sharepoint_copy_m365_group`, `sharepoint_copy_team`, `sharepoint_copy_planner_plan`.
- New doc [docs/08](docs/08-teams-groups-planner.md). All dry-run by default; need Microsoft
  Graph scopes on the app registration.

### Changed
- Pure core grows: `Get-SPMembershipDelta` (which members to add) is unit-tested (5 new Pester
  cases; 60 total, no tenant needed).

## [0.4.0]

ShareGate-parity **Phase 3** — tenant-to-tenant.

### Added
- **`New-SPMigrationConnection`** — open a PnP connection to a specific site in a specific
  tenant and return it, so a migration can hold source + destination connections to two
  different tenants at once (interactive, device-code, or app-only auth).
- **`Copy-SPSite -CrossTenant`** — copy a site between different tenants: structure via the
  provisioning template, library files by **download + re-upload** (`Copy-PnPFolder` can't
  cross tenants), items via the destination connection, and permissions remapped with the
  Phase 2 principal map. Requires `-SourceConnection`/`-DestinationConnection`.
- **`Copy-SPTermGroup`** — copy a managed-metadata term group between tenants via XML
  export/import (`Export-`/`Import-PnPTermGroup*`).
- **MCP** — `sharepoint_copy_site_cross_tenant` (app-only per tenant; the server opens both
  connections itself).

### Changed
- The same-tenant library path-mapping math is now the unit-tested pure helper
  `Resolve-SPCrossTenantUrl`, shared by both same- and cross-tenant copy (5 new Pester cases;
  55 total, no tenant needed).

## [0.3.0]

ShareGate-parity **Phase 2** — permissions, identity mapping, and incremental copy.

### Added
- **`Copy-SPPermissions`** — copy a site's role assignments (and, with `-IncludeListPermissions`,
  unique list/library permissions) to another site, remapping users and groups via a
  `-MappingCsv` (Source,Destination) and/or a `-DomainFrom`/`-DomainTo` swap. Dry-run by
  default; flags principals that can't be mapped. Same-tenant or tenant-to-tenant.
- **Incremental copy** — `-Since <date>` on `Copy-SPSite` / `Copy-SPList` copies only items
  modified at/after a watermark (timestamp-based; PnP has no native change-feed).
- **`Copy-SPSite -CopyPermissions`** — fold the permission copy into a site copy as a final step.
- **MCP** — `sharepoint_copy_permissions` tool; `sharepoint_copy_site` gains
  `copyPermissions` / `mappingCsv` / `domainFrom` / `domainTo` / `since`.
- **GUI** — a **Copy permissions** option in the Copy-site wizard.

### Changed
- Pure, unit-tested core grows: principal-key normalization, principal mapping, and
  incremental change-selection helpers (12 new Pester cases; 50 total, no tenant needed).

## [0.2.0]

### Added
- **Pre-migration readiness check** — `Test-SPMigrationReadiness` scans a local folder for
  SharePoint blockers (illegal/reserved names, blocked file types, over-long projected URLs,
  oversized and empty files), graded Error/Warning. Local and read-only — no tenant needed.
- **Scheduled governance reports** — `scripts/scheduled/Run-GovernanceReport.ps1` writes
  sharing/permission CSVs headless (app-only auth); `Register-GovernanceReportTask.ps1`
  schedules it; `Get-SPScheduledCommand` builds the command line. See [docs/06](docs/06-scheduled-reports.md).
- **SharePoint → SharePoint site copy (ShareGate-parity, Phase 1)** — `Copy-SPSite` copies a
  site's structure (lists, libraries, fields, content types, views, navigation, pages) and
  optionally its content (items, plus files with their Created/Modified/Author timestamps) to
  another site in the **same tenant**. Dry-run by default; conflict modes Replace / Skip /
  KeepBoth / IfNewer; scope with `-Lists`. Same-tenant only this release — tenant-to-tenant,
  permission/identity mapping, and version history are tracked milestones. See [docs/07](docs/07-sharepoint-migration.md).
- **MCP** — `sharepoint_precheck_migration` (pre-check) and `sharepoint_copy_site`
  (site copy, dry-run by default) tools.

### Changed
- **GUI redesigned** — a left sidebar navigation grouped into Migration / Governance, a
  card-based Home ("What do you want to do?"), a breadcrumb app bar, a numbered **Copy site**
  (source → destination → options → run) wizard, severity-coloured results, empty states, a
  busy indicator, and a provisioning template/libraries picker. Now ships with a
  **Microsoft Fluent**-style light theme by default (plus Fluent dark, Gruvbox, and Tokyo
  Night Moon) in a theme picker, WCAG-AA-tuned contrast, and fluid window scaling. Same engine
  and worker-runspace model underneath.

## [0.1.0]

### Added
- **Engine (OpenGateSP module):**
  - `Connect-SPTool` — interactive/device-code delegated connection with saved defaults.
  - `Get-SPSiteInventory` — tenant-wide sites, storage, and last-activity report.
  - `Get-SPPermissionReport` — site/library permissions and broken-inheritance report.
  - `Get-SPSharingReport` — external users and sharing links.
  - `Start-SPFileMigration` — local folder → SharePoint library, dry-run by default.
  - `New-SPSiteFromTemplate` — create a site/library from a template spec.
  - `Set-SPBulkMetadata` — CSV-driven bulk column updates.
  - Shared `-AsJson` output contract, throttling/retry, and logging.
- **GUI** — Windows WPF front end (`gui/Start-OpenGateSPGui.ps1`) with a background worker
  runspace, Connect/Reports/Migrate/Provision tabs, and CSV/HTML export.
- **MCP server** — TypeScript Model Context Protocol server (`mcp-server/`) exposing the
  engine to AI assistants via a persistent `pwsh` host; write tools preview by default.
- Entra app-registration, prerequisites, quickstart, and operations docs; runnable examples.
- **App-only certificate auth** — `Connect-SPTool -Thumbprint`/`-CertificatePath` for headless,
  unattended runs (scheduled jobs, fully headless MCP). The auth mode persists in config; the
  certificate password is read from `OPENGATESP_CERT_PASSWORD` and never saved.
- PSScriptAnalyzer + Pester + MCP-build CI.
