#Requires -Version 7.4
<#
.SYNOPSIS
    Build the pwsh command line that a scheduled task runs to produce a governance
    report unattended. Pure string assembly (no side effects) so it can be unit-tested
    and previewed in the GUI before anything is registered.
.EXAMPLE
    (Get-SPScheduledCommand -SiteUrl https://contoso.sharepoint.com/sites/Mktg).CommandLine
#>
function Get-SPScheduledCommand {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [string]$OutDir = 'C:\OpenGateSP\reports',
        [ValidateSet('Sharing', 'Permissions')][string[]]$Reports = @('Sharing', 'Permissions'),
        [string]$Thumbprint,
        [string]$ClientId,
        [string]$Tenant,
        [string]$ScriptPath
    )

    if (-not $ScriptPath) { $ScriptPath = Join-Path $PSScriptRoot 'Run-GovernanceReport.ps1' }

    $argv = [System.Collections.Generic.List[string]]::new()
    $argv.AddRange([string[]]@('-NoProfile', '-File', $ScriptPath, '-SiteUrl', $SiteUrl, '-OutDir', $OutDir, '-Reports', ($Reports -join ',')))
    if ($Thumbprint) { $argv.AddRange([string[]]@('-Thumbprint', $Thumbprint)) }
    if ($ClientId) { $argv.AddRange([string[]]@('-ClientId', $ClientId)) }
    if ($Tenant) { $argv.AddRange([string[]]@('-Tenant', $Tenant)) }

    # Quote any argument that contains whitespace so the command line round-trips.
    $quoted = $argv | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
    $argumentLine = $quoted -join ' '

    [pscustomobject]@{
        Executable   = 'pwsh'
        Arguments    = $argv.ToArray()
        ArgumentLine = $argumentLine
        CommandLine  = "pwsh $argumentLine"
    }
}
