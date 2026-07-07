function Remove-SPEnvironment {
    <#
    .SYNOPSIS
        Remove a saved environment (named tenant connection profile) from the local config.
        Does not touch the tenant and does not disconnect a live session.
    .DESCRIPTION
        If the removed environment was the active one, the active pointer and the flat
        connection defaults are cleared too — the next Connect-SPTool needs an -Environment
        or explicit parameters. Re-adding is just connecting again with -Environment <name>.
    .PARAMETER Name
        The environment to remove (case-insensitive). Get-SPEnvironment lists them.
    .PARAMETER Force
        Skip the confirmation prompt (still respects -WhatIf).
    .PARAMETER AsJson
        Emit the result as JSON.
    .EXAMPLE
        Remove-SPEnvironment -Name Fabrikam -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Force,
        [switch]$AsJson
    )

    # The pure transform validates the name (throws on unknown) without writing anything;
    # only the save is gated by ShouldProcess, so -WhatIf still surfaces a bad name.
    $newCfg = Remove-SPEnvironmentFromConfig -Config (Get-SPConfig) -Name $Name

    if ($Force) { $ConfirmPreference = 'None' }   # -Force skips the prompt; -WhatIf must still override
    if ($PSCmdlet.ShouldProcess($Name, 'Remove saved environment')) {
        Save-SPConfigObject -Config $newCfg | Out-Null
        Write-SPLog "Environment '$Name' removed." -Level Success
        [pscustomobject]@{ Name = $Name; Status = 'Removed' } | ConvertTo-SPOutput -AsJson:$AsJson
    }
    else {
        [pscustomobject]@{ Name = $Name; Status = 'WouldRemove' } | ConvertTo-SPOutput -AsJson:$AsJson
    }
}
