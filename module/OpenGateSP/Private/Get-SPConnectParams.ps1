function Get-SPConnectParams {
    <#
    .SYNOPSIS
        Builds Connect-PnPOnline parameters for a target URL from saved config, honouring the
        saved auth mode (Delegated or AppOnly). Lets any caller (re)connect to a site without
        re-specifying how to authenticate.
    .NOTES
        For app-only with a .pfx, the certificate password is read at runtime from
        $env:OPENGATESP_CERT_PASSWORD and is never persisted.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Certificate password is supplied at runtime via env var for headless auth; never persisted.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    $cfg = Get-SPConfig
    if (-not $cfg.ClientId) {
        throw "No saved ClientId. Run 'Connect-SPTool ... -SaveConfig' once."
    }

    $p = @{ Url = $Url; ClientId = $cfg.ClientId }
    if ($cfg.Tenant) { $p['Tenant'] = $cfg.Tenant }

    if ($cfg.AuthMode -eq 'AppOnly') {
        if ($cfg.Thumbprint) {
            $p['Thumbprint'] = $cfg.Thumbprint
        }
        elseif ($cfg.CertificatePath) {
            $p['CertificatePath'] = $cfg.CertificatePath
            if ($env:OPENGATESP_CERT_PASSWORD) {
                $p['CertificatePassword'] = ConvertTo-SecureString $env:OPENGATESP_CERT_PASSWORD -AsPlainText -Force
            }
        }
        else {
            throw "App-only config is missing a Thumbprint or CertificatePath. Re-run Connect-SPTool with -Thumbprint or -CertificatePath plus -SaveConfig."
        }
    }
    else {
        $p['Interactive'] = $true
    }

    return $p
}
