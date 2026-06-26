function Get-SPCheckedOutFiles {
    <#
    .SYNOPSIS
        Report files left checked out in a site's document libraries — a classic migration
        blocker (checked-out files copy as their last checked-in version, or not at all).
    .DESCRIPTION
        Read-only. Scans every (or one named) non-hidden document library and returns one row
        per file that is currently checked out, with who holds the checkout. Fix these with
        Invoke-SPCheckIn before migrating.
    .PARAMETER SiteUrl
        The site to scan. Connected automatically.
    .PARAMETER Library
        Limit the scan to a single library (display name). Default: all document libraries.
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Get-SPCheckedOutFiles -SiteUrl https://contoso.sharepoint.com/sites/Marketing
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [string]$Library,
        [switch]$AsJson
    )

    Resolve-SPSiteConnection -SiteUrl $SiteUrl | Out-Null
    Write-SPLog "Scanning $SiteUrl for checked-out files ..."

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
                Get-PnPListItem -List $lib.Title -PageSize 500 -Fields 'FileLeafRef', 'FileRef', 'CheckoutUser' -ErrorAction Stop
            }
            foreach ($it in $items) {
                $co = $it.FieldValues['CheckoutUser']
                if ($co) {
                    $rows.Add([pscustomobject]@{
                        Library      = $lib.Title
                        FileName     = "$($it.FieldValues['FileLeafRef'])"
                        FileRef      = "$($it.FieldValues['FileRef'])"
                        CheckedOutTo = "$($co.LookupValue)"
                    })
                }
            }
        }
        catch { Write-SPLog "Could not scan '$($lib.Title)': $($_.Exception.Message)" -Level Warn }
    }

    Write-SPLog "Found $($rows.Count) checked-out file(s)." -Level $(if ($rows.Count) { 'Warn' } else { 'Success' })
    $rows | ConvertTo-SPOutput -AsJson:$AsJson
}
