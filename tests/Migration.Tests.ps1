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
    . (Join-Path $priv 'Measure-SPBatchOutcome.ps1')
    . (Join-Path $priv 'Select-SPChangedItems.ps1')
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

Describe 'Measure-SPBatchOutcome' {
    It 'flags an empty batch output as unconfirmed instead of inventing failures' {
        $r = Measure-SPBatchOutcome -BatchOutput @() -Queued 7
        $r.Copied    | Should -Be 7
        $r.Failed    | Should -Be 0
        $r.Confirmed | Should -BeFalse
    }
    It 'counts every clean result as copied' {
        $out = 1..3 | ForEach-Object { [pscustomobject]@{ StatusCode = 201 } }
        $r = Measure-SPBatchOutcome -BatchOutput $out -Queued 3
        $r.Copied    | Should -Be 3
        $r.Failed    | Should -Be 0
        $r.Confirmed | Should -BeTrue
    }
    It 'never reports a failed request as copied (error property)' {
        $out = @(
            [pscustomobject]@{ ErrorMessage = $null }
            [pscustomobject]@{ ErrorMessage = 'Column X does not exist' }
            [pscustomobject]@{ Error = 'The item could not be added' }
        )
        $r = Measure-SPBatchOutcome -BatchOutput $out -Queued 3
        $r.Copied | Should -Be 1
        $r.Failed | Should -Be 2
        $r.Errors | Should -Contain 'Column X does not exist'
    }
    It 'treats an HTTP status >= 400 as a failure' {
        $out = @(
            [pscustomobject]@{ ResponseStatusCode = 500 }
            [pscustomobject]@{ ResponseStatusCode = 204 }
        )
        $r = Measure-SPBatchOutcome -BatchOutput $out -Queued 2
        $r.Failed | Should -Be 1
        $r.Copied | Should -Be 1
    }
    It 'caps the captured error messages at 5' {
        $out = 1..9 | ForEach-Object { [pscustomobject]@{ Error = "err$_" } }
        $r = Measure-SPBatchOutcome -BatchOutput $out -Queued 9
        $r.Failed | Should -Be 9
        @($r.Errors).Count | Should -Be 5
    }
}

Describe 'Select-SPChangedItems UTC handling' {
    It 'treats Kind=Unspecified timestamps as UTC on both sides (deterministic cut-off)' {
        $items = @(
            [pscustomobject]@{ Id = 1; Modified = [datetime]::SpecifyKind((Get-Date '2026-07-01T09:59:59'), 'Unspecified') }
            [pscustomobject]@{ Id = 2; Modified = [datetime]::SpecifyKind((Get-Date '2026-07-01T10:00:00'), 'Unspecified') }
        )
        $since = [datetime]::SpecifyKind((Get-Date '2026-07-01T10:00:00'), 'Utc')
        $r = @(Select-SPChangedItems -SourceItem $items -Since $since)
        @($r).Id | Should -Be @(2)
    }
    It 'converts a Kind=Local -Since so it compares as the same instant, not the same wall-clock' {
        # 10:00 UTC expressed as local time must keep an item modified 10:30 UTC and drop 09:30 UTC,
        # regardless of the machine's timezone.
        $sinceLocal = ([datetime]::SpecifyKind((Get-Date '2026-07-01T10:00:00'), 'Utc')).ToLocalTime()
        $items = @(
            [pscustomobject]@{ Id = 1; Modified = [datetime]::SpecifyKind((Get-Date '2026-07-01T09:30:00'), 'Unspecified') }
            [pscustomobject]@{ Id = 2; Modified = [datetime]::SpecifyKind((Get-Date '2026-07-01T10:30:00'), 'Unspecified') }
        )
        $r = @(Select-SPChangedItems -SourceItem $items -Since $sinceLocal)
        @($r).Id | Should -Be @(2)
    }
    It 'converges when the DestIndex holds the same instant in a different kind' {
        $items = @([pscustomobject]@{ Id = 5; Modified = [datetime]::SpecifyKind((Get-Date '2026-07-01T12:00:00'), 'Unspecified') })
        $dest = @{ '5' = ([datetime]::SpecifyKind((Get-Date '2026-07-01T12:00:00'), 'Utc')).ToLocalTime() }
        @(Select-SPChangedItems -SourceItem $items -DestIndex $dest).Count | Should -Be 0
    }
}
