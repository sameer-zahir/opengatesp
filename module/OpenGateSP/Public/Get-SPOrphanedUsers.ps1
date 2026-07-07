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
    # Fail closed: the connecting admin is always a directory user, so an empty snapshot means the
    # query failed (usually missing Graph User.Read.All), never a real empty tenant. Proceeding
    # would flag EVERY site user as orphaned — and downstream Remove-SPOrphanedUsers would delete them.
    $dir = @(Get-PnPEntraIDUser -ErrorAction Stop | ForEach-Object { $_.UserPrincipalName } | Where-Object { $_ })
    if (-not $dir.Count) { throw "Directory snapshot returned no users — refusing to flag site users as orphaned (that would mark everyone orphaned). This almost always means the app registration is missing Microsoft Graph User.Read.All. Grant it (docs/02) and retry." }

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
