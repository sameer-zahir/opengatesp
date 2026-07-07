function Resolve-SPAuthChoice {
    <#
    .SYNOPSIS
        Decide the auth mode (AppOnly | Delegated) and delegated flow
        (Interactive | DeviceLogin | OSLogin) for a connection, from the explicit switches
        and the saved config. Pure — no I/O, no PnP.
    .DESCRIPTION
        Rules, in order:
        - Certificate arguments always win: -Thumbprint / -CertificatePath => AppOnly.
        - ANY delegated switch (-DeviceLogin or -OSLogin) overrides a saved AuthMode=AppOnly —
          previously only -DeviceLogin did, so -OSLogin against an app-only config would have
          silently connected app-only.
        - Explicit flow switches beat the saved DelegatedFlow; with no switch, the saved
          flavor is reused (so device-code users stay device-code on plain Connect-SPTool).
        - -OSLogin uses the Windows broker (WAM): explicitly requesting it off-Windows throws;
          a SAVED OSLogin flavor off-Windows quietly downgrades to the browser instead, so a
          config copied from a Windows box still connects.
    .PARAMETER OnWindows
        Injectable for tests; defaults to the real platform.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Cfg,
        [string]$Thumbprint,
        [string]$CertificatePath,
        [bool]$DeviceLogin,
        [bool]$OSLogin,
        [bool]$OnWindows = $IsWindows
    )

    if ($DeviceLogin -and $OSLogin) { throw 'Choose one of -DeviceLogin or -OSLogin, not both.' }
    if ($OSLogin -and -not $OnWindows) {
        throw '-OSLogin uses the Windows broker (WAM) and is Windows-only. Use the browser sign-in (default) or -DeviceLogin instead.'
    }

    $delegatedFlag = $DeviceLogin -or $OSLogin
    $useAppOnly = [bool]($Thumbprint -or $CertificatePath -or (-not $delegatedFlag -and "$($Cfg.AuthMode)" -eq 'AppOnly'))

    $flow = if ($useAppOnly) { $null }
            elseif ($DeviceLogin) { 'DeviceLogin' }
            elseif ($OSLogin) { 'OSLogin' }
            elseif ("$($Cfg.DelegatedFlow)" -in 'DeviceLogin', 'OSLogin') { "$($Cfg.DelegatedFlow)" }
            else { 'Interactive' }
    if ($flow -eq 'OSLogin' -and -not $OnWindows -and -not $OSLogin) { $flow = 'Interactive' }

    [pscustomobject]@{
        Mode = $(if ($useAppOnly) { 'AppOnly' } else { 'Delegated' })
        Flow = $flow
    }
}
