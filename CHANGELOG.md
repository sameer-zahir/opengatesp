# Changelog

All notable changes to this project are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project aims to
follow [Semantic Versioning](https://semver.org/).

## [0.14.0]

The identity release: **Copy identities (Entra tenant-to-tenant)** — cross-tenant identity
copy for Entra ID users and groups — plus saved **environments** with browser-SSO,
stay-signed-in, and Windows-native sign-in. Also folds in the planned 0.13 migration
correctness wave, so failures can no longer report as Success.

### Added
- **Copy identities** — a four-step, review-first pipeline: `Get-SPIdentityInventory`
  (users/guests/security/M365 groups + rosters; Exchange-only group types flagged
  unsupported), `New-SPIdentityMap` (matches existing destination identities — mail first,
  then UPN local part — and proposes the rest; emits a **hand-editable mapping CSV**),
  `Test-SPIdentityMap` (UPN/nickname collisions, unverified domains, vanished matches;
  fail-closed), and `Copy-SPIdentity` (dry-run by default; users created **disabled** with
  crypto-random throwaway passwords — **passwords, MFA, and licenses never migrate, by
  design**; guests by invitation; convergent group-roster sync; emits a `Source,Destination`
  principal map for `Copy-SPPermissions -MappingCsv`). Four `sharepoint_identity_*` MCP
  tools behind the server-side preview-first gate. CLI + MCP only. See docs/14.
- **Environments** — save each tenant as a named profile: `Connect-SPTool -Environment`,
  `Get-SPEnvironment`, `Remove-SPEnvironment`, `Disconnect-SPTool`, and
  `New-SPMigrationConnection -Environment` (one line per side for cross-tenant). The GUI
  Connect view becomes a saved-tenant **Environments manager** with one-click switching
  and the app's first **Sign out**. Read-only `sharepoint_environments` MCP tool. See docs/03.
- **Sign-in upgrades** — `-OSLogin` (Windows Hello / WAM broker, no browser; automatic
  browser fallback when the app registration lacks the broker redirect URI — docs/02);
  opt-in `-PersistLogin` (stay signed in across restarts; clear with
  `Disconnect-SPTool -ClearPersistedLogin`); the device-code prompt now appears in a GUI
  dialog (code + copy + open-page) instead of vanishing into a background stream.

### Fixed
- **Migration correctness wave** (the planned 0.13): batch item failures are classified from
  real `Invoke-PnPBatch` results instead of counting as copied on queue; cross-site metadata
  restore passes `-TargetConnection` (was a silent no-op across site collections) and
  downgrades to Warning on failure; `-Since` is normalized to UTC and now honored for
  library files; hidden files migrate and reparse points are reported as skipped instead of
  followed or omitted; throttling retries honor `Retry-After` and detect by HTTP status
  (robust to localized messages); version-history copy degrades loudly ("current version
  only") instead of silently.
- Saved delegated sign-in flavors are reused on silent reconnects — device-code users were
  being switched to browser auth on every reconnect.
- GUI onboarding no longer overwrites `spconfig.json` (it dropped `AuthMode`/`Thumbprint`).
- The Environments form no longer clips its sign-in checkboxes at default window width.

### Changed
- **Requires PnP.PowerShell 2.12.0 or later** (enforced by the module manifest) — the
  release that added the persisted sign-in cache.
- Note: the PnP token cache is per app registration, so `-ClearPersistedLogin` signs out
  every environment sharing that app.
- README: Fluent Light screenshots (incl. the new Environments page); identity copy and
  environments move to checkmarks in the feature comparison.
- CI: a failed winget submission no longer fails the release job (the GitHub release is
  already published by then).

## [0.12.0]

### Security
- **`-Force` no longer bypasses `-WhatIf`.** In all 12 write cmdlets the `-Force` fast-path
  skipped `ShouldProcess` entirely, so `-Force -WhatIf` (or a session-wide
  `$WhatIfPreference = $true`) performed the real write while claiming a dry run. `-Force` now
  only suppresses the confirmation prompt; `-WhatIf` always wins.
- **Orphaned-user detection fails closed.** If the Entra directory snapshot came back empty
  (most commonly a missing Microsoft Graph `User.Read.All` grant), every site user was flagged
  as orphaned — and `Remove-SPOrphanedUsers -Force` would have deleted them all.
  `Get-SPOrphanedUsers` now throws instead of proceeding with an empty directory.
- **App / ACS / system principals are never flagged as orphaned.** Only Entra membership claims
  and bare UPNs/emails are orphan candidates; `app@sharepoint`, ACS add-in and other
  non-directory principals are skipped, so cleanup can no longer strip valid app grants
  (Flow connections, add-ins).
- **AI reply-gate hardened.** An armed write approval is now single-use (consumed on apply — no
  replay) and expires after one turn (a key previewed in turn N is honored only in turn N+1),
  and only a real boolean `execute` applies — the string `"false"` no longer counts as true.
- **AI writes now require a click, not a reply.** Every write preview card has an **Apply**
  button, and clicking it is the *only* thing that approves the change (one click approves and
  applies). A chat reply can no longer arm a write, which closes the remaining injection window
  where a preview armed in one turn could be fired by whatever message came next.
- **MCP writes are preview-gated server-side.** `execute:true` is honored only after the
  identical call was previewed in the same session; otherwise it runs as another preview and the
  result says so. Approvals are single-use. An MCP client set to auto-approve tools can no longer
  one-shot a write.

### Fixed
- Regression tests for all of the above (`tests/Guardrails.Tests.ps1` plus new governance and
  AI-gate cases).

## [0.11.1]

### Fixed
- **Silent / winget installs no longer stall on a dialog.** The installer's "PowerShell 7 not
  detected" advisory was shown even under `/VERYSILENT` (Inno Setup's `MsgBox` ignores silent
  mode), so unattended installs — including winget's validation pipeline — hung waiting for a
  click on machines without PowerShell 7. Silent installs now skip the advisory entirely; with
  `/SUPPRESSMSGBOXES` it auto-answers "No" instead of opening a browser.

### Security
- **AI write actions: the apply step is now reply-gated.** A write's `execute` call is only
  honored in a turn *after* its preview — the model can no longer preview and apply within one
  message, so a prompt-injected assistant cannot change anything without you seeing the preview
  and replying. (Previously the confirm step was prompt guidance only.)
- **AI tool arguments are schema-filtered.** Only arguments a tool's schema declares reach the
  cmdlet; a model-supplied `force` / `confirm` / `whatIf` can no longer slip past the dry-run
  guard and turn a preview into a real write. The MCP server was already safe — zod strips
  undeclared keys.
- New [SECURITY.md](SECURITY.md) (private vulnerability reporting via the repo's Security tab).

## [0.11.0]

The BYOK in-app AI assistant, governance detection (oversharing & ownership risk), and a dashboard Home.

### Added
- **In-app AI assistant (bring your own model)** — chat with *your own* Claude / OpenAI key or a local
  **Ollama / LM Studio** (no key; nothing leaves your machine). The assistant runs the same engine
  tools the GUI uses, shows the exact PowerShell it ran (copyable), and streams progress as step
  cards. Keys are encrypted **on-device with Windows DPAPI** — never plaintext, never bundled.
  Guide: [docs/13-ai-assistant.md](docs/13-ai-assistant.md).
- **AI write actions, preview-first** — the "Allow write actions" toggle now works: off (default)
  keeps the assistant strictly read-only; on, it adds write tools (migrate files, provision, bulk
  metadata, check-in, trim versions, restore inheritance, remove orphaned users, site lifecycle)
  that **always run as a preview first** — `execute` only takes effect after an identical preview
  ran and you confirmed in chat (the wizard's Run-locked-until-Preview rule, enforced in code).
- **Governance detection** — `Find-SPEveryoneClaims` (where "Everyone"/"Everyone
  except external users" has access — the biggest oversharing risk, graded Error/Warning),
  `Get-SPOwnerlessGroups` (Microsoft 365 Groups with no owner), and `Invoke-SPGovernanceReview`
  (broad-audience grants + external sharing + orphaned access in one severity-graded list). All
  three ship in the GUI Reports view, the AI assistant, and as MCP tools
  ([docs/09-governance.md](docs/09-governance.md)).
- **Dashboard Home** — live KPI tiles and recent activity; activity now **persists across
  restarts**.
- **`sharepoint_copy_term_group` MCP tool** — cross-tenant managed-metadata term-group copy
  (`Copy-SPTermGroup` was previously module-only), using the same per-tenant app-only connections
  as the cross-tenant site copy.
- Tests: AI write-gating/preview-first enforcement, MCP surface parity (every exported cmdlet
  reachable over MCP; in-app AI tools ⊆ MCP tools), and version-copy sync guards.

### Changed
- The two Copy UIs converged into the **single guided Copy wizard**; the old separate Copy-site
  view was removed (its actions live on in the wizard).
- **Accessibility** — screen-reader names on icon-only buttons and key inputs.
- Default AI models refreshed (`claude-sonnet-5`, `gpt-5.5`); assistant responses get more
  output-token headroom.
- CI lint now also covers `tools/` and `installer/`; `tsx` 4.22.4 → 4.23.0.

## [0.10.0]

A polished, human GUI and the groundwork for a seamless install. No engine cmdlet changes.

### Added
- **Navigation icons + app identity** — Segoe MDL2 glyphs on every nav item, a brand mark, and a window icon.
- **Settings** — an app-bar cog opens a Settings view (theme, connection summary, logs folder,
  about, and **Check for updates**); the connection pill opens it too.
- **First-run onboarding** — a guided, in-app Entra app-registration dialog the first time you launch
  (replaces the old console hints).
- **Toasts** for operation results (copy, remediation), **keyboard shortcuts** (`?` help overlay,
  `Esc`, `Ctrl+,` → Settings), **in-context tooltips**, warmer empty states, and a 2px keyboard
  **focus ring** (accessibility).
- **Installable-app groundwork** — the installer now *offers* to install PowerShell 7; a CI
  release-on-tag job builds + publishes the installer and portable zip and stamps the winget hash;
  winget manifests bumped and SignPath OSS signing prepped (see [docs/distribution.md](docs/distribution.md)).
- Docs: [docs/design-system.md](docs/design-system.md) extended (nav icons, toast, focus ring,
  Settings); [docs/TESTING.md](docs/TESTING.md) gains tenant-runtime + GUI smoke checks.

### Changed
- The theme picker moved into **Settings**; the app bar is now brand · breadcrumb · connection · cog.
- The **PnP API surface was audited** against PnP.PowerShell 3.2.0 — every cmdlet/parameter the
  engine uses is correct (only `Get-PnPWorkflowSubscription` is absent in 3.2.0, already guarded).

## [0.9.0]

GUI redesign — lifecycle-grouped navigation and a guided Copy wizard. No engine cmdlet changes.

### Added
- **Guided Copy flow** — a "What would you like to copy?" **chooser** (SharePoint / Collaboration /
  Import external, with plain-language "what's copied" cards) that opens a **breadcrumb wizard**:
  Source → Destination → Scope → Options → Preview & run. `Next` is disabled until each step is
  valid; **`Run` is locked until you Preview** the current settings (preview-before-write); the Scope
  step uses `Compare-SPSite` to show source-vs-destination lists in one grid. A new **Tasks** view
  lists what's run this session with its result.
- **`docs/design-system.md`** — the reusable design reference (color tokens, type scale, components,
  navigation IA + rationale, the wizard pattern, and human-interface principles + do/don'ts) so the
  GUI can be extended consistently.

### Changed
- **Left navigation** regrouped by the migration lifecycle — Home (top); **Migration** (Explore, Copy,
  Pre-check, Security); **Activity** (Tasks, Scheduled); **Governance** (Provisioning); Connect pinned
  at the bottom. The old Migrate / Copy-site / Teams-&-Groups nav entries fold into the single
  **Copy** chooser (those forms are still reached through it).

## [0.8.0]

Remediation quick-actions and migration fidelity.

### Added
- **Remediation** (dry-run by default, `ConfirmImpact='High'`): **`Invoke-SPCheckIn`** (bulk
  check-in), **`Clear-SPVersionHistory`** (trim to the newest N versions), **`Restore-SPInheritance`**
  (reset broken inheritance on a list/item), **`Remove-SPOrphanedUsers`** (stale-access cleanup).
  MCP tools (preview unless `execute=true`) and a **Remediate** bar in the Explore GUI view. New
  doc [docs/11](docs/11-remediation.md).
- **`-IncludeVersions`** on `Copy-SPSite` / `Copy-SPList` — rebuild library file version history
  (`Copy-SPFileVersions`; same-tenant, **experimental / best-effort** — per-version author/date are
  not preserved; exact fidelity needs the SharePoint Migration API). Surfaced in the MCP copy tools
  and the GUI Copy-site wizard.
- **GUI Collaboration view** — clone Microsoft 365 Groups, Teams, and Planner plans (the Phase 4
  cmdlets, previously CLI/MCP-only).

### Changed
- **Field fidelity** — `Copy-SPListItems` maps Person/User and Managed-Metadata values to a portable
  form via the unit-tested **`Resolve-SPFieldValue`**, so they round-trip same-tenant (taxonomy needs
  the term group copied first; lookup values and per-item authors are still not preserved).
- Pure core grows: `Resolve-SPFieldValue` and `Select-SPVersionsToTrim` are unit-tested
  (**97 Pester cases total**, no tenant needed).

## [0.7.0]

Source **Explore** (pre-migration discovery) and post-migration validation.

### Added
- **`Invoke-SPExplore`** — a read-only, consolidated assessment of a SharePoint **source** site
  (checked-out files, large files, external sharing, orphaned users, 2013 workflows), graded
  Error/Warning — the SharePoint-side companion to `Test-SPMigrationReadiness` (which scans local
  folders).
- **Discovery reports** — `Get-SPCheckedOutFiles`, `Get-SPLargeFiles`, `Get-SPVersionHistoryReport`,
  `Get-SPInactiveSites`, `Get-SPWorkflowReport`, `Get-SPContentInsights` (standalone, and reused
  inside `Invoke-SPExplore`).
- **`Compare-SPSite`** — post-migration validation: diffs destination vs source (lists, item/file
  counts) → Match / CountMismatch / Missing / ExtraInDest.
- **MCP** — `sharepoint_explore` + the discovery tools, and `sharepoint_compare_site`.
- **GUI** — a new **Explore** view; the Reports view gains the permissions-matrix and orphaned-users
  reports and a **Site lifecycle** control; a **Validate copy** action in the Copy-site view.
- **Docs/tests** — [docs/10](docs/10-explore.md), a consolidated [docs/TESTING.md] matrix, and
  `scripts/test/Seed-TestTenant.ps1` to seed a dev tenant for end-to-end testing.

### Changed
- Pure, unit-tested core grows: `ConvertTo-SPExploreFinding`, `Select-SPInactiveSites`,
  `Measure-SPVersionBloat`, and `Compare-SPStructure` (no tenant needed).

## [0.6.0]

**Phase 5** — deeper governance.

### Added
- **`Get-SPPermissionsMatrix`** — pivot a site's role assignments into a per-principal access
  matrix (who can touch what, at what level).
- **`Get-SPOrphanedUsers`** — report users with site access who no longer exist in the
  directory (stale-access cleanup); needs Graph `User.Read.All`.
- **`Set-SPSiteLifecycle`** — lock / read-only (archive) / unlock a site via
  `Set-PnPTenantSite` (SharePoint admin; dry-run by default).
- **MCP** — `sharepoint_permissions_matrix`, `sharepoint_orphaned_users`,
  `sharepoint_set_site_lifecycle`. New doc [docs/09](docs/09-governance.md).

### Changed
- Pure core grows: `ConvertTo-SPPermissionMatrix` and `Get-SPOrphanedPrincipals` are
  unit-tested (6 new Pester cases; 66 total, no tenant needed).

## [0.5.0]

**Phase 4** — Teams, Microsoft 365 Groups, and Planner.

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

**Phase 3** — tenant-to-tenant.

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

**Phase 2** — permissions, identity mapping, and incremental copy.

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
- **SharePoint → SharePoint site copy (Phase 1)** — `Copy-SPSite` copies a
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
