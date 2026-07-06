function Invoke-SPGovernanceReview {
    <#
    .SYNOPSIS
        Review a site's access risks in one shot: a read-only, consolidated governance assessment
        that surfaces the things an owner should attest to — broad-audience grants, external sharing,
        and stale access — in one severity-graded table. The "Protect" companion to Invoke-SPExplore.
    .DESCRIPTION
        Runs the per-site governance checks and normalizes them into uniform findings
        { Category, ItemType, Name, Severity, Detail, Count }, sorted Error -> Warning -> Info:

          - Broad access (Everyone / EEEU)  (Error   — biggest oversharing risk) [Find-SPEveryoneClaims]
          - External sharing                (Warning — review who's outside)     [Get-SPSharingReport]
          - Orphaned / stale access         (Warning — users no longer in dir)   [Get-SPOrphanedUsers; needs Graph]

        Each check is also available as its own cmdlet for detail. Nothing is written. Pair the
        findings with Restore-SPInheritance / Remove-SPOrphanedUsers / Set-SPSiteLifecycle to fix.
    .PARAMETER SiteUrl
        The site to review. Connected automatically.
    .PARAMETER IncludeListPermissions
        Also scan lists/libraries with unique permissions for broad-audience grants (slower).
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Invoke-SPGovernanceReview -SiteUrl https://contoso.sharepoint.com/sites/Marketing
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [switch]$IncludeListPermissions,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    Write-SPLog "Governance review of $SiteUrl ..."
    $findings = [System.Collections.Generic.List[object]]::new()

    $add = {
        param($Items, $Category, $Severity, $ItemType, $NameProp, $DetailProp)
        $p = @{ Item = @($Items); Category = $Category; Severity = $Severity; ItemType = $ItemType }
        if ($NameProp) { $p['NameProperty'] = $NameProp }
        if ($DetailProp) { $p['DetailProperty'] = $DetailProp }
        $findings.AddRange(@(ConvertTo-SPExploreFinding @p))
    }

    # Each check is wrapped so one failing probe never aborts the whole review.
    try { & $add (Find-SPEveryoneClaims -SiteUrl $SiteUrl -IncludeListPermissions:$IncludeListPermissions) 'Broad access (Everyone/EEEU)' 'Error' 'Grant' 'Claim' 'Roles' }
    catch { Write-SPLog "Broad-access scan failed: $($_.Exception.Message)" -Level Warn }

    try { & $add (Get-SPSharingReport -SiteUrl $SiteUrl) 'External sharing' 'Warning' 'User' 'Principal' 'Type' }
    catch { Write-SPLog "Sharing scan failed: $($_.Exception.Message)" -Level Warn }

    try { & $add (Get-SPOrphanedUsers -SiteUrl $SiteUrl) 'Orphaned / stale access' 'Warning' 'User' 'LoginName' 'Status' }
    catch { Write-SPLog "Orphaned-user scan skipped: $($_.Exception.Message)" -Level Warn }

    $rank = @{ Error = 0; Warning = 1; Info = 2 }
    $sorted = $findings | Sort-Object `
        @{ Expression = { $rank["$($_.Severity)"] } }, `
        @{ Expression = { $_.Category } }, `
        @{ Expression = { $_.Name } }

    $errors = @($findings | Where-Object Severity -eq 'Error').Count
    $warns = @($findings | Where-Object Severity -eq 'Warning').Count
    $level = if ($errors) { 'Error' } elseif ($warns) { 'Warn' } else { 'Success' }
    Write-SPLog ("Governance review: {0} finding(s) — {1} error(s), {2} warning(s)." -f $findings.Count, $errors, $warns) -Level $level
    $sorted | ConvertTo-SPOutput -AsJson:$AsJson
}
