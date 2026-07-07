#Requires -Version 7.4
# Regression tests for the destructive-cmdlet guardrails: the orphaned-users fail-closed
# directory check, and the -Force/-WhatIf ShouldProcess contract (-Force skips the prompt
# but -WhatIf — including a session-global $WhatIfPreference — must still win).
# PnP cmdlets are stubbed + mocked: no PnP.PowerShell, no tenant, CI-friendly.

BeforeAll {
    $mod = Join-Path $PSScriptRoot '..\module\OpenGateSP'
    . (Join-Path $mod 'Private\Write-SPLog.ps1')
    . (Join-Path $mod 'Private\ConvertTo-SPOutput.ps1')
    . (Join-Path $mod 'Private\New-SPCopyResult.ps1')
    . (Join-Path $mod 'Private\Get-SPHttpStatusCode.ps1')
    . (Join-Path $mod 'Private\Get-SPRetryDelay.ps1')
    . (Join-Path $mod 'Private\Invoke-SPRetry.ps1')
    . (Join-Path $mod 'Private\Select-SPVersionsToTrim.ps1')
    . (Join-Path $mod 'Private\ConvertTo-SPPrincipalKey.ps1')
    . (Join-Path $mod 'Private\Get-SPOrphanedPrincipals.ps1')
    . (Join-Path $mod 'Public\Get-SPOrphanedUsers.ps1')
    . (Join-Path $mod 'Public\Remove-SPOrphanedUsers.ps1')
    . (Join-Path $mod 'Public\Clear-SPVersionHistory.ps1')

    # Stubs standing in for PnP.PowerShell / the connection helper so Pester can Mock them.
    function Resolve-SPSiteConnection { [CmdletBinding()] param([string]$SiteUrl) $true }
    function Get-PnPUser { [CmdletBinding()] param() }
    function Get-PnPEntraIDUser { [CmdletBinding()] param() }
    function Remove-PnPUser { [CmdletBinding()] param($Identity, [switch]$Force) }
    function Get-PnPFileVersion { [CmdletBinding()] param([string]$Url) }
    function Remove-PnPFileVersion { [CmdletBinding()] param([string]$Url, $Identity, [switch]$Force) }
}

Describe 'Get-SPOrphanedUsers fails closed on a bad directory snapshot' {
    BeforeEach {
        Mock Resolve-SPSiteConnection { $true }
        Mock Get-PnPUser { @(
                [pscustomobject]@{ LoginName = 'i:0#.f|membership|jane@contoso.com'; Title = 'Jane'; Email = 'jane@contoso.com' }
                [pscustomobject]@{ LoginName = 'i:0#.f|membership|bob@contoso.com'; Title = 'Bob'; Email = 'bob@contoso.com' }
            ) }
    }
    It 'throws when the directory snapshot is empty instead of flagging everyone' {
        Mock Get-PnPEntraIDUser { @() }
        { Get-SPOrphanedUsers -SiteUrl 'https://x' } | Should -Throw '*refusing to flag*'
    }
    It 'propagates a directory query failure (no silent continue)' {
        Mock Get-PnPEntraIDUser { throw 'Access denied: missing User.Read.All' }
        { Get-SPOrphanedUsers -SiteUrl 'https://x' } | Should -Throw '*User.Read.All*'
    }
    It 'the throw aborts Remove-SPOrphanedUsers before any deletion' {
        Mock Get-PnPEntraIDUser { @() }
        Mock Remove-PnPUser {}
        { Remove-SPOrphanedUsers -SiteUrl 'https://x' -Force } | Should -Throw '*refusing to flag*'
        Should -Invoke Remove-PnPUser -Times 0 -Exactly
    }
    It 'still reports real orphans with a healthy directory' {
        Mock Get-PnPEntraIDUser { @([pscustomobject]@{ UserPrincipalName = 'jane@contoso.com' }) }
        $rows = @(Get-SPOrphanedUsers -SiteUrl 'https://x')
        $rows.Count | Should -Be 1
        $rows[0].Title | Should -Be 'Bob'
    }
}

Describe 'ShouldProcess contract: -WhatIf always wins, even with -Force' {
    Context 'Remove-SPOrphanedUsers' {
        BeforeEach {
            Mock Resolve-SPSiteConnection { $true }
            Mock Get-PnPUser { @([pscustomobject]@{ LoginName = 'i:0#.f|membership|gone@contoso.com'; Title = 'Gone'; Email = 'gone@contoso.com' }) }
            Mock Get-PnPEntraIDUser { @([pscustomobject]@{ UserPrincipalName = 'admin@contoso.com' }) }
            Mock Remove-PnPUser {}
        }
        It '-WhatIf performs no write' {
            $rows = @(Remove-SPOrphanedUsers -SiteUrl 'https://x' -WhatIf)
            Should -Invoke Remove-PnPUser -Times 0 -Exactly
            $rows[0].Status | Should -Be 'WouldCopy'
        }
        It '-Force -WhatIf performs no write (the -Force bypass regression)' {
            $rows = @(Remove-SPOrphanedUsers -SiteUrl 'https://x' -Force -WhatIf)
            Should -Invoke Remove-PnPUser -Times 0 -Exactly
            $rows[0].Status | Should -Be 'WouldCopy'
        }
        It 'a session-global $WhatIfPreference overrides -Force' {
            $WhatIfPreference = $true
            @(Remove-SPOrphanedUsers -SiteUrl 'https://x' -Force) | Out-Null
            Should -Invoke Remove-PnPUser -Times 0 -Exactly
        }
        It '-Force alone applies without prompting' {
            $rows = @(Remove-SPOrphanedUsers -SiteUrl 'https://x' -Force)
            Should -Invoke Remove-PnPUser -Times 1 -Exactly
            $rows[0].Status | Should -Be 'Success'
        }
    }
    Context 'Clear-SPVersionHistory' {
        BeforeEach {
            Mock Resolve-SPSiteConnection { $true }
            Mock Get-PnPFileVersion { @(1..12 | ForEach-Object { [pscustomobject]@{ ID = $_; VersionLabel = "0.$_" } }) }
            Mock Remove-PnPFileVersion {}
        }
        It '-WhatIf performs no write' {
            $rows = @(Clear-SPVersionHistory -SiteUrl 'https://x' -FileUrl '/f.pptx' -WhatIf)
            Should -Invoke Remove-PnPFileVersion -Times 0 -Exactly
            $rows.Count | Should -Be 2
            $rows[0].Status | Should -Be 'WouldCopy'
        }
        It '-Force -WhatIf performs no write (the -Force bypass regression)' {
            @(Clear-SPVersionHistory -SiteUrl 'https://x' -FileUrl '/f.pptx' -Force -WhatIf) | Out-Null
            Should -Invoke Remove-PnPFileVersion -Times 0 -Exactly
        }
        It 'a session-global $WhatIfPreference overrides -Force' {
            $WhatIfPreference = $true
            @(Clear-SPVersionHistory -SiteUrl 'https://x' -FileUrl '/f.pptx' -Force) | Out-Null
            Should -Invoke Remove-PnPFileVersion -Times 0 -Exactly
        }
        It '-Force alone applies without prompting' {
            $rows = @(Clear-SPVersionHistory -SiteUrl 'https://x' -FileUrl '/f.pptx' -Force)
            Should -Invoke Remove-PnPFileVersion -Times 2 -Exactly
            foreach ($r in $rows) { $r.Status | Should -Be 'Success' }
        }
    }
}
