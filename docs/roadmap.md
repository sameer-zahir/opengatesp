# Roadmap

OpenGateSP v0.1.0 ships the engine (PowerShell module) + a Windows GUI. What's next, roughly in priority order:

## Next
- **MCP server** — a TypeScript Model Context Protocol server that exposes each engine
  function as a tool, so Claude / Codex / Gemini can run migrations and reports
  conversationally. Cheap to build because every function already emits `-AsJson`.
- **App-only certificate auth** — for unattended / scheduled runs (governance reports on a
  timer) without an interactive sign-in.

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
