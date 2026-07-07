function ConvertTo-SPIdentityInventoryRow {
    <#
    .SYNOPSIS
        Shape a raw Graph user or group into one identity-inventory row, classifying the
        type and whether OpenGateSP can recreate it at a destination tenant. Pure — no I/O.
    .DESCRIPTION
        Users become User or Guest rows (guests by userType or the #EXT# UPN marker). Groups
        classify from their Graph flags: groupTypes 'Unified' -> M365Group; security-only ->
        SecurityGroup; mail-enabled security groups and classic distribution lists are
        enumerated but marked Supported=$false — Microsoft Graph cannot create them (Exchange
        objects); they must be recreated in Exchange admin or converted to M365 Groups.
        One flat, CSV-friendly schema for both kinds (Owners/Members are ';'-joined UPNs).
    #>
    [CmdletBinding(DefaultParameterSetName = 'User')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'User')][object]$User,
        [Parameter(Mandatory, ParameterSetName = 'Group')][object]$Group,
        [Parameter(ParameterSetName = 'Group')][string[]]$Owners,
        [Parameter(ParameterSetName = 'Group')][string[]]$Members
    )

    if ($PSCmdlet.ParameterSetName -eq 'User') {
        $upn = "$($User.userPrincipalName)"
        $isGuest = ("$($User.userType)" -eq 'Guest') -or ($upn -match '#EXT#')
        return [pscustomobject]@{
            Type              = $(if ($isGuest) { 'Guest' } else { 'User' })
            Id                = "$($User.id)"
            UserPrincipalName = $upn
            DisplayName       = "$($User.displayName)"
            Mail              = "$($User.mail)"
            MailNickname      = "$($User.mailNickname)"
            AccountEnabled    = [bool]$User.accountEnabled
            UsageLocation     = "$($User.usageLocation)"
            Supported         = $true
            Notes             = ''
            Owners            = ''
            Members           = ''
        }
    }

    $isUnified = @($Group.groupTypes) -contains 'Unified'
    $mailOn = [bool]$Group.mailEnabled
    $secOn = [bool]$Group.securityEnabled
    $type = if ($isUnified) { 'M365Group' }
    elseif ($secOn -and -not $mailOn) { 'SecurityGroup' }
    elseif ($secOn -and $mailOn) { 'MailEnabledSecurityGroup' }
    else { 'DistributionList' }
    $supported = $type -in 'M365Group', 'SecurityGroup'
    $notes = if ($supported) { '' } else {
        'Graph cannot create this Exchange group type - recreate it in Exchange admin or convert to a Microsoft 365 Group.'
    }

    [pscustomobject]@{
        Type              = $type
        Id                = "$($Group.id)"
        UserPrincipalName = ''
        DisplayName       = "$($Group.displayName)"
        Mail              = "$($Group.mail)"
        MailNickname      = "$($Group.mailNickname)"
        AccountEnabled    = $true
        UsageLocation     = ''
        Supported         = $supported
        Notes             = $notes
        Owners            = (@($Owners | Where-Object { $_ }) -join ';')
        Members           = (@($Members | Where-Object { $_ }) -join ';')
    }
}
