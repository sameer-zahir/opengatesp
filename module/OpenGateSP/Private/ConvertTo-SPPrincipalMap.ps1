function ConvertTo-SPPrincipalMap {
    <#
    .SYNOPSIS
        Build a normalized source-to-destination principal lookup from mapping rows and/or a
        blanket domain swap. Pure — no I/O.
    .DESCRIPTION
        Used to remap users and groups when copying permissions between sites or tenants.
        Each row contributes an explicit Source=Destination entry (keyed by the normalized
        source via ConvertTo-SPPrincipalKey). -DomainFrom/-DomainTo add a fallback that swaps
        an email/UPN domain when no explicit row matches — handy for tenant-to-tenant moves
        where every 'name@contoso.com' becomes 'name@fabrikam.com'.
    .PARAMETER Row
        Objects with .Source and .Destination properties. Import-Csv rows work directly.
    .PARAMETER DomainFrom
        Source domain for the fallback swap, e.g. 'contoso.com'.
    .PARAMETER DomainTo
        Destination domain for the fallback swap, e.g. 'fabrikam.com'.
    .OUTPUTS
        A hashtable: @{ Explicit = <normalized-source -> destination>; DomainFrom; DomainTo }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [object[]]$Row,
        [string]$DomainFrom,
        [string]$DomainTo
    )

    $explicit = @{}
    foreach ($r in $Row) {
        if (-not $r) { continue }
        $s = "$($r.Source)".Trim()
        $d = "$($r.Destination)".Trim()
        if (-not $s -or -not $d) { continue }
        $explicit[(ConvertTo-SPPrincipalKey $s)] = $d
    }

    @{
        Explicit   = $explicit
        DomainFrom = $DomainFrom
        DomainTo   = $DomainTo
    }
}
