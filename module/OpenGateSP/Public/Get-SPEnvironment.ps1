function Get-SPEnvironment {
    <#
    .SYNOPSIS
        List the saved environments (named tenant connection profiles) and which one is
        active. Local config only — does not call SharePoint.
    .DESCRIPTION
        An environment is a saved connection to a tenant: URL, client id, tenant, auth mode
        and delegated flavor. Create or update one by connecting:
        Connect-SPTool -Environment "Contoso" ... — and switch with
        Connect-SPTool -Environment <name>. See docs/03.
    .PARAMETER Name
        Return only the named environment (case-insensitive).
    .PARAMETER AsJson
        Emit the list as a JSON array instead of objects.
    .EXAMPLE
        Get-SPEnvironment
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Name,
        [switch]$AsJson
    )

    $rows = @(Get-SPEnvironmentsFromConfig -Config (Get-SPConfig))
    if ($Name) { $rows = @($rows | Where-Object { $_.Name -ieq $Name }) }
    $rows | ConvertTo-SPOutput -AsJson:$AsJson
}
