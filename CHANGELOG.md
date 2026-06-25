# Changelog

All notable changes to this project are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project aims to
follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
- PSScriptAnalyzer + Pester + MCP-build CI.

### Planned
- App-only certificate auth for unattended/scheduled runs (fully headless MCP).
- Tenant-to-tenant and full-site migration; PowerShell Gallery publish. See docs/roadmap.md.
