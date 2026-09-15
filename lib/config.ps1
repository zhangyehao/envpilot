function Convert-EnvpilotMessage {
    param([string]$Message)
    $language = if ($env:ENVPILOT_LANG -and $env:ENVPILOT_LANG -ne 'auto') { $env:ENVPILOT_LANG } elseif ($Lang) { $Lang } else { [Globalization.CultureInfo]::CurrentUICulture.Name }
    $core = Join-Path $Script:Root 'bin/envpilot-core.exe'
    if ($language -like 'zh*' -and (Test-Path -LiteralPath $core)) {
        $OutputEncoding = [Text.UTF8Encoding]::new($false)
        $previousConsoleEncoding = [Console]::OutputEncoding
        try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); return ($Message | & $core message --lang zh-CN | Out-String).TrimEnd() }
        finally { [Console]::OutputEncoding = $previousConsoleEncoding }
    }
    return $Message
}

function Get-EnvpilotProfileTarget {
    if ($env:ENVPILOT_PROFILE) { return $env:ENVPILOT_PROFILE }
    if ($PROFILE.CurrentUserCurrentHost) { return $PROFILE.CurrentUserCurrentHost }
    $directory = if ($PSVersionTable.PSEdition -eq 'Core') { 'PowerShell' } else { 'WindowsPowerShell' }
    return Join-Path $HOME "Documents/$directory/Microsoft.PowerShell_profile.ps1"
}

function Get-EnvpilotCore {
    $version = (Get-Content -LiteralPath (Join-Path $Script:Root 'VERSION') -Raw).Trim()
    $installed = Join-Path $HOME ".local/lib/envpilot/$version/envpilot-core.exe"
    foreach ($candidate in @($env:ENVPILOT_CORE, (Join-Path $Script:Root 'bin/envpilot-core.exe'), $installed)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    if ($Mode -eq 'offline' -or (-not $Script:ExplicitParameters.ContainsKey('Mode') -and $env:ENVPILOT_MODE -eq 'offline')) { throw 'Offline configuration requires the complete envpilot platform package.' }
    $arch = if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'arm64' } else { 'amd64' }
    $name = "envpilot-core-$version-windows-$arch.exe"
    $base = "https://github.com/zhangyehao/envpilot/releases/download/v$version"
    $binaryUrl = "$base/$name"
    $checksumUrl = "$base/SHA256SUMS"
    if ($env:ENVPILOT_RELEASE_SOURCE -eq 'gitee') {
        $api = 'https://gitee.com/api/v5/repos/zhangyehao0422/envpilot'
        $release = Invoke-RestMethod "$api/releases/tags/v$version"
        if ($release.tag_name -ne "v$version") { throw 'Gitee release tag mismatch.' }
        $assets = Invoke-RestMethod "$api/releases/$($release.id)/attach_files?per_page=100"
        $binaryAsset = $assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
        $checksumAsset = $assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1
        if (-not $binaryAsset -or -not $checksumAsset) { throw 'Required Gitee release attachments are missing.' }
        $binaryUrl = "$api/releases/$($release.id)/attach_files/$($binaryAsset.id)/download"
        $checksumUrl = "$api/releases/$($release.id)/attach_files/$($checksumAsset.id)/download"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $installed) | Out-Null
    $temp = "$installed.download-$([guid]::NewGuid().ToString('N'))"
    try {
        Invoke-WebRequest $binaryUrl -OutFile $temp
        Invoke-WebRequest $checksumUrl -OutFile "$temp.sha256"
        $sums = Get-Content -LiteralPath "$temp.sha256" -Raw
        $line = ($sums -split "`n" | Where-Object { ($_ -split '\s+')[1] -eq $name } | Select-Object -First 1)
        $expected = ($line -split '\s+')[0]
        if (-not $expected -or (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash -ne $expected) { throw 'envpilot-core checksum verification failed.' }
        Move-Item -LiteralPath $temp -Destination $installed -Force
        if ((& $installed version) -ne $version) { throw 'envpilot-core version mismatch.' }
    } finally { Remove-Item -LiteralPath $temp,"$temp.sha256" -ErrorAction SilentlyContinue }
    return $installed
}

function Invoke-EnvpilotCore {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$CoreArgs)
    $core = Get-EnvpilotCore
    $overrides = @{}
    foreach ($entry in @{ Mode='ENVPILOT_MODE'; Prefix='ENVPILOT_PREFIX'; Lang='ENVPILOT_LANG' }.GetEnumerator()) {
        if ($Script:ExplicitParameters.ContainsKey($entry.Key)) { $overrides[$entry.Value] = [string]$Script:ExplicitParameters[$entry.Key] }
    }
    $env:ENVPILOT_OVERRIDES = ConvertTo-Json -Compress $overrides
    $configPath = if ($Config) { $Config } else { Join-Path $Script:ConfigDir 'config.yaml' }
    $previousConsoleEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        & $core @CoreArgs --config $configPath --root $Script:Root
        if ($LASTEXITCODE -ne 0) { throw "envpilot-core failed ($LASTEXITCODE)." }
    } finally { [Console]::OutputEncoding = $previousConsoleEncoding }
}

function Import-EnvpilotConfig {
    $overrides = @{}
    foreach ($entry in @{ Mode='ENVPILOT_MODE'; Prefix='ENVPILOT_PREFIX'; Lang='ENVPILOT_LANG' }.GetEnumerator()) {
        if ($Script:ExplicitParameters.ContainsKey($entry.Key)) { $overrides[$entry.Value] = [string]$Script:ExplicitParameters[$entry.Key] }
    }
    $env:ENVPILOT_OVERRIDES = ConvertTo-Json -Compress $overrides
    $values = Invoke-EnvpilotCore export | ConvertFrom-Json
    foreach ($property in $values.PSObject.Properties) {
        $Script:PreviousEnv[$property.Name] = [Environment]::GetEnvironmentVariable($property.Name)
        [Environment]::SetEnvironmentVariable($property.Name, [string]$property.Value)
    }
    $Script:Mode = $values.EP_MODE
    $Script:Prefix = $values.EP_PREFIX
    $Script:ResolvedConfig = $values
}

function Save-EnvpilotSnapshot {
    $snapshot = Invoke-EnvpilotCore snapshot --target (Get-EnvpilotProfileTarget)
    Write-Info "Snapshot: $snapshot"
}

function Install-EnvpilotCommand {
    $target = Join-Path $HOME '.local/bin/envpilot.ps1'
    if (Test-Path -LiteralPath $target) {
        if (-not (Select-String -LiteralPath $target -SimpleMatch '# envpilot-managed-command' -Quiet)) { throw "Existing unrelated command preserved: $target" }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target), $Script:ConfigDir | Out-Null
    Backup-File $target
    Backup-File (Join-Path $Script:ConfigDir 'command-root')
    [IO.File]::WriteAllText((Join-Path $Script:ConfigDir 'command-root'), $Script:Root + "`n", [Text.UTF8Encoding]::new($false))
    $registry = (Join-Path $Script:ConfigDir 'command-root').Replace("'", "''")
    $wrapper = @"
# envpilot-managed-command
`$root = (Get-Content -LiteralPath '$registry' -Raw).Trim()
if (-not (Test-Path -LiteralPath (Join-Path `$root 'envpilot.ps1'))) { throw 'envpilot registration is unavailable; rerun setup-command.' }
& (Join-Path `$root 'envpilot.ps1') @args
exit `$LASTEXITCODE
"@
    [IO.File]::WriteAllText($target, $wrapper, [Text.UTF8Encoding]::new($true))
    Invoke-EnvpilotCore install-core
    Write-Info "Installed envpilot command: $target"
}

function Apply-EnvpilotConfig {
    Invoke-EnvpilotCore plan
    Invoke-EnvpilotCore preflight
    if (-not $Yes -and -not (Confirm-Step 'Apply this configuration?' $false)) { return }
    Save-EnvpilotSnapshot
    $Script:ConfigApply = $true
    foreach ($name in @('mihomo','git','python','conda','mamba','codex','github','tmux')) {
        if ($name -in ($Script:ResolvedConfig.ENVPILOT_COMPONENTS -split ' ')) { Install-One $name }
    }
    if ($Script:ResolvedConfig.ENVPILOT_SHELL_ENABLED -eq '1') { Apply-ShellProfile }
    if ($Script:ResolvedConfig.ENVPILOT_CODEX_ENABLED -eq '1') { Write-Warn 'Codex node-local remote management requires the Unix entrypoint.' }
    Save-Report 'apply' 'configured'
}

function Update-EnvpilotSelf {
    if (-not (Test-Path -LiteralPath (Join-Path $Script:Root '.git'))) { Invoke-EnvpilotCore self-update; return }
    if (git -C $Script:Root status --porcelain) { throw 'Save local changes before self-update.' }
    git -C $Script:Root fetch origin --tags
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch releases.' }
    $tag = git -C $Script:Root tag --list 'v[0-9]*' --sort=-version:refname | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' } | Select-Object -First 1
    if (-not $tag) { throw 'No stable release found.' }
    git -C $Script:Root merge-base --is-ancestor HEAD $tag
    if ($LASTEXITCODE -ne 0) { throw 'Checkout is ahead of or diverged from the release; files were preserved.' }
    Save-EnvpilotSnapshot
    git -C $Script:Root merge --ff-only $tag
    if ($LASTEXITCODE -ne 0) { throw 'Fast-forward update failed.' }
    Install-EnvpilotCommand
    $Script:ConfigApply = $true
    Apply-ShellProfile
}

function Get-EnvpilotSubscription {
    if ($env:ENVPILOT_MIHOMO_SUBSCRIPTION_URL) { return $env:ENVPILOT_MIHOMO_SUBSCRIPTION_URL }
    if ($env:ENVPILOT_SUBSCRIPTION_ENV) { $value = [Environment]::GetEnvironmentVariable($env:ENVPILOT_SUBSCRIPTION_ENV); if ($value) { return $value } }
    $file = if ($env:ENVPILOT_SUBSCRIPTION_FILE) { $env:ENVPILOT_SUBSCRIPTION_FILE } else { Join-Path $HOME '.config/mihomo/subscription.url' }
    if (Test-Path -LiteralPath $file) { return (Get-Content -LiteralPath $file -Raw).Trim() }
    return ''
}

function Invoke-EnvpilotProtectedDownload {
    param([Parameter(ValueFromPipeline=$true)][string]$Url, [string]$Destination)
    process {
        $OutputEncoding = [Text.UTF8Encoding]::new($false)
        $Url | & (Get-EnvpilotCore) protected-download --target $Destination
        if ($LASTEXITCODE -ne 0) { throw 'Protected subscription download failed.' }
    }
}
