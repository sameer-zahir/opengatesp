function Write-SPLog {
    <#
    .SYNOPSIS
        Internal logging helper. Writes a coloured, timestamped line to the host
        and (optionally) appends it to a log file.
    .NOTES
        $LogPath defaults to $script:OpenGateSPLogPath, which operations such as
        Start-SPFileMigration set so the whole run is captured to a transcript.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [ValidateSet('Info', 'Warn', 'Error', 'Success', 'Debug')]
        [string]$Level = 'Info',

        [string]$LogPath = $script:OpenGateSPLogPath
    )

    $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$($Level.ToUpper())] $Message"

    try {
        switch ($Level) {
            'Warn'    { Write-Host $line -ForegroundColor Yellow }
            'Error'   { Write-Host $line -ForegroundColor Red }
            'Success' { Write-Host $line -ForegroundColor Green }
            'Debug'   { Write-Verbose $line }
            default   { Write-Host $line -ForegroundColor Gray }
        }
    }
    catch {
        # No host attached (e.g. inside the GUI's background runspace) — ignore.
    }

    if ($LogPath) {
        try { Add-Content -LiteralPath $LogPath -Value $line -ErrorAction Stop } catch { }
    }
}
