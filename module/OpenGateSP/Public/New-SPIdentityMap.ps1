function New-SPIdentityMap {
    <#
    .SYNOPSIS
        Propose a reviewable source→destination identity mapping: match what already exists
        at the destination, propose UPNs for what doesn't. Read-only; nothing is created.
    .DESCRIPTION
        Step 2 of the identity-copy pipeline (docs/14). For every inventory row it emits one
        map row with a proposed Action:

          Map    — an existing destination identity matched (users by mail first, then UPN
                   local part; groups by mail nickname, then display name)
          Create — no match; users get local-part@DomainTo as the proposed UPN
          Invite — guests (only with -IncludeGuests; skipped otherwise)
          Skip   — guests by default, and group types Graph cannot create

        The output CSV is meant to be HAND-EDITED — change Actions, fix target UPNs — then
        validated with Test-SPIdentityMap and executed with Copy-SPIdentity.
    .PARAMETER InventoryCsv
        The inventory CSV from Get-SPIdentityInventory -Path.
    .PARAMETER Inventory
        The inventory rows as objects (alternative to -InventoryCsv).
    .PARAMETER DomainTo
        Destination UPN domain for proposed users, e.g. fabrikam.com. Must be verified at the
        destination tenant (Test-SPIdentityMap checks).
    .PARAMETER DestinationConnection
        Optional PnP connection to the DESTINATION tenant; defaults to the current connection.
    .PARAMETER IncludeGuests
        Propose Action=Invite for guest accounts instead of skipping them.
    .PARAMETER Path
        Optional CSV path to write the map to (the file you review and edit).
    .PARAMETER AsJson
        Emit the map as a JSON array instead of objects.
    .EXAMPLE
        New-SPIdentityMap -InventoryCsv .\contoso-identities.csv -DomainTo fabrikam.com -DestinationConnection $dst -Path .\identity-map.csv
    #>
    [CmdletBinding(DefaultParameterSetName = 'Csv')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Csv')][string]$InventoryCsv,
        [Parameter(Mandatory, ParameterSetName = 'Objects')][object[]]$Inventory,
        [Parameter(Mandatory)][string]$DomainTo,
        [object]$DestinationConnection,
        [switch]$IncludeGuests,
        [string]$Path,
        [switch]$AsJson
    )

    if ($PSCmdlet.ParameterSetName -eq 'Csv') {
        if (-not (Test-Path -LiteralPath $InventoryCsv)) { throw "Inventory CSV not found: $InventoryCsv" }
        $Inventory = @(Import-Csv -LiteralPath $InventoryCsv)
    }
    if (-not @($Inventory).Count) { throw 'The inventory is empty - nothing to map.' }

    $connArg = @{}; if ($DestinationConnection) { $connArg['Connection'] = $DestinationConnection }
    Write-SPLog "New-SPIdentityMap: mapping $(@($Inventory).Count) identit(ies) to $DomainTo ..."

    # Snapshot the destination once; the pure mapper does the matching.
    $destUsers = @(Invoke-SPGraph -Method GET -Url 'v1.0/users?$select=id,userPrincipalName,displayName,mail&$top=999' -All @connArg)
    $destGroups = @(Invoke-SPGraph -Method GET -Url 'v1.0/groups?$select=id,displayName,mailNickname&$top=999' -All @connArg)

    $rows = @(foreach ($inv in @($Inventory)) {
            ConvertTo-SPIdentityMapRow -InventoryRow $inv -DomainTo $DomainTo -DestUsers $destUsers -DestGroups $destGroups -IncludeGuests:$IncludeGuests
        })

    $byAction = $rows | Group-Object Action -AsHashTable -AsString
    Write-SPLog ("Map proposed: {0} Create, {1} Map, {2} Invite, {3} Skip. Review the CSV, then run Test-SPIdentityMap." -f `
        @($byAction['Create']).Count, @($byAction['Map']).Count, @($byAction['Invite']).Count, @($byAction['Skip']).Count) -Level Success

    if ($Path) {
        $rows | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8
        Write-SPLog "Map CSV written (hand-edit before copying): $Path" -Level Success
    }
    $rows | ConvertTo-SPOutput -AsJson:$AsJson
}
