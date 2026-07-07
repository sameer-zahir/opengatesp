function Measure-SPBatchOutcome {
    <#
    .SYNOPSIS
        Classify the output of Invoke-PnPBatch -Details into per-request success/failure
        counts, so a partially failed batch is never reported as fully copied. Pure — no I/O.
    .DESCRIPTION
        Invoke-PnPBatch does not throw when individual requests inside the batch fail; the
        per-request outcomes are only visible in its -Details output. This inspects each result
        object defensively (the exact shape varies across PnP.PowerShell versions): a populated
        error-ish property (Error/ErrorMessage/Exception) or an HTTP status >= 400 counts as a
        failure. When no per-request details are available at all (older PnP, or -Details
        unsupported), the outcome is assumed-copied but flagged Confirmed=$false so callers can
        say so instead of overstating certainty.
    .OUTPUTS
        [pscustomobject] @{ Queued; Copied; Failed; Errors (first 5 messages); Confirmed }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [object[]]$BatchOutput,
        [Parameter(Mandatory)][int]$Queued
    )

    $results = @($BatchOutput | Where-Object { $null -ne $_ })
    if (-not $results.Count) {
        return [pscustomobject]@{ Queued = $Queued; Copied = $Queued; Failed = 0; Errors = @(); Confirmed = $false }
    }

    $failed = 0
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $results) {
        $isError = $false
        $detail = $null

        foreach ($name in 'Error', 'ErrorMessage', 'Exception') {
            $prop = $r.PSObject.Properties[$name]
            if ($prop -and $prop.Value) {
                $isError = $true
                $detail = "$($prop.Value)"
                break
            }
        }

        if (-not $isError) {
            foreach ($name in 'ResponseStatusCode', 'StatusCode', 'HttpStatusCode') {
                $prop = $r.PSObject.Properties[$name]
                if ($prop -and $null -ne $prop.Value) {
                    try {
                        $code = [int]$prop.Value
                        if ($code -ge 400) {
                            $isError = $true
                            $detail = "HTTP $code"
                        }
                    }
                    catch { <# not numeric — ignore #> }
                    break
                }
            }
        }

        if ($isError) {
            $failed++
            if ($detail -and $errors.Count -lt 5) { $errors.Add($detail) }
        }
    }

    [pscustomobject]@{
        Queued    = $Queued
        Copied    = [Math]::Max(0, $Queued - $failed)
        Failed    = $failed
        Errors    = @($errors)
        Confirmed = $true
    }
}
