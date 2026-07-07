function Invoke-SPGraph {
    <#
    .SYNOPSIS
        Call Microsoft Graph through the current PnP connection's token, with throttling
        retry and @odata.nextLink paging. The module's single Graph seam.
    .DESCRIPTION
        PnP.PowerShell covers many Graph operations with dedicated cmdlets; the gaps (user
        creation, guest invitations, verified-domain enumeration, membership $ref adds) go
        through Invoke-PnPGraphMethod. This wrapper keeps every raw call consistent: each
        request runs inside Invoke-SPRetry (Retry-After-aware since 0.13), GET collections
        are paged to completion with -All, and the caller gets plain objects back.

        Deliberately NOT the Microsoft.Graph SDK: PnP.PowerShell stays the module's only
        dependency (see docs/14).
    .PARAMETER Method
        HTTP method: GET, POST, PATCH, DELETE.
    .PARAMETER Url
        Graph URL, relative ('v1.0/users?$select=...') or absolute (an @odata.nextLink).
    .PARAMETER Body
        Optional request body (hashtable) for POST/PATCH.
    .PARAMETER Connection
        Optional PnP connection (from New-SPMigrationConnection); defaults to the current one.
    .PARAMETER All
        For GET collection endpoints: follow @odata.nextLink until the collection is complete
        and return the accumulated items (the .value entries), not the envelope.
    .OUTPUTS
        With -All: the collection items. Otherwise the deserialized response as-is.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Body', Justification = 'Used inside the $call scriptblock, which the rule cannot see into.')]
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        [hashtable]$Body,
        [object]$Connection,
        [switch]$All
    )

    $connArg = @{}; if ($Connection) { $connArg['Connection'] = $Connection }

    $call = {
        param($u)
        $p = @{ Url = $u; Method = $Method; ErrorAction = 'Stop' }
        if ($Body) { $p['Content'] = $Body }
        Invoke-SPRetry -Operation "Graph $Method $u" { Invoke-PnPGraphMethod @p @connArg }
    }

    if (-not ($All -and $Method -eq 'GET')) {
        return & $call $Url
    }

    # Page a GET collection to completion.
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Url
    while ($next) {
        $page = & $call $next
        $valueProp = $page.PSObject.Properties['value']
        if ($valueProp) {
            foreach ($v in @($valueProp.Value)) { if ($null -ne $v) { $items.Add($v) } }
        }
        elseif ($null -ne $page) {
            # Endpoint returned a bare object (no collection envelope) — hand it through.
            $items.Add($page)
        }
        $nextProp = $page.PSObject.Properties['@odata.nextLink']
        $next = if ($nextProp -and $nextProp.Value) { "$($nextProp.Value)" } else { $null }
    }
    @($items)
}
