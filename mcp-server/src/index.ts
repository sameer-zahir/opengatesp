import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { EngineHost } from "./engine.js";

const engine = new EngineHost();

const server = new McpServer({ name: "opengatesp", version: "0.1.0" });

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
