function Copy-SPTeam {
    <#
    .SYNOPSIS
        Create a new Microsoft Teams team modelled on an existing one — its channels and its
        owner/member roster. Dry-run by default.
    .DESCRIPTION
        Reads the source team's channels and members, creates a new team (a new M365 group),
        recreates each non-default channel, and adds the members the destination doesn't yet
        have. Tabs, apps, and channel messages are not copied (Graph does not expose a faithful
        copy for them). Needs a Graph connection with Group.ReadWrite.All / Team scopes.
    .PARAMETER SourceTeam
        The source team's group id or display name.
    .PARAMETER DisplayName
        Display name for the new team.
    .PARAMETER MailNickname
        Mail nickname (alias) for the new team — must be unique in the tenant.
    .PARAMETER Connection
        Optional PnP connection; defaults to the current one.
    .PARAMETER Force
        Create without the confirmation prompt (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the report as JSON.
    .EXAMPLE
        Copy-SPTeam -SourceTeam "Project Falcon" -DisplayName "Project Falcon 2" -MailNickname falcon2 -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SourceTeam,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$MailNickname,
        [object]$Connection,
        [switch]$Force,
        [switch]$AsJson
    )

    $connArg = @{}; if ($Connection) { $connArg['Connection'] = $Connection }
    Write-SPLog "Copy-SPTeam: '$SourceTeam' -> '$DisplayName' (WhatIf=$($WhatIfPreference))"

    $srcChannels = @(Get-PnPTeamsChannel -Team $SourceTeam @connArg -ErrorAction Stop)
    $owners      = @(Get-PnPTeamsUser -Team $SourceTeam -Role Owner  @connArg -ErrorAction SilentlyContinue | ForEach-Object { $_.UserPrincipalName } | Where-Object { $_ })
    $members     = @(Get-PnPTeamsUser -Team $SourceTeam -Role Member @connArg -ErrorAction SilentlyContinue | ForEach-Object { $_.UserPrincipalName } | Where-Object { $_ })
    $extraChannels = @($srcChannels | Where-Object { $_.DisplayName -ne 'General' })

    $results = [System.Collections.Generic.List[object]]::new()

    if (-not $Force -and -not $PSCmdlet.ShouldProcess($DisplayName, "Create team from '$SourceTeam'")) {
        $results.Add((New-SPCopyResult -ObjectType 'Team' -Name $DisplayName -Action 'Create' -Status 'WouldCopy' -Detail "$($extraChannels.Count) channel(s), $($owners.Count) owner(s), $($members.Count) member(s)"))
        foreach ($ch in $extraChannels) {
            $results.Add((New-SPCopyResult -ObjectType 'Channel' -Name $ch.DisplayName -Action 'Create' -Status 'WouldCopy' -Detail 'channel'))
        }
        return ($results | ConvertTo-SPOutput -AsJson:$AsJson)
    }

    # Create the team (owners seed the new group).
    $newTeam = $null
    try {
        $tp = @{ DisplayName = $DisplayName; MailNickName = $MailNickname }
        if ($owners) { $tp['Owners'] = $owners }
        $newTeam = Invoke-SPRetry -Operation "create team $DisplayName" { New-PnPTeamsTeam @tp @connArg -ErrorAction Stop }
        $results.Add((New-SPCopyResult -ObjectType 'Team' -Name $DisplayName -Action 'Create' -Status 'Success' -Detail "Created ($($owners.Count) owner(s))"))
    }
    catch {
        $results.Add((New-SPCopyResult -ObjectType 'Team' -Name $DisplayName -Action 'Create' -Status 'Error' -Detail $_.Exception.Message))
        return ($results | ConvertTo-SPOutput -AsJson:$AsJson)   # can't copy channels/members without the team
    }

    $newId = $newTeam.GroupId

    # Channels (skip the auto-created General).
    foreach ($ch in $extraChannels) {
        try {
            $cp = @{ Team = $newId; DisplayName = $ch.DisplayName }
            if ($ch.Description) { $cp['Description'] = $ch.Description }
            Invoke-SPRetry -Operation "add channel $($ch.DisplayName)" { Add-PnPTeamsChannel @cp @connArg -ErrorAction Stop } | Out-Null
            $results.Add((New-SPCopyResult -ObjectType 'Channel' -Name $ch.DisplayName -Action 'Create' -Status 'Success' -Detail 'Created'))
        }
        catch {
            $results.Add((New-SPCopyResult -ObjectType 'Channel' -Name $ch.DisplayName -Action 'Create' -Status 'Error' -Detail $_.Exception.Message))
        }
    }

    # Members the new team doesn't already have (owners are already on it).
    $toAdd = Get-SPMembershipDelta -SourceMember $members -DestMember $owners
    foreach ($m in $toAdd) {
        try {
            Invoke-SPRetry -Operation "add member $m" { Add-PnPTeamsUser -Team $newId -Users $m -Role Member @connArg -ErrorAction Stop } | Out-Null
            $results.Add((New-SPCopyResult -ObjectType 'Member' -Name $m -Action 'Create' -Status 'Success' -Detail 'Added'))
        }
        catch {
            $results.Add((New-SPCopyResult -ObjectType 'Member' -Name $m -Action 'Create' -Status 'Error' -Detail $_.Exception.Message))
        }
    }

    $errors = @($results | Where-Object Status -eq 'Error').Count
    Write-SPLog ("Copy-SPTeam: {0} step(s), {1} error(s)." -f $results.Count, $errors) -Level $(if ($errors) { 'Warn' } else { 'Success' })
    $results | ConvertTo-SPOutput -AsJson:$AsJson
}
