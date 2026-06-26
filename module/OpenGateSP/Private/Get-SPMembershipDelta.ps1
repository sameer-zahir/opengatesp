function Get-SPMembershipDelta {
    <#
    .SYNOPSIS
        Return the members present in the source that are missing from the destination — the
        set to add when syncing Team / Group / Planner membership. Case-insensitive. Pure.
    .DESCRIPTION
        Used by the Phase 4 Team and Microsoft 365 Group copy functions to avoid re-adding
        principals the destination already has (and to keep owners out of the members add-list).
        Comparison is by lower-cased UPN/email, so 'Jane@x.com' and 'jane@x.com' match.
    .PARAMETER SourceMember
        The desired members (UPNs/emails).
    .PARAMETER DestMember
        The members already present at the destination.
    .OUTPUTS
        The subset of SourceMember not already in DestMember, in source order.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string[]]$SourceMember,
        [string[]]$DestMember
    )

    $have = @{}
    foreach ($m in $DestMember) { if ($m) { $have[$m.ToLowerInvariant()] = $true } }
    @($SourceMember | Where-Object { $_ -and -not $have.ContainsKey($_.ToLowerInvariant()) })
}
