function Get-SPSharingReport {
    <#
    .SYNOPSIS
        Reports external/guest users on a site, and (optionally) sharing links on a
        document library's items.
    .DESCRIPTION
        External users are detected reliably via the site user list (#ext# login marker).
        Sharing-link scanning (-IncludeLinks) is best-effort and slower: it walks a
        library's items and reads their sharing links where the PnP cmdlets are available.
    .PARAMETER SiteUrl
        The site to report on. The function connects to it automatically.
    .PARAMETER IncludeLinks
        Also scan a document library's items for sharing links (slower; best-effort).
    .PARAMETER Library
        Library to scan when -IncludeLinks is used. Default "Documents".
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Get-SPSharingReport -SiteUrl https://contoso.sharepoint.com/sites/Marketing
    .EXAMPLE
        Get-SPSharingReport -SiteUrl https://contoso.sharepoint.com/sites/Marketing -IncludeLinks
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$SiteUrl,

        [switch]$IncludeLinks,

        [string]$Library = 'Documents',

        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    Write-SPLog "Building sharing report for $SiteUrl ..."
    $rows = [System.Collections.Generic.List[object]]::new()

    # 1. External / guest users present in the site
    try {
        $users = Invoke-SPRetry -Operation 'Get-PnPUser' { Get-PnPUser -ErrorAction Stop }
        foreach ($u in $users) {
            if ($u.LoginName -match '#ext#' -or $u.Email -match '#EXT#') {
                $rows.Add([pscustomobject]@{
                    Type = 'External User'; Principal = $u.Title; Login = $u.LoginName
                    Email = $u.Email; Resource = $SiteUrl; Link = $null; LinkScope = $null
                })
            }
        }
    }
    catch { Write-SPLog "Could not read site users: $($_.Exception.Message)" -Level Warn }

    # 2. Sharing links (optional, best-effort)
    if ($IncludeLinks) {
        $haveFileLink   = [bool](Get-Command Get-PnPFileSharingLink   -ErrorAction SilentlyContinue)
        $haveFolderLink = [bool](Get-Command Get-PnPFolderSharingLink -ErrorAction SilentlyContinue)

        if (-not ($haveFileLink -or $haveFolderLink)) {
            Write-SPLog "Sharing-link cmdlets not available in this PnP.PowerShell version; skipping link scan." -Level Warn
        }
        else {
            try {
                $items = Invoke-SPRetry -Operation 'Get-PnPListItem' { Get-PnPListItem -List $Library -PageSize 500 -ErrorAction Stop }
                foreach ($it in $items) {
                    $fileRef = $it.FieldValues.FileRef
                    $fsType  = "$($it.FileSystemObjectType)"
                    try {
                        $links = $null
                        if ($fsType -eq 'File' -and $haveFileLink) {
                            $links = Get-PnPFileSharingLink -Identity $fileRef -ErrorAction Stop
                        }
                        elseif ($fsType -eq 'Folder' -and $haveFolderLink) {
                            $links = Get-PnPFolderSharingLink -Folder $fileRef -ErrorAction Stop
                        }
                        foreach ($l in $links) {
                            $rows.Add([pscustomobject]@{
                                Type = 'Sharing Link'; Principal = $null; Login = $null; Email = $null
                                Resource = $fileRef; Link = $l.Link.WebUrl; LinkScope = "$($l.Link.Scope)"
                            })
                        }
                    }
                    catch { }   # per-item failures are non-fatal in a best-effort scan
                }
            }
            catch { Write-SPLog "Could not scan '$Library' for sharing links: $($_.Exception.Message)" -Level Warn }
        }
    }

    Write-SPLog "Sharing report: $($rows.Count) entries." -Level Success
    $rows | ConvertTo-SPOutput -AsJson:$AsJson
}
