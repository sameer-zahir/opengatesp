function Invoke-SPRetry {
    <#
    .SYNOPSIS
        Runs a script block with exponential back-off retry on SharePoint Online
        throttling (HTTP 429) and transient 503 errors. Real tenants WILL throttle
        bulk operations, so all looped read/write calls should go through this.
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
            $msg = $_.Exception.Message
            $isTransient = $msg -match '(?i)429|throttl|too many requests|503|service unavailable|temporarily'

            if (-not $isTransient -or $attempt -ge $MaxRetries) { throw }

            $delay = [int][Math]::Min(60, $InitialDelaySeconds * [Math]::Pow(2, $attempt - 1))
            Write-SPLog "Throttled during $Operation (attempt $attempt/$MaxRetries). Waiting ${delay}s..." -Level Warn
            Start-Sleep -Seconds $delay
        }
    }
}
