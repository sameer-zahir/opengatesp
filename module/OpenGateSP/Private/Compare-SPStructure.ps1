function Compare-SPStructure {
    <#
    .SYNOPSIS
        Diff two site structure indexes (source vs destination) into a per-object report —
        what's missing at the destination and where item counts disagree. Pure — no I/O.
    .DESCRIPTION
        The core of post-migration validation. Compare-SPSite enumerates each side's lists and
        libraries with their item counts; this matches them by title (case-insensitive) and grades
        each: Match, CountMismatch, Missing (in source but not destination), or ExtraInDest.
    .PARAMETER Source
        Source rows with .Title and .ItemCount (BaseType optional).
    .PARAMETER Destination
        Destination rows with .Title and .ItemCount.
    .OUTPUTS
        One pscustomobject per object: Object, InSource, InDest, SourceCount, DestCount, Status.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [object[]]$Source,
        [object[]]$Destination
    )

    $destByTitle = @{}
    foreach ($d in $Destination) {
        if (-not $d -or -not $d.Title) { continue }
        $destByTitle["$($d.Title)".ToLowerInvariant()] = $d
    }

    $seen = @{}
    foreach ($s in $Source) {
        if (-not $s -or -not $s.Title) { continue }
        $key = "$($s.Title)".ToLowerInvariant()
        $seen[$key] = $true

        if ($destByTitle.ContainsKey($key)) {
            $d = $destByTitle[$key]
            $sc = [int]$s.ItemCount
            $dc = [int]$d.ItemCount
            [pscustomobject]@{
                Object      = "$($s.Title)"
                InSource    = $true
                InDest      = $true
                SourceCount = $sc
                DestCount   = $dc
                Status      = if ($sc -eq $dc) { 'Match' } else { 'CountMismatch' }
            }
        }
        else {
            [pscustomobject]@{
                Object      = "$($s.Title)"
                InSource    = $true
                InDest      = $false
                SourceCount = [int]$s.ItemCount
                DestCount   = $null
                Status      = 'Missing'
            }
        }
    }

    foreach ($d in $Destination) {
        if (-not $d -or -not $d.Title) { continue }
        if (-not $seen.ContainsKey("$($d.Title)".ToLowerInvariant())) {
            [pscustomobject]@{
                Object      = "$($d.Title)"
                InSource    = $false
                InDest      = $true
                SourceCount = $null
                DestCount   = [int]$d.ItemCount
                Status      = 'ExtraInDest'
            }
        }
    }
}
