function Get-SPHttpStatusCode {
    <#
    .SYNOPSIS
        Extract the HTTP status code from an exception chain, if one is present. Pure — no I/O.
    .DESCRIPTION
        Throttle detection must not depend on the (localized) exception message, so this walks
        the InnerException chain looking for a numeric HTTP status: PnP/Graph exceptions expose
        HttpResponseCode, HttpRequestException exposes StatusCode, and WebException carries it
        on Response.StatusCode. Returns $null when no HTTP status can be found.
    #>
    [CmdletBinding()]
    [OutputType([Nullable[int]])]
    param([object]$Exception)

    $ex = $Exception
    while ($ex) {
        foreach ($name in 'HttpResponseCode', 'StatusCode') {
            $prop = $ex.PSObject.Properties[$name]
            if ($prop -and $null -ne $prop.Value) {
                try {
                    $code = [int]$prop.Value
                    if ($code -ge 100 -and $code -le 599) { return $code }
                }
                catch { <# not numeric (e.g. an unrelated enum) — keep looking #> }
            }
        }
        # WebException and friends: the code lives on the attached response.
        $respProp = $ex.PSObject.Properties['Response']
        if ($respProp -and $respProp.Value) {
            $scProp = $respProp.Value.PSObject.Properties['StatusCode']
            if ($scProp -and $null -ne $scProp.Value) {
                try {
                    $code = [int]$scProp.Value
                    if ($code -ge 100 -and $code -le 599) { return $code }
                }
                catch { <# ignore #> }
            }
        }
        $ex = $ex.InnerException
    }
    $null
}
