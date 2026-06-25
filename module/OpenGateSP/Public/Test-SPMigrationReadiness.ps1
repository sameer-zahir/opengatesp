function Test-SPMigrationReadiness {
    <#
    .SYNOPSIS
        Pre-flight a local folder before a SharePoint migration: flag the names,
        paths, and files that SharePoint Online will reject or skip.
    .DESCRIPTION
        Scans $Source recursively (no connection needed — this is a local, read-only
        check) and returns one row per problem it finds, so you can fix the source
        before you migrate instead of discovering failures half-way through.

        It checks for: illegal characters and reserved names, names with leading/
        trailing spaces or a trailing dot, temp/excluded file types, files that would
        blow past SharePoint's URL-length limit once uploaded, oversized files, and
        empty files. Each row is graded Error (would fail) or Warning (would be
        skipped or may misbehave).

        This is the engine behind the GUI's "Pre-check" view and mirrors the pre-check
        step a commercial tool runs before a copy.
    .PARAMETER Source
        Local folder to scan (e.g. C:\Shares\Marketing or a UNC path).
    .PARAMETER SiteUrl
        Optional target site URL. When given, the projected destination URL is the
        full https URL, so the length check matches SharePoint's real 400-char limit.
        Without it, only the library-relative path length is measured.
    .PARAMETER Library
        Target document library name, used to project the destination URL. Default "Documents".
    .PARAMETER TargetFolder
        Optional sub-folder within the library, used to project the destination URL.
    .PARAMETER MaxPathLength
        Maximum projected URL length before a file is flagged. Default 400 (SharePoint's limit).
    .PARAMETER MaxFileSizeMB
        Files at or above this size are flagged as Error. Default 256000 (250 GB, SharePoint's per-file limit).
    .PARAMETER BlockedExtension
        File extensions to flag as Warning (migration skips them). Default .tmp, .ds_store, .lnk, .lock.
    .PARAMETER AsJson
        Emit the issue rows as a JSON array instead of objects.
    .EXAMPLE
        Test-SPMigrationReadiness -Source C:\Shares\Marketing
    .EXAMPLE
        Test-SPMigrationReadiness -Source C:\Shares\Marketing -SiteUrl https://contoso.sharepoint.com/sites/Mktg -Library Documents
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Source,
        [string]$SiteUrl,
        [string]$Library = 'Documents',
        [string]$TargetFolder = '',
        [int]$MaxPathLength = 400,
        [long]$MaxFileSizeMB = 256000,
        [string[]]$BlockedExtension = @('.tmp', '.ds_store', '.lnk', '.lock'),
        [switch]$AsJson
    )

    if (-not (Test-Path -LiteralPath $Source)) { throw "Source not found: $Source" }
    $sourceItem = Get-Item -LiteralPath $Source -Force
    if (-not $sourceItem.PSIsContainer) { throw "Source must be a folder: $Source" }
    $sourceFull = $sourceItem.FullName

    # SharePoint's hard-invalid name characters, plus device names reserved by Windows/SharePoint.
    $illegalChars  = [char[]]'"*:<>?/\|'
    $reservedNames = @('CON', 'PRN', 'AUX', 'NUL') +
        (0..9 | ForEach-Object { "COM$_" }) +
        (0..9 | ForEach-Object { "LPT$_" })

    # Project a source item onto its destination URL so we can measure the real length.
    $base = if ($SiteUrl) { $SiteUrl.TrimEnd('/') } else { '' }
    $libPart = (@($base, $Library, $TargetFolder) | Where-Object { $_ }) -join '/'

    $results = [System.Collections.Generic.List[object]]::new()
    $scanned = 0

    # Scriptblock (not a nested function) so PSScriptAnalyzer's verb rules don't apply.
    $newIssue = {
        param($Path, $ItemType, $Issue, $Severity, $Detail)
        [pscustomobject]@{ Path = $Path; ItemType = $ItemType; Issue = $Issue; Severity = $Severity; Detail = $Detail }
    }

    $items = @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue)
    foreach ($item in $items) {
        $scanned++
        $name     = $item.Name
        $itemType = if ($item.PSIsContainer) { 'Folder' } else { 'File' }
        $rel      = $item.FullName.Substring($sourceFull.Length).TrimStart('\', '/').Replace('\', '/')

        # --- name checks (apply to files and folders) ---
        $bad = ($name.ToCharArray() | Where-Object { $illegalChars -contains $_ }) | Select-Object -Unique
        if ($bad) {
            $results.Add((& $newIssue $rel $itemType 'Illegal characters' 'Error' ("Remove: $($bad -join ' ')")))
        }
        if ($name -match '[#%]') {
            $results.Add((& $newIssue $rel $itemType 'Discouraged characters' 'Warning' 'Contains # or % — can break links; rename if possible.'))
        }
        if ($name -ne $name.Trim()) {
            $results.Add((& $newIssue $rel $itemType 'Leading/trailing space' 'Warning' 'SharePoint trims or rejects edge whitespace in names.'))
        }
        if ($name.EndsWith('.')) {
            $results.Add((& $newIssue $rel $itemType 'Trailing period' 'Warning' 'Names ending in "." are rejected by SharePoint.'))
        }
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)
        if ($reservedNames -contains $baseName.ToUpperInvariant()) {
            $results.Add((& $newIssue $rel $itemType 'Reserved name' 'Error' "'$baseName' is a reserved device name."))
        }
        if ($name -like '_vti_*' -or $rel -match '(^|/)_vti_') {
            $results.Add((& $newIssue $rel $itemType 'Reserved prefix' 'Error' '"_vti_" is reserved by SharePoint.'))
        }
        if ($name.StartsWith('~$') -or $name -ieq 'desktop.ini') {
            $results.Add((& $newIssue $rel $itemType 'Temp/system file' 'Warning' 'Temp or system file — usually safe to leave behind.'))
        }
        if ($name.Length -gt 255) {
            $results.Add((& $newIssue $rel $itemType 'Name too long' 'Warning' "Name is $($name.Length) chars; keep under 255."))
        }

        # --- file-only checks ---
        if (-not $item.PSIsContainer) {
            $ext = $item.Extension.ToLowerInvariant()
            if ($BlockedExtension -contains $ext) {
                $results.Add((& $newIssue $rel 'File' 'Excluded type' 'Warning' "$ext files are skipped by migration."))
            }

            $projected = (@($libPart, $rel) | Where-Object { $_ }) -join '/'
            $len = $projected.Length
            if ($len -gt $MaxPathLength) {
                $results.Add((& $newIssue $rel 'File' 'Path too long' 'Error' "Projected URL is $len chars (limit $MaxPathLength)."))
            }
            elseif ($len -ge [int]($MaxPathLength * 0.9)) {
                $results.Add((& $newIssue $rel 'File' 'Path near limit' 'Warning' "Projected URL is $len chars (limit $MaxPathLength)."))
            }

            $sizeMB = [math]::Round($item.Length / 1MB, 1)
            if ($item.Length -ge ($MaxFileSizeMB * 1MB)) {
                $results.Add((& $newIssue $rel 'File' 'File too large' 'Error' "$sizeMB MB exceeds the $MaxFileSizeMB MB limit."))
            }
            if ($item.Length -eq 0) {
                $results.Add((& $newIssue $rel 'File' 'Empty file' 'Warning' '0 bytes — may be skipped by migration.'))
            }
        }
    }

    $errors   = @($results | Where-Object Severity -eq 'Error').Count
    $warnings = @($results | Where-Object Severity -eq 'Warning').Count
    $level    = if ($errors) { 'Error' } elseif ($warnings) { 'Warn' } else { 'Success' }
    Write-SPLog ("Pre-check: scanned {0} item(s) under '{1}' — {2} error(s), {3} warning(s)." -f $scanned, $Source, $errors, $warnings) -Level $level

    # Errors first, then warnings, each by path — most actionable at the top.
    $sorted = $results | Sort-Object @{ Expression = { $_.Severity -eq 'Warning' } }, Path
    $sorted | ConvertTo-SPOutput -AsJson:$AsJson
}
