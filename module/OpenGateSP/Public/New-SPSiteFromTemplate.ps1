function New-SPSiteFromTemplate {
    <#
    .SYNOPSIS
        Create a SharePoint site (Team or Communication), optionally apply a PnP
        provisioning template, and optionally create document libraries.
    .DESCRIPTION
        Wraps New-PnPSite. With -TemplatePath, applies a PnP site template (.xml/.pnp) to
        the new site. With -Libraries, creates the named document libraries.
    .PARAMETER Title
        Site title.
    .PARAMETER Alias
        Mailbox/alias for a Team Site (required for -Type TeamSite).
    .PARAMETER Url
        Full or server-relative URL for a Communication Site (required for that type).
    .PARAMETER Type
        TeamSite (M365 group-connected) or CommunicationSite. Default TeamSite.
    .PARAMETER TemplatePath
        Optional PnP provisioning template to apply after creation.
    .PARAMETER Libraries
        Optional document libraries to create on the site.
    .PARAMETER AsJson
        Emit the result as a JSON array instead of an object.
    .EXAMPLE
        New-SPSiteFromTemplate -Title "Project Apollo" -Alias project-apollo -Type TeamSite -Libraries 'Specs','Designs'
    .EXAMPLE
        New-SPSiteFromTemplate -Title "Intranet" -Url https://contoso.sharepoint.com/sites/intranet -Type CommunicationSite -TemplatePath ./intranet.pnp
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Alias,
        [string]$Url,
        [ValidateSet('TeamSite', 'CommunicationSite')][string]$Type = 'TeamSite',
        [string]$TemplatePath,
        [string[]]$Libraries,
        [switch]$AsJson
    )

    Assert-SPConnection | Out-Null
    $createdUrl = $null

    if ($Type -eq 'TeamSite') {
        if (-not $Alias) { throw "TeamSite requires -Alias." }
        if ($PSCmdlet.ShouldProcess($Alias, 'Create Microsoft 365 group-connected Team Site')) {
            $createdUrl = Invoke-SPRetry -Operation 'New-PnPSite' { New-PnPSite -Type TeamSite -Title $Title -Alias $Alias -ErrorAction Stop }
        }
    }
    else {
        if (-not $Url) { throw "CommunicationSite requires -Url." }
        if ($PSCmdlet.ShouldProcess($Url, 'Create Communication Site')) {
            $createdUrl = Invoke-SPRetry -Operation 'New-PnPSite' { New-PnPSite -Type CommunicationSite -Title $Title -Url $Url -ErrorAction Stop }
        }
    }

    $targetUrl = if ($createdUrl) { "$createdUrl" } elseif ($Url) { $Url } else { $null }
    if ($createdUrl) { Write-SPLog "Created site: $targetUrl" -Level Success }

    # Apply a provisioning template
    $templateApplied = $false
    if ($TemplatePath -and $targetUrl) {
        if (-not (Test-Path -LiteralPath $TemplatePath)) {
            Write-SPLog "Template not found: $TemplatePath" -Level Warn
        }
        elseif (-not (Get-Command Invoke-PnPSiteTemplate -ErrorAction SilentlyContinue)) {
            Write-SPLog 'Invoke-PnPSiteTemplate not available in this PnP version; skipping template.' -Level Warn
        }
        elseif ($PSCmdlet.ShouldProcess($targetUrl, "Apply template $TemplatePath")) {
            Resolve-SPSiteConnection -SiteUrl $targetUrl | Out-Null
            Invoke-SPRetry -Operation 'Invoke-PnPSiteTemplate' { Invoke-PnPSiteTemplate -Path $TemplatePath -ErrorAction Stop }
            $templateApplied = $true
            Write-SPLog "Applied template $TemplatePath" -Level Success
        }
    }

    # Create libraries
    $createdLibs = @()
    if ($Libraries -and $targetUrl) {
        Resolve-SPSiteConnection -SiteUrl $targetUrl | Out-Null
        foreach ($lib in $Libraries) {
            if ($PSCmdlet.ShouldProcess("$targetUrl :: $lib", 'Create document library')) {
                try {
                    Invoke-SPRetry -Operation "New-PnPList $lib" { New-PnPList -Title $lib -Template DocumentLibrary -OnQuickLaunch -ErrorAction Stop } | Out-Null
                    $createdLibs += $lib
                    Write-SPLog "Created library '$lib'" -Level Success
                }
                catch { Write-SPLog "Could not create library '$lib': $($_.Exception.Message)" -Level Warn }
            }
        }
    }

    [pscustomobject]@{
        Title            = $Title
        Type             = $Type
        Url              = $targetUrl
        Created          = [bool]$createdUrl
        TemplateApplied  = $templateApplied
        LibrariesCreated = $createdLibs
        WhatIf           = [bool]$WhatIfPreference
    } | ConvertTo-SPOutput -AsJson:$AsJson
}
