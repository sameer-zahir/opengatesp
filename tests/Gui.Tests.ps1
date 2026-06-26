#Requires -Version 7.4
# Unit tests for the pure GUI helpers (gui\Common.ps1). No WPF or live tenant needed.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\gui\Common.ps1')
    $G = '11111111-2222-3333-4444-555555555555'
}

Describe 'Get-SPAppIdFromResult' {
    It 'reads ClientId from an object' {
        Get-SPAppIdFromResult ([pscustomobject]@{ ClientId = $G }) | Should -Be $G
    }
    It 'reads AzureAppId from an object' {
        Get-SPAppIdFromResult ([pscustomobject]@{ AzureAppId = $G }) | Should -Be $G
    }
    It 'reads the slash-named property from a hashtable' {
        Get-SPAppIdFromResult @{ 'AzureAppId/ClientId' = $G } | Should -Be $G
    }
    It 'pulls a GUID out of host text' {
        Get-SPAppIdFromResult "App 'OpenGateSP' with id $G created." | Should -Be $G
    }
    It 'returns null when there is no GUID' {
        Get-SPAppIdFromResult 'no id here' | Should -BeNullOrEmpty
    }
    It 'returns null for null input' {
        Get-SPAppIdFromResult $null | Should -BeNullOrEmpty
    }
}

Describe 'Test-SPConnectInput' {
    It 'accepts a valid client id (no problems)' {
        (Test-SPConnectInput -ClientId $G).Count | Should -Be 0
    }
    It 'requires a client id' {
        (Test-SPConnectInput -ClientId '').Count | Should -BeGreaterThan 0
    }
    It 'rejects a non-GUID client id' {
        (Test-SPConnectInput -ClientId 'not-a-guid') -join "`n" | Should -Match 'GUID'
    }
    It 'accepts a well-formed tenant and url' {
        (Test-SPConnectInput -ClientId $G -Tenant 'contoso.onmicrosoft.com' -Url 'https://contoso.sharepoint.com/sites/Marketing').Count | Should -Be 0
    }
    It 'flags a malformed tenant' {
        (Test-SPConnectInput -ClientId $G -Tenant 'contoso') -join "`n" | Should -Match 'Tenant'
    }
    It 'flags a malformed site url' {
        (Test-SPConnectInput -ClientId $G -Url 'http://example.com') -join "`n" | Should -Match 'Site URL'
    }
}
