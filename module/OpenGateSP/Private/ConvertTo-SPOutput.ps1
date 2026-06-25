function ConvertTo-SPOutput {
    <#
    .SYNOPSIS
        Shapes operation results for output. By default passes rich objects
        through unchanged; with -AsJson, emits a single JSON array string.
    .NOTES
        Every public function pipes its results through this with its own
        [switch]$AsJson. The JSON path (-AsArray, fixed depth) is the contract
        the future MCP server consumes, so single-item and empty results stay
        valid JSON arrays.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        $InputObject,

        [switch]$AsJson,

        [int]$Depth = 6
    )
    begin {
        $buffer = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -ne $InputObject) { $buffer.Add($InputObject) }
    }
    end {
        if ($AsJson) {
            if ($buffer.Count -eq 0) { return '[]' }
            $buffer | ConvertTo-Json -Depth $Depth -AsArray
        }
        else {
            $buffer
        }
    }
}
