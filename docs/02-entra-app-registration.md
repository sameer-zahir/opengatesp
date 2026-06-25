# 02 — Register an Entra ID app

Since **2024-09-09**, PnP.PowerShell no longer ships a shared multi-tenant app — you must
register your **own** Entra ID application and pass its **ClientId** to every connection.
This is a one-time setup.

## Option A — one command (recommended)

If you can register apps in your tenant, PnP does it all for you, including consenting to
the delegated permissions:

```powershell
Register-PnPEntraIDAppForInteractiveLogin `
    -ApplicationName "OpenGateSP" `
    -Tenant contoso.onmicrosoft.com
```

A browser opens; sign in and consent. The cmdlet prints the **Application (client) ID** —
save it. That's the `-ClientId` you pass to `Connect-SPTool`.

### Default delegated permissions

The app is registered with these delegated scopes (more than enough for every v0.1.0
operation):

- `AllSites.FullControl` (SharePoint)
- `Group.ReadWrite.All`, `User.ReadWrite.All` (Microsoft Graph)
- `TermStore.ReadWrite.All`

### Least-privilege variant (read-only)

If you only need the reporting functions, register a narrower app:

```powershell
Register-PnPEntraIDAppForInteractiveLogin `
    -ApplicationName "SharePoint-Reports-ReadOnly" `
    -Tenant contoso.onmicrosoft.com `
    -SharePointDelegatePermissions "AllSites.Read" `
    -GraphDelegatePermissions "Group.Read.All", "User.Read.All"
```

## Option B — manual (Entra admin centre)

1. **Entra admin centre → App registrations → New registration.**
2. Name: `OpenGateSP`. Supported account types: **single tenant**. Register.
3. Copy the **Application (client) ID**.
4. **Authentication → Add a platform → Mobile and desktop applications**, add redirect URI
   `http://localhost`, and enable **Allow public client flows = Yes** (needed for interactive/device-code).
5. **API permissions → Add a permission:**
   - *SharePoint* → Delegated → `AllSites.FullControl` (or `AllSites.Read` for read-only)
   - *Microsoft Graph* → Delegated → `User.Read` (and `Group.Read.All` for group reports)
6. **Grant admin consent** for the tenant.

## Connect

```powershell
Connect-SPTool -Url https://contoso.sharepoint.com -ClientId <clientId> -Tenant contoso.onmicrosoft.com -SaveConfig
```

`-SaveConfig` stores `Url`/`ClientId`/`Tenant` in your user profile
(`%APPDATA%\OpenGateSP\spconfig.json`, git-ignored), so afterwards you can simply run
`Connect-SPTool`.

> **Security note:** this is delegated auth — there is **no client secret** and nothing
> secret to store. The ClientId is not a credential; the app can never exceed your own
> SharePoint permissions.
