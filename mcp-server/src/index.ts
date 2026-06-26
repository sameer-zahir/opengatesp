import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { EngineHost } from "./engine.js";

const engine = new EngineHost();

const server = new McpServer({ name: "opengatesp", version: "0.6.0" });

type ToolResult = {
  content: { type: "text"; text: string }[];
  isError?: boolean;
};

function ok(data: unknown): ToolResult {
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

async function run(command: string, params: Record<string, unknown>): Promise<ToolResult> {
  try {
    return ok(await engine.call(command, params));
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { content: [{ type: "text", text: `Error: ${message}` }], isError: true };
  }
}

server.tool(
  "sharepoint_status",
  "Check the OpenGateSP engine and connection status. Does not call SharePoint.",
  {},
  async () => run("ping", {}),
);

server.tool(
  "sharepoint_external_sharing_report",
  "List external/guest users (and optionally sharing links) on a SharePoint site.",
  {
    siteUrl: z.string().url().describe("Site URL, e.g. https://contoso.sharepoint.com/sites/Marketing"),
    includeLinks: z.boolean().optional().describe("Also scan a document library for sharing links (slower)."),
  },
  async ({ siteUrl, includeLinks }) =>
    run("report.sharing", { SiteUrl: siteUrl, IncludeLinks: includeLinks === true }),
);

server.tool(
  "sharepoint_permission_report",
  "Report who has access to a SharePoint site, expanding groups, and where inheritance is broken.",
  {
    siteUrl: z.string().url(),
    includeListPermissions: z.boolean().optional().describe("Also report lists/libraries with unique permissions."),
  },
  async ({ siteUrl, includeListPermissions }) =>
    run("report.permissions", { SiteUrl: siteUrl, IncludeListPermissions: includeListPermissions === true }),
);

server.tool(
  "sharepoint_site_inventory",
  "Tenant-wide inventory of site collections with storage and last activity. Requires SharePoint admin.",
  {},
  async () => run("report.inventory", { IncludeStorage: true }),
);

server.tool(
  "sharepoint_permissions_matrix",
  "Report a site's access as a per-principal matrix (who can touch what, and at what level). Read-only.",
  {
    siteUrl: z.string().url(),
    includeListPermissions: z.boolean().optional().describe("Also include lists/libraries with unique permissions."),
  },
  async ({ siteUrl, includeListPermissions }) =>
    run("report.matrix", { SiteUrl: siteUrl, IncludeListPermissions: includeListPermissions === true }),
);

server.tool(
  "sharepoint_orphaned_users",
  "Report users who still have access to a site but no longer exist in the directory (stale access). Read-only; needs Graph User.Read.All.",
  {
    siteUrl: z.string().url(),
  },
  async ({ siteUrl }) => run("report.orphans", { SiteUrl: siteUrl }),
);

server.tool(
  "sharepoint_set_site_lifecycle",
  "Lock, make read-only (archive), or unlock a site. Requires SharePoint admin. Dry-run by default; execute=true to apply.",
  {
    siteUrl: z.string().url(),
    lockState: z.enum(["Unlock", "ReadOnly", "NoAccess"]).describe("ReadOnly archives; NoAccess fully locks; Unlock restores."),
    execute: z.boolean().optional().describe("false = preview (default); true = apply."),
  },
  async ({ siteUrl, lockState, execute }) => {
    const params: Record<string, unknown> = { SiteUrl: siteUrl, LockState: lockState };
    if (execute === true) params.Force = true;
    else params.WhatIf = true;
    return run("site.lifecycle", params);
  },
);

server.tool(
  "sharepoint_migrate_files",
  "Migrate a local folder into a SharePoint library. Previews (-WhatIf) by default; set execute=true to actually upload.",
  {
    source: z.string().describe("Local folder path, e.g. C:\\Shares\\Marketing"),
    siteUrl: z.string().url(),
    library: z.string().optional().describe("Target library display name (default: Documents)."),
    targetFolder: z.string().optional().describe("Sub-folder within the library."),
    execute: z.boolean().optional().describe("false = preview (default); true = perform the upload."),
  },
  async ({ source, siteUrl, library, targetFolder, execute }) => {
    const params: Record<string, unknown> = {
      Source: source,
      SiteUrl: siteUrl,
      Library: library ?? "Documents",
      PreserveTimestamps: true,
    };
    if (targetFolder) params.TargetFolder = targetFolder;
    if (execute === true) params.Force = true;
    else params.WhatIf = true;
    return run("migrate.files", params);
  },
);

server.tool(
  "sharepoint_precheck_migration",
  "Pre-check a local folder for SharePoint blockers before migrating: illegal/reserved names, blocked file types, over-long projected URLs, oversized and empty files. Local and read-only; no connection needed. Returns issue rows graded Error/Warning.",
  {
    source: z.string().describe("Local folder to scan, e.g. C:\\Shares\\Marketing"),
    siteUrl: z.string().url().optional().describe("Target site URL; when set, path-length checks use the full destination URL."),
    library: z.string().optional().describe("Target library display name (default: Documents)."),
    targetFolder: z.string().optional().describe("Sub-folder within the library."),
    maxPathLength: z.number().int().positive().optional().describe("Projected URL length that triggers a flag (default 400)."),
  },
  async ({ source, siteUrl, library, targetFolder, maxPathLength }) => {
    const params: Record<string, unknown> = { Source: source };
    if (siteUrl) params.SiteUrl = siteUrl;
    if (library) params.Library = library;
    if (targetFolder) params.TargetFolder = targetFolder;
    if (maxPathLength) params.MaxPathLength = maxPathLength;
    return run("precheck.readiness", params);
  },
);

server.tool(
  "sharepoint_copy_site",
  "Copy a SharePoint site's structure (and optionally its content) to another site in the SAME tenant — the open 'copy structure and content'. Previews a dry-run plan by default; set execute=true to perform the copy. Same-tenant only in this release.",
  {
    sourceUrl: z.string().url(),
    destinationUrl: z.string().url(),
    lists: z.array(z.string()).optional().describe("Limit to these list/library display names."),
    includeContent: z.boolean().optional().describe("Also copy items and files (default: structure only)."),
    conflictMode: z.enum(["Replace", "Skip", "KeepBoth", "IfNewer"]).optional().describe("Conflict handling for existing objects (default: IfNewer)."),
    copyPermissions: z.boolean().optional().describe("Also copy role assignments (Phase 2), remapping principals via mappingCsv/domain swap."),
    mappingCsv: z.string().optional().describe("Path to a Source,Destination CSV for principal remapping (used with copyPermissions)."),
    domainFrom: z.string().optional().describe("Source domain for a blanket principal domain swap, e.g. contoso.com."),
    domainTo: z.string().optional().describe("Destination domain for the swap, e.g. fabrikam.com."),
    since: z.string().optional().describe("ISO date/time watermark: only copy items modified at/after it (incremental)."),
    execute: z.boolean().optional().describe("false = dry-run plan (default); true = perform the copy."),
  },
  async ({ sourceUrl, destinationUrl, lists, includeContent, conflictMode, copyPermissions, mappingCsv, domainFrom, domainTo, since, execute }) => {
    const params: Record<string, unknown> = { SourceUrl: sourceUrl, DestinationUrl: destinationUrl };
    if (lists) params.Lists = lists;
    if (includeContent === true) params.IncludeContent = true;
    if (conflictMode) params.ConflictMode = conflictMode;
    if (copyPermissions === true) params.CopyPermissions = true;
    if (mappingCsv) params.MappingCsv = mappingCsv;
    if (domainFrom) params.DomainFrom = domainFrom;
    if (domainTo) params.DomainTo = domainTo;
    if (since) params.Since = since;
    if (execute === true) params.Force = true;
    else params.WhatIf = true;
    return run("copy.site", params);
  },
);

server.tool(
  "sharepoint_copy_permissions",
  "Copy a site's role assignments to another site, remapping users/groups via a Source,Destination mapping CSV and/or a domain swap. Same-tenant or tenant-to-tenant. Previews a dry-run plan by default (and flags unmapped principals); set execute=true to apply.",
  {
    sourceUrl: z.string().url(),
    destinationUrl: z.string().url(),
    mappingCsv: z.string().optional().describe("Path to a CSV with Source,Destination columns (logins/emails)."),
    domainFrom: z.string().optional().describe("Source domain for a blanket swap, e.g. contoso.com."),
    domainTo: z.string().optional().describe("Destination domain for the swap, e.g. fabrikam.com."),
    includeListPermissions: z.boolean().optional().describe("Also copy unique (broken-inheritance) list/library permissions."),
    execute: z.boolean().optional().describe("false = dry-run plan (default); true = apply."),
  },
  async ({ sourceUrl, destinationUrl, mappingCsv, domainFrom, domainTo, includeListPermissions, execute }) => {
    const params: Record<string, unknown> = { SourceUrl: sourceUrl, DestinationUrl: destinationUrl };
    if (mappingCsv) params.MappingCsv = mappingCsv;
    if (domainFrom) params.DomainFrom = domainFrom;
    if (domainTo) params.DomainTo = domainTo;
    if (includeListPermissions === true) params.IncludeListPermissions = true;
    if (execute === true) params.Force = true;
    else params.WhatIf = true;
    return run("copy.permissions", params);
  },
);

server.tool(
  "sharepoint_copy_site_cross_tenant",
  "Copy a site between DIFFERENT tenants (Phase 3): structure via provisioning template, library files by download/upload, optional principal remap. The server opens an app-only connection per tenant, so a certificate thumbprint registered in each tenant is required (headless). Dry-run by default; execute=true to perform the copy.",
  {
    sourceUrl: z.string().url(),
    sourceClientId: z.string().describe("Entra app (client) id registered in the SOURCE tenant."),
    sourceTenant: z.string().describe("Source tenant, e.g. contoso.onmicrosoft.com."),
    sourceThumbprint: z.string().describe("App-only certificate thumbprint in the source tenant's store."),
    destinationUrl: z.string().url(),
    destinationClientId: z.string().describe("Entra app (client) id registered in the DESTINATION tenant."),
    destinationTenant: z.string().describe("Destination tenant, e.g. fabrikam.onmicrosoft.com."),
    destinationThumbprint: z.string().describe("App-only certificate thumbprint in the destination tenant's store."),
    includeContent: z.boolean().optional().describe("Also copy items and files (default: structure only)."),
    copyPermissions: z.boolean().optional().describe("Also copy role assignments, remapping principals."),
    domainFrom: z.string().optional().describe("Source domain for the principal swap, e.g. contoso.com."),
    domainTo: z.string().optional().describe("Destination domain for the swap, e.g. fabrikam.com."),
    execute: z.boolean().optional().describe("false = dry-run plan (default); true = perform the copy."),
  },
  async (a) => {
    const params: Record<string, unknown> = {
      SourceUrl: a.sourceUrl, SourceClientId: a.sourceClientId, SourceTenant: a.sourceTenant, SourceThumbprint: a.sourceThumbprint,
      DestinationUrl: a.destinationUrl, DestinationClientId: a.destinationClientId, DestinationTenant: a.destinationTenant, DestinationThumbprint: a.destinationThumbprint,
    };
    if (a.includeContent === true) params.IncludeContent = true;
    if (a.copyPermissions === true) params.CopyPermissions = true;
    if (a.domainFrom) params.DomainFrom = a.domainFrom;
    if (a.domainTo) params.DomainTo = a.domainTo;
    if (a.execute === true) params.Force = true;
    else params.WhatIf = true;
    return run("copy.site.crosstenant", params);
  },
);

server.tool(
  "sharepoint_copy_m365_group",
  "Create a new Microsoft 365 Group modelled on an existing one (description + owner/member roster). Dry-run by default; execute=true to create. Needs Graph Group.ReadWrite.All.",
  {
    sourceIdentity: z.string().describe("Source group id or display name."),
    displayName: z.string().describe("Display name for the new group."),
    mailNickname: z.string().describe("Mail nickname (alias) for the new group — must be unique."),
    execute: z.boolean().optional().describe("false = dry-run (default); true = create."),
  },
  async ({ sourceIdentity, displayName, mailNickname, execute }) => {
    const params: Record<string, unknown> = { SourceIdentity: sourceIdentity, DisplayName: displayName, MailNickname: mailNickname };
    if (execute === true) params.Force = true;
    else params.WhatIf = true;
    return run("copy.m365group", params);
  },
);

server.tool(
  "sharepoint_copy_team",
  "Create a new Microsoft Teams team modelled on an existing one (channels + owner/member roster; tabs/messages not copied). Dry-run by default; execute=true to create.",
  {
    sourceTeam: z.string().describe("Source team group id or display name."),
    displayName: z.string().describe("Display name for the new team."),
    mailNickname: z.string().describe("Mail nickname (alias) for the new team — must be unique."),
    execute: z.boolean().optional().describe("false = dry-run (default); true = create."),
  },
  async ({ sourceTeam, displayName, mailNickname, execute }) => {
    const params: Record<string, unknown> = { SourceTeam: sourceTeam, DisplayName: displayName, MailNickname: mailNickname };
    if (execute === true) params.Force = true;
    else params.WhatIf = true;
    return run("copy.team", params);
  },
);

server.tool(
  "sharepoint_copy_planner_plan",
  "Recreate a Planner plan (buckets + tasks) on a destination Microsoft 365 Group. Assignments/attachments not copied. Dry-run by default; execute=true to create.",
  {
    sourcePlanId: z.string().describe("Source plan id."),
    destinationGroupId: z.string().describe("Microsoft 365 Group id that will own the new plan."),
    title: z.string().describe("Title for the new plan."),
    execute: z.boolean().optional().describe("false = dry-run (default); true = create."),
  },
  async ({ sourcePlanId, destinationGroupId, title, execute }) => {
    const params: Record<string, unknown> = { SourcePlanId: sourcePlanId, DestinationGroupId: destinationGroupId, Title: title };
    if (execute === true) params.Force = true;
    else params.WhatIf = true;
    return run("copy.planner", params);
  },
);

server.tool(
  "sharepoint_copy_list",
  "Copy a single SharePoint list or library — its schema (columns, content types, views) and optionally its content — to another site in the SAME tenant. The granular form of sharepoint_copy_site. Previews a dry-run plan by default; set execute=true to perform the copy.",
  {
    sourceUrl: z.string().url(),
    destinationUrl: z.string().url(),
    list: z.string().describe("Display name of the list or library to copy."),
    includeContent: z.boolean().optional().describe("Also copy items/files (default: schema only)."),
    conflictMode: z.enum(["Replace", "Skip", "KeepBoth", "IfNewer"]).optional().describe("Conflict handling if the list already exists (default: IfNewer)."),
    execute: z.boolean().optional().describe("false = dry-run plan (default); true = perform the copy."),
  },
  async ({ sourceUrl, destinationUrl, list, includeContent, conflictMode, execute }) => {
    const params: Record<string, unknown> = { SourceUrl: sourceUrl, DestinationUrl: destinationUrl, List: list };
    if (includeContent === true) params.IncludeContent = true;
    if (conflictMode) params.ConflictMode = conflictMode;
    if (execute === true) params.Force = true;
    else params.WhatIf = true;
    return run("copy.list", params);
  },
);

server.tool(
  "sharepoint_provision_site",
  "Create a SharePoint site. Previews (-WhatIf) by default; set execute=true to actually create.",
  {
    title: z.string(),
    type: z.enum(["TeamSite", "CommunicationSite"]).describe("Site type (default: TeamSite)."),
    alias: z.string().optional().describe("Required for TeamSite."),
    url: z.string().optional().describe("Required for CommunicationSite."),
    execute: z.boolean().optional(),
  },
  async ({ title, type, alias, url, execute }) => {
    const params: Record<string, unknown> = { Title: title, Type: type };
    if (alias) params.Alias = alias;
    if (url) params.Url = url;
    if (execute !== true) params.WhatIf = true;
    return run("provision.site", params);
  },
);

server.tool(
  "sharepoint_bulk_metadata",
  "Bulk-update list/library metadata from a CSV. Previews (-WhatIf) by default; set execute=true to apply.",
  {
    siteUrl: z.string().url(),
    list: z.string(),
    csvPath: z.string().describe("Path to a CSV: header = field internal names; one column is the item id."),
    execute: z.boolean().optional(),
  },
  async ({ siteUrl, list, csvPath, execute }) => {
    const params: Record<string, unknown> = { SiteUrl: siteUrl, List: list, CsvPath: csvPath };
    if (execute === true) params.Force = true;
    else params.WhatIf = true;
    return run("bulk.metadata", params);
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
