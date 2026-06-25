function Set-SPBulkMetadata {
    <#
    .SYNOPSIS
        Bulk-update list/library item metadata from a CSV file.
    .DESCRIPTION
        Reads a CSV where one column identifies the item (default "ID") and the remaining
        columns are field internal names to set. Each row updates one item. Throttling is
        handled with back-off, and a per-item result is returned.

        SAFETY: run with -WhatIf first to preview. A real run asks for one confirmation
        before writing (suppress with -Force).
    .PARAMETER SiteUrl
        The site containing the list/library. The function connects to it automatically.
    .PARAMETER List
        List/library display name or internal name.
    .PARAMETER CsvPath
        Path to the CSV. Header row = field internal names; one column is the item id.
    .PARAMETER IdColumn
        Name of the CSV column holding the item id. Default "ID".
    .PARAMETER Force
        Skip the one-time "are you sure" confirmation on a real run.
    .PARAMETER AsJson
        Emit the per-item result as a JSON array instead of objects.
    .EXAMPLE
        Set-SPBulkMetadata -SiteUrl https://contoso.sharepoint.com/sites/Mktg -List Documents -CsvPath ./updates.csv -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][string]$List,
        [Parameter(Mandatory)][string]$CsvPath,
        [string]$IdColumn = 'ID',
        [switch]$Force,
        [switch]$AsJson
    )

    if (-not (Test-Path -LiteralPath $CsvPath)) { throw "CSV not found: $CsvPath" }
    $rows = @(Import-Csv -LiteralPath $CsvPath)
    if ($rows.Count -eq 0) { throw "CSV is empty: $CsvPath" }

    $columns = $rows[0].PSObject.Properties.Name
    if ($columns -notcontains $IdColumn) { throw "CSV has no '$IdColumn' column. Columns: $($columns -join ', ')" }
    $fieldNames = $columns | Where-Object { $_ -ne $IdColumn }
    if (-not $fieldNames) { throw "CSV has no field columns to set (only '$IdColumn')." }

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    Write-SPLog "Bulk metadata on '$List' ($($rows.Count) rows; fields: $($fieldNames -join ', '); WhatIf=$($WhatIfPreference))"

    if (-not $WhatIfPreference -and -not $Force) {
        if (-not $PSCmdlet.ShouldContinue("Update $($rows.Count) item(s) in '$List' on $SiteUrl? This writes to SharePoint.", 'Confirm bulk update')) {
            Write-SPLog 'Bulk update cancelled by user.' -Level Warn
            return
        }
    }

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $id = $row.$IdColumn
        if (-not $id) {
            $results.Add([pscustomobject]@{ Id = $null; Status = 'Skipped (no id)'; Fields = $null; Error = $null })
            continue
        }

        $values = @{}
        foreach ($f in $fieldNames) { if ("$($row.$f)" -ne '') { $values[$f] = $row.$f } }
        $fieldList = $values.Keys -join ', '

        if (-not $PSCmdlet.ShouldProcess("item #$id in '$List'", "Set $fieldList")) {
            $results.Add([pscustomobject]@{ Id = $id; Status = 'WouldUpdate'; Fields = $fieldList; Error = $null })
            continue
        }

        try {
            Invoke-SPRetry -Operation "Set-PnPListItem #$id" { Set-PnPListItem -List $List -Identity $id -Values $values -ErrorAction Stop } | Out-Null
            $results.Add([pscustomobject]@{ Id = $id; Status = 'Updated'; Fields = $fieldList; Error = $null })
        }
        catch {
            Write-SPLog "FAILED item #${id}: $($_.Exception.Message)" -Level Error
            $results.Add([pscustomobject]@{ Id = $id; Status = 'Failed'; Fields = $fieldList; Error = $_.Exception.Message })
        }
    }

    $updated = @($results | Where-Object Status -eq 'Updated').Count
    Write-SPLog "Bulk metadata done. $updated updated of $($rows.Count)." -Level Success
    $results | ConvertTo-SPOutput -AsJson:$AsJson
}
