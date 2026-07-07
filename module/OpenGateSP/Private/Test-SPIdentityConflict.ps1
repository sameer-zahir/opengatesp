function Test-SPIdentityConflict {
    <#
    .SYNOPSIS
        Validate an (edited) identity map against a destination-directory snapshot: UPN and
        nickname collisions, unverified domains, vanished matches, unsupported creates.
        Pure — no I/O.
    .DESCRIPTION
        The rule engine behind Test-SPIdentityMap (and Copy-SPIdentity's fail-closed
        re-validation). Emits one finding per map row with Status OK | Warning | Error and the
        joined issue text; any Error should block Copy-SPIdentity.

        Errors: Create-user with an empty/duplicate/existing target UPN or an unverified
        domain; Create on an unsupported type (DL / mail-enabled security); Invite without a
        mail address; Map without a MatchedExistingId or whose match no longer exists;
        Create-group with an empty/colliding/duplicate mail nickname; unknown Action.
        Warnings: Create-user without a UsageLocation (license assignment will fail later);
        an empty verified-domain list (domain checks impossible — surfaced, not assumed OK).
    .PARAMETER MapRow
        The map rows (from New-SPIdentityMap, possibly hand-edited).
    .PARAMETER DestUsers
        Destination users snapshot (objects with id, userPrincipalName, mail).
    .PARAMETER DestGroups
        Destination groups snapshot (objects with id, displayName, mailNickname).
    .PARAMETER VerifiedDomains
        The destination tenant's verified domain names.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [object[]]$MapRow,
        [object[]]$DestUsers,
        [object[]]$DestGroups,
        [string[]]$VerifiedDomains
    )

    # Lookups for collision checks.
    $destUpns = @{}
    foreach ($u in @($DestUsers)) { $k = "$($u.userPrincipalName)".ToLowerInvariant(); if ($k) { $destUpns[$k] = $true } }
    $destNicknames = @{}
    foreach ($g in @($DestGroups)) { $k = "$($g.mailNickname)".ToLowerInvariant(); if ($k) { $destNicknames[$k] = $true } }
    $destIds = @{}
    foreach ($x in @($DestUsers) + @($DestGroups)) { $k = "$($x.id)"; if ($k) { $destIds[$k] = $true } }
    $domains = @{}
    foreach ($d in @($VerifiedDomains)) { if ($d) { $domains["$d".ToLowerInvariant()] = $true } }

    # Duplicates WITHIN the map (hand-edits introduce these).
    $upnCounts = @{}
    $nickCounts = @{}
    foreach ($r in @($MapRow)) {
        if ("$($r.Action)" -eq 'Create') {
            if ("$($r.Type)" -in 'User', 'Guest') {
                $k = "$($r.TargetUpn)".ToLowerInvariant()
                if ($k) { $upnCounts[$k] = 1 + [int]$upnCounts[$k] }
            }
            else {
                $k = "$($r.TargetMailNickname)".ToLowerInvariant()
                if ($k) { $nickCounts[$k] = 1 + [int]$nickCounts[$k] }
            }
        }
    }

    $findings = foreach ($r in @($MapRow)) {
        if (-not $r) { continue }
        $issues = [System.Collections.Generic.List[string]]::new()
        $warnings = [System.Collections.Generic.List[string]]::new()
        $type = "$($r.Type)"
        $action = "$($r.Action)"
        $targetUpn = "$($r.TargetUpn)"

        switch ($action) {
            'Skip' { }
            'Map' {
                if (-not "$($r.MatchedExistingId)") { $issues.Add('Action=Map requires MatchedExistingId.') }
                elseif (-not $destIds.ContainsKey("$($r.MatchedExistingId)")) { $issues.Add('The matched destination identity no longer exists.') }
            }
            'Invite' {
                if ($type -ne 'Guest') { $issues.Add("Action=Invite is only valid for guests (row is $type).") }
                elseif (-not "$($r.SourceMail)") { $issues.Add('Guest has no mail address to invite.') }
            }
            'Create' {
                if ($type -in 'DistributionList', 'MailEnabledSecurityGroup') {
                    $issues.Add('Graph cannot create this Exchange group type - recreate it in Exchange admin or convert to a Microsoft 365 Group.')
                }
                elseif ($type -in 'User', 'Guest') {
                    if (-not $targetUpn) { $issues.Add('TargetUpn is empty.') }
                    else {
                        $upnKey = $targetUpn.ToLowerInvariant()
                        $domain = ($targetUpn -split '@')[-1].ToLowerInvariant()
                        if ($destUpns.ContainsKey($upnKey)) { $issues.Add("A user with UPN $targetUpn already exists at the destination - change Action to Map.") }
                        if ($upnCounts[$upnKey] -gt 1) { $issues.Add("Duplicate target UPN in the map ($targetUpn).") }
                        if ($domains.Count -eq 0) { $warnings.Add('Verified domains unknown - the UPN domain could not be validated.') }
                        elseif (-not $domains.ContainsKey($domain)) { $issues.Add("Domain $domain is not verified at the destination tenant.") }
                    }
                    if (-not "$($r.UsageLocation)") { $warnings.Add('No UsageLocation - license assignment will fail until one is set.') }
                }
                else {
                    $nick = "$($r.TargetMailNickname)"
                    if (-not $nick) { $issues.Add('TargetMailNickname is empty.') }
                    else {
                        $nickKey = $nick.ToLowerInvariant()
                        if ($destNicknames.ContainsKey($nickKey)) { $issues.Add("A group with mail nickname $nick already exists at the destination - change Action to Map.") }
                        if ($nickCounts[$nickKey] -gt 1) { $issues.Add("Duplicate target mail nickname in the map ($nick).") }
                    }
                }
            }
            default { $issues.Add("Unknown Action '$action' (expected Create, Map, Invite, or Skip).") }
        }

        $status = if ($issues.Count) { 'Error' } elseif ($warnings.Count) { 'Warning' } else { 'OK' }
        [pscustomobject]@{
            Type              = $type
            SourceUpn         = "$($r.SourceUpn)"
            SourceDisplayName = "$($r.SourceDisplayName)"
            TargetUpn         = $targetUpn
            Action            = $action
            Status            = $status
            Issues            = ((@($issues) + @($warnings)) -join ' ')
        }
    }
    @($findings)
}
