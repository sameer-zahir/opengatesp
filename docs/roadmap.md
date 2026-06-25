# Roadmap

OpenGateSP v0.1.0 ships the engine (PowerShell module), a Windows GUI, and an MCP server. What's next, roughly in priority order:

## Next
- **App-only certificate auth** — for unattended / scheduled runs (governance reports on a
  timer) without an interactive sign-in. Also makes the MCP server fully headless (no
  one-time browser sign-in).

## Later
- **More migration types** — tenant-to-tenant, full site (lists + pages + navigation),
  and Teams/Microsoft 365 Group migration.
- **Scheduled reports** — drop a permissions/sharing report to a library or email on a cron.
- **PowerShell Gallery** — `Install-Module OpenGateSP`.
- **More provisioning templates** — a small library of common site/library templates.

## Non-goals (for now)
- A hosted SaaS or paid tier. OpenGateSP stays a tool you run against your own tenant.
- Competing on a polished commercial GUI — the differentiator is free + scriptable + AI-driven.

Contributions welcome — open an issue describing the operation you need.
