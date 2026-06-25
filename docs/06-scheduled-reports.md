# 06 — Scheduled reports

Drop a sharing or permission report to disk on a schedule, unattended. This pairs the
governance reports with **app-only certificate auth** ([05 — App-only auth](05-app-only-auth.md))
so the task runs with no sign-in.

There are three pieces, all under `scripts/scheduled/`:

| Script | Job |
|---|---|
| `Run-GovernanceReport.ps1` | Connects and writes timestamped CSV report(s) for a site. Headless. |
| `Register-GovernanceReportTask.ps1` | Registers a daily/weekly Windows scheduled task that runs the above. |
| `Get-SPScheduledCommand.ps1` | Builds the exact `pwsh` command line (used by the GUI's **Scheduled** view and the registrar). |

## 1. One-time setup: app-only auth

Follow [05 — App-only auth](05-app-only-auth.md) to register a certificate and note your
**thumbprint**, **client ID**, and **tenant**. A scheduled task can't answer an interactive
sign-in, so app-only is the supported path for unattended runs.

## 2. Run it once by hand

```powershell
./scripts/scheduled/Run-GovernanceReport.ps1 `
    -SiteUrl https://contoso.sharepoint.com/sites/Marketing `
    -OutDir C:\OpenGateSP\reports `
    -Reports Sharing,Permissions `
    -Thumbprint <cert-thumbprint> -ClientId <app-id> -Tenant contoso.onmicrosoft.com
```

It writes `sharing-<timestamp>.csv` and/or `permissions-<timestamp>.csv` into `-OutDir`.
Omit the app-only flags to use a saved interactive connection instead (handy for testing).

## 3. Schedule it (Windows)

```powershell
# Preview the task without registering anything:
./scripts/scheduled/Register-GovernanceReportTask.ps1 `
    -SiteUrl https://contoso.sharepoint.com/sites/Marketing `
    -OutDir C:\OpenGateSP\reports -Reports Sharing,Permissions `
    -Frequency Weekly -At 06:30 `
    -Thumbprint <cert-thumbprint> -ClientId <app-id> -Tenant contoso.onmicrosoft.com -WhatIf

# Drop -WhatIf to register it. Runs as the current user; no admin needed for a user task.
```

`-Frequency` is `Daily` or `Weekly` (weekly runs Mondays). `-At` is a 24-hour time like `06:30`.
The task name defaults to **"OpenGateSP Governance Report"** — change it with `-TaskName` if you
schedule more than one.

## From the GUI

The **Scheduled** view does the same thing: fill in the site, reports, output folder, frequency,
time, and certificate thumbprint, click **Build command** to see exactly what will run, then
**Create task**.

## Linux / macOS (cron)

There's no Windows Task Scheduler off Windows, so schedule `Run-GovernanceReport.ps1` with cron.
The engine and reports are cross-platform (only the WPF GUI is Windows-only):

```cron
# 06:30 every Monday
30 6 * * 1 pwsh -NoProfile -File /opt/opengatesp/scripts/scheduled/Run-GovernanceReport.ps1 -SiteUrl https://contoso.sharepoint.com/sites/Marketing -OutDir /var/opengatesp/reports -Reports Sharing,Permissions -Thumbprint <thumb> -ClientId <app-id> -Tenant contoso.onmicrosoft.com
```

## Notes

- Reports are plain CSV — point `-OutDir` at a synced library or a path your SIEM/Excel picks up.
- The run is read-only; it never writes to SharePoint.
- Throttling is handled by the engine's built-in retry/back-off.
