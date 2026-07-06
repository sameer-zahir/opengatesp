#Requires -Version 7.4
# The catalog of OpenGateSP tools exposed to the in-app AI assistant (BYOK). Mirrors the MCP server's
# tool surface (mcp-server/src/index.ts) so the in-app and external-AI experiences match. The default
# catalog is the read-only reports; -IncludeWrites (the "Allow write actions" toggle) adds the write
# tools, which always run as a preview (-WhatIf) until the model re-calls them with execute=true after
# an identical preview — see Resolve-SPWriteParams / Get-SPWriteKey and the loop in AiClient.ps1.
# Pure data + helpers — unit-tested in tests/AI.Tests.ps1.

function Get-SPAiToolCatalog {
    param([switch]$IncludeWrites)
    $tools = @(
        @{
            name = 'sharepoint_external_sharing_report'
            description = 'List external/guest users (and optionally sharing links) on a SharePoint site.'
            cmdlet = 'Get-SPSharingReport'; readOnly = $true
            schema = @{ type = 'object'; required = @('siteUrl'); properties = [ordered]@{
                siteUrl      = @{ type = 'string'; description = 'Site URL, e.g. https://contoso.sharepoint.com/sites/Marketing' }
                includeLinks = @{ type = 'boolean'; description = 'Also scan a document library for sharing links (slower).' }
            } }
        }
        @{
            name = 'sharepoint_permission_report'
            description = 'Report who has access to a SharePoint site, expanding groups, and where inheritance is broken.'
            cmdlet = 'Get-SPPermissionReport'; readOnly = $true
            schema = @{ type = 'object'; required = @('siteUrl'); properties = [ordered]@{
                siteUrl                = @{ type = 'string'; description = 'Site URL' }
                includeListPermissions = @{ type = 'boolean'; description = 'Also report lists/libraries with unique permissions.' }
            } }
        }
        @{
            name = 'sharepoint_permissions_matrix'
            description = "Report a site's access as a per-principal matrix (who can touch what, at what level). Read-only."
            cmdlet = 'Get-SPPermissionsMatrix'; readOnly = $true
            schema = @{ type = 'object'; required = @('siteUrl'); properties = [ordered]@{
                siteUrl                = @{ type = 'string'; description = 'Site URL' }
                includeListPermissions = @{ type = 'boolean'; description = 'Also include lists/libraries with unique permissions.' }
            } }
        }
        @{
            name = 'sharepoint_orphaned_users'
            description = 'Report users who still have access to a site but no longer exist in the directory (stale access). Read-only.'
            cmdlet = 'Get-SPOrphanedUsers'; readOnly = $true
            schema = @{ type = 'object'; required = @('siteUrl'); properties = [ordered]@{
                siteUrl = @{ type = 'string'; description = 'Site URL' }
            } }
        }
        @{
            name = 'sharepoint_everyone_claims'
            description = "Find where 'Everyone' or 'Everyone except external users' (EEEU) has access on a site — the biggest oversharing risk. Read-only; grants are graded Error (writable) or Warning."
            cmdlet = 'Find-SPEveryoneClaims'; readOnly = $true
            schema = @{ type = 'object'; required = @('siteUrl'); properties = [ordered]@{
                siteUrl                = @{ type = 'string'; description = 'Site URL' }
                includeListPermissions = @{ type = 'boolean'; description = 'Also scan lists/libraries with unique permissions.' }
            } }
        }
        @{
            name = 'sharepoint_ownerless_groups'
            description = 'Report Microsoft 365 Groups (and their Teams/sites) that have no owner — a governance risk. Read-only; needs Graph Group.Read.All.'
            cmdlet = 'Get-SPOwnerlessGroups'; readOnly = $true
            schema = @{ type = 'object'; required = @(); properties = [ordered]@{} }
        }
        @{
            name = 'sharepoint_governance_review'
            description = 'Consolidated governance review of a site: broad-audience grants (Everyone/EEEU), external sharing, and orphaned access in one severity-graded list. Read-only.'
            cmdlet = 'Invoke-SPGovernanceReview'; readOnly = $true
            schema = @{ type = 'object'; required = @('siteUrl'); properties = [ordered]@{
                siteUrl                = @{ type = 'string'; description = 'Site URL' }
                includeListPermissions = @{ type = 'boolean'; description = 'Also scan lists/libraries with unique permissions.' }
            } }
        }
        @{
            name = 'sharepoint_explore'
            description = 'Explore a SharePoint source site: a read-only pre-migration assessment surfacing blockers and review items (checked-out files, large files, external sharing, orphaned users, 2013 workflows) as one severity-graded list.'
            cmdlet = 'Invoke-SPExplore'; readOnly = $true
            schema = @{ type = 'object'; required = @('siteUrl'); properties = [ordered]@{
                siteUrl         = @{ type = 'string'; description = 'Site URL' }
                largeFileMB     = @{ type = 'integer'; description = 'Flag files at/above this size in MB (default 100).' }
                includeVersions = @{ type = 'boolean'; description = 'Also scan version history (slower).' }
            } }
        }
        @{
            name = 'sharepoint_checked_out_files'
            description = "List files left checked out in a site's document libraries (a migration blocker). Read-only."
            cmdlet = 'Get-SPCheckedOutFiles'; readOnly = $true
            schema = @{ type = 'object'; required = @('siteUrl'); properties = [ordered]@{
                siteUrl = @{ type = 'string'; description = 'Site URL' }
                library = @{ type = 'string'; description = 'Limit to one library (default: all document libraries).' }
            } }
        }
        @{
            name = 'sharepoint_large_files'
            description = "List the largest files in a site's document libraries, at/above a size threshold. Read-only."
            cmdlet = 'Get-SPLargeFiles'; readOnly = $true
            schema = @{ type = 'object'; required = @('siteUrl'); properties = [ordered]@{
                siteUrl   = @{ type = 'string'; description = 'Site URL' }
                minSizeMB = @{ type = 'integer'; description = 'Minimum size in MB (default 100).' }
                library   = @{ type = 'string'; description = 'Limit to one library.' }
            } }
        }
        @{
            name = 'sharepoint_site_inventory'
            description = 'Tenant-wide inventory of site collections with storage and last activity. Requires SharePoint admin. Read-only.'
            cmdlet = 'Get-SPSiteInventory'; readOnly = $true
            fixedParams = @{ IncludeStorage = $true }
            schema = @{ type = 'object'; required = @(); properties = [ordered]@{} }
        }
    )
    if (-not $IncludeWrites) { return $tools }

    # Write tools (the "Allow write actions" toggle). Same names/args as the MCP server. Every one
    # previews by default; execute=true applies — but only after an identical preview ran (enforced
    # in AiClient.ps1, not left to the model's good manners).
    $execProp = @{ type = 'boolean'; description = 'false/omitted = preview only (default, changes nothing); true = apply. Only set true after the user confirmed a preview of this exact call.' }
    $tools + @(
        @{
            name = 'sharepoint_migrate_files'
            description = 'Migrate a local folder into a SharePoint library, preserving structure and timestamps. Previews by default; execute=true uploads.'
            cmdlet = 'Start-SPFileMigration'; readOnly = $false
            fixedParams = @{ PreserveTimestamps = $true; Library = 'Documents' }
            schema = @{ type = 'object'; required = @('source', 'siteUrl'); properties = [ordered]@{
                siteUrl      = @{ type = 'string'; description = 'Destination site URL' }
                source       = @{ type = 'string'; description = 'Local folder path, e.g. C:\Shares\Marketing' }
                library      = @{ type = 'string'; description = 'Target library display name (default: Documents).' }
                targetFolder = @{ type = 'string'; description = 'Sub-folder within the library.' }
                execute      = $execProp
            } }
        }
        @{
            name = 'sharepoint_provision_site'
            description = 'Create a SharePoint site (TeamSite needs an alias; CommunicationSite needs a url). Previews by default; execute=true creates.'
            cmdlet = 'New-SPSiteFromTemplate'; readOnly = $false; noForce = $true
            schema = @{ type = 'object'; required = @('title', 'type'); properties = [ordered]@{
                title   = @{ type = 'string'; description = 'Title for the new site' }
                type    = @{ type = 'string'; enum = @('TeamSite', 'CommunicationSite'); description = 'Site type' }
                alias   = @{ type = 'string'; description = 'Required for TeamSite.' }
                url     = @{ type = 'string'; description = 'Required for CommunicationSite.' }
                execute = $execProp
            } }
        }
        @{
            name = 'sharepoint_bulk_metadata'
            description = 'Bulk-update list/library metadata from a CSV (header row = field internal names; one column is the item id). Previews by default; execute=true applies.'
            cmdlet = 'Set-SPBulkMetadata'; readOnly = $false
            schema = @{ type = 'object'; required = @('siteUrl', 'list', 'csvPath'); properties = [ordered]@{
                siteUrl = @{ type = 'string'; description = 'Site URL' }
                list    = @{ type = 'string'; description = 'List or library display name' }
                csvPath = @{ type = 'string'; description = 'Path to the CSV of updates' }
                execute = $execProp
            } }
        }
        @{
            name = 'sharepoint_check_in_files'
            description = "Bulk check-in files left checked out in a site's document libraries (clears a migration blocker). Previews by default; execute=true checks in."
            cmdlet = 'Invoke-SPCheckIn'; readOnly = $false
            schema = @{ type = 'object'; required = @('siteUrl'); properties = [ordered]@{
                siteUrl = @{ type = 'string'; description = 'Site URL' }
                library = @{ type = 'string'; description = 'Limit to one library (default: all document libraries).' }
                execute = $execProp
            } }
        }
        @{
            name = 'sharepoint_clear_version_history'
            description = "Trim a file's version history, keeping the newest N historical versions (the current version is never touched). Previews by default; execute=true deletes."
            cmdlet = 'Clear-SPVersionHistory'; readOnly = $false
            schema = @{ type = 'object'; required = @('siteUrl', 'fileUrl'); properties = [ordered]@{
                siteUrl = @{ type = 'string'; description = 'Site URL' }
                fileUrl = @{ type = 'string'; description = 'Server-relative file URL, e.g. /sites/Marketing/Shared Documents/big.pptx' }
                keep    = @{ type = 'integer'; description = 'Newest historical versions to retain (default 10).' }
                execute = $execProp
            } }
        }
        @{
            name = 'sharepoint_restore_inheritance'
            description = 'Restore permission inheritance on a list/library (or a single item via itemId) that has broken inheritance. Previews by default; execute=true applies.'
            cmdlet = 'Restore-SPInheritance'; readOnly = $false
            schema = @{ type = 'object'; required = @('siteUrl', 'list'); properties = [ordered]@{
                siteUrl = @{ type = 'string'; description = 'Site URL' }
                list    = @{ type = 'string'; description = 'List or library display name' }
                itemId  = @{ type = 'integer'; description = "Restore a single item's inheritance instead of the whole list." }
                execute = $execProp
            } }
        }
        @{
            name = 'sharepoint_remove_orphaned_users'
            description = 'Remove users who still have site access but no longer exist in the directory (stale-access cleanup). Needs Graph User.Read.All. Previews by default; execute=true removes.'
            cmdlet = 'Remove-SPOrphanedUsers'; readOnly = $false
            schema = @{ type = 'object'; required = @('siteUrl'); properties = [ordered]@{
                siteUrl = @{ type = 'string'; description = 'Site URL' }
                execute = $execProp
            } }
        }
        @{
            name = 'sharepoint_set_site_lifecycle'
            description = 'Lock, make read-only (archive), or unlock a site. Requires SharePoint admin. Previews by default; execute=true applies.'
            cmdlet = 'Set-SPSiteLifecycle'; readOnly = $false
            schema = @{ type = 'object'; required = @('siteUrl', 'lockState'); properties = [ordered]@{
                siteUrl   = @{ type = 'string'; description = 'Site URL' }
                lockState = @{ type = 'string'; enum = @('Unlock', 'ReadOnly', 'NoAccess'); description = 'ReadOnly archives; NoAccess fully locks; Unlock restores.' }
                execute   = $execProp
            } }
        }
    )
}

# Canonical identity of a write call — the tool plus its args minus the safety flags. This is the key
# the preview-first contract tracks: execute=true only takes effect when this exact key has already
# been previewed. Order-insensitive so a re-call with reordered args still matches.
function Get-SPWriteKey {
    param([hashtable]$Tool, [hashtable]$Params)
    $parts = foreach ($k in ($Params.Keys | Where-Object { $_ -notin 'Execute', 'WhatIf', 'Force' } | Sort-Object)) {
        '{0}={1}' -f $k, $Params[$k]
    }
    '{0}|{1}' -f $Tool.name, ($parts -join ';')
}

# Turn a write tool's params into what actually runs: preview (-WhatIf) or apply (-Force to skip the
# console confirm, except cmdlets without -Force — e.g. New-SPSiteFromTemplate, marked noForce).
# Always strips the model-facing Execute arg so it never reaches the cmdlet.
function Resolve-SPWriteParams {
    param([hashtable]$Tool, [hashtable]$Params, [bool]$Apply)
    $p = @{} + $Params
    [void]$p.Remove('Execute')
    if ($Apply) { if (-not $Tool.noForce) { $p['Force'] = $true } }
    else { $p['WhatIf'] = $true }
    $p
}

# Map the model's camelCase tool arguments to the PascalCase cmdlet parameters (the MCP server uses
# the same convention), plus any fixed params. Returns a hashtable ready for splatting.
function ConvertTo-SPCmdletParams {
    param([hashtable]$Tool, $Arguments)
    $p = @{}
    if ($Tool.fixedParams) { foreach ($k in $Tool.fixedParams.Keys) { $p[$k] = $Tool.fixedParams[$k] } }
    if ($Arguments) {
        $pairs = if ($Arguments -is [System.Collections.IDictionary]) { $Arguments.GetEnumerator() } else { $Arguments.PSObject.Properties }
        foreach ($kv in $pairs) {
            $val = $kv.Value
            if ($null -eq $val -or "$val" -eq '') { continue }
            $pascal = $kv.Name.Substring(0, 1).ToUpper() + $kv.Name.Substring(1)
            $p[$pascal] = $val
        }
    }
    $p
}

# Render a cmdlet + param hashtable as a copy-pasteable one-liner ("copy the script it ran").
function Get-SPCommandLine {
    param([string]$Cmdlet, [hashtable]$Params)
    $sb = [System.Text.StringBuilder]::new($Cmdlet)
    foreach ($k in ($Params.Keys | Sort-Object)) {
        $v = $Params[$k]
        if ($v -is [bool]) { if ($v) { [void]$sb.Append(" -$k") } }
        elseif ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) { [void]$sb.Append(" -$k $v") }
        else { [void]$sb.Append((" -$k '{0}'" -f ("$v" -replace "'", "''"))) }
    }
    $sb.ToString()
}
