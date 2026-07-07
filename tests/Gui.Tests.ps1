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

Describe 'Get-SPDeviceCodeFromText' {
    It 'parses the standard MSAL device-code message' {
        $r = Get-SPDeviceCodeFromText 'To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code CN2KLBQWZ to authenticate.'
        $r.Code | Should -Be 'CN2KLBQWZ'
        $r.Url | Should -Be 'https://microsoft.com/devicelogin'
    }
    It 'parses a hyphenated code and the aka.ms URL variant' {
        $r = Get-SPDeviceCodeFromText 'To sign in, use a web browser to open the page https://www.microsoft.com/link and enter the code ABCD-EFGH to authenticate.'
        $r.Code | Should -Be 'ABCD-EFGH'
    }
    It 'falls back to a loose code + devicelogin-URL scan when the wording differs' {
        $r = Get-SPDeviceCodeFromText 'Sign in at https://microsoft.com/devicelogin. Use code H4XR2PLM9 when asked.'
        $r.Code | Should -Be 'H4XR2PLM9'
        $r.Url | Should -Be 'https://microsoft.com/devicelogin'
    }
    It 'returns null for unrelated text and empty input' {
        Get-SPDeviceCodeFromText 'Connecting to https://contoso.sharepoint.com ...' | Should -BeNullOrEmpty
        Get-SPDeviceCodeFromText '' | Should -BeNullOrEmpty
    }
}
