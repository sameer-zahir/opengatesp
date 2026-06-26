function Copy-SPPermissions {
    <#
    .SYNOPSIS
        Copy a site's permissions (role assignments) to another site, remapping users and
        groups through a principal map — same-tenant or, with a mapping, tenant-to-tenant.
    .DESCRIPTION
        Reads the source site's role assignments (and, with -IncludeListPermissions, any
        list/library with unique permissions), resolves each principal through a map built
        from -MappingCsv and/or a -DomainFrom/-DomainTo swap, and re-applies the same role
        levels on the destination.

        SAFETY: dry-run by default — it reports what it *would* grant (and flags unmapped
        principals) and writes nothing until you confirm or pass -Force.

        NOTE: in the SAME tenant, SharePoint groups and their site-level grants already come
        across with the structure template (Copy-SPSite). This function fills the gaps —
        unique list permissions and direct grants — and is the path for **principal remapping**
        when the destination is a different tenant. A $null mapping in the same tenant means
        "use the principal as-is"; a different tenant requires every principal to map.
    .PARAMETER SourceUrl
        Site to read permissions from.
    .PARAMETER DestinationUrl
        Site to apply them to.
    .PARAMETER MappingCsv
        Optional CSV with Source,Destination columns (logins/emails) for explicit remapping.
    .PARAMETER DomainFrom
        Optional source domain for a blanket domain swap (e.g. contoso.com).
    .PARAMETER DomainTo
        Optional destination domain for the swap (e.g. fabrikam.com).
    .PARAMETER IncludeListPermissions
        Also copy unique (broken-inheritance) list/library permissions.
    .PARAMETER Force
        Apply without the confirmation prompt (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the report as a JSON array.
    .EXAMPLE
        Copy-SPPermissions -SourceUrl .../sites/A -DestinationUrl .../sites/B -IncludeListPermissions -WhatIf
    .EXAMPLE
        Copy-SPPermissions -SourceUrl .../sites/A -DestinationUrl .../sites/B -DomainFrom contoso.com -DomainTo fabrikam.com -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SourceUrl,
        [Parameter(Mandatory)][string]$DestinationUrl,
        [string]$MappingCsv,
        [string]$DomainFrom,
        [string]$DomainTo,
        [switch]$IncludeListPermissions,
        [object]$SourceConnection,
        [object]$DestinationConnection,
        [switch]$Force,
        [switch]$AsJson
    )

    if ($SourceUrl.TrimEnd('/') -ieq $DestinationUrl.TrimEnd('/')) { throw 'Source and destination are the same site.' }
    Write-SPLog "Copy-SPPermissions: $SourceUrl -> $DestinationUrl (lists=$IncludeListPermissions, WhatIf=$($WhatIfPreference))"

    # Build the principal map (pure, tested).
    $rows = @()
    if ($MappingCsv) {
        if (-not (Test-Path -LiteralPath $MappingCsv)) { throw "Mapping CSV not found: $MappingCsv" }
        $rows = @(Import-Csv -LiteralPath $MappingCsv)
    }
    $map = ConvertTo-SPPrincipalMap -Row $rows -DomainFrom $DomainFrom -DomainTo $DomainTo

    # Reuse pre-opened connections (cross-tenant) or build them from saved config (same tenant).
    if ($SourceConnection -and $DestinationConnection) {
        $src = $SourceConnection
        $dst = $DestinationConnection
    }
    else {
        $srcParams = Get-SPConnectParams -Url $SourceUrl
        $dstParams = Get-SPConnectParams -Url $DestinationUrl
        $src = Invoke-SPRetry -Operation 'connect source' { Connect-PnPOnline @srcParams -ReturnConnection }
        $dst = Invoke-SPRetry -Operation 'connect destination' { Connect-PnPOnline @dstParams -ReturnConnection }
    }

    $assignments = @(Get-SPRoleAssignments -Connection $src -IncludeListPermissions:$IncludeListPermissions)
    Write-SPLog "Read $($assignments.Count) source role assignment(s)."

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($a in $assignments) {
        $dest   = Resolve-SPPrincipal -Principal $a.LoginName -Map $map
        $mapped = [bool]$dest
        if (-not $dest) { $dest = $a.LoginName }   # same-tenant: principal exists as-is

        $isSpGroup = $a.PrincipalType -eq 'SharePointGroup'
        $rolesText = ($a.Roles -join ', ')
        $name      = if ($a.Scope -eq 'List') { "$($a.ListTitle): $($a.Principal)" } else { $a.Principal }
        $detail    = "$rolesText -> $dest" + $(if ($mapped) { ' (mapped)' } else { '' })

        # Cross-tenant principals that don't map are a real risk — surface, don't silently apply as-is.
        if (-not $mapped -and ($DomainFrom -or $MappingCsv) -and $a.LoginName -match '@') {
            $results.Add((New-SPCopyResult -ObjectType "Permission ($($a.Scope))" -Name $name -Action 'Skip' -Status 'Warning' -Detail "No mapping for $($a.LoginName) — skipped"))
            continue
        }

        if (-not $Force -and -not $PSCmdlet.ShouldProcess($DestinationUrl, "Grant '$rolesText' to $dest")) {
            $results.Add((New-SPCopyResult -ObjectType "Permission ($($a.Scope))" -Name $name -Action 'Create' -Status 'WouldCopy' -Detail $detail))
            continue
        }
        try {
            foreach ($role in $a.Roles) {
                if ($a.Scope -eq 'List') {
                    if ($isSpGroup) { Set-PnPListPermission -Identity $a.ListTitle -Group $dest -AddRole $role -Connection $dst -ErrorAction Stop }
                    else { Set-PnPListPermission -Identity $a.ListTitle -User $dest -AddRole $role -Connection $dst -ErrorAction Stop }
                }
                else {
                    if ($isSpGroup) { Set-PnPWebPermission -Group $dest -AddRole $role -Connection $dst -ErrorAction Stop }
                    else { Set-PnPWebPermission -User $dest -AddRole $role -Connection $dst -ErrorAction Stop }
                }
            }
            $results.Add((New-SPCopyResult -ObjectType "Permission ($($a.Scope))" -Name $name -Action 'Create' -Status 'Success' -Detail $detail))
        }
        catch {
            $results.Add((New-SPCopyResult -ObjectType "Permission ($($a.Scope))" -Name $name -Action 'Create' -Status 'Error' -Detail "$($dest): $($_.Exception.Message)"))
        }
    }

    $errors = @($results | Where-Object Status -eq 'Error').Count
    Write-SPLog ("Copy-SPPermissions: {0} assignment(s), {1} error(s)." -f $results.Count, $errors) -Level $(if ($errors) { 'Warn' } else { 'Success' })
    $results | ConvertTo-SPOutput -AsJson:$AsJson
}
