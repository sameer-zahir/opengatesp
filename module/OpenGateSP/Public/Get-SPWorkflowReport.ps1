function Get-SPWorkflowReport {
    <#
    .SYNOPSIS
        Report SharePoint 2013-platform workflows (SharePoint Designer / Nintex) on a site — they
        do not migrate and are deprecated, so they need a plan before you move.
    .DESCRIPTION
        Read-only, best-effort. Lists workflow subscriptions on the site via
        Get-PnPWorkflowSubscription where that cmdlet is available in the installed
        PnP.PowerShell. Classic 2013 workflows are retired in SharePoint Online; this surfaces
        what exists so it can be rebuilt as Power Automate (out of scope to migrate). Modern
        cloud flows are not enumerable here.
    .PARAMETER SiteUrl
        The site to scan. Connected automatically.
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Get-SPWorkflowReport -SiteUrl https://contoso.sharepoint.com/sites/Marketing
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null

    if (-not (Get-Command Get-PnPWorkflowSubscription -ErrorAction SilentlyContinue)) {
        Write-SPLog 'Get-PnPWorkflowSubscription is not available in this PnP.PowerShell version; 2013 workflows cannot be enumerated.' -Level Warn
        return (@() | ConvertTo-SPOutput -AsJson:$AsJson)
    }

    Write-SPLog "Scanning $SiteUrl for 2013-platform workflows ..."
    $rows = [System.Collections.Generic.List[object]]::new()
    try {
        $subs = @(Invoke-SPRetry -Operation 'Get-PnPWorkflowSubscription' { Get-PnPWorkflowSubscription -ErrorAction Stop })
        foreach ($s in $subs) {
            $rows.Add([pscustomobject]@{
                Name      = "$($s.Name)"
                Enabled   = $s.Enabled
                ListId    = "$($s.EventSourceId)"
                Status    = 'Needs rebuild (Power Automate)'
            })
        }
    }
    catch { Write-SPLog "Could not read workflows: $($_.Exception.Message)" -Level Warn }

    Write-SPLog "Found $($rows.Count) workflow subscription(s)." -Level $(if ($rows.Count) { 'Warn' } else { 'Success' })
    $rows | ConvertTo-SPOutput -AsJson:$AsJson
}
