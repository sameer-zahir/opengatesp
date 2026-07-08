# 09 — Deeper governance

Beyond the sharing / permission / inventory reports, OpenGateSP can answer "who can touch
what", flag stale access, detect the biggest oversharing and ownership risks, and lock or
archive a site.

## Functions

| Function | What it does | Notes |
|---|---|---|
| `Get-SPPermissionsMatrix` | Per-principal access matrix — who can reach what, at what level | Read-only |
| `Get-SPOrphanedUsers` | Users with site access who no longer exist in the directory | Read-only; needs Graph `User.Read.All` |
| `Find-SPEveryoneClaims` | Where **"Everyone" / "Everyone except external users" (EEEU)** has access — the biggest oversharing risk | Read-only; writable grants graded **Error**, read-only **Warning** |
| `Get-SPOwnerlessGroups` | Microsoft 365 Groups (and the Teams/sites behind them) with **no owner** | Read-only; needs Graph `Group.Read.All`; public groups graded Error, private Warning |
| `Invoke-SPGovernanceReview` | **Consolidated review** of a site: broad-audience grants (Everyone/EEEU) + external sharing + orphaned access in one severity-graded list | Read-only; the "Protect" companion to `Invoke-SPExplore` |
| `Set-SPSiteLifecycle` | Lock / read-only (archive) / unlock a site | SharePoint **admin**; dry-run by default |

## Use it

```powershell
# Who can touch what (group by principal), including unique list permissions:
Get-SPPermissionsMatrix -SiteUrl https://contoso.sharepoint.com/sites/Marketing -IncludeListPermissions

# Stale access — accounts deleted from the directory but still on the site:
Get-SPOrphanedUsers -SiteUrl https://contoso.sharepoint.com/sites/Marketing

# The biggest oversharing risk — where Everyone/EEEU has access (scan lists too):
Find-SPEveryoneClaims -SiteUrl https://contoso.sharepoint.com/sites/Marketing -IncludeListPermissions

# Groups nobody owns (tenant-wide; needs Graph Group.Read.All):
Get-SPOwnerlessGroups

# One severity-graded governance review of a site — start here:
Invoke-SPGovernanceReview -SiteUrl https://contoso.sharepoint.com/sites/Marketing

# Archive a site (read-only) — preview first, then drop -WhatIf:
Set-SPSiteLifecycle -SiteUrl https://contoso.sharepoint.com/sites/Old -LockState ReadOnly -WhatIf
```

In the GUI these live in **Reports** (Everyone/EEEU oversharing, Ownerless groups, Governance
review), and the [AI assistant](13-ai-assistant.md) can run them conversationally.

MCP tools: `sharepoint_permissions_matrix`, `sharepoint_orphaned_users`,
`sharepoint_everyone_claims`, `sharepoint_ownerless_groups`, `sharepoint_governance_review`,
`sharepoint_set_site_lifecycle`.

## Notes / limits

- `Get-SPOrphanedUsers` snapshots the directory (`Get-PnPEntraIDUser`) and diffs — it can be
  slow on large tenants and needs Microsoft Graph `User.Read.All` on the app registration.
- `Set-SPSiteLifecycle` uses `Set-PnPTenantSite`, so connect with **`-Admin`** (a SharePoint
  administrator connection to the `-admin` URL). `ReadOnly` archives; `NoAccess` fully locks;
  `Unlock` restores.
