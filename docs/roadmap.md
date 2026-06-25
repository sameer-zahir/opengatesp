# Roadmap

OpenGateSP v0.1.0 ships the engine (PowerShell module), a Windows GUI, an MCP server, and
app-only certificate auth (headless/unattended). What's next, roughly in priority order:

## Next
- **Scheduled reports** — a ready-made scheduled-task / cron example that drops a permissions or
  sharing report to a library or email, using app-only auth (no sign-in).
- **More provisioning templates** — a small library of common site/library templates.

## Later
- **More migration types** — tenant-to-tenant, full site (lists + pages + navigation),
  and Teams/Microsoft 365 Group migration.
- **PowerShell Gallery** — `Install-Module OpenGateSP`.

## Non-goals (for now)
- A hosted SaaS or paid tier. OpenGateSP stays a tool you run against your own tenant.
- Competing on a polished commercial GUI — the differentiator is free + scriptable + AI-driven.

Contributions welcome — open an issue describing the operation you need.
