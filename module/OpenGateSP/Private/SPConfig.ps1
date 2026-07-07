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

# Persist a whole config object (schema v2 aware) — the single writer for the file.
function Save-SPConfigObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )
    $path = Get-SPConfigPath
    $Config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
    Write-SPLog "Saved connection config to $path" -Level Debug
    $path
}

function Set-SPConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings
    )
    $current = Get-SPConfig

    $merged = @{}
    foreach ($p in $current.PSObject.Properties) { $merged[$p.Name] = $p.Value }
    foreach ($k in $Settings.Keys) {
        if ($null -ne $Settings[$k] -and "$($Settings[$k])" -ne '') { $merged[$k] = $Settings[$k] }
    }

    # Write-through to schema v2: the flat keys stay the active environment's projection
    # (see SPEnvironments.ps1), so a legacy-style flat save must also land in
    # Environments[ActiveEnvironment] or the two views would drift apart.
    $obj = ConvertTo-SPEnvironmentsConfig -Config ([pscustomobject]$merged)
    if ("$($obj.ActiveEnvironment)") {
        $conn = @{}
        foreach ($k in (Get-SPConnectionKey)) {
            if ($merged.ContainsKey($k)) { $conn[$k] = $merged[$k] }
        }
        if ($conn.Count) {
            $obj = Set-SPEnvironmentInConfig -Config $obj -Name $obj.ActiveEnvironment -Settings $conn
        }
    }
    Save-SPConfigObject -Config $obj
}
