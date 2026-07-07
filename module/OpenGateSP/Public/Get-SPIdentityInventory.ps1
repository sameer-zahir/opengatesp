function Get-SPIdentityInventory {
    <#
    .SYNOPSIS
        Inventory a tenant's identities for tenant-to-tenant migration: users, guests,
        security groups, and Microsoft 365 groups, with owner/member rosters. Read-only.
    .DESCRIPTION
        Step 1 of the identity-copy pipeline (docs/14): inventory the SOURCE tenant, feed the
        result to New-SPIdentityMap, review the mapping CSV, validate with Test-SPIdentityMap,
        then create with Copy-SPIdentity.

        Distribution lists and mail-enabled security groups are enumerated but marked
        Supported=$false — Microsoft Graph cannot create them; recreate those in Exchange
        admin or convert them to M365 Groups. Rosters are ';'-joined user UPNs (nested groups
        are not expanded).

        Needs Graph application/delegated scopes User.Read.All + Group.Read.All (see docs/02).
    .PARAMETER Connection
        Optional PnP connection to the source tenant (from New-SPMigrationConnection);
        defaults to the current connection.
    .PARAMETER Path
        Optional CSV path to write the inventory to (the file New-SPIdentityMap consumes).
    .PARAMETER AsJson
        Emit the inventory as a JSON array instead of objects.
    .EXAMPLE
        $src = New-SPMigrationConnection -Url https://contoso.sharepoint.com -ClientId $id -Tenant contoso.onmicrosoft.com -Thumbprint $tp
        Get-SPIdentityInventory -Connection $src -Path .\contoso-identities.csv
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [object]$Connection,
        [string]$Path,
        [switch]$AsJson
    )

    $connArg = @{}; if ($Connection) { $connArg['Connection'] = $Connection }
    Write-SPLog 'Get-SPIdentityInventory: enumerating users and groups ...'

    $users = @(Invoke-SPGraph -Method GET -Url 'v1.0/users?$select=id,userPrincipalName,displayName,mail,mailNickname,userType,accountEnabled,usageLocation&$top=999' -All @connArg)
    $groups = @(Invoke-SPGraph -Method GET -Url 'v1.0/groups?$select=id,displayName,mail,mailNickname,groupTypes,securityEnabled,mailEnabled&$top=999' -All @connArg)

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($u in $users) { $rows.Add((ConvertTo-SPIdentityInventoryRow -User $u)) }

    foreach ($g in $groups) {
        # Rosters: UPNs only (nested groups and service principals have none and are omitted).
        $owners = @(Invoke-SPGraph -Method GET -Url "v1.0/groups/$($g.id)/owners?`$select=userPrincipalName&`$top=999" -All @connArg |
                ForEach-Object { "$($_.userPrincipalName)" } | Where-Object { $_ })
        $members = @(Invoke-SPGraph -Method GET -Url "v1.0/groups/$($g.id)/members?`$select=userPrincipalName&`$top=999" -All @connArg |
                ForEach-Object { "$($_.userPrincipalName)" } | Where-Object { $_ })
        $rows.Add((ConvertTo-SPIdentityInventoryRow -Group $g -Owners $owners -Members $members))
    }

    $unsupported = @($rows | Where-Object { -not $_.Supported }).Count
    Write-SPLog ("Inventory: {0} identit(ies) — {1} user(s), {2} group(s), {3} unsupported group(s)." -f `
            $rows.Count, $users.Count, $groups.Count, $unsupported) -Level Success

    if ($Path) {
        $rows | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8
        Write-SPLog "Inventory CSV written: $Path" -Level Success
    }
    $rows | ConvertTo-SPOutput -AsJson:$AsJson
}
