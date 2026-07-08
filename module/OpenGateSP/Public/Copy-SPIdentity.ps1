function Copy-SPIdentity {
    <#
    .SYNOPSIS
        Create the identities from a reviewed map in the DESTINATION tenant: users, guests
        (by invitation), security groups, and M365 groups — then sync group rosters.
        Dry-run by default. Cross-tenant identity copy (Entra ID users & groups).
    .DESCRIPTION
        Step 4 of the identity-copy pipeline (docs/14). Refuses to start while
        Test-SPIdentityMap still reports Errors (override with -SkipValidation at your own
        risk). Creation runs in dependency order (users/guests, security groups, M365
        groups), then the membership pass adds owners/members that are missing — re-runs
        converge instead of duplicating.

        HANDOVER — what does NOT migrate, by design: passwords, MFA registrations, and
        licenses. Users are created with a cryptographically random throwaway password
        (never shown or stored, force-change-at-next-sign-in) and DISABLED by default —
        after cutover, assign licenses, issue Temporary Access Passes, and enable accounts
        (or create them enabled with -EnableAccounts).

        Needs Graph write scopes at the destination: User.ReadWrite.All,
        Group.ReadWrite.All, User.Invite.All (guests). See docs/02 and docs/14.
    .PARAMETER MapCsv
        The reviewed map CSV (from New-SPIdentityMap -Path, then your edits).
    .PARAMETER InventoryCsv
        Optional: the inventory CSV (from Get-SPIdentityInventory -Path). Enables the
        membership pass — without it, group rosters are not synced.
    .PARAMETER DestinationConnection
        Optional PnP connection to the DESTINATION tenant; defaults to the current connection.
    .PARAMETER EnableAccounts
        Create users enabled. Default: disabled, for a controlled cutover.
    .PARAMETER SendInvitations
        Send guests the standard invitation email. Default: invite silently.
    .PARAMETER SkipValidation
        Skip the fail-closed Test-SPIdentityMap re-run. Not recommended.
    .PARAMETER PrincipalMapPath
        Write a Source,Destination principal-map CSV consumable by
        Copy-SPPermissions -MappingCsv (users by UPN; groups by object id).
    .PARAMETER Force
        Skip the confirmation prompt (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the report as a JSON array.
    .EXAMPLE
        Copy-SPIdentity -MapCsv .\identity-map.csv -DestinationConnection $dst -WhatIf
    .EXAMPLE
        Copy-SPIdentity -MapCsv .\identity-map.csv -InventoryCsv .\contoso-identities.csv -DestinationConnection $dst -PrincipalMapPath .\principal-map.csv -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$MapCsv,
        [string]$InventoryCsv,
        [object]$DestinationConnection,
        [switch]$EnableAccounts,
        [switch]$SendInvitations,
        [switch]$SkipValidation,
        [string]$PrincipalMapPath,
        [switch]$Force,
        [switch]$AsJson
    )

    if (-not (Test-Path -LiteralPath $MapCsv)) { throw "Map CSV not found: $MapCsv" }
    $map = @(Import-Csv -LiteralPath $MapCsv)
    if (-not $map.Count) { throw 'The identity map is empty - nothing to copy.' }

    $connArg = @{}; if ($DestinationConnection) { $connArg['Connection'] = $DestinationConnection }
    Write-SPLog "Copy-SPIdentity: $($map.Count) map row(s) (EnableAccounts=$([bool]$EnableAccounts), WhatIf=$($WhatIfPreference))"

    # Destination snapshot: validation + membership deltas share it.
    $destUsers = @(Invoke-SPGraph -Method GET -Url 'v1.0/users?$select=id,userPrincipalName,mail&$top=999' -All @connArg)
    $destGroups = @(Invoke-SPGraph -Method GET -Url 'v1.0/groups?$select=id,displayName,mailNickname&$top=999' -All @connArg)

    # Fail closed: never create into a map that still validates with errors.
    if (-not $SkipValidation) {
        $org = Invoke-SPGraph -Method GET -Url 'v1.0/organization?$select=verifiedDomains' -All @connArg
        $verifiedDomains = @($org | ForEach-Object { @($_.verifiedDomains) } | ForEach-Object { "$($_.name)" } | Where-Object { $_ })
        $findings = @(Test-SPIdentityConflict -MapRow $map -DestUsers $destUsers -DestGroups $destGroups -VerifiedDomains $verifiedDomains)
        $bad = @($findings | Where-Object Status -eq 'Error')
        if ($bad.Count) {
            throw "The identity map has $($bad.Count) validation error(s) - run Test-SPIdentityMap and fix them first. First: [$($bad[0].SourceUpn)] $($bad[0].Issues)"
        }
    }

    $plan = @(Get-SPIdentityPlan -MapRow $map)
    $results = [System.Collections.Generic.List[object]]::new()

    # Source→destination lookups, seeded from Action=Map rows and grown by each creation.
    $destIdBySourceId = @{}
    $targetUpnBySourceUpn = @{}
    $destUserIdByUpn = @{}
    foreach ($u in $destUsers) { $k = "$($u.userPrincipalName)".ToLowerInvariant(); if ($k) { $destUserIdByUpn[$k] = "$($u.id)" } }
    foreach ($r in $map) {
        if ("$($r.Action)" -eq 'Map' -and "$($r.MatchedExistingId)") {
            $destIdBySourceId["$($r.SourceId)"] = "$($r.MatchedExistingId)"
            if ("$($r.SourceUpn)" -and "$($r.TargetUpn)") { $targetUpnBySourceUpn["$($r.SourceUpn)".ToLowerInvariant()] = "$($r.TargetUpn)" }
        }
    }

    # Cryptographically random throwaway password — never stored, never emitted. The '!Aa1'
    # suffix guarantees every complexity class; force-change invalidates it at first sign-in.
    $newPassword = {
        $bytes = [byte[]]::new(24)
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
        [Convert]::ToBase64String($bytes) + '!Aa1'
    }

    if ($Force) { $ConfirmPreference = 'None' }   # -Force skips the prompt; -WhatIf must still override

    # ---- Creation phases (users/guests -> security groups -> M365 groups) ----
    foreach ($row in $plan) {
        $type = "$($row.Type)"
        $action = "$($row.Action)"
        $name = if ("$($row.TargetUpn)") { "$($row.TargetUpn)" } else { "$($row.SourceDisplayName)" }

        if (-not $PSCmdlet.ShouldProcess($name, "$action $type in destination tenant")) {
            $results.Add((New-SPCopyResult -ObjectType $type -Name $name -Action $action -Status 'WouldCopy' -Detail $(
                        if ($type -eq 'User') { "Would create $(if ($EnableAccounts) { 'ENABLED' } else { 'disabled' }), random throwaway password" }
                        elseif ($action -eq 'Invite') { "Would invite $(if ($SendInvitations) { 'with' } else { 'without' }) invitation mail" }
                        else { 'Would create' })))
            continue
        }

        try {
            $newId = $null
            switch ($type) {
                'User' {
                    $nickname = "$($row.TargetMailNickname)"
                    if (-not $nickname) { $nickname = ("$($row.TargetUpn)" -split '@')[0] -replace '[^A-Za-z0-9]', '' }
                    $body = @{
                        accountEnabled    = [bool]$EnableAccounts
                        displayName       = "$($row.SourceDisplayName)"
                        mailNickname      = $nickname
                        userPrincipalName = "$($row.TargetUpn)"
                        passwordProfile   = @{ forceChangePasswordNextSignIn = $true; password = (& $newPassword) }
                    }
                    if ("$($row.UsageLocation)") { $body['usageLocation'] = "$($row.UsageLocation)" }
                    $created = Invoke-SPGraph -Method POST -Url 'v1.0/users' -Body $body @connArg
                    $newId = "$($created.id)"
                    $results.Add((New-SPCopyResult -ObjectType 'User' -Name "$($row.TargetUpn)" -Action 'Create' -Status 'Success' -Detail "Created $(if ($EnableAccounts) { 'ENABLED' } else { 'disabled (enable after cutover)' })"))
                }
                'Guest' {
                    $body = @{
                        invitedUserEmailAddress = "$($row.SourceMail)"
                        inviteRedirectUrl       = 'https://myapps.microsoft.com'
                        sendInvitationMessage   = [bool]$SendInvitations
                    }
                    $created = Invoke-SPGraph -Method POST -Url 'v1.0/invitations' -Body $body @connArg
                    $newId = "$($created.invitedUser.id)"
                    $results.Add((New-SPCopyResult -ObjectType 'Guest' -Name "$($row.SourceMail)" -Action 'Invite' -Status 'Success' -Detail "Invited$(if (-not $SendInvitations) { ' (no mail sent)' })"))
                }
                'SecurityGroup' {
                    $body = @{
                        displayName     = "$($row.SourceDisplayName)"
                        mailNickname    = "$($row.TargetMailNickname)"
                        mailEnabled     = $false
                        securityEnabled = $true
                    }
                    $created = Invoke-SPGraph -Method POST -Url 'v1.0/groups' -Body $body @connArg
                    $newId = "$($created.id)"
                    $results.Add((New-SPCopyResult -ObjectType 'SecurityGroup' -Name "$($row.SourceDisplayName)" -Action 'Create' -Status 'Success' -Detail 'Created'))
                }
                'M365Group' {
                    $body = @{
                        displayName     = "$($row.SourceDisplayName)"
                        mailNickname    = "$($row.TargetMailNickname)"
                        mailEnabled     = $true
                        securityEnabled = $false
                        groupTypes      = @('Unified')
                        visibility      = 'Private'
                    }
                    $created = Invoke-SPGraph -Method POST -Url 'v1.0/groups' -Body $body @connArg
                    $newId = "$($created.id)"
                    $results.Add((New-SPCopyResult -ObjectType 'M365Group' -Name "$($row.SourceDisplayName)" -Action 'Create' -Status 'Success' -Detail 'Created (Private)'))
                }
            }
            if ($newId) {
                $destIdBySourceId["$($row.SourceId)"] = $newId
                if ("$($row.SourceUpn)") {
                    $targetUpnBySourceUpn["$($row.SourceUpn)".ToLowerInvariant()] = "$($row.TargetUpn)"
                    $destUserIdByUpn["$($row.TargetUpn)".ToLowerInvariant()] = $newId
                }
            }
        }
        catch {
            $results.Add((New-SPCopyResult -ObjectType $type -Name $name -Action $action -Status 'Error' -Detail $_.Exception.Message))
        }
    }

    # ---- Membership pass: source rosters, remapped, added where missing (convergent) ----
    if ($InventoryCsv) {
        if (-not (Test-Path -LiteralPath $InventoryCsv)) { throw "Inventory CSV not found: $InventoryCsv" }
        $groupRows = @(Import-Csv -LiteralPath $InventoryCsv | Where-Object {
                "$($_.Supported)" -notin 'False', '0' -and "$($_.Type)" -in 'SecurityGroup', 'M365Group' -and ("$($_.Owners)" -or "$($_.Members)")
            })
        foreach ($g in $groupRows) {
            $destGroupId = $destIdBySourceId["$($g.Id)"]
            $gName = "$($g.DisplayName)"
            if (-not $destGroupId) {
                $results.Add((New-SPCopyResult -ObjectType 'Membership' -Name $gName -Action 'Skip' -Status 'Skipped' -Detail 'Group was not created or mapped - roster not synced'))
                continue
            }

            foreach ($kind in 'Members', 'Owners') {
                $sourceUpns = @("$($g.$kind)" -split ';' | Where-Object { $_ })
                if (-not $sourceUpns.Count) { continue }

                # Remap source UPNs -> destination UPNs; count what has no mapping.
                $mapped = [System.Collections.Generic.List[string]]::new()
                $unmapped = 0
                foreach ($u in $sourceUpns) {
                    $t = $targetUpnBySourceUpn[$u.ToLowerInvariant()]
                    if ($t) { $mapped.Add($t) } else { $unmapped++ }
                }

                if (-not $PSCmdlet.ShouldProcess($gName, "Sync $($mapped.Count) $($kind.ToLowerInvariant()) (+$unmapped unmapped)")) {
                    $results.Add((New-SPCopyResult -ObjectType 'Membership' -Name "$gName ($kind)" -Action 'Create' -Status 'WouldCopy' -Detail "Would add up to $($mapped.Count); $unmapped unmapped"))
                    continue
                }

                try {
                    $refPath = if ($kind -eq 'Owners') { 'owners' } else { 'members' }
                    $current = @(Invoke-SPGraph -Method GET -Url "v1.0/groups/$destGroupId/$refPath`?`$select=userPrincipalName&`$top=999" -All @connArg |
                            ForEach-Object { "$($_.userPrincipalName)" } | Where-Object { $_ })
                    $toAdd = @(Get-SPMembershipDelta -SourceMember $mapped -DestMember $current)
                    $added = 0
                    $failed = 0
                    foreach ($upn in $toAdd) {
                        $uid = $destUserIdByUpn[$upn.ToLowerInvariant()]
                        if (-not $uid) { $failed++; continue }
                        try {
                            Invoke-SPGraph -Method POST -Url "v1.0/groups/$destGroupId/$refPath/`$ref" -Body @{
                                '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$uid"
                            } @connArg | Out-Null
                            $added++
                        }
                        catch { $failed++; Write-SPLog "Could not add $upn to $gName ($kind): $($_.Exception.Message)" -Level Warn }
                    }
                    $status = if ($failed -or $unmapped) { 'Warning' } else { 'Success' }
                    $results.Add((New-SPCopyResult -ObjectType 'Membership' -Name "$gName ($kind)" -Action 'Create' -Status $status -Detail "Added $added; already present $($mapped.Count - $toAdd.Count); failed $failed; unmapped $unmapped"))
                }
                catch {
                    $results.Add((New-SPCopyResult -ObjectType 'Membership' -Name "$gName ($kind)" -Action 'Create' -Status 'Error' -Detail $_.Exception.Message))
                }
            }
        }
    }

    # ---- Principal map for Copy-SPPermissions (users by UPN, groups by object id) ----
    if ($PrincipalMapPath) {
        $pairs = [System.Collections.Generic.List[object]]::new()
        foreach ($r in $map) {
            if ("$($r.Action)" -eq 'Skip') { continue }
            if ("$($r.Type)" -in 'User', 'Guest') {
                if ("$($r.SourceUpn)" -and "$($r.TargetUpn)") {
                    $pairs.Add([pscustomobject]@{ Source = "$($r.SourceUpn)"; Destination = "$($r.TargetUpn)" })
                }
            }
            else {
                $destId = $destIdBySourceId["$($r.SourceId)"]
                if ("$($r.SourceId)" -and $destId) {
                    $pairs.Add([pscustomobject]@{ Source = "$($r.SourceId)"; Destination = $destId })
                }
            }
        }
        if ($PSCmdlet.ShouldProcess($PrincipalMapPath, "Write principal map ($($pairs.Count) pair(s))")) {
            $pairs | Export-Csv -Path $PrincipalMapPath -NoTypeInformation -Encoding utf8
            Write-SPLog "Principal map written for Copy-SPPermissions -MappingCsv: $PrincipalMapPath" -Level Success
        }
    }

    $errors = @($results | Where-Object Status -eq 'Error').Count
    $created = @($results | Where-Object { $_.Status -eq 'Success' -and $_.ObjectType -ne 'Membership' }).Count
    Write-SPLog ("Copy-SPIdentity complete: {0} row(s), {1} identit(ies) created/invited, {2} error(s)." -f $results.Count, $created, $errors) -Level $(if ($errors) { 'Warn' } else { 'Success' })
    if ($created -and -not $EnableAccounts) {
        Write-SPLog 'HANDOVER: new users are DISABLED with throwaway passwords. Passwords, MFA, and licenses do not migrate - assign licenses, issue Temporary Access Passes, then enable the accounts.' -Level Warn
    }
    $results | ConvertTo-SPOutput -AsJson:$AsJson
}
