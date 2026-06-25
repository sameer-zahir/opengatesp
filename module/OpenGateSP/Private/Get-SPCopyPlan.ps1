function Get-SPCopyPlan {
    <#
    .SYNOPSIS
        Build the dry-run plan for copying a set of source objects to a destination,
        given what already exists there and the conflict mode. Pure (no SharePoint
        calls) — feed it inventories and it returns the planned migration-report rows.
    .DESCRIPTION
        Each source/destination object is anything with .Name, plus .ObjectType and
        .Modified on the source side and .Modified on the destination side. Returns one
        New-SPCopyResult row per source object with Status WouldCopy or Skipped.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$SourceObjects,
        [object[]]$DestObjects = @(),
        [ValidateSet('Replace', 'Skip', 'KeepBoth', 'IfNewer')][string]$Mode = 'Replace'
    )

    $destByName = @{}
    foreach ($d in $DestObjects) { if ($d.Name) { $destByName[$d.Name] = $d } }

    foreach ($s in $SourceObjects) {
        $exists  = $destByName.ContainsKey($s.Name)
        $destMod = if ($exists) { $destByName[$s.Name].Modified } else { $null }
        $c = Resolve-SPConflict -Exists $exists -SourceModified $s.Modified -DestModified $destMod -Mode $Mode
        $status = if ($c.Action -eq 'Skip') { 'Skipped' } else { 'WouldCopy' }
        New-SPCopyResult -ObjectType $s.ObjectType -Name $s.Name -Action $c.Action -Status $status -Detail $c.Reason
    }
}
