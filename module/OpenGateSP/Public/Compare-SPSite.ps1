function Compare-SPSite {
    <#
    .SYNOPSIS
        Validate a finished copy: compare a destination site against its source and report which
        lists/libraries are missing or have different item counts. Read-only.
    .DESCRIPTION
        Enumerates the non-hidden lists and libraries on each site (with item counts) and diffs
        them, so after a Copy-SPSite you can confirm everything landed. Same-tenant: it connects to
        each site in turn using your saved app/tenant defaults. Statuses: Match, CountMismatch,
        Missing (source-only), ExtraInDest.
    .PARAMETER SourceUrl
        The original site.
    .PARAMETER DestinationUrl
        The copied-to site.
    .PARAMETER Lists
        Limit the comparison to these list/library display names. Default: all non-hidden.
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Compare-SPSite -SourceUrl https://contoso.sharepoint.com/sites/Old -DestinationUrl https://contoso.sharepoint.com/sites/New
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SourceUrl,
        [Parameter(Mandatory)][string]$DestinationUrl,
        [string[]]$Lists,
        [switch]$AsJson
    )

    $readIndex = {
        param($Url, $ListFilter)
        Resolve-SPSiteConnection -SiteUrl $Url | Out-Null
        $all = @(Invoke-SPRetry -Operation "list lists $Url" { Get-PnPList -ErrorAction Stop })
        $all = $all | Where-Object { -not $_.Hidden }
        if ($ListFilter) { $all = $all | Where-Object { $ListFilter -contains $_.Title } }
        foreach ($l in $all) {
            [pscustomobject]@{ Title = "$($l.Title)"; ItemCount = [int]$l.ItemCount; BaseType = "$($l.BaseType)" }
        }
    }

    Write-SPLog "Comparing $SourceUrl -> $DestinationUrl ..."
    $srcIdx = @(& $readIndex $SourceUrl $Lists)
    $dstIdx = @(& $readIndex $DestinationUrl $Lists)

    $rows = @(Compare-SPStructure -Source $srcIdx -Destination $dstIdx)
    $issues = @($rows | Where-Object Status -ne 'Match').Count
    $level = if ($issues) { 'Warn' } else { 'Success' }
    Write-SPLog ("Compare: {0} object(s), {1} with differences." -f $rows.Count, $issues) -Level $level
    $rows | ConvertTo-SPOutput -AsJson:$AsJson
}
