function Start-SPFileMigration {
    <#
    .SYNOPSIS
        Migrate a local file share / folder into a SharePoint Online document library,
        preserving folder structure (and optionally timestamps).
    .DESCRIPTION
        Walks $Source recursively and uploads each file into $Library under $TargetFolder,
        recreating the folder tree. Existing files are skipped unless -Overwrite. Throttling
        is handled with back-off, and the whole run is logged to a file.

        SAFETY: run with -WhatIf first to preview. A real run asks for one confirmation
        before writing (suppress with -Force).
    .PARAMETER Source
        Local folder to migrate (e.g. C:\Shares\Marketing or a UNC path).
    .PARAMETER SiteUrl
        Target site. The function connects to it automatically.
    .PARAMETER Library
        Target document library display name. Default "Documents".
    .PARAMETER TargetFolder
        Optional sub-folder within the library to migrate into.
    .PARAMETER PreserveTimestamps
        Set the SharePoint Created/Modified fields from the local file's timestamps.
    .PARAMETER Overwrite
        Re-upload files that already exist (default: skip existing, so re-runs resume).
    .PARAMETER ExcludeExtension
        File extensions to skip. Default .tmp, .lnk, .ds_store.
    .PARAMETER Force
        Skip the one-time "are you sure" confirmation on a real run.
    .PARAMETER LogPath
        Where to write the run log. Default ./logs/migration-<timestamp>.log.
    .PARAMETER AsJson
        Emit the per-file result as a JSON array instead of objects.
    .EXAMPLE
        Start-SPFileMigration -Source C:\Shares\Marketing -SiteUrl https://contoso.sharepoint.com/sites/Mktg -WhatIf
    .EXAMPLE
        Start-SPFileMigration -Source C:\Shares\Marketing -SiteUrl https://contoso.sharepoint.com/sites/Mktg -PreserveTimestamps
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$SiteUrl,
        [string]$Library = 'Documents',
        [string]$TargetFolder = '',
        [switch]$PreserveTimestamps,
        [switch]$Overwrite,
        [string[]]$ExcludeExtension = @('.tmp', '.lnk', '.ds_store'),
        [switch]$Force,
        [string]$LogPath,
        [switch]$AsJson
    )

    if (-not (Test-Path -LiteralPath $Source)) { throw "Source not found: $Source" }
    $sourceItem = Get-Item -LiteralPath $Source
    if (-not $sourceItem.PSIsContainer) { throw "Source must be a folder: $Source" }

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null

    # Per-run log file
    if (-not $LogPath) {
        $logDir = Join-Path (Get-Location) 'logs'
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $LogPath = Join-Path $logDir ("migration-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    $script:OpenGateSPLogPath = $LogPath

    # Resolve the library's site-relative path ("Documents" display name -> "Shared Documents")
    try {
        $list = Get-PnPList -Identity $Library -ErrorAction Stop
        if (-not $list) { throw "Library '$Library' not found." }
        $rootFolder   = Get-PnPProperty -ClientObject $list -Property RootFolder
        $web          = Get-PnPWeb -ErrorAction Stop
        $libServerRel = $rootFolder.ServerRelativeUrl
        $webServerRel = $web.ServerRelativeUrl.TrimEnd('/')
        $libSiteRel   = $libServerRel.Substring($webServerRel.Length).TrimStart('/')
    }
    catch { throw "Could not resolve library '$Library' on ${SiteUrl}: $($_.Exception.Message)" }

    $files = @(Get-ChildItem -LiteralPath $Source -Recurse -File)
    Write-SPLog "Migration: '$Source' -> $SiteUrl / $libSiteRel/$TargetFolder  ($($files.Count) files; WhatIf=$($WhatIfPreference))"

    # One-time confirmation on a real run
    if (-not $WhatIfPreference -and -not $Force) {
        if (-not $PSCmdlet.ShouldContinue("Upload $($files.Count) file(s) to $SiteUrl ($libSiteRel/$TargetFolder)? This writes to SharePoint.", 'Confirm migration')) {
            Write-SPLog 'Migration cancelled by user.' -Level Warn
            $script:OpenGateSPLogPath = $null
            return
        }
    }

    $stats   = [ordered]@{ Total = $files.Count; Uploaded = 0; Skipped = 0; Failed = 0; WouldUpload = 0 }
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($f in $files) {
        $ext = $f.Extension.ToLowerInvariant()
        if ($ExcludeExtension -contains $ext) {
            $stats.Skipped++
            $results.Add([pscustomobject]@{ File = $f.FullName; Status = 'Skipped (excluded)'; Target = $null; Error = $null })
            continue
        }

        # Destination folder (site-relative) mirroring the source tree
        $relDir = ''
        if ($f.DirectoryName.Length -gt $sourceItem.FullName.Length) {
            $relDir = $f.DirectoryName.Substring($sourceItem.FullName.Length).TrimStart('\', '/').Replace('\', '/')
        }
        $destFolderSiteRel = (@($libSiteRel, $TargetFolder, $relDir) | Where-Object { $_ }) -join '/'
        $destFileServerRel = "$webServerRel/$destFolderSiteRel/$($f.Name)"

        if (-not $PSCmdlet.ShouldProcess($destFileServerRel, 'Upload file')) {
            $stats.WouldUpload++
            $results.Add([pscustomobject]@{ File = $f.FullName; Status = 'WouldUpload'; Target = $destFileServerRel; Error = $null })
            continue
        }

        try {
            if (-not $Overwrite) {
                $existing = Get-PnPFile -Url $destFileServerRel -AsListItem -ErrorAction SilentlyContinue
                if ($existing) {
                    $stats.Skipped++
                    $results.Add([pscustomobject]@{ File = $f.FullName; Status = 'Skipped (exists)'; Target = $destFileServerRel; Error = $null })
                    continue
                }
            }

            Invoke-SPRetry -Operation 'Resolve-PnPFolder' { Resolve-PnPFolder -SiteRelativePath $destFolderSiteRel -ErrorAction Stop } | Out-Null

            $addParams = @{ Path = $f.FullName; Folder = $destFolderSiteRel; ErrorAction = 'Stop' }
            if ($PreserveTimestamps) { $addParams['Values'] = @{ Created = $f.CreationTime; Modified = $f.LastWriteTime } }
            Invoke-SPRetry -Operation "upload $($f.Name)" { Add-PnPFile @addParams } | Out-Null

            $stats.Uploaded++
            $results.Add([pscustomobject]@{ File = $f.FullName; Status = 'Uploaded'; Target = $destFileServerRel; Error = $null })
        }
        catch {
            $stats.Failed++
            Write-SPLog "FAILED $($f.FullName): $($_.Exception.Message)" -Level Error
            $results.Add([pscustomobject]@{ File = $f.FullName; Status = 'Failed'; Target = $destFileServerRel; Error = $_.Exception.Message })
        }
    }

    Write-SPLog ("Done. Total {0} | Uploaded {1} | Skipped {2} | Failed {3} | WouldUpload {4} | Log: {5}" -f `
        $stats.Total, $stats.Uploaded, $stats.Skipped, $stats.Failed, $stats.WouldUpload, $LogPath) -Level Success

    $script:OpenGateSPLogPath = $null
    $results | ConvertTo-SPOutput -AsJson:$AsJson
}
