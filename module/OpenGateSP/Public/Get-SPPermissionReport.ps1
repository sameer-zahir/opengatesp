function Get-SPPermissionReport {
    <#
    .SYNOPSIS
        Reports who has access to a site (and optionally its lists/libraries), and where
        permission inheritance is broken.
    .DESCRIPTION
        Covers site collection administrators and site-level role assignments, expanding
        SharePoint groups to their members. With -IncludeListPermissions, also reports any
        list/library with unique (broken-inheritance) permissions.
    .PARAMETER SiteUrl
        The site to report on. The function connects to it automatically.
    .PARAMETER IncludeListPermissions
        Also scan lists/libraries for broken inheritance (slower).
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Get-SPPermissionReport -SiteUrl https://contoso.sharepoint.com/sites/Marketing -IncludeListPermissions
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$SiteUrl,

        [switch]$IncludeListPermissions,

        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    Write-SPLog "Building permission report for $SiteUrl ..."
    $rows = [System.Collections.Generic.List[object]]::new()

    # 1. Site collection administrators
    try {
        foreach ($a in (Get-PnPSiteCollectionAdmin -ErrorAction Stop)) {
            $rows.Add([pscustomobject]@{
                Scope      = 'Site Collection'
                Object     = $SiteUrl
                Principal  = $a.Title
                LoginName  = $a.LoginName
                Permission = 'Site Collection Administrator'
                Type       = 'Admin'
            })
        }
    }
    catch { Write-SPLog "Could not read site collection admins: $($_.Exception.Message)" -Level Warn }

    # Helper: expand a principal (user or SharePoint group) into rows.
    $addAssignment = {
        param($member, $perms, $scope, $object)
        $ptype = "$($member.PrincipalType)"
        $rows.Add([pscustomobject]@{
            Scope = $scope; Object = $object; Principal = $member.Title
            LoginName = $member.LoginName; Permission = $perms; Type = $ptype
        })
        if ($ptype -eq 'SharePointGroup') {
            try {
                foreach ($gm in (Get-PnPGroupMember -Group $member.Title -ErrorAction Stop)) {
                    $rows.Add([pscustomobject]@{
                        Scope = "$scope (via group)"; Object = $object
                        Principal = $gm.Title; LoginName = $gm.LoginName
                        Permission = "$perms (member of $($member.Title))"; Type = 'User'
                    })
                }
            }
            catch { Write-SPLog "Could not expand group '$($member.Title)': $($_.Exception.Message)" -Level Debug }
        }
    }

    # 2. Web-level role assignments
    try {
        $web = Get-PnPWeb -Includes RoleAssignments -ErrorAction Stop
        foreach ($ra in $web.RoleAssignments) {
            $member = Get-PnPProperty -ClientObject $ra -Property Member
            $binds  = Get-PnPProperty -ClientObject $ra -Property RoleDefinitionBindings
            $perms  = (($binds | ForEach-Object { $_.Name }) -join ', ')
            & $addAssignment $member $perms 'Site' $web.Title
        }
    }
    catch { Write-SPLog "Could not read site role assignments: $($_.Exception.Message)" -Level Warn }

    # 3. List/library broken inheritance
    if ($IncludeListPermissions) {
        try {
            $lists = Get-PnPList -ErrorAction Stop | Where-Object { -not $_.Hidden }
            foreach ($list in $lists) {
                $unique = Get-PnPProperty -ClientObject $list -Property HasUniqueRoleAssignments
                if (-not $unique) { continue }
                $las = Get-PnPProperty -ClientObject $list -Property RoleAssignments
                foreach ($ra in $las) {
                    $member = Get-PnPProperty -ClientObject $ra -Property Member
                    $binds  = Get-PnPProperty -ClientObject $ra -Property RoleDefinitionBindings
                    $perms  = (($binds | ForEach-Object { $_.Name }) -join ', ')
                    & $addAssignment $member $perms 'List (broken inheritance)' $list.Title
                }
            }
        }
        catch { Write-SPLog "Could not read list permissions: $($_.Exception.Message)" -Level Warn }
    }

    Write-SPLog "Permission report: $($rows.Count) entries." -Level Success
    $rows | ConvertTo-SPOutput -AsJson:$AsJson
}
