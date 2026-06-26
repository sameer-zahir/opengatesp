function Clear-SPVersionHistory {
    <#
    .SYNOPSIS
        Trim a file's version history, keeping only the newest -Keep historical versions — reduces
        migration volume and storage. Dry-run by default.
    .DESCRIPTION
        Reads the file's historical versions (Get-PnPFileVersion; the current published version is
        never touched) and deletes the oldest beyond -Keep. Dry-run by default: lists what it would
        remove and writes nothing until -Force (or confirmation). Respects -WhatIf. The decision of
        which versions to drop is the unit-tested Select-SPVersionsToTrim.
    .PARAMETER SiteUrl
        The site the file lives on. Connected automatically.
    .PARAMETER FileUrl
        Server-relative URL of the file, e.g. /sites/Marketing/Shared Documents/big.pptx.
    .PARAMETER Keep
        How many of the newest historical versions to retain. Default 10.
    .PARAMETER Force
        Apply without the confirmation prompt (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the result rows as JSON.
    .EXAMPLE
        Clear-SPVersionHistory -SiteUrl https://contoso.sharepoint.com/sites/Marketing -FileUrl '/sites/Marketing/Shared Documents/big.pptx' -Keep 5 -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][string]$FileUrl,
        [int]$Keep = 10,
        [switch]$Force,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    $versions = @(Invoke-SPRetry -Operation "versions $FileUrl" { Get-PnPFileVersion -Url $FileUrl -ErrorAction Stop })
    $toRemove = @(Select-SPVersionsToTrim -Version $versions -Keep $Keep)
    Write-SPLog "Clear-SPVersionHistory: $($versions.Count) version(s), $($toRemove.Count) to trim (keep $Keep)."

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($v in $toRemove) {
        $label = "$FileUrl (v$($v.VersionLabel))"
        if (-not $Force -and -not $PSCmdlet.ShouldProcess($label, 'Delete version')) {
            $rows.Add((New-SPCopyResult -ObjectType 'File' -Name $label -Action 'Skip' -Status 'WouldCopy' -Detail 'Would delete version'))
            continue
        }
        try {
            Invoke-SPRetry -Operation "remove version $label" {
                Remove-PnPFileVersion -Url $FileUrl -Identity $v.ID -Force -ErrorAction Stop
            } | Out-Null
            $rows.Add((New-SPCopyResult -ObjectType 'File' -Name $label -Action 'Skip' -Status 'Success' -Detail 'Version deleted'))
        }
        catch {
            $rows.Add((New-SPCopyResult -ObjectType 'File' -Name $label -Action 'Skip' -Status 'Error' -Detail $_.Exception.Message))
        }
    }

    $rows | ConvertTo-SPOutput -AsJson:$AsJson
}
