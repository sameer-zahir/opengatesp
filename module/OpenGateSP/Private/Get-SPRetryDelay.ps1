function Get-SPRetryDelay {
    <#
    .SYNOPSIS
        Pick the wait (in seconds) before a retry: the server's Retry-After header when the
        response carries one, exponential back-off otherwise. Pure — no I/O.
    .DESCRIPTION
        SharePoint Online's 429/503 responses include a Retry-After header stating exactly how
        long to back off; ignoring it prolongs throttling for the whole tenant. This walks the
        exception chain for a response header (WebHeaderCollection indexer or
        HttpResponseHeaders.RetryAfter.Delta) and falls back to InitialDelaySeconds * 2^(n-1),
        capped at MaxDelaySeconds either way.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [object]$Exception,
        [int]$Attempt = 1,
        [int]$InitialDelaySeconds = 2,
        [int]$MaxDelaySeconds = 60
    )

    $retryAfter = $null
    $ex = $Exception
    while ($ex -and $null -eq $retryAfter) {
        $respProp = $ex.PSObject.Properties['Response']
        $resp = if ($respProp) { $respProp.Value } else { $null }
        if ($resp) {
            $headersProp = $resp.PSObject.Properties['Headers']
            $headers = if ($headersProp) { $headersProp.Value } else { $null }
            if ($headers) {
                # HttpResponseHeaders (HttpClient): typed RetryAfter with a Delta TimeSpan.
                $raProp = $headers.PSObject.Properties['RetryAfter']
                if ($raProp -and $raProp.Value) {
                    $deltaProp = $raProp.Value.PSObject.Properties['Delta']
                    if ($deltaProp -and $null -ne $deltaProp.Value) {
                        $retryAfter = [int][Math]::Ceiling($deltaProp.Value.TotalSeconds)
                    }
                }
                # WebHeaderCollection (WebException): string indexer.
                if ($null -eq $retryAfter) {
                    try {
                        $raw = $headers['Retry-After']
                        $parsed = 0
                        if ($raw -and [int]::TryParse("$raw", [ref]$parsed)) { $retryAfter = $parsed }
                    }
                    catch { <# header collection without a string indexer — ignore #> }
                }
            }
        }
        $ex = $ex.InnerException
    }

    if ($null -ne $retryAfter -and $retryAfter -gt 0) {
        return [int][Math]::Min($MaxDelaySeconds, $retryAfter)
    }
    [int][Math]::Min($MaxDelaySeconds, $InitialDelaySeconds * [Math]::Pow(2, $Attempt - 1))
}
