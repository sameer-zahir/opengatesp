#Requires -Version 7.4
# On-device encryption for the user's AI API key. Uses Windows DPAPI (CurrentUser scope) via the
# built-in SecureString cmdlets, so the key is never written to disk in plaintext and can only be
# decrypted by the same Windows user on the same machine. Stored in %APPDATA%\OpenGateSP\aiconfig.json.

function Protect-SPSecret {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Encrypting the user-provided API key with DPAPI for on-device storage; never persisted in plaintext.')]
    [CmdletBinding()]
    param([string]$Plain)
    if ([string]::IsNullOrEmpty($Plain)) { return '' }
    $ss = ConvertTo-SecureString -String $Plain -AsPlainText -Force
    ConvertFrom-SecureString -SecureString $ss   # DPAPI CurrentUser; returns a portable encrypted string
}

function Unprotect-SPSecret {
    [CmdletBinding()]
    param([string]$Protected)
    if ([string]::IsNullOrEmpty($Protected)) { return '' }
    try {
        $ss = ConvertTo-SecureString -String $Protected   # decrypts (DPAPI CurrentUser)
        [System.Net.NetworkCredential]::new('', $ss).Password
    }
    catch { '' }
}

# Load / save the AI config (provider, model, endpoint, encrypted key) in %APPDATA%\OpenGateSP.
function Get-SPAiConfigPath { Join-Path $env:APPDATA 'OpenGateSP\aiconfig.json' }

function Get-SPAiConfig {
    $path = Get-SPAiConfigPath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { $null }
}

function Save-SPAiConfig {
    param([string]$Provider, [string]$Model, [string]$Endpoint, [string]$ApiKey, [bool]$AllowWrites)
    $dir = Split-Path (Get-SPAiConfigPath) -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    @{
        Provider    = $Provider
        Model       = $Model
        Endpoint    = $Endpoint
        KeyEnc      = (Protect-SPSecret $ApiKey)
        AllowWrites = [bool]$AllowWrites
    } | ConvertTo-Json | Set-Content -LiteralPath (Get-SPAiConfigPath) -Encoding utf8
}
