function Select-SPChangedItems {
    <#
    .SYNOPSIS
        Filter source items down to those that changed at/after a watermark (incremental
        "copy if newer"), optionally also skipping ones the destination already has at the
        same-or-newer time. Pure — no I/O.
    .DESCRIPTION
        The backbone of incremental copy. PnP has no native change-feed, so a delta run passes
        the timestamp of the last successful copy as -Since; only items modified at/after it
        survive. With -DestIndex (item id -> destination Modified) it also drops items the
        destination already holds at an equal-or-newer time, so re-runs converge.

        All timestamps are compared in UTC: Kind=Local values are converted, Kind=Unspecified
        values are TREATED AS UTC (SharePoint returns UTC datetimes with an Unspecified kind;
        a -Since built from Get-Date carries Kind=Local and converts correctly). Comparing raw
        wall-clock values would silently drop or duplicate items across timezones.
    .PARAMETER SourceItem
        Items with .Id and .Modified.
    .PARAMETER Since
        Keep only items with Modified >= Since. Treated as UTC when its Kind is Unspecified.
        Omit to ignore the watermark.
    .PARAMETER DestIndex
        Optional hashtable keyed by item id (as string) -> destination Modified.
    .OUTPUTS
        The surviving subset of SourceItem, in input order.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [object[]]$SourceItem,
        [Nullable[datetime]]$Since,
        [hashtable]$DestIndex
    )

    # Local => convert; Unspecified => stamp as UTC (SharePoint's convention); Utc => as-is.
    $toUtc = {
        param($value)
        $dt = $value -as [Nullable[datetime]]
        if ($null -eq $dt) { return $null }
        switch ($dt.Kind) {
            ([System.DateTimeKind]::Local) { $dt.ToUniversalTime() }
            ([System.DateTimeKind]::Unspecified) { [datetime]::SpecifyKind($dt, [System.DateTimeKind]::Utc) }
            default { $dt }
        }
    }

    $sinceUtc = & $toUtc $Since

    $out = foreach ($it in $SourceItem) {
        if (-not $it) { continue }
        $mod = & $toUtc $it.Modified

        if ($sinceUtc -and $mod -and $mod -lt $sinceUtc) { continue }

        if ($DestIndex -and $null -ne $it.Id -and $DestIndex.ContainsKey("$($it.Id)")) {
            $dmod = & $toUtc $DestIndex["$($it.Id)"]
            if ($mod -and $dmod -and $mod -le $dmod) { continue }
        }
        $it
    }
    @($out)
}
