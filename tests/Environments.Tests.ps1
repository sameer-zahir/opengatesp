#Requires -Version 7.4
# Unit tests for the named-environments config schema (spconfig.json v2): lazy v1->v2
# migration, environment upsert/select/remove as pure object transforms, the flat-projection
# rebuild (the stale-Thumbprint regression), and Set-SPConfig's write-through. Pure logic +
# TestDrive file I/O — no PnP, no tenant, CI-friendly.

BeforeAll {
    $priv = Join-Path $PSScriptRoot '..\module\OpenGateSP\Private'
    . (Join-Path $priv 'Write-SPLog.ps1')
    . (Join-Path $priv 'SPEnvironments.ps1')
    . (Join-Path $priv 'SPConfig.ps1')

    function New-V1Config {
        [pscustomobject]@{
            Url        = 'https://contoso.sharepoint.com'
            ClientId   = '11111111-2222-3333-4444-555555555555'
            Tenant     = 'contoso.onmicrosoft.com'
            AuthMode   = 'AppOnly'
            Thumbprint = 'AB12CD34'
        }
    }
}

Describe 'ConvertTo-SPEnvironmentsConfig (v1 -> v2 migration)' {
    It 'synthesizes one environment from a flat v1 config, named after the tenant label' {
        $cfg = ConvertTo-SPEnvironmentsConfig -Config (New-V1Config)
        $cfg.ConfigVersion | Should -Be 2
        $cfg.ActiveEnvironment | Should -Be 'contoso'
        $env = $cfg.Environments.contoso
        $env.ClientId | Should -Be '11111111-2222-3333-4444-555555555555'
        $env.AuthMode | Should -Be 'AppOnly'
        $env.Thumbprint | Should -Be 'AB12CD34'
        # the flat projection survives untouched
        $cfg.Url | Should -Be 'https://contoso.sharepoint.com'
    }
    It 'falls back to the name Default when there is no tenant' {
        $cfg = ConvertTo-SPEnvironmentsConfig -Config ([pscustomobject]@{ ClientId = 'x' })
        $cfg.ActiveEnvironment | Should -Be 'Default'
    }
    It 'is idempotent on a v2 config' {
        $once = ConvertTo-SPEnvironmentsConfig -Config (New-V1Config)
        $twice = ConvertTo-SPEnvironmentsConfig -Config $once
        @($twice.Environments.PSObject.Properties.Name) | Should -Be @('contoso')
        $twice.ActiveEnvironment | Should -Be 'contoso'
    }
    It 'turns an empty config into v2 with no environments and no active pointer' {
        $cfg = ConvertTo-SPEnvironmentsConfig -Config ([pscustomobject]@{})
        $cfg.ConfigVersion | Should -Be 2
        @($cfg.Environments.PSObject.Properties).Count | Should -Be 0
        $cfg.PSObject.Properties['ActiveEnvironment'] | Should -BeNullOrEmpty
    }
    It 'never mutates the input object' {
        $input = New-V1Config
        ConvertTo-SPEnvironmentsConfig -Config $input | Out-Null
        $input.PSObject.Properties['Environments'] | Should -BeNullOrEmpty
    }
}

Describe 'Set-SPEnvironmentInConfig (upsert)' {
    It 'adds a new environment without touching the active one' {
        $cfg = ConvertTo-SPEnvironmentsConfig -Config (New-V1Config)
        $cfg = Set-SPEnvironmentInConfig -Config $cfg -Name 'Fabrikam' -Settings @{
            ClientId = 'fab-id'; Tenant = 'fabrikam.onmicrosoft.com'; AuthMode = 'Delegated'
        }
        @($cfg.Environments.PSObject.Properties.Name) | Sort-Object | Should -Be @('contoso', 'Fabrikam')
        $cfg.ActiveEnvironment | Should -Be 'contoso'
        $cfg.Thumbprint | Should -Be 'AB12CD34'   # projection still the active env
    }
    It 'update merges into an existing environment without dropping unspecified keys' {
        $cfg = ConvertTo-SPEnvironmentsConfig -Config (New-V1Config)
        $cfg = Set-SPEnvironmentInConfig -Config $cfg -Name 'contoso' -Settings @{ Url = 'https://contoso.sharepoint.com/sites/hub' }
        $cfg.Environments.contoso.Url | Should -Be 'https://contoso.sharepoint.com/sites/hub'
        $cfg.Environments.contoso.Thumbprint | Should -Be 'AB12CD34'
    }
    It 'matches environment names case-insensitively (no duplicate on CONTOSO)' {
        $cfg = ConvertTo-SPEnvironmentsConfig -Config (New-V1Config)
        $cfg = Set-SPEnvironmentInConfig -Config $cfg -Name 'CONTOSO' -Settings @{ Url = 'https://x' }
        @($cfg.Environments.PSObject.Properties.Name) | Should -Be @('contoso')
        $cfg.Environments.contoso.Url | Should -Be 'https://x'
    }
    It 'ignores non-connection keys and empty values, but keeps $false (persistence off)' {
        $cfg = ConvertTo-SPEnvironmentsConfig -Config ([pscustomobject]@{})
        $cfg = Set-SPEnvironmentInConfig -Config $cfg -Name 'E' -Settings @{
            ClientId = 'x'; Rogue = 'nope'; Tenant = ''; PersistLogin = $false
        }
        $cfg.Environments.E.PSObject.Properties['Rogue'] | Should -BeNullOrEmpty
        $cfg.Environments.E.PSObject.Properties['Tenant'] | Should -BeNullOrEmpty
        $cfg.Environments.E.PersistLogin | Should -BeFalse
    }
    It '-MakeActive switches the flat projection to the new environment' {
        $cfg = ConvertTo-SPEnvironmentsConfig -Config (New-V1Config)
        $cfg = Set-SPEnvironmentInConfig -Config $cfg -Name 'Fabrikam' -Settings @{
            ClientId = 'fab-id'; Tenant = 'fabrikam.onmicrosoft.com'; AuthMode = 'Delegated'
        } -MakeActive
        $cfg.ActiveEnvironment | Should -Be 'Fabrikam'
        $cfg.ClientId | Should -Be 'fab-id'
    }
    It 'throws on an invalid environment name' {
        { Set-SPEnvironmentInConfig -Config ([pscustomobject]@{}) -Name '   ' -Settings @{ ClientId = 'x' } } |
            Should -Throw '*empty*'
    }
}

Describe 'Select-SPEnvironmentInConfig (the projection rebuild)' {
    It 'removes stale flat keys when switching from an app-only to a delegated environment' {
        $cfg = ConvertTo-SPEnvironmentsConfig -Config (New-V1Config)   # active: contoso (AppOnly + Thumbprint)
        $cfg = Set-SPEnvironmentInConfig -Config $cfg -Name 'Fabrikam' -Settings @{
            ClientId = 'fab-id'; Tenant = 'fabrikam.onmicrosoft.com'; AuthMode = 'Delegated'; DelegatedFlow = 'Interactive'
        }
        $cfg = Select-SPEnvironmentInConfig -Config $cfg -Name 'Fabrikam'
        $cfg.ActiveEnvironment | Should -Be 'Fabrikam'
        $cfg.AuthMode | Should -Be 'Delegated'
        # THE regression this schema exists to prevent: a merge would have left this behind
        # and every reconnect would still try certificate auth.
        $cfg.PSObject.Properties['Thumbprint'] | Should -BeNullOrEmpty
        # and the contoso environment itself is untouched
        $cfg.Environments.contoso.Thumbprint | Should -Be 'AB12CD34'
    }
    It 'resolves names case-insensitively but stores the canonical key in the pointer' {
        $cfg = ConvertTo-SPEnvironmentsConfig -Config (New-V1Config)
        $cfg = Select-SPEnvironmentInConfig -Config $cfg -Name 'CONTOSO'
        $cfg.ActiveEnvironment | Should -BeExactly 'contoso'
    }
    It 'throws on an unknown environment, listing the known ones' {
        $cfg = ConvertTo-SPEnvironmentsConfig -Config (New-V1Config)
        { Select-SPEnvironmentInConfig -Config $cfg -Name 'nope' } | Should -Throw '*contoso*'
    }
}

Describe 'Remove-SPEnvironmentFromConfig' {
    BeforeEach {
        $script:Two = Set-SPEnvironmentInConfig -Config (ConvertTo-SPEnvironmentsConfig -Config (New-V1Config)) `
            -Name 'Fabrikam' -Settings @{ ClientId = 'fab-id'; Tenant = 'fabrikam.onmicrosoft.com'; AuthMode = 'Delegated' }
    }
    It 'removes a non-active environment and leaves the projection alone' {
        $cfg = Remove-SPEnvironmentFromConfig -Config $script:Two -Name 'Fabrikam'
        @($cfg.Environments.PSObject.Properties.Name) | Should -Be @('contoso')
        $cfg.ActiveEnvironment | Should -Be 'contoso'
        $cfg.ClientId | Should -Be '11111111-2222-3333-4444-555555555555'
    }
    It 'removing the active environment clears the pointer and the flat projection' {
        $cfg = Remove-SPEnvironmentFromConfig -Config $script:Two -Name 'contoso'
        @($cfg.Environments.PSObject.Properties.Name) | Should -Be @('Fabrikam')
        $cfg.PSObject.Properties['ActiveEnvironment'] | Should -BeNullOrEmpty
        $cfg.PSObject.Properties['ClientId'] | Should -BeNullOrEmpty
        $cfg.PSObject.Properties['Thumbprint'] | Should -BeNullOrEmpty
    }
    It 'throws on an unknown environment' {
        { Remove-SPEnvironmentFromConfig -Config $script:Two -Name 'nope' } | Should -Throw '*Unknown environment*'
    }
}

Describe 'Get-SPEnvironmentsFromConfig' {
    It 'lists a v1 flat file as one active environment (in-memory migration)' {
        $rows = @(Get-SPEnvironmentsFromConfig -Config (New-V1Config))
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -Be 'contoso'
        $rows[0].Active | Should -BeTrue
        $rows[0].AuthMode | Should -Be 'AppOnly'
    }
    It 'defaults AuthMode to Delegated and DelegatedFlow to Interactive when unset' {
        $cfg = Set-SPEnvironmentInConfig -Config ([pscustomobject]@{}) -Name 'E' -Settings @{ ClientId = 'x' }
        $row = @(Get-SPEnvironmentsFromConfig -Config $cfg)[0]
        $row.AuthMode | Should -Be 'Delegated'
        $row.DelegatedFlow | Should -Be 'Interactive'
        $row.PersistLogin | Should -BeFalse
    }
    It 'round-trips PersistLogin through JSON as a boolean' {
        $cfg = Set-SPEnvironmentInConfig -Config ([pscustomobject]@{}) -Name 'E' -Settings @{ ClientId = 'x'; PersistLogin = $true }
        $json = $cfg | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        (@(Get-SPEnvironmentsFromConfig -Config $json)[0]).PersistLogin | Should -BeTrue
    }
}

Describe 'Test-SPEnvironmentName' {
    It 'flags empty, over-long, and control-character names; passes normal ones' {
        @(Test-SPEnvironmentName -Name '').Count | Should -BeGreaterThan 0
        @(Test-SPEnvironmentName -Name ('x' * 65)).Count | Should -BeGreaterThan 0
        @(Test-SPEnvironmentName -Name "a`tb").Count | Should -BeGreaterThan 0
        @(Test-SPEnvironmentName -Name 'Contoso (prod)').Count | Should -Be 0
    }
}

Describe 'Set-SPConfig write-through (file I/O)' {
    BeforeEach {
        Mock Get-SPConfigPath { Join-Path $TestDrive 'spconfig.json' }
    }

    It 'creates a v2 file with a synthesized environment on first save' {
        Set-SPConfig -Settings @{ Url = 'https://contoso.sharepoint.com'; ClientId = 'cid'; Tenant = 'contoso.onmicrosoft.com'; AuthMode = 'Delegated' } | Out-Null
        $saved = Get-Content (Join-Path $TestDrive 'spconfig.json') -Raw | ConvertFrom-Json
        $saved.ConfigVersion | Should -Be 2
        $saved.ActiveEnvironment | Should -Be 'contoso'
        $saved.Environments.contoso.ClientId | Should -Be 'cid'
        $saved.ClientId | Should -Be 'cid'   # flat projection kept for old readers
    }
    It 'mirrors a legacy flat save into the active environment (no v2 desync)' {
        Set-SPConfig -Settings @{ Url = 'https://contoso.sharepoint.com'; ClientId = 'cid'; Tenant = 'contoso.onmicrosoft.com' } | Out-Null
        Set-SPConfig -Settings @{ Url = 'https://contoso.sharepoint.com/sites/new' } | Out-Null
        $saved = Get-Content (Join-Path $TestDrive 'spconfig.json') -Raw | ConvertFrom-Json
        $saved.Url | Should -Be 'https://contoso.sharepoint.com/sites/new'
        $saved.Environments.contoso.Url | Should -Be 'https://contoso.sharepoint.com/sites/new'
    }
}
