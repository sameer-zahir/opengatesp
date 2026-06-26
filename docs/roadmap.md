# Roadmap

OpenGateSP v0.2.0 adds a pre-migration readiness check, scheduled governance reports, and a
redesigned GUI (sidebar navigation + card home), on top of the engine (PowerShell module), the
MCP server, and app-only certificate auth (headless/unattended). What's next, roughly in
priority order:

## SharePoint → SharePoint migration (the big build, phased)
The path toward ShareGate-style site migration, grounded in what PnP PowerShell actually supports. Each phase ships independently.
- **Phase 1 — same-tenant copy structure + content (shipped, 0.2.0):** `Copy-SPSite` / `Copy-SPList` copy a site's lists, libraries, fields, content types, views, navigation, pages, items, and files (with timestamps) to another site in the same tenant. Dry-run by default, with a GUI Copy-site wizard. See [docs/07](07-sharepoint-migration.md).
- **Phase 2 — mappings, permissions, incremental (shipped, 0.3.0):** `Copy-SPPermissions` copies role assignments and remaps users/groups (mapping CSV or domain swap); `-CopyPermissions` folds it into a site copy; `-Since` makes content copy incremental. Conflict modes (Replace/Skip/KeepBoth/IfNewer) shipped in Phase 1.
- **Phase 3** — **tenant-to-tenant** (multi-connection, identity mapping, cross-tenant files).
- **Phase 4** — **Teams + Planner + M365 Groups**.
- **Phase 5** — deeper governance (permissions-matrix / external-sharing / orphaned-user reports, lifecycle, provisioning requests).
- Maybe later: **Box** import.

## Also planned
- **Post-migration validation** — compare a finished migration against its source.
- **More provisioning templates**; **PowerShell Gallery** (`Install-Module OpenGateSP`).

## Out of scope
- Exchange/Gmail **mailboxes**, **Google Drive** import, classic **2013 workflows** — different APIs or deprecated.
- A hosted SaaS or paid tier. OpenGateSP stays a tool you run against your own tenant; the durable edge is free + open + scriptable + AI-driven.

Contributions welcome — open an issue describing the operation you need.
