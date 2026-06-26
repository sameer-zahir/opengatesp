@{
    RootModule        = 'OpenGateSP.psm1'
    ModuleVersion     = '0.5.0'
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
        'Copy-SPTermGroup',
        'Copy-SPM365Group',
        'Copy-SPTeam',
        'Copy-SPPlannerPlan',
        'New-SPMigrationConnection',
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
            ReleaseNotes = 'v0.5.0 - Phase 4 (collaboration): Copy-SPTeam (channels + membership), Copy-SPM365Group, Copy-SPPlannerPlan (buckets + tasks). v0.4.0 - Phase 3 (tenant-to-tenant): New-SPMigrationConnection, Copy-SPSite -CrossTenant, Copy-SPTermGroup. v0.3.0 - Phase 2: Copy-SPPermissions + incremental copy. v0.2.0 - Copy-SPSite/Copy-SPList, Test-SPMigrationReadiness, scheduled reports, modernized GUI. v0.1.0 - initial engine.'
        }
    }
}
