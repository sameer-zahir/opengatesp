# 14 — Copy identities (Entra tenant-to-tenant)

Create the **people and groups** in a destination tenant before you move their content:
users, guests (by invitation), security groups, and Microsoft 365 groups — with their
owner/member rosters. Cross-tenant identity copy (Entra ID users & groups), built on the same
review-first posture as the rest of the module: every step
until the last is **read-only**, and the last is **dry-run by default**.

Run this **before** a cross-tenant content copy ([docs/07](07-sharepoint-migration.md)):
the identity copy emits the principal map that `Copy-SPPermissions -MappingCsv` consumes,
so permissions land on the right people.

## The pipeline

Four cmdlets, one hand-editable CSV between them:

```
Get-SPIdentityInventory  →  New-SPIdentityMap  →  [you review/edit the CSV]
        →  Test-SPIdentityMap  →  Copy-SPIdentity  →  principal map for Copy-SPPermissions
```

Identity work is tenant-level Graph work, so each side uses its own connection from
`New-SPMigrationConnection` (an Entra app per tenant; a certificate per tenant for headless
runs — see [docs/05](05-app-only-auth.md)). Scopes are listed at the end and in
[docs/02](02-entra-app-registration.md).

```powershell
$src = New-SPMigrationConnection -Url https://contoso.sharepoint.com  -ClientId $contosoApp  -Tenant contoso.onmicrosoft.com  -Thumbprint $srcCert
$dst = New-SPMigrationConnection -Url https://fabrikam.sharepoint.com -ClientId $fabrikamApp -Tenant fabrikam.onmicrosoft.com -Thumbprint $dstCert

# 1. Inventory the SOURCE tenant (read-only).
Get-SPIdentityInventory -Connection $src -Path .\contoso-identities.csv

# 2. Propose a map against the DESTINATION tenant (read-only; nothing created).
New-SPIdentityMap -InventoryCsv .\contoso-identities.csv -DomainTo fabrikam.com `
                  -DestinationConnection $dst -Path .\identity-map.csv

# 3. REVIEW AND EDIT identity-map.csv (see the schema below), then validate it.
Test-SPIdentityMap -MapCsv .\identity-map.csv -DestinationConnection $dst

# 4. Dry-run, then create. Re-validation is built in and fail-closed.
Copy-SPIdentity -MapCsv .\identity-map.csv -InventoryCsv .\contoso-identities.csv `
                -DestinationConnection $dst -PrincipalMapPath .\principal-map.csv -WhatIf
Copy-SPIdentity -MapCsv .\identity-map.csv -InventoryCsv .\contoso-identities.csv `
                -DestinationConnection $dst -PrincipalMapPath .\principal-map.csv -Force

# 5. Feed the emitted principal map into the content/permission copy (docs/07).
Copy-SPPermissions -SourceUrl .../sites/A -DestinationUrl .../sites/B -MappingCsv .\principal-map.csv -WhatIf
```

## The map CSV — the review contract

`New-SPIdentityMap` writes one row per identity. **It is meant to be hand-edited** — change
Actions, fix target UPNs — before `Test-SPIdentityMap` / `Copy-SPIdentity` consume it:

| Column | Meaning |
|---|---|
| `Type` | `User`, `Guest`, `SecurityGroup`, `M365Group`, `DistributionList`, `MailEnabledSecurityGroup` |
| `SourceId` / `SourceUpn` / `SourceDisplayName` / `SourceMail` | The source identity (don't edit) |
| `UsageLocation` | Copied to created users; required later for licensing |
| `TargetUpn` | The UPN to create, or the matched existing user's UPN |
| `TargetMailNickname` | Mail alias for created groups (and users) |
| `Action` | **`Create`** \| **`Map`** (use an existing destination identity) \| **`Invite`** (guests) \| **`Skip`** |
| `MatchedExistingId` | Destination object id backing an `Action=Map` row |
| `Notes` | Why the proposal is what it is |

How the proposal is made: users match an existing destination identity **by mail first**
(survives UPN renames), then by **UPN local part**; groups match by **mail nickname**, then
**display name**. Matches become `Map`; unmatched users become `Create` with
`local-part@DomainTo`; guests default to `Skip` (re-run with `-IncludeGuests` for `Invite`);
group types Graph cannot create become `Skip`.

`Test-SPIdentityMap` then checks the edited map against the destination — UPN collisions
(in the directory *and* within the CSV), unverified UPN domains, mail-nickname collisions,
vanished `Map` targets, guests without a mail address, missing `UsageLocation` (warning) —
and emits one `OK | Warning | Error` finding per row, errors first. **`Copy-SPIdentity`
re-runs this validation itself and refuses to start while any row is an Error** (override
with `-SkipValidation` at your own risk).

## What is created, and in what order

`Copy-SPIdentity` creates in dependency order — **users and guests, then security groups,
then Microsoft 365 groups** — and runs the roster pass last, so memberships always have
their principals. With `-InventoryCsv` it re-adds each group's owners/members (remapped
through the map); only **missing** members are added, so **re-runs converge** instead of
duplicating.

- **Users** — created **disabled** with a cryptographically random throwaway password
  (never shown or stored, force-change at first sign-in). `-EnableAccounts` opts into
  creating them enabled.
- **Guests** — invited via the Graph invitation API, **silently by default**;
  `-SendInvitations` sends the standard invitation email.
- **Security groups / M365 groups** — created with the source display name and the target
  mail nickname (M365 groups arrive `Private`).
- `-PrincipalMapPath` writes the `Source,Destination` CSV for
  `Copy-SPPermissions -MappingCsv`: **users by UPN, groups by object id**.

## Handover — what never migrates, by design

**Passwords, MFA registrations, and licenses do not migrate.** No API exposes them, and no
migration should pretend otherwise. The intended cutover:

1. Run `Copy-SPIdentity` (users arrive disabled).
2. Assign licenses in the destination tenant (set `UsageLocation` first — the validator
   warns where it's missing).
3. Issue **Temporary Access Passes** (or equivalent) so people can register MFA fresh.
4. Enable the accounts.

`Copy-SPIdentity` prints this handover reminder whenever it creates users disabled.

## Limits

- **Distribution lists and mail-enabled security groups** are inventoried but can't be
  created (Graph limitation — they're Exchange objects). Recreate them in Exchange admin or
  convert them to M365 Groups; the inventory marks them `Supported=False`.
- **Rosters are direct user members only** — nested groups aren't expanded, and members
  that were skipped (e.g. guests without `-IncludeGuests`) are reported as *unmapped*, not
  silently dropped.
- Group settings beyond the basics (dynamic membership rules, group photos, Teams behind
  M365 groups) don't come along — pair with `Copy-SPTeam` ([docs/08](08-teams-groups-planner.md))
  for Teams structure.

## Graph scopes

| Side | Scopes | Used for |
|---|---|---|
| **Source** (read) | `User.Read.All`, `Group.Read.All` (or `Directory.Read.All`) | Inventory users, groups, rosters |
| **Destination** (read) | `User.Read.All`, `Group.Read.All`, `Organization.Read.All` | Matching, collision checks, verified domains |
| **Destination** (write) | `User.ReadWrite.All`, `Group.ReadWrite.All`, `User.Invite.All` (guests) | `Copy-SPIdentity` only |

Grant the write scopes only to the **destination** tenant's app — the source app never
needs them. See [docs/02](02-entra-app-registration.md).

## MCP tools

The same pipeline is exposed over MCP (each step opens its own app-only connection, so pass
the tenant/clientId/thumbprint for the side it touches):

| Tool | Step |
|---|---|
| `sharepoint_identity_inventory` | 1 — inventory the source tenant (read-only) |
| `sharepoint_identity_map` | 2 — propose the map (read-only) |
| `sharepoint_identity_validate` | 3 — validate the edited map (read-only) |
| `sharepoint_identity_copy` | 4 — create (dry-run by default; `execute=true` after a preview) |

`sharepoint_identity_copy` sits behind the server-side preview-first gate like every other
write tool. **No GUI** — identity copy is deliberately CLI/MCP-only, like all cross-tenant
operations.
