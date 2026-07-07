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
# Shared write-safety helpers (Get-SPWriteKey / Resolve-SPGatedWrite) — the same file the GUI AI uses.
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'gui\ai\ToolCatalog.ps1')

$script:Connected = $false

# Preview-first gate for write commands (mirrors the GUI's Apply-button gate): an apply call —
# execute=true, already resolved to -Force (or, for noForce cmdlets, to "no -WhatIf") by the MCP
# layer — is only honored when the identical call (same command + args minus safety flags) was
# previewed earlier in this session; otherwise it is downgraded to a -WhatIf preview and the
# response is marked downgraded. Approvals are single-use.
$script:PreviewedWrites = [System.Collections.Generic.HashSet[string]]::new()
$script:WriteCommands = @(
    'site.lifecycle', 'remediate.checkin', 'remediate.versions', 'remediate.inheritance',
    'remediate.orphans', 'migrate.files', 'copy.site', 'copy.permissions', 'copy.site.crosstenant',
    'copy.termgroup', 'copy.m365group', 'copy.team', 'copy.planner', 'copy.list',
    'provision.site', 'bulk.metadata', 'identity.copy'
)

function Confirm-Connected {
    if ($script:Connected) { return }
    Connect-SPTool | Out-Null   # uses saved defaults (ClientId/Tenant/Url); interactive once
    $script:Connected = $true
}

# One side of a cross-tenant operation. Connection objects can't cross the JSON protocol, so both
# ends are opened here; a certificate thumbprint per tenant keeps it headless (app-only).
function New-EngineTenantConnection {
    param($Url, $ClientId, $Tenant, $Thumbprint)
    $cp = @{ Url = $Url; ClientId = $ClientId }
    if ($Tenant) { $cp['Tenant'] = $Tenant }
    if ($Thumbprint) { $cp['Thumbprint'] = $Thumbprint }
    New-SPMigrationConnection @cp
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
        'disconnect' {
            $r = Disconnect-SPTool @Params
            $script:Connected = $false
            return $r
        }
        # Named environments — local config only, no tenant call, so no Confirm-Connected.
        'environment.list'   { return (Get-SPEnvironment @Params) }
        'environment.remove' { return (Remove-SPEnvironment @Params -Confirm:$false) }
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
            # Cross-tenant: a connection per tenant, then hand both to Copy-SPSite -CrossTenant.
            $s = New-EngineTenantConnection $Params.SourceUrl $Params.SourceClientId $Params.SourceTenant $Params.SourceThumbprint
            $d = New-EngineTenantConnection $Params.DestinationUrl $Params.DestinationClientId $Params.DestinationTenant $Params.DestinationThumbprint
            $cp = @{ SourceUrl = $Params.SourceUrl; DestinationUrl = $Params.DestinationUrl
                     SourceConnection = $s; DestinationConnection = $d; CrossTenant = $true }
            foreach ($k in 'IncludeContent', 'CopyPermissions', 'DomainFrom', 'DomainTo', 'MappingCsv', 'Force', 'WhatIf') {
                if ($Params.ContainsKey($k)) { $cp[$k] = $Params[$k] }
            }
            return (Copy-SPSite @cp)
        }
        'copy.termgroup' {
            # Managed-metadata term group copy — same per-tenant connections as copy.site.crosstenant.
            $s = New-EngineTenantConnection $Params.SourceUrl $Params.SourceClientId $Params.SourceTenant $Params.SourceThumbprint
            $d = New-EngineTenantConnection $Params.DestinationUrl $Params.DestinationClientId $Params.DestinationTenant $Params.DestinationThumbprint
            $cp = @{ SourceConnection = $s; DestinationConnection = $d; TermGroup = $Params.TermGroup }
            foreach ($k in 'Force', 'WhatIf') {
                if ($Params.ContainsKey($k)) { $cp[$k] = $Params[$k] }
            }
            return (Copy-SPTermGroup @cp)
        }

        # Identity pipeline (docs/14) — tenant-level Graph work, so each step opens its own
        # app-only connection (inventory: SOURCE tenant; map/validate/copy: DESTINATION tenant).
        'identity.inventory' {
            $s = New-EngineTenantConnection $Params.SourceUrl $Params.SourceClientId $Params.SourceTenant $Params.SourceThumbprint
            $cp = @{ Connection = $s }
            if ($Params.ContainsKey('Path')) { $cp['Path'] = $Params.Path }
            return (Get-SPIdentityInventory @cp)
        }
        'identity.map' {
            $d = New-EngineTenantConnection $Params.DestinationUrl $Params.DestinationClientId $Params.DestinationTenant $Params.DestinationThumbprint
            $cp = @{ InventoryCsv = $Params.InventoryCsv; DomainTo = $Params.DomainTo; DestinationConnection = $d }
            foreach ($k in 'IncludeGuests', 'Path') {
                if ($Params.ContainsKey($k)) { $cp[$k] = $Params[$k] }
            }
            return (New-SPIdentityMap @cp)
        }
        'identity.validate' {
            $d = New-EngineTenantConnection $Params.DestinationUrl $Params.DestinationClientId $Params.DestinationTenant $Params.DestinationThumbprint
            return (Test-SPIdentityMap -MapCsv $Params.MapCsv -DestinationConnection $d)
        }
        'identity.copy' {
            $d = New-EngineTenantConnection $Params.DestinationUrl $Params.DestinationClientId $Params.DestinationTenant $Params.DestinationThumbprint
            $cp = @{ MapCsv = $Params.MapCsv; DestinationConnection = $d }
            foreach ($k in 'InventoryCsv', 'EnableAccounts', 'SendInvitations', 'PrincipalMapPath', 'Force', 'WhatIf') {
                if ($Params.ContainsKey($k)) { $cp[$k] = $Params[$k] }
            }
            return (Copy-SPIdentity @cp)
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
        # Preview-first gate: write applies only go through when this exact call was previewed.
        $gate = $null
        if ($req.command -in $script:WriteCommands) {
            $gate = Resolve-SPGatedWrite -Command $req.command -Params $params -Previewed $script:PreviewedWrites
            $params = $gate.Params
        }
        # Suppress warning/verbose/debug/information streams; keep only pipeline output.
        $data = Invoke-EngineCommand -Command $req.command -Params $params 3>$null 4>$null 5>$null 6>$null
        if ($gate -and $gate.WasPreview) { [void]$script:PreviewedWrites.Add($gate.Key) }   # arm only after a successful preview
        $resp = [ordered]@{ id = $id; ok = $true; data = @($data) }
        if ($gate -and $gate.Downgraded) { $resp['downgraded'] = $true }
        [Console]::Out.WriteLine(($resp | ConvertTo-Json -Depth 8 -Compress))
    }
    catch {
        $resp = [ordered]@{ id = $id; ok = $false; error = "$($_.Exception.Message)" }
        [Console]::Out.WriteLine(($resp | ConvertTo-Json -Depth 4 -Compress))
    }
}
