function ConvertTo-SPPrincipalKey {
    <#
    .SYNOPSIS
        Normalize a SharePoint principal (a claims login, a UPN, or a plain email) into a
        stable lookup key. Pure — no I/O.
    .DESCRIPTION
        SharePoint surfaces principals in several shapes: a claims login like
        'i:0#.f|membership|user@contoso.com', a group claim like 'c:0t.c|tenant|<guid>',
        or just 'user@contoso.com'. For mapping we only care about the trailing identity,
        so this strips any leading claims prefix (everything up to and including the last
        '|') and lower-cases the result.
    .PARAMETER Principal
        The principal string to normalize.
    .EXAMPLE
        ConvertTo-SPPrincipalKey 'i:0#.f|membership|Jane@Contoso.com'   # -> jane@contoso.com
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Principal
    )

    $p = $Principal.Trim()
    if ($p -match '\|([^|]+)$') { $p = $Matches[1] }
    $p.ToLowerInvariant()
}
