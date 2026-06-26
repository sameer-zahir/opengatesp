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
        [int] number of versions uploaded (historical + current).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]$SourceConnection,
        [Parameter(Mandatory)]$DestinationConnection,
        [Parameter(Mandatory)][string]$SourceFileUrl,
        [Parameter(Mandatory)][string]$DestFolderUrl,
        [Parameter(Mandatory)][string]$FileName
    )

    if (-not $PSCmdlet.ShouldProcess("$DestFolderUrl/$FileName", 'Copy file with version history')) { return 0 }

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) 'OpenGateSP-ver'
    if (-not (Test-Path -LiteralPath $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }

    $versions = @(Get-PnPFileVersion -Url $SourceFileUrl -Connection $SourceConnection -ErrorAction SilentlyContinue |
            Sort-Object -Property @{ Expression = { [int]$_.ID } })

    $uploaded = 0
    foreach ($v in $versions) {
        $tmpName = "v$($v.ID)-$FileName"
        $local = Join-Path $tmpDir $tmpName
        try {
            $verUrl = '/' + "$($v.Url)".TrimStart('/')
            Get-PnPFile -Url $verUrl -Path $tmpDir -Filename $tmpName -AsFile -Force -Connection $SourceConnection -ErrorAction Stop | Out-Null
            Add-PnPFile -Path $local -Folder $DestFolderUrl -NewFileName $FileName -Connection $DestinationConnection -ErrorAction Stop | Out-Null
            $uploaded++
        }
        catch { Write-SPLog "Version $($v.ID) of $FileName not copied: $($_.Exception.Message)" -Level Warn }
        finally { if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue } }
    }

    # Current version last, so the destination's latest version is the source's current content.
    $curName = "cur-$FileName"
    $curLocal = Join-Path $tmpDir $curName
    try {
        Get-PnPFile -Url $SourceFileUrl -Path $tmpDir -Filename $curName -AsFile -Force -Connection $SourceConnection -ErrorAction Stop | Out-Null
        Add-PnPFile -Path $curLocal -Folder $DestFolderUrl -NewFileName $FileName -Connection $DestinationConnection -ErrorAction Stop | Out-Null
        $uploaded++
    }
    catch { Write-SPLog "Current version of $FileName not copied: $($_.Exception.Message)" -Level Warn }
    finally { if (Test-Path -LiteralPath $curLocal) { Remove-Item -LiteralPath $curLocal -Force -ErrorAction SilentlyContinue } }

    $uploaded
}
