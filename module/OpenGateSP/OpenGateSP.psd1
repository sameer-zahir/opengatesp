@{
    RootModule        = 'OpenGateSP.psm1'
    ModuleVersion     = '0.10.0'
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
        'Get-SPPermissionsMatrix',
        'Get-SPOrphanedUsers',
        'Set-SPSiteLifecycle',
        'Invoke-SPExplore',
        'Get-SPCheckedOutFiles',
        'Get-SPLargeFiles',
        'Get-SPVersionHistoryReport',
        'Get-SPInactiveSites',
        'Get-SPWorkflowReport',
        'Get-SPContentInsights',
        'Invoke-SPCheckIn',
        'Clear-SPVersionHistory',
        'Restore-SPInheritance',
        'Remove-SPOrphanedUsers',
        'Start-SPFileMigration',
        'Test-SPMigrationReadiness',
        'Copy-SPSite',
        'Copy-SPList',
        'Compare-SPSite',
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
            ReleaseNotes = 'v0.10.0 - polished, human GUI (nav icons, Settings cog, first-run onboarding, toasts, keyboard shortcuts, focus ring) + seamless-install groundwork (installer PowerShell-7 offer, in-app update check, CI release + winget). No engine cmdlet changes. v0.9.0 - GUI redesign: ShareGate-aligned nav (Migration/Activity/Governance) + a guided Copy chooser & breadcrumb wizard (preview-before-write); docs/design-system.md. No engine cmdlet changes. v0.8.0 - remediation quick-actions (check-in, trim versions, restore inheritance, clean orphans) + migration fidelity (version history, Person/Managed-Metadata columns). v0.7.0 - Explore source assessment + discovery reports (checked-out/large/version-bloat/inactive/workflows) + Compare-SPSite validation. v0.6.0 - Phase 5 (governance): Get-SPPermissionsMatrix (who-can-touch-what), Get-SPOrphanedUsers (stale access), Set-SPSiteLifecycle (lock/archive). v0.5.0 - Phase 4: Copy-SPTeam/Copy-SPM365Group/Copy-SPPlannerPlan. v0.4.0 - Phase 3: tenant-to-tenant. v0.3.0 - Phase 2: permissions + incremental. v0.2.0 - same-tenant site/list copy, readiness check, scheduled reports, modernized GUI. v0.1.0 - initial engine.'
        }
    }
}
