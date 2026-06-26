#Requires -Version 7.4
<#
.SYNOPSIS
    Seed a throwaway dev tenant with fixtures for OpenGateSP end-to-end testing.
.DESCRIPTION
    Creates a SOURCE site (a library with a nested folder and files, a multi-version file, a
    checked-out file, a larger file, and a list with a Person column + a broken-inheritance list)
    and an empty DEST site — the fixtures docs/TESTING.md exercises. Idempotent: re-running skips
    what already exists. Preview with -WhatIf.

    Run ONLY against a free Microsoft 365 Developer Program tenant. Connect first with an admin
    connection so the sites can be created:

        Connect-SPTool -Url https://contoso-admin.sharepoint.com -ClientId <id> `
            -Tenant contoso.onmicrosoft.com -Admin -SaveConfig

    (Site creation needs the SharePoint Administrator role; saved defaults let the per-site
    connections below reuse the same app registration.)
.PARAMETER BaseUrl
    Tenant root, e.g. https://contoso.sharepoint.com (no trailing path).
.PARAMETER SourceAlias
    URL segment for the source site (default 'ogsp-src').
.PARAMETER DestAlias
    URL segment for the destination site (default 'ogsp-dst').
.PARAMETER ExternalEmail
    Optional external/guest email — when given, a sharing-link fixture is attempted.
.EXAMPLE
    ./Seed-TestTenant.ps1 -BaseUrl https://contoso.sharepoint.com -WhatIf
.EXAMPLE
    ./Seed-TestTenant.ps1 -BaseUrl https://contoso.sharepoint.com
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$BaseUrl,
    [string]$SourceAlias = 'ogsp-src',
    [string]$DestAlias = 'ogsp-dst',
    [string]$ExternalEmail
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\module\OpenGateSP\OpenGateSP.psd1') -Force

$root = $BaseUrl.TrimEnd('/')
$sourceUrl = "$root/sites/$SourceAlias"
$destUrl = "$root/sites/$DestAlias"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'OpenGateSP-seed'
if (-not (Test-Path -LiteralPath $tmp)) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }

function New-SeedFile {
    param([string]$Name, [int]$SizeKB, [string]$Text)
    $path = Join-Path $tmp $Name
    if ($Text) { Set-Content -LiteralPath $path -Value $Text -Encoding utf8 }
    else { [System.IO.File]::WriteAllBytes($path, (New-Object byte[] ($SizeKB * 1024))) }
    $path
}

# --- 1. Sites -------------------------------------------------------------------------------
foreach ($s in @(@{ Url = $sourceUrl; Title = 'OGSP Source'; Alias = $SourceAlias },
        @{ Url = $destUrl; Title = 'OGSP Dest'; Alias = $DestAlias })) {
    $exists = $null
    try { $exists = Get-PnPTenantSite -Identity $s.Url -ErrorAction SilentlyContinue } catch { }
    if ($exists) { Write-Host "Site exists: $($s.Url)" -ForegroundColor DarkGray; continue }
    if ($PSCmdlet.ShouldProcess($s.Url, "Create team site '$($s.Title)'")) {
        New-PnPSite -Type TeamSite -Title $s.Title -Alias $s.Alias -ErrorAction Stop | Out-Null
        Write-Host "Created site: $($s.Url)" -ForegroundColor Green
    }
}

if ($WhatIfPreference) { Write-Host 'WhatIf: skipping content seeding (sites would be created first).' -ForegroundColor Yellow; return }

# --- 2. Source content ----------------------------------------------------------------------
Connect-SPTool -Url $sourceUrl | Out-Null
$lib = 'Shared Documents'

# Nested folder + a few files
if ($PSCmdlet.ShouldProcess("$sourceUrl/$lib", 'Add folder + files')) {
    Resolve-PnPFolder -SiteRelativePath "$lib/Projects" -ErrorAction SilentlyContinue | Out-Null
    Add-PnPFile -Path (New-SeedFile -Name 'readme.txt' -Text 'OpenGateSP test fixture.') -Folder $lib -ErrorAction Stop | Out-Null
    Add-PnPFile -Path (New-SeedFile -Name 'plan.txt' -Text 'Nested file.') -Folder "$lib/Projects" -ErrorAction Stop | Out-Null
    Write-Host 'Added folder + files.' -ForegroundColor Green
}

# Multi-version file: upload three times to build version history
if ($PSCmdlet.ShouldProcess("$lib/versioned.txt", 'Create 3 versions')) {
    1..3 | ForEach-Object {
        Add-PnPFile -Path (New-SeedFile -Name 'versioned.txt' -Text "version $_") -Folder $lib -ErrorAction Stop | Out-Null
    }
    Write-Host 'Created multi-version file.' -ForegroundColor Green
}

# Larger file (a few MB) — test Get-SPLargeFiles with -MinSizeMB 1
if ($PSCmdlet.ShouldProcess("$lib/large.bin", 'Upload larger file')) {
    Add-PnPFile -Path (New-SeedFile -Name 'large.bin' -SizeKB 3072) -Folder $lib -ErrorAction Stop | Out-Null
    Write-Host 'Uploaded larger file (~3 MB).' -ForegroundColor Green
}

# Checked-out file
if ($PSCmdlet.ShouldProcess("$lib/checkedout.txt", 'Upload + check out')) {
    Add-PnPFile -Path (New-SeedFile -Name 'checkedout.txt' -Text 'left checked out') -Folder $lib -ErrorAction Stop | Out-Null
    try { Set-PnPFileCheckedOut -Url "/sites/$SourceAlias/$lib/checkedout.txt" -ErrorAction Stop } catch { Write-Warning "Check-out: $($_.Exception.Message)" }
    Write-Host 'Created checked-out file.' -ForegroundColor Green
}

# List with a Person column + items (fidelity fixture)
if ($PSCmdlet.ShouldProcess('Reviews', 'Create list with a Person column')) {
    $rev = Get-PnPList -Identity 'Reviews' -ErrorAction SilentlyContinue
    if (-not $rev) { New-PnPList -Title 'Reviews' -Template GenericList -ErrorAction Stop | Out-Null }
    if (-not (Get-PnPField -List 'Reviews' -Identity 'Reviewer' -ErrorAction SilentlyContinue)) {
        Add-PnPField -List 'Reviews' -DisplayName 'Reviewer' -InternalName 'Reviewer' -Type User -AddToDefaultView -ErrorAction Stop | Out-Null
    }
    $me = (Get-PnPProperty -ClientObject (Get-PnPWeb) -Property CurrentUser).Email
    Add-PnPListItem -List 'Reviews' -Values @{ Title = 'Review A'; Reviewer = $me } -ErrorAction SilentlyContinue | Out-Null
    Write-Host 'Created Reviews list with a Person column.' -ForegroundColor Green
}

# List with broken inheritance (remediation fixture)
if ($PSCmdlet.ShouldProcess('Restricted', 'Create broken-inheritance list')) {
    $restricted = Get-PnPList -Identity 'Restricted' -ErrorAction SilentlyContinue
    if (-not $restricted) { $restricted = New-PnPList -Title 'Restricted' -Template GenericList -ErrorAction Stop }
    try {
        $restricted.BreakRoleInheritance($true, $false)
        Invoke-PnPQuery
    }
    catch { Write-Warning "Break inheritance: $($_.Exception.Message)" }
    Write-Host 'Created broken-inheritance list.' -ForegroundColor Green
}

# Optional external sharing fixture
if ($ExternalEmail -and $PSCmdlet.ShouldProcess($ExternalEmail, 'Share a file externally')) {
    try {
        Add-PnPFileSharingLink -Identity "/sites/$SourceAlias/$lib/readme.txt" -Type View -Scope Anonymous -ErrorAction Stop | Out-Null
        Write-Host "Created an anonymous sharing link (external fixture)." -ForegroundColor Green
    }
    catch { Write-Warning "External share: $($_.Exception.Message)" }
}

Write-Host ''
Write-Host "Seed complete. Source: $sourceUrl   Dest: $destUrl" -ForegroundColor Cyan
Write-Host 'Next: Invoke-SPExplore -SiteUrl ' -NoNewline; Write-Host $sourceUrl -ForegroundColor Cyan
