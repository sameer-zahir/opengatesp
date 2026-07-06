# Security policy

## Reporting a vulnerability

Please report vulnerabilities **privately** via GitHub: **Security → Report a vulnerability** on
this repository (private vulnerability reporting is enabled). Please don't open a public issue for
a security report. You'll get a response within a few days; confirmed issues ship as a patch
release, credited to you unless you prefer otherwise.

## Supported versions

The [latest release](https://github.com/sameer-zahir/opengatesp/releases/latest) receives security
fixes.

## Security model, in brief

- **Delegated-permissions ceiling** — OpenGateSP talks to SharePoint as *you* (or as your app-only
  certificate identity); it can never exceed the permissions of the signed-in identity.
- **AI keys stay local** — assistant API keys are encrypted with Windows DPAPI (current user, this
  machine) in `%APPDATA%\OpenGateSP\aiconfig.json`; they are never stored in plain text and never
  sent anywhere except the provider you chose.
- **Tenant content is untrusted input to the AI assistant** — write actions are off by default;
  when enabled, the model only sees schema-declared tool arguments, every write runs as a preview
  first, and the apply call is honored only after you reply to the preview in a later message.
  These are code-enforced guarantees, not model behavior (see
  [docs/13-ai-assistant.md](docs/13-ai-assistant.md)).
- **Write operations preview first everywhere** — the GUI wizard, the MCP tools, and the cmdlets
  default to dry-run and require explicit opt-in (`execute: true` / `-Force`) to change anything.
