@{
    RootModule        = 'OpenGateSP.psm1'
    ModuleVersion     = '0.14.0'
    GUID              = 'a4d9b2e7-6c81-4f3a-9b5e-2f7c1d8e4a60'
    Author            = 'Sameer Zahir'
    CompanyName       = 'Sameer Zahir'
    Copyright         = '(c) 2026 Sameer Zahir. MIT License.'
    Description       = 'OpenGateSP - a free, open-source SharePoint Online migration and governance toolkit (an independent alternative to ShareGate): file-share migration, permissions/governance reporting, and provisioning. The PowerShell engine behind the OpenGateSP GUI (and roadmap MCP server). Built on PnP.PowerShell. Independent project - not affiliated with or endorsed by Workleap; ShareGate is a trademark of Workleap.'
    PowerShellVersion = '7.4'

    # PnP.PowerShell is the SharePoint engine. Installed separately (see docs/01).
    # 2.12.0 floor: -PersistLogin / Disconnect-PnPOnline -ClearPersistedLogin shipped there
    # (the same 2024-09-09 release that made your own ClientId mandatory).
    RequiredModules   = @(@{ ModuleName = 'PnP.PowerShell'; ModuleVersion = '2.12.0' })

    FunctionsToExport = @(
        'Connect-SPTool',
        'Get-SPSiteInventory',
        'Get-SPPermissionReport',
        'Get-SPSharingReport',
        'Get-SPPermissionsMatrix',
        'Get-SPOrphanedUsers',
        'Find-SPEveryoneClaims',
        'Get-SPOwnerlessGroups',
        'Invoke-SPGovernanceReview',
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
        'Set-SPBulkMetadata',
        'Get-SPIdentityInventory',
        'New-SPIdentityMap',
        'Test-SPIdentityMap',
        'Copy-SPIdentity',
        'Get-SPEnvironment',
        'Remove-SPEnvironment',
        'Disconnect-SPTool'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('SharePoint', 'SharePointOnline', 'Microsoft365', 'PnP', 'Migration', 'FileShare', 'Governance', 'Permissions', 'ShareGate-alternative', 'migration-tool')
            LicenseUri   = 'https://github.com/sameer-zahir/opengatesp/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/sameer-zahir/opengatesp'
            ReleaseNotes = 'v0.14.0 - Copy identities (Entra tenant-to-tenant): Get-SPIdentityInventory -> New-SPIdentityMap (hand-editable review CSV) -> Test-SPIdentityMap (fail-closed validation) -> Copy-SPIdentity (dry-run default; users created DISABLED with throwaway passwords - passwords/MFA/licenses never migrate; guests by invitation; convergent group-roster sync; emits a principal map for Copy-SPPermissions); four MCP tools behind the preview-first gate. Named environments: save each tenant as a profile, switch with Connect-SPTool -Environment, list/remove with Get-/Remove-SPEnvironment, sign out with Disconnect-SPTool; the GUI Connect view becomes a saved-environments manager. Sign-in upgrades: -OSLogin (Windows Hello/WAM broker with automatic browser fallback), opt-in -PersistLogin (stay signed in across restarts), the device-code prompt now surfaces in a GUI dialog, and saved delegated flavors are reused on reconnect (device-code users were silently switched to browser). Migration correctness wave: batch item failures no longer report as copied; cross-site metadata restore passes -TargetConnection (was a silent no-op); -Since normalized to UTC and honored for library files; hidden files included and reparse points reported instead of followed; throttling retries honor Retry-After and detect by HTTP status (localized-proof); version-history copy degrades loudly instead of silently. BREAKING: requires PnP.PowerShell 2.12.0 or later. v0.12.0 - AI writes now require a click: every write preview card has an Apply button and only that click approves the change (approvals are single-use and expire after one turn; a chat reply alone never applies). MCP writes are preview-gated server-side: execute=true is honored only after the identical call was previewed in the same session. Write-cmdlet guardrails: -Force no longer bypasses -WhatIf anywhere; orphaned-user detection fails closed on an empty directory snapshot and never flags app/ACS/system principals. README rewritten for non-technical users with fresh screenshots. v0.11.1 - Security hardening for AI write actions (execute is reply-gated after a preview; tool arguments are schema-filtered so force/confirm/whatIf cannot bypass the dry-run guard); SECURITY.md with private vulnerability reporting; installer fix: silent/unattended installs (winget) no longer show the PowerShell 7 advisory dialog. v0.11.0 - BYOK in-app AI assistant (Claude / OpenAI / Ollama / LM Studio; key encrypted on-device with DPAPI; read-only reports plus preview-first write actions behind an opt-in toggle). governance detection: Find-SPEveryoneClaims (Everyone/EEEU oversharing), Get-SPOwnerlessGroups, Invoke-SPGovernanceReview (consolidated severity-graded review). Dashboard Home with live KPI tiles and activity that persists across restarts; the two Copy UIs converged into one guided wizard; screen-reader names on icon controls. MCP: sharepoint_copy_term_group (cross-tenant managed-metadata copy). v0.10.0 - polished, human GUI (nav icons, Settings cog, first-run onboarding, toasts, keyboard shortcuts, focus ring) + seamless-install groundwork (installer PowerShell-7 offer, in-app update check, CI release + winget). No engine cmdlet changes. v0.9.0 - GUI redesign: lifecycle-grouped nav (Migration/Activity/Governance) + a guided Copy chooser & breadcrumb wizard (preview-before-write); docs/design-system.md. No engine cmdlet changes. v0.8.0 - remediation quick-actions (check-in, trim versions, restore inheritance, clean orphans) + migration fidelity (version history, Person/Managed-Metadata columns). v0.7.0 - Explore source assessment + discovery reports (checked-out/large/version-bloat/inactive/workflows) + Compare-SPSite validation. v0.6.0 - Phase 5 (governance): Get-SPPermissionsMatrix (who-can-touch-what), Get-SPOrphanedUsers (stale access), Set-SPSiteLifecycle (lock/archive). v0.5.0 - Phase 4: Copy-SPTeam/Copy-SPM365Group/Copy-SPPlannerPlan. v0.4.0 - Phase 3: tenant-to-tenant. v0.3.0 - Phase 2: permissions + incremental. v0.2.0 - same-tenant site/list copy, readiness check, scheduled reports, modernized GUI. v0.1.0 - initial engine.'
        }
    }
}
