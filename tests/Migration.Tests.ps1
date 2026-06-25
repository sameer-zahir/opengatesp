#Requires -Version 7.4
# Tests for the pure SP->SP copy-planning helpers. These dot-source the Private
# helpers directly, so they run with no PnP.PowerShell and no tenant (CI-friendly).
# The PnP I/O (Get-PnPSiteTemplate, Copy-PnPFile, etc.) is verified by dry-runs and
# the manual test plan against a real tenant, not here.

BeforeAll {
    $priv = Join-Path $PSScriptRoot '..\module\OpenGateSP\Private'
    . (Join-Path $priv 'Resolve-SPConflict.ps1')
    . (Join-Path $priv 'New-SPCopyResult.ps1')
    . (Join-Path $priv 'Get-SPCopyPlan.ps1')
}

Describe 'Resolve-SPConflict' {
    It 'creates when the object is absent at the destination' {
        (Resolve-SPConflict -Exists $false -Mode Replace).Action | Should -Be 'Create'
    }
    It 'overwrites an existing object in Replace mode' {
        (Resolve-SPConflict -Exists $true -Mode Replace).Action | Should -Be 'Overwrite'
    }
    It 'skips an existing object in Skip mode' {
        (Resolve-SPConflict -Exists $true -Mode Skip).Action | Should -Be 'Skip'
    }
    It 'renames (keep both) an existing object in KeepBoth mode' {
        (Resolve-SPConflict -Exists $true -Mode KeepBoth).Action | Should -Be 'Rename'
    }
    It 'IfNewer overwrites when the source is newer' {
        $r = Resolve-SPConflict -Exists $true -Mode IfNewer -SourceModified (Get-Date '2026-06-01') -DestModified (Get-Date '2026-01-01')
        $r.Action | Should -Be 'Overwrite'
    }
    It 'IfNewer skips when the destination is same or newer' {
        $r = Resolve-SPConflict -Exists $true -Mode IfNewer -SourceModified (Get-Date '2026-01-01') -DestModified (Get-Date '2026-06-01')
        $r.Action | Should -Be 'Skip'
    }
    It 'IfNewer copies when the destination has no timestamp' {
        (Resolve-SPConflict -Exists $true -Mode IfNewer -SourceModified (Get-Date '2026-01-01') -DestModified $null).Action | Should -Be 'Overwrite'
    }
}

Describe 'New-SPCopyResult' {
    It 'shapes a report row with the expected fields' {
        $r = New-SPCopyResult -ObjectType 'List' -Name 'Docs' -Action 'Create' -Status 'WouldCopy' -Detail 'x'
        $r.ObjectType | Should -Be 'List'
        $r.Name | Should -Be 'Docs'
        $r.Action | Should -Be 'Create'
        $r.Status | Should -Be 'WouldCopy'
    }
}

Describe 'Get-SPCopyPlan' {
    It 'returns nothing for an empty source' {
        @(Get-SPCopyPlan -SourceObjects @()) | Should -BeNullOrEmpty
    }
    It 'plans create/overwrite/skip correctly with IfNewer' {
        $src = @(
            [pscustomobject]@{ Name = 'A'; ObjectType = 'List'; Modified = (Get-Date '2026-06-01') }  # exists, newer -> overwrite
            [pscustomobject]@{ Name = 'B'; ObjectType = 'List'; Modified = (Get-Date '2026-01-01') }  # exists, older -> skip
            [pscustomobject]@{ Name = 'C'; ObjectType = 'List'; Modified = (Get-Date '2026-06-01') }  # absent  -> create
        )
        $dst = @(
            [pscustomobject]@{ Name = 'A'; Modified = (Get-Date '2026-01-01') }
            [pscustomobject]@{ Name = 'B'; Modified = (Get-Date '2026-06-01') }
        )
        $plan = @(Get-SPCopyPlan -SourceObjects $src -DestObjects $dst -Mode IfNewer)
        $plan.Count | Should -Be 3
        ($plan | Where-Object Name -eq 'A').Action | Should -Be 'Overwrite'
        ($plan | Where-Object Name -eq 'B').Action | Should -Be 'Skip'
        ($plan | Where-Object Name -eq 'B').Status | Should -Be 'Skipped'
        ($plan | Where-Object Name -eq 'C').Action | Should -Be 'Create'
        ($plan | Where-Object Name -eq 'C').Status | Should -Be 'WouldCopy'
    }
    It 'overwrites all existing in Replace mode' {
        $src = @([pscustomobject]@{ Name = 'A'; ObjectType = 'List'; Modified = $null })
        $dst = @([pscustomobject]@{ Name = 'A'; Modified = $null })
        (Get-SPCopyPlan -SourceObjects $src -DestObjects $dst -Mode Replace).Action | Should -Be 'Overwrite'
    }
}
