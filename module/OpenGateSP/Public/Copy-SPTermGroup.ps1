function Copy-SPTermGroup {
    <#
    .SYNOPSIS
        Copy a managed-metadata term group between tenants (or sites) via XML
        export/import. Dry-run by default.
    .DESCRIPTION
        Exports the named term group from the source term store to a temporary XML file
        (Export-PnPTermGroupToXml) and imports it into the destination
        (Import-PnPTermGroupFromXml). Useful before a tenant-to-tenant content copy so that
        managed-metadata columns have terms to bind to on the destination.
    .PARAMETER SourceConnection
        Source connection (from New-SPMigrationConnection).
    .PARAMETER DestinationConnection
        Destination connection (from New-SPMigrationConnection).
    .PARAMETER TermGroup
        The term group name to copy.
    .PARAMETER Force
        Import without the confirmation prompt (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the report row as JSON.
    .EXAMPLE
        Copy-SPTermGroup -SourceConnection $src -DestinationConnection $dst -TermGroup "Corporate Taxonomy" -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$SourceConnection,
        [Parameter(Mandatory)]$DestinationConnection,
        [Parameter(Mandatory)][string]$TermGroup,
        [switch]$Force,
        [switch]$AsJson
    )

    if (-not $SourceConnection -or -not $DestinationConnection) { throw 'Source and destination connections are required (see New-SPMigrationConnection).' }

    $dir = Join-Path ([System.IO.Path]::GetTempPath()) 'OpenGateSP'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $xmlPath = Join-Path $dir ('termgroup-' + ([guid]::NewGuid().ToString('N')) + '.xml')

    Write-SPLog "Copy-SPTermGroup: '$TermGroup' (WhatIf=$($WhatIfPreference))"
    Invoke-SPRetry -Operation 'export term group' {
        Export-PnPTermGroupToXml -Identity $TermGroup -Out $xmlPath -Connection $SourceConnection -ErrorAction Stop
    } | Out-Null

    if (-not $Force -and -not $PSCmdlet.ShouldProcess('destination term store', "Import term group '$TermGroup'")) {
        $row = New-SPCopyResult -ObjectType 'TermGroup' -Name $TermGroup -Action 'Create' -Status 'WouldCopy' -Detail "Exported to $xmlPath"
        return ($row | ConvertTo-SPOutput -AsJson:$AsJson)
    }

    try {
        Invoke-SPRetry -Operation 'import term group' {
            Import-PnPTermGroupFromXml -Path $xmlPath -Connection $DestinationConnection -ErrorAction Stop
        } | Out-Null
        $row = New-SPCopyResult -ObjectType 'TermGroup' -Name $TermGroup -Action 'Create' -Status 'Success' -Detail 'Imported'
    }
    catch {
        $row = New-SPCopyResult -ObjectType 'TermGroup' -Name $TermGroup -Action 'Create' -Status 'Error' -Detail $_.Exception.Message
    }
    finally {
        Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue
    }

    $row | ConvertTo-SPOutput -AsJson:$AsJson
}
