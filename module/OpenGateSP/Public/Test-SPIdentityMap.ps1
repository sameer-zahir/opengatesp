function Test-SPIdentityMap {
    <#
    .SYNOPSIS
        Validate an (edited) identity map against the destination tenant before anything is
        created: UPN/nickname collisions, unverified domains, vanished matches. Read-only.
    .DESCRIPTION
        Step 3 of the identity-copy pipeline (docs/14). Emits one finding per map row
        (Status OK | Warning | Error, errors first). Copy-SPIdentity re-runs this validation
        itself and refuses to start while any row is an Error, so fixing the map here is not
        optional busywork — it is the gate.

        Needs Graph User.Read.All + Group.Read.All + Organization.Read.All at the destination.
    .PARAMETER MapCsv
        The map CSV from New-SPIdentityMap -Path (after your edits).
    .PARAMETER Map
        The map rows as objects (alternative to -MapCsv).
    .PARAMETER DestinationConnection
        Optional PnP connection to the DESTINATION tenant; defaults to the current connection.
    .PARAMETER AsJson
        Emit the findings as a JSON array instead of objects.
    .EXAMPLE
        Test-SPIdentityMap -MapCsv .\identity-map.csv -DestinationConnection $dst
    #>
    [CmdletBinding(DefaultParameterSetName = 'Csv')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Csv')][string]$MapCsv,
        [Parameter(Mandatory, ParameterSetName = 'Objects')][object[]]$Map,
        [object]$DestinationConnection,
        [switch]$AsJson
    )

    if ($PSCmdlet.ParameterSetName -eq 'Csv') {
        if (-not (Test-Path -LiteralPath $MapCsv)) { throw "Map CSV not found: $MapCsv" }
        $Map = @(Import-Csv -LiteralPath $MapCsv)
    }
    if (-not @($Map).Count) { throw 'The identity map is empty - nothing to validate.' }

    $connArg = @{}; if ($DestinationConnection) { $connArg['Connection'] = $DestinationConnection }
    Write-SPLog "Test-SPIdentityMap: validating $(@($Map).Count) row(s) against the destination ..."

    $destUsers = @(Invoke-SPGraph -Method GET -Url 'v1.0/users?$select=id,userPrincipalName,mail&$top=999' -All @connArg)
    $destGroups = @(Invoke-SPGraph -Method GET -Url 'v1.0/groups?$select=id,displayName,mailNickname&$top=999' -All @connArg)
    $org = Invoke-SPGraph -Method GET -Url 'v1.0/organization?$select=verifiedDomains' -All @connArg
    $verifiedDomains = @($org | ForEach-Object { @($_.verifiedDomains) } | ForEach-Object { "$($_.name)" } | Where-Object { $_ })

    $findings = @(Test-SPIdentityConflict -MapRow $Map -DestUsers $destUsers -DestGroups $destGroups -VerifiedDomains $verifiedDomains)

    $errors = @($findings | Where-Object Status -eq 'Error').Count
    $warnings = @($findings | Where-Object Status -eq 'Warning').Count
    $level = if ($errors) { 'Error' } elseif ($warnings) { 'Warn' } else { 'Success' }
    Write-SPLog ("Validation: {0} row(s) — {1} error(s), {2} warning(s). {3}" -f `
            @($findings).Count, $errors, $warnings,
        $(if ($errors) { 'NOT ready - fix the errors before Copy-SPIdentity.' } else { 'Ready for Copy-SPIdentity.' })) -Level $level

    # Errors first, then warnings, then OK — same convention as Test-SPMigrationReadiness.
    $rank = @{ Error = 0; Warning = 1; OK = 2 }
    $sorted = @($findings | Sort-Object -Property @{ Expression = { $rank["$($_.Status)"] } } -Stable)
    $sorted | ConvertTo-SPOutput -AsJson:$AsJson
}
