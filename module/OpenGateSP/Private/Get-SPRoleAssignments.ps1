function Get-SPRoleAssignments {
    <#
    .SYNOPSIS
        Read a site's role assignments (and optionally its lists/libraries with unique
        permissions) into structured rows that Copy-SPPermissions can re-apply.
    .NOTES
        Live-tenant I/O (not runnable headlessly). 'Limited Access' is dropped — it's a
        system-managed side effect of finer-grained grants, not something to re-apply.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$Connection,
        [switch]$IncludeListPermissions
    )

    if (-not $Connection) { throw 'A source connection is required.' }
    $out = [System.Collections.Generic.List[object]]::new()

    $readRoles = {
        param($ra)
        $binds = Get-PnPProperty -ClientObject $ra -Property RoleDefinitionBindings -Connection $Connection
        @($binds | ForEach-Object { $_.Name } | Where-Object { $_ -and $_ -ne 'Limited Access' })
    }

    # Site/web-level assignments.
    $web = Get-PnPWeb -Includes RoleAssignments -Connection $Connection -ErrorAction Stop
    foreach ($ra in $web.RoleAssignments) {
        $member = Get-PnPProperty -ClientObject $ra -Property Member -Connection $Connection
        $roles  = & $readRoles $ra
        if (-not $roles) { continue }
        $out.Add([pscustomobject]@{
            Scope = 'Site'; ListTitle = $null
            LoginName = $member.LoginName; Principal = $member.Title
            PrincipalType = "$($member.PrincipalType)"; Roles = $roles
        })
    }

    # List/library assignments where inheritance is broken.
    if ($IncludeListPermissions) {
        $lists = Get-PnPList -Connection $Connection -ErrorAction Stop | Where-Object { -not $_.Hidden }
        foreach ($list in $lists) {
            $unique = Get-PnPProperty -ClientObject $list -Property HasUniqueRoleAssignments -Connection $Connection
            if (-not $unique) { continue }
            $las = Get-PnPProperty -ClientObject $list -Property RoleAssignments -Connection $Connection
            foreach ($ra in $las) {
                $member = Get-PnPProperty -ClientObject $ra -Property Member -Connection $Connection
                $roles  = & $readRoles $ra
                if (-not $roles) { continue }
                $out.Add([pscustomobject]@{
                    Scope = 'List'; ListTitle = $list.Title
                    LoginName = $member.LoginName; Principal = $member.Title
                    PrincipalType = "$($member.PrincipalType)"; Roles = $roles
                })
            }
        }
    }

    $out
}
