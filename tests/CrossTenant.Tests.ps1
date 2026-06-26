#Requires -Version 7.4
# Tests for the pure Phase 3 helper — cross-tenant/cross-web URL remapping.
# Dot-sources the Private helper directly: no PnP.PowerShell, no tenant, CI-friendly.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\module\OpenGateSP\Private\Resolve-SPCrossTenantUrl.ps1')
}

Describe 'Resolve-SPCrossTenantUrl' {
    It 'swaps the web prefix for a file URL' {
        Resolve-SPCrossTenantUrl -SourceServerRelativeUrl '/sites/A/Shared Documents/x.docx' `
            -SourceWebServerRelativeUrl '/sites/A' -DestinationWebServerRelativeUrl '/sites/B' |
            Should -Be '/sites/B/Shared Documents/x.docx'
    }
    It 'handles a nested folder path' {
        Resolve-SPCrossTenantUrl -SourceServerRelativeUrl '/sites/A/Docs/sub/deep/f.txt' `
            -SourceWebServerRelativeUrl '/sites/A' -DestinationWebServerRelativeUrl '/teams/B' |
            Should -Be '/teams/B/Docs/sub/deep/f.txt'
    }
    It 'maps the web root itself' {
        Resolve-SPCrossTenantUrl -SourceServerRelativeUrl '/sites/A' `
            -SourceWebServerRelativeUrl '/sites/A' -DestinationWebServerRelativeUrl '/sites/B' |
            Should -Be '/sites/B'
    }
    It 'tolerates a trailing slash on the web URLs' {
        Resolve-SPCrossTenantUrl -SourceServerRelativeUrl '/sites/A/Docs/f.txt' `
            -SourceWebServerRelativeUrl '/sites/A/' -DestinationWebServerRelativeUrl '/sites/B/' |
            Should -Be '/sites/B/Docs/f.txt'
    }
    It 'throws when the URL is not under the source web' {
        { Resolve-SPCrossTenantUrl -SourceServerRelativeUrl '/sites/OTHER/x.txt' `
            -SourceWebServerRelativeUrl '/sites/A' -DestinationWebServerRelativeUrl '/sites/B' } |
            Should -Throw
    }
}
