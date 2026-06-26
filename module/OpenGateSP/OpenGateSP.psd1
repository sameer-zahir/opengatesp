@{
    RootModule        = 'OpenGateSP.psm1'
    ModuleVersion     = '0.3.0'
    GUID              = 'a4d9b2e7-6c81-4f3a-9b5e-2f7c1d8e4a60'
    Author            = 'Sameer Zahir'
    CompanyName       = 'Sameer Zahir'
    Copyright         = '(c) 2026 Sameer Zahir. MIT License.'
    Description       = 'OpenGateSP - the free, open-source ShareGate alternative for SharePoint Online: file-share migration, permissions/governance reporting, and provisioning. The PowerShell engine behind the OpenGateSP GUI (and roadmap MCP server). Built on PnP.PowerShell.'
    PowerShellVersion = '7.4'

    # PnP.PowerShell is the SharePoint engine. Installed separately (see docs/01).
    RequiredModules   = @('PnP.PowerShell')

    FunctionsToExport = @(
        'Connect-SPTool',
        'Get-SPSiteInventory',
        'Get-SPPermissionReport',
        'Get-SPSharingReport',
        'Start-SPFileMigration',
        'Test-SPMigrationReadiness',
        'Copy-SPSite',
        'Copy-SPList',
        'Copy-SPPermissions',
        'New-SPSiteFromTemplate',
        'Set-SPBulkMetadata'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('SharePoint', 'SharePointOnline', 'Microsoft365', 'PnP', 'Migration', 'FileShare', 'Governance', 'Permissions', 'ShareGate-alternative', 'migration-tool')
            LicenseUri   = 'https://github.com/sameer-zahir/opengatesp/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/sameer-zahir/opengatesp'
            ReleaseNotes = 'v0.3.0 - Phase 2: Copy-SPPermissions (role-assignment copy with user/group remapping via mapping CSV or domain swap) and incremental copy (-Since watermark) on Copy-SPSite/Copy-SPList. v0.2.0 - Copy-SPSite/Copy-SPList (same-tenant SharePoint site/list copy), Test-SPMigrationReadiness (local pre-migration readiness check), scheduled governance reports, modernized GUI (Copy-site wizard, Fluent default theme + picker). v0.1.0 - initial engine.'
        }
    }
}
