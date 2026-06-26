function Copy-SPLibraryFiles {
    <#
    .SYNOPSIS
        Copy all files and folders of a document library from a source site to the
        same-named library on a destination site in the SAME tenant, then restore
        Created/Modified/Author metadata.
    .NOTES
        Validated against a live tenant. Same-tenant only (Copy-PnPFolder does not work
        cross-tenant — that's the Phase 3 download/upload path).

        Default: latest version only (Copy-PnPFolder). With -IncludeVersions and a
        -DestinationConnection, it instead rebuilds each file with its version history via
        Copy-SPFileVersions (EXPERIMENTAL, best-effort — per-version author/date are not
        preserved; see docs/07).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$SourceConnection,
        [Parameter(Mandatory)][string]$ListTitle,
        [Parameter(Mandatory)][string]$SourceWebUrl,
        [Parameter(Mandatory)][string]$DestinationWebUrl,
        [object]$DestinationConnection,
        [switch]$IncludeVersions,
        [switch]$Overwrite
    )

    # Resolve the library's server-relative folder on the source, then map the web path to the destination.
    $srcList = Get-PnPList -Identity $ListTitle -Connection $SourceConnection -ErrorAction Stop
    $srcRoot = Get-PnPProperty -ClientObject $srcList -Property RootFolder -Connection $SourceConnection
    $srcServerRel = $srcRoot.ServerRelativeUrl

    $srcWebPath = ([uri]$SourceWebUrl).AbsolutePath
    $dstWebPath = ([uri]$DestinationWebUrl).AbsolutePath
    $dstServerRel = Resolve-SPCrossTenantUrl -SourceServerRelativeUrl $srcServerRel -SourceWebServerRelativeUrl $srcWebPath -DestinationWebServerRelativeUrl $dstWebPath
    $forceCopy = [bool]$Overwrite

    # Opt-in version-preserving path: rebuild each file's history (best-effort). Leaves the default
    # Copy-PnPFolder path below untouched when -IncludeVersions is not set.
    if ($IncludeVersions -and $DestinationConnection) {
        $files = @(Invoke-SPRetry -Operation "list files $ListTitle" {
                Get-PnPListItem -List $ListTitle -PageSize 500 -Fields 'FileRef', 'FileLeafRef' -Connection $SourceConnection -ErrorAction Stop
            } | Where-Object { $_.FileSystemObjectType -eq 'File' })
        if ($PSCmdlet.ShouldProcess($dstServerRel, "Copy $($files.Count) file(s) of '$ListTitle' with version history")) {
            foreach ($f in $files) {
                $srcRef = "$($f.FieldValues.FileRef)"
                $leaf = "$($f.FieldValues.FileLeafRef)"
                $destFileUrl = Resolve-SPCrossTenantUrl -SourceServerRelativeUrl $srcRef -SourceWebServerRelativeUrl $srcWebPath -DestinationWebServerRelativeUrl $dstWebPath
                $destFolder = $destFileUrl.Substring(0, [Math]::Max(0, $destFileUrl.Length - $leaf.Length)).TrimEnd('/')
                Copy-SPFileVersions -SourceConnection $SourceConnection -DestinationConnection $DestinationConnection -SourceFileUrl $srcRef -DestFolderUrl $destFolder -FileName $leaf | Out-Null
            }
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($dstServerRel, "Copy files of '$ListTitle'")) {
        Invoke-SPRetry -Operation "copy files $ListTitle" {
            Copy-PnPFolder -SourceUrl $srcServerRel -TargetUrl $dstServerRel -Connection $SourceConnection -Force:$forceCopy -ErrorAction Stop
        } | Out-Null
        Invoke-SPRetry -Operation "restore metadata $ListTitle" {
            Copy-PnPFileMetadata -SourceUrl $srcServerRel -TargetUrl $dstServerRel -Recursive -Connection $SourceConnection -ErrorAction SilentlyContinue
        } | Out-Null
    }
}
