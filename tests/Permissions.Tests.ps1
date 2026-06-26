#Requires -Version 7.4
# Tests for the pure Phase 2 helpers — principal mapping + incremental change selection.
# Dot-source the Private helpers directly: no PnP.PowerShell, no tenant, CI-friendly.

BeforeAll {
    $priv = Join-Path $PSScriptRoot '..\module\OpenGateSP\Private'
    . (Join-Path $priv 'ConvertTo-SPPrincipalKey.ps1')
    . (Join-Path $priv 'ConvertTo-SPPrincipalMap.ps1')
    . (Join-Path $priv 'Resolve-SPPrincipal.ps1')
    . (Join-Path $priv 'Select-SPChangedItems.ps1')
}

Describe 'ConvertTo-SPPrincipalKey' {
    It 'strips a claims prefix and lower-cases' {
        ConvertTo-SPPrincipalKey 'i:0#.f|membership|Jane@Contoso.com' | Should -Be 'jane@contoso.com'
    }
    It 'passes a plain email through (lower-cased)' {
        ConvertTo-SPPrincipalKey 'Bob@Contoso.com' | Should -Be 'bob@contoso.com'
    }
    It 'keeps the trailing token of a group claim' {
        ConvertTo-SPPrincipalKey 'c:0t.c|tenant|abc-123' | Should -Be 'abc-123'
    }
}

Describe 'ConvertTo-SPPrincipalMap' {
    It 'normalizes explicit rows into a case-insensitive lookup' {
        $map = ConvertTo-SPPrincipalMap -Row @(
            [pscustomobject]@{ Source = 'Jane@Contoso.com'; Destination = 'jane@fabrikam.com' }
        )
        $map.Explicit['jane@contoso.com'] | Should -Be 'jane@fabrikam.com'
    }
    It 'ignores blank/partial rows' {
        $map = ConvertTo-SPPrincipalMap -Row @(
            [pscustomobject]@{ Source = ''; Destination = 'x' },
            [pscustomobject]@{ Source = 'a@b.com'; Destination = '' },
            $null
        )
        $map.Explicit.Count | Should -Be 0
    }
    It 'carries the domain swap' {
        $map = ConvertTo-SPPrincipalMap -DomainFrom 'contoso.com' -DomainTo 'fabrikam.com'
        $map.DomainFrom | Should -Be 'contoso.com'
        $map.DomainTo | Should -Be 'fabrikam.com'
    }
}

Describe 'Resolve-SPPrincipal' {
    It 'prefers an explicit mapping' {
        $map = ConvertTo-SPPrincipalMap -Row @([pscustomobject]@{ Source = 'jane@contoso.com'; Destination = 'jane.doe@fabrikam.com' }) -DomainFrom 'contoso.com' -DomainTo 'fabrikam.com'
        Resolve-SPPrincipal -Principal 'i:0#.f|membership|jane@contoso.com' -Map $map | Should -Be 'jane.doe@fabrikam.com'
    }
    It 'falls back to a domain swap' {
        $map = ConvertTo-SPPrincipalMap -DomainFrom 'contoso.com' -DomainTo 'fabrikam.com'
        Resolve-SPPrincipal -Principal 'bob@contoso.com' -Map $map | Should -Be 'bob@fabrikam.com'
    }
    It 'returns $null when nothing maps' {
        $map = ConvertTo-SPPrincipalMap -DomainFrom 'contoso.com' -DomainTo 'fabrikam.com'
        Resolve-SPPrincipal -Principal 'external@other.com' -Map $map | Should -BeNullOrEmpty
    }
}

Describe 'Select-SPChangedItems' {
    It 'keeps only items at/after the watermark' {
        $items = @(
            [pscustomobject]@{ Id = 1; Modified = (Get-Date '2026-01-01') }
            [pscustomobject]@{ Id = 2; Modified = (Get-Date '2026-06-01') }
        )
        $r = Select-SPChangedItems -SourceItem $items -Since (Get-Date '2026-03-01')
        $r.Count | Should -Be 1
        $r[0].Id | Should -Be 2
    }
    It 'returns all items when no watermark is given' {
        $items = @([pscustomobject]@{ Id = 1; Modified = (Get-Date '2026-01-01') })
        (Select-SPChangedItems -SourceItem $items).Count | Should -Be 1
    }
    It 'skips items the destination already holds at an equal-or-newer time' {
        $items = @(
            [pscustomobject]@{ Id = 1; Modified = (Get-Date '2026-06-01') }  # dest newer -> skip
            [pscustomobject]@{ Id = 2; Modified = (Get-Date '2026-06-01') }  # dest older -> keep
        )
        $dest = @{ '1' = (Get-Date '2026-07-01'); '2' = (Get-Date '2026-01-01') }
        $r = Select-SPChangedItems -SourceItem $items -DestIndex $dest
        $r.Count | Should -Be 1
        $r[0].Id | Should -Be 2
    }
}
