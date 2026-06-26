function Get-SPContentInsights {
    <#
    .SYNOPSIS
        Summarize a site's document libraries by file type — count and total size per extension —
        to size up a migration and spot unsupported or temp content.
    .DESCRIPTION
        Read-only. Walks every (or one named) non-hidden document library and aggregates files by
        extension, returning count and total MB per type, largest first. A quick "what's in here"
        for planning.
    .PARAMETER SiteUrl
        The site to scan. Connected automatically.
    .PARAMETER Library
        Limit the scan to a single library (display name). Default: all document libraries.
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Get-SPContentInsights -SiteUrl https://contoso.sharepoint.com/sites/Marketing
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [string]$Library,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    Write-SPLog "Summarizing content of $SiteUrl by file type ..."

    $libs = if ($Library) {
        @(Get-PnPList -Identity $Library -ErrorAction Stop)
    }
    else {
        @(Get-PnPList -ErrorAction Stop | Where-Object { $_.BaseTemplate -eq 101 -and -not $_.Hidden })
    }

    $byExt = @{}
    foreach ($lib in $libs) {
        try {
            $items = Invoke-SPRetry -Operation "list items $($lib.Title)" {
                Get-PnPListItem -List $lib.Title -PageSize 500 -Fields 'FileLeafRef', 'File_x0020_Size' -ErrorAction Stop
            }
            foreach ($it in $items) {
                $name = "$($it.FieldValues['FileLeafRef'])"
                if (-not $name) { continue }
                $ext = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
                if (-not $ext) { $ext = '(none)' }
                $bytes = [long]($it.FieldValues['File_x0020_Size'])
                if (-not $byExt.ContainsKey($ext)) { $byExt[$ext] = [pscustomobject]@{ Count = 0; Bytes = [long]0 } }
                $byExt[$ext].Count++
                $byExt[$ext].Bytes += $bytes
            }
        }
        catch { Write-SPLog "Could not scan '$($lib.Title)': $($_.Exception.Message)" -Level Warn }
    }

    $rows = foreach ($k in $byExt.Keys) {
        [pscustomobject]@{
            Extension = $k
            Count     = $byExt[$k].Count
            TotalMB   = [math]::Round($byExt[$k].Bytes / 1MB, 1)
        }
    }
    $sorted = $rows | Sort-Object -Property TotalMB -Descending
    Write-SPLog "Summarized $(@($rows).Count) file type(s)." -Level Success
    $sorted | ConvertTo-SPOutput -AsJson:$AsJson
}
