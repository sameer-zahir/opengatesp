#Requires -Version 7.4
# Tests for the pure Phase 4 helper — membership delta for Team/Group/Planner copy.
# Dot-sources the Private helper directly: no PnP.PowerShell, no tenant, CI-friendly.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\module\OpenGateSP\Private\Get-SPMembershipDelta.ps1')
}

Describe 'Get-SPMembershipDelta' {
    It 'returns members missing from the destination' {
        $r = Get-SPMembershipDelta -SourceMember @('a@x.com', 'b@x.com', 'c@x.com') -DestMember @('b@x.com')
        $r | Should -Be @('a@x.com', 'c@x.com')
    }
    It 'is case-insensitive' {
        Get-SPMembershipDelta -SourceMember @('Jane@X.com') -DestMember @('jane@x.com') | Should -BeNullOrEmpty
    }
    It 'returns all when the destination is empty' {
        (Get-SPMembershipDelta -SourceMember @('a@x.com', 'b@x.com') -DestMember @()).Count | Should -Be 2
    }
    It 'returns nothing when the source is empty' {
        Get-SPMembershipDelta -SourceMember @() -DestMember @('a@x.com') | Should -BeNullOrEmpty
    }
    It 'ignores blank entries' {
        (Get-SPMembershipDelta -SourceMember @('a@x.com', '', $null) -DestMember @()).Count | Should -Be 1
    }
}
