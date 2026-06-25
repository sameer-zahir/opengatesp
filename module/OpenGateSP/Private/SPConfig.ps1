# Local config persistence for OpenGateSP.
# Stores non-secret connection defaults (tenant, client id, default site URL)
# in the user profile (NOT in the repo). Delegated auth means there is no
# client secret to store. The file is git-ignored as a belt-and-braces measure.

function Get-SPConfigPath {
    [CmdletBinding()]
    param()
    $base =
        if ($env:APPDATA)          { $env:APPDATA }           # Windows
        elseif ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } # Linux (XDG)
        else                       { Join-Path $HOME '.config' } # macOS / fallback

    $dir = Join-Path $base 'OpenGateSP'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Join-Path $dir 'spconfig.json'
}

function Get-SPConfig {
    [CmdletBinding()]
    param()
    $path = Get-SPConfigPath
    if (Test-Path -LiteralPath $path) {
        try { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
        catch { [pscustomobject]@{} }
    }
    else {
        [pscustomobject]@{}
    }
}

function Set-SPConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings
    )
    $path    = Get-SPConfigPath
    $current = Get-SPConfig

    $merged = @{}
    foreach ($p in $current.PSObject.Properties) { $merged[$p.Name] = $p.Value }
    foreach ($k in $Settings.Keys) {
        if ($null -ne $Settings[$k] -and "$($Settings[$k])" -ne '') { $merged[$k] = $Settings[$k] }
    }

    $merged | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding utf8
    Write-SPLog "Saved connection defaults to $path" -Level Debug
    $path
}
