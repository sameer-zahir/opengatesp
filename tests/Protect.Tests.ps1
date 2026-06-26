#Requires -Version 7.4
# Unit tests for Protect-style governance detection (pure decision logic; no tenant / PnP).

BeforeAll {
    . (Join-Path $PSScriptRoot '..\module\OpenGateSP\Private\Select-SPEveryoneClaims.ps1')
}

Describe 'Select-SPEveryoneClaims' {
    It 'flags EEEU and Everyone, ignores normal principals' {
        $assignments = @(
            [pscustomobject]@{ Scope = 'Site'; ListTitle = $null; LoginName = 'c:0-.f|rolemanager|spo-grid-all-users/abc'; Principal = 'Everyone except external users'; Roles = @('Read') }
            [pscustomobject]@{ Scope = 'List'; ListTitle = 'Documents'; LoginName = 'c:0(.s|true'; Principal = 'Everyone'; Roles = @('Edit') }
            [pscustomobject]@{ Scope = 'Site'; ListTitle = $null; LoginName = 'i:0#.f|membership|jane@contoso.com'; Principal = 'Jane'; Roles = @('Full Control') }
        )
        $f = @(Select-SPEveryoneClaims -Assignment $assignments)
        $f.Count | Should -Be 2
        ($f | Where-Object { $_.Claim -eq 'Everyone except external users' }).Severity | Should -Be 'Warning'  # read only
        ($f | Where-Object { $_.Claim -eq 'Everyone' }).Severity | Should -Be 'Error'                          # Edit = write
        ($f | Where-Object { $_.Claim -eq 'Everyone' }).Location | Should -Be 'Documents'
    }
    It 'grades a broad grant with write access as an Error' {
        $f = @(Select-SPEveryoneClaims -Assignment @([pscustomobject]@{ Scope = 'Site'; LoginName = 'spo-grid-all-users/x'; Principal = 'Everyone except external users'; Roles = @('Full Control') }))
        $f[0].Severity | Should -Be 'Error'
    }
    It 'detects "Everyone" by title even without the claim login' {
        $f = @(Select-SPEveryoneClaims -Assignment @([pscustomobject]@{ Scope = 'Site'; LoginName = 'something'; Principal = 'Everyone'; Roles = @('Read') }))
        $f.Count | Should -Be 1
        $f[0].Claim | Should -Be 'Everyone'
    }
    It 'returns nothing for an empty or null set' {
        @(Select-SPEveryoneClaims -Assignment @()).Count | Should -Be 0
        @(Select-SPEveryoneClaims -Assignment $null).Count | Should -Be 0
    }
}
