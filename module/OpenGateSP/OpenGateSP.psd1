@{
    RootModule        = 'OpenGateSP.psm1'
    ModuleVersion     = '0.2.0'
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
            ReleaseNotes = 'v0.2.0 - add Copy-SPSite (same-tenant SharePoint site copy, structure + content, dry-run by default), Test-SPMigrationReadiness (local pre-migration readiness check), and scheduled governance reports; modernized GUI (sidebar nav, card home, Copy-site wizard, Fluent default theme + picker). v0.1.0 - initial engine.'
        }
    }
}
