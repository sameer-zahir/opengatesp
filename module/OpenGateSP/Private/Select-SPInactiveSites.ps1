function Select-SPInactiveSites {
    <#
    .SYNOPSIS
        Filter site-inventory rows down to those that look inactive — no content change for
        at least -InactiveDays. Pure — no I/O.
    .DESCRIPTION
        Get-SPSiteInventory emits one row per site with a .LastActivity
        (LastContentModifiedDate). For a pre-migration / governance sweep it's useful to surface
        the sites nobody has touched in months (candidates to archive or skip). This applies the
        threshold against a reference time so the result is deterministic and testable: the public
        cmdlet passes (Get-Date); tests pass a fixed -AsOf.

        Rows with no parseable LastActivity are returned too, flagged 'NoActivityData', because a
        missing activity date is itself worth a human look.
    .PARAMETER Site
        Inventory rows with .Url, .Title, .LastActivity, .StorageUsedMB (as from Get-SPSiteInventory).
    .PARAMETER InactiveDays
        A site is inactive once its last activity is at least this many days before -AsOf. Default 180.
    .PARAMETER AsOf
        Reference "now" the age is measured against. Defaults to the current date.
    .OUTPUTS
        One pscustomobject per inactive site: Url, Title, LastActivity, InactiveDays, StorageUsedMB, Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [object[]]$Site,
        [int]$InactiveDays = 180,
        [datetime]$AsOf = (Get-Date)
    )

    foreach ($s in $Site) {
        if (-not $s) { continue }
        $last = $s.LastActivity -as [Nullable[datetime]]

        if ($null -eq $last) {
            [pscustomobject]@{
                Url           = "$($s.Url)"
                Title         = "$($s.Title)"
                LastActivity  = $null
                InactiveDays  = $null
                StorageUsedMB = $s.StorageUsedMB
                Reason        = 'NoActivityData'
            }
            continue
        }

        $days = [int][math]::Floor(($AsOf - $last).TotalDays)
        if ($days -ge $InactiveDays) {
            [pscustomobject]@{
                Url           = "$($s.Url)"
                Title         = "$($s.Title)"
                LastActivity  = $last
                InactiveDays  = $days
                StorageUsedMB = $s.StorageUsedMB
                Reason        = 'Inactive'
            }
        }
    }
}
