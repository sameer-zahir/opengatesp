# 08 — Teams, Microsoft 365 Groups & Planner (Phase 4)

OpenGateSP can clone the collaboration objects around a site, not just the site itself. All
three functions are **dry-run by default** and need a **Microsoft Graph**-scoped connection
(`Group.ReadWrite.All` plus the relevant Team / Tasks scopes — register the app accordingly,
see [docs/02](02-entra-app-registration.md)).

> **Status:** the membership-delta logic is unit-tested; the live Graph calls are verified
> with a manual test plan against a tenant. Run a `-WhatIf` first, always.

## What it copies

| Function | Copies | Doesn't copy |
|---|---|---|
| `Copy-SPM365Group` | Description, owners, members | — |
| `Copy-SPTeam` | Channels (except the auto-created General), owners, members | Tabs, installed apps, channel messages |
| `Copy-SPPlannerPlan` | Buckets, tasks (title, description, bucket) | Assignments, attachments, checklists |

## Use it

```powershell
# A Microsoft 365 Group with the same roster:
Copy-SPM365Group -SourceIdentity "Marketing" -DisplayName "Marketing (copy)" -MailNickname marketing-copy -WhatIf

# A Team with its channels and members:
Copy-SPTeam -SourceTeam "Project Falcon" -DisplayName "Project Falcon (copy)" -MailNickname falcon-copy -WhatIf

# A Planner plan's buckets and tasks onto a destination group:
Copy-SPPlannerPlan -SourcePlanId <planId> -DestinationGroupId <groupId> -Title "Sprint board (copy)" -WhatIf
```

Drop `-WhatIf` (or add `-Force`) to create. MCP tools: `sharepoint_copy_m365_group`,
`sharepoint_copy_team`, `sharepoint_copy_planner_plan`.

## Notes / limits

- Needs **Graph** permissions on the app registration, beyond SharePoint.
- New groups/teams provision **asynchronously** — a freshly created team can take a minute
  before channels/members can be added; re-run if an add fails the first time.
- Membership is **added, never removed** — these functions create, they don't sync deletions.
- Same-tenant by default; pass `-Connection` (from `New-SPMigrationConnection`) to target a
  specific tenant.
