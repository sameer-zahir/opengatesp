function Copy-SPList {
    <#
    .SYNOPSIS
        Copy a single list or library — its schema, and optionally its content — to another
        site in the SAME tenant. The granular building block behind Copy-SPSite.
    .DESCRIPTION
        Connects to both sites, extracts a provisioning template scoped to just this one list
        (so the destination gets only its columns, content types, and views — not the whole
        site), applies it, and — when -IncludeContent is set — copies the items (or, for a
        library, the files and folders with their timestamps).

        SAFETY: dry-run by default. It returns the plan and writes nothing until you confirm
        (or pass -Force). SCOPE: same-tenant only — see docs/07-sharepoint-migration.md.
    .PARAMETER SourceUrl
        The site that holds the list to copy from.
    .PARAMETER DestinationUrl
        The site to copy the list into (same tenant).
    .PARAMETER List
        The display name of the list or library to copy.
    .PARAMETER IncludeContent
        Also copy items (lists) or files + folders (libraries). Default: schema only.
    .PARAMETER ConflictMode
        What to do if the list already exists at the destination: Replace, Skip, KeepBoth,
        or IfNewer (default).
    .PARAMETER Force
        Skip the confirmation and perform the copy (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the migration report as a JSON array.
    .EXAMPLE
        Copy-SPList -SourceUrl https://contoso.sharepoint.com/sites/A -DestinationUrl https://contoso.sharepoint.com/sites/B -List "Documents" -WhatIf
    .EXAMPLE
        Copy-SPList -SourceUrl .../sites/A -DestinationUrl .../sites/B -List "Tasks" -IncludeContent
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SourceUrl,
        [Parameter(Mandatory)][string]$DestinationUrl,
        [Parameter(Mandatory)][string]$List,
        [switch]$IncludeContent,
        [ValidateSet('Replace', 'Skip', 'KeepBoth', 'IfNewer')][string]$ConflictMode = 'IfNewer',
        [switch]$Force,
        [switch]$AsJson
    )

    if ($SourceUrl.TrimEnd('/') -ieq $DestinationUrl.TrimEnd('/')) { throw 'Source and destination are the same site.' }

    Write-SPLog "Copy-SPList: '$List' $SourceUrl -> $DestinationUrl (content=$IncludeContent, mode=$ConflictMode, WhatIf=$($WhatIfPreference))"

    # Two connections in the same tenant.
    $srcParams = Get-SPConnectParams -Url $SourceUrl
    $dstParams = Get-SPConnectParams -Url $DestinationUrl
    $src = Invoke-SPRetry -Operation 'connect source' { Connect-PnPOnline @srcParams -ReturnConnection }
    $dst = Invoke-SPRetry -Operation 'connect destination' { Connect-PnPOnline @dstParams -ReturnConnection }

    $srcList = Get-PnPList -Identity $List -Connection $src -ErrorAction SilentlyContinue
    if (-not $srcList) { throw "List '$List' was not found on the source site." }
    $dstList = Get-PnPList -Identity $List -Connection $dst -ErrorAction SilentlyContinue

    $isLib   = $srcList.BaseType -eq 'DocumentLibrary'
    $objType = if ($isLib) { 'Library' } else { 'List' }

    # Build a one-object plan with the pure planner (same conflict semantics as Copy-SPSite).
    $srcObj  = [pscustomobject]@{ Name = $srcList.Title; ObjectType = $objType; Modified = $srcList.LastItemUserModifiedDate }
    $dstObjs = @()
    if ($dstList) { $dstObjs = @([pscustomobject]@{ Name = $dstList.Title; Modified = $dstList.LastItemUserModifiedDate }) }
    $plan = @(Get-SPCopyPlan -SourceObjects @($srcObj) -DestObjects $dstObjs -Mode $ConflictMode)

    # Dry-run: return the plan, write nothing.
    if (-not $Force -and -not $PSCmdlet.ShouldProcess($DestinationUrl, "Copy $objType '$List' from $SourceUrl")) {
        Write-SPLog "Dry-run: $objType '$List' -> $($plan[0].Action)." -Level Success
        return ($plan | ConvertTo-SPOutput -AsJson:$AsJson)
    }

    $results = [System.Collections.Generic.List[object]]::new()

    # Honour a planned Skip before doing any work.
    $row = $plan | Select-Object -First 1
    if ($row -and $row.Action -eq 'Skip') {
        $results.Add((New-SPCopyResult -ObjectType $objType -Name $List -Action 'Skip' -Status 'Skipped' -Detail $row.Detail))
        return ($results | ConvertTo-SPOutput -AsJson:$AsJson)
    }

    # 1) Schema: extract a template scoped to this one list and apply it.
    try {
        $tpl = Get-SPSiteStructure -Connection $src -Lists @($List)
        Invoke-SPRetry -Operation 'apply list template' { Invoke-PnPSiteTemplate -Path $tpl.Path -Connection $dst -ErrorAction Stop } | Out-Null
        $results.Add((New-SPCopyResult -ObjectType $objType -Name $List -Action 'Overwrite' -Status 'Success' -Detail 'Schema applied'))
    }
    catch {
        $results.Add((New-SPCopyResult -ObjectType $objType -Name $List -Action 'Overwrite' -Status 'Error' -Detail $_.Exception.Message))
    }

    # 2) Content: items for a list, files + folders for a library.
    if ($IncludeContent) {
        try {
            if ($isLib) {
                Copy-SPLibraryFiles -SourceConnection $src -ListTitle $List -SourceWebUrl $SourceUrl -DestinationWebUrl $DestinationUrl -Overwrite:($ConflictMode -eq 'Replace')
                $results.Add((New-SPCopyResult -ObjectType 'Library' -Name $List -Action 'Overwrite' -Status 'Success' -Detail 'Files copied'))
            }
            else {
                $n = Copy-SPListItems -SourceConnection $src -DestinationConnection $dst -ListTitle $List
                $results.Add((New-SPCopyResult -ObjectType 'List' -Name $List -Action 'Overwrite' -Status 'Success' -Detail "$n item(s) copied"))
            }
        }
        catch {
            Write-SPLog "FAILED $objType '$List': $($_.Exception.Message)" -Level Error
            $results.Add((New-SPCopyResult -ObjectType $objType -Name $List -Action 'Overwrite' -Status 'Error' -Detail $_.Exception.Message))
        }
    }

    $errors = @($results | Where-Object Status -eq 'Error').Count
    Write-SPLog ("Copy-SPList complete: {0} step(s), {1} error(s)." -f $results.Count, $errors) -Level $(if ($errors) { 'Warn' } else { 'Success' })
    $results | ConvertTo-SPOutput -AsJson:$AsJson
}
