#Requires -Version 7.4
# Tests for the pure Explore helpers — finding normalization, inactive-site selection,
# and version-bloat detection. Dot-sources the Private helpers directly: no PnP, no tenant.

BeforeAll {
    $priv = Join-Path $PSScriptRoot '..\module\OpenGateSP\Private'
    . (Join-Path $priv 'ConvertTo-SPExploreFinding.ps1')
    . (Join-Path $priv 'Select-SPInactiveSites.ps1')
    . (Join-Path $priv 'Measure-SPVersionBloat.ps1')
}

Describe 'ConvertTo-SPExploreFinding' {
    It 'emits one finding per item with the standard shape' {
        $rows = @(
            [pscustomobject]@{ FileRef = '/sites/x/Docs/a.docx' }
            [pscustomobject]@{ FileRef = '/sites/x/Docs/b.docx' }
        )
        $f = @(ConvertTo-SPExploreFinding -Item $rows -Category 'Checked-out files' -Severity 'Warning')
        $f.Count | Should -Be 2
        $f[0].Category | Should -Be 'Checked-out files'
        $f[0].Severity | Should -Be 'Warning'
        $f[0].Name | Should -Be '/sites/x/Docs/a.docx'
        $f[0].Count | Should -Be 1
    }
    It 'aggregates to a single summary finding with a Count' {
        $rows = 1..5 | ForEach-Object { [pscustomobject]@{ Name = "f$_" } }
        $f = @(ConvertTo-SPExploreFinding -Item $rows -Category 'Large files' -Severity 'Info' -Aggregate)
        $f.Count | Should -Be 1
        $f[0].Count | Should -Be 5
        $f[0].Name | Should -Match '5 item'
    }
    It 'honors an explicit NameProperty and DetailProperty' {
        $rows = @([pscustomobject]@{ Login = 'guest#ext#'; Note = 'external' })
        $f = @(ConvertTo-SPExploreFinding -Item $rows -Category 'External' -ItemType 'User' -NameProperty 'Login' -DetailProperty 'Note')
        $f[0].ItemType | Should -Be 'User'
        $f[0].Name | Should -Be 'guest#ext#'
        $f[0].Detail | Should -Be 'external'
    }
    It 'returns nothing for no items' {
        @(ConvertTo-SPExploreFinding -Item @() -Category 'X') | Should -BeNullOrEmpty
    }
}

Describe 'Select-SPInactiveSites' {
    BeforeAll {
        $asOf = [datetime]'2026-06-01'
        $script:sites = @(
            [pscustomobject]@{ Url = 'https://c/sites/fresh'; Title = 'Fresh'; LastActivity = [datetime]'2026-05-20'; StorageUsedMB = 10 }
            [pscustomobject]@{ Url = 'https://c/sites/stale'; Title = 'Stale'; LastActivity = [datetime]'2025-01-01'; StorageUsedMB = 99 }
            [pscustomobject]@{ Url = 'https://c/sites/unknown'; Title = 'Unknown'; LastActivity = $null; StorageUsedMB = 5 }
        )
        $script:asOf = $asOf
    }
    It 'flags sites past the inactivity threshold' {
        $r = @(Select-SPInactiveSites -Site $script:sites -InactiveDays 180 -AsOf $script:asOf)
        ($r | Where-Object Reason -eq 'Inactive').Title | Should -Be 'Stale'
    }
    It 'excludes recently active sites' {
        $r = @(Select-SPInactiveSites -Site $script:sites -InactiveDays 180 -AsOf $script:asOf)
        $r.Title | Should -Not -Contain 'Fresh'
    }
    It 'computes InactiveDays from the reference date' {
        $r = @(Select-SPInactiveSites -Site $script:sites -InactiveDays 180 -AsOf $script:asOf)
        $stale = $r | Where-Object Title -eq 'Stale'
        $stale.InactiveDays | Should -BeGreaterThan 500
    }
    It 'flags sites with no activity data' {
        $r = @(Select-SPInactiveSites -Site $script:sites -InactiveDays 180 -AsOf $script:asOf)
        ($r | Where-Object Reason -eq 'NoActivityData').Title | Should -Be 'Unknown'
    }
}

Describe 'Measure-SPVersionBloat' {
    It 'flags files over the version-count threshold' {
        $r = @(Measure-SPVersionBloat -Item @([pscustomobject]@{ Name = 'big.docx'; VersionCount = 120; VersionSizeMB = 5 }) -MaxVersions 50)
        $r.Count | Should -Be 1
        $r[0].Reason | Should -Match 'versions=120'
    }
    It 'flags files over the version-size threshold' {
        $r = @(Measure-SPVersionBloat -Item @([pscustomobject]@{ Name = 'fat.zip'; VersionCount = 3; VersionSizeMB = 250 }) -MaxVersionSizeMB 100)
        $r.Count | Should -Be 1
        $r[0].Reason | Should -Match 'versionMB'
    }
    It 'ignores files within both thresholds' {
        @(Measure-SPVersionBloat -Item @([pscustomobject]@{ Name = 'ok.txt'; VersionCount = 4; VersionSizeMB = 2 })) | Should -BeNullOrEmpty
    }
}
