function ConvertTo-SPPermissionMatrix {
    <#
    .SYNOPSIS
        Pivot flat role-assignment rows into a per-principal access matrix: one row per
        principal, listing every object they can reach and at what level. Pure — no I/O.
    .DESCRIPTION
        Get-SPPermissionReport / Get-SPRoleAssignments emit one row per (principal, object,
        roles). For a governance review it's easier to read "who can touch what" grouped by
        principal — this produces that view: Principal, AccessCount, and a Grants summary.
    .PARAMETER Assignment
        Rows with a .Principal and either .ListTitle/.Object/.Scope plus .Roles (or .Permission).
    .OUTPUTS
        One pscustomobject per principal: Principal, AccessCount, Grants.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [object[]]$Assignment
    )

    $byPrincipal = [ordered]@{}
    foreach ($a in $Assignment) {
        if (-not $a) { continue }
        $key = "$($a.Principal)"
        if (-not $key) { continue }

        $obj   = if ($a.ListTitle) { $a.ListTitle } elseif ($a.Object) { $a.Object } else { "$($a.Scope)" }
        $roles = if ($a.Roles) { ($a.Roles -join '/') } else { "$($a.Permission)" }

        if (-not $byPrincipal.Contains($key)) { $byPrincipal[$key] = [System.Collections.Generic.List[string]]::new() }
        $byPrincipal[$key].Add(('{0}: {1}' -f $obj, $roles))
    }

    foreach ($k in $byPrincipal.Keys) {
        [pscustomobject]@{
            Principal   = $k
            AccessCount = $byPrincipal[$k].Count
            Grants      = ($byPrincipal[$k] -join '; ')
        }
    }
}
