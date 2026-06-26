function Select-SPVersionsToTrim {
    <#
    .SYNOPSIS
        Given a file's historical versions, pick the ones to delete so only the newest -Keep
        survive. Pure — no I/O.
    .DESCRIPTION
        The decision logic behind Clear-SPVersionHistory, separated so it is unit-testable. PnP's
        Get-PnPFileVersion returns only historical versions (the current published version is not
        in the list and is never touched). Versions are ordered by their numeric .ID; this keeps
        the highest -Keep IDs and returns the rest (oldest first) for removal.
    .PARAMETER Version
        Version objects with a numeric .ID (as from Get-PnPFileVersion).
    .PARAMETER Keep
        How many of the newest historical versions to retain. Default 10.
    .OUTPUTS
        The subset of versions to remove, oldest first.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [object[]]$Version,
        [int]$Keep = 10
    )

    $list = @($Version | Where-Object { $_ })
    if ($Keep -lt 0) { $Keep = 0 }
    if ($list.Count -le $Keep) { return }

    $sorted = $list | Sort-Object -Property @{ Expression = { [int]$_.ID } }
    $removeCount = $list.Count - $Keep
    $sorted | Select-Object -First $removeCount
}
