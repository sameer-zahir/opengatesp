function Get-SPSiteStructure {
    <#
    .SYNOPSIS
        Extract a source site's structure (lists, libraries, fields, content types, views,
        navigation, pages) into a PnP provisioning template (.pnp) so it can be re-applied
        to a destination site. Thin wrapper over Get-PnPSiteTemplate.
    .NOTES
        Validated against a live tenant (not runnable headlessly). Managed-metadata field
        values and some web parts are lossy on re-apply — see docs/07.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$Connection,
        [string]$OutPath
    )

    if (-not $Connection) { throw 'A source connection is required.' }

    if (-not $OutPath) {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) 'OpenGateSP'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $OutPath = Join-Path $dir ('structure-{0}.pnp' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }

    Invoke-SPRetry -Operation 'extract site template' {
        Get-PnPSiteTemplate -Out $OutPath -Connection $Connection -Force -PersistBrandingFiles -ErrorAction Stop
    } | Out-Null

    [pscustomobject]@{ Path = $OutPath }
}
