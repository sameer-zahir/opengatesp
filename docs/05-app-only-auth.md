# 05 — App-only (certificate) auth for headless runs

Delegated auth ([docs/02](02-entra-app-registration.md)) is great interactively, but scheduled
jobs and the MCP server shouldn't need a browser. **App-only** auth uses a certificate instead
of a signed-in user, so OpenGateSP can run fully unattended.

> Trade-off: app-only uses **application** permissions (not bounded by a user). Grant the least
> privilege you need and keep the certificate safe.

## 1. Register an app-only app (one time)

PnP creates the app, a self-signed certificate, and requests admin consent:

```powershell
# Certificate installed into your user store (recommended on Windows) -> connect by thumbprint
Register-PnPEntraIDApp -ApplicationName "OpenGateSP-AppOnly" -Tenant contoso.onmicrosoft.com `
    -SharePointApplicationPermissions "Sites.FullControl.All" `
    -GraphApplicationPermissions "Sites.Read.All" `
    -Store CurrentUser
```

It prints the **AppId/ClientId** and the certificate **Thumbprint**, and a consent URL — a Global
Admin must approve the application permissions once.

For a portable certificate file instead of the store, use `-OutPath <dir>` (writes a `.pfx` and
`.cer`) and connect with `-CertificatePath`.

> Least privilege: use `Sites.Read.All` (SharePoint application permission) for read-only
> reporting jobs.

## 2. Connect app-only

```powershell
# By thumbprint (certificate in the store)
Connect-SPTool -Url https://contoso.sharepoint.com -ClientId <appId> -Tenant contoso.onmicrosoft.com -Thumbprint <thumbprint> -SaveConfig

# Or by certificate file (cross-platform). The password is read from an env var, never saved.
$env:OPENGATESP_CERT_PASSWORD = '...'
Connect-SPTool -Url https://contoso.sharepoint.com -ClientId <appId> -Tenant contoso.onmicrosoft.com -CertificatePath ./OpenGateSP-AppOnly.pfx -SaveConfig
```

`-SaveConfig` records the **auth mode** (and thumbprint / cert path — **never the password**), so
afterwards a plain `Connect-SPTool` reconnects headlessly, and so do the GUI and the MCP server.

## 3. Use it unattended

A nightly external-sharing report, no human in the loop:

```powershell
Import-Module ./module/OpenGateSP/OpenGateSP.psd1
Connect-SPTool   # app-only, from saved config — no browser
Get-SPSharingReport -SiteUrl https://contoso.sharepoint.com/sites/Marketing |
    Export-Csv "./reports/sharing-$(Get-Date -Format yyyyMMdd).csv" -NoTypeInformation
```

The **MCP server** picks this up automatically: once app-only is the saved mode, AI-driven calls
need no sign-in.

## Secret handling

- The **thumbprint** and **ClientId** are not secrets; they live in `spconfig.json`.
- The certificate **private key** is the secret. Prefer the certificate **store**
  (`-Store` / `-Thumbprint`) so the OS protects it. For `.pfx` files, pass the password via
  `OPENGATESP_CERT_PASSWORD` (env) — OpenGateSP never writes it to disk. `.pfx`/`.cer` are
  git-ignored.
