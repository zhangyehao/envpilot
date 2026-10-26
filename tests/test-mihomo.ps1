param([switch]$Child, [string]$Fixture, [string]$CorePath)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

function Assert-FixturePath {
    param([string]$Path, [string]$FixtureRoot)
    $resolved = [IO.Path]::GetFullPath($Path)
    $fixtureResolved = [IO.Path]::GetFullPath($FixtureRoot)
    $temporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $fixtureResolved.StartsWith($temporary, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $fixtureResolved) -notlike 'envpilot-mihomo-*') {
        throw 'Unsafe Mihomo fixture root.'
    }
    $prefix = $fixtureResolved.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($resolved -ne $fixtureResolved -and -not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Path is outside the Mihomo fixture.'
    }
}

function Stop-FixtureProcesses {
    param([string]$FixtureRoot)
    $binary = Join-Path $FixtureRoot 'software/mihomo/mihomo.exe'
    Assert-FixturePath -Path $binary -FixtureRoot $FixtureRoot
    foreach ($candidate in @(Get-Process -Name mihomo -ErrorAction SilentlyContinue)) {
        try {
            if ($candidate.Path -ne $binary) { continue }
            $current = Get-Process -Id $candidate.Id -ErrorAction Stop
            if ($current.Path -ne $binary) { continue }
            Stop-Process -Id $current.Id -Force
            $current.WaitForExit(5000) | Out-Null
        } catch {
            if (Get-Process -Id $candidate.Id -ErrorAction SilentlyContinue) { throw }
        }
    }
}

if (-not $Child) {
    $fixturePath = Join-Path ([IO.Path]::GetTempPath()) ('envpilot-mihomo-fixture with spaces-' + [guid]::NewGuid().ToString('N'))
    Assert-FixturePath -Path $fixturePath -FixtureRoot $fixturePath
    $previousProfile = $env:USERPROFILE
    try {
        New-Item -ItemType Directory -Path $fixturePath | Out-Null
        $env:USERPROFILE = $fixturePath
        $executable = (Get-Process -Id $PID).Path
        $childArgs = @('-NoProfile', '-File', $PSCommandPath, '-Child', '-Fixture', $fixturePath)
        if ($CorePath) { $childArgs += @('-CorePath', $CorePath) }
        & $executable @childArgs
        if ($LASTEXITCODE -ne 0) { throw 'Mihomo integration test failed.' }
    } finally {
        $env:USERPROFILE = $previousProfile
        Stop-FixtureProcesses -FixtureRoot $fixturePath
        Assert-FixturePath -Path $fixturePath -FixtureRoot $fixturePath
        Remove-Item -LiteralPath $fixturePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    return
}

Assert-FixturePath -Path $Fixture -FixtureRoot $Fixture
if ([IO.Path]::GetFullPath($HOME) -ne [IO.Path]::GetFullPath($Fixture)) { throw 'Test did not isolate HOME.' }
# The test uses a real process, so refuse older adapters which matched unrelated
# installations through a broad software/mihomo path pattern.
if ((Get-Content -LiteralPath (Join-Path $Root 'envpilot.ps1') -Raw) -match '\.Path\s+-like\s+"\*\\software\\mihomo\\mihomo\.exe"') {
    throw 'Mihomo process matching is not isolated to the configured binary.'
}
foreach ($entry in @(Get-ChildItem Env: | Where-Object { $_.Name -match '^(ENVPILOT_|MIHOMO_|BASHRC_|EP_)' })) {
    Remove-Item -LiteralPath ('Env:' + $entry.Name) -ErrorAction SilentlyContinue
}
$env:ENVPILOT_CONFIG_DIR = Join-Path $HOME '.config/envpilot'
$env:ENVPILOT_CORE = if ($CorePath) { $CorePath } else { Join-Path $Root 'bin/envpilot-core.exe' }
$env:ENVPILOT_MODE = 'offline'
$env:HTTP_PROXY = 'http://127.0.0.1:1'
$env:HTTPS_PROXY = 'http://127.0.0.1:1'
$env:ALL_PROXY = 'socks5://127.0.0.1:1'
$powershell = (Get-Process -Id $PID).Path
$entrypoint = Join-Path $Root 'envpilot.ps1'
$binaryDirectory = Join-Path $HOME 'software/mihomo'
$binary = Join-Path $binaryDirectory 'mihomo.exe'
$configDirectory = Join-Path $HOME 'custom config'
$configFile = Join-Path $configDirectory 'envpilot.yaml'
$source = Join-Path $HOME 'subscription.yaml'
$candidate = Join-Path $HOME 'candidate.yaml'
$active = Join-Path $HOME '.config/mihomo/config.yaml'
$secret = 'envpilot-fixture-secret-not-real'
$group = '验收 / Group With Spaces'
$utf8 = [Text.UTF8Encoding]::new($false)
$reservations = @()

function Invoke-FixtureEnvpilot {
    param([string[]]$Arguments, [switch]$ExpectFailure)
    $output = (& $powershell -NoProfile -File $entrypoint @Arguments -Config $configFile -NonInteractive 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
    if ($output.Contains($secret)) { throw 'Mihomo command exposed its controller credential.' }
    if ($ExpectFailure) {
        if ($exitCode -eq 0) { throw "Expected failure: $($Arguments -join ' ')" }
    } elseif ($exitCode -ne 0) {
        throw "Fixture command failed: $($Arguments -join ' ')`n$output"
    }
    return $output
}

function Get-FixtureProcesses {
    return @(Get-Process -Name mihomo -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -eq $binary } catch { $false }
    })
}

function Assert-FixtureStopped {
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if (@(Get-FixtureProcesses).Count -eq 0) { return }
        Start-Sleep -Milliseconds 100
    }
    throw 'Fixture Mihomo is still running.'
}

function Assert-FixtureSelection {
    param([string]$Expected, [bool]$Running = $true)
    $result = Invoke-FixtureEnvpilot -Arguments @('mihomo', 'nodes', $group, '-Json') | ConvertFrom-Json
    if ([bool]$result.running -ne $Running) { throw 'Mihomo running state was reported incorrectly.' }
    if ($result.groups.Count -ne 1 -or $result.groups[0].name -ne $group) { throw 'Custom group was lost.' }
    if ($Running -and $result.groups[0].now -ne $Expected) { throw 'Mihomo did not retain the requested node.' }
    if ($result.groups[0].all -notcontains 'REJECT') { throw 'Node list is incomplete.' }
}

try {
    foreach ($directory in @($binaryDirectory, $configDirectory, $env:ENVPILOT_CONFIG_DIR)) {
        Assert-FixturePath -Path $directory -FixtureRoot $Fixture
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $archives = @(Get-ChildItem -LiteralPath (Join-Path $Root 'downloads') -Filter 'mihomo-windows-amd64-compatible-v*.zip')
    if ($archives.Count -ne 1) { throw 'Expected one bundled Windows amd64 Mihomo archive.' }
    $archive = $archives[0].FullName
    $unpacked = Join-Path $HOME 'unpacked'
    Assert-FixturePath -Path $unpacked -FixtureRoot $Fixture
    Expand-Archive -LiteralPath $archive -DestinationPath $unpacked
    $cachedBinary = Join-Path $unpacked 'mihomo-windows-amd64-compatible.exe'
    Assert-FixturePath -Path $cachedBinary -FixtureRoot $Fixture
    Assert-FixturePath -Path $binary -FixtureRoot $Fixture
    Move-Item -LiteralPath $cachedBinary -Destination $binary

    # Reserve distinct random loopback ports together, then release immediately
    # before starting the fixture. No globally configured ports are used.
    foreach ($unused in 1..2) {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $reservations += $listener
    }
    $proxyPort = $reservations[0].LocalEndpoint.Port
    $apiPort = $reservations[1].LocalEndpoint.Port
    $customPrefix = (Join-Path $HOME 'other component prefix').Replace('\', '/').Replace("'", "''")
    [IO.File]::WriteAllText($configFile, @"
version: 1
language: en
install:
  mode: offline
  prefix: '$customPrefix'
mihomo:
  proxy_port: $proxyPort
  api_port: $apiPort
  subscription_network: direct
"@, $utf8)
    # Every command must respect -Config instead of loading this invalid default.
    [IO.File]::WriteAllText((Join-Path $env:ENVPILOT_CONFIG_DIR 'config.yaml'), "invalid: [`n", $utf8)
    $subscription = @"
mode: rule
log-level: error
ipv6: false
secret: $secret
profile:
  store-selected: false
dns:
  enable: false
proxies: []
proxy-groups:
  - name: '$group'
    type: select
    proxies: [DIRECT, REJECT]
rules:
  - 'MATCH,$group'
"@
    [IO.File]::WriteAllText($source, $subscription, $utf8)
    foreach ($listener in $reservations) { $listener.Stop() }
    $reservations = @()

    Write-Output '[TEST] stopped import, custom config and non-default component prefix'
    Invoke-FixtureEnvpilot -Arguments @('mihomo', 'update-subscription', '-SubscriptionFile', $source) | Out-Null
    Assert-FixtureStopped
    Assert-FixtureSelection -Expected '' -Running $false
    $missingInput = Invoke-FixtureEnvpilot -Arguments @('mihomo', 'select') -ExpectFailure
    if ($missingInput -notmatch 'E_INPUT_REQUIRED') { throw 'Non-interactive selection did not fail before prompting.' }
    Assert-FixtureStopped

    Write-Output '[TEST] authenticated real controller, selection and restart persistence'
    Invoke-FixtureEnvpilot -Arguments @('mihomo', 'start') | Out-Null
    # Every helper invocation starts fresh ownership-checking PowerShell
    # processes. Successful health must therefore include both ownership
    # checks within the controller client's ten-second request timeout.
    $healthClock = [Diagnostics.Stopwatch]::StartNew()
    $healthOutput = (& $env:ENVPILOT_CORE mihomo --config $configFile -- health 2>&1 | Out-String)
    $healthExitCode = $LASTEXITCODE
    $healthClock.Stop()
    if ($healthOutput.Contains($secret)) { throw 'Mihomo health exposed its controller credential.' }
    if ($healthExitCode -ne 0) { throw "Fresh controller ownership checks failed: $healthOutput" }
    Write-Output ('[TEST] fresh helper health with both owner checks completed in {0:N3}s' -f $healthClock.Elapsed.TotalSeconds)
    Assert-FixtureSelection -Expected 'DIRECT'
    $running = @(Get-FixtureProcesses)
    if ($running.Count -ne 1) { throw 'Expected exactly one fixture Mihomo process.' }
    $firstPid = $running[0].Id
    Invoke-FixtureEnvpilot -Arguments @('mihomo', 'select', $group, 'REJECT') | Out-Null
    Assert-FixtureSelection -Expected 'REJECT'
    $stateFiles = @(Get-ChildItem -LiteralPath (Join-Path $env:ENVPILOT_CONFIG_DIR 'mihomo-selections') -Filter '*.json')
    if ($stateFiles.Count -ne 1) { throw 'Node-scoped selection state was not saved.' }
    $state = Get-Content -LiteralPath $stateFiles[0].FullName -Raw | ConvertFrom-Json
    if ($state.selections.$group -ne 'REJECT') { throw 'Persisted selection disagrees with the controller.' }
    Invoke-FixtureEnvpilot -Arguments @('mihomo', 'restart') | Out-Null
    Assert-FixtureSelection -Expected 'REJECT'
    $running = @(Get-FixtureProcesses)
    if ($running.Count -ne 1 -or $running[0].Id -eq $firstPid) { throw 'Restart did not replace the fixture process.' }

    Write-Output '[TEST] native validation failure preserves active configuration and process'
    $beforeHash = (Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash
    $beforePid = $running[0].Id
    $invalid = $subscription.Replace('proxies: []', "proxies:`n  - name: InvalidFixture`n    type: envpilot-invalid-proxy-type")
    [IO.File]::WriteAllText($candidate, $invalid, $utf8)
    $failure = Invoke-FixtureEnvpilot -Arguments @('mihomo', 'update-subscription', '-SubscriptionFile', $candidate) -ExpectFailure
    if ($failure -notmatch 'E_MIHOMO_CONFIG') { throw 'Candidate was not rejected by native Mihomo validation.' }
    if ((Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash -ne $beforeHash) { throw 'Invalid candidate replaced active configuration.' }
    $running = @(Get-FixtureProcesses)
    if ($running.Count -ne 1 -or $running[0].Id -ne $beforePid) { throw 'Validation failure changed the running service.' }
    Assert-FixtureSelection -Expected 'REJECT'

    Write-Output '[TEST] subscription replacement preserves selection and stopped state'
    [IO.File]::WriteAllText($candidate, $subscription.Replace('log-level: error', 'log-level: warning'), $utf8)
    Invoke-FixtureEnvpilot -Arguments @('mihomo', 'update-subscription', '-SubscriptionFile', $candidate) | Out-Null
    Assert-FixtureSelection -Expected 'REJECT'
    $running = @(Get-FixtureProcesses)
    if ($running.Count -ne 1 -or $running[0].Id -eq $beforePid) { throw 'Running subscription update did not replace the process.' }
    Invoke-FixtureEnvpilot -Arguments @('mihomo', 'stop') | Out-Null
    Assert-FixtureStopped
    Invoke-FixtureEnvpilot -Arguments @('mihomo', 'update-subscription', '-SubscriptionFile', $source) | Out-Null
    Assert-FixtureStopped
    Invoke-FixtureEnvpilot -Arguments @('mihomo', 'start') | Out-Null
    Assert-FixtureSelection -Expected 'REJECT'
    Invoke-FixtureEnvpilot -Arguments @('mihomo', 'stop') | Out-Null
    Assert-FixtureStopped
    Write-Output '[TEST] real Windows Mihomo lifecycle and protected local imports passed'
} finally {
    foreach ($listener in $reservations) { $listener.Stop() }
    Stop-FixtureProcesses -FixtureRoot $Fixture
}
