function Select-SPEveryoneClaims {
    <#
    .SYNOPSIS
        Pure filter: from a site's role assignments, pick the broad-audience claims — "Everyone"
        and "Everyone except external users" (EEEU) — the top SharePoint oversharing risks.
    .DESCRIPTION
        Decision logic only (no tenant I/O), so it is unit-tested. EEEU shows up as a login
        containing 'spo-grid-all-users'; "Everyone" as the 'c:0(.s|true' claim. A grant that allows
        writing (Edit/Contribute/Full Control/...) is graded Error; read-only is a Warning.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Assignment)

    foreach ($a in @($Assignment)) {
        if (-not $a) { continue }
        $login = "$($a.LoginName)"
        $title = "$($a.Principal)"
        $claim = $null
        if ($login -like '*spo-grid-all-users*' -or $title -eq 'Everyone except external users') {
            $claim = 'Everyone except external users'
        }
        elseif ($login -like '*c:0(.s|true*' -or $title -eq 'Everyone') {
            $claim = 'Everyone'
        }
        if (-not $claim) { continue }

        $roles = @($a.Roles)
        $canWrite = @($roles | Where-Object { $_ -match 'Edit|Contribute|Full Control|Design|Manage|Owner' }).Count -gt 0
        [pscustomobject]@{
            Claim    = $claim
            Scope    = "$($a.Scope)"
            Location = if ("$($a.Scope)" -eq 'List') { "$($a.ListTitle)" } else { 'Site' }
            Roles    = ($roles -join ', ')
            Severity = if ($canWrite) { 'Error' } else { 'Warning' }
        }
    }
}
