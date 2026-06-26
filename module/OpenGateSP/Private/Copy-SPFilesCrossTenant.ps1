function Copy-SPFilesCrossTenant {
    <#
    .SYNOPSIS
        Copy a document library's files from a source connection to a destination connection in
        a DIFFERENT tenant by downloading each file locally and re-uploading it. Returns the
        number of files copied.
    .DESCRIPTION
        Copy-PnPFile/Copy-PnPFolder only work within one tenant, so cross-tenant copy is a
        download-then-upload. Files are enumerated from the library (server-relative FileRef),
        downloaded to a unique temp folder, and uploaded to the mapped destination folder
        (Add-PnPFile creates the folder path as needed). The temp folder is always cleaned up.
    .NOTES
        Live-tenant I/O. Latest version only. User/lookup/managed-metadata column values are
        not guaranteed to round-trip cross-tenant (principals and terms differ per tenant).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]$SourceConnection,
        [Parameter(Mandatory)]$DestinationConnection,
        [Parameter(Mandatory)][string]$ListTitle,
        [Parameter(Mandatory)][string]$SourceWebUrl,
        [Parameter(Mandatory)][string]$DestinationWebUrl,
        [string]$TempRoot
    )

    if (-not $DestinationConnection) { throw 'A destination connection is required.' }
    $srcWebPath = ([uri]$SourceWebUrl).AbsolutePath
    $dstWebPath = ([uri]$DestinationWebUrl).AbsolutePath

    if (-not $TempRoot) { $TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('OpenGateSP-xt-' + ([guid]::NewGuid().ToString('N'))) }
    if (-not (Test-Path -LiteralPath $TempRoot)) { New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null }

    $items  = @(Get-PnPListItem -List $ListTitle -PageSize 500 -Connection $SourceConnection -ErrorAction Stop)
    $copied = 0
    try {
        foreach ($it in $items) {
            if ("$($it.FileSystemObjectType)" -ne 'File') { continue }   # files only; folders are created on upload
            $fileRef = [string]$it['FileRef']
            if (-not $fileRef) { continue }

            $name = Split-Path $fileRef -Leaf
            if (-not $PSCmdlet.ShouldProcess($fileRef, 'Copy file cross-tenant')) { continue }

            # Download to a unique temp dir (avoids collisions between same-named files in different folders).
            $localDir = Join-Path $TempRoot ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $localDir -Force | Out-Null
            Invoke-SPRetry -Operation "download $name" {
                Get-PnPFile -Url $fileRef -Path $localDir -Filename $name -AsFile -Force -Connection $SourceConnection -ErrorAction Stop
            } | Out-Null

            # Map the file's parent folder across webs and upload.
            $srcParent = (Split-Path $fileRef -Parent) -replace '\\', '/'
            $dstFolder = Resolve-SPCrossTenantUrl -SourceServerRelativeUrl $srcParent -SourceWebServerRelativeUrl $srcWebPath -DestinationWebServerRelativeUrl $dstWebPath
            Invoke-SPRetry -Operation "upload $name" {
                Add-PnPFile -Path (Join-Path $localDir $name) -Folder $dstFolder -Connection $DestinationConnection -ErrorAction Stop
            } | Out-Null
            $copied++
        }
    }
    finally {
        if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $copied
}
