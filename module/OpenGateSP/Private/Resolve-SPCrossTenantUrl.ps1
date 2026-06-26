function Resolve-SPCrossTenantUrl {
    <#
    .SYNOPSIS
        Map a source server-relative URL to the equivalent URL under a destination web, by
        swapping the web's server-relative prefix. Pure — no I/O.
    .DESCRIPTION
        Same-tenant copy (Copy-PnPFolder) and cross-tenant copy (download/upload) both need to
        translate '/sites/Src/Shared Documents/x.docx' under source web '/sites/Src' into
        '/sites/Dst/Shared Documents/x.docx' under destination web '/sites/Dst'. This is the
        pure core of that translation, shared by both paths and unit-tested.
    .PARAMETER SourceServerRelativeUrl
        The source file/folder server-relative URL, e.g. '/sites/Src/Shared Documents/x.docx'.
    .PARAMETER SourceWebServerRelativeUrl
        The source web's server-relative URL, e.g. '/sites/Src'.
    .PARAMETER DestinationWebServerRelativeUrl
        The destination web's server-relative URL, e.g. '/sites/Dst'.
    .EXAMPLE
        Resolve-SPCrossTenantUrl -SourceServerRelativeUrl '/sites/A/Docs/f.txt' -SourceWebServerRelativeUrl '/sites/A' -DestinationWebServerRelativeUrl '/sites/B'
        # -> /sites/B/Docs/f.txt
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$SourceServerRelativeUrl,
        [Parameter(Mandatory)][string]$SourceWebServerRelativeUrl,
        [Parameter(Mandatory)][string]$DestinationWebServerRelativeUrl
    )

    $srcWeb = $SourceWebServerRelativeUrl.TrimEnd('/')
    $dstWeb = $DestinationWebServerRelativeUrl.TrimEnd('/')

    if ($SourceServerRelativeUrl.TrimEnd('/') -ieq $srcWeb) { return $dstWeb }
    if ($SourceServerRelativeUrl -notlike "$srcWeb/*") {
        throw "URL '$SourceServerRelativeUrl' is not under source web '$srcWeb'."
    }
    $dstWeb + $SourceServerRelativeUrl.Substring($srcWeb.Length)
}
