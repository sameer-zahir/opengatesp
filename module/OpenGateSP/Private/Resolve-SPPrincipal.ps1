function Resolve-SPPrincipal {
    <#
    .SYNOPSIS
        Resolve a source principal to its destination through a principal map — explicit rows
        first, then an optional domain swap. Returns $null when nothing maps. Pure — no I/O.
    .DESCRIPTION
        The map comes from ConvertTo-SPPrincipalMap. An explicit row always wins. Failing
        that, if the principal's domain matches DomainFrom, its domain is swapped to DomainTo.
        A $null return means "no mapping" — the caller decides whether that's an error
        (cross-tenant: the principal must be remapped) or a no-op (same-tenant: the principal
        already exists and can be used as-is).
    .PARAMETER Principal
        The source principal (claims login, UPN, or email).
    .PARAMETER Map
        A map hashtable from ConvertTo-SPPrincipalMap.
    .EXAMPLE
        Resolve-SPPrincipal -Principal 'jane@contoso.com' -Map $map   # -> jane@fabrikam.com
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Principal,
        [Parameter(Mandatory)][hashtable]$Map
    )

    $key = ConvertTo-SPPrincipalKey $Principal
    if ($Map.Explicit -and $Map.Explicit.ContainsKey($key)) { return [string]$Map.Explicit[$key] }

    if ($Map.DomainFrom -and $Map.DomainTo) {
        $from = ([string]$Map.DomainFrom).ToLowerInvariant()
        if ($key -like "*@$from") {
            return ($key -replace ("@" + [regex]::Escape($from) + "$"), "@$($Map.DomainTo)")
        }
    }
    return $null
}
