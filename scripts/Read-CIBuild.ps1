[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('List', 'Status', 'Watch', 'FailedLogs', 'Artifacts', 'Evidence', 'Download')]
    [string]$Mode,
    [ValidateRange(0, [long]::MaxValue)]
    [long]$RunId = 0
)

$ErrorActionPreference = 'Stop'
if ($Mode -ne 'List' -and $RunId -lt 1) { throw 'RunId is required for this mode.' }
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskCli = Join-Path $taskRoot '.tools/github-cli/bin/gh.exe'
if (-not (Test-Path -LiteralPath $taskCli)) {
    throw 'Local GitHub CLI missing; install the official CLI under .tools/github-cli first.'
}

# Process-only compatibility for this Windows network; certificate verification remains enabled.
$taskPreviousGoDebug = $env:GODEBUG
try {
    $env:GODEBUG = 'tlsmlkem=0,http2client=0'
    switch ($Mode) {
        'List' {
            & $taskCli run list --repo loliruru/cost-ios --limit 5 --json databaseId,headSha,status,conclusion,url
        }
        'Status' {
            & $taskCli run view $RunId --repo loliruru/cost-ios --json status,conclusion,jobs,url,headSha
        }
        'Watch' {
            & $taskCli run watch $RunId --repo loliruru/cost-ios --exit-status --interval 20
        }
        'FailedLogs' {
            $taskLogLines = & $taskCli run view $RunId --repo loliruru/cost-ios --log-failed 2>&1
            $taskLogExitCode = $LASTEXITCODE
            $taskLogDirectory = Join-Path $taskRoot 'build/ci-logs'
            New-Item -ItemType Directory -Path $taskLogDirectory -Force | Out-Null
            $taskLogLines | Set-Content -LiteralPath (Join-Path $taskLogDirectory "$RunId-failed.log") -Encoding utf8
            $taskLogLines | Select-String -Pattern 'error:|fatal error|BUILD FAILED|##\[error\]' -Context 2, 2
            $global:LASTEXITCODE = $taskLogExitCode
        }
        'Artifacts' {
            & $taskCli api "repos/loliruru/cost-ios/actions/runs/$RunId/artifacts" --jq '.artifacts | map({id,name,size_in_bytes,expired,digest})'
        }
        'Evidence' {
            $taskDestination = Join-Path $taskRoot "build/downloads/$RunId/evidence"
            New-Item -ItemType Directory -Path $taskDestination -Force | Out-Null
            & $taskCli run download $RunId --repo loliruru/cost-ios --pattern 'Cost-build-evidence-*' --dir $taskDestination
        }
        'Download' {
            $taskDestination = Join-Path $taskRoot "build/downloads/$RunId"
            New-Item -ItemType Directory -Path $taskDestination -Force | Out-Null
            & $taskCli run download $RunId --repo loliruru/cost-ios --name Cost-unsigned-ipa --dir (Join-Path $taskDestination 'ipa')
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            & $taskCli run download $RunId --repo loliruru/cost-ios --pattern 'Cost-build-evidence-*' --dir (Join-Path $taskDestination 'evidence')
        }
    }
    $taskExitCode = $LASTEXITCODE
} finally {
    $env:GODEBUG = $taskPreviousGoDebug
}
exit $taskExitCode
