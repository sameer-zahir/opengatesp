function Invoke-SPRetry {
    <#
    .SYNOPSIS
        Runs a script block with retry on SharePoint Online throttling (HTTP 429) and
        transient 503/504 errors. Real tenants WILL throttle bulk operations, so all
        looped read/write calls should go through this.
    .DESCRIPTION
        Transient errors are detected by HTTP status code first (Get-SPHttpStatusCode — immune
        to localized exception messages) with the message regex as a fallback. The wait honours
        the server's Retry-After header when present (Get-SPRetryDelay), falling back to
        exponential back-off.

        Only wrap operations that are safe to repeat (reads, and uploads that overwrite the
        same target). Do NOT wrap batch submits — a retried Invoke-PnPBatch re-executes
        requests that already committed, duplicating writes.
    .EXAMPLE
        Invoke-SPRetry -Operation 'upload' { Add-PnPFile -Path $f -Folder $dst }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$ScriptBlock,

        [int]$MaxRetries = 5,

        [int]$InitialDelaySeconds = 2,

        [string]$Operation = 'operation'
    )

    $attempt = 0
    while ($true) {
        try {
            return & $ScriptBlock
        }
        catch {
            $attempt++
            $code = Get-SPHttpStatusCode -Exception $_.Exception
            $isTransient = if ($null -ne $code) {
                $code -in 429, 503, 504
            }
            else {
                $_.Exception.Message -match '(?i)429|throttl|too many requests|503|service unavailable|temporarily'
            }

            if (-not $isTransient -or $attempt -ge $MaxRetries) { throw }

            $delay = Get-SPRetryDelay -Exception $_.Exception -Attempt $attempt -InitialDelaySeconds $InitialDelaySeconds
            Write-SPLog "Throttled during $Operation (attempt $attempt/$MaxRetries). Waiting ${delay}s..." -Level Warn
            Start-Sleep -Seconds $delay
        }
    }
}
