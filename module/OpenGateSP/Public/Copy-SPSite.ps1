function Copy-SPSite {
    <#
    .SYNOPSIS
        Copy a SharePoint site's structure (and optionally its content) to another site
        in the SAME tenant — the open equivalent of ShareGate's "Copy structure and content".
    .DESCRIPTION
        Connects to both the source and destination sites, builds a plan of what would copy
        (honouring the conflict mode), and — unless this is a dry run — applies the source's
        structure via a PnP provisioning template, then copies each list's items and each
        library's files.

        SAFETY: dry-run by default. It prints the plan and writes nothing until you confirm
        (or pass -Force). Run the plan first and read it.

        SCOPE: same-tenant only in this release. Tenant-to-tenant, full permission/identity
        mapping, version history, and managed-metadata item values are later milestones
        (see docs/07-sharepoint-migration.md for the honest limits).
    .PARAMETER SourceUrl
        The site to copy from.
    .PARAMETER DestinationUrl
        The site to copy into (in the same tenant). Pre-create it, or provision it first.
    .PARAMETER Lists
        Optional: limit the copy to these list/library display names.
    .PARAMETER IncludeContent
        Also copy list items and library files (default: structure only).
    .PARAMETER ConflictMode
        What to do when an object already exists at the destination: Replace, Skip,
        KeepBoth, or IfNewer (default).
    .PARAMETER Force
        Skip the confirmation and perform the copy (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the migration report as a JSON array.
    .EXAMPLE
        Copy-SPSite -SourceUrl https://contoso.sharepoint.com/sites/A -DestinationUrl https://contoso.sharepoint.com/sites/B -WhatIf
    .EXAMPLE
        Copy-SPSite -SourceUrl https://contoso.sharepoint.com/sites/A -DestinationUrl https://contoso.sharepoint.com/sites/B -IncludeContent
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SourceUrl,
        [Parameter(Mandatory)][string]$DestinationUrl,
        [string[]]$Lists,
        [switch]$IncludeContent,
        [ValidateSet('Replace', 'Skip', 'KeepBoth', 'IfNewer')][string]$ConflictMode = 'IfNewer',
        [switch]$CopyPermissions,
        [string]$MappingCsv,
        [string]$DomainFrom,
        [string]$DomainTo,
        [Nullable[datetime]]$Since,
        [switch]$Force,
        [switch]$AsJson
    )

    if ($SourceUrl.TrimEnd('/') -ieq $DestinationUrl.TrimEnd('/')) { throw 'Source and destination are the same site.' }

    Write-SPLog "Copy-SPSite: $SourceUrl -> $DestinationUrl (content=$IncludeContent, mode=$ConflictMode, WhatIf=$($WhatIfPreference))"

    # Two connections in the same tenant (delegated opens a browser per site the first time).
    $srcParams = Get-SPConnectParams -Url $SourceUrl
    $dstParams = Get-SPConnectParams -Url $DestinationUrl
    $src = Invoke-SPRetry -Operation 'connect source' { Connect-PnPOnline @srcParams -ReturnConnection }
    $dst = Invoke-SPRetry -Operation 'connect destination' { Connect-PnPOnline @dstParams -ReturnConnection }

    # Inventory both sides (read-only) and build the plan with the pure planner.
    $srcLists = @(Get-PnPList -Connection $src | Where-Object { -not $_.Hidden })
    if ($Lists) { $srcLists = @($srcLists | Where-Object { $_.Title -in $Lists }) }
    $dstLists = @(Get-PnPList -Connection $dst | Where-Object { -not $_.Hidden })

    $srcObjs = $srcLists | ForEach-Object {
        [pscustomobject]@{
            Name       = $_.Title
            ObjectType = $(if ($_.BaseType -eq 'DocumentLibrary') { 'Library' } else { 'List' })
            Modified   = $_.LastItemUserModifiedDate
        }
    }
    $dstObjs = $dstLists | ForEach-Object { [pscustomobject]@{ Name = $_.Title; Modified = $_.LastItemUserModifiedDate } }
    $plan = @(Get-SPCopyPlan -SourceObjects $srcObjs -DestObjects $dstObjs -Mode $ConflictMode)

    # Dry-run: return the plan, write nothing.
    if (-not $Force -and -not $PSCmdlet.ShouldProcess($DestinationUrl, "Copy $($srcLists.Count) list(s) from $SourceUrl")) {
        Write-SPLog "Dry-run: $($plan.Count) object(s) planned ($(@($plan | Where-Object Status -eq 'Skipped').Count) skipped)." -Level Success
        return ($plan | ConvertTo-SPOutput -AsJson:$AsJson)
    }

    $results = [System.Collections.Generic.List[object]]::new()

    # 1) Structure: extract the source template and apply it to the destination.
    try {
        $tpl = Get-SPSiteStructure -Connection $src
        Invoke-SPRetry -Operation 'apply site template' { Invoke-PnPSiteTemplate -Path $tpl.Path -Connection $dst -ErrorAction Stop } | Out-Null
        $results.Add((New-SPCopyResult -ObjectType 'Site' -Name $SourceUrl -Action 'Overwrite' -Status 'Success' -Detail 'Structure applied'))
    }
    catch {
        $results.Add((New-SPCopyResult -ObjectType 'Site' -Name $SourceUrl -Action 'Overwrite' -Status 'Error' -Detail $_.Exception.Message))
    }

    # 2) Content: per list/library, honouring the planned action.
    if ($IncludeContent) {
        foreach ($l in $srcLists) {
            $row = $plan | Where-Object Name -eq $l.Title | Select-Object -First 1
            if ($row -and $row.Action -eq 'Skip') {
                $results.Add((New-SPCopyResult -ObjectType $row.ObjectType -Name $l.Title -Action 'Skip' -Status 'Skipped' -Detail $row.Detail))
                continue
            }
            try {
                if ($l.BaseType -eq 'DocumentLibrary') {
                    Copy-SPLibraryFiles -SourceConnection $src -ListTitle $l.Title -SourceWebUrl $SourceUrl -DestinationWebUrl $DestinationUrl -Overwrite:($ConflictMode -eq 'Replace')
                    $results.Add((New-SPCopyResult -ObjectType 'Library' -Name $l.Title -Action 'Overwrite' -Status 'Success' -Detail 'Files copied'))
                }
                else {
                    $n = Copy-SPListItems -SourceConnection $src -DestinationConnection $dst -ListTitle $l.Title -Since $Since
                    $results.Add((New-SPCopyResult -ObjectType 'List' -Name $l.Title -Action 'Overwrite' -Status 'Success' -Detail "$n item(s) copied"))
                }
            }
            catch {
                Write-SPLog "FAILED list '$($l.Title)': $($_.Exception.Message)" -Level Error
                $results.Add((New-SPCopyResult -ObjectType $(if ($l.BaseType -eq 'DocumentLibrary') { 'Library' } else { 'List' }) -Name $l.Title -Action 'Overwrite' -Status 'Error' -Detail $_.Exception.Message))
            }
        }
    }

    # 3) Permissions (optional): re-apply role assignments, remapping principals. We're past
    # the dry-run guard here, so the site copy is already confirmed — run it -Force.
    if ($CopyPermissions) {
        try {
            $permRows = Copy-SPPermissions -SourceUrl $SourceUrl -DestinationUrl $DestinationUrl `
                -MappingCsv $MappingCsv -DomainFrom $DomainFrom -DomainTo $DomainTo `
                -IncludeListPermissions -Force
            foreach ($r in @($permRows)) { $results.Add($r) }
        }
        catch {
            $results.Add((New-SPCopyResult -ObjectType 'Permissions' -Name $SourceUrl -Action 'Create' -Status 'Error' -Detail $_.Exception.Message))
        }
    }

    $errors = @($results | Where-Object Status -eq 'Error').Count
    Write-SPLog ("Copy complete: {0} object(s), {1} error(s)." -f $results.Count, $errors) -Level $(if ($errors) { 'Warn' } else { 'Success' })
    $results | ConvertTo-SPOutput -AsJson:$AsJson
}
