#Requires -Version 7.4
# Pure, UI-thread-safe helpers for the GUI, kept separate so they can be unit-tested headlessly
# (dot-sourced by Start-OpenGateSPGui.ps1; covered by tests/Gui.Tests.ps1). No WPF dependencies.

function Get-SPAppIdFromResult {
    <#
    .SYNOPSIS
        Pull the Entra application (client) ID out of whatever
        Register-PnPEntraIDAppForInteractiveLogin returned.
    .DESCRIPTION
        The return shape varies across PnP.PowerShell versions — sometimes a typed object with a
        ClientId / AzureAppId / 'AzureAppId/ClientId' property, sometimes a hashtable, sometimes just
        host text. This digs the first GUID out of any of those, so the one-click sign-in can capture
        the app id no matter the shape. Returns $null if nothing GUID-shaped is found.
    #>
    param($Result)

    $guid = '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}'
    $names = @('ClientId', 'AzureAppId', 'AppId', 'ApplicationId', 'AzureAppId/ClientId')

    foreach ($item in @($Result)) {
        if ($null -eq $item) { continue }

        if ($item -is [string]) {
            if ($item -match $guid) { return $matches[0] }
            continue
        }
        if ($item -is [System.Collections.IDictionary]) {
            foreach ($name in $names) {
                if ($item.Contains($name) -and "$($item[$name])" -match $guid) { return $matches[0] }
            }
            continue
        }
        foreach ($name in $names) {
            $val = $null
            try { $val = $item.PSObject.Properties[$name].Value } catch { $val = $null }
            if ($val -and "$val" -match $guid) { return $matches[0] }
        }
    }

    # Last resort: stringify the whole thing and take the first GUID.
    if (($Result | Out-String) -match $guid) { return $matches[0] }
    return $null
}

function Test-SPConnectInput {
    <#
    .SYNOPSIS
        Validate connection inputs before attempting Connect-SPTool, so the user gets a specific,
        actionable message instead of an opaque PnP error after the round-trip.
    .OUTPUTS
        [string[]] of human-readable problems. An empty array means the inputs look valid.
    #>
    param([string]$ClientId, [string]$Tenant, [string]$Url)

    $problems = [System.Collections.Generic.List[string]]::new()
    $guid = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'

    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        $problems.Add('Client ID is required — sign in to your tenant first (one-time setup).')
    }
    elseif ($ClientId.Trim() -notmatch $guid) {
        $problems.Add('Client ID must be a GUID like 11111111-2222-3333-4444-555555555555.')
    }
    if (-not [string]::IsNullOrWhiteSpace($Tenant) -and $Tenant.Trim() -notmatch '^[\w.-]+\.[A-Za-z]{2,}$') {
        $problems.Add('Tenant should look like contoso.onmicrosoft.com.')
    }
    if (-not [string]::IsNullOrWhiteSpace($Url) -and $Url.Trim() -notmatch '^https://[\w-]+\.sharepoint\.(com|us|de|cn)(/.*)?$') {
        $problems.Add('Site URL should look like https://contoso.sharepoint.com/sites/Team.')
    }

    , $problems.ToArray()
}
