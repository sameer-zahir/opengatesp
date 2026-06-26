function Remove-SPOrphanedUsers {
    <#
    .SYNOPSIS
        Remove users who still have access to a site but no longer exist in the directory
        (stale-access cleanup). Dry-run by default.
    .DESCRIPTION
        Finds orphaned users (via Get-SPOrphanedUsers — needs Graph User.Read.All) and removes each
        from the site's user list. Dry-run by default: lists who it would remove and writes nothing
        until -Force (or confirmation). Respects -WhatIf. Run Get-SPOrphanedUsers first to review.
    .PARAMETER SiteUrl
        The site to clean. Connected automatically.
    .PARAMETER Force
        Apply without the confirmation prompt (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the result rows as JSON.
    .EXAMPLE
        Remove-SPOrphanedUsers -SiteUrl https://contoso.sharepoint.com/sites/Marketing -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [switch]$Force,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    $orphans = @(Get-SPOrphanedUsers -SiteUrl $SiteUrl)
    Write-SPLog "Remove-SPOrphanedUsers: $($orphans.Count) orphaned user(s) found."

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($o in $orphans) {
        $login = $o.LoginName
        if (-not $Force -and -not $PSCmdlet.ShouldProcess($login, 'Remove user from site')) {
            $rows.Add((New-SPCopyResult -ObjectType 'Item' -Name $login -Action 'Skip' -Status 'WouldCopy' -Detail "Would remove ($($o.Title))"))
            continue
        }
        try {
            Invoke-SPRetry -Operation "remove user $login" {
                Remove-PnPUser -Identity $login -Force -ErrorAction Stop
            } | Out-Null
            $rows.Add((New-SPCopyResult -ObjectType 'Item' -Name $login -Action 'Skip' -Status 'Success' -Detail 'Removed'))
        }
        catch {
            $rows.Add((New-SPCopyResult -ObjectType 'Item' -Name $login -Action 'Skip' -Status 'Error' -Detail $_.Exception.Message))
        }
    }

    $rows | ConvertTo-SPOutput -AsJson:$AsJson
}
