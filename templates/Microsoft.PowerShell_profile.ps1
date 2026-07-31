# PowerShell profile managed by envpilot.
$EnvpilotConfigDir = Join-Path $HOME ".config/envpilot"
$EnvpilotSecrets = Join-Path $HOME ".config/secrets/api.env.ps1"
$Global:EnvpilotProxyHost = if ($Global:EnvpilotProxyHost) { $Global:EnvpilotProxyHost } else { "127.0.0.1" }
$Global:EnvpilotProxyPort = if ($env:MIHOMO_PROXY_PORT) { [int]$env:MIHOMO_PROXY_PORT } elseif ($Global:EnvpilotProxyPort) { [int]$Global:EnvpilotProxyPort } else { 42290 }
$Global:EnvpilotApiPort = if ($env:MIHOMO_API_PORT) { [int]$env:MIHOMO_API_PORT } elseif ($Global:EnvpilotApiPort) { [int]$Global:EnvpilotApiPort } else { 60290 }

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

function Get-EnvpilotProxyPort {
    if ($env:MIHOMO_PROXY_PORT -match '^\d+$') { return [int]$env:MIHOMO_PROXY_PORT }
    if ($EnvpilotProxyPort -match '^\d+$') { return [int]$EnvpilotProxyPort }
    return [int]$Global:EnvpilotProxyPort
}

function Get-EnvpilotApiPort {
    if ($env:MIHOMO_API_PORT -match '^\d+$') { return [int]$env:MIHOMO_API_PORT }
    return [int]$Global:EnvpilotApiPort
}

function Enable-EnvpilotProxy {
    param([string]$HostName = $Global:EnvpilotProxyHost, [int]$Port = (Get-EnvpilotProxyPort))
    $proxy = "http://${HostName}:${Port}"
    $env:http_proxy = $proxy
    $env:https_proxy = $proxy
    $env:HTTP_PROXY = $proxy
    $env:HTTPS_PROXY = $proxy
    $env:all_proxy = "socks5h://${HostName}:${Port}"
    $env:ALL_PROXY = $env:all_proxy
    $env:no_proxy = "localhost,127.0.0.1,::1"
    $env:NO_PROXY = $env:no_proxy
}

function Disable-EnvpilotProxy {
    foreach ($name in "http_proxy","https_proxy","HTTP_PROXY","HTTPS_PROXY","all_proxy","ALL_PROXY") {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    $env:no_proxy = "localhost,127.0.0.1,::1"
    $env:NO_PROXY = $env:no_proxy
}

function Get-MihomoBin {
    Join-Path $HOME "software/mihomo/mihomo.exe"
}

function Test-MihomoPort {
    param([string]$HostName = $Global:EnvpilotProxyHost, [int]$Port = (Get-EnvpilotProxyPort))
    $listen = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Where-Object {
        $_.LocalAddress -in @($HostName, "0.0.0.0", "::", "::1")
    } | Select-Object -First 1
    return [bool]$listen
}

function Test-MihomoApi {
    param([int]$Port = (Get-EnvpilotApiPort))
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

function Set-EnvpilotYamlScalar {
    param([string]$Path, [string]$Key, [string]$Value)
    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path) { [void]$lines.Add($line) }
    }
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*:") {
            if (-not $found) { $lines[$i] = "${Key}: $Value" }
            else { $lines.RemoveAt($i); $i-- }
            $found = $true
        }
    }
    if (-not $found) { $lines.Insert(0, "${Key}: $Value") }
    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Set-MihomoLocalConfig {
    param([int]$ProxyPort = (Get-EnvpilotProxyPort), [int]$ApiPort = (Get-EnvpilotApiPort), [string]$Path = (Join-Path $HOME ".config/mihomo/config.yaml"))
    Set-EnvpilotYamlScalar -Path $Path -Key "allow-lan" -Value "false"
    Set-EnvpilotYamlScalar -Path $Path -Key "mixed-port" -Value ([string]$ProxyPort)
    Set-EnvpilotYamlScalar -Path $Path -Key "bind-address" -Value "127.0.0.1"
    Set-EnvpilotYamlScalar -Path $Path -Key "external-controller" -Value "127.0.0.1:$ApiPort"
}

function Start-Mihomo {
    $bin = Get-MihomoBin
    $configDir = Join-Path $HOME ".config/mihomo"
    $config = Join-Path $configDir "config.yaml"
    $proxyPort = Get-EnvpilotProxyPort
    $apiPort = Get-EnvpilotApiPort
    if (-not (Test-Path -LiteralPath $bin)) { throw "Mihomo executable not found: $bin" }
    if (-not (Test-Path -LiteralPath $config)) { throw "Mihomo config not found: $config" }
    if (Test-MihomoApi -Port $apiPort) { Write-Info "Mihomo is already running and healthy."; return }
    if (Test-MihomoPort -Port $proxyPort) { throw "Proxy port 127.0.0.1:$proxyPort is already in use." }
    if (Test-MihomoPort -Port $apiPort) { throw "API port 127.0.0.1:$apiPort is already in use." }
    Set-MihomoLocalConfig -ProxyPort $proxyPort -ApiPort $apiPort -Path $config
    Start-Process -WindowStyle Hidden -FilePath $bin -ArgumentList @("-d", $configDir) | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        if ((Test-MihomoPort -Port $proxyPort) -and (Test-MihomoApi -Port $apiPort)) {
            Write-Info "Mihomo is ready: proxy=$proxyPort API=$apiPort"
            return
        }
        Start-Sleep -Seconds 1
    }
    throw "Mihomo did not become healthy within 30 seconds."
}

function Stop-Mihomo {
    $bin = Get-MihomoBin
    $processes = @(Get-Process -Name mihomo -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -eq $bin -or $_.Path -like "*\software\mihomo\mihomo.exe" } catch { $false }
    })
    foreach ($process in $processes) {
        Stop-Process -Id $process.Id -Force
        Write-Info "Stopped Mihomo process: $($process.Id)"
    }
    if ($processes.Count -eq 0) { Write-Info "No envpilot-managed Mihomo process found." }
}

function Get-MihomoStatus {
    $proxyPort = Get-EnvpilotProxyPort
    $apiPort = Get-EnvpilotApiPort
    Write-Host "Mihomo process:"
    $processes = @(Get-Process -Name mihomo -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -like "*\software\mihomo\mihomo.exe" } catch { $false }
    })
    if ($processes.Count -eq 0) { Write-Host "  not running" }
    else { foreach ($process in $processes) { Write-Host "  $($process.Id) $($process.Path)" } }
    Write-Host ""
    Write-Host "ports:"
    Write-Host "  proxy 127.0.0.1:$proxyPort $(if (Test-MihomoPort -Port $proxyPort) { 'listening' } else { 'not detected' })"
    Write-Host "  API   127.0.0.1:$apiPort $(if (Test-MihomoPort -Port $apiPort) { 'listening' } else { 'not detected' })"
    Write-Host "  API health: $(if (Test-MihomoApi -Port $apiPort) { 'OK' } else { 'FAILED' })"
    Write-Host ""
    Write-Host "proxy variables:"
    Write-Host "  http_proxy=$(if ($env:http_proxy) { $env:http_proxy } else { 'unset' })"
    Write-Host "  https_proxy=$(if ($env:https_proxy) { $env:https_proxy } else { 'unset' })"
    Write-Host "  all_proxy=$(if ($env:all_proxy) { $env:all_proxy } else { 'unset' })"
}

function Save-MihomoPorts {
    param([int]$ProxyPort, [int]$ApiPort)
    $localProfile = Join-Path $EnvpilotConfigDir "profile.local.ps1"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $localProfile) | Out-Null
    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $localProfile) {
        Get-Content -LiteralPath $localProfile | Where-Object {
            $_ -notmatch '^\s*\$env:MIHOMO_(?:PROXY|API)_PORT\s*=' -and
            $_ -notmatch '^\s*\$(?:Global:)?Envpilot(?:Proxy|Api)Port\s*='
        } | ForEach-Object { [void]$lines.Add($_) }
    } else {
        [void]$lines.Add("# envpilot profile.local.ps1")
    }
    [void]$lines.Add(('$env:MIHOMO_PROXY_PORT = ''{0}''' -f $ProxyPort))
    [void]$lines.Add(('$env:MIHOMO_API_PORT = ''{0}''' -f $ApiPort))
    Set-Content -LiteralPath $localProfile -Value $lines -Encoding UTF8
}

function Set-MihomoPorts {
    param([Parameter(Mandatory=$true)][int]$ProxyPort, [Parameter(Mandatory=$true)][int]$ApiPort)
    if ($ProxyPort -lt 1 -or $ProxyPort -gt 65535 -or $ApiPort -lt 1 -or $ApiPort -gt 65535 -or $ProxyPort -eq $ApiPort) {
        throw "Usage: mihomo ports PROXY_PORT API_PORT"
    }
    $config = Join-Path $HOME ".config/mihomo/config.yaml"
    if (-not (Test-Path -LiteralPath (Get-MihomoBin))) { throw "Mihomo executable not found." }
    if (-not (Test-Path -LiteralPath $config)) { throw "Mihomo config not found: $config" }
    $proxyWasEnabled = [bool]$env:http_proxy
    Stop-Mihomo
    if (Test-MihomoPort -Port $ProxyPort) { throw "Proxy port 127.0.0.1:$ProxyPort is already in use." }
    if (Test-MihomoPort -Port $ApiPort) { throw "API port 127.0.0.1:$ApiPort is already in use." }
    Set-MihomoLocalConfig -ProxyPort $ProxyPort -ApiPort $ApiPort -Path $config
    Save-MihomoPorts -ProxyPort $ProxyPort -ApiPort $ApiPort
    $env:MIHOMO_PROXY_PORT = [string]$ProxyPort
    $env:MIHOMO_API_PORT = [string]$ApiPort
    $Global:EnvpilotProxyPort = $ProxyPort
    $Global:EnvpilotApiPort = $ApiPort
    Start-Mihomo
    if ($proxyWasEnabled) {
        Disable-EnvpilotProxy
        Enable-EnvpilotProxy
    }
    Write-Info "Current PowerShell Mihomo ports: proxy=$ProxyPort API=$ApiPort"
}

function Set-MihomoPort {
    param([Parameter(Mandatory=$true)][int]$Port)
    Set-MihomoPorts -ProxyPort $Port -ApiPort (Get-EnvpilotApiPort)
}

function Update-MihomoSubscription {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { $Url = Read-Host "Paste Clash/Mihomo subscription URL" }
    if ($Url -notmatch '^https?://') { throw "Provide a Clash/Mihomo subscription URL beginning with http:// or https://." }
    $config = Join-Path $HOME ".config/mihomo/config.yaml"
    $configDir = Split-Path -Parent $config
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $temp = Join-Path $configDir ("config.yaml.new." + [guid]::NewGuid().ToString("N"))
    $backup = "$config.bak.$(Get-Date -Format yyyyMMddHHmmss)"
    $wasRunning = Test-MihomoApi
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $temp
        if ((Get-Item -LiteralPath $temp).Length -eq 0) { throw "Downloaded subscription config is empty." }
        if ((Get-Content -LiteralPath $temp -TotalCount 1) -match '^\s*<(?:html|!doctype)') {
            throw "Downloaded content looks like HTML, not a Mihomo configuration."
        }
        if (Test-Path -LiteralPath $config) { Copy-Item -LiteralPath $config -Destination $backup -Force }
        Move-Item -LiteralPath $temp -Destination $config -Force
        Set-MihomoLocalConfig -ProxyPort (Get-EnvpilotProxyPort) -ApiPort (Get-EnvpilotApiPort) -Path $config
        if ($wasRunning) {
            Stop-Mihomo
            try {
                Start-Mihomo
            } catch {
                if (Test-Path -LiteralPath $backup) {
                    Copy-Item -LiteralPath $backup -Destination $config -Force
                    Start-Mihomo
                }
                throw
            }
        }
        Write-Info "Mihomo subscription updated: $config"
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
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
        "ports" { Set-MihomoPorts -ProxyPort ([int]$Args[0]) -ApiPort ([int]$Args[1]); break }
        { $_ -in @("update-subscription", "subscription") } { Update-MihomoSubscription -Url $Args[0]; break }
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
