function Get-SPLargeFiles {
    <#
    .SYNOPSIS
        Report the largest files in a site's document libraries — the ones that dominate
        migration time and storage.
    .DESCRIPTION
        Read-only. Scans every (or one named) non-hidden document library and returns files at
        or above -MinSizeMB, largest first. Useful to estimate migration volume and to spot files
        near SharePoint's per-file limit.
    .PARAMETER SiteUrl
        The site to scan. Connected automatically.
    .PARAMETER MinSizeMB
        Report files at or above this size in MB. Default 100.
    .PARAMETER Library
        Limit the scan to a single library (display name). Default: all document libraries.
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Get-SPLargeFiles -SiteUrl https://contoso.sharepoint.com/sites/Marketing -MinSizeMB 250
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [int]$MinSizeMB = 100,
        [string]$Library,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    Write-SPLog "Scanning $SiteUrl for files >= $MinSizeMB MB ..."

    $libs = if ($Library) {
        @(Get-PnPList -Identity $Library -ErrorAction Stop)
    }
    else {
        @(Get-PnPList -ErrorAction Stop | Where-Object { $_.BaseTemplate -eq 101 -and -not $_.Hidden })
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($lib in $libs) {
        try {
            $items = Invoke-SPRetry -Operation "list items $($lib.Title)" {
                Get-PnPListItem -List $lib.Title -PageSize 500 -Fields 'FileLeafRef', 'FileRef', 'File_x0020_Size' -ErrorAction Stop
            }
            foreach ($it in $items) {
                $bytes = [long]($it.FieldValues['File_x0020_Size'])
                if ($bytes -le 0) { continue }
                $mb = [math]::Round($bytes / 1MB, 1)
                if ($mb -ge $MinSizeMB) {
                    $rows.Add([pscustomobject]@{
                        Library  = $lib.Title
                        FileName = "$($it.FieldValues['FileLeafRef'])"
                        FileRef  = "$($it.FieldValues['FileRef'])"
                        SizeMB   = $mb
                    })
                }
            }
        }
        catch { Write-SPLog "Could not scan '$($lib.Title)': $($_.Exception.Message)" -Level Warn }
    }

    $sorted = $rows | Sort-Object -Property SizeMB -Descending
    Write-SPLog "Found $($rows.Count) file(s) >= $MinSizeMB MB." -Level $(if ($rows.Count) { 'Warn' } else { 'Success' })
    $sorted | ConvertTo-SPOutput -AsJson:$AsJson
}
