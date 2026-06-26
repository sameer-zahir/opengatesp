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
        Copy-SPSite -CrossTenant (or Copy-SPPermissions / Copy-SPTermGroup).
    .PARAMETER Url
        The site URL to connect to.
    .PARAMETER ClientId
        The Entra app (client) id registered in that tenant.
    .PARAMETER Tenant
        The tenant (e.g. contoso.onmicrosoft.com).
    .PARAMETER Thumbprint
        App-only: certificate thumbprint from the local store.
    .PARAMETER CertificatePath
        App-only: path to a .pfx (password read at runtime from OPENGATESP_CERT_PASSWORD).
    .PARAMETER DeviceLogin
        Use device-code sign-in instead of an interactive browser.
    .EXAMPLE
        $src = New-SPMigrationConnection -Url https://contoso.sharepoint.com/sites/A -ClientId <id> -Tenant contoso.onmicrosoft.com
        $dst = New-SPMigrationConnection -Url https://fabrikam.sharepoint.com/sites/B -ClientId <id> -Tenant fabrikam.onmicrosoft.com
        Copy-SPSite -SourceUrl $src.Url -DestinationUrl $dst.Url -SourceConnection $src -DestinationConnection $dst -CrossTenant -IncludeContent
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Certificate password is supplied at runtime via env var for headless auth; never persisted.')]
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$ClientId,
        [string]$Tenant,
        [string]$Thumbprint,
        [string]$CertificatePath,
        [switch]$DeviceLogin
    )

    $p = @{ Url = $Url; ClientId = $ClientId; ReturnConnection = $true }
    if ($Tenant) { $p['Tenant'] = $Tenant }

    if ($Thumbprint) {
        $p['Thumbprint'] = $Thumbprint
    }
    elseif ($CertificatePath) {
        $p['CertificatePath'] = $CertificatePath
        if ($env:OPENGATESP_CERT_PASSWORD) {
            $p['CertificatePassword'] = ConvertTo-SecureString $env:OPENGATESP_CERT_PASSWORD -AsPlainText -Force
        }
    }
    elseif ($DeviceLogin) {
        $p['DeviceLogin'] = $true
    }
    else {
        $p['Interactive'] = $true
    }

    Write-SPLog "Opening migration connection to $Url"
    Invoke-SPRetry -Operation "connect $Url" { Connect-PnPOnline @p }
}
