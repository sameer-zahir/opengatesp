# PSScriptAnalyzer configuration (used locally and in CI).
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',                       # this is a console tool; coloured host output is intentional
        'PSAvoidUsingEmptyCatchBlock',                 # best-effort cloud calls deliberately swallow non-fatal errors
        'PSUseBOMForUnicodeEncodedFile',               # PS 7+ only; UTF-8 without BOM is correct here
        'PSUseShouldProcessForStateChangingFunctions', # Connect-SPTool / Set-SPConfig are intentional non-destructive helpers
        'PSUseSingularNouns'                           # false positive on 'Metadata' (a mass noun)
    )
}
