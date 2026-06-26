#Requires -Version 7.4
# Tests for the pure field-value resolver — Person/User + Managed-Metadata round-tripping.
# No PnP, no tenant: CSOM values are duck-typed as pscustomobjects.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\module\OpenGateSP\Private\Resolve-SPFieldValue.ps1')
}

Describe 'Resolve-SPFieldValue' {
    It 'extracts the email from a User field value' {
        $v = [pscustomobject]@{ LookupId = 7; LookupValue = 'Jane Doe'; Email = 'jane@contoso.com' }
        Resolve-SPFieldValue -FieldType 'User' -Value $v | Should -Be 'jane@contoso.com'
    }
    It 'falls back to LookupValue when there is no email' {
        $v = [pscustomobject]@{ LookupId = 7; LookupValue = 'i:0#.f|membership|jane@contoso.com' }
        Resolve-SPFieldValue -FieldType 'User' -Value $v | Should -Be 'i:0#.f|membership|jane@contoso.com'
    }
    It 'remaps a user via UserMap (cross-tenant)' {
        $v = [pscustomobject]@{ Email = 'jane@contoso.com' }
        $map = @{ 'jane@contoso.com' = 'jane@fabrikam.com' }
        Resolve-SPFieldValue -FieldType 'User' -Value $v -UserMap $map | Should -Be 'jane@fabrikam.com'
    }
    It 'resolves a multi-user field to an array of emails' {
        $v = @(
            [pscustomobject]@{ Email = 'a@contoso.com' }
            [pscustomobject]@{ Email = 'b@contoso.com' }
        )
        $r = @(Resolve-SPFieldValue -FieldType 'UserMulti' -Value $v)
        $r.Count | Should -Be 2
        $r | Should -Contain 'a@contoso.com'
    }
    It 'formats a Managed-Metadata value as Label|Guid' {
        $v = [pscustomobject]@{ Label = 'Finance'; TermGuid = '11111111-2222-3333-4444-555555555555' }
        Resolve-SPFieldValue -FieldType 'TaxonomyFieldType' -Value $v | Should -Be 'Finance|11111111-2222-3333-4444-555555555555'
    }
    It 'resolves a multi-value taxonomy field to an array' {
        $v = @(
            [pscustomobject]@{ Label = 'A'; TermGuid = 'g1' }
            [pscustomobject]@{ Label = 'B'; TermGuid = 'g2' }
        )
        $r = @(Resolve-SPFieldValue -FieldType 'TaxonomyFieldTypeMulti' -Value $v)
        $r | Should -Contain 'A|g1'
        $r | Should -Contain 'B|g2'
    }
    It 'passes simple field types through unchanged' {
        Resolve-SPFieldValue -FieldType 'Text' -Value 'hello' | Should -Be 'hello'
        Resolve-SPFieldValue -FieldType 'Number' -Value 42 | Should -Be 42
        Resolve-SPFieldValue -FieldType '' -Value 'x' | Should -Be 'x'
    }
    It 'passes a plain string user/taxonomy value through' {
        Resolve-SPFieldValue -FieldType 'User' -Value 'jane@contoso.com' | Should -Be 'jane@contoso.com'
        Resolve-SPFieldValue -FieldType 'TaxonomyFieldType' -Value 'Finance|g1' | Should -Be 'Finance|g1'
    }
    It 'returns null for a null value' {
        Resolve-SPFieldValue -FieldType 'User' -Value $null | Should -BeNullOrEmpty
    }
}
