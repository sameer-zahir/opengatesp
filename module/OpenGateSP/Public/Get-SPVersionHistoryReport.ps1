function Get-SPVersionHistoryReport {
    <#
    .SYNOPSIS
        Report files whose version history is heavy — many versions or a lot of space spent on
        versions — so you can trim before migrating.
    .DESCRIPTION
        Read-only, but potentially SLOW: counting versions is a per-file call, so the scan is
        gated by -MinSizeMB (only files at least this big are inspected) to bound cost on large
        libraries. Returns per-file VersionCount and VersionSizeMB; pair with
        Measure-SPVersionBloat / Clear-SPVersionHistory to act on the worst offenders.
    .PARAMETER SiteUrl
        The site to scan. Connected automatically.
    .PARAMETER Library
        Limit the scan to a single library (display name). Default: all document libraries.
    .PARAMETER MinSizeMB
        Only inspect files at or above this current size, to bound the per-file version calls. Default 25.
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Get-SPVersionHistoryReport -SiteUrl https://contoso.sharepoint.com/sites/Marketing -MinSizeMB 50
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [string]$Library,
        [int]$MinSizeMB = 25,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    Write-SPLog "Scanning $SiteUrl for version-history bloat (files >= $MinSizeMB MB) ..."

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
                if (($bytes / 1MB) -lt $MinSizeMB) { continue }
                $fileRef = "$($it.FieldValues['FileRef'])"
                try {
                    $vers = @(Invoke-SPRetry -Operation "versions $fileRef" { Get-PnPFileVersion -Url $fileRef -ErrorAction Stop })
                    $vSize = (($vers | Measure-Object -Property Size -Sum).Sum) -as [double]
                    $rows.Add([pscustomobject]@{
                        Library       = $lib.Title
                        FileName      = "$($it.FieldValues['FileLeafRef'])"
                        FileRef       = $fileRef
                        CurrentSizeMB = [math]::Round($bytes / 1MB, 1)
                        VersionCount  = $vers.Count
                        VersionSizeMB = [math]::Round(($vSize / 1MB), 1)
                    })
                }
                catch { }   # per-file version read is best-effort
            }
        }
        catch { Write-SPLog "Could not scan '$($lib.Title)': $($_.Exception.Message)" -Level Warn }
    }

    $sorted = $rows | Sort-Object -Property VersionSizeMB -Descending
    Write-SPLog "Inspected version history on $($rows.Count) file(s)." -Level Success
    $sorted | ConvertTo-SPOutput -AsJson:$AsJson
}
