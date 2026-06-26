function Set-SPSiteLifecycle {
    <#
    .SYNOPSIS
        Lock, make read-only, or unlock a site — the lifecycle/archive control for a governance
        workflow. Dry-run by default.
    .DESCRIPTION
        Sets the site's lock state via Set-PnPTenantSite: `ReadOnly` to archive a site without
        deleting it, `NoAccess` to fully lock it, or `Unlock` to restore. Requires a
        **SharePoint admin** connection (connect with -Admin). Dry-run by default — it reports
        the intended change and writes nothing until you confirm or pass -Force.
    .PARAMETER SiteUrl
        The site collection URL.
    .PARAMETER LockState
        Unlock, ReadOnly, or NoAccess.
    .PARAMETER Force
        Apply without the confirmation prompt (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the report row as JSON.
    .EXAMPLE
        Set-SPSiteLifecycle -SiteUrl https://contoso.sharepoint.com/sites/Old -LockState ReadOnly -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][ValidateSet('Unlock', 'ReadOnly', 'NoAccess')][string]$LockState,
        [switch]$Force,
        [switch]$AsJson
    )

    Write-SPLog "Set-SPSiteLifecycle: $SiteUrl -> $LockState (WhatIf=$($WhatIfPreference))"

    if (-not $Force -and -not $PSCmdlet.ShouldProcess($SiteUrl, "Set lock state to $LockState")) {
        $row = New-SPCopyResult -ObjectType 'SiteLifecycle' -Name $SiteUrl -Action 'Overwrite' -Status 'WouldCopy' -Detail "Would set LockState=$LockState"
        return ($row | ConvertTo-SPOutput -AsJson:$AsJson)
    }

    try {
        Invoke-SPRetry -Operation "set lock $LockState" { Set-PnPTenantSite -Identity $SiteUrl -LockState $LockState -ErrorAction Stop } | Out-Null
        $row = New-SPCopyResult -ObjectType 'SiteLifecycle' -Name $SiteUrl -Action 'Overwrite' -Status 'Success' -Detail "LockState=$LockState"
    }
    catch {
        $row = New-SPCopyResult -ObjectType 'SiteLifecycle' -Name $SiteUrl -Action 'Overwrite' -Status 'Error' -Detail $_.Exception.Message
    }

    $row | ConvertTo-SPOutput -AsJson:$AsJson
}
