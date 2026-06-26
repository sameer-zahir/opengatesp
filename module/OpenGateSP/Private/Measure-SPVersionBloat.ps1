function Measure-SPVersionBloat {
    <#
    .SYNOPSIS
        Flag files whose version history is excessive — too many versions or too much space
        spent on versions. Pure — no I/O.
    .DESCRIPTION
        Version history is a common migration cost: it multiplies the data to move and is the
        first thing to trim. Get-SPVersionHistoryReport gathers per-file version counts/sizes;
        this classifies which of them cross a threshold, so Explore can surface them and the
        Clear-SPVersionHistory remediation can act on them.
    .PARAMETER Item
        Rows with .Name (or .FileRef/.Url), .VersionCount, and .VersionSizeMB.
    .PARAMETER MaxVersions
        Flag a file with more than this many versions. Default 50.
    .PARAMETER MaxVersionSizeMB
        Flag a file whose versions occupy more than this many MB. Default 100.
    .OUTPUTS
        One pscustomobject per flagged file: Name, VersionCount, VersionSizeMB, Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [object[]]$Item,
        [int]$MaxVersions = 50,
        [double]$MaxVersionSizeMB = 100
    )

    foreach ($it in $Item) {
        if (-not $it) { continue }
        $vc = $it.VersionCount -as [int]
        $vs = $it.VersionSizeMB -as [double]

        $reasons = [System.Collections.Generic.List[string]]::new()
        if ($vc -gt $MaxVersions) { $reasons.Add("versions=$vc (>$MaxVersions)") }
        if ($vs -gt $MaxVersionSizeMB) { $reasons.Add("versionMB=$([math]::Round($vs, 1)) (>$MaxVersionSizeMB)") }

        if ($reasons.Count) {
            [pscustomobject]@{
                Name          = if ($it.Name) { "$($it.Name)" } elseif ($it.FileRef) { "$($it.FileRef)" } else { "$($it.Url)" }
                VersionCount  = $vc
                VersionSizeMB = [math]::Round($vs, 1)
                Reason        = ($reasons -join '; ')
            }
        }
    }
}
