function Get-SPInactiveSites {
    <#
    .SYNOPSIS
        Report site collections nobody has touched in months — candidates to archive or skip
        before a migration, or to clean up in a governance sweep.
    .DESCRIPTION
        Requires a SharePoint admin-centre connection (Connect-SPTool -Admin). Builds the
        tenant inventory via Get-SPSiteInventory, then selects sites whose last content change is
        at least -InactiveDays old (plus any with no recorded activity). Read-only.
    .PARAMETER InactiveDays
        A site is inactive once its last activity is at least this many days old. Default 180.
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Connect-SPTool -Admin
        Get-SPInactiveSites -InactiveDays 365
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int]$InactiveDays = 180,
        [switch]$AsJson
    )

    Write-SPLog "Finding sites inactive for >= $InactiveDays day(s) ..."
    $inventory = @(Get-SPSiteInventory -IncludeStorage)
    $rows = @(Select-SPInactiveSites -Site $inventory -InactiveDays $InactiveDays -AsOf (Get-Date))

    $sorted = $rows | Sort-Object -Property @{ Expression = { $_.InactiveDays }; Descending = $true }
    Write-SPLog "Found $($rows.Count) inactive site(s)." -Level $(if ($rows.Count) { 'Warn' } else { 'Success' })
    $sorted | ConvertTo-SPOutput -AsJson:$AsJson
}
