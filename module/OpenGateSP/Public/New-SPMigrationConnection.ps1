function New-SPMigrationConnection {
    <#
    .SYNOPSIS
        Open a PnP connection to a specific site in a specific tenant and return the connection
        object — so a tenant-to-tenant migration can hold a source and a destination connection
        to two different tenants at the same time.
    .DESCRIPTION
        Same-tenant copies let Copy-SPSite build both connections from your saved config. Going
        cross-tenant, source and destination are different tenants (often different app
        registrations), so you open each explicitly here and pass the two connection objects to
        Copy-SPSite -CrossTenant (or Copy-SPPermissions / Copy-SPTermGroup / the identity
        pipeline).

        With -Environment, the ClientId/Tenant/certificate come from a saved environment
        (see Get-SPEnvironment), so a cross-tenant run reads as one line per side:
        New-SPMigrationConnection -Environment Contoso -Url <site>. Explicit parameters
        override the environment's values. This never changes the ACTIVE environment —
        migration connections are transient by design.
    .PARAMETER Url
        The site URL to connect to.
    .PARAMETER ClientId
        The Entra app (client) id registered in that tenant. Required unless -Environment
        supplies it.
    .PARAMETER Tenant
        The tenant (e.g. contoso.onmicrosoft.com).
    .PARAMETER Environment
        A saved environment name to take ClientId/Tenant/certificate (and delegated flavor)
        from. See docs/03.
    .PARAMETER Thumbprint
        App-only: certificate thumbprint from the local store.
    .PARAMETER CertificatePath
        App-only: path to a .pfx (password read at runtime from OPENGATESP_CERT_PASSWORD).
    .PARAMETER DeviceLogin
        Use device-code sign-in instead of an interactive browser.
    .PARAMETER OSLogin
        Windows-native sign-in via the OS broker (WAM) — no browser. Needs the broker
        redirect URI on the app registration (docs/02). Windows only.
    .EXAMPLE
        $src = New-SPMigrationConnection -Url https://contoso.sharepoint.com/sites/A -ClientId <id> -Tenant contoso.onmicrosoft.com
        $dst = New-SPMigrationConnection -Url https://fabrikam.sharepoint.com/sites/B -ClientId <id> -Tenant fabrikam.onmicrosoft.com
        Copy-SPSite -SourceUrl $src.Url -DestinationUrl $dst.Url -SourceConnection $src -DestinationConnection $dst -CrossTenant -IncludeContent
    .EXAMPLE
        $src = New-SPMigrationConnection -Environment Contoso  -Url https://contoso.sharepoint.com/sites/A
        $dst = New-SPMigrationConnection -Environment Fabrikam -Url https://fabrikam.sharepoint.com/sites/B
        Cross-tenant sides from two saved environments.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Certificate password is supplied at runtime via env var for headless auth; never persisted.')]
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$ClientId,
        [string]$Tenant,
        [string]$Environment,
        [string]$Thumbprint,
        [string]$CertificatePath,
        [switch]$DeviceLogin,
        [switch]$OSLogin
    )

    $cfg = [pscustomobject]@{}
    if ($Environment) {
        $v2 = ConvertTo-SPEnvironmentsConfig -Config (Get-SPConfig)
        $key = Resolve-SPEnvironmentKey $v2.Environments $Environment
        if (-not $key) {
            $known = @($v2.Environments.PSObject.Properties.Name)
            throw "Unknown environment '$Environment'. Known environment(s): $(if ($known) { $known -join ', ' } else { '(none)' })."
        }
        $cfg = $v2.Environments.$key
        if (-not $ClientId)        { $ClientId        = "$($cfg.ClientId)" }
        if (-not $Tenant)          { $Tenant          = "$($cfg.Tenant)" }
        if (-not $Thumbprint)      { $Thumbprint      = "$($cfg.Thumbprint)" }
        if (-not $CertificatePath) { $CertificatePath = "$($cfg.CertificatePath)" }
    }
    if (-not $ClientId) {
        throw 'ClientId is required - pass -ClientId, or -Environment <name> for a saved environment (Get-SPEnvironment lists them).'
    }

    $choice = Resolve-SPAuthChoice -Cfg $cfg -Thumbprint $Thumbprint -CertificatePath $CertificatePath `
        -DeviceLogin:$DeviceLogin -OSLogin:$OSLogin

    $p = @{ Url = $Url; ClientId = $ClientId; ReturnConnection = $true }
    if ($Tenant) { $p['Tenant'] = $Tenant }

    if ($choice.Mode -eq 'AppOnly') {
        if ($Thumbprint) {
            $p['Thumbprint'] = $Thumbprint
        }
        elseif ($CertificatePath) {
            $p['CertificatePath'] = $CertificatePath
            if ($env:OPENGATESP_CERT_PASSWORD) {
                $p['CertificatePassword'] = ConvertTo-SecureString $env:OPENGATESP_CERT_PASSWORD -AsPlainText -Force
            }
        }
        else {
            throw "Environment '$Environment' is app-only but has no Thumbprint or CertificatePath saved. See docs/05-app-only-auth.md."
        }
    }
    else {
        switch ($choice.Flow) {
            'DeviceLogin' { $p['DeviceLogin'] = $true }
            'OSLogin'     { $p['OSLogin'] = $true }
            default       { $p['Interactive'] = $true }
        }
    }

    Write-SPLog "Opening migration connection to $Url$(if ($Environment) { " (environment: $Environment)" })"
    Invoke-SPRetry -Operation "connect $Url" { Connect-PnPOnline @p }
}
