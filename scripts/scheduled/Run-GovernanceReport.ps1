#Requires -Version 7.4
<#
.SYNOPSIS
    Unattended: write sharing and/or permission reports for a site to timestamped CSVs.
.DESCRIPTION
    Built to run headless from a scheduled task. Pass -Thumbprint (with -ClientId and
    -Tenant) to connect with app-only certificate auth and no sign-in; omit them to use
    the saved connection from `Connect-SPTool ... -SaveConfig`.
.EXAMPLE
    ./Run-GovernanceReport.ps1 -SiteUrl https://contoso.sharepoint.com/sites/Mktg -OutDir C:\Reports
.EXAMPLE
    ./Run-GovernanceReport.ps1 -SiteUrl https://contoso.sharepoint.com/sites/Mktg `
        -Thumbprint A1B2C3... -ClientId <app-id> -Tenant contoso.onmicrosoft.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [string]$OutDir = '.\reports',
    [ValidateSet('Sharing', 'Permissions')][string[]]$Reports = @('Sharing', 'Permissions'),
    [string]$Thumbprint,
    [string]$ClientId,
    [string]$Tenant
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\module\OpenGateSP\OpenGateSP.psd1') -Force

# App-only when a thumbprint is supplied; otherwise the saved/delegated config.
$connect = @{}
if ($Thumbprint) { $connect.Thumbprint = $Thumbprint }
if ($ClientId) { $connect.ClientId = $ClientId }
if ($Tenant) { $connect.Tenant = $Tenant }
Connect-SPTool @connect | Out-Null

if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

foreach ($report in $Reports) {
    switch ($report) {
        'Sharing' { $data = Get-SPSharingReport -SiteUrl $SiteUrl -IncludeLinks }
        'Permissions' { $data = Get-SPPermissionReport -SiteUrl $SiteUrl -IncludeListPermissions }
    }
    $out = Join-Path $OutDir ("{0}-{1}.csv" -f $report.ToLower(), $stamp)
    @($data) | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding utf8
    Write-Output "Wrote $(@($data).Count) row(s) to $out"
}
