function Copy-SPListItems {
    <#
    .SYNOPSIS
        Copy the items of a source list into a same-named destination list, batched.
        Returns the number of items copied.
    .NOTES
        Validated against a live tenant. Field fidelity caveats (Phase 2): lookup, user,
        and managed-metadata field values may not round-trip; authors/timestamps are not
        yet preserved on items. Simple columns copy cleanly.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]$SourceConnection,
        [Parameter(Mandatory)]$DestinationConnection,
        [Parameter(Mandatory)][string]$ListTitle,
        [string[]]$Fields,
        [Nullable[datetime]]$Since,
        [int]$PageSize = 500
    )

    $items = @(Get-PnPListItem -List $ListTitle -PageSize $PageSize -Connection $SourceConnection -ErrorAction Stop)
    if (-not $items.Count) { return 0 }

    # Incremental: keep only items changed at/after the watermark (pure, tested helper).
    if ($Since) {
        $shaped = $items | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Modified = $_['Modified']; Raw = $_ } }
        $items = @(Select-SPChangedItems -SourceItem $shaped -Since $Since | ForEach-Object { $_.Raw })
        if (-not $items.Count) { return 0 }
    }

    if (-not $Fields) {
        $Fields = @(
            Get-PnPField -List $ListTitle -Connection $SourceConnection -ErrorAction Stop |
                Where-Object { -not $_.Hidden -and -not $_.ReadOnlyField -and $_.InternalName -notin @('Attachments', 'ContentType') } |
                Select-Object -ExpandProperty InternalName
        )
    }

    $copied = 0
    $batch = New-PnPBatch -Connection $DestinationConnection
    foreach ($it in $items) {
        if (-not $PSCmdlet.ShouldProcess("$ListTitle item $($it.Id)", 'Copy list item')) { continue }
        $values = @{}
        foreach ($f in $Fields) { if ($null -ne $it[$f]) { $values[$f] = $it[$f] } }
        Add-PnPListItem -List $ListTitle -Values $values -Batch $batch -Connection $DestinationConnection | Out-Null
        $copied++
    }
    if ($copied -gt 0) {
        Invoke-SPRetry -Operation "add $copied item(s) to $ListTitle" { Invoke-PnPBatch -Batch $batch -Connection $DestinationConnection }
    }
    $copied
}
