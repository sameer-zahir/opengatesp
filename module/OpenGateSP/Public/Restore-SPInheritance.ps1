function Restore-SPInheritance {
    <#
    .SYNOPSIS
        Restore permission inheritance on a list/library (or a single item) that has broken
        inheritance — re-aligns it with the site's permissions. Dry-run by default.
    .DESCRIPTION
        Clears unique role assignments so the object inherits from its parent again. Target a
        list/library by -List, or a single item by adding -ItemId. Dry-run by default: reports the
        intended change and writes nothing until -Force (or confirmation). Respects -WhatIf. Find
        broken-inheritance objects first with Get-SPPermissionReport.
    .PARAMETER SiteUrl
        The site to act on. Connected automatically.
    .PARAMETER List
        The list/library display name.
    .PARAMETER ItemId
        Optional list item id; when given, only that item's inheritance is restored.
    .PARAMETER Force
        Apply without the confirmation prompt (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the result row as JSON.
    .EXAMPLE
        Restore-SPInheritance -SiteUrl https://contoso.sharepoint.com/sites/Marketing -List 'Documents' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][string]$List,
        [int]$ItemId,
        [switch]$Force,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    $target = if ($ItemId) { "$List item $ItemId" } else { $List }
    Write-SPLog "Restore-SPInheritance: $target on $SiteUrl"

    if (-not $Force -and -not $PSCmdlet.ShouldProcess($target, 'Restore permission inheritance')) {
        $row = New-SPCopyResult -ObjectType $(if ($ItemId) { 'Item' } else { 'List' }) -Name $target -Action 'Overwrite' -Status 'WouldCopy' -Detail 'Would restore inheritance'
        return ($row | ConvertTo-SPOutput -AsJson:$AsJson)
    }

    try {
        if ($ItemId) {
            Invoke-SPRetry -Operation "restore inheritance $target" {
                Set-PnPListItemPermission -List $List -Identity $ItemId -InheritPermissions -ErrorAction Stop
            } | Out-Null
        }
        else {
            Invoke-SPRetry -Operation "restore inheritance $target" {
                $l = Get-PnPList -Identity $List -ErrorAction Stop
                $l.ResetRoleInheritance()
                Invoke-PnPQuery
            } | Out-Null
        }
        $row = New-SPCopyResult -ObjectType $(if ($ItemId) { 'Item' } else { 'List' }) -Name $target -Action 'Overwrite' -Status 'Success' -Detail 'Inheritance restored'
    }
    catch {
        $row = New-SPCopyResult -ObjectType $(if ($ItemId) { 'Item' } else { 'List' }) -Name $target -Action 'Overwrite' -Status 'Error' -Detail $_.Exception.Message
    }

    $row | ConvertTo-SPOutput -AsJson:$AsJson
}
