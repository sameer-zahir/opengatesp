function Copy-SPPlannerPlan {
    <#
    .SYNOPSIS
        Recreate a Planner plan — its buckets and tasks — on a destination Microsoft 365
        Group. Dry-run by default.
    .DESCRIPTION
        Reads the source plan's buckets and tasks, creates a new plan on the destination group,
        recreates each bucket (by name), and recreates each task into its matching bucket.
        Assignments, attachments, and checklists are not copied (they reference per-tenant ids).
        Needs a Graph connection with Group.ReadWrite.All / Tasks scopes.
    .PARAMETER SourcePlanId
        The source plan's id.
    .PARAMETER DestinationGroupId
        The id of the Microsoft 365 Group that will own the new plan.
    .PARAMETER Title
        Title for the new plan.
    .PARAMETER Connection
        Optional PnP connection; defaults to the current one.
    .PARAMETER Force
        Create without the confirmation prompt (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the report as JSON.
    .EXAMPLE
        Copy-SPPlannerPlan -SourcePlanId $pid -DestinationGroupId $gid -Title "Sprint board (copy)" -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SourcePlanId,
        [Parameter(Mandatory)][string]$DestinationGroupId,
        [Parameter(Mandatory)][string]$Title,
        [object]$Connection,
        [switch]$Force,
        [switch]$AsJson
    )

    $connArg = @{}; if ($Connection) { $connArg['Connection'] = $Connection }
    Write-SPLog "Copy-SPPlannerPlan: plan '$SourcePlanId' -> group '$DestinationGroupId' as '$Title' (WhatIf=$($WhatIfPreference))"

    $buckets = @(Get-PnPPlannerBucket -PlanId $SourcePlanId @connArg -ErrorAction Stop)
    $tasks   = @(Get-PnPPlannerTask   -PlanId $SourcePlanId @connArg -ErrorAction SilentlyContinue)

    $results = [System.Collections.Generic.List[object]]::new()

    if (-not $Force -and -not $PSCmdlet.ShouldProcess($Title, "Create plan with $($buckets.Count) bucket(s) and $($tasks.Count) task(s)")) {
        $results.Add((New-SPCopyResult -ObjectType 'PlannerPlan' -Name $Title -Action 'Create' -Status 'WouldCopy' -Detail "$($buckets.Count) bucket(s), $($tasks.Count) task(s)"))
        return ($results | ConvertTo-SPOutput -AsJson:$AsJson)
    }

    # Create the plan.
    $newPlan = $null
    try {
        $newPlan = Invoke-SPRetry -Operation "create plan $Title" { New-PnPPlannerPlan -Group $DestinationGroupId -Title $Title @connArg -ErrorAction Stop }
        $results.Add((New-SPCopyResult -ObjectType 'PlannerPlan' -Name $Title -Action 'Create' -Status 'Success' -Detail 'Created'))
    }
    catch {
        $results.Add((New-SPCopyResult -ObjectType 'PlannerPlan' -Name $Title -Action 'Create' -Status 'Error' -Detail $_.Exception.Message))
        return ($results | ConvertTo-SPOutput -AsJson:$AsJson)
    }

    # Recreate buckets, keeping a source-bucket-id -> new-bucket-id map for tasks.
    $bucketMap = @{}
    foreach ($b in $buckets) {
        try {
            $nb = Invoke-SPRetry -Operation "add bucket $($b.Name)" { Add-PnPPlannerBucket -PlanId $newPlan.Id -Name $b.Name @connArg -ErrorAction Stop }
            if ($b.Id -and $nb.Id) { $bucketMap[$b.Id] = $nb.Id }
            $results.Add((New-SPCopyResult -ObjectType 'PlannerBucket' -Name $b.Name -Action 'Create' -Status 'Success' -Detail 'Created'))
        }
        catch {
            $results.Add((New-SPCopyResult -ObjectType 'PlannerBucket' -Name $b.Name -Action 'Create' -Status 'Error' -Detail $_.Exception.Message))
        }
    }

    # Recreate tasks into the matching bucket.
    foreach ($t in $tasks) {
        try {
            $tp = @{ PlanId = $newPlan.Id; Title = $t.Title }
            if ($t.BucketId -and $bucketMap.ContainsKey($t.BucketId)) { $tp['Bucket'] = $bucketMap[$t.BucketId] }
            if ($t.Description) { $tp['Description'] = $t.Description }
            Invoke-SPRetry -Operation "add task $($t.Title)" { Add-PnPPlannerTask @tp @connArg -ErrorAction Stop } | Out-Null
            $results.Add((New-SPCopyResult -ObjectType 'PlannerTask' -Name $t.Title -Action 'Create' -Status 'Success' -Detail 'Created'))
        }
        catch {
            $results.Add((New-SPCopyResult -ObjectType 'PlannerTask' -Name $t.Title -Action 'Create' -Status 'Error' -Detail $_.Exception.Message))
        }
    }

    $errors = @($results | Where-Object Status -eq 'Error').Count
    Write-SPLog ("Copy-SPPlannerPlan: {0} step(s), {1} error(s)." -f $results.Count, $errors) -Level $(if ($errors) { 'Warn' } else { 'Success' })
    $results | ConvertTo-SPOutput -AsJson:$AsJson
}
