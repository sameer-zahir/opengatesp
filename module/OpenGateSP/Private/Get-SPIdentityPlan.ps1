function Get-SPIdentityPlan {
    <#
    .SYNOPSIS
        Order an identity map's creation work into dependency-safe phases: users and guests
        first, then security groups, then Microsoft 365 groups. Pure — no I/O.
    .DESCRIPTION
        Memberships can only be added once their principals exist, so Copy-SPIdentity creates
        in this order and runs the membership pass last (outside this plan). Rows whose Action
        is Skip or Map do no creation work and are excluded; each returned row gains a Phase
        (1..3) and rows keep their in-phase input order.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([object[]]$MapRow)

    $phaseOf = @{
        'User'          = 1
        'Guest'         = 1
        'SecurityGroup' = 2
        'M365Group'     = 3
    }

    $planned = foreach ($r in @($MapRow)) {
        if (-not $r) { continue }
        if ("$($r.Action)" -notin 'Create', 'Invite') { continue }
        $phase = $phaseOf["$($r.Type)"]
        if (-not $phase) { continue }   # unsupported types never plan
        $r | Select-Object *, @{ Name = 'Phase'; Expression = { $phase } }
    }
    @($planned | Sort-Object -Property Phase -Stable)
}
