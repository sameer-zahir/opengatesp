function New-SPCopyResult {
    <#
    .SYNOPSIS
        Shape one row of a migration report. Pure (no side effects), so the report
        format is stable and unit-testable. Every copy operation emits these.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ObjectType,   # Site, List, Library, Item, File, Folder, ContentType, Field, View, Page, Navigation
        [string]$Name,
        [string]$Action,       # Create, Overwrite, Skip, Rename, ...
        [ValidateSet('Success', 'Warning', 'Error', 'WouldCopy', 'Skipped')][string]$Status,
        [string]$Detail
    )
    [pscustomobject]@{
        ObjectType = $ObjectType
        Name       = $Name
        Action     = $Action
        Status     = $Status
        Detail     = $Detail
    }
}
