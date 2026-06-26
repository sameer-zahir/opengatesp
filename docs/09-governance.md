# 09 — Deeper governance (Phase 5)

Beyond the sharing / permission / inventory reports, OpenGateSP can answer "who can touch
what", flag stale access, and lock or archive a site.

## Functions

| Function | What it does | Notes |
|---|---|---|
| `Get-SPPermissionsMatrix` | Per-principal access matrix — who can reach what, at what level | Read-only |
| `Get-SPOrphanedUsers` | Users with site access who no longer exist in the directory | Read-only; needs Graph `User.Read.All` |
| `Set-SPSiteLifecycle` | Lock / read-only (archive) / unlock a site | SharePoint **admin**; dry-run by default |

## Use it

```powershell
# Who can touch what (group by principal), including unique list permissions:
Get-SPPermissionsMatrix -SiteUrl https://contoso.sharepoint.com/sites/Marketing -IncludeListPermissions

# Stale access — accounts deleted from the directory but still on the site:
Get-SPOrphanedUsers -SiteUrl https://contoso.sharepoint.com/sites/Marketing

# Archive a site (read-only) — preview first, then drop -WhatIf:
Set-SPSiteLifecycle -SiteUrl https://contoso.sharepoint.com/sites/Old -LockState ReadOnly -WhatIf
```

MCP tools: `sharepoint_permissions_matrix`, `sharepoint_orphaned_users`,
`sharepoint_set_site_lifecycle`.

## Notes / limits

- `Get-SPOrphanedUsers` snapshots the directory (`Get-PnPEntraIDUser`) and diffs — it can be
  slow on large tenants and needs Microsoft Graph `User.Read.All` on the app registration.
- `Set-SPSiteLifecycle` uses `Set-PnPTenantSite`, so connect with **`-Admin`** (a SharePoint
  administrator connection to the `-admin` URL). `ReadOnly` archives; `NoAccess` fully locks;
  `Unlock` restores.
