#Requires -Version 7.4
# Tests for the pure post-migration validation helper — structure diff. No PnP, no tenant.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\module\OpenGateSP\Private\Compare-SPStructure.ps1')
}

Describe 'Compare-SPStructure' {
    It 'marks matching lists with equal counts as Match' {
        $src = @([pscustomobject]@{ Title = 'Documents'; ItemCount = 10 })
        $dst = @([pscustomobject]@{ Title = 'Documents'; ItemCount = 10 })
        $r = @(Compare-SPStructure -Source $src -Destination $dst)
        $r[0].Status | Should -Be 'Match'
    }
    It 'flags count differences as CountMismatch' {
        $src = @([pscustomobject]@{ Title = 'Documents'; ItemCount = 10 })
        $dst = @([pscustomobject]@{ Title = 'Documents'; ItemCount = 7 })
        $r = @(Compare-SPStructure -Source $src -Destination $dst)
        $r[0].Status | Should -Be 'CountMismatch'
        $r[0].SourceCount | Should -Be 10
        $r[0].DestCount | Should -Be 7
    }
    It 'flags a source list absent at the destination as Missing' {
        $src = @([pscustomobject]@{ Title = 'Contracts'; ItemCount = 3 })
        $r = @(Compare-SPStructure -Source $src -Destination @())
        $r[0].Status | Should -Be 'Missing'
        $r[0].InDest | Should -Be $false
    }
    It 'flags a destination-only list as ExtraInDest' {
        $dst = @([pscustomobject]@{ Title = 'Leftovers'; ItemCount = 1 })
        $r = @(Compare-SPStructure -Source @() -Destination $dst)
        $r[0].Status | Should -Be 'ExtraInDest'
        $r[0].InSource | Should -Be $false
    }
    It 'matches titles case-insensitively' {
        $src = @([pscustomobject]@{ Title = 'Shared Documents'; ItemCount = 5 })
        $dst = @([pscustomobject]@{ Title = 'shared documents'; ItemCount = 5 })
        $r = @(Compare-SPStructure -Source $src -Destination $dst)
        $r.Count | Should -Be 1
        $r[0].Status | Should -Be 'Match'
    }
    It 'returns nothing for two empty sites' {
        @(Compare-SPStructure -Source @() -Destination @()) | Should -BeNullOrEmpty
    }
}
