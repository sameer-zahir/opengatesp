function Invoke-SPExplore {
    <#
    .SYNOPSIS
        Explore a SharePoint SOURCE site: a read-only, consolidated pre-migration assessment that
        surfaces blockers and review items in one severity-graded table — the SharePoint-side
        companion to Test-SPMigrationReadiness (which scans local folders).
    .DESCRIPTION
        Runs several read-only checks against the site and normalizes them into uniform findings
        { Category, ItemType, Name, Severity, Detail, Count }, sorted Error → Warning → Info:

          - Checked-out files       (Error  — migrate as last check-in, or not at all)
          - Large files             (Warning — drive migration time/volume)
          - External sharing        (Warning — review before/after move)   [reuses Get-SPSharingReport]
          - Orphaned users          (Warning — stale access)               [reuses Get-SPOrphanedUsers; needs Graph]
          - 2013-platform workflows (Warning — don't migrate)              [reuses Get-SPWorkflowReport]
          - Version-history bloat   (Warning — opt-in via -IncludeVersions; slower)

        Each check is also available as its own Get-SP* cmdlet for detail. Nothing is written.
    .PARAMETER SiteUrl
        The source site to assess. Connected automatically.
    .PARAMETER LargeFileMB
        Size at/above which a file is flagged large. Default 100.
    .PARAMETER IncludeVersions
        Also scan version history (per-file calls — slower on big libraries) and flag bloated files.
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Invoke-SPExplore -SiteUrl https://contoso.sharepoint.com/sites/Marketing
    .EXAMPLE
        Invoke-SPExplore -SiteUrl https://contoso.sharepoint.com/sites/Marketing -IncludeVersions -AsJson
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [int]$LargeFileMB = 100,
        [switch]$IncludeVersions,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    Write-SPLog "Exploring $SiteUrl ..."
    $findings = [System.Collections.Generic.List[object]]::new()

    $add = {
        param($Items, $Category, $Severity, $ItemType, $NameProp, $DetailProp)
        $p = @{ Item = @($Items); Category = $Category; Severity = $Severity; ItemType = $ItemType }
        if ($NameProp) { $p['NameProperty'] = $NameProp }
        if ($DetailProp) { $p['DetailProperty'] = $DetailProp }
        $findings.AddRange(@(ConvertTo-SPExploreFinding @p))
    }

    # Each check is wrapped so one failing probe never aborts the whole assessment.
    try { & $add (Get-SPCheckedOutFiles -SiteUrl $SiteUrl) 'Checked-out files' 'Error'  'File'     'FileRef'   'CheckedOutTo' }
    catch { Write-SPLog "Checked-out scan failed: $($_.Exception.Message)" -Level Warn }

    try { & $add (Get-SPLargeFiles -SiteUrl $SiteUrl -MinSizeMB $LargeFileMB) 'Large files' 'Warning' 'File' 'FileRef' 'SizeMB' }
    catch { Write-SPLog "Large-file scan failed: $($_.Exception.Message)" -Level Warn }

    try { & $add (Get-SPSharingReport -SiteUrl $SiteUrl) 'External sharing' 'Warning' 'User' 'Principal' 'Type' }
    catch { Write-SPLog "Sharing scan failed: $($_.Exception.Message)" -Level Warn }

    try { & $add (Get-SPOrphanedUsers -SiteUrl $SiteUrl) 'Orphaned users' 'Warning' 'User' 'LoginName' 'Status' }
    catch { Write-SPLog "Orphaned-user scan skipped: $($_.Exception.Message)" -Level Warn }

    try { & $add (Get-SPWorkflowReport -SiteUrl $SiteUrl) '2013 workflows' 'Warning' 'Workflow' 'Name' 'Status' }
    catch { Write-SPLog "Workflow scan failed: $($_.Exception.Message)" -Level Warn }

    if ($IncludeVersions) {
        try {
            $bloat = Measure-SPVersionBloat -Item (Get-SPVersionHistoryReport -SiteUrl $SiteUrl)
            & $add $bloat 'Version-history bloat' 'Warning' 'File' 'Name' 'Reason'
        }
        catch { Write-SPLog "Version scan failed: $($_.Exception.Message)" -Level Warn }
    }

    $rank = @{ Error = 0; Warning = 1; Info = 2 }
    $sorted = $findings | Sort-Object `
        @{ Expression = { $rank["$($_.Severity)"] } }, `
        @{ Expression = { $_.Category } }, `
        @{ Expression = { $_.Name } }

    $errors = @($findings | Where-Object Severity -eq 'Error').Count
    $warns = @($findings | Where-Object Severity -eq 'Warning').Count
    $level = if ($errors) { 'Error' } elseif ($warns) { 'Warn' } else { 'Success' }
    Write-SPLog ("Explore: {0} finding(s) — {1} error(s), {2} warning(s)." -f $findings.Count, $errors, $warns) -Level $level
    $sorted | ConvertTo-SPOutput -AsJson:$AsJson
}
