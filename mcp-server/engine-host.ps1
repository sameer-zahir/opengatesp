#Requires -Version 7.4
<#
.SYNOPSIS
    Persistent OpenGateSP engine host for the MCP server.
.DESCRIPTION
    Imports the OpenGateSP module once, then serves newline-delimited JSON requests from
    stdin, writing exactly one JSON response per line to stdout:

        ->  {"id":"r1","command":"report.sharing","params":{"SiteUrl":"https://..."}}
        <-  {"id":"r1","ok":true,"data":[ ... ]}
        <-  {"id":"r1","ok":false,"error":"..."}

    Engine host output is silenced (OPENGATESP_QUIET) so it can never corrupt the protocol.
    The SharePoint connection is established lazily on the first command that needs it,
    so `ping` works without a tenant.
#>
[CmdletBinding()]
param([string]$ModulePath)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$env:OPENGATESP_QUIET  = '1'   # engine must not write to stdout

if (-not $ModulePath) {
    $ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'module\OpenGateSP\OpenGateSP.psd1'
}
Import-Module $ModulePath -Force

$script:Connected = $false

function Confirm-Connected {
    if ($script:Connected) { return }
    Connect-SPTool | Out-Null   # uses saved defaults (ClientId/Tenant/Url); interactive once
    $script:Connected = $true
}

function Invoke-EngineCommand {
    param([string]$Command, [hashtable]$Params)
    switch ($Command) {
        'ping' {
            return [pscustomobject]@{
                pong = $true; module = 'OpenGateSP'
                version = (Get-Module OpenGateSP).Version.ToString()
                connected = $script:Connected
            }
        }
        'connect' {
            $p = @{ SaveConfig = $true }
            foreach ($k in $Params.Keys) { $p[$k] = $Params[$k] }
            $r = Connect-SPTool @p
            $script:Connected = $true
            return $r
        }
        'report.sharing'     { Confirm-Connected; return (Get-SPSharingReport @Params) }
        'report.permissions' { Confirm-Connected; return (Get-SPPermissionReport @Params) }
        'report.inventory'   { Confirm-Connected; return (Get-SPSiteInventory @Params) }
        'report.matrix'      { Confirm-Connected; return (Get-SPPermissionsMatrix @Params) }
        'report.orphans'     { Confirm-Connected; return (Get-SPOrphanedUsers @Params) }
        'governance.everyone' { Confirm-Connected; return (Find-SPEveryoneClaims @Params) }
        'governance.ownerless' { Confirm-Connected; return (Get-SPOwnerlessGroups @Params) }
        'governance.review'   { Confirm-Connected; return (Invoke-SPGovernanceReview @Params) }
        'explore.assess'     { Confirm-Connected; return (Invoke-SPExplore @Params) }
        'report.checkedout'  { Confirm-Connected; return (Get-SPCheckedOutFiles @Params) }
        'report.largefiles'  { Confirm-Connected; return (Get-SPLargeFiles @Params) }
        'report.versions'    { Confirm-Connected; return (Get-SPVersionHistoryReport @Params) }
        'report.content'     { Confirm-Connected; return (Get-SPContentInsights @Params) }
        'report.workflows'   { Confirm-Connected; return (Get-SPWorkflowReport @Params) }
        'report.inactive'    { Confirm-Connected; return (Get-SPInactiveSites @Params) }
        'site.lifecycle'     { Confirm-Connected; return (Set-SPSiteLifecycle @Params) }
        'remediate.checkin'     { Confirm-Connected; return (Invoke-SPCheckIn @Params) }
        'remediate.versions'    { Confirm-Connected; return (Clear-SPVersionHistory @Params) }
        'remediate.inheritance' { Confirm-Connected; return (Restore-SPInheritance @Params) }
        'remediate.orphans'     { Confirm-Connected; return (Remove-SPOrphanedUsers @Params) }
        'migrate.files'      { Confirm-Connected; return (Start-SPFileMigration @Params) }
        'precheck.readiness' { return (Test-SPMigrationReadiness @Params) }  # local scan, no connection
        'copy.site'          { return (Copy-SPSite @Params) }                # manages its own source+dest connections
        'copy.list'          { return (Copy-SPList @Params) }                # granular single list/library copy
        'compare.site'       { Confirm-Connected; return (Compare-SPSite @Params) }  # post-migration validation
        'copy.permissions'   { return (Copy-SPPermissions @Params) }         # role-assignment copy + principal remap
        'copy.site.crosstenant' {
            # Cross-tenant: open a connection per tenant here (objects can't cross the protocol),
            # then hand both to Copy-SPSite -CrossTenant. App-only (thumbprint) needed headlessly.
            $mk = {
                param($u, $cid, $tn, $thumb)
                $cp = @{ Url = $u; ClientId = $cid }
                if ($tn) { $cp['Tenant'] = $tn }
                if ($thumb) { $cp['Thumbprint'] = $thumb }
                New-SPMigrationConnection @cp
            }
            $s = & $mk $Params.SourceUrl $Params.SourceClientId $Params.SourceTenant $Params.SourceThumbprint
            $d = & $mk $Params.DestinationUrl $Params.DestinationClientId $Params.DestinationTenant $Params.DestinationThumbprint
            $cp = @{ SourceUrl = $Params.SourceUrl; DestinationUrl = $Params.DestinationUrl
                     SourceConnection = $s; DestinationConnection = $d; CrossTenant = $true }
            foreach ($k in 'IncludeContent', 'CopyPermissions', 'DomainFrom', 'DomainTo', 'MappingCsv', 'Force', 'WhatIf') {
                if ($Params.ContainsKey($k)) { $cp[$k] = $Params[$k] }
            }
            return (Copy-SPSite @cp)
        }


        'copy.team'          { Confirm-Connected; return (Copy-SPTeam @Params) }
        'copy.m365group'     { Confirm-Connected; return (Copy-SPM365Group @Params) }
        'copy.planner'       { Confirm-Connected; return (Copy-SPPlannerPlan @Params) }
        'provision.site'     { Confirm-Connected; return (New-SPSiteFromTemplate @Params) }
        'bulk.metadata'      { Confirm-Connected; return (Set-SPBulkMetadata @Params) }
        default              { throw "Unknown command: $Command" }
    }
}

# Signal readiness to the Node parent.
[Console]::Out.WriteLine((@{ ready = $true } | ConvertTo-Json -Compress))

while ($null -ne ($line = [Console]::In.ReadLine())) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $id = $null
    try {
        $req = $line | ConvertFrom-Json
        $id  = $req.id
        $params = @{}
        if ($req.PSObject.Properties.Name -contains 'params' -and $req.params) {
            foreach ($prop in $req.params.PSObject.Properties) { $params[$prop.Name] = $prop.Value }
        }
        # Suppress warning/verbose/debug/information streams; keep only pipeline output.
        $data = Invoke-EngineCommand -Command $req.command -Params $params 3>$null 4>$null 5>$null 6>$null
        $resp = [ordered]@{ id = $id; ok = $true; data = @($data) }
        [Console]::Out.WriteLine(($resp | ConvertTo-Json -Depth 8 -Compress))
    }
    catch {
        $resp = [ordered]@{ id = $id; ok = $false; error = "$($_.Exception.Message)" }
        [Console]::Out.WriteLine(($resp | ConvertTo-Json -Depth 4 -Compress))
    }
}
