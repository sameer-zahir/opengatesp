#Requires -Version 7.4
<#
.SYNOPSIS
    Register a Windows scheduled task that runs the governance report on a cadence,
    unattended, with app-only certificate auth.
.DESCRIPTION
    Assembles the command with Get-SPScheduledCommand, prints it for transparency, then
    registers a daily or weekly task. Run with -WhatIf to preview without registering.
    On Linux/macOS, use the cron one-liner in docs/06-scheduled-reports.md instead.
.EXAMPLE
    ./Register-GovernanceReportTask.ps1 -SiteUrl https://contoso.sharepoint.com/sites/Mktg `
        -OutDir C:\Reports -Frequency Weekly -At 06:30 `
        -Thumbprint A1B2C3... -ClientId <app-id> -Tenant contoso.onmicrosoft.com
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [string]$OutDir = 'C:\OpenGateSP\reports',
    [ValidateSet('Sharing', 'Permissions')][string[]]$Reports = @('Sharing', 'Permissions'),
    [ValidateSet('Daily', 'Weekly')][string]$Frequency = 'Daily',
    [string]$At = '07:00',
    [string]$TaskName = 'OpenGateSP Governance Report',
    [string]$Thumbprint,
    [string]$ClientId,
    [string]$Tenant
)

. (Join-Path $PSScriptRoot 'Get-SPScheduledCommand.ps1')

$cmd = Get-SPScheduledCommand -SiteUrl $SiteUrl -OutDir $OutDir -Reports $Reports `
    -Thumbprint $Thumbprint -ClientId $ClientId -Tenant $Tenant
Write-Host "Scheduled command:`n  $($cmd.CommandLine)`n"

$pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
$action = New-ScheduledTaskAction -Execute $pwshPath -Argument $cmd.ArgumentLine
$trigger = if ($Frequency -eq 'Weekly') {
    New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At ([datetime]$At)
}
else {
    New-ScheduledTaskTrigger -Daily -At ([datetime]$At)
}

if ($PSCmdlet.ShouldProcess($TaskName, "Register $Frequency scheduled task")) {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Description 'OpenGateSP unattended governance report' -Force | Out-Null
    Write-Host "Registered '$TaskName' ($Frequency at $At). Reports land in $OutDir."
}
