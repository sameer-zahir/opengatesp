function Copy-SPListItems {
    <#
    .SYNOPSIS
        Copy the items of a source list into a same-named destination list, batched.
        Returns the number of items copied.
    .NOTES
        Validated against a live tenant. User and managed-metadata field values are mapped to a
        portable form via Resolve-SPFieldValue (email/login for people; "Label|TermGuid" for
        taxonomy — which needs the term group present at the destination, see Copy-SPTermGroup).
        Lookup values and per-item authors/timestamps are still not preserved. Simple columns copy
        cleanly.
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

    # Field definitions give us each field's TypeAsString, so User/Taxonomy values can be mapped to
    # a portable form (Resolve-SPFieldValue) instead of copied as source-bound CSOM objects.
    $fieldDefs = @(
        Get-PnPField -List $ListTitle -Connection $SourceConnection -ErrorAction Stop |
            Where-Object { -not $_.Hidden -and -not $_.ReadOnlyField -and $_.InternalName -notin @('Attachments', 'ContentType') }
    )
    $typeMap = @{}
    foreach ($fd in $fieldDefs) { $typeMap[$fd.InternalName] = "$($fd.TypeAsString)" }
    if (-not $Fields) { $Fields = @($fieldDefs | Select-Object -ExpandProperty InternalName) }

    $copied = 0
    $batch = New-PnPBatch -Connection $DestinationConnection
    foreach ($it in $items) {
        if (-not $PSCmdlet.ShouldProcess("$ListTitle item $($it.Id)", 'Copy list item')) { continue }
        $values = @{}
        foreach ($f in $Fields) {
            $raw = $it[$f]
            if ($null -eq $raw) { continue }
            $kind = if ($typeMap.ContainsKey($f)) { $typeMap[$f] } else { '' }
            $resolved = Resolve-SPFieldValue -FieldType $kind -Value $raw
            if ($null -ne $resolved) { $values[$f] = $resolved }
        }
        Add-PnPListItem -List $ListTitle -Values $values -Batch $batch -Connection $DestinationConnection | Out-Null
        $copied++
    }
    if ($copied -gt 0) {
        Invoke-SPRetry -Operation "add $copied item(s) to $ListTitle" { Invoke-PnPBatch -Batch $batch -Connection $DestinationConnection }
    }
    $copied
}
