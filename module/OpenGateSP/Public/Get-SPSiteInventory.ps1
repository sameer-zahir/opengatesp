function Get-SPSiteInventory {
    <#
    .SYNOPSIS
        Tenant-wide inventory of site collections: storage, template, owner, and last
        activity. The "what do we even have?" report.
    .DESCRIPTION
        Requires a connection to the SharePoint admin centre and the SharePoint
        Administrator role. Connect with: Connect-SPTool -Admin
    .PARAMETER IncludeStorage
        Fetch detailed properties (storage usage and last-activity date). Slower on large
        tenants, so it is opt-in.
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Connect-SPTool -Admin
        Get-SPSiteInventory -IncludeStorage | Sort-Object StorageUsedMB -Descending | Format-Table
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch]$IncludeStorage,
        [switch]$AsJson
    )

    Assert-SPConnection | Out-Null
    Write-SPLog "Retrieving site inventory (needs admin-centre connection: Connect-SPTool -Admin)..."

    $params = @{ ErrorAction = 'Stop' }
    if ($IncludeStorage) { $params['Detailed'] = $true }

    try {
        $sites = Invoke-SPRetry -Operation 'Get-PnPTenantSite' { Get-PnPTenantSite @params }
    }
    catch {
        throw "Could not list tenant sites. Connect to the admin centre first (Connect-SPTool -Admin) and ensure you hold the SharePoint Administrator role. Underlying error: $($_.Exception.Message)"
    }

    $result = foreach ($s in $sites) {
        $usedMB  = [math]::Round([double]$s.StorageUsage, 0)
        $quotaMB = [math]::Round([double]$s.StorageQuota, 0)
        [pscustomobject]@{
            Url            = $s.Url
            Title          = $s.Title
            Template       = $s.Template
            Owner          = $s.Owner
            StorageUsedMB  = $usedMB
            StorageQuotaMB = $quotaMB
            PercentUsed    = if ($quotaMB -gt 0) { [math]::Round(($usedMB / $quotaMB) * 100, 1) } else { $null }
            LastActivity   = $s.LastContentModifiedDate
            Sharing        = "$($s.SharingCapability)"
        }
    }

    Write-SPLog "Found $(@($result).Count) site collection(s)." -Level Success
    $result | Sort-Object -Property StorageUsedMB -Descending | ConvertTo-SPOutput -AsJson:$AsJson
}
