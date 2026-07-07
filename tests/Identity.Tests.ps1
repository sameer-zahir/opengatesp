#Requires -Version 7.4
# Unit tests for the 0.14 identity-copy pipeline (docs/14): inventory classification, map
# proposal precedence, conflict validation, plan ordering, the hand-editable CSV schema
# contracts, and Copy-SPIdentity's guardrails (dry-run default, -Force honoring -WhatIf,
# fail-closed validation, disabled-by-default users, convergent membership sync). All Graph
# traffic goes through an in-memory Invoke-SPGraph stand-in — no tenant, CI-friendly.

BeforeAll {
    $script:PriorQuiet = $env:OPENGATESP_QUIET
    $env:OPENGATESP_QUIET = '1'

    $mod = Join-Path $PSScriptRoot '..\module\OpenGateSP'
    . (Join-Path $mod 'Private\Write-SPLog.ps1')
    . (Join-Path $mod 'Private\ConvertTo-SPOutput.ps1')
    . (Join-Path $mod 'Private\New-SPCopyResult.ps1')
    . (Join-Path $mod 'Private\Get-SPMembershipDelta.ps1')
    . (Join-Path $mod 'Private\ConvertTo-SPIdentityInventoryRow.ps1')
    . (Join-Path $mod 'Private\ConvertTo-SPIdentityMapRow.ps1')
    . (Join-Path $mod 'Private\Test-SPIdentityConflict.ps1')
    . (Join-Path $mod 'Private\Get-SPIdentityPlan.ps1')
    . (Join-Path $mod 'Public\Get-SPIdentityInventory.ps1')
    . (Join-Path $mod 'Public\New-SPIdentityMap.ps1')
    . (Join-Path $mod 'Public\Test-SPIdentityMap.ps1')
    . (Join-Path $mod 'Public\Copy-SPIdentity.ps1')

    # In-memory Graph stand-in. Every call is recorded so tests can assert exactly what was
    # (or was NOT) sent. Unexpected calls throw so new traffic can't slip past a test.
    function Invoke-SPGraph {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Method,
            [Parameter(Mandatory)][string]$Url,
            [hashtable]$Body,
            [object]$Connection,
            [switch]$All
        )
        $script:GraphCalls.Add([pscustomobject]@{ Method = $Method; Url = $Url; Body = $Body })
        switch -Wildcard ("$Method $Url") {
            'GET v1.0/organization*'     { return [pscustomobject]@{ verifiedDomains = @($script:VerifiedDomains | ForEach-Object { [pscustomobject]@{ name = $_ } }) } }
            'GET v1.0/groups/*/owners*'  { return @($script:Rosters["$(($Url -split '/')[2])/owners"]  | Where-Object { $_ }) }
            'GET v1.0/groups/*/members*' { return @($script:Rosters["$(($Url -split '/')[2])/members"] | Where-Object { $_ }) }
            'GET v1.0/users*'            { return @($script:DestUsers) }
            'GET v1.0/groups*'           { return @($script:DestGroups) }
            'POST v1.0/groups/*/$ref'    { return $null }
            'POST v1.0/users'            { return [pscustomobject]@{ id = "new-user-$($Body.mailNickname)" } }
            'POST v1.0/invitations'      { return [pscustomobject]@{ invitedUser = [pscustomobject]@{ id = "new-guest-$($Body.invitedUserEmailAddress)" } } }
            'POST v1.0/groups'           { return [pscustomobject]@{ id = "new-group-$($Body.mailNickname)" } }
            default                      { throw "Unexpected Graph call in test: $Method $Url" }
        }
    }

    # Row factories matching the inventory / map CSV schemas.
    function New-InvRow {
        param($Type = 'User', $Id = 's1', $Upn = '', $Display = '', $Mail = '', $Nick = '',
            $Usage = '', $Supported = $true, $Notes = '', $Owners = '', $Members = '')
        [pscustomobject]@{
            Type = $Type; Id = $Id; UserPrincipalName = $Upn; DisplayName = $Display; Mail = $Mail
            MailNickname = $Nick; AccountEnabled = $true; UsageLocation = $Usage
            Supported = $Supported; Notes = $Notes; Owners = $Owners; Members = $Members
        }
    }
    function New-MapRow {
        param($Type = 'User', $SourceId = 's1', $SourceUpn = '', $Display = '', $Mail = '',
            $Usage = 'US', $TargetUpn = '', $Nick = '', $Action = 'Create', $Matched = '', $Notes = '')
        [pscustomobject]@{
            Type = $Type; SourceId = $SourceId; SourceUpn = $SourceUpn; SourceDisplayName = $Display
            SourceMail = $Mail; UsageLocation = $Usage; TargetUpn = $TargetUpn
            TargetMailNickname = $Nick; Action = $Action; MatchedExistingId = $Matched; Notes = $Notes
        }
    }
}

AfterAll {
    $env:OPENGATESP_QUIET = $script:PriorQuiet
}

Describe 'ConvertTo-SPIdentityInventoryRow (classification)' {
    It 'classifies a member user as User, supported' {
        $row = ConvertTo-SPIdentityInventoryRow -User ([pscustomobject]@{
                id = 'u1'; userPrincipalName = 'jane@contoso.com'; displayName = 'Jane'
                mail = 'jane@contoso.com'; mailNickname = 'jane'; userType = 'Member'
                accountEnabled = $true; usageLocation = 'US'
            })
        $row.Type | Should -Be 'User'
        $row.Supported | Should -BeTrue
        $row.UsageLocation | Should -Be 'US'
    }
    It 'classifies guests by userType and by the #EXT# UPN marker' {
        (ConvertTo-SPIdentityInventoryRow -User ([pscustomobject]@{ id = 'u2'; userPrincipalName = 'x@other.com'; userType = 'Guest' })).Type |
            Should -Be 'Guest'
        (ConvertTo-SPIdentityInventoryRow -User ([pscustomobject]@{ id = 'u3'; userPrincipalName = 'x_gmail.com#EXT#@contoso.onmicrosoft.com'; userType = '' })).Type |
            Should -Be 'Guest'
    }
    It 'classifies group flavours and marks Exchange-only types unsupported' {
        $unified = ConvertTo-SPIdentityInventoryRow -Group ([pscustomobject]@{ id = 'g1'; displayName = 'A'; groupTypes = @('Unified'); mailEnabled = $true; securityEnabled = $false })
        $sec = ConvertTo-SPIdentityInventoryRow -Group ([pscustomobject]@{ id = 'g2'; displayName = 'B'; groupTypes = @(); mailEnabled = $false; securityEnabled = $true })
        $mesg = ConvertTo-SPIdentityInventoryRow -Group ([pscustomobject]@{ id = 'g3'; displayName = 'C'; groupTypes = @(); mailEnabled = $true; securityEnabled = $true })
        $dl = ConvertTo-SPIdentityInventoryRow -Group ([pscustomobject]@{ id = 'g4'; displayName = 'D'; groupTypes = @(); mailEnabled = $true; securityEnabled = $false })

        $unified.Type | Should -Be 'M365Group';                $unified.Supported | Should -BeTrue
        $sec.Type | Should -Be 'SecurityGroup';                $sec.Supported | Should -BeTrue
        $mesg.Type | Should -Be 'MailEnabledSecurityGroup';    $mesg.Supported | Should -BeFalse
        $dl.Type | Should -Be 'DistributionList';              $dl.Supported | Should -BeFalse
        $dl.Notes | Should -Match 'Exchange'
    }
    It 'joins rosters with semicolons and drops blanks' {
        $row = ConvertTo-SPIdentityInventoryRow -Group ([pscustomobject]@{ id = 'g1'; displayName = 'A'; groupTypes = @('Unified'); mailEnabled = $true; securityEnabled = $false }) `
            -Owners @('a@x.com', '', 'b@x.com') -Members @('c@x.com')
        $row.Owners | Should -Be 'a@x.com;b@x.com'
        $row.Members | Should -Be 'c@x.com'
    }
}

Describe 'ConvertTo-SPIdentityMapRow (matching precedence)' {
    BeforeEach {
        $script:MapDestUsers = @(
            [pscustomobject]@{ id = 'd1'; userPrincipalName = 'jane.renamed@fabrikam.com'; displayName = 'Jane'; mail = 'jane@contoso.com' }
            [pscustomobject]@{ id = 'd2'; userPrincipalName = 'bob@fabrikam.com'; displayName = 'Bob'; mail = '' }
        )
        $script:MapDestGroups = @(
            [pscustomobject]@{ id = 'g1'; displayName = 'Team A'; mailNickname = 'teama' }
            [pscustomobject]@{ id = 'g2'; displayName = 'Team B'; mailNickname = 'bteam' }
        )
    }

    It 'matches users by mail before UPN local part' {
        $row = ConvertTo-SPIdentityMapRow -InventoryRow (New-InvRow -Upn 'jane@contoso.com' -Mail 'jane@contoso.com') `
            -DomainTo 'fabrikam.com' -DestUsers $script:MapDestUsers -DestGroups $script:MapDestGroups
        $row.Action | Should -Be 'Map'
        $row.MatchedExistingId | Should -Be 'd1'
        $row.TargetUpn | Should -Be 'jane.renamed@fabrikam.com'
        $row.Notes | Should -Match 'by mail'
    }
    It 'falls back to the UPN local part when mail does not match' {
        $row = ConvertTo-SPIdentityMapRow -InventoryRow (New-InvRow -Upn 'bob@contoso.com') `
            -DomainTo 'fabrikam.com' -DestUsers $script:MapDestUsers -DestGroups $script:MapDestGroups
        $row.Action | Should -Be 'Map'
        $row.MatchedExistingId | Should -Be 'd2'
        $row.Notes | Should -Match 'UPN local part'
    }
    It 'proposes Create with local-part@DomainTo when nothing matches' {
        $row = ConvertTo-SPIdentityMapRow -InventoryRow (New-InvRow -Upn 'carol@contoso.com') `
            -DomainTo 'fabrikam.com' -DestUsers $script:MapDestUsers -DestGroups $script:MapDestGroups
        $row.Action | Should -Be 'Create'
        $row.TargetUpn | Should -Be 'carol@fabrikam.com'
    }
    It 'skips guests by default, invites them with -IncludeGuests' {
        $guest = New-InvRow -Type 'Guest' -Upn 'ext_gmail.com#EXT#@contoso.onmicrosoft.com' -Mail 'ext@gmail.com'
        (ConvertTo-SPIdentityMapRow -InventoryRow $guest -DomainTo 'fabrikam.com').Action | Should -Be 'Skip'
        $inv = ConvertTo-SPIdentityMapRow -InventoryRow $guest -DomainTo 'fabrikam.com' -IncludeGuests
        $inv.Action | Should -Be 'Invite'
        $inv.TargetUpn | Should -Be 'ext@gmail.com'
    }
    It "treats the CSV round-trip string 'False' as unsupported" {
        $row = ConvertTo-SPIdentityMapRow -InventoryRow (New-InvRow -Type 'DistributionList' -Display 'Old DL' -Supported 'False') -DomainTo 'fabrikam.com'
        $row.Action | Should -Be 'Skip'
    }
    It 'matches groups by mail nickname, then display name' {
        $byNick = ConvertTo-SPIdentityMapRow -InventoryRow (New-InvRow -Type 'SecurityGroup' -Display 'Renamed' -Nick 'teama') `
            -DomainTo 'fabrikam.com' -DestGroups $script:MapDestGroups
        $byNick.Action | Should -Be 'Map'
        $byNick.MatchedExistingId | Should -Be 'g1'

        $byName = ConvertTo-SPIdentityMapRow -InventoryRow (New-InvRow -Type 'SecurityGroup' -Display 'Team B') `
            -DomainTo 'fabrikam.com' -DestGroups $script:MapDestGroups
        $byName.Action | Should -Be 'Map'
        $byName.MatchedExistingId | Should -Be 'g2'
    }
    It 'derives a nickname for unmatched groups that lack one' {
        $row = ConvertTo-SPIdentityMapRow -InventoryRow (New-InvRow -Type 'SecurityGroup' -Display 'Fin & Ops!') `
            -DomainTo 'fabrikam.com' -DestGroups $script:MapDestGroups
        $row.Action | Should -Be 'Create'
        $row.TargetMailNickname | Should -Be 'finops'
    }
}

Describe 'Test-SPIdentityConflict (validation rules)' {
    BeforeEach {
        $script:VDestUsers = @([pscustomobject]@{ id = 'd1'; userPrincipalName = 'taken@fabrikam.com'; mail = '' })
        $script:VDestGroups = @([pscustomobject]@{ id = 'g1'; displayName = 'X'; mailNickname = 'taken' })
        $script:VDomains = @('fabrikam.com')
    }

    It 'errors when a Create user UPN already exists at the destination' {
        $f = Test-SPIdentityConflict -MapRow @(New-MapRow -TargetUpn 'taken@fabrikam.com') -DestUsers $script:VDestUsers -DestGroups $script:VDestGroups -VerifiedDomains $script:VDomains
        $f.Status | Should -Be 'Error'
        $f.Issues | Should -Match 'already exists'
    }
    It 'errors on duplicate target UPNs within the map itself' {
        $rows = @((New-MapRow -SourceId 'a' -TargetUpn 'new@fabrikam.com'), (New-MapRow -SourceId 'b' -TargetUpn 'NEW@fabrikam.com'))
        $f = @(Test-SPIdentityConflict -MapRow $rows -DestUsers $script:VDestUsers -DestGroups $script:VDestGroups -VerifiedDomains $script:VDomains)
        @($f | Where-Object { $_.Issues -match 'Duplicate target UPN' }).Count | Should -Be 2
    }
    It 'errors on an unverified UPN domain' {
        $f = Test-SPIdentityConflict -MapRow @(New-MapRow -TargetUpn 'new@evil.com') -DestUsers $script:VDestUsers -DestGroups $script:VDestGroups -VerifiedDomains $script:VDomains
        $f.Status | Should -Be 'Error'
        $f.Issues | Should -Match 'not verified'
    }
    It 'only warns when the verified-domain list is empty (cannot validate is not invalid)' {
        $f = Test-SPIdentityConflict -MapRow @(New-MapRow -TargetUpn 'new@fabrikam.com') -DestUsers $script:VDestUsers -DestGroups $script:VDestGroups -VerifiedDomains @()
        $f.Status | Should -Be 'Warning'
        $f.Issues | Should -Match 'Verified domains unknown'
    }
    It 'warns when a Create user has no UsageLocation' {
        $f = Test-SPIdentityConflict -MapRow @(New-MapRow -TargetUpn 'new@fabrikam.com' -Usage '') -DestUsers $script:VDestUsers -DestGroups $script:VDestGroups -VerifiedDomains $script:VDomains
        $f.Status | Should -Be 'Warning'
        $f.Issues | Should -Match 'UsageLocation'
    }
    It 'validates Map rows: id required, must still exist, OK when it does' {
        $noId = Test-SPIdentityConflict -MapRow @(New-MapRow -Action 'Map') -DestUsers $script:VDestUsers -DestGroups $script:VDestGroups -VerifiedDomains $script:VDomains
        $noId.Status | Should -Be 'Error'
        $gone = Test-SPIdentityConflict -MapRow @(New-MapRow -Action 'Map' -Matched 'vanished-id') -DestUsers $script:VDestUsers -DestGroups $script:VDestGroups -VerifiedDomains $script:VDomains
        $gone.Status | Should -Be 'Error'
        $gone.Issues | Should -Match 'no longer exists'
        $ok = Test-SPIdentityConflict -MapRow @(New-MapRow -Action 'Map' -Matched 'd1') -DestUsers $script:VDestUsers -DestGroups $script:VDestGroups -VerifiedDomains $script:VDomains
        $ok.Status | Should -Be 'OK'
    }
    It 'validates Invite rows: guests only, mail required' {
        (Test-SPIdentityConflict -MapRow @(New-MapRow -Action 'Invite') -DestUsers @() -DestGroups @() -VerifiedDomains $script:VDomains).Status | Should -Be 'Error'
        (Test-SPIdentityConflict -MapRow @(New-MapRow -Type 'Guest' -Action 'Invite') -DestUsers @() -DestGroups @() -VerifiedDomains $script:VDomains).Status | Should -Be 'Error'
        (Test-SPIdentityConflict -MapRow @(New-MapRow -Type 'Guest' -Action 'Invite' -Mail 'g@x.com') -DestUsers @() -DestGroups @() -VerifiedDomains $script:VDomains).Status | Should -Be 'OK'
    }
    It 'errors on Create for Exchange-only group types' {
        $f = Test-SPIdentityConflict -MapRow @(New-MapRow -Type 'DistributionList' -Nick 'dl1') -DestUsers @() -DestGroups @() -VerifiedDomains $script:VDomains
        $f.Status | Should -Be 'Error'
        $f.Issues | Should -Match 'Exchange'
    }
    It 'errors on group nickname collisions (destination and within the map) and empty nicknames' {
        (Test-SPIdentityConflict -MapRow @(New-MapRow -Type 'SecurityGroup' -Nick 'taken') -DestUsers @() -DestGroups $script:VDestGroups -VerifiedDomains $script:VDomains).Status | Should -Be 'Error'
        $dupes = @((New-MapRow -Type 'SecurityGroup' -SourceId 'a' -Nick 'ops'), (New-MapRow -Type 'M365Group' -SourceId 'b' -Nick 'OPS'))
        @(Test-SPIdentityConflict -MapRow $dupes -DestUsers @() -DestGroups @() -VerifiedDomains $script:VDomains | Where-Object Status -eq 'Error').Count | Should -Be 2
        (Test-SPIdentityConflict -MapRow @(New-MapRow -Type 'SecurityGroup' -Nick '') -DestUsers @() -DestGroups @() -VerifiedDomains $script:VDomains).Status | Should -Be 'Error'
    }
    It 'errors on unknown Actions and passes Skip rows' {
        (Test-SPIdentityConflict -MapRow @(New-MapRow -Action 'Delete') -DestUsers @() -DestGroups @() -VerifiedDomains $script:VDomains).Status | Should -Be 'Error'
        (Test-SPIdentityConflict -MapRow @(New-MapRow -Action 'Skip') -DestUsers @() -DestGroups @() -VerifiedDomains $script:VDomains).Status | Should -Be 'OK'
    }
}

Describe 'Get-SPIdentityPlan (phase ordering)' {
    It 'plans users/guests first, then security groups, then M365 groups; only Create/Invite rows' {
        $rows = @(
            New-MapRow -Type 'M365Group' -SourceId 'm1' -Nick 'm1'
            New-MapRow -Type 'User' -SourceId 'u1' -TargetUpn 'a@f.com'
            New-MapRow -Type 'SecurityGroup' -SourceId 'g1' -Nick 'g1'
            New-MapRow -Type 'User' -SourceId 'u2' -Action 'Map' -Matched 'd1'
            New-MapRow -Type 'Guest' -SourceId 'gu1' -Action 'Invite' -Mail 'g@x.com'
            New-MapRow -Type 'DistributionList' -SourceId 'dl1' -Nick 'dl1'
            New-MapRow -Type 'User' -SourceId 'u3' -Action 'Skip'
        )
        $plan = @(Get-SPIdentityPlan -MapRow $rows)
        $plan.Count | Should -Be 4
        $plan.SourceId | Should -Be @('u1', 'gu1', 'g1', 'm1')
        $plan.Phase | Should -Be @(1, 1, 2, 3)
    }
    It 'returns nothing for an all-Map/Skip plan' {
        @(Get-SPIdentityPlan -MapRow @((New-MapRow -Action 'Map' -Matched 'd1'), (New-MapRow -Action 'Skip'))).Count | Should -Be 0
    }
}

Describe 'CSV schema contracts (the hand-editable surface)' {
    It 'inventory rows keep the documented column order' {
        $row = ConvertTo-SPIdentityInventoryRow -User ([pscustomobject]@{ id = 'u1'; userPrincipalName = 'a@c.com' })
        @($row.PSObject.Properties.Name) | Should -Be @(
            'Type', 'Id', 'UserPrincipalName', 'DisplayName', 'Mail', 'MailNickname',
            'AccountEnabled', 'UsageLocation', 'Supported', 'Notes', 'Owners', 'Members')
    }
    It 'map rows keep the documented column order' {
        $row = ConvertTo-SPIdentityMapRow -InventoryRow (New-InvRow -Upn 'a@c.com') -DomainTo 'f.com'
        @($row.PSObject.Properties.Name) | Should -Be @(
            'Type', 'SourceId', 'SourceUpn', 'SourceDisplayName', 'SourceMail', 'UsageLocation',
            'TargetUpn', 'TargetMailNickname', 'Action', 'MatchedExistingId', 'Notes')
    }
}

Describe 'Identity cmdlets against the mock Graph' {
    BeforeEach {
        $script:GraphCalls = [System.Collections.Generic.List[object]]::new()
        $script:DestUsers = @()
        $script:DestGroups = @()
        $script:VerifiedDomains = @('fabrikam.com')
        $script:Rosters = @{}
        $script:Fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('ogsp-identity-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Fixture -Force | Out-Null
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Fixture -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'Get-SPIdentityInventory' {
        BeforeEach {
            $script:DestUsers = @(   # serves the single GET v1.0/users call (source side here)
                [pscustomobject]@{ id = 'u1'; userPrincipalName = 'jane@contoso.com'; displayName = 'Jane'; mail = 'jane@contoso.com'; mailNickname = 'jane'; userType = 'Member'; accountEnabled = $true; usageLocation = 'US' }
                [pscustomobject]@{ id = 'u2'; userPrincipalName = 'ext_gmail.com#EXT#@contoso.onmicrosoft.com'; displayName = 'Ext'; mail = 'ext@gmail.com'; mailNickname = 'ext'; userType = 'Guest'; accountEnabled = $true; usageLocation = '' }
            )
            $script:DestGroups = @(
                [pscustomobject]@{ id = 'g1'; displayName = 'Team A'; mail = 'teama@contoso.com'; mailNickname = 'teama'; groupTypes = @('Unified'); securityEnabled = $false; mailEnabled = $true }
                [pscustomobject]@{ id = 'g2'; displayName = 'Old DL'; mail = 'dl@contoso.com'; mailNickname = 'olddl'; groupTypes = @(); securityEnabled = $false; mailEnabled = $true }
            )
            $script:Rosters = @{
                'g1/owners'  = @([pscustomobject]@{ userPrincipalName = 'jane@contoso.com' })
                'g1/members' = @([pscustomobject]@{ userPrincipalName = 'jane@contoso.com' }, [pscustomobject]@{ userPrincipalName = 'ext_gmail.com#EXT#@contoso.onmicrosoft.com' })
            }
        }

        It 'classifies users, guests, and groups into one flat inventory' {
            $rows = @(Get-SPIdentityInventory)
            $rows.Count | Should -Be 4
            ($rows | Where-Object Id -eq 'u2').Type | Should -Be 'Guest'
            ($rows | Where-Object Id -eq 'g1').Type | Should -Be 'M365Group'
            ($rows | Where-Object Id -eq 'g1').Owners | Should -Be 'jane@contoso.com'
            ($rows | Where-Object Id -eq 'g2').Supported | Should -BeFalse
        }
        It 'writes a CSV that round-trips' {
            $csv = Join-Path $script:Fixture 'inv.csv'
            Get-SPIdentityInventory -Path $csv | Out-Null
            @(Import-Csv -LiteralPath $csv).Count | Should -Be 4
        }
    }

    Context 'New-SPIdentityMap (CSV round-trip)' {
        It 'proposes actions from an inventory CSV, honoring the Supported=False string' {
            $inv = Join-Path $script:Fixture 'inv.csv'
            @(
                New-InvRow -Id 'u1' -Upn 'carol@contoso.com' -Display 'Carol'
                New-InvRow -Type 'Guest' -Id 'u2' -Upn 'ext#EXT#@c.onmicrosoft.com' -Mail 'ext@gmail.com'
                New-InvRow -Type 'DistributionList' -Id 'g2' -Display 'Old DL' -Nick 'olddl' -Supported $false
            ) | Export-Csv -Path $inv -NoTypeInformation -Encoding utf8

            $rows = @(New-SPIdentityMap -InventoryCsv $inv -DomainTo 'fabrikam.com')
            ($rows | Where-Object SourceId -eq 'u1').Action | Should -Be 'Create'
            ($rows | Where-Object SourceId -eq 'u1').TargetUpn | Should -Be 'carol@fabrikam.com'
            ($rows | Where-Object SourceId -eq 'u2').Action | Should -Be 'Skip'   # guests skipped without -IncludeGuests
            ($rows | Where-Object SourceId -eq 'g2').Action | Should -Be 'Skip'   # unsupported survives the CSV round-trip
        }
        It 'throws on a missing inventory CSV' {
            { New-SPIdentityMap -InventoryCsv (Join-Path $script:Fixture 'nope.csv') -DomainTo 'f.com' } | Should -Throw '*not found*'
        }
    }

    Context 'Test-SPIdentityMap' {
        It 'sorts errors first' {
            $script:DestUsers = @([pscustomobject]@{ id = 'd1'; userPrincipalName = 'taken@fabrikam.com'; mail = '' })
            $rows = @((New-MapRow -Action 'Skip'), (New-MapRow -SourceId 's2' -TargetUpn 'taken@fabrikam.com'))
            $out = @(Test-SPIdentityMap -Map $rows)
            $out[0].Status | Should -Be 'Error'
            $out[-1].Status | Should -Be 'OK'
        }
    }

    Context 'Copy-SPIdentity guardrails' {
        BeforeEach {
            $script:DestUsers = @([pscustomobject]@{ id = 'd-bob'; userPrincipalName = 'bob@fabrikam.com'; mail = 'bob@contoso.com' })
            $script:MapCsv = Join-Path $script:Fixture 'map.csv'
            @(
                New-MapRow -SourceId 'src-alice' -SourceUpn 'alice@contoso.com' -Display 'Alice' -TargetUpn 'alice@fabrikam.com'
                New-MapRow -SourceId 'src-bob' -SourceUpn 'bob@contoso.com' -Display 'Bob' -TargetUpn 'bob@fabrikam.com' -Action 'Map' -Matched 'd-bob'
                New-MapRow -Type 'SecurityGroup' -SourceId 'src-ops' -Display 'Ops' -Nick 'ops'
            ) | Export-Csv -Path $script:MapCsv -NoTypeInformation -Encoding utf8
        }

        It 'previews with -WhatIf and performs no writes' {
            $rows = @(Copy-SPIdentity -MapCsv $script:MapCsv -WhatIf)
            @($rows | Where-Object Status -eq 'WouldCopy').Count | Should -Be 2   # alice + ops (bob maps, no work)
            @($script:GraphCalls | Where-Object Method -eq 'POST').Count | Should -Be 0
        }
        It 'honors -WhatIf even when -Force is set' {
            @(Copy-SPIdentity -MapCsv $script:MapCsv -Force -WhatIf) | Out-Null
            @($script:GraphCalls | Where-Object Method -eq 'POST').Count | Should -Be 0
        }
        It 'fails closed on a map that still validates with errors' {
            $bad = Join-Path $script:Fixture 'bad.csv'
            @(New-MapRow -TargetUpn 'alice@unverified.com') | Export-Csv -Path $bad -NoTypeInformation -Encoding utf8
            { Copy-SPIdentity -MapCsv $bad -Force } | Should -Throw '*validation error*'
            @($script:GraphCalls | Where-Object Method -eq 'POST').Count | Should -Be 0
        }
        It 'proceeds past a bad map only with -SkipValidation' {
            $bad = Join-Path $script:Fixture 'bad.csv'
            @(New-MapRow -TargetUpn 'alice@unverified.com') | Export-Csv -Path $bad -NoTypeInformation -Encoding utf8
            @(Copy-SPIdentity -MapCsv $bad -SkipValidation -Force) | Out-Null
            @($script:GraphCalls | Where-Object { $_.Method -eq 'POST' -and $_.Url -eq 'v1.0/users' }).Count | Should -Be 1
        }
        It 'creates users disabled with a force-change password by default' {
            @(Copy-SPIdentity -MapCsv $script:MapCsv -Force) | Out-Null
            $post = @($script:GraphCalls | Where-Object { $_.Method -eq 'POST' -and $_.Url -eq 'v1.0/users' })
            $post.Count | Should -Be 1
            $post[0].Body.accountEnabled | Should -BeFalse
            $post[0].Body.userPrincipalName | Should -Be 'alice@fabrikam.com'
            $post[0].Body.passwordProfile.forceChangePasswordNextSignIn | Should -BeTrue
            $post[0].Body.passwordProfile.password | Should -Not -BeNullOrEmpty
        }
        It 'creates users enabled only with -EnableAccounts' {
            @(Copy-SPIdentity -MapCsv $script:MapCsv -EnableAccounts -Force) | Out-Null
            @($script:GraphCalls | Where-Object { $_.Method -eq 'POST' -and $_.Url -eq 'v1.0/users' })[0].Body.accountEnabled | Should -BeTrue
        }
        It 'invites guests silently unless -SendInvitations is set' {
            $gmap = Join-Path $script:Fixture 'guests.csv'
            @(New-MapRow -Type 'Guest' -SourceId 'src-g' -Mail 'ext@gmail.com' -Action 'Invite') | Export-Csv -Path $gmap -NoTypeInformation -Encoding utf8
            @(Copy-SPIdentity -MapCsv $gmap -Force) | Out-Null
            $inv = @($script:GraphCalls | Where-Object { $_.Method -eq 'POST' -and $_.Url -eq 'v1.0/invitations' })
            $inv.Count | Should -Be 1
            $inv[0].Body.sendInvitationMessage | Should -BeFalse

            $script:GraphCalls.Clear()
            @(Copy-SPIdentity -MapCsv $gmap -SendInvitations -Force) | Out-Null
            @($script:GraphCalls | Where-Object { $_.Method -eq 'POST' -and $_.Url -eq 'v1.0/invitations' })[0].Body.sendInvitationMessage | Should -BeTrue
        }
        It 'membership pass adds only the missing members (convergent re-runs)' {
            $inv = Join-Path $script:Fixture 'inv.csv'
            @(
                New-InvRow -Id 'src-alice' -Upn 'alice@contoso.com' -Display 'Alice'
                New-InvRow -Id 'src-bob' -Upn 'bob@contoso.com' -Display 'Bob'
                New-InvRow -Type 'SecurityGroup' -Id 'src-ops' -Display 'Ops' -Nick 'ops' -Members 'alice@contoso.com;bob@contoso.com'
            ) | Export-Csv -Path $inv -NoTypeInformation -Encoding utf8
            # Bob is already a member at the destination; only Alice should be added.
            $script:Rosters = @{ 'new-group-ops/members' = @([pscustomobject]@{ userPrincipalName = 'bob@fabrikam.com' }) }

            $rows = @(Copy-SPIdentity -MapCsv $script:MapCsv -InventoryCsv $inv -Force)
            $refs = @($script:GraphCalls | Where-Object { $_.Method -eq 'POST' -and $_.Url -like '*/$ref' })
            $refs.Count | Should -Be 1
            $refs[0].Body['@odata.id'] | Should -BeLike '*new-user-alice*'
            $member = @($rows | Where-Object { $_.ObjectType -eq 'Membership' -and $_.Name -like 'Ops*' })[0]
            $member.Detail | Should -Match 'Added 1; already present 1'
        }
        It 'emits a principal map for Copy-SPPermissions (users by UPN, groups by id)' {
            $pmap = Join-Path $script:Fixture 'principals.csv'
            @(Copy-SPIdentity -MapCsv $script:MapCsv -PrincipalMapPath $pmap -Force) | Out-Null
            $pairs = @(Import-Csv -LiteralPath $pmap)
            @($pairs[0].PSObject.Properties.Name) | Should -Be @('Source', 'Destination')
            ($pairs | Where-Object Source -eq 'alice@contoso.com').Destination | Should -Be 'alice@fabrikam.com'
            ($pairs | Where-Object Source -eq 'bob@contoso.com').Destination | Should -Be 'bob@fabrikam.com'
            ($pairs | Where-Object Source -eq 'src-ops').Destination | Should -Be 'new-group-ops'
        }
        It 'throws on a missing map CSV' {
            { Copy-SPIdentity -MapCsv (Join-Path $script:Fixture 'nope.csv') -WhatIf } | Should -Throw '*not found*'
        }
    }
}
