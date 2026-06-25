function Resolve-SPConflict {
    <#
    .SYNOPSIS
        Decide what to do with one object when copying it to a destination, given the
        conflict mode. Pure decision logic (no SharePoint calls) so it is unit-testable.
    .OUTPUTS
        [pscustomobject] @{ Action; Reason }. Action is one of:
        Create (not at destination), Overwrite, Skip, Rename (keep both).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [bool]$Exists,
        [Nullable[datetime]]$SourceModified,
        [Nullable[datetime]]$DestModified,
        [ValidateSet('Replace', 'Skip', 'KeepBoth', 'IfNewer')][string]$Mode = 'Replace'
    )

    if (-not $Exists) {
        return [pscustomobject]@{ Action = 'Create'; Reason = 'Not present at destination' }
    }

    switch ($Mode) {
        'Replace' { [pscustomobject]@{ Action = 'Overwrite'; Reason = 'Exists; replace mode' } }
        'Skip' { [pscustomobject]@{ Action = 'Skip'; Reason = 'Exists; skip mode' } }
        'KeepBoth' { [pscustomobject]@{ Action = 'Rename'; Reason = 'Exists; keep both' } }
        'IfNewer' {
            if (-not $DestModified) {
                [pscustomobject]@{ Action = 'Overwrite'; Reason = 'No destination timestamp; copying' }
            }
            elseif ($SourceModified -and $SourceModified -gt $DestModified) {
                [pscustomobject]@{ Action = 'Overwrite'; Reason = 'Source is newer' }
            }
            else {
                [pscustomobject]@{ Action = 'Skip'; Reason = 'Destination is same or newer' }
            }
        }
    }
}
