function Resolve-SPFieldValue {
    <#
    .SYNOPSIS
        Map a source list-item field value to a destination-ready value by field type, so
        Person/User and Managed-Metadata columns round-trip on copy (the documented lossy areas).
        Pure — no I/O.
    .DESCRIPTION
        Get-PnPListItem returns rich CSOM values for some field types that don't copy verbatim:
        a User field is a FieldUserValue (a lookup id into the SOURCE site's user list), and a
        Managed-Metadata field is a TaxonomyFieldValue (a term GUID + label). Setting those on the
        destination needs a portable representation:

          - User / UserMulti          -> the user's email/login (Add-PnPListItem ensures the user)
          - TaxonomyFieldType(/Multi)  -> "Label|TermGuid" (PnP resolves the term)
          - everything else            -> passed through unchanged (Text, Number, Choice, ...)

        -UserMap optionally remaps a source email/login to a destination one (cross-tenant). The
        FieldType strings are SharePoint's TypeAsString, so callers pass $field.TypeAsString directly.
    .PARAMETER FieldType
        The SharePoint field TypeAsString (e.g. User, UserMulti, TaxonomyFieldType,
        TaxonomyFieldTypeMulti, Text). Unknown/blank types pass the value through.
    .PARAMETER Value
        The source field value (a CSOM value object, an array, or a primitive).
    .PARAMETER UserMap
        Optional hashtable: source email/login -> destination email/login.
    .OUTPUTS
        The destination-ready value (string, string[], or the original value).
    #>
    [CmdletBinding()]
    param(
        [string]$FieldType = '',
        $Value,
        [hashtable]$UserMap
    )
    if ($null -eq $Value) { return $null }

    $resolveUser = {
        param($v, $map)
        if ($null -eq $v) { return $null }
        $key =
            if ($v -is [string]) { $v }
            elseif ($v.PSObject.Properties['Email'] -and $v.Email) { "$($v.Email)" }
            elseif ($v.PSObject.Properties['LookupValue'] -and $v.LookupValue) { "$($v.LookupValue)" }
            else { "$v" }
        if (-not $key) { return $null }
        if ($map -and $map.ContainsKey($key)) { return "$($map[$key])" }
        $key
    }

    $resolveTax = {
        param($v)
        if ($null -eq $v) { return $null }
        if ($v -is [string]) { return $v }
        $label = if ($v.PSObject.Properties['Label']) { "$($v.Label)" } else { '' }
        $guid = if ($v.PSObject.Properties['TermGuid']) { "$($v.TermGuid)" } else { '' }
        if ($guid) { return ('{0}|{1}' -f $label, $guid) }
        if ($label) { return $label }
        $null
    }

    switch ($FieldType) {
        'User'                  { & $resolveUser $Value $UserMap }
        'UserMulti'             { @($Value | ForEach-Object { & $resolveUser $_ $UserMap } | Where-Object { $_ }) }
        'TaxonomyFieldType'     { & $resolveTax $Value }
        'TaxonomyFieldTypeMulti' { @($Value | ForEach-Object { & $resolveTax $_ } | Where-Object { $_ }) }
        default                 { $Value }
    }
}
