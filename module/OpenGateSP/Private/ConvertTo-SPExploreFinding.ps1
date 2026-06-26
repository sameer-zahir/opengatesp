function ConvertTo-SPExploreFinding {
    <#
    .SYNOPSIS
        Normalize a set of discovery-report rows into the uniform Explore "finding" shape, so a
        consolidated assessment can mix checked-out files, large files, external shares, orphans,
        etc. in one severity-graded table. Pure — no I/O.
    .DESCRIPTION
        Invoke-SPExplore runs several read-only checks, each returning its own row shape. This
        maps any of them to a common finding: { Category, ItemType, Name, Severity, Detail, Count }.
        Per item by default (one finding per row); with -Aggregate it collapses to a single summary
        finding carrying the item Count — handy for "47 large files" rather than 47 rows.
    .PARAMETER Item
        The report rows to convert. No items yields no findings.
    .PARAMETER Category
        The finding category, e.g. 'Checked-out files', 'Large files', 'External sharing'.
    .PARAMETER Severity
        Error (a migration blocker), Warning (migrates with caveats / worth review), or Info.
    .PARAMETER ItemType
        What each row is, e.g. File, Site, List, User. Default 'File'.
    .PARAMETER NameProperty
        Property to use as the finding Name. If omitted, falls back to the first present of
        Name, Title, FileRef, Url, LoginName, Principal.
    .PARAMETER DetailProperty
        Optional property to use as the finding Detail.
    .PARAMETER Aggregate
        Emit one summary finding with Count = item count instead of one finding per item.
    .OUTPUTS
        pscustomobject findings: Category, ItemType, Name, Severity, Detail, Count.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [object[]]$Item,
        [Parameter(Mandatory)][string]$Category,
        [ValidateSet('Error', 'Warning', 'Info')][string]$Severity = 'Warning',
        [string]$ItemType = 'File',
        [string]$NameProperty,
        [string]$DetailProperty,
        [switch]$Aggregate
    )

    $rows = @($Item | Where-Object { $_ })
    if (-not $rows.Count) { return }

    if ($Aggregate) {
        [pscustomobject]@{
            Category = $Category
            ItemType = $ItemType
            Name     = "$($rows.Count) item(s)"
            Severity = $Severity
            Detail   = "$Category — $($rows.Count) found"
            Count    = $rows.Count
        }
        return
    }

    $nameFallback = @('Name', 'Title', 'FileRef', 'Url', 'LoginName', 'Principal')
    foreach ($r in $rows) {
        $name = $null
        if ($NameProperty -and $null -ne $r.$NameProperty) {
            $name = "$($r.$NameProperty)"
        }
        else {
            foreach ($p in $nameFallback) {
                if ($null -ne $r.$p -and "$($r.$p)") { $name = "$($r.$p)"; break }
            }
        }

        $detail = if ($DetailProperty -and $null -ne $r.$DetailProperty) { "$($r.$DetailProperty)" } else { '' }

        [pscustomobject]@{
            Category = $Category
            ItemType = $ItemType
            Name     = $name
            Severity = $Severity
            Detail   = $detail
            Count    = 1
        }
    }
}
