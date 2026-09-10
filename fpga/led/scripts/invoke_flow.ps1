[CmdletBinding()]
param(
    [ValidateSet('ad9517')]
    [string]$Module = 'ad9517',

    [Parameter(Mandatory)]
    [ValidateSet('sim', 'build', 'hardware', 'diagnose')]
    [string]$Stage,

    [switch]$ForceRebuild,
    [switch]$PreflightOnly,

    [string]$VivadoBat = 'D:\Xilinx\Vivado\2021.1\bin\vivado.bat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-PropertyFile {
    param([Parameter(Mandatory)][string]$Path)

    $values = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $values
    }
    foreach ($line in Get-Content -LiteralPath $Path) {
        $pair = $line -split '=', 2
        if ($pair.Count -eq 2 -and $pair[0].Length -gt 0) {
            $values[$pair[0]] = $pair[1]
        }
    }
    return $values
}

function Get-ArtifactIdentity {
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-Item -LiteralPath $Path
    [ordered]@{
        path          = $item.FullName
        sha256        = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        length        = $item.Length
        lastWriteTime = $item.LastWriteTime.ToString('o')
    }
}

function Assert-ArtifactIdentity {
    param(
        [Parameter(Mandatory)]$Artifact,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not (Test-Path -LiteralPath $Artifact.path -PathType Leaf)) {
        throw "$Name artifact is missing: $($Artifact.path)"
    }
    $actual = (Get-FileHash -LiteralPath $Artifact.path -Algorithm SHA256).Hash
    if ($actual -ne $Artifact.sha256) {
        throw "$Name artifact hash changed after signoff: $($Artifact.path)"
    }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$projectDir = Split-Path -Parent $scriptRoot
$stageScript = Join-Path $scriptRoot "modules\$Module\$Stage.tcl"
$logRoot = Join-Path $projectDir "logs\$Module\$Stage"
$lockPath = Join-Path $projectDir 'logs\.cowork-vivado.lock'
$expectedResults = @{
    sim      = 'AD9517_SIM_PASS'
    build    = 'AD9517_BUILD_PASS'
    hardware = 'AD9517_PROGRAM_AND_CAPTURE_PASS'
    diagnose = 'AD9517_DIAGNOSE_PASS'
}
$effectiveForceRebuild = [bool]$ForceRebuild
if ($PreflightOnly -and $Stage -ne 'hardware') {
    throw '-PreflightOnly is supported only by the hardware stage'
}
$expectedResult = if ($PreflightOnly) { 'AD9517_HARDWARE_PREFLIGHT_PASS' } else { $expectedResults[$Stage] }

if (-not (Test-Path -LiteralPath $VivadoBat -PathType Leaf)) {
    throw "Vivado launcher is missing: $VivadoBat"
}
if (-not (Test-Path -LiteralPath $stageScript -PathType Leaf)) {
    throw "Stage script is missing: $stageScript"
}

# A reusable build must still point to the exact signed-off artifacts.  If a
# previous bit/LTX was edited or replaced, force a clean rebuild instead of
# accepting and re-signing the changed file.
if ($Stage -eq 'build' -and -not $effectiveForceRebuild) {
    $previousBuildManifestPath = Join-Path $projectDir "logs\$Module\build\latest_success.json"
    if (Test-Path -LiteralPath $previousBuildManifestPath -PathType Leaf) {
        try {
            $previousBuild = Get-Content -LiteralPath $previousBuildManifestPath -Raw | ConvertFrom-Json
            if ($previousBuild.exitCode -ne 0 -or $previousBuild.result.RESULT -ne $expectedResults.build) {
                throw 'previous build manifest is not accepted'
            }
            Assert-ArtifactIdentity -Artifact $previousBuild.artifacts.bitstream -Name 'bitstream'
            Assert-ArtifactIdentity -Artifact $previousBuild.artifacts.probes -Name 'LTX'
        }
        catch {
            Write-Warning "Previous build artifacts cannot be reused: $($_.Exception.Message)"
            $effectiveForceRebuild = $true
        }
    }
}

# Hardware is allowed to consume only the exact bit/LTX pair recorded by the
# latest successful build.  This check occurs before any Hardware Manager call.
if ($Stage -eq 'hardware') {
    $buildManifestPath = Join-Path $projectDir "logs\$Module\build\latest_success.json"
    if (-not (Test-Path -LiteralPath $buildManifestPath -PathType Leaf)) {
        throw "No accepted build manifest exists: $buildManifestPath"
    }
    $buildManifest = Get-Content -LiteralPath $buildManifestPath -Raw | ConvertFrom-Json
    if ($buildManifest.exitCode -ne 0 -or $buildManifest.result.RESULT -ne $expectedResults.build) {
        throw "The latest build manifest is not a successful signed-off build"
    }
    Assert-ArtifactIdentity -Artifact $buildManifest.artifacts.bitstream -Name 'bitstream'
    Assert-ArtifactIdentity -Artifact $buildManifest.artifacts.probes -Name 'LTX'
}

# A GUI Vivado process is allowed because led.xpr is the shared GUI project.
# Another batch/Tcl worker is not allowed to race this invocation.
$workers = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -ieq 'vivado.exe' -and $_.CommandLine -match '-mode\s+(batch|tcl)'
})
if ($workers.Count -ne 0) {
    $details = ($workers | ForEach-Object { "PID=$($_.ProcessId) $($_.CommandLine)" }) -join [Environment]::NewLine
    throw "Another Vivado batch/Tcl worker is active:`n$details"
}

$runId = '{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), $PID
$runDir = Join-Path $logRoot $runId
$vivadoLog = Join-Path $runDir 'vivado.log'
$vivadoJournal = Join-Path $runDir 'vivado.jou'
$resultPath = Join-Path $runDir 'result.properties'
$manifestPath = Join-Path $runDir 'manifest.json'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $lockPath) -Force | Out-Null

$lockStream = $null
$oldRunId = [Environment]::GetEnvironmentVariable('COWORK_RUN_ID', 'Process')
$oldRunDir = [Environment]::GetEnvironmentVariable('COWORK_RUN_DIR', 'Process')
$oldForce = [Environment]::GetEnvironmentVariable('COWORK_FORCE_REBUILD', 'Process')
$oldPreflight = [Environment]::GetEnvironmentVariable('COWORK_PREFLIGHT_ONLY', 'Process')
$startedAt = (Get-Date).ToString('o')
$exitCode = 1

try {
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        $stale = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
        if (Get-Process -Id $stale.pid -ErrorAction SilentlyContinue) {
            throw "Vivado collaboration lock is held by PID $($stale.pid), stage $($stale.stage)"
        }
        Remove-Item -LiteralPath $lockPath -Force
    }

    $lockStream = [System.IO.File]::Open(
        $lockPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None)
    $lockText = ([ordered]@{
        pid       = $PID
        module    = $Module
        stage     = $Stage
        startedAt = $startedAt
        runDir    = $runDir
    } | ConvertTo-Json -Compress)
    $lockBytes = [System.Text.Encoding]::UTF8.GetBytes($lockText)
    $lockStream.Write($lockBytes, 0, $lockBytes.Length)
    $lockStream.Flush()

    $env:COWORK_RUN_ID = $runId
    $env:COWORK_RUN_DIR = $runDir
    $env:COWORK_FORCE_REBUILD = if ($effectiveForceRebuild) { '1' } else { '0' }
    $env:COWORK_PREFLIGHT_ONLY = if ($PreflightOnly) { '1' } else { '0' }

    Write-Host "FLOW_START module=$Module stage=$Stage run=$runId"
    & $VivadoBat -mode batch -source $stageScript -log $vivadoLog -journal $vivadoJournal
    $exitCode = $LASTEXITCODE
}
finally {
    if ($null -ne $lockStream) {
        $lockStream.Dispose()
    }
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        Remove-Item -LiteralPath $lockPath -Force
    }

    foreach ($entry in @(
        @{ Name = 'COWORK_RUN_ID'; Value = $oldRunId },
        @{ Name = 'COWORK_RUN_DIR'; Value = $oldRunDir },
        @{ Name = 'COWORK_FORCE_REBUILD'; Value = $oldForce },
        @{ Name = 'COWORK_PREFLIGHT_ONLY'; Value = $oldPreflight })) {
        if ($null -eq $entry.Value) {
            Remove-Item -LiteralPath "Env:$($entry.Name)" -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($entry.Name, $entry.Value, 'Process')
        }
    }
}

$result = Read-PropertyFile -Path $resultPath
$artifacts = [ordered]@{}
if ($result.Contains('BITSTREAM') -and (Test-Path -LiteralPath $result.BITSTREAM -PathType Leaf)) {
    $artifacts.bitstream = Get-ArtifactIdentity -Path $result.BITSTREAM
}
if ($result.Contains('LTX') -and (Test-Path -LiteralPath $result.LTX -PathType Leaf)) {
    $artifacts.probes = Get-ArtifactIdentity -Path $result.LTX
}
if ($result.Contains('ILA_DATA') -and (Test-Path -LiteralPath $result.ILA_DATA -PathType Leaf)) {
    $artifacts.ilaData = Get-ArtifactIdentity -Path $result.ILA_DATA
}
if ($result.Contains('ILA_CSV') -and (Test-Path -LiteralPath $result.ILA_CSV -PathType Leaf)) {
    $artifacts.ilaCsv = Get-ArtifactIdentity -Path $result.ILA_CSV
}

$manifest = [ordered]@{
    schemaVersion = 1
    runId          = $runId
    module         = $Module
    stage          = $Stage
    startedAt      = $startedAt
    finishedAt     = (Get-Date).ToString('o')
    exitCode       = $exitCode
    vivadoLog      = $vivadoLog
    vivadoJournal  = $vivadoJournal
    result          = $result
    artifacts       = $artifacts
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$accepted = $exitCode -eq 0 -and $result.Contains('RESULT') -and $result.RESULT -eq $expectedResult
if ($accepted) {
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $latestStem = if ($PreflightOnly) { 'latest_preflight' } else { 'latest_success' }
    Copy-Item -LiteralPath $resultPath -Destination (Join-Path $logRoot "$latestStem.properties") -Force
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $logRoot "$latestStem.json") -Force
}

Write-Host "FLOW_RESULT accepted=$accepted exitCode=$exitCode"
Write-Host "RUN_DIR=$runDir"
Write-Host "MANIFEST=$manifestPath"
if (-not $accepted) {
    exit $(if ($exitCode -ne 0) { $exitCode } else { 1 })
}
exit 0
