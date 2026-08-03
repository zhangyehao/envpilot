[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet("doctor","install","update","upgrade","apply-shell","rollback","restore","mihomo","resume","reset","update-manifests","update-mihomo-cache","self-test","help")]
    [string]$Command = "help",

    [Parameter(Position=1)]
    [string]$Component = "all",

    [Parameter(Position=2)]
    [string]$Value,

    [Parameter(Position=3)]
    [string]$Value2,

    [ValidateSet("online","offline")]
    [string]$Mode = "online",

    [string]$Prefix = (Join-Path $HOME "software"),
    [string]$AssetPath,
    [switch]$Yes,
    [switch]$Upgrade
)

$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:ConfigDir = if ($env:ENVPILOT_CONFIG_DIR) { $env:ENVPILOT_CONFIG_DIR } else { Join-Path $HOME ".config/envpilot" }
$Script:StateFile = Join-Path $Script:ConfigDir "state.ps1.txt"
$Script:RollbackLog = Join-Path $Script:ConfigDir "rollback.ps1.tsv"
$Script:BaselineDir = Join-Path $Script:ConfigDir "baseline"
$Script:BaselineFile = Join-Path $Script:BaselineDir "baseline.tsv"
$Script:RepoRootFile = Join-Path $Script:ConfigDir "repo-root"
$Script:ReportFile = Join-Path $Script:ConfigDir "install-report.json"
$Script:RunId = Get-Date -Format "yyyyMMddHHmmss"
$Script:Upgrade = $Upgrade.IsPresent
$Script:Events = @()
$Script:Platform = $null

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" }
function Write-Warn { param([string]$Message) Write-Warning $Message }
function Stop-Envpilot { param([string]$Message) throw "[ERROR] $Message" }

function Initialize-Envpilot {
    New-Item -ItemType Directory -Force -Path $Script:ConfigDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Script:ConfigDir "logs") | Out-Null
    [System.IO.File]::WriteAllText($Script:RepoRootFile, $Script:Root + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Test-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-EnvpilotPlatform {
    $arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
        "X64" { "amd64" }
        "Arm64" { "arm64" }
        default { $_.ToLowerInvariant() }
    }
    [pscustomobject]@{
        OS = "windows"
        Arch = $arch
        Shell = "powershell"
        IsRoot = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Prefix = $Prefix
    }
}

function Confirm-Step {
    param([string]$Prompt, [bool]$DefaultYes = $false)
    if ($Yes -and $DefaultYes) { return $true }
    $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $answer = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
        switch -Regex ($answer) {
            "^(y|yes)$" { return $true }
            "^(n|no)$" { return $false }
            default { Write-Host "Please answer yes or no." }
        }
    }
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $backup = "$Path.bak.$Script:RunId"
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    "$Path`t$backup" | Add-Content -LiteralPath $Script:RollbackLog
    Write-Info "Backed up $Path -> $backup"
}

function Add-ReportEvent {
    param([string]$Component, [string]$Status, [string]$Message, [string]$Version = "", [string]$Source = "", [string]$Path = "")
    $Script:Events += [pscustomobject]@{
        component = $Component
        status = $Status
        message = $Message
        version = $Version
        source = $Source
        path = $Path
        time = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
}

function Save-Report {
    param([string]$Action, [string]$RequestedComponent)
    $report = [pscustomobject]@{
        run_id = $Script:RunId
        action = $Action
        requested_component = $RequestedComponent
        mode = $Mode
        prefix = $Prefix
        platform = $Script:Platform
        events = $Script:Events
        finished_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Script:ReportFile -Encoding UTF8
}

function Mark-StateDone { param([string]$Name) "$Name=done:$(Get-Date -Format o)" | Add-Content -LiteralPath $Script:StateFile }
function Test-StateDone { param([string]$Name) (Test-Path $Script:StateFile) -and (Select-String -LiteralPath $Script:StateFile -Pattern "^$Name=done:" -Quiet) }

function Invoke-EnvpilotDownload {
    param([string]$Url, [string]$Destination)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Find-CachedAsset {
    param([string]$Pattern)
    $downloads = Join-Path $Script:Root "downloads"
    $asset = Get-ChildItem -LiteralPath $downloads -File -Filter $Pattern -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($asset) { return $asset.FullName }
    return $null
}

function Find-OfflineAsset {
    param([string]$Pattern)
    if ($AssetPath) {
        if (-not (Test-Path -LiteralPath $AssetPath)) { Stop-Envpilot "--asset-path does not exist: $AssetPath" }
        return $AssetPath
    }
    $asset = Find-CachedAsset $Pattern
    if (-not $asset) { Stop-Envpilot "Offline asset not found in downloads/: $Pattern" }
    return $asset
}

function Resolve-GitHubAsset {
    param([string]$Owner, [string]$Repo, [string]$AssetRegex)
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases"
    $asset = $releases |
        Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -notmatch "alpha|beta|rc|pre" } |
        ForEach-Object { $_.assets } |
        Where-Object { $_.name -match $AssetRegex -and $_.name -notmatch "alpha|beta|rc|pre" } |
        Select-Object -First 1
    if (-not $asset) { Stop-Envpilot "Could not resolve stable GitHub asset: $Owner/$Repo $AssetRegex" }
    return $asset.browser_download_url
}


function Get-MihomoDataUrl {
    param([string]$Name)
    switch ($Name) {
        "country.mmdb" { return "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb" }
        "geoip.metadb" { return "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb" }
        default { Stop-Envpilot "No mihomo data asset rule for $Name" }
    }
}

function Install-MihomoDataAsset {
    param([string]$Name, [string]$ConfigDir)
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $target = Join-Path $ConfigDir $Name
    $source = $null
    if ($Mode -eq "offline") {
        $source = Find-OfflineAsset $Name
    } else {
        $source = Find-CachedAsset $Name
        if ($source) {
            Write-Info "Using bundled downloads/ mihomo data asset before network: $source"
        } else {
            $source = Get-MihomoDataUrl $Name
        }
    }
    Write-Info "Geodata asset: $Name"
    Write-Info "Source: $source"
    Write-Info "Target: $target"
    Backup-File $target
    if ($source -match "^https?://") {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "envpilot-mihomo-data.tmp"
        Invoke-EnvpilotDownload $source $tmp
        Move-Item -LiteralPath $tmp -Destination $target -Force
    } else {
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

function Install-MihomoDataAssets {
    param([string]$ConfigDir)
    Install-MihomoDataAsset -Name "country.mmdb" -ConfigDir $ConfigDir
    Install-MihomoDataAsset -Name "geoip.metadb" -ConfigDir $ConfigDir
}

function Get-MihomoBin {
    return (Join-Path $HOME "software/mihomo/mihomo.exe")
}

function Test-EnvpilotPort {
    param([string]$Port)
    if ($Port -notmatch '^\d+$') { return $false }
    $number = [int]$Port
    return ($number -ge 1 -and $number -le 65535)
}

function Get-MihomoConfigPath {
    return (Join-Path $HOME ".config/mihomo/config.yaml")
}

function Get-MihomoProxyPort {
    if (Test-EnvpilotPort $env:MIHOMO_PROXY_PORT) { return [int]$env:MIHOMO_PROXY_PORT }
    $local = Join-Path $Script:ConfigDir "profile.local.ps1"
    if (Test-Path -LiteralPath $local) {
        $match = Select-String -LiteralPath $local -Pattern '^\s*\$env:MIHOMO_PROXY_PORT\s*=\s*[''"]?(\d+)' | Select-Object -Last 1
        if ($match -and (Test-EnvpilotPort $match.Matches[0].Groups[1].Value)) { return [int]$match.Matches[0].Groups[1].Value }
        $legacy = Select-String -LiteralPath $local -Pattern '^\s*\$EnvpilotProxyPort\s*=\s*(\d+)' | Select-Object -Last 1
        if ($legacy -and (Test-EnvpilotPort $legacy.Matches[0].Groups[1].Value)) { return [int]$legacy.Matches[0].Groups[1].Value }
    }
    $config = Get-MihomoConfigPath
    if (Test-Path -LiteralPath $config) {
        $match = Select-String -LiteralPath $config -Pattern '^\s*mixed-port:\s*(\d+)\s*$' | Select-Object -Last 1
        if ($match -and (Test-EnvpilotPort $match.Matches[0].Groups[1].Value)) { return [int]$match.Matches[0].Groups[1].Value }
    }
    return 42290
}

function Get-MihomoApiPort {
    if (Test-EnvpilotPort $env:MIHOMO_API_PORT) { return [int]$env:MIHOMO_API_PORT }
    $local = Join-Path $Script:ConfigDir "profile.local.ps1"
    if (Test-Path -LiteralPath $local) {
        $match = Select-String -LiteralPath $local -Pattern '^\s*\$env:MIHOMO_API_PORT\s*=\s*[''"]?(\d+)' | Select-Object -Last 1
        if ($match -and (Test-EnvpilotPort $match.Matches[0].Groups[1].Value)) { return [int]$match.Matches[0].Groups[1].Value }
    }
    $config = Get-MihomoConfigPath
    if (Test-Path -LiteralPath $config) {
        $match = Select-String -LiteralPath $config -Pattern '^\s*external-controller:\s*(?:127\.0\.0\.1|localhost):(\d+)\s*$' | Select-Object -Last 1
        if ($match -and (Test-EnvpilotPort $match.Matches[0].Groups[1].Value)) { return [int]$match.Matches[0].Groups[1].Value }
    }
    return 60290
}

function Assert-MihomoPorts {
    param([string]$ProxyPort, [string]$ApiPort)
    if (-not (Test-EnvpilotPort $ProxyPort)) { Stop-Envpilot "Invalid proxy port: $ProxyPort. Use an integer from 1 to 65535." }
    if (-not (Test-EnvpilotPort $ApiPort)) { Stop-Envpilot "Invalid API port: $ApiPort. Use an integer from 1 to 65535." }
    if ([int]$ProxyPort -eq [int]$ApiPort) { Stop-Envpilot "Proxy and API ports must be different." }
}
function Set-YamlScalar {
    param([string]$Path, [string]$Key, [string]$Value)
    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path) { [void]$lines.Add($line) }
    }
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*:") {
            $lines[$i] = "${Key}: $Value"
            $found = $true
        }
    }
    if (-not $found) { $lines.Insert(0, "${Key}: $Value") }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Set-MihomoConfigPorts {
    param([int]$ProxyPort, [int]$ApiPort)
    Assert-MihomoPorts -ProxyPort $ProxyPort -ApiPort $ApiPort
    $config = Get-MihomoConfigPath
    Set-YamlScalar -Path $config -Key "allow-lan" -Value "false"
    Set-YamlScalar -Path $config -Key "mixed-port" -Value ([string]$ProxyPort)
    Set-YamlScalar -Path $config -Key "bind-address" -Value "127.0.0.1"
    Set-YamlScalar -Path $config -Key "external-controller" -Value "127.0.0.1:$ApiPort"
}

function Set-EnvpilotProfileLocalPorts {
    param([int]$ProxyPort, [int]$ApiPort)
    $local = Join-Path $Script:ConfigDir "profile.local.ps1"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $local) | Out-Null
    Backup-File $local
    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $local) {
        foreach ($line in Get-Content -LiteralPath $local) {
            if ($line -notmatch '^\s*\$(?:env:MIHOMO_(?:PROXY|API)_PORT|EnvpilotProxyPort)\s*=') { [void]$lines.Add($line) }
        }
    } else {
        [void]$lines.Add("# envpilot profile.local.ps1")
    }
    [void]$lines.Add(('$env:MIHOMO_PROXY_PORT = ''{0}''' -f $ProxyPort))
    [void]$lines.Add(('$env:MIHOMO_API_PORT = ''{0}''' -f $ApiPort))
    [System.IO.File]::WriteAllLines($local, $lines, [System.Text.UTF8Encoding]::new($false))
    Write-Info "Wrote Mihomo ports to $($local): proxy=$ProxyPort API=$ApiPort"
}
function New-BaselineSlug {
    param([string]$Path)
    $slug = $Path -replace "^([A-Za-z]):", "drive_`$1"
    $slug = $slug -replace "^[\\/]+", ""
    $slug = $slug -replace "[\\/:\s]", "_"
    $slug = $slug -replace "[^A-Za-z0-9_.-]", "_"
    return $slug
}

function Add-BaselineEntry {
    param([string]$Kind, [string]$Name, [string]$Target, [bool]$Present, [string]$Snapshot = "", [string]$Detail = "")
    $presentValue = if ($Present) { "1" } else { "0" }
    [void]$Script:BaselineRows.Add("$Kind`t$Name`t$Target`t$presentValue`t$Snapshot`t$Detail")
}

function Add-BaselineFile {
    param([string]$Name, [string]$Target)
    if (Test-Path -LiteralPath $Target) {
        $snapshotRel = "files/$(New-BaselineSlug $Target)"
        $snapshotAbs = Join-Path $Script:BaselineDir $snapshotRel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $snapshotAbs) | Out-Null
        Copy-Item -LiteralPath $Target -Destination $snapshotAbs -Force
        Add-BaselineEntry -Kind "file" -Name $Name -Target $Target -Present $true -Snapshot $snapshotRel
    } else {
        Add-BaselineEntry -Kind "file" -Name $Name -Target $Target -Present $false
    }
}

function Add-BaselineDir {
    param([string]$Name, [string]$Target)
    Add-BaselineEntry -Kind "dir" -Name $Name -Target $Target -Present (Test-Path -LiteralPath $Target -PathType Container)
}

function Add-BaselineTool {
    param([string]$Name, [string]$Path = "")
    if (-not $Path) {
        $cmd = Get-Command $Name -ErrorAction SilentlyContinue
        if ($cmd) { $Path = $cmd.Source }
    }
    Add-BaselineEntry -Kind "tool" -Name $Name -Target $Path -Present ([bool]$Path)
}

function Save-Baseline {
    Remove-Item -LiteralPath $Script:BaselineDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Join-Path $Script:BaselineDir "files") | Out-Null
    $Script:BaselineRows = [System.Collections.Generic.List[string]]::new()
    [void]$Script:BaselineRows.Add("# envpilot doctor baseline")
    [void]$Script:BaselineRows.Add("# captured_at=$((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))")
    [void]$Script:BaselineRows.Add("# platform=$($Script:Platform.OS)/$($Script:Platform.Arch)")
    [void]$Script:BaselineRows.Add("# prefix=$Prefix")

    Add-BaselineFile -Name "powershell-profile" -Target $PROFILE.CurrentUserCurrentHost
    Add-BaselineFile -Name "powershell-local" -Target (Join-Path $Script:ConfigDir "profile.local.ps1")
    Add-BaselineFile -Name "repo-root" -Target $Script:RepoRootFile
    Add-BaselineFile -Name "condarc" -Target (Join-Path $HOME ".condarc")
    Add-BaselineFile -Name "mihomo-config" -Target (Join-Path $HOME ".config/mihomo/config.yaml")
    Add-BaselineFile -Name "mihomo-country" -Target (Join-Path $HOME ".config/mihomo/country.mmdb")
    Add-BaselineFile -Name "mihomo-geoip" -Target (Join-Path $HOME ".config/mihomo/geoip.metadb")
    Add-BaselineFile -Name "mihomo-bin" -Target (Get-MihomoBin)
    Add-BaselineFile -Name "mihomo-start" -Target (Join-Path $HOME "software/mihomo/start_mihomo.sh")
    Add-BaselineFile -Name "mihomo-log" -Target (Join-Path $HOME "logs/mihomo.log")
    Add-BaselineFile -Name "mihomo-state-log" -Target (Join-Path $HOME ".local/state/mihomo/start.log")
    Add-BaselineFile -Name "codex-config" -Target (Join-Path $HOME ".codex/config.toml")
    Add-BaselineFile -Name "codex-secrets" -Target (Join-Path $HOME ".config/secrets/api.env.example")
    Add-BaselineFile -Name "gh-link" -Target (Join-Path $HOME ".local/bin/gh.exe")
    Add-BaselineFile -Name "tmux-link" -Target (Join-Path $HOME ".local/bin/tmux")

    Add-BaselineDir -Name "conda-miniconda-prefix" -Target (Join-Path $Prefix "miniconda3")
    Add-BaselineDir -Name "conda-anaconda-prefix" -Target (Join-Path $Prefix "anaconda3")
    Add-BaselineDir -Name "github-prefix" -Target (Join-Path $Prefix "github-cli")
    Add-BaselineDir -Name "mihomo-prefix" -Target (Join-Path $HOME "software/mihomo")
    Add-BaselineDir -Name "nvm-dir" -Target (Join-Path $HOME ".nvm")
    Add-BaselineDir -Name "tmux-prefix" -Target (Join-Path $HOME ".local/envpilot")

    Add-BaselineTool -Name "conda"
    Add-BaselineTool -Name "mamba"
    Add-BaselineTool -Name "codex"
    Add-BaselineTool -Name "gh"
    Add-BaselineTool -Name "tmux"
    $mihomoBin = Get-MihomoBin
    Add-BaselineTool -Name "mihomo" -Path ($(if (Test-Path -LiteralPath $mihomoBin) { $mihomoBin } else { "" }))

    [System.IO.File]::WriteAllLines($Script:BaselineFile, $Script:BaselineRows, [System.Text.UTF8Encoding]::new($false))
    Write-Info "Captured doctor baseline: $Script:BaselineFile"
}

function Test-EnvpilotSafePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        foreach ($root in @($HOME, $Prefix, $Script:ConfigDir)) {
            if ([string]::IsNullOrWhiteSpace($root)) { continue }
            $rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            $rootPrefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
            if ($full.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
    } catch {
        return $false
    }
    return $false
}

function Remove-EnvpilotPath {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not (Test-EnvpilotSafePath $Path)) {
        Write-Warn "Skip unsafe restore target: $Path"
        return
    }
    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Test-MihomoPort {
    param([string]$HostName = "127.0.0.1", [int]$Port = (Get-MihomoProxyPort))
    $listen = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Where-Object {
        $_.LocalAddress -in @($HostName, "0.0.0.0", "::", "::1")
    } | Select-Object -First 1
    return [bool]$listen
}

function Stop-MihomoProcesses {
    param([switch]$Quiet)
    $bin = Get-MihomoBin
    $resolvedBin = if (Test-Path -LiteralPath $bin) { (Resolve-Path -LiteralPath $bin).Path } else { $null }
    $stopped = 0
    Get-Process -Name "mihomo" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if (($resolvedBin -and $_.Path -eq $resolvedBin) -or ($_.Path -like "*\software\mihomo\mihomo.exe")) {
                Stop-Process -Id $_.Id -Force
                $stopped += 1
                Write-Info "Stopped Mihomo process: $($_.Id)"
            }
        } catch {
        }
    }
    if ($stopped -eq 0 -and -not $Quiet) { Write-Info "No envpilot-managed Mihomo process found." }
}

function Test-MihomoApi {
    param([int]$Port = (Get-MihomoApiPort))
    try {
        $request = [System.Net.WebRequest]::Create("http://127.0.0.1:$Port/version")
        $request.Proxy = $null
        $request.Timeout = 2000
        $response = $request.GetResponse()
        $response.Close()
        return $true
    } catch {
        return $false
    }
}

function Start-MihomoProcess {
    param([int]$ProxyPort = (Get-MihomoProxyPort), [int]$ApiPort = (Get-MihomoApiPort))
    Assert-MihomoPorts -ProxyPort $ProxyPort -ApiPort $ApiPort
    $bin = Get-MihomoBin
    $configDir = Join-Path $HOME ".config/mihomo"
    $config = Join-Path $configDir "config.yaml"
    if (Test-MihomoApi -Port $ApiPort) {
        Write-Info "Mihomo is already running and healthy: proxy=$ProxyPort API=$ApiPort"
        return
    }
    if (Test-MihomoPort -Port $ProxyPort) { Stop-Envpilot "Proxy port 127.0.0.1:$ProxyPort is already in use." }
    if (Test-MihomoPort -Port $ApiPort) { Stop-Envpilot "API port 127.0.0.1:$ApiPort is already in use." }
    if (-not (Test-Path -LiteralPath $bin)) { Stop-Envpilot "Mihomo executable not found: $bin" }
    if (-not (Test-Path -LiteralPath $config)) { Stop-Envpilot "Mihomo config not found: $config" }
    Set-MihomoConfigPorts -ProxyPort $ProxyPort -ApiPort $ApiPort
    Start-Process -WindowStyle Hidden -FilePath $bin -ArgumentList @("-d", $configDir) | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        if ((Test-MihomoPort -Port $ProxyPort) -and (Test-MihomoApi -Port $ApiPort)) {
            Write-Info "Mihomo is ready: proxy=127.0.0.1:$ProxyPort API=127.0.0.1:$ApiPort"
            return
        }
        Start-Sleep -Seconds 1
    }
    Stop-Envpilot "Mihomo did not become healthy within 30 seconds."
}

function Show-MihomoStatus {
    $bin = Get-MihomoBin
    $resolvedBin = if (Test-Path -LiteralPath $bin) { (Resolve-Path -LiteralPath $bin).Path } else { $null }
    $proxyPort = Get-MihomoProxyPort
    $apiPort = Get-MihomoApiPort
    Write-Host "envpilot Mihomo binary:"
    if ($resolvedBin) { Write-Host "  $resolvedBin" } else { Write-Host "  not found: $bin" }
    Write-Host ""
    Write-Host "Mihomo process:"
    $processes = @(Get-Process -Name "mihomo" -ErrorAction SilentlyContinue | Where-Object {
        try { ($resolvedBin -and $_.Path -eq $resolvedBin) -or ($_.Path -like "*\software\mihomo\mihomo.exe") } catch { $false }
    })
    if ($processes.Count -eq 0) { Write-Host "  not running" }
    else { foreach ($process in $processes) { Write-Host "  $($process.Id) $($process.Path)" } }
    $proxyState = if (Test-MihomoPort -Port $proxyPort) { "listening" } else { "not detected" }
    $apiState = if (Test-MihomoPort -Port $apiPort) { "listening" } else { "not detected" }
    $health = if (Test-MihomoApi -Port $apiPort) { "OK" } else { "FAILED" }
    Write-Host ""
    Write-Host "ports:"
    Write-Host "  proxy 127.0.0.1:$proxyPort $proxyState"
    Write-Host "  API   127.0.0.1:$apiPort $apiState"
    Write-Host "  API health: $health"
}

function Set-MihomoPorts {
    param([string]$ProxyPort, [string]$ApiPort)
    Assert-MihomoPorts -ProxyPort $ProxyPort -ApiPort $ApiPort
    $proxyNumber = [int]$ProxyPort
    $apiNumber = [int]$ApiPort
    $config = Get-MihomoConfigPath
    $bin = Get-MihomoBin
    if (-not (Test-Path -LiteralPath $bin)) { Stop-Envpilot "Mihomo executable not found: $bin" }
    if (-not (Test-Path -LiteralPath $config)) { Stop-Envpilot "Mihomo config not found: $config. Run: .\envpilot.ps1 install mihomo" }
    Write-Info "Plan: switch Mihomo ports to proxy=$proxyNumber API=$apiNumber"
    Stop-MihomoProcesses -Quiet
    if (Test-MihomoPort -Port $proxyNumber) { Stop-Envpilot "Target proxy port 127.0.0.1:$proxyNumber is already in use." }
    if (Test-MihomoPort -Port $apiNumber) { Stop-Envpilot "Target API port 127.0.0.1:$apiNumber is already in use." }
    Backup-File $config
    Set-MihomoConfigPorts -ProxyPort $proxyNumber -ApiPort $apiNumber
    Set-EnvpilotProfileLocalPorts -ProxyPort $proxyNumber -ApiPort $apiNumber
    $env:MIHOMO_PROXY_PORT = [string]$proxyNumber
    $env:MIHOMO_API_PORT = [string]$apiNumber
    Start-MihomoProcess -ProxyPort $proxyNumber -ApiPort $apiNumber
    Write-Info "Switched Mihomo ports: proxy=$proxyNumber API=$apiNumber"
}

function Set-MihomoPort {
    param([string]$Port)
    Set-MihomoPorts -ProxyPort $Port -ApiPort (Get-MihomoApiPort)
}

function Update-MihomoSubscription {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { $Url = $env:ENVPILOT_MIHOMO_SUBSCRIPTION_URL }
    if ([string]::IsNullOrWhiteSpace($Url)) { $Url = Read-Host "Paste Clash/Mihomo subscription URL" }
    if ($Url -notmatch '^https?://') { Stop-Envpilot "Provide a Clash/Mihomo subscription URL beginning with http:// or https://." }
    $config = Get-MihomoConfigPath
    $configDir = Split-Path -Parent $config
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $newConfig = Join-Path $configDir ("config.yaml.new." + [guid]::NewGuid().ToString("N"))
    $backup = $null
    $wasRunning = @(Get-Process -Name "mihomo" -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -like "*\software\mihomo\mihomo.exe" } catch { $false } }).Count -gt 0
    try {
        Invoke-EnvpilotDownload $Url $newConfig
        if ((Get-Item -LiteralPath $newConfig).Length -eq 0) { Stop-Envpilot "Downloaded subscription config is empty." }
        if ((Get-Content -LiteralPath $newConfig -TotalCount 1) -match '^\s*<(?:html|!doctype)') { Stop-Envpilot "Downloaded content looks like HTML, not a Mihomo configuration." }
        if (Test-Path -LiteralPath $config) {
            $backup = "$config.bak.$Script:RunId"
            Copy-Item -LiteralPath $config -Destination $backup -Force
            ($config + [char]9 + $backup) | Add-Content -LiteralPath $Script:RollbackLog
            Write-Info "Backed up $config -> $backup"
        }
        Set-YamlScalar -Path $newConfig -Key "allow-lan" -Value "false"
        Set-YamlScalar -Path $newConfig -Key "mixed-port" -Value ([string](Get-MihomoProxyPort))
        Set-YamlScalar -Path $newConfig -Key "bind-address" -Value "127.0.0.1"
        Set-YamlScalar -Path $newConfig -Key "external-controller" -Value "127.0.0.1:$(Get-MihomoApiPort)"
        Stop-MihomoProcesses -Quiet
        Move-Item -LiteralPath $newConfig -Destination $config -Force
        if ($wasRunning) {
            try { Start-MihomoProcess }
            catch {
                if ($backup) {
                    Copy-Item -LiteralPath $backup -Destination $config -Force
                    Start-MihomoProcess
                }
                throw
            }
        }
        Write-Info "Mihomo subscription updated."
    } finally {
        Remove-Item -LiteralPath $newConfig -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-MihomoCommand {
    $action = if ([string]::IsNullOrWhiteSpace($Component) -or $Component -eq "all") { "status" } else { $Component.ToLowerInvariant() }
    switch ($action) {
        "start" { Start-MihomoProcess }
        "stop" { Stop-MihomoProcesses }
        "status" { Show-MihomoStatus }
        "port" { Set-MihomoPort -Port $Value }
        "ports" { Set-MihomoPorts -ProxyPort $Value -ApiPort $Value2 }
        { $_ -in @("update-subscription","subscription") } { Update-MihomoSubscription -Url $Value }
        default { Stop-Envpilot "Unknown Mihomo action: $Component. Use start, stop, status, port PORT, ports PROXY_PORT API_PORT, or update-subscription [URL]." }
    }
}
function Restore-BaselineTool {
    param([string]$Name)
    switch ($Name) {
        "mamba" {
            if (Test-Command conda) {
                try { conda remove -n base -y mamba | Out-Null } catch { Write-Warn "Could not remove mamba from Conda base." }
            }
        }
        "codex" {
            if (Test-Command npm) {
                try { npm uninstall -g "@openai/codex" | Out-Null } catch { Write-Warn "Could not uninstall Codex from npm global packages." }
            }
        }
        "mihomo" {
            Remove-EnvpilotPath (Get-MihomoBin)
        }
        "gh" {
            if (Test-Command winget) {
                try { winget uninstall --id GitHub.cli --silent | Out-Null } catch { Write-Warn "Could not uninstall GitHub CLI with winget." }
            }
        }
    }
}

function Restore-Baseline {
    if (-not (Test-Path -LiteralPath $Script:BaselineFile)) { Stop-Envpilot "No doctor baseline found. Run: .\envpilot.ps1 doctor" }
    Write-Info "Restoring doctor baseline from $Script:BaselineFile"
    Stop-MihomoProcesses

    foreach ($line in Get-Content -LiteralPath $Script:BaselineFile) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
        $parts = $line -split "`t", 6
        if ($parts.Count -lt 4) { continue }
        $kind = $parts[0]
        $name = $parts[1]
        $target = $parts[2]
        $present = $parts[3]
        $snapshot = if ($parts.Count -ge 5) { $parts[4] } else { "" }

        switch ($kind) {
            "file" {
                if ($present -eq "1") {
                    $snapshotPath = Join-Path $Script:BaselineDir $snapshot
                    if (Test-Path -LiteralPath $snapshotPath) {
                        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
                        Copy-Item -LiteralPath $snapshotPath -Destination $target -Force
                        Write-Info "Restored file: $target"
                    } else {
                        Write-Warn "Missing snapshot for ${name}: $snapshotPath"
                    }
                } else {
                    Remove-EnvpilotPath $target
                }
            }
            "dir" {
                if ($present -eq "0") { Remove-EnvpilotPath $target }
            }
            "tool" {
                if ($present -eq "0") { Restore-BaselineTool $name }
            }
        }
    }
    Remove-Item -LiteralPath $Script:StateFile -Force -ErrorAction SilentlyContinue
    Write-Info "Baseline restore complete."
}
function Show-Doctor {
    $Script:Platform = Get-EnvpilotPlatform
    Save-Baseline
    Write-Info "OS: $($Script:Platform.OS)"
    Write-Info "Architecture: $($Script:Platform.Arch)"
    Write-Info "Administrator: $($Script:Platform.IsRoot)"
    Write-Info "Prefix: $Prefix"
    foreach ($cmd in "git","gh","ssh","conda","mamba","node","npm","codex","wsl") {
        if (Test-Command $cmd) {
            Write-Info "${cmd}: $(Get-Command $cmd | Select-Object -ExpandProperty Source)"
        } else {
            Write-Warn "${cmd}: not found"
        }
    }
    $mihomoDir = Join-Path $HOME ".config/mihomo"
    foreach ($asset in "country.mmdb", "geoip.metadb") {
        $path = Join-Path $mihomoDir $asset
        if (Test-Path -LiteralPath $path) {
            Write-Info "mihomo data: found at $path"
        } else {
            $cached = Find-CachedAsset $asset
            if ($cached) {
                Write-Info "mihomo data cache: found at $cached"
            } else {
                Write-Warn "mihomo data: $asset not found in $mihomoDir or downloads/"
            }
        }
    }
}
function Install-Conda {
    if (Test-Command conda) {
        $condaPath = (Get-Command conda).Source
        $beforeVersion = (& conda --version 2>$null | Out-String).Trim()
        if (-not $Script:Upgrade) {
            Add-ReportEvent "conda" "skipped" "already installed; use update conda to refresh" $beforeVersion "" $condaPath
            Mark-StateDone "conda"
            return
        }
        Write-Info "Current Conda: $beforeVersion at $condaPath"
        Write-Info "Update strategy: let Conda resolve the newest compatible base package for this Windows installation."
        if ($Mode -eq "offline") {
            Write-Warn "Offline mode cannot resolve a newer Conda package; keeping $beforeVersion."
            Add-ReportEvent "conda" "skipped" "offline update requires a prepared package cache" $beforeVersion "" $condaPath
            Mark-StateDone "conda"
            return
        }
        if (-not (Confirm-Step "Update the Conda base command to the newest compatible package?" $true)) {
            Add-ReportEvent "conda" "skipped" "user declined update" $beforeVersion "" $condaPath
            return
        }
        $condarc = Join-Path $HOME ".condarc"
        Backup-File $condarc
        Copy-Item -LiteralPath (Join-Path $Script:Root "templates/condarc") -Destination $condarc -Force
        $global:LASTEXITCODE = 0
        & conda update -n base -y conda
        if ($LASTEXITCODE -ne 0) { Stop-Envpilot "Conda self-update failed with exit $LASTEXITCODE. The existing installation remains available." }
        $afterVersion = (& conda --version 2>$null | Out-String).Trim()
        Add-ReportEvent "conda" "updated" "resolved newest compatible base conda package" $afterVersion $condarc $condaPath
        Mark-StateDone "conda"
        Write-Info "Conda update complete: $beforeVersion -> $afterVersion"
        return
    }
    if ($Script:Platform.Arch -ne "amd64") { Stop-Envpilot "Windows Conda installer rule currently supports amd64 only." }
    $url = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
    $installer = Join-Path ([System.IO.Path]::GetTempPath()) "envpilot-miniconda.exe"
    $target = Join-Path $Prefix "miniconda3"
    Write-Info "Selected latest Miniconda installer for Windows amd64"
    Write-Info "Source: $url"
    Write-Info "Install target: $target"
    if (-not (Confirm-Step "Install Conda to $target?" $true)) { Add-ReportEvent "conda" "skipped" "user declined"; return }
    if ($Mode -eq "offline") {
        Copy-Item -LiteralPath (Find-OfflineAsset "Miniconda3-*.exe") -Destination $installer -Force
    } else {
        Invoke-EnvpilotDownload $url $installer
    }
    $process = Start-Process -FilePath $installer -ArgumentList @("/InstallationType=JustMe","/RegisterPython=0","/S","/D=$target") -Wait -PassThru
    if ($process.ExitCode -ne 0) { Stop-Envpilot "Miniconda installer failed with exit $($process.ExitCode)." }
    $condarc = Join-Path $HOME ".condarc"
    Backup-File $condarc
    Copy-Item -LiteralPath (Join-Path $Script:Root "templates/condarc") -Destination $condarc -Force
    $targetConda = Join-Path $target "Scripts/conda.exe"
    $version = if (Test-Path -LiteralPath $targetConda) { (& $targetConda --version 2>$null | Out-String).Trim() } else { "" }
    Add-ReportEvent "conda" "installed" "installed latest compatible Miniconda" $version $url $target
    Mark-StateDone "conda"
}

function Install-Mihomo {
    $regex = if ($Script:Platform.Arch -eq "amd64") { "mihomo-windows-amd64-compatible-.*\.zip$" } else { "mihomo-windows-arm64-.*\.zip$" }
    $offlinePattern = if ($Script:Platform.Arch -eq "amd64") { "mihomo-windows-amd64-compatible-*.zip" } else { "mihomo-windows-arm64-*.zip" }
    $installDir = Join-Path $HOME "software/mihomo"
    $bin = Join-Path $installDir "mihomo.exe"
    $configDir = Join-Path $HOME ".config/mihomo"
    $config = Join-Path $configDir "config.yaml"
    $configBefore = Test-Path -LiteralPath $config
    $managedProcesses = @(Get-Process -Name "mihomo" -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -eq $bin -or $_.Path -like "*\software\mihomo\mihomo.exe" } catch { $false }
    })
    $wasRunning = $managedProcesses.Count -gt 0
    $reportStatus = if ($Script:Upgrade) { "updated" } else { "installed" }
    $proxyPort = Get-MihomoProxyPort
    $apiPort = Get-MihomoApiPort
    Assert-MihomoPorts -ProxyPort $proxyPort -ApiPort $apiPort

    Write-Info "Selected Mihomo asset rule for Windows/$($Script:Platform.Arch): $regex"
    Write-Info "Offline asset pattern: $offlinePattern"
    if ($Mode -eq "offline") {
        $source = Find-OfflineAsset $offlinePattern
    } else {
        $source = Find-CachedAsset $offlinePattern
        if ($source) {
            Write-Info "Using bundled downloads/ Mihomo asset for Windows/$($Script:Platform.Arch) before network: $source"
        } else {
            $source = Resolve-GitHubAsset "MetaCubeX" "mihomo" $regex
        }
    }

    Write-Info "Plan: install/update Mihomo"
    Write-Info "Source: $source"
    Write-Info "Target: $bin"
    Write-Info "Config: $config"
    Write-Info "Ports: proxy=127.0.0.1:$proxyPort API=127.0.0.1:$apiPort"
    if ($wasRunning) {
        Write-Info "Existing envpilot-managed Mihomo is running; it will be stopped only for replacement and restarted afterward."
    } elseif (Test-MihomoPort -Port $proxyPort) {
        Write-Warn "Proxy port 127.0.0.1:$proxyPort is currently in use by another process."
    } else {
        Write-Info "Proxy port availability: 127.0.0.1:$proxyPort is available"
    }
    if (-not $wasRunning -and (Test-MihomoPort -Port $apiPort)) {
        Write-Warn "API port 127.0.0.1:$apiPort is currently in use by another process."
    } elseif (-not $wasRunning) {
        Write-Info "API port availability: 127.0.0.1:$apiPort is available"
    }
    if (-not (Confirm-Step "Install/update Mihomo from the source above to $bin?" $true)) {
        Add-ReportEvent "mihomo" "skipped" "user declined" "" $source $bin
        return
    }

    New-Item -ItemType Directory -Force -Path $installDir, $configDir | Out-Null
    Set-EnvpilotProfileLocalPorts -ProxyPort $proxyPort -ApiPort $apiPort
    $archive = Join-Path ([System.IO.Path]::GetTempPath()) "envpilot-mihomo.zip"
    $extract = Join-Path ([System.IO.Path]::GetTempPath()) "envpilot-mihomo"
    $binaryBackup = Join-Path ([System.IO.Path]::GetTempPath()) "envpilot-mihomo-backup.exe"
    try {
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination $archive -Force
        } else {
            Invoke-EnvpilotDownload $source $archive
        }
        Remove-Item -Recurse -Force -LiteralPath $extract -ErrorAction SilentlyContinue
        Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force
        $exe = Get-ChildItem -LiteralPath $extract -Recurse -File -Filter "mihomo*.exe" | Select-Object -First 1
        if (-not $exe) { Stop-Envpilot "Could not find Mihomo executable in archive." }
        if (Test-Path -LiteralPath $bin) { Copy-Item -LiteralPath $bin -Destination $binaryBackup -Force }
        if ($wasRunning) {
            Stop-MihomoProcesses -Quiet
            Start-Sleep -Seconds 1
        }
        if (Test-MihomoPort -Port $proxyPort) { Stop-Envpilot "Target proxy port 127.0.0.1:$proxyPort is still occupied after stopping managed Mihomo." }
        if (Test-MihomoPort -Port $apiPort) { Stop-Envpilot "Target API port 127.0.0.1:$apiPort is still occupied after stopping managed Mihomo." }
        Copy-Item -LiteralPath $exe.FullName -Destination $bin -Force
        Install-MihomoDataAssets -ConfigDir $configDir
        $subscription = $env:ENVPILOT_MIHOMO_SUBSCRIPTION_URL
        if ([string]::IsNullOrWhiteSpace($subscription) -and $Script:Upgrade -and $configBefore) {
            Write-Info "Existing envpilot Mihomo config detected; update will preserve it without requesting the subscription again."
        } elseif ([string]::IsNullOrWhiteSpace($subscription) -and -not $Yes) {
            $subscription = Read-Host "Paste Clash/Mihomo subscription URL (press Enter to skip)"
        }
        if (-not [string]::IsNullOrWhiteSpace($subscription)) {
            Update-MihomoSubscription -Url $subscription
        } elseif (Test-Path -LiteralPath $config) {
            Write-Info "Preserved existing Mihomo config: $config"
        } else {
            Write-Warn "No subscription URL provided. Later run: .\envpilot.ps1 mihomo update-subscription '<Clash/Mihomo URL>'"
        }
        if ($wasRunning -and (Test-Path -LiteralPath $config)) {
            Start-MihomoProcess -ProxyPort $proxyPort -ApiPort $apiPort
        }
        $version = (& $bin -v 2>$null | Select-Object -First 1 | Out-String).Trim()
        Add-ReportEvent "mihomo" $reportStatus "installed or updated Mihomo; preserved managed config and running state" $version $source $bin
        Mark-StateDone "mihomo"
    } catch {
        if (Test-Path -LiteralPath $binaryBackup) {
            Copy-Item -LiteralPath $binaryBackup -Destination $bin -Force
        }
        if ($wasRunning -and (Test-Path -LiteralPath $config)) {
            try { Start-MihomoProcess -ProxyPort $proxyPort -ApiPort $apiPort } catch { Write-Warn "Could not restore the previous Mihomo runtime after update failure." }
        }
        throw
    } finally {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $binaryBackup -Force -ErrorAction SilentlyContinue
    }
}
function Install-Codex {
    $action = "configured"
    Write-Info "Codex config will use env_key=OPENAI_API_KEY and will not write auth.json."
    if (-not (Test-Command npm)) {
        if (Test-Command winget) {
            if (Confirm-Step "Install Node.js LTS with winget?" $true) {
                $process = Start-Process -FilePath "winget" -ArgumentList @("install","--id","OpenJS.NodeJS.LTS","--silent","--accept-package-agreements","--accept-source-agreements") -Wait -PassThru
                if ($process.ExitCode -ne 0) { Stop-Envpilot "Node.js installation failed with exit $($process.ExitCode)." }
            }
        }
    }
    if (-not (Test-Command npm)) { Stop-Envpilot "npm is required for Codex. Install Node.js and rerun." }
    if (-not (Test-Command codex)) {
        $action = "installed"
        npm install -g "@openai/codex"
        if ($LASTEXITCODE -ne 0) { Stop-Envpilot "npm failed to install @openai/codex." }
    } elseif ($Script:Upgrade) {
        $action = "updated"
        Write-Info "Updating Codex CLI from $(& codex --version 2>$null) using npm."
        npm install -g "@openai/codex"
        if ($LASTEXITCODE -ne 0) { Stop-Envpilot "npm failed to update @openai/codex." }
    }
    $codexDir = Join-Path $HOME ".codex"
    New-Item -ItemType Directory -Force -Path $codexDir | Out-Null
    $config = Join-Path $codexDir "config.toml"
    Backup-File $config
    @'
model_provider = "codex"
model = "gpt-5.5"
review_model = "gpt-5.5"
model_reasoning_effort = "high"
disable_response_storage = true
network_access = "enabled"

[model_providers.codex]
name = "codex"
base_url = "https://yanhuoapi.com/v1"
wire_api = "responses"
env_key = "OPENAI_API_KEY"
'@ | Set-Content -LiteralPath $config -Encoding UTF8
    $codexCommand = Get-Command codex -ErrorAction SilentlyContinue
    $version = if ($codexCommand) { (& codex --version 2>$null | Out-String).Trim() } else { "" }
    Add-ReportEvent "codex" $action "installed or updated Codex and configured env_key" $version "npm:@openai/codex" $(if ($codexCommand) { $codexCommand.Source } else { "" })
    Mark-StateDone "codex"
}

function Install-GitHubCli {
    $action = "checked"
    if (-not (Test-Command gh)) {
        if (-not (Test-Command winget)) { Stop-Envpilot "GitHub CLI not found and winget is unavailable." }
        $action = "installed"
        $process = Start-Process -FilePath "winget" -ArgumentList @("install","--id","GitHub.cli","--exact","--silent","--accept-package-agreements","--accept-source-agreements") -Wait -PassThru
        if ($process.ExitCode -ne 0) { Stop-Envpilot "GitHub CLI installation failed with exit $($process.ExitCode)." }
    } elseif ($Script:Upgrade) {
        if (Test-Command winget) {
            $action = "updated"
            Write-Info "Checking GitHub CLI updates with winget."
            $process = Start-Process -FilePath "winget" -ArgumentList @("upgrade","--id","GitHub.cli","--exact","--silent","--accept-package-agreements","--accept-source-agreements") -Wait -PassThru
            if ($process.ExitCode -ne 0) { Write-Warn "winget did not apply a GitHub CLI update; the existing gh command is unchanged." }
        } else {
            Write-Warn "GitHub CLI exists, but winget is unavailable; envpilot will not overwrite a system-managed installation."
        }
    }
    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCommand) {
        try {
            gh auth status | Out-String | ForEach-Object { Write-Info $_.TrimEnd() }
        } catch {
            Write-Warn "Run: gh auth login -h github.com --git-protocol ssh"
        }
    }
    $version = if ($ghCommand) { (& gh --version 2>$null | Select-Object -First 1 | Out-String).Trim() } else { "" }
    Add-ReportEvent "github" $action "GitHub CLI checked or updated; auth may require user action" $version "winget/GitHub.cli" $(if ($ghCommand) { $ghCommand.Source } else { "" })
    Mark-StateDone "github"
}

function Install-Tmux {
    if (Test-Command tmux) {
        Add-ReportEvent "tmux" "skipped" "already available" "" "" (Get-Command tmux).Source
        Mark-StateDone "tmux"
        return
    }
    if (Test-Command wsl) {
        Write-Warn "Windows native tmux is not installed by envpilot. Use WSL: wsl bash envpilot.sh install tmux"
        Add-ReportEvent "tmux" "skipped" "use WSL/MSYS2 for tmux" "" "" ""
        Mark-StateDone "tmux"
        return
    }
    Write-Warn "tmux is a Unix terminal multiplexer; install WSL/MSYS2/Git Bash for tmux support."
    Add-ReportEvent "tmux" "skipped" "Windows native tmux unsupported" "" "" ""
}

function Install-One {
    param([string]$Name)
    switch ($Name) {
        "conda" { Install-Conda }
        "mamba" { Write-Warn "Install mamba from an initialized Conda shell using the configured channels: conda install -n base -y mamba"; Add-ReportEvent "mamba" "skipped" "requires conda shell initialization" }
        "mihomo" { Install-Mihomo }
        "codex" { Install-Codex }
        "github" { Install-GitHubCli }
        "tmux" { Install-Tmux }
        default { Stop-Envpilot "Unknown component: $Name" }
    }
}

function Invoke-Install {
    $Script:Platform = Get-EnvpilotPlatform
    $names = if ($Component -eq "all") { @("mihomo","conda","mamba","codex","github","tmux") } else { @($Component) }
    foreach ($name in $names) {
        if ((Test-StateDone $name) -and -not $Script:Upgrade) {
            Write-Info "Skip ${name}: already marked done. Use update or -Upgrade to re-check versions."
            Add-ReportEvent $name "skipped" "already marked done"
            continue
        }
        if (Test-StateDone $name) { Write-Info "Re-checking installed $name for compatible updates." }
        Install-One $name
    }
    $action = if ($Script:Upgrade) { "update" } else { "install" }
    Save-Report $action $Component
    Write-Info "Install report: $Script:ReportFile"
}

function Apply-ShellProfile {
    $profilePath = $PROFILE.CurrentUserCurrentHost
    $template = Join-Path $Script:Root "templates/Microsoft.PowerShell_profile.ps1"
    Write-Info "PowerShell profile target: $profilePath"
    if (-not (Confirm-Step "Replace PowerShell profile with envpilot template?" $false)) {
        Write-Warn "PowerShell profile unchanged."
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $profilePath) | Out-Null
    Backup-File $profilePath
    Copy-Item -LiteralPath $template -Destination $profilePath -Force
    Write-Info "Applied PowerShell profile: $profilePath"
}

function Rollback-Latest {
    if (-not (Test-Path -LiteralPath $Script:RollbackLog)) { Stop-Envpilot "No rollback records found." }
    $line = Get-Content -LiteralPath $Script:RollbackLog | Select-Object -Last 1
    $parts = $line -split "`t", 2
    if ($parts.Count -ne 2 -or -not (Test-Path -LiteralPath $parts[1])) { Stop-Envpilot "Invalid rollback record." }
    Copy-Item -LiteralPath $parts[1] -Destination $parts[0] -Force
    Write-Info "Restored $($parts[0]) from $($parts[1])"
}

function Update-Manifests {
    $script = Join-Path $Script:Root "scripts/update-manifests.py"
    $python = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $python) { Stop-Envpilot "python3 or python is required to update manifests" }
    & $python.Source $script
    if ($LASTEXITCODE -ne 0) { Stop-Envpilot "Manifest update failed." }
}

function Update-MihomoCache {
    $script = Join-Path $Script:Root "scripts/update-mihomo-cache.py"
    $python = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $python) { Stop-Envpilot "python3 or python is required to refresh the mihomo cache" }
    & $python.Source $script
    if ($LASTEXITCODE -ne 0) { Stop-Envpilot "mihomo cache refresh failed." }
}

function Show-Usage {
@"
envpilot - cross-platform user-space environment bootstrapper

Usage:
  .\envpilot.ps1 doctor
      Show system, shell, proxy, and installed tool status.
  .\envpilot.ps1 install [all|mihomo|conda|mamba|codex|github|tmux] [-Mode online|offline] [-Prefix PATH] [-AssetPath PATH] [-Upgrade] [-Yes]
      Install selected component(s). Online is the default.
  .\envpilot.ps1 update [all|mihomo|conda|mamba|codex|github|tmux]
      Re-check compatible latest versions and update existing envpilot components.
  .\envpilot.ps1 apply-shell
      Back up and replace the active PowerShell profile.
  .\envpilot.ps1 rollback
      Restore the most recent envpilot-managed backup.
  .\envpilot.ps1 restore
      Restore envpilot-managed changes to the latest doctor baseline.
  .\envpilot.ps1 mihomo [start|stop|status|port PORT|ports PROXY_PORT API_PORT|update-subscription [URL]]
      Manage Mihomo, its two local ports, and subscription config.
  .\envpilot.ps1 resume
      Continue an interrupted install using saved state.
  .\envpilot.ps1 reset
      Clear saved state so install steps can run again.
  .\envpilot.ps1 update-manifests
      Refresh manifest latest metadata from upstream.
  .\envpilot.ps1 update-mihomo-cache
      Refresh the bundled stable mihomo assets in downloads/.
"@
}
try {
    if ($Command -notin @("help")) {
        Initialize-Envpilot
    }
    switch ($Command) {
        "doctor" { Show-Doctor }
        "install" { Invoke-Install }
        { $_ -in @("update","upgrade") } { $Script:Upgrade = $true; Invoke-Install }
        "apply-shell" { Apply-ShellProfile }
        "rollback" { Rollback-Latest }
        "restore" { Restore-Baseline }
        "mihomo" { Invoke-MihomoCommand }
        "resume" { if (Test-Path $Script:StateFile) { Get-Content $Script:StateFile }; $Component = "all"; Invoke-Install }
        "reset" { Remove-Item -LiteralPath $Script:StateFile -Force -ErrorAction SilentlyContinue; Write-Info "State reset." }
        "update-manifests" { Update-Manifests }
        "update-mihomo-cache" { Update-MihomoCache }
        "self-test" { & (Join-Path $Script:Root "tests/test-envpilot.ps1") }
        "help" { Show-Usage }
    }
} catch {
    Write-Error $_
    exit 1
}
