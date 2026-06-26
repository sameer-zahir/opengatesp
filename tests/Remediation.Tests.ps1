#Requires -Version 7.4
# Tests for the pure remediation helper — which file versions to trim. No PnP, no tenant.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\module\OpenGateSP\Private\Select-SPVersionsToTrim.ps1')
}

Describe 'Select-SPVersionsToTrim' {
    BeforeAll {
        $script:versions = 1..12 | ForEach-Object { [pscustomobject]@{ ID = $_; VersionLabel = "0.$_" } }
    }
    It 'keeps the newest N and returns the rest oldest-first' {
        $r = @(Select-SPVersionsToTrim -Version $script:versions -Keep 10)
        $r.Count | Should -Be 2
        $r[0].ID | Should -Be 1
        $r[1].ID | Should -Be 2
    }
    It 'returns nothing when the count is at or below Keep' {
        @(Select-SPVersionsToTrim -Version $script:versions -Keep 12) | Should -BeNullOrEmpty
        @(Select-SPVersionsToTrim -Version $script:versions -Keep 50) | Should -BeNullOrEmpty
    }
    It 'removes all when Keep is zero' {
        @(Select-SPVersionsToTrim -Version $script:versions -Keep 0).Count | Should -Be 12
    }
    It 'sorts numerically, not lexically' {
        $unordered = @(2, 11, 1, 10) | ForEach-Object { [pscustomobject]@{ ID = $_ } }
        $r = @(Select-SPVersionsToTrim -Version $unordered -Keep 2)
        $r.Count | Should -Be 2
        $r[0].ID | Should -Be 1
        $r[1].ID | Should -Be 2
    }
    It 'tolerates empty input' {
        @(Select-SPVersionsToTrim -Version @() -Keep 5) | Should -BeNullOrEmpty
    }
}
