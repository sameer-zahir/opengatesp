#Requires -Version 7.4
# Tests for the pure Phase 5 governance helpers — permission matrix + orphan detection.
# Dot-sources the Private helpers directly: no PnP.PowerShell, no tenant, CI-friendly.

BeforeAll {
    $priv = Join-Path $PSScriptRoot '..\module\OpenGateSP\Private'
    . (Join-Path $priv 'ConvertTo-SPPrincipalKey.ps1')
    . (Join-Path $priv 'ConvertTo-SPPermissionMatrix.ps1')
    . (Join-Path $priv 'Get-SPOrphanedPrincipals.ps1')
}

Describe 'ConvertTo-SPPermissionMatrix' {
    It 'groups grants by principal' {
        $rows = @(
            [pscustomobject]@{ Principal = 'Jane'; Object = 'Site'; Roles = @('Full Control') }
            [pscustomobject]@{ Principal = 'Jane'; ListTitle = 'Docs'; Roles = @('Edit') }
            [pscustomobject]@{ Principal = 'Bob';  Object = 'Site'; Roles = @('Read') }
        )
        $m = @(ConvertTo-SPPermissionMatrix -Assignment $rows)
        $m.Count | Should -Be 2
        $jane = $m | Where-Object Principal -eq 'Jane'
        $jane.AccessCount | Should -Be 2
        $jane.Grants | Should -Match 'Docs: Edit'
        $jane.Grants | Should -Match 'Site: Full Control'
    }
    It 'falls back to the Permission field when Roles is absent' {
        $m = @(ConvertTo-SPPermissionMatrix -Assignment @([pscustomobject]@{ Principal = 'X'; Object = 'Site'; Permission = 'Read' }))
        $m[0].Grants | Should -Be 'Site: Read'
    }
    It 'returns nothing for no assignments' {
        @(ConvertTo-SPPermissionMatrix -Assignment @()) | Should -BeNullOrEmpty
    }
}

Describe 'Get-SPOrphanedPrincipals' {
    It 'flags site users not in the directory' {
        $site = @(
            [pscustomobject]@{ LoginName = 'i:0#.f|membership|gone@contoso.com'; Title = 'Gone User' }
            [pscustomobject]@{ LoginName = 'i:0#.f|membership|here@contoso.com'; Title = 'Here User' }
        )
        $dir = @('here@contoso.com', 'someone@contoso.com')
        $orphans = @(Get-SPOrphanedPrincipals -SitePrincipal $site -DirectoryLogin $dir)
        $orphans.Count | Should -Be 1
        $orphans[0].Title | Should -Be 'Gone User'
    }
    It 'ignores SharePoint groups / non-user principals' {
        $site = @([pscustomobject]@{ LoginName = 'Marketing Members'; Title = 'Marketing Members' })
        @(Get-SPOrphanedPrincipals -SitePrincipal $site -DirectoryLogin @()) | Should -BeNullOrEmpty
    }
    It 'is case-insensitive on the directory match' {
        $site = @([pscustomobject]@{ LoginName = 'Jane@Contoso.com'; Title = 'Jane' })
        @(Get-SPOrphanedPrincipals -SitePrincipal $site -DirectoryLogin @('jane@contoso.com')) | Should -BeNullOrEmpty
    }
}
