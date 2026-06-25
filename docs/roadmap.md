# Roadmap

OpenGateSP v0.2.0 adds a pre-migration readiness check, scheduled governance reports, and a
redesigned GUI (sidebar navigation + card home), on top of the engine (PowerShell module), the
MCP server, and app-only certificate auth (headless/unattended). What's next, roughly in
priority order:

## Next
- **Post-migration validation** — compare a finished migration against its source (file counts
  and names) and report what didn't make it.
- **More provisioning templates** — a small library of common site/library templates.

## Later
- **More migration types** — tenant-to-tenant, full site (lists + pages + navigation),
  and Teams/Microsoft 365 Group migration.
- **PowerShell Gallery** — `Install-Module OpenGateSP`.

## Non-goals (for now)
- A hosted SaaS or paid tier. OpenGateSP stays a tool you run against your own tenant.
- Chasing feature-parity for its own sake. We invest in a clean, modern GUI, but the durable
  edge is free + open + scriptable + AI-driven, not matching every commercial checkbox.

Contributions welcome — open an issue describing the operation you need.
