function Get-SPPermissionsMatrix {
    <#
    .SYNOPSIS
        Report a site's access as a per-principal matrix: one row per user/group, listing
        every object they can reach and at what level. The "who can touch what" governance view.
    .DESCRIPTION
        Reads the site's role assignments (and, with -IncludeListPermissions, unique
        list/library permissions) and pivots them per principal. Read-only.
    .PARAMETER SiteUrl
        The site to report on. Connected automatically.
    .PARAMETER IncludeListPermissions
        Also include lists/libraries with unique permissions (slower).
    .PARAMETER AsJson
        Emit a JSON array.
    .EXAMPLE
        Get-SPPermissionsMatrix -SiteUrl https://contoso.sharepoint.com/sites/Marketing -IncludeListPermissions
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [switch]$IncludeListPermissions,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    Write-SPLog "Building permission matrix for $SiteUrl ..."
    $conn = Get-PnPConnection
    $assignments = @(Get-SPRoleAssignments -Connection $conn -IncludeListPermissions:$IncludeListPermissions)
    $matrix = @(ConvertTo-SPPermissionMatrix -Assignment $assignments)
    Write-SPLog "Permission matrix: $($matrix.Count) principal(s)." -Level Success
    $matrix | ConvertTo-SPOutput -AsJson:$AsJson
}
