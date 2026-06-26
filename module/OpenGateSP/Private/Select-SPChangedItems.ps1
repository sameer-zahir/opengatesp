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
    .PARAMETER SourceItem
        Items with .Id and .Modified.
    .PARAMETER Since
        Keep only items with Modified >= Since. Omit to ignore the watermark.
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

    $out = foreach ($it in $SourceItem) {
        if (-not $it) { continue }
        $mod = $it.Modified -as [Nullable[datetime]]

        if ($Since -and $mod -and $mod -lt $Since) { continue }

        if ($DestIndex -and $null -ne $it.Id -and $DestIndex.ContainsKey("$($it.Id)")) {
            $dmod = $DestIndex["$($it.Id)"] -as [Nullable[datetime]]
            if ($mod -and $dmod -and $mod -le $dmod) { continue }
        }
        $it
    }
    @($out)
}
