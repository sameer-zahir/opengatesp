#Requires -Version 7.4
# Unit tests for the pure helper functions. These dot-source the Private helpers
# directly so they run without PnP.PowerShell or a live tenant (CI-friendly).

# Exception fakes with the HTTP-status shapes Get-SPHttpStatusCode understands.
class SPFakeHttpException : System.Exception {
    [int]$HttpResponseCode
    SPFakeHttpException([string]$m, [int]$code) : base($m) { $this.HttpResponseCode = $code }
}

BeforeAll {
    $priv = Join-Path $PSScriptRoot '..\module\OpenGateSP\Private'
    . (Join-Path $priv 'Write-SPLog.ps1')
    . (Join-Path $priv 'ConvertTo-SPOutput.ps1')
    . (Join-Path $priv 'Get-SPHttpStatusCode.ps1')
    . (Join-Path $priv 'Get-SPRetryDelay.ps1')
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
    It 'retries on a 429 status code even when the message has no throttle keywords (localized)' {
        $counter = [pscustomobject]@{ N = 0 }
        $result = Invoke-SPRetry -InitialDelaySeconds 0 -MaxRetries 5 {
            $counter.N++
            if ($counter.N -lt 3) { throw [SPFakeHttpException]::new('Limite de requêtes atteinte.', 429) }
            'ok'
        }
        $result    | Should -Be 'ok'
        $counter.N | Should -Be 3
    }
    It 'does not retry when the status code is non-transient, even if the message mentions throttling' {
        $counter = [pscustomobject]@{ N = 0 }
        {
            Invoke-SPRetry -InitialDelaySeconds 0 {
                $counter.N++
                throw [SPFakeHttpException]::new('Request was throttled by policy.', 403)
            }
        } | Should -Throw
        $counter.N | Should -Be 1
    }
}

Describe 'Get-SPHttpStatusCode' {
    It 'reads HttpResponseCode off the exception' {
        Get-SPHttpStatusCode -Exception ([pscustomobject]@{ HttpResponseCode = 429 }) | Should -Be 429
    }
    It 'reads a StatusCode enum (HttpRequestException style)' {
        Get-SPHttpStatusCode -Exception ([pscustomobject]@{ StatusCode = [System.Net.HttpStatusCode]::ServiceUnavailable }) | Should -Be 503
    }
    It 'reads Response.StatusCode (WebException style)' {
        $ex = [pscustomobject]@{ Response = [pscustomobject]@{ StatusCode = 429 } }
        Get-SPHttpStatusCode -Exception $ex | Should -Be 429
    }
    It 'walks the InnerException chain' {
        $ex = [pscustomobject]@{ InnerException = [pscustomobject]@{ HttpResponseCode = 503 } }
        Get-SPHttpStatusCode -Exception $ex | Should -Be 503
    }
    It 'returns null when no HTTP status is present' {
        Get-SPHttpStatusCode -Exception ([System.Exception]::new('plain')) | Should -BeNullOrEmpty
    }
    It 'ignores non-HTTP numeric properties out of range' {
        Get-SPHttpStatusCode -Exception ([pscustomobject]@{ StatusCode = 7 }) | Should -BeNullOrEmpty
    }
}

Describe 'Get-SPRetryDelay' {
    It 'honours a Retry-After header from a WebHeaderCollection-style indexer' {
        $ex = [pscustomobject]@{ Response = [pscustomobject]@{ Headers = @{ 'Retry-After' = '17' } } }
        Get-SPRetryDelay -Exception $ex -Attempt 1 -InitialDelaySeconds 2 | Should -Be 17
    }
    It 'honours a typed RetryAfter.Delta (HttpResponseHeaders style)' {
        $headers = [pscustomobject]@{ RetryAfter = [pscustomobject]@{ Delta = [timespan]::FromSeconds(42) } }
        $ex = [pscustomobject]@{ Response = [pscustomobject]@{ Headers = $headers } }
        Get-SPRetryDelay -Exception $ex | Should -Be 42
    }
    It 'caps the server value at MaxDelaySeconds' {
        $ex = [pscustomobject]@{ Response = [pscustomobject]@{ Headers = @{ 'Retry-After' = '600' } } }
        Get-SPRetryDelay -Exception $ex -MaxDelaySeconds 60 | Should -Be 60
    }
    It 'falls back to exponential back-off without a header' {
        Get-SPRetryDelay -Exception ([System.Exception]::new('x')) -Attempt 3 -InitialDelaySeconds 2 | Should -Be 8
    }
    It 'caps exponential back-off at MaxDelaySeconds' {
        Get-SPRetryDelay -Exception ([System.Exception]::new('x')) -Attempt 10 -InitialDelaySeconds 2 -MaxDelaySeconds 60 | Should -Be 60
    }
}

Describe 'Get-SPConfigPath' {
    It 'returns a spconfig.json path under an OpenGateSP folder' {
        $p = Get-SPConfigPath
        $p | Should -Match 'OpenGateSP'
        $p | Should -Match 'spconfig\.json$'
    }
}
