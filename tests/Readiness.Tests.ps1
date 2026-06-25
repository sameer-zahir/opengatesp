#Requires -Version 7.4
# Tests for Test-SPMigrationReadiness — a local, read-only pre-check, so these run
# without PnP.PowerShell or a live tenant. The fixture only uses names Windows/NTFS
# actually lets us create; the illegal-character and reserved-device-name branches
# can't be fixtured on Windows (the OS blocks creating them), so they're covered by
# review rather than here.

BeforeAll {
    $mod = Join-Path $PSScriptRoot '..\module\OpenGateSP'
    . (Join-Path $mod 'Private\Write-SPLog.ps1')
    . (Join-Path $mod 'Private\ConvertTo-SPOutput.ps1')
    . (Join-Path $mod 'Public\Test-SPMigrationReadiness.ps1')

    $script:Fix = Join-Path $TestDrive 'src'
    New-Item -ItemType Directory -Path $script:Fix -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:Fix 'clean.txt')        -Value 'ok' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $script:Fix 'report#1.txt')     -Value 'x'  -Encoding utf8
    Set-Content -LiteralPath (Join-Path $script:Fix '~$draft.docx')     -Value 'x'  -Encoding utf8
    Set-Content -LiteralPath (Join-Path $script:Fix 'cache.tmp')        -Value 'x'  -Encoding utf8
    Set-Content -LiteralPath (Join-Path $script:Fix '_vti_secret.txt')  -Value 'x'  -Encoding utf8
    New-Item -ItemType File -Path (Join-Path $script:Fix 'empty.txt') -Force | Out-Null

    $script:Rows = @(Test-SPMigrationReadiness -Source $script:Fix)
}

Describe 'Test-SPMigrationReadiness' {
    It 'throws on a missing source' {
        { Test-SPMigrationReadiness -Source (Join-Path $TestDrive 'does-not-exist') } | Should -Throw
    }
    It 'leaves a clean file alone' {
        ($script:Rows | Where-Object Path -eq 'clean.txt') | Should -BeNullOrEmpty
    }
    It 'flags # / % as a discouraged-characters warning' {
        $r = $script:Rows | Where-Object { $_.Path -eq 'report#1.txt' -and $_.Issue -eq 'Discouraged characters' }
        $r | Should -Not -BeNullOrEmpty
        $r.Severity | Should -Be 'Warning'
    }
    It 'flags a ~$ temp file' {
        ($script:Rows | Where-Object { $_.Path -eq '~$draft.docx' -and $_.Issue -eq 'Temp/system file' }) | Should -Not -BeNullOrEmpty
    }
    It 'flags an excluded extension' {
        ($script:Rows | Where-Object { $_.Path -eq 'cache.tmp' -and $_.Issue -eq 'Excluded type' }) | Should -Not -BeNullOrEmpty
    }
    It 'flags a _vti_ reserved prefix as an error' {
        $r = $script:Rows | Where-Object { $_.Path -eq '_vti_secret.txt' -and $_.Issue -eq 'Reserved prefix' }
        $r | Should -Not -BeNullOrEmpty
        $r.Severity | Should -Be 'Error'
    }
    It 'flags an empty file' {
        ($script:Rows | Where-Object { $_.Path -eq 'empty.txt' -and $_.Issue -eq 'Empty file' }) | Should -Not -BeNullOrEmpty
    }
    It 'sorts errors before warnings' {
        $firstWarn = [array]::IndexOf([string[]]$script:Rows.Severity, 'Warning')
        $lastErr   = [array]::LastIndexOf([string[]]$script:Rows.Severity, 'Error')
        $lastErr | Should -BeLessThan $firstWarn
    }
    It 'flags a path that exceeds MaxPathLength' {
        $rows = @(Test-SPMigrationReadiness -Source $script:Fix -SiteUrl 'https://contoso.sharepoint.com/sites/x' -MaxPathLength 20)
        ($rows | Where-Object Issue -eq 'Path too long') | Should -Not -BeNullOrEmpty
    }
    It 'returns a JSON array string with -AsJson' {
        $json = Test-SPMigrationReadiness -Source $script:Fix -AsJson
        $json | Should -BeOfType [string]
        ($json | ConvertFrom-Json).Count | Should -BeGreaterThan 0
    }
    It 'returns nothing for a clean folder' {
        $cleanDir = Join-Path $TestDrive 'cleanonly'
        New-Item -ItemType Directory -Path $cleanDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $cleanDir 'fine.txt') -Value 'ok' -Encoding utf8
        @(Test-SPMigrationReadiness -Source $cleanDir) | Should -BeNullOrEmpty
    }
}
