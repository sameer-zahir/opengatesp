#Requires -Version 7.4
<#
.SYNOPSIS
    Example: bulk-update list/library metadata from a CSV. Dry-run unless -Execute.
.DESCRIPTION
    The CSV header row holds field internal names; one column ("ID" by default) identifies
    the item. See sample-metadata.csv in this folder.
.EXAMPLE
    ./Set-MetadataFromCsv.ps1 -SiteUrl https://contoso.sharepoint.com/sites/Mktg -List Documents
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [string]$List = 'Documents',
    [string]$CsvPath = (Join-Path $PSScriptRoot 'sample-metadata.csv'),
    [switch]$Execute
)

Import-Module (Join-Path $PSScriptRoot '..\..\module\OpenGateSP\OpenGateSP.psd1') -Force
Connect-SPTool

if ($Execute) { Set-SPBulkMetadata -SiteUrl $SiteUrl -List $List -CsvPath $CsvPath -Force }
else          { Set-SPBulkMetadata -SiteUrl $SiteUrl -List $List -CsvPath $CsvPath -WhatIf }
