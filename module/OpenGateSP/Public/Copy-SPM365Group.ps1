function Copy-SPM365Group {
    <#
    .SYNOPSIS
        Create a new Microsoft 365 Group modelled on an existing one — same description and
        owner/member roster. Dry-run by default.
    .DESCRIPTION
        Reads the source group's description, owners, and members, then creates a new group
        with a fresh display name and mail nickname and the same roster. The connection needs
        Microsoft Graph Group.ReadWrite.All (register the app with those scopes; see docs/02).
    .PARAMETER SourceIdentity
        The source group's id or display name.
    .PARAMETER DisplayName
        Display name for the new group.
    .PARAMETER MailNickname
        Mail nickname (alias) for the new group — must be unique in the tenant.
    .PARAMETER Connection
        Optional PnP connection (from New-SPMigrationConnection); defaults to the current one.
    .PARAMETER Force
        Create without the confirmation prompt (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the report as JSON.
    .EXAMPLE
        Copy-SPM365Group -SourceIdentity "Marketing" -DisplayName "Marketing 2" -MailNickname marketing2 -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SourceIdentity,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$MailNickname,
        [object]$Connection,
        [switch]$Force,
        [switch]$AsJson
    )

    $connArg = @{}; if ($Connection) { $connArg['Connection'] = $Connection }
    Write-SPLog "Copy-SPM365Group: '$SourceIdentity' -> '$DisplayName' (WhatIf=$($WhatIfPreference))"

    $srcGroup = Get-PnPMicrosoft365Group -Identity $SourceIdentity @connArg -ErrorAction Stop
    $owners   = @(Get-PnPMicrosoft365GroupOwner  -Identity $SourceIdentity @connArg -ErrorAction SilentlyContinue | ForEach-Object { $_.UserPrincipalName } | Where-Object { $_ })
    $members  = @(Get-PnPMicrosoft365GroupMember -Identity $SourceIdentity @connArg -ErrorAction SilentlyContinue | ForEach-Object { $_.UserPrincipalName } | Where-Object { $_ })

    $results = [System.Collections.Generic.List[object]]::new()
    $detail  = "$($owners.Count) owner(s), $($members.Count) member(s)"

    if (-not $Force -and -not $PSCmdlet.ShouldProcess($DisplayName, "Create M365 group from '$($srcGroup.DisplayName)'")) {
        $results.Add((New-SPCopyResult -ObjectType 'M365Group' -Name $DisplayName -Action 'Create' -Status 'WouldCopy' -Detail $detail))
        return ($results | ConvertTo-SPOutput -AsJson:$AsJson)
    }

    try {
        $p = @{ DisplayName = $DisplayName; MailNickname = $MailNickname }
        if ($srcGroup.Description) { $p['Description'] = $srcGroup.Description }
        if ($owners)  { $p['Owners']  = $owners }
        if ($members) { $p['Members'] = $members }
        Invoke-SPRetry -Operation "create group $DisplayName" { New-PnPMicrosoft365Group @p @connArg -ErrorAction Stop } | Out-Null
        $results.Add((New-SPCopyResult -ObjectType 'M365Group' -Name $DisplayName -Action 'Create' -Status 'Success' -Detail "Created ($detail)"))
    }
    catch {
        $results.Add((New-SPCopyResult -ObjectType 'M365Group' -Name $DisplayName -Action 'Create' -Status 'Error' -Detail $_.Exception.Message))
    }

    $results | ConvertTo-SPOutput -AsJson:$AsJson
}
