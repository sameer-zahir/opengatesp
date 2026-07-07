# Named environments (saved tenant connection profiles) — pure helpers.
#
# spconfig.json schema v2: a top-level `Environments` map keyed by display name plus an
# `ActiveEnvironment` pointer, while the ORIGINAL FLAT KEYS remain as a projection of the
# active environment — so every existing reader (Get-SPConnectParams, the GUI prefill,
# Resolve-SPSiteConnection) keeps working unchanged. v1 flat files migrate lazily and
# in-memory; the v2 shape is only persisted on the first write.
#
# Every function here is PURE (config object in → new config object out, no file I/O) so the
# whole schema is unit-testable without touching the profile. File I/O lives in SPConfig.ps1.

# The keys that describe a connection. These live inside each environment and are mirrored
# into the flat projection; everything else in the config file is left alone.
function Get-SPConnectionKey {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    @('Url', 'ClientId', 'Tenant', 'AuthMode', 'DelegatedFlow', 'PersistLogin', 'Thumbprint', 'CertificatePath')
}

# Deep-clone a config object via a JSON round-trip so callers' inputs are never mutated.
# Configs are JSON-shaped by definition (they live in spconfig.json), so this is lossless.
function ConvertTo-SPConfigClone {
    [CmdletBinding()]
    param($Config)
    if ($null -eq $Config) { return [pscustomobject]@{} }
    $json = $Config | ConvertTo-Json -Depth 6
    if (-not $json) { return [pscustomobject]@{} }
    $json | ConvertFrom-Json
}

# Case-insensitive environment-name lookup; returns the canonical (stored) key or $null.
function Resolve-SPEnvironmentKey {
    [CmdletBinding()]
    param($Environments, [string]$Name)
    if ($null -eq $Environments) { return $null }
    @($Environments.PSObject.Properties.Name) | Where-Object { $_ -ieq $Name } | Select-Object -First 1
}

function Test-SPEnvironmentName {
    <#
    .SYNOPSIS
        Validate an environment name. Returns an array of problem strings (empty = valid).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([string]$Name)
    $problems = [System.Collections.Generic.List[string]]::new()
    if (-not "$Name".Trim()) { $problems.Add('Environment name is empty.') }
    elseif ($Name.Length -gt 64) { $problems.Add('Environment name is longer than 64 characters.') }
    if ($Name -match '[\x00-\x1f]') { $problems.Add('Environment name contains control characters.') }
    @($problems)
}

function ConvertTo-SPEnvironmentsConfig {
    <#
    .SYNOPSIS
        Migrate a config object to schema v2 (Environments map + ActiveEnvironment pointer).
        Idempotent: a v2 config comes back as-is (cloned); a v1 flat config gains one
        environment synthesized from its flat keys, named after the tenant's first label.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][object]$Config)

    $cfg = ConvertTo-SPConfigClone $Config
    if ($cfg.PSObject.Properties['Environments']) { return $cfg }

    $envs = [pscustomobject]@{}
    $active = $null
    if ("$($cfg.ClientId)") {
        $active = if ("$($cfg.Tenant)") { ("$($cfg.Tenant)" -split '\.')[0] } else { 'Default' }
        $env = [ordered]@{}
        foreach ($k in (Get-SPConnectionKey)) {
            $prop = $cfg.PSObject.Properties[$k]
            if ($prop -and $null -ne $prop.Value -and "$($prop.Value)" -ne '') { $env[$k] = $prop.Value }
        }
        $envs | Add-Member -NotePropertyName $active -NotePropertyValue ([pscustomobject]$env)
    }

    $cfg | Add-Member -NotePropertyName ConfigVersion -NotePropertyValue 2 -Force
    $cfg | Add-Member -NotePropertyName Environments -NotePropertyValue $envs -Force
    if ($active) { $cfg | Add-Member -NotePropertyName ActiveEnvironment -NotePropertyValue $active -Force }
    $cfg
}

function Select-SPEnvironmentInConfig {
    <#
    .SYNOPSIS
        Make the named environment active: set the pointer and REBUILD the flat projection
        wholesale (every connection key removed, then re-copied from the environment).
    .DESCRIPTION
        The wholesale rebuild is the point: a merge could never REMOVE a stale key, and
        switching from an app-only environment to a delegated one must drop the flat
        Thumbprint or every reconnect would still try certificate auth.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Name
    )

    $cfg = ConvertTo-SPEnvironmentsConfig -Config $Config
    $key = Resolve-SPEnvironmentKey $cfg.Environments $Name
    if (-not $key) {
        $known = @($cfg.Environments.PSObject.Properties.Name)
        throw "Unknown environment '$Name'. Known environment(s): $(if ($known) { $known -join ', ' } else { '(none)' })."
    }

    $cfg | Add-Member -NotePropertyName ActiveEnvironment -NotePropertyValue $key -Force
    foreach ($k in (Get-SPConnectionKey)) {
        if ($cfg.PSObject.Properties[$k]) { $cfg.PSObject.Properties.Remove($k) }
    }
    foreach ($prop in $cfg.Environments.$key.PSObject.Properties) {
        if ($prop.Name -in (Get-SPConnectionKey)) {
            $cfg | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }
    }
    $cfg
}

function Set-SPEnvironmentInConfig {
    <#
    .SYNOPSIS
        Create or update the named environment by merging connection settings into it
        (non-connection keys are ignored; empty values are skipped, but $false is kept so
        persistence can be turned off). -MakeActive also switches the flat projection.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Settings,
        [switch]$MakeActive
    )

    $problems = @(Test-SPEnvironmentName -Name $Name)
    if ($problems.Count) { throw ($problems -join ' ') }

    $cfg = ConvertTo-SPEnvironmentsConfig -Config $Config
    $key = Resolve-SPEnvironmentKey $cfg.Environments $Name
    if (-not $key) {
        $key = $Name.Trim()
        $cfg.Environments | Add-Member -NotePropertyName $key -NotePropertyValue ([pscustomobject]@{})
    }

    $env = $cfg.Environments.$key
    foreach ($k in $Settings.Keys) {
        if ($k -notin (Get-SPConnectionKey)) { continue }
        if ($null -ne $Settings[$k] -and "$($Settings[$k])" -ne '') {
            $env | Add-Member -NotePropertyName $k -NotePropertyValue $Settings[$k] -Force
        }
    }

    if ($MakeActive) { $cfg = Select-SPEnvironmentInConfig -Config $cfg -Name $key }
    $cfg
}

function Remove-SPEnvironmentFromConfig {
    <#
    .SYNOPSIS
        Remove the named environment. If it was active, the pointer and the flat projection
        are cleared too (the config keeps any other environments untouched).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Name
    )

    $cfg = ConvertTo-SPEnvironmentsConfig -Config $Config
    $key = Resolve-SPEnvironmentKey $cfg.Environments $Name
    if (-not $key) {
        $known = @($cfg.Environments.PSObject.Properties.Name)
        throw "Unknown environment '$Name'. Known environment(s): $(if ($known) { $known -join ', ' } else { '(none)' })."
    }

    $wasActive = "$($cfg.ActiveEnvironment)" -ieq $key
    $cfg.Environments.PSObject.Properties.Remove($key)
    if ($wasActive) {
        if ($cfg.PSObject.Properties['ActiveEnvironment']) { $cfg.PSObject.Properties.Remove('ActiveEnvironment') }
        foreach ($k in (Get-SPConnectionKey)) {
            if ($cfg.PSObject.Properties[$k]) { $cfg.PSObject.Properties.Remove($k) }
        }
    }
    $cfg
}

function Get-SPEnvironmentsFromConfig {
    <#
    .SYNOPSIS
        List the environments in a config (migrating v1 in-memory), one row per environment
        with the active one flagged. Sorted by name.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][object]$Config)

    $cfg = ConvertTo-SPEnvironmentsConfig -Config $Config
    $active = "$($cfg.ActiveEnvironment)"
    foreach ($prop in ($cfg.Environments.PSObject.Properties | Sort-Object Name)) {
        $e = $prop.Value
        [pscustomobject]@{
            Name          = $prop.Name
            Url           = "$($e.Url)"
            Tenant        = "$($e.Tenant)"
            ClientId      = "$($e.ClientId)"
            AuthMode      = $(if ("$($e.AuthMode)") { "$($e.AuthMode)" } else { 'Delegated' })
            DelegatedFlow = $(if ("$($e.DelegatedFlow)") { "$($e.DelegatedFlow)" } else { 'Interactive' })
            PersistLogin  = ("$($e.PersistLogin)" -in 'True', '1')
            Active        = ($prop.Name -ieq $active)
        }
    }
}
