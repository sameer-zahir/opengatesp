function Copy-SPFileVersions {
    <#
    .SYNOPSIS
        Best-effort copy of a single file WITH its version history to a destination folder, by
        uploading each historical version oldest-first and the current version last (so the
        destination's latest matches the source). EXPERIMENTAL.
    .DESCRIPTION
        PnP/CSOM cannot preserve a version's original author or timestamp on upload, and there is
        no bulk "copy with versions" — so this rebuilds the version chain by re-uploading content
        in order. The version COUNT and CONTENT order are preserved; per-version author/date become
        the migration account/time. For exact fidelity use the SharePoint Migration API.

        Degradation is never silent: version enumeration runs inside Invoke-SPRetry (a transient
        429 no longer collapses the file to current-version-only), and any enumeration or
        per-version failure is reported in the returned Status/VersionHistory instead of the row
        claiming full success.
    .PARAMETER SourceConnection
        Connection to the source web (holds the file + its versions).
    .PARAMETER DestinationConnection
        Connection to the destination web (where the file is rebuilt).
    .PARAMETER SourceFileUrl
        Server-relative URL of the source file.
    .PARAMETER DestFolderUrl
        Server-relative URL of the destination folder to upload into.
    .PARAMETER FileName
        Leaf file name.
    .OUTPUTS
        [pscustomobject] @{ FileName; Uploaded; FailedVersions; VersionHistory
        (Full|Partial|CurrentOnly|NotCopied); Status (Success|Warning|Error|Skipped); Detail }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceConnection', Justification = 'Used inside Invoke-SPRetry scriptblocks, which the rule cannot see into.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'DestinationConnection', Justification = 'Used inside Invoke-SPRetry scriptblocks, which the rule cannot see into.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceFileUrl', Justification = 'Used inside Invoke-SPRetry scriptblocks, which the rule cannot see into.')]
    param(
        [Parameter(Mandatory)]$SourceConnection,
        [Parameter(Mandatory)]$DestinationConnection,
        [Parameter(Mandatory)][string]$SourceFileUrl,
        [Parameter(Mandatory)][string]$DestFolderUrl,
        [Parameter(Mandatory)][string]$FileName
    )

    $newResult = {
        param($Uploaded, $FailedVersions, $VersionHistory, $Status, $Detail)
        [pscustomobject]@{
            FileName       = $FileName
            Uploaded       = $Uploaded
            FailedVersions = $FailedVersions
            VersionHistory = $VersionHistory
            Status         = $Status
            Detail         = $Detail
        }
    }

    if (-not $PSCmdlet.ShouldProcess("$DestFolderUrl/$FileName", 'Copy file with version history')) {
        return & $newResult 0 0 'NotCopied' 'Skipped' 'Dry run'
    }

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) 'OpenGateSP-ver'
    if (-not (Test-Path -LiteralPath $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }

    # Enumerate versions with retry; if it still fails, say so instead of quietly copying
    # only the current version.
    $historyError = $null
    $versions = @()
    try {
        $versions = @(Invoke-SPRetry -Operation "list versions of $FileName" {
                Get-PnPFileVersion -Url $SourceFileUrl -Connection $SourceConnection -ErrorAction Stop
            } | Sort-Object -Property @{ Expression = { [int]$_.ID } })
    }
    catch {
        $historyError = $_.Exception.Message
        Write-SPLog "Version history of $FileName could not be enumerated (copying current version only): $historyError" -Level Warn
    }

    $uploaded = 0
    $failedVersions = 0
    foreach ($v in $versions) {
        $tmpName = "v$($v.ID)-$FileName"
        $local = Join-Path $tmpDir $tmpName
        try {
            $verUrl = '/' + "$($v.Url)".TrimStart('/')
            Invoke-SPRetry -Operation "download version $($v.ID) of $FileName" {
                Get-PnPFile -Url $verUrl -Path $tmpDir -Filename $tmpName -AsFile -Force -Connection $SourceConnection -ErrorAction Stop
            } | Out-Null
            Invoke-SPRetry -Operation "upload version $($v.ID) of $FileName" {
                Add-PnPFile -Path $local -Folder $DestFolderUrl -NewFileName $FileName -Connection $DestinationConnection -ErrorAction Stop
            } | Out-Null
            $uploaded++
        }
        catch {
            $failedVersions++
            Write-SPLog "Version $($v.ID) of $FileName not copied: $($_.Exception.Message)" -Level Warn
        }
        finally { if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue } }
    }

    # Current version last, so the destination's latest version is the source's current content.
    $curName = "cur-$FileName"
    $curLocal = Join-Path $tmpDir $curName
    $currentError = $null
    try {
        Invoke-SPRetry -Operation "download current $FileName" {
            Get-PnPFile -Url $SourceFileUrl -Path $tmpDir -Filename $curName -AsFile -Force -Connection $SourceConnection -ErrorAction Stop
        } | Out-Null
        Invoke-SPRetry -Operation "upload current $FileName" {
            Add-PnPFile -Path $curLocal -Folder $DestFolderUrl -NewFileName $FileName -Connection $DestinationConnection -ErrorAction Stop
        } | Out-Null
        $uploaded++
    }
    catch {
        $currentError = $_.Exception.Message
        Write-SPLog "Current version of $FileName not copied: $currentError" -Level Error
    }
    finally { if (Test-Path -LiteralPath $curLocal) { Remove-Item -LiteralPath $curLocal -Force -ErrorAction SilentlyContinue } }

    if ($currentError) {
        return & $newResult $uploaded $failedVersions 'NotCopied' 'Error' "Current version failed: $currentError"
    }
    if ($historyError) {
        return & $newResult $uploaded $failedVersions 'CurrentOnly' 'Warning' "Current version only (history enumeration failed: $historyError)"
    }
    if ($failedVersions -gt 0) {
        return & $newResult $uploaded $failedVersions 'Partial' 'Warning' "$uploaded version(s) copied, $failedVersions failed"
    }
    & $newResult $uploaded 0 'Full' 'Success' "$uploaded version(s) copied"
}
