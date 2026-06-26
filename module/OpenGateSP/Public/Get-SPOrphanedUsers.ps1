function Get-SPOrphanedUsers {
    <#
    .SYNOPSIS
        Report users who still have access to a site but no longer exist in the directory
        (deleted accounts / stale access) — cleanup candidates for a governance review.
    .DESCRIPTION
        Lists the site's users and compares them against a snapshot of the directory
        (Get-PnPEntraIDUser). Any site user whose UPN/email isn't in the directory is reported
        as orphaned. Read-only. The directory snapshot can be large/slow on big tenants and
        needs Microsoft Graph User.Read.All on the app registration.
    .PARAMETER SiteUrl
        The site to scan. Connected automatically.
    .PARAMETER AsJson
        Emit a JSON array.
    .EXAMPLE
        Get-SPOrphanedUsers -SiteUrl https://contoso.sharepoint.com/sites/Marketing
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    Write-SPLog "Scanning $SiteUrl for orphaned users ..."

    $siteUsers = @(Get-PnPUser -ErrorAction Stop)
    $dir = @(Get-PnPEntraIDUser -ErrorAction SilentlyContinue | ForEach-Object { $_.UserPrincipalName } | Where-Object { $_ })
    if (-not $dir.Count) { Write-SPLog 'Directory snapshot was empty — check Graph User.Read.All on the app.' -Level Warn }

    $orphans = @(Get-SPOrphanedPrincipals -SitePrincipal $siteUsers -DirectoryLogin $dir)
    $rows = $orphans | ForEach-Object {
        [pscustomobject]@{
            Title     = $_.Title
            LoginName = $_.LoginName
            Email     = $_.Email
            Status    = 'Orphaned'
        }
    }

    Write-SPLog "Found $(@($rows).Count) orphaned user(s)." -Level $(if (@($rows).Count) { 'Warn' } else { 'Success' })
    $rows | ConvertTo-SPOutput -AsJson:$AsJson
}
