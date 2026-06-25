#Requires -Version 7.4
# Unit tests for the pure helper functions. These dot-source the Private helpers
# directly so they run without PnP.PowerShell or a live tenant (CI-friendly).

BeforeAll {
    $priv = Join-Path $PSScriptRoot '..\module\OpenGateSP\Private'
    . (Join-Path $priv 'Write-SPLog.ps1')
    . (Join-Path $priv 'ConvertTo-SPOutput.ps1')
    . (Join-Path $priv 'Invoke-SPRetry.ps1')
    . (Join-Path $priv 'SPConfig.ps1')
}

Describe 'ConvertTo-SPOutput' {
    It 'passes objects through unchanged by default' {
        $in  = 1..3 | ForEach-Object { [pscustomobject]@{ N = $_ } }
        $out = $in | ConvertTo-SPOutput
        @($out).Count | Should -Be 3
    }
    It 'emits a JSON array string with -AsJson' {
        $json = ([pscustomobject]@{ A = 1 }) | ConvertTo-SPOutput -AsJson
        $json | Should -BeOfType [string]
        ($json | ConvertFrom-Json).A | Should -Be 1
    }
    It 'returns an empty JSON array for no input with -AsJson' {
        (@() | ConvertTo-SPOutput -AsJson) | Should -Be '[]'
    }
}

Describe 'Invoke-SPRetry' {
    It 'returns the script block result on success' {
        Invoke-SPRetry -InitialDelaySeconds 0 { 42 } | Should -Be 42
    }
    It 'retries on a throttling (429) error, then succeeds' {
        $counter = [pscustomobject]@{ N = 0 }
        $result = Invoke-SPRetry -InitialDelaySeconds 0 -MaxRetries 5 {
            $counter.N++
            if ($counter.N -lt 3) { throw 'The remote server returned 429 Too Many Requests.' }
            'ok'
        }
        $result    | Should -Be 'ok'
        $counter.N | Should -Be 3
    }
    It 'rethrows a non-transient error immediately (no retry)' {
        $counter = [pscustomobject]@{ N = 0 }
        { Invoke-SPRetry -InitialDelaySeconds 0 { $counter.N++; throw 'Access denied.' } } | Should -Throw
        $counter.N | Should -Be 1
    }
}

Describe 'Get-SPConfigPath' {
    It 'returns a spconfig.json path under an OpenGateSP folder' {
        $p = Get-SPConfigPath
        $p | Should -Match 'OpenGateSP'
        $p | Should -Match 'spconfig\.json$'
    }
}
