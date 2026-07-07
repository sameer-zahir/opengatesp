#Requires -Version 7.4
# Behavior tests for Connect-SPTool's auth flavors: OSLogin/PersistLogin routing, the
# broker->browser fallback, saved-flavor reuse, and what -SaveConfig persists. PnP cmdlets
# are stubbed and record their calls; config goes to TestDrive. No tenant, CI-friendly.

BeforeAll {
    $mod = Join-Path $PSScriptRoot '..\module\OpenGateSP'
    . (Join-Path $mod 'Private\Write-SPLog.ps1')
    . (Join-Path $mod 'Private\ConvertTo-SPOutput.ps1')
    . (Join-Path $mod 'Private\Get-SPHttpStatusCode.ps1')
    . (Join-Path $mod 'Private\Get-SPRetryDelay.ps1')
    . (Join-Path $mod 'Private\Invoke-SPRetry.ps1')
    . (Join-Path $mod 'Private\SPEnvironments.ps1')
    . (Join-Path $mod 'Private\SPConfig.ps1')
    . (Join-Path $mod 'Private\Resolve-SPAuthChoice.ps1')
    . (Join-Path $mod 'Public\Connect-SPTool.ps1')
    . (Join-Path $mod 'Public\Disconnect-SPTool.ps1')

    # PnP stand-ins: record every call; OSLogin fails when the test arms $script:BrokerFails.
    function Connect-PnPOnline {
        [CmdletBinding()]
        param(
            [string]$Url, [string]$ClientId, [string]$Tenant,
            [switch]$Interactive, [switch]$DeviceLogin, [switch]$OSLogin, [switch]$PersistLogin,
            [string]$Thumbprint, [string]$CertificatePath, [securestring]$CertificatePassword,
            [switch]$ReturnConnection
        )
        $script:ConnectCalls.Add([pscustomobject]@{
                Url = $Url; ClientId = $ClientId; Tenant = $Tenant
                Interactive = [bool]$Interactive; DeviceLogin = [bool]$DeviceLogin
                OSLogin = [bool]$OSLogin; PersistLogin = [bool]$PersistLogin
                Thumbprint = $Thumbprint; ReturnConnection = [bool]$ReturnConnection
            })
        if ($script:BrokerFails -and $OSLogin) { throw 'AADSTS50011: broker redirect URI not configured for this application.' }
        if ($script:ConnectFailsWith) { throw $script:ConnectFailsWith }
        if ($ReturnConnection) { [pscustomobject]@{ Url = $Url } }
    }
    function Get-PnPWeb { [CmdletBinding()] param() [pscustomobject]@{ Title = 'Stub Web' } }
    function Get-PnPConnection {
        [CmdletBinding()] param()
        if (-not $script:PnPConnected) { throw 'No connection.' }
        [pscustomobject]@{ Url = 'https://stub' }
    }
    function Disconnect-PnPOnline {
        [CmdletBinding()] param([switch]$ClearPersistedLogin)
        $script:DisconnectCalls.Add([pscustomobject]@{ ClearPersistedLogin = [bool]$ClearPersistedLogin })
        $script:PnPConnected = $false
    }
}

Describe 'Connect-SPTool auth flavors' {
    BeforeEach {
        $script:ConnectCalls = [System.Collections.Generic.List[object]]::new()
        $script:BrokerFails = $false
        $script:ConnectFailsWith = $null
        Mock Get-SPConfigPath { Join-Path $TestDrive 'spconfig.json' }
    }

    It 'defaults to browser sign-in with no persistence' {
        $r = Connect-SPTool -Url 'https://contoso.sharepoint.com' -ClientId 'cid' -Tenant 'contoso.onmicrosoft.com'
        $script:ConnectCalls[0].Interactive | Should -BeTrue
        $script:ConnectCalls[0].PersistLogin | Should -BeFalse
        $r.Mode | Should -Be 'Delegated'
        $r.Flow | Should -Be 'Interactive'
        $r.FellBack | Should -BeFalse
    }

    It '-PersistLogin reaches Connect-PnPOnline and is persisted by -SaveConfig' {
        Connect-SPTool -Url 'https://contoso.sharepoint.com' -ClientId 'cid' -Tenant 'contoso.onmicrosoft.com' -PersistLogin -SaveConfig | Out-Null
        $script:ConnectCalls[0].PersistLogin | Should -BeTrue
        $saved = Get-Content (Join-Path $TestDrive 'spconfig.json') -Raw | ConvertFrom-Json
        $saved.PersistLogin | Should -BeTrue
        $saved.DelegatedFlow | Should -Be 'Interactive'
        $saved.Environments.contoso.PersistLogin | Should -BeTrue
    }

    It 'a saved PersistLogin opt-in is reused on a plain connect, and -PersistLogin:$false turns it off' {
        Connect-SPTool -Url 'https://contoso.sharepoint.com' -ClientId 'cid' -Tenant 'contoso.onmicrosoft.com' -PersistLogin -SaveConfig | Out-Null
        $script:ConnectCalls.Clear()

        Connect-SPTool | Out-Null                                     # saved opt-in applies
        $script:ConnectCalls[0].PersistLogin | Should -BeTrue

        $script:ConnectCalls.Clear()
        Connect-SPTool -PersistLogin:$false -SaveConfig | Out-Null    # explicit off wins and saves
        $script:ConnectCalls[0].PersistLogin | Should -BeFalse
        $saved = Get-Content (Join-Path $TestDrive 'spconfig.json') -Raw | ConvertFrom-Json
        $saved.PersistLogin | Should -BeFalse
    }

    It 'reuses the saved device-code flavor on a plain connect' {
        Connect-SPTool -Url 'https://contoso.sharepoint.com' -ClientId 'cid' -Tenant 'contoso.onmicrosoft.com' -DeviceLogin -SaveConfig | Out-Null
        $script:ConnectCalls.Clear()
        Connect-SPTool | Out-Null
        $script:ConnectCalls[0].DeviceLogin | Should -BeTrue
        $script:ConnectCalls[0].Interactive | Should -BeFalse
    }

    It '-OSLogin connects via the OS broker (standalone parameter, no Interactive)' -Skip:(-not $IsWindows) {
        $r = Connect-SPTool -Url 'https://contoso.sharepoint.com' -ClientId 'cid' -Tenant 'contoso.onmicrosoft.com' -OSLogin
        $script:ConnectCalls[0].OSLogin | Should -BeTrue
        $script:ConnectCalls[0].Interactive | Should -BeFalse
        $r.Flow | Should -Be 'OSLogin'
    }

    It 'falls back to the browser when the broker fails, and saves the flow that worked' -Skip:(-not $IsWindows) {
        $script:BrokerFails = $true
        $r = Connect-SPTool -Url 'https://contoso.sharepoint.com' -ClientId 'cid' -Tenant 'contoso.onmicrosoft.com' -OSLogin -SaveConfig 3>$null
        $script:ConnectCalls.Count | Should -Be 2
        $script:ConnectCalls[0].OSLogin | Should -BeTrue
        $script:ConnectCalls[1].Interactive | Should -BeTrue
        $r.FellBack | Should -BeTrue
        $r.Flow | Should -Be 'Interactive'
        (Get-Content (Join-Path $TestDrive 'spconfig.json') -Raw | ConvertFrom-Json).DelegatedFlow | Should -Be 'Interactive'
    }

    It 'a non-broker connect failure still throws (fallback is OSLogin-only)' {
        $script:ConnectFailsWith = 'AADSTS700016: application not found.'
        { Connect-SPTool -Url 'https://contoso.sharepoint.com' -ClientId 'bad' -Tenant 'contoso.onmicrosoft.com' } | Should -Throw '*AADSTS700016*'
    }

    It '-OSLogin overrides a saved app-only config (delegated switch wins)' -Skip:(-not $IsWindows) {
        Connect-SPTool -Url 'https://contoso.sharepoint.com' -ClientId 'cid' -Tenant 'contoso.onmicrosoft.com' -Thumbprint 'ABC' -SaveConfig | Out-Null
        $script:ConnectCalls.Clear()
        $r = Connect-SPTool -OSLogin
        $script:ConnectCalls[0].OSLogin | Should -BeTrue
        $script:ConnectCalls[0].Thumbprint | Should -BeNullOrEmpty
        $r.Mode | Should -Be 'Delegated'
    }

    It 'saved app-only config still connects app-only by default' {
        Connect-SPTool -Url 'https://contoso.sharepoint.com' -ClientId 'cid' -Tenant 'contoso.onmicrosoft.com' -Thumbprint 'ABC' -SaveConfig | Out-Null
        $script:ConnectCalls.Clear()
        Connect-SPTool | Out-Null
        $script:ConnectCalls[0].Thumbprint | Should -Be 'ABC'
        $script:ConnectCalls[0].Interactive | Should -BeFalse
        $script:ConnectCalls[0].PersistLogin | Should -BeFalse
    }
}

Describe 'Connect-SPTool -Environment (named profiles)' {
    BeforeEach {
        $script:ConnectCalls = [System.Collections.Generic.List[object]]::new()
        $script:BrokerFails = $false
        $script:ConnectFailsWith = $null
        Mock Get-SPConfigPath { Join-Path $TestDrive 'spconfig.json' }
    }

    It 'creates, saves, and activates a named environment on connect (no -SaveConfig needed)' {
        $r = Connect-SPTool -Environment 'Contoso' -Url 'https://contoso.sharepoint.com' -ClientId 'cid' -Tenant 'contoso.onmicrosoft.com'
        $r.Environment | Should -Be 'Contoso'
        $saved = Get-Content (Join-Path $TestDrive 'spconfig.json') -Raw | ConvertFrom-Json
        $saved.ActiveEnvironment | Should -Be 'Contoso'
        $saved.Environments.Contoso.ClientId | Should -Be 'cid'
        $saved.ClientId | Should -Be 'cid'   # flat projection follows
    }

    It 'switching environments reconnects with the target auth and rebuilds the projection (no stale Thumbprint)' {
        Connect-SPTool -Environment 'Contoso' -Url 'https://contoso.sharepoint.com' -ClientId 'cid' -Tenant 'contoso.onmicrosoft.com' | Out-Null
        Connect-SPTool -Environment 'Fabrikam' -Url 'https://fabrikam.sharepoint.com' -ClientId 'fid' -Tenant 'fabrikam.onmicrosoft.com' -Thumbprint 'FAB1' | Out-Null
        $script:ConnectCalls.Clear()

        $r = Connect-SPTool -Environment 'contoso'   # case-insensitive switch back
        $r.Environment | Should -BeExactly 'Contoso'
        $script:ConnectCalls[0].ClientId | Should -Be 'cid'
        $script:ConnectCalls[0].Interactive | Should -BeTrue
        $script:ConnectCalls[0].Thumbprint | Should -BeNullOrEmpty

        $saved = Get-Content (Join-Path $TestDrive 'spconfig.json') -Raw | ConvertFrom-Json
        $saved.ActiveEnvironment | Should -Be 'Contoso'
        $saved.PSObject.Properties['Thumbprint'] | Should -BeNullOrEmpty   # projection rebuilt wholesale
        $saved.Environments.Fabrikam.Thumbprint | Should -Be 'FAB1'        # the other env keeps its cert
    }

    It 'throws on an unknown environment without -ClientId, listing the known ones' {
        Connect-SPTool -Environment 'Contoso' -Url 'https://contoso.sharepoint.com' -ClientId 'cid' -Tenant 'contoso.onmicrosoft.com' | Out-Null
        { Connect-SPTool -Environment 'nope' } | Should -Throw '*Contoso*'
    }

    It 'explicit parameters override the environment defaults and are saved back' {
        Connect-SPTool -Environment 'Contoso' -Url 'https://contoso.sharepoint.com' -ClientId 'cid' -Tenant 'contoso.onmicrosoft.com' | Out-Null
        $script:ConnectCalls.Clear()
        Connect-SPTool -Environment 'Contoso' -Url 'https://contoso.sharepoint.com/sites/hub' | Out-Null
        $script:ConnectCalls[0].Url | Should -Be 'https://contoso.sharepoint.com/sites/hub'
        (Get-Content (Join-Path $TestDrive 'spconfig.json') -Raw | ConvertFrom-Json).Environments.Contoso.Url |
            Should -Be 'https://contoso.sharepoint.com/sites/hub'
    }
}

Describe 'Disconnect-SPTool' {
    BeforeEach {
        $script:DisconnectCalls = [System.Collections.Generic.List[object]]::new()
        $script:PnPConnected = $true
    }

    It 'disconnects and forwards -ClearPersistedLogin' {
        $r = Disconnect-SPTool -ClearPersistedLogin
        $r.Disconnected | Should -BeTrue
        $r.ClearedPersistedLogin | Should -BeTrue
        $script:DisconnectCalls[0].ClearPersistedLogin | Should -BeTrue
    }
    It 'keeps the persisted cache unless asked' {
        (Disconnect-SPTool).ClearedPersistedLogin | Should -BeFalse
        $script:DisconnectCalls[0].ClearPersistedLogin | Should -BeFalse
    }
    It 'is a friendly no-op when not connected' {
        $script:PnPConnected = $false
        $r = Disconnect-SPTool -ClearPersistedLogin
        $r.Disconnected | Should -BeFalse
        $script:DisconnectCalls.Count | Should -Be 0
    }
}
