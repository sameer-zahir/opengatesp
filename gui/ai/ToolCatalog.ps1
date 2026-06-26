#Requires -Version 7.4
# The catalog of OpenGateSP tools exposed to the in-app AI assistant (BYOK). Mirrors the MCP server's
# tool surface (mcp-server/src/index.ts) so the in-app and external-AI experiences match. MVP = the
# read-only reports (safe — no preview/confirm flow needed); write tools come later behind preview-
# gating. Pure data + helpers — unit-tested in tests/AI.Tests.ps1.

function Get-SPAiToolCatalog {
    @(
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
