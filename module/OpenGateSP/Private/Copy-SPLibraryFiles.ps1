function Copy-SPLibraryFiles {
    <#
    .SYNOPSIS
        Copy all files and folders of a document library from a source site to the
        same-named library on a destination site in the SAME tenant, then restore
        Created/Modified/Author metadata.
    .NOTES
        Validated against a live tenant. Same-tenant only (Copy-PnPFolder does not work
        cross-tenant — that's the Phase 3 download/upload path). Version history is not
        preserved (latest version only).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$SourceConnection,
        [Parameter(Mandatory)][string]$ListTitle,
        [Parameter(Mandatory)][string]$SourceWebUrl,
        [Parameter(Mandatory)][string]$DestinationWebUrl,
        [switch]$Overwrite
    )

    # Resolve the library's server-relative folder on the source, then map the web path to the destination.
    $srcList = Get-PnPList -Identity $ListTitle -Connection $SourceConnection -ErrorAction Stop
    $srcRoot = Get-PnPProperty -ClientObject $srcList -Property RootFolder -Connection $SourceConnection
    $srcServerRel = $srcRoot.ServerRelativeUrl

    $srcWebPath = ([uri]$SourceWebUrl).AbsolutePath.TrimEnd('/')
    $dstWebPath = ([uri]$DestinationWebUrl).AbsolutePath.TrimEnd('/')
    $dstServerRel = $dstWebPath + $srcServerRel.Substring($srcWebPath.Length)
    $forceCopy = [bool]$Overwrite

    if ($PSCmdlet.ShouldProcess($dstServerRel, "Copy files of '$ListTitle'")) {
        Invoke-SPRetry -Operation "copy files $ListTitle" {
            Copy-PnPFolder -SourceUrl $srcServerRel -TargetUrl $dstServerRel -Connection $SourceConnection -Force:$forceCopy -ErrorAction Stop
        } | Out-Null
        Invoke-SPRetry -Operation "restore metadata $ListTitle" {
            Copy-PnPFileMetadata -SourceUrl $srcServerRel -TargetUrl $dstServerRel -Recursive -Connection $SourceConnection -ErrorAction SilentlyContinue
        } | Out-Null
    }
}
