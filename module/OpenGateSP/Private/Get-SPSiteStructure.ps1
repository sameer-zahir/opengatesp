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
        [string]$OutPath,
        [string[]]$Lists
    )

    if (-not $Connection) { throw 'A source connection is required.' }

    if (-not $OutPath) {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) 'OpenGateSP'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $OutPath = Join-Path $dir ('structure-{0}.pnp' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }

    # Whole-site extraction by default; scope to named lists/libraries when -Lists is given
    # (granular Copy-SPList path) — that limits the template to just those list schemas.
    $tplParams = @{ Out = $OutPath; Connection = $Connection; Force = $true; ErrorAction = 'Stop' }
    if ($Lists) {
        $tplParams.Handlers        = 'Lists'
        $tplParams.ListsToExtract  = $Lists
    }
    else {
        $tplParams.PersistBrandingFiles = $true
    }

    Invoke-SPRetry -Operation 'extract site template' {
        Get-PnPSiteTemplate @tplParams
    } | Out-Null

    [pscustomobject]@{ Path = $OutPath }
}
