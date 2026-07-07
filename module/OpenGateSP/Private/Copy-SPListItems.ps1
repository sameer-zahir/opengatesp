function Copy-SPListItems {
    <#
    .SYNOPSIS
        Copy the items of a source list into a same-named destination list, batched.
        Returns a per-list outcome: @{ Queued; Copied; Failed; Errors; Confirmed }.
    .NOTES
        Validated against a live tenant. User and managed-metadata field values are mapped to a
        portable form via Resolve-SPFieldValue (email/login for people; "Label|TermGuid" for
        taxonomy — which needs the term group present at the destination, see Copy-SPTermGroup).
        Lookup values and per-item authors/timestamps are still not preserved. Simple columns copy
        cleanly.

        The batch submit is deliberately NOT wrapped in Invoke-SPRetry: a retried Invoke-PnPBatch
        re-executes requests that already committed, duplicating items. Its per-request failures
        don't throw either — they are read from the -Details output (Measure-SPBatchOutcome), so
        partial failures surface in the outcome instead of being counted as copied.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$SourceConnection,
        [Parameter(Mandatory)]$DestinationConnection,
        [Parameter(Mandatory)][string]$ListTitle,
        [string[]]$Fields,
        [Nullable[datetime]]$Since,
        [int]$PageSize = 500
    )

    $emptyOutcome = [pscustomobject]@{ Queued = 0; Copied = 0; Failed = 0; Errors = @(); Confirmed = $true }

    $items = @(Get-PnPListItem -List $ListTitle -PageSize $PageSize -Connection $SourceConnection -ErrorAction Stop)
    if (-not $items.Count) { return $emptyOutcome }

    # Incremental: keep only items changed at/after the watermark (pure, tested helper).
    if ($Since) {
        $shaped = $items | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Modified = $_['Modified']; Raw = $_ } }
        $items = @(Select-SPChangedItems -SourceItem $shaped -Since $Since | ForEach-Object { $_.Raw })
        if (-not $items.Count) { return $emptyOutcome }
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

    $queued = 0
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
        $queued++
    }
    if (-not $queued) { return $emptyOutcome }

    # Submit once (no retry — see NOTES) and read per-request outcomes from -Details.
    $batchOutput = @()
    try {
        $batchOutput = @(Invoke-PnPBatch -Batch $batch -Connection $DestinationConnection -Details)
    }
    catch [System.Management.Automation.ParameterBindingException] {
        # PnP version without -Details: submit plain; outcome stays unconfirmed.
        Invoke-PnPBatch -Batch $batch -Connection $DestinationConnection
    }
    $outcome = Measure-SPBatchOutcome -BatchOutput $batchOutput -Queued $queued
    if ($outcome.Failed -gt 0) {
        Write-SPLog "Batch for '$ListTitle': $($outcome.Failed) of $($outcome.Queued) item(s) failed. First error: $(@($outcome.Errors)[0])" -Level Warn
    }
    $outcome
}
