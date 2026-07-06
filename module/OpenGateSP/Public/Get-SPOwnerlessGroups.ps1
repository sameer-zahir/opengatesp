function Get-SPOwnerlessGroups {
    <#
    .SYNOPSIS
        Report Microsoft 365 Groups (and the Teams / sites behind them) that have no owner — a
        governance risk: nobody to approve members, manage the lifecycle, or answer access reviews.
        Read-only.
    .DESCRIPTION
        Lists every Microsoft 365 Group and counts its owners; reports those with zero. Ownerless
        *public* groups are graded Error, private ones Warning. Needs Microsoft Graph Group.Read.All
        (register the app with that scope; see docs/02). Slower on large tenants (one owner lookup
        per group). Part of ShareGate-Protect-style governance detection.
    .PARAMETER AsJson
        Emit a JSON array instead of objects.
    .EXAMPLE
        Get-SPOwnerlessGroups | Format-Table
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([switch]$AsJson)

    Assert-SPConnection | Out-Null
    Write-SPLog "Scanning Microsoft 365 Groups for ownerless ones (needs Graph Group.Read.All)..."
    $groups = @(Invoke-SPRetry -Operation 'Get-PnPMicrosoft365Group' { Get-PnPMicrosoft365Group -ErrorAction Stop })

    $rows = foreach ($g in $groups) {
        $owners = @(Get-PnPMicrosoft365GroupOwner -Identity $g.Id -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            DisplayName = $g.DisplayName
            Mail        = $g.Mail
            Visibility  = "$($g.Visibility)"
            OwnerCount  = $owners.Count
        }
    }

    $ownerless = @(Select-SPOwnerlessGroups -Group $rows)
    $level = if (@($ownerless | Where-Object { $_.Severity -eq 'Error' }).Count) { 'Error' }
    elseif ($ownerless.Count) { 'Warning' } else { 'Success' }
    Write-SPLog "$($ownerless.Count) of $($groups.Count) group(s) have no owner." -Level $level
    $ownerless | ConvertTo-SPOutput -AsJson:$AsJson
}
