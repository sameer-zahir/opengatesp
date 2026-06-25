#Requires -Version 7.4
<#
.SYNOPSIS
    Example: export an external-sharing report for a site to CSV.
.EXAMPLE
    ./Export-SharingReport.ps1 -SiteUrl https://contoso.sharepoint.com/sites/Marketing
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [string]$OutCsv = './sharing-report.csv',
    [switch]$IncludeLinks
)

Import-Module (Join-Path $PSScriptRoot '..\..\module\OpenGateSP\OpenGateSP.psd1') -Force
Connect-SPTool   # uses your saved defaults (run Connect-SPTool ... -SaveConfig once)

Get-SPSharingReport -SiteUrl $SiteUrl -IncludeLinks:$IncludeLinks |
    Tee-Object -Variable rows |
    Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding utf8

Write-Output "Wrote $(@($rows).Count) row(s) to $OutCsv"
