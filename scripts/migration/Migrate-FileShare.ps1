#Requires -Version 7.4
<#
.SYNOPSIS
    Example: migrate a local folder into a SharePoint library. Dry-run unless -Execute.
.EXAMPLE
    ./Migrate-FileShare.ps1 -Source C:\Shares\Marketing -SiteUrl https://contoso.sharepoint.com/sites/Mktg
    ./Migrate-FileShare.ps1 -Source C:\Shares\Marketing -SiteUrl https://contoso.sharepoint.com/sites/Mktg -Execute
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$SiteUrl,
    [string]$Library = 'Documents',
    [switch]$Execute   # omit for a -WhatIf preview
)

Import-Module (Join-Path $PSScriptRoot '..\..\module\OpenGateSP\OpenGateSP.psd1') -Force
Connect-SPTool

$common = @{ Source = $Source; SiteUrl = $SiteUrl; Library = $Library; PreserveTimestamps = $true }
if ($Execute) { Start-SPFileMigration @common -Force }
else          { Start-SPFileMigration @common -WhatIf }
