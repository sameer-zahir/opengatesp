#Requires -Version 7.4
# Unit tests for connection-parameter building (no PnP / tenant needed; config is mocked).

BeforeAll {
    $priv = Join-Path $PSScriptRoot '..\module\OpenGateSP\Private'
    . (Join-Path $priv 'Write-SPLog.ps1')
    . (Join-Path $priv 'SPConfig.ps1')
    . (Join-Path $priv 'Get-SPConnectParams.ps1')
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
}
