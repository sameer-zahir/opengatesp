function ConvertTo-SPIdentityMapRow {
    <#
    .SYNOPSIS
        Turn one identity-inventory row into a reviewable mapping proposal against a
        destination-directory snapshot. Pure — no I/O.
    .DESCRIPTION
        The heart of New-SPIdentityMap. For users it proposes local-part@DomainTo and matches
        existing destination identities — by mail first (most reliable across tenants), then by
        UPN local part — emitting Action=Map with the match's id when found, Action=Create
        otherwise. Guests default to Skip (opt in with -IncludeGuests to propose Action=Invite).
        Groups match by mail nickname, then display name. Unsupported inventory rows
        (distribution lists, mail-enabled security groups) become Action=Skip.

        The output row is the map-CSV schema users hand-edit before Test-SPIdentityMap /
        Copy-SPIdentity consume it: Type, SourceId, SourceUpn, SourceDisplayName, SourceMail,
        UsageLocation, TargetUpn, TargetMailNickname, Action, MatchedExistingId, Notes.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$InventoryRow,
        [Parameter(Mandatory)][string]$DomainTo,
        [object[]]$DestUsers,
        [object[]]$DestGroups,
        [switch]$IncludeGuests
    )

    $type = "$($InventoryRow.Type)"
    $mail = "$($InventoryRow.Mail)"
    $upn = "$($InventoryRow.UserPrincipalName)"
    # CSV round-trips booleans as strings, so 'False' must read as unsupported.
    $supported = "$($InventoryRow.Supported)" -notin 'False', '0'

    $row = [ordered]@{
        Type               = $type
        SourceId           = "$($InventoryRow.Id)"
        SourceUpn          = $upn
        SourceDisplayName  = "$($InventoryRow.DisplayName)"
        SourceMail         = $mail
        UsageLocation      = "$($InventoryRow.UsageLocation)"
        TargetUpn          = ''
        TargetMailNickname = "$($InventoryRow.MailNickname)"
        Action             = 'Skip'
        MatchedExistingId  = ''
        Notes              = "$($InventoryRow.Notes)"
    }

    if (-not $supported) {
        return [pscustomobject]$row
    }

    if ($type -in 'User', 'Guest') {
        if ($type -eq 'Guest' -and -not $IncludeGuests) {
            $row.Notes = 'Guests are skipped by default - re-run New-SPIdentityMap with -IncludeGuests, or edit Action to Invite.'
            return [pscustomobject]$row
        }

        # Match by mail first (survives UPN renames), then by UPN local part.
        $match = $null
        if ($mail) {
            $match = @($DestUsers | Where-Object { "$($_.mail)" -and ("$($_.mail)" -ieq $mail) }) | Select-Object -First 1
        }
        if (-not $match -and $upn -and $upn -notmatch '#EXT#') {
            $local = ($upn -split '@')[0]
            $match = @($DestUsers | Where-Object { ("$($_.userPrincipalName)" -split '@')[0] -ieq $local }) | Select-Object -First 1
        }

        if ($match) {
            $row.Action = 'Map'
            $row.MatchedExistingId = "$($match.id)"
            $row.TargetUpn = "$($match.userPrincipalName)"
            $row.Notes = "Matched existing destination user$(if ($mail -and ("$($match.mail)" -ieq $mail)) { ' by mail' } else { ' by UPN local part' })."
        }
        elseif ($type -eq 'Guest') {
            $row.Action = 'Invite'
            $row.TargetUpn = $mail   # invitations go to the guest's email
            if (-not $mail) { $row.Notes = 'Guest has no mail address to invite.' }
        }
        else {
            $row.Action = 'Create'
            $row.TargetUpn = (($upn -split '@')[0]) + '@' + $DomainTo
        }
        return [pscustomobject]$row
    }

    # Groups: match by mail nickname first, then display name.
    $nickname = "$($InventoryRow.MailNickname)"
    $display = "$($InventoryRow.DisplayName)"
    $match = $null
    if ($nickname) {
        $match = @($DestGroups | Where-Object { "$($_.mailNickname)" -ieq $nickname }) | Select-Object -First 1
    }
    if (-not $match -and $display) {
        $match = @($DestGroups | Where-Object { "$($_.displayName)" -ieq $display }) | Select-Object -First 1
    }

    if ($match) {
        $row.Action = 'Map'
        $row.MatchedExistingId = "$($match.id)"
        $row.TargetMailNickname = "$($match.mailNickname)"
        $row.Notes = 'Matched existing destination group.'
    }
    else {
        $row.Action = 'Create'
        if (-not $nickname -and $display) {
            # Derive a nickname the way M365 would: alphanumerics only, lower case.
            $row.TargetMailNickname = ($display -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
        }
    }
    [pscustomobject]$row
}
