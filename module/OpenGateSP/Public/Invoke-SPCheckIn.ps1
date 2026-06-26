function Invoke-SPCheckIn {
    <#
    .SYNOPSIS
        Bulk check-in the files left checked out in a site's document libraries — clears a common
        migration blocker. Dry-run by default.
    .DESCRIPTION
        Finds checked-out files (via Get-SPCheckedOutFiles) and checks each one in with a major
        version. Dry-run by default: it lists what it would check in and writes nothing until you
        pass -Force (or confirm the prompt). Respects -WhatIf.
    .PARAMETER SiteUrl
        The site to act on. Connected automatically.
    .PARAMETER Library
        Limit to a single library (display name). Default: all document libraries.
    .PARAMETER Comment
        Check-in comment. Default 'Checked in by OpenGateSP'.
    .PARAMETER Force
        Apply without the confirmation prompt (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the result rows as JSON.
    .EXAMPLE
        Invoke-SPCheckIn -SiteUrl https://contoso.sharepoint.com/sites/Marketing -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [string]$Library,
        [string]$Comment = 'Checked in by OpenGateSP',
        [switch]$Force,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    $coParams = @{ SiteUrl = $SiteUrl }
    if ($Library) { $coParams['Library'] = $Library }
    $files = @(Get-SPCheckedOutFiles @coParams)
    Write-SPLog "Invoke-SPCheckIn: $($files.Count) checked-out file(s) found (check-in comment: '$Comment')."

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $files) {
        $ref = $f.FileRef
        if (-not $Force -and -not $PSCmdlet.ShouldProcess($ref, 'Check in file')) {
            $rows.Add((New-SPCopyResult -ObjectType 'File' -Name $ref -Action 'Overwrite' -Status 'WouldCopy' -Detail "Would check in (was: $($f.CheckedOutTo))"))
            continue
        }
        try {
            Invoke-SPRetry -Operation "check in $ref" {
                Set-PnPFileCheckedIn -Url $ref -Comment $Comment -CheckinType MajorCheckIn -ErrorAction Stop
            } | Out-Null
            $rows.Add((New-SPCopyResult -ObjectType 'File' -Name $ref -Action 'Overwrite' -Status 'Success' -Detail 'Checked in'))
        }
        catch {
            $rows.Add((New-SPCopyResult -ObjectType 'File' -Name $ref -Action 'Overwrite' -Status 'Error' -Detail $_.Exception.Message))
        }
    }

    $rows | ConvertTo-SPOutput -AsJson:$AsJson
}
