# PowerShell profile managed by envpilot.
$EnvpilotConfigDir = Join-Path $HOME ".config/envpilot"
$EnvpilotSecrets = Join-Path $HOME ".config/secrets/api.env.ps1"
$Global:EnvpilotProxyHost = if ($Global:EnvpilotProxyHost) { $Global:EnvpilotProxyHost } else { "127.0.0.1" }
$Global:EnvpilotProxyPort = if ($Global:EnvpilotProxyPort) { [int]$Global:EnvpilotProxyPort } else { 7890 }

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" }

function Add-PathFront {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $parts = [System.Collections.Generic.List[string]]::new()
        $env:PATH -split [System.IO.Path]::PathSeparator | Where-Object { $_ } | ForEach-Object { [void]$parts.Add($_) }
        if ($parts -notcontains $Path) {
            $env:PATH = $Path + [System.IO.Path]::PathSeparator + $env:PATH
        }
    }
}

Add-PathFront (Join-Path $HOME ".local/bin")
Add-PathFront (Join-Path $HOME "bin")
Add-PathFront (Join-Path $HOME "software/bin")

function Use-EnvpilotSecrets {
    param([string]$Path = $EnvpilotSecrets)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Secret file not found: $Path"
    }
    . $Path
}

function Enable-EnvpilotProxy {
    param([string]$HostName = $Global:EnvpilotProxyHost, [int]$Port = $Global:EnvpilotProxyPort)
    $proxy = "http://${HostName}:${Port}"
    $env:http_proxy = $proxy
    $env:https_proxy = $proxy
    $env:HTTP_PROXY = $proxy
    $env:HTTPS_PROXY = $proxy
    $env:all_proxy = "socks5://${HostName}:${Port}"
    $env:ALL_PROXY = $env:all_proxy
    $env:no_proxy = "localhost,127.0.0.1,::1"
    $env:NO_PROXY = $env:no_proxy
}

function Disable-EnvpilotProxy {
    "http_proxy","https_proxy","HTTP_PROXY","HTTPS_PROXY","all_proxy","ALL_PROXY","no_proxy","NO_PROXY" | ForEach-Object {
        Remove-Item "Env:\$_" -ErrorAction SilentlyContinue
    }
}

function Get-MihomoBin {
    Join-Path $HOME "software/mihomo/mihomo.exe"
}

function Test-MihomoPort {
    param([string]$HostName = $Global:EnvpilotProxyHost, [int]$Port = $Global:EnvpilotProxyPort)
    $listen = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Where-Object {
        $_.LocalAddress -in @($HostName, "0.0.0.0", "::", "::1")
    } | Select-Object -First 1
    return [bool]$listen
}

function Start-Mihomo {
    $bin = Get-MihomoBin
    $configDir = Join-Path $HOME ".config/mihomo"
    if (-not (Test-Path -LiteralPath $bin)) {
        throw "mihomo executable not found: $bin"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $configDir "config.yaml"))) {
        throw "mihomo config not found: $(Join-Path $configDir 'config.yaml')"
    }
    if (Test-MihomoPort -Port $Global:EnvpilotProxyPort) {
        Write-Info "mihomo already running."
        return
    }
    Start-Process -WindowStyle Hidden -FilePath $bin -ArgumentList @("-d", $configDir) | Out-Null
    Write-Info "mihomo start requested."
}

function Stop-Mihomo {
    $bin = Get-MihomoBin
    $processes = @(Get-Process -Name mihomo -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -eq $bin -or $_.Path -like "*\software\mihomo\mihomo.exe"
        } catch {
            $false
        }
    })
    foreach ($process in $processes) {
        Stop-Process -Id $process.Id -Force
    }
    if ($processes.Count -gt 0) {
        Start-Sleep -Seconds 1
        Write-Info "mihomo stopped."
    }
}

function Get-MihomoStatus {
    $bin = Get-MihomoBin
    $processes = @(Get-Process -Name mihomo -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -eq $bin -or $_.Path -like "*\software\mihomo\mihomo.exe"
        } catch {
            $false
        }
    })
    Write-Host "mihomo process:"
    if ($processes.Count -eq 0) {
        Write-Host "  not running"
    } else {
        foreach ($process in $processes) {
            Write-Host "  $($process.Id) $($process.Path)"
        }
    }
    Write-Host ""
    Write-Host "proxy port:"
    if (Test-MihomoPort -Port $Global:EnvpilotProxyPort) {
        Write-Host "  127.0.0.1:$Global:EnvpilotProxyPort listening"
    } else {
        Write-Host "  127.0.0.1:$Global:EnvpilotProxyPort not listening"
    }
    Write-Host ""
    Write-Host "proxy variables:"
    $httpProxy = if ([string]::IsNullOrWhiteSpace($env:http_proxy)) { 'unset' } else { $env:http_proxy }
    $httpsProxy = if ([string]::IsNullOrWhiteSpace($env:https_proxy)) { 'unset' } else { $env:https_proxy }
    $allProxy = if ([string]::IsNullOrWhiteSpace($env:all_proxy)) { 'unset' } else { $env:all_proxy }
    Write-Host "  http_proxy=$httpProxy"
    Write-Host "  https_proxy=$httpsProxy"
    Write-Host "  all_proxy=$allProxy"
}

function Set-EnvpilotYamlScalar {
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

function Set-MihomoPort {
    param([Parameter(Mandatory=$true)][int]$Port)
    if ($Port -lt 1 -or $Port -gt 65535) { throw "Usage: mihomo port PORT (1-65535)" }
    $bin = Get-MihomoBin
    $configDir = Join-Path $HOME ".config/mihomo"
    $config = Join-Path $configDir "config.yaml"
    if (-not (Test-Path -LiteralPath $bin)) { throw "mihomo executable not found: $bin" }
    if (-not (Test-Path -LiteralPath $config)) { throw "mihomo config not found: $config" }
    Set-EnvpilotYamlScalar -Path $config -Key "allow-lan" -Value "false"
    Set-EnvpilotYamlScalar -Path $config -Key "mixed-port" -Value ([string]$Port)
    Set-EnvpilotYamlScalar -Path $config -Key "bind-address" -Value "127.0.0.1"
    $localProfile = Join-Path $EnvpilotConfigDir "profile.local.ps1"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $localProfile) | Out-Null
    "`$EnvpilotProxyPort = $Port" | Set-Content -LiteralPath $localProfile -Encoding UTF8
    Stop-Mihomo
    $Global:EnvpilotProxyPort = $Port
    Start-Mihomo
    Disable-EnvpilotProxy
    Enable-EnvpilotProxy
    Write-Info "Current PowerShell proxy variables now use $($Global:EnvpilotProxyHost):$($Global:EnvpilotProxyPort)."
}
function mihomo {
    param(
        [Parameter(Position=0)]
        [string]$Action = "start",
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$Args
    )
    switch ($Action.ToLowerInvariant()) {
        "start" { Start-Mihomo; break }
        "stop" { Stop-Mihomo; break }
        "status" { Get-MihomoStatus; break }
        "port" { Set-MihomoPort -Port ([int]$Args[0]); break }
        "proxy-on" { Enable-EnvpilotProxy; break }
        "proxy-off" { Disable-EnvpilotProxy; break }
        default {
            $bin = Get-MihomoBin
            if (-not (Test-Path -LiteralPath $bin)) {
                throw "mihomo executable not found: $bin"
            }
            & $bin $Action @Args
        }
    }
}
$localProfile = Join-Path $EnvpilotConfigDir "profile.local.ps1"
if (Test-Path -LiteralPath $localProfile) {
    . $localProfile
}

