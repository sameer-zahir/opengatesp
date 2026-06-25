#Requires -Version 7.4
# Tests for Get-SPScheduledCommand — pure command-line assembly, no registration and
# no tenant. The Run-/Register- scripts that consume it are integration glue and are
# verified by review (they call Windows-only ScheduledTasks cmdlets).

BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\scheduled\Get-SPScheduledCommand.ps1')
    $script:Site = 'https://contoso.sharepoint.com/sites/Mktg'
}

Describe 'Get-SPScheduledCommand' {
    It 'puts pwsh and the site URL on the command line' {
        $c = Get-SPScheduledCommand -SiteUrl $script:Site
        $c.Executable | Should -Be 'pwsh'
        $c.CommandLine | Should -BeLike 'pwsh *'
        $c.CommandLine | Should -BeLike "*$($script:Site)*"
    }
    It 'targets Run-GovernanceReport.ps1' {
        (Get-SPScheduledCommand -SiteUrl $script:Site).CommandLine | Should -BeLike '*Run-GovernanceReport.ps1*'
    }
    It 'passes -NoProfile and joins reports with a comma' {
        $c = Get-SPScheduledCommand -SiteUrl $script:Site -Reports Sharing, Permissions
        $c.Arguments | Should -Contain '-NoProfile'
        $c.CommandLine | Should -BeLike '*Sharing,Permissions*'
    }
    It 'includes app-only auth flags only when supplied' {
        $with = Get-SPScheduledCommand -SiteUrl $script:Site -Thumbprint 'ABC123' -ClientId 'app-id' -Tenant 'contoso.onmicrosoft.com'
        $with.CommandLine | Should -BeLike '*-Thumbprint ABC123*'
        $with.CommandLine | Should -BeLike '*-ClientId app-id*'

        $without = Get-SPScheduledCommand -SiteUrl $script:Site
        $without.CommandLine | Should -Not -BeLike '*-Thumbprint*'
    }
    It 'quotes arguments that contain spaces' {
        $c = Get-SPScheduledCommand -SiteUrl $script:Site -OutDir 'C:\My Reports'
        $c.ArgumentLine.Contains('"C:\My Reports"') | Should -BeTrue
    }
}
