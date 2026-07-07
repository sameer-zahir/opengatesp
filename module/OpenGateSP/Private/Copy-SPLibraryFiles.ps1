function Copy-SPLibraryFiles {
    <#
    .SYNOPSIS
        Copy all files and folders of a document library from a source site to the
        same-named library on a destination site in the SAME tenant, then restore
        Created/Modified/Author metadata. Returns @{ Status; Detail } for the caller's
        report row.
    .NOTES
        Validated against a live tenant. Same-tenant only (Copy-PnPFolder does not work
        cross-tenant — that's the Phase 3 download/upload path).

        Default: latest version only (Copy-PnPFolder). With -IncludeVersions and a
        -DestinationConnection, it instead rebuilds each file with its version history via
        Copy-SPFileVersions (EXPERIMENTAL, best-effort — per-version author/date are not
        preserved; see docs/07).

        With -Since, only files modified at/after the (UTC) watermark are copied — per-file
        via Copy-PnPFile, since Copy-PnPFolder cannot filter. Metadata restore passes
        -TargetConnection so cross-site-collection targets resolve against the DESTINATION
        context (without it the restore silently no-ops), and a metadata failure downgrades
        the outcome to Warning instead of disappearing.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$SourceConnection,
        [Parameter(Mandatory)][string]$ListTitle,
        [Parameter(Mandatory)][string]$SourceWebUrl,
        [Parameter(Mandatory)][string]$DestinationWebUrl,
        [object]$DestinationConnection,
        [Nullable[datetime]]$Since,
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

    # Enumerates the library's files (with Modified, for -Since filtering) — shared by the
    # version-preserving and incremental paths.
    $getFiles = {
        $rows = @(Invoke-SPRetry -Operation "list files $ListTitle" {
                Get-PnPListItem -List $ListTitle -PageSize 500 -Fields 'FileRef', 'FileLeafRef', 'Modified' -Connection $SourceConnection -ErrorAction Stop
            } | Where-Object { "$($_.FileSystemObjectType)" -eq 'File' })
        if ($Since) {
            $shaped = $rows | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Modified = $_['Modified']; Raw = $_ } }
            $rows = @(Select-SPChangedItems -SourceItem $shaped -Since $Since | ForEach-Object { $_.Raw })
        }
        $rows
    }

    # Restores Created/Modified/Author on the copied target. -TargetConnection is what makes the
    # target resolve against the destination context when the copy crosses site collections.
    $restoreMetadata = {
        param([string]$FromUrl, [string]$ToUrl, [switch]$Recursive)
        $metaParams = @{
            SourceUrl   = $FromUrl
            TargetUrl   = $ToUrl
            Connection  = $SourceConnection
            ErrorAction = 'Stop'
        }
        if ($Recursive) { $metaParams['Recursive'] = $true }
        if ($DestinationConnection) { $metaParams['TargetConnection'] = $DestinationConnection }
        Invoke-SPRetry -Operation "restore metadata $ToUrl" { Copy-PnPFileMetadata @metaParams } | Out-Null
    }

    # Opt-in version-preserving path: rebuild each file's history (best-effort). Leaves the default
    # Copy-PnPFolder path below untouched when -IncludeVersions is not set.
    if ($IncludeVersions -and $DestinationConnection) {
        $files = @(& $getFiles)
        if (-not $files.Count) {
            return [pscustomobject]@{ Status = 'Success'; Detail = $(if ($Since) { 'No files changed since watermark' } else { 'No files to copy' }) }
        }
        if (-not $PSCmdlet.ShouldProcess($dstServerRel, "Copy $($files.Count) file(s) of '$ListTitle' with version history")) {
            return [pscustomobject]@{ Status = 'Skipped'; Detail = 'Dry run' }
        }
        $degraded = 0
        foreach ($f in $files) {
            $srcRef = "$($f.FieldValues.FileRef)"
            $leaf = "$($f.FieldValues.FileLeafRef)"
            $destFileUrl = Resolve-SPCrossTenantUrl -SourceServerRelativeUrl $srcRef -SourceWebServerRelativeUrl $srcWebPath -DestinationWebServerRelativeUrl $dstWebPath
            $destFolder = $destFileUrl.Substring(0, [Math]::Max(0, $destFileUrl.Length - $leaf.Length)).TrimEnd('/')
            $verResult = Copy-SPFileVersions -SourceConnection $SourceConnection -DestinationConnection $DestinationConnection -SourceFileUrl $srcRef -DestFolderUrl $destFolder -FileName $leaf
            if ($verResult.Status -ne 'Success') { $degraded++ }
        }
        if ($degraded -gt 0) {
            return [pscustomobject]@{ Status = 'Warning'; Detail = "$($files.Count) file(s) copied with version history; $degraded degraded (see log)" }
        }
        return [pscustomobject]@{ Status = 'Success'; Detail = "$($files.Count) file(s) copied with version history" }
    }

    # Incremental path: Copy-PnPFolder can't filter by date, so changed files copy one by one.
    if ($Since) {
        $files = @(& $getFiles)
        if (-not $files.Count) {
            return [pscustomobject]@{ Status = 'Success'; Detail = 'No files changed since watermark' }
        }
        if (-not $PSCmdlet.ShouldProcess($dstServerRel, "Copy $($files.Count) changed file(s) of '$ListTitle'")) {
            return [pscustomobject]@{ Status = 'Skipped'; Detail = 'Dry run' }
        }
        $copied = 0
        $failed = 0
        $firstError = $null
        foreach ($f in $files) {
            $srcRef = "$($f.FieldValues.FileRef)"
            $leaf = "$($f.FieldValues.FileLeafRef)"
            $destFileUrl = Resolve-SPCrossTenantUrl -SourceServerRelativeUrl $srcRef -SourceWebServerRelativeUrl $srcWebPath -DestinationWebServerRelativeUrl $dstWebPath
            $destFolder = $destFileUrl.Substring(0, [Math]::Max(0, $destFileUrl.Length - $leaf.Length)).TrimEnd('/')
            try {
                Invoke-SPRetry -Operation "copy changed file $leaf" {
                    Copy-PnPFile -SourceUrl $srcRef -TargetUrl $destFolder -Force -Connection $SourceConnection -ErrorAction Stop
                } | Out-Null
                try { & $restoreMetadata $srcRef $destFileUrl }
                catch { Write-SPLog "Metadata restore failed for ${leaf}: $($_.Exception.Message)" -Level Warn }
                $copied++
            }
            catch {
                $failed++
                if (-not $firstError) { $firstError = $_.Exception.Message }
                Write-SPLog "FAILED changed file ${leaf}: $($_.Exception.Message)" -Level Error
            }
        }
        if ($failed -gt 0) {
            return [pscustomobject]@{
                Status = $(if ($copied -eq 0) { 'Error' } else { 'Warning' })
                Detail = "$copied changed file(s) copied, $failed failed: $firstError"
            }
        }
        return [pscustomobject]@{ Status = 'Success'; Detail = "$copied changed file(s) copied" }
    }

    if (-not $PSCmdlet.ShouldProcess($dstServerRel, "Copy files of '$ListTitle'")) {
        return [pscustomobject]@{ Status = 'Skipped'; Detail = 'Dry run' }
    }
    Invoke-SPRetry -Operation "copy files $ListTitle" {
        Copy-PnPFolder -SourceUrl $srcServerRel -TargetUrl $dstServerRel -Connection $SourceConnection -Force:$forceCopy -ErrorAction Stop
    } | Out-Null
    try {
        & $restoreMetadata $srcServerRel $dstServerRel -Recursive
        return [pscustomobject]@{ Status = 'Success'; Detail = 'Files copied' }
    }
    catch {
        Write-SPLog "Metadata restore failed for '$ListTitle': $($_.Exception.Message)" -Level Warn
        return [pscustomobject]@{ Status = 'Warning'; Detail = "Files copied; metadata restore failed: $($_.Exception.Message)" }
    }
}
