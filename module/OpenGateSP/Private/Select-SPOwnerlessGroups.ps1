function Select-SPOwnerlessGroups {
    <#
    .SYNOPSIS
        Pure filter: from Microsoft 365 Group rows (DisplayName, Mail, Visibility, OwnerCount),
        return the ones with no owner — a governance risk (nobody to manage membership/lifecycle).
    .DESCRIPTION
        Decision logic only (no Graph I/O), so it is unit-tested. An ownerless *public* group is
        graded Error (anyone can join, no one in charge); an ownerless private group is a Warning.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Group)

    foreach ($g in @($Group)) {
        if (-not $g) { continue }
        if ([int]$g.OwnerCount -gt 0) { continue }
        $public = "$($g.Visibility)" -eq 'Public'
        [pscustomobject]@{
            DisplayName = "$($g.DisplayName)"
            Mail        = "$($g.Mail)"
            Visibility  = "$($g.Visibility)"
            Severity    = if ($public) { 'Error' } else { 'Warning' }
        }
    }
}
