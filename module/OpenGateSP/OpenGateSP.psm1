# OpenGateSP module loader
# Dot-sources every Private (internal) and Public (exported) function file,
# then exports only the Public functions. Adding a new operation is just
# dropping a .ps1 into Public/ and listing it in FunctionsToExport (psd1).

# --- module-level state ---
$script:OpenGateSPLogPath = $null   # set by operations that write a transcript/log file

# --- load function files ---
$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "OpenGateSP: failed to import $($file.FullName): $_"
    }
}

# Export public functions by file base name (manifest FunctionsToExport is the
# authoritative allow-list; this keeps the two in sync when loaded directly).
Export-ModuleMember -Function $public.BaseName
