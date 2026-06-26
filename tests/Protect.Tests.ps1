#Requires -Version 7.4
# Unit tests for Protect-style governance detection (pure decision logic; no tenant / PnP).

BeforeAll {
    . (Join-Path $PSScriptRoot '..\module\OpenGateSP\Private\Select-SPEveryoneClaims.ps1')
    . (Join-Path $PSScriptRoot '..\module\OpenGateSP\Private\Select-SPOwnerlessGroups.ps1')
    . (Join-Path $PSScriptRoot '..\module\OpenGateSP\Private\ConvertTo-SPExploreFinding.ps1')
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

Describe 'Select-SPOwnerlessGroups' {
    It 'returns only groups with no owner' {
        $groups = @(
            [pscustomobject]@{ DisplayName = 'Marketing'; Mail = 'mktg@x.com'; Visibility = 'Private'; OwnerCount = 2 }
            [pscustomobject]@{ DisplayName = 'Orphan A'; Mail = 'a@x.com'; Visibility = 'Public'; OwnerCount = 0 }
            [pscustomobject]@{ DisplayName = 'Orphan B'; Mail = 'b@x.com'; Visibility = 'Private'; OwnerCount = 0 }
        )
        $o = @(Select-SPOwnerlessGroups -Group $groups)
        $o.Count | Should -Be 2
        ($o | Where-Object { $_.DisplayName -eq 'Orphan A' }).Severity | Should -Be 'Error'    # public
        ($o | Where-Object { $_.DisplayName -eq 'Orphan B' }).Severity | Should -Be 'Warning'  # private
    }
    It 'returns nothing when every group has an owner' {
        @(Select-SPOwnerlessGroups -Group @([pscustomobject]@{ DisplayName = 'X'; Visibility = 'Public'; OwnerCount = 1 })).Count | Should -Be 0
    }
    It 'handles an empty set' {
        @(Select-SPOwnerlessGroups -Group @()).Count | Should -Be 0
    }
}

Describe 'Governance review normalization' {
    It 'normalizes broad-access findings into graded review items' {
        $broad = @(
            [pscustomobject]@{ Claim = 'Everyone'; Scope = 'Site'; Location = 'Site'; Roles = 'Edit'; Severity = 'Error' }
            [pscustomobject]@{ Claim = 'Everyone except external users'; Scope = 'List'; Location = 'Docs'; Roles = 'Read'; Severity = 'Warning' }
        )
        $f = @(ConvertTo-SPExploreFinding -Item $broad -Category 'Broad access (Everyone/EEEU)' -Severity 'Error' -ItemType 'Grant' -NameProperty 'Claim' -DetailProperty 'Roles')
        $f.Count | Should -Be 2
        $f[0].Category | Should -Be 'Broad access (Everyone/EEEU)'
        $f[0].Severity | Should -Be 'Error'
        ($f | Where-Object { $_.Name -eq 'Everyone' }).Detail | Should -Be 'Edit'
    }
}
