function Find-SPEveryoneClaims {
    <#
    .SYNOPSIS
        Find where "Everyone" or "Everyone except external users" (EEEU) has been granted access on a
        site — the single biggest SharePoint oversharing risk. Read-only.
    .DESCRIPTION
        Reads the site's role assignments (and, with -IncludeListPermissions, lists/libraries with
        unique permissions) and reports every broad-audience grant, graded by whether it allows
        writing. This is the detection half of ShareGate-Protect-style governance — pair it with
        Restore-SPInheritance / Set-SPSiteLifecycle to remediate.
    .PARAMETER SiteUrl
        The site to scan. Connected automatically.
    .PARAMETER IncludeListPermissions
        Also scan lists/libraries that have unique permissions (slower).
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Find-SPEveryoneClaims -SiteUrl https://contoso.sharepoint.com/sites/Marketing -IncludeListPermissions
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [switch]$IncludeListPermissions,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    Write-SPLog "Scanning $SiteUrl for 'Everyone' / EEEU broad-access grants ..."
    $conn = Get-PnPConnection
    $assignments = @(Get-SPRoleAssignments -Connection $conn -IncludeListPermissions:$IncludeListPermissions)
    $findings = @(Select-SPEveryoneClaims -Assignment $assignments)

    $level = if (@($findings | Where-Object { $_.Severity -eq 'Error' }).Count) { 'Error' }
    elseif ($findings.Count) { 'Warning' } else { 'Success' }
    Write-SPLog "Found $($findings.Count) broad-access grant(s) on $SiteUrl." -Level $level
    $findings | ConvertTo-SPOutput -AsJson:$AsJson
}
