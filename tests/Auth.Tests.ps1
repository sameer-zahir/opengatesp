#Requires -Version 7.4
# Unit tests for connection-parameter building (no PnP / tenant needed; config is mocked).

BeforeAll {
    $priv = Join-Path $PSScriptRoot '..\module\OpenGateSP\Private'
    . (Join-Path $priv 'Write-SPLog.ps1')
    . (Join-Path $priv 'SPEnvironments.ps1')
    . (Join-Path $priv 'SPConfig.ps1')
    . (Join-Path $priv 'Get-SPConnectParams.ps1')
    . (Join-Path $priv 'Resolve-SPAuthChoice.ps1')
}

Describe 'Get-SPConnectParams' {
    It 'builds app-only params from a saved thumbprint (no interactive)' {
        Mock Get-SPConfig { [pscustomobject]@{ ClientId = 'cid'; Tenant = 't.onmicrosoft.com'; AuthMode = 'AppOnly'; Thumbprint = 'ABC123' } }
        $p = Get-SPConnectParams -Url 'https://x.sharepoint.com'
        $p.ClientId   | Should -Be 'cid'
        $p.Thumbprint | Should -Be 'ABC123'
        $p.ContainsKey('Interactive') | Should -BeFalse
    }

    It 'defaults to delegated interactive auth' {
        Mock Get-SPConfig { [pscustomobject]@{ ClientId = 'cid'; Tenant = 't'; AuthMode = 'Delegated' } }
        $p = Get-SPConnectParams -Url 'https://x.sharepoint.com'
        $p.Interactive | Should -BeTrue
        $p.ContainsKey('Thumbprint') | Should -BeFalse
    }

    It 'throws when no ClientId is saved' {
        Mock Get-SPConfig { [pscustomobject]@{} }
        { Get-SPConnectParams -Url 'https://x.sharepoint.com' } | Should -Throw
    }

    It 'throws for app-only config with no certificate' {
        Mock Get-SPConfig { [pscustomobject]@{ ClientId = 'cid'; AuthMode = 'AppOnly' } }
        { Get-SPConnectParams -Url 'https://x.sharepoint.com' } | Should -Throw
    }

    It 'preserves the saved device-code flavor on reconnect (was silently Interactive)' {
        Mock Get-SPConfig { [pscustomobject]@{ ClientId = 'cid'; AuthMode = 'Delegated'; DelegatedFlow = 'DeviceLogin' } }
        $p = Get-SPConnectParams -Url 'https://x.sharepoint.com'
        $p.DeviceLogin | Should -BeTrue
        $p.ContainsKey('Interactive') | Should -BeFalse
    }

    It 'reconnects with the OS broker when the saved flavor is OSLogin (standalone, no Interactive)' {
        Mock Get-SPConfig { [pscustomobject]@{ ClientId = 'cid'; AuthMode = 'Delegated'; DelegatedFlow = 'OSLogin' } }
        $p = Get-SPConnectParams -Url 'https://x.sharepoint.com'
        if ($IsWindows) {
            $p.OSLogin | Should -BeTrue
            $p.ContainsKey('Interactive') | Should -BeFalse
        }
        else {
            $p.Interactive | Should -BeTrue
        }
    }

    It 'never re-passes PersistLogin on reconnect (PnP needs it once)' {
        Mock Get-SPConfig { [pscustomobject]@{ ClientId = 'cid'; AuthMode = 'Delegated'; PersistLogin = $true } }
        (Get-SPConnectParams -Url 'https://x.sharepoint.com').ContainsKey('PersistLogin') | Should -BeFalse
    }
}

Describe 'Resolve-SPAuthChoice' {
    It 'certificate arguments always win' {
        $c = Resolve-SPAuthChoice -Cfg ([pscustomobject]@{ AuthMode = 'Delegated' }) -Thumbprint 'ABC'
        $c.Mode | Should -Be 'AppOnly'
        $c.Flow | Should -BeNullOrEmpty
    }
    It 'saved AuthMode=AppOnly is used when no delegated switch is given' {
        (Resolve-SPAuthChoice -Cfg ([pscustomobject]@{ AuthMode = 'AppOnly' })).Mode | Should -Be 'AppOnly'
    }
    It '-OSLogin overrides a saved AuthMode=AppOnly (the line-91 regression)' {
        $c = Resolve-SPAuthChoice -Cfg ([pscustomobject]@{ AuthMode = 'AppOnly' }) -OSLogin $true -OnWindows $true
        $c.Mode | Should -Be 'Delegated'
        $c.Flow | Should -Be 'OSLogin'
    }
    It '-DeviceLogin overrides a saved AuthMode=AppOnly' {
        (Resolve-SPAuthChoice -Cfg ([pscustomobject]@{ AuthMode = 'AppOnly' }) -DeviceLogin $true).Mode | Should -Be 'Delegated'
    }
    It 'reuses the saved DelegatedFlow when no switch is given' {
        (Resolve-SPAuthChoice -Cfg ([pscustomobject]@{ DelegatedFlow = 'DeviceLogin' })).Flow | Should -Be 'DeviceLogin'
    }
    It 'explicit switches beat the saved flavor' {
        (Resolve-SPAuthChoice -Cfg ([pscustomobject]@{ DelegatedFlow = 'OSLogin' }) -DeviceLogin $true -OnWindows $true).Flow | Should -Be 'DeviceLogin'
    }
    It 'throws on -DeviceLogin plus -OSLogin' {
        { Resolve-SPAuthChoice -Cfg ([pscustomobject]@{}) -DeviceLogin $true -OSLogin $true -OnWindows $true } | Should -Throw '*one of*'
    }
    It 'throws on explicit -OSLogin off Windows, but quietly downgrades a SAVED OSLogin flavor' {
        { Resolve-SPAuthChoice -Cfg ([pscustomobject]@{}) -OSLogin $true -OnWindows $false } | Should -Throw '*Windows-only*'
        (Resolve-SPAuthChoice -Cfg ([pscustomobject]@{ DelegatedFlow = 'OSLogin' }) -OnWindows $false).Flow | Should -Be 'Interactive'
    }
    It 'defaults to the browser (Interactive)' {
        (Resolve-SPAuthChoice -Cfg ([pscustomobject]@{})).Flow | Should -Be 'Interactive'
    }
}
