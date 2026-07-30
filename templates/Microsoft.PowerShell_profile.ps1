# PowerShell profile managed by envpilot.
$EnvpilotConfigDir = Join-Path $HOME ".config/envpilot"
$EnvpilotSecrets = Join-Path $HOME ".config/secrets/api.env.ps1"

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
    param([string]$HostName = "127.0.0.1", [int]$Port = 7890)
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
    param([string]$HostName = "127.0.0.1", [int]$Port = 7890)
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
    if (Test-MihomoPort) {
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
    if (Test-MihomoPort) {
        Write-Host "  127.0.0.1:7890 listening"
    } else {
        Write-Host "  127.0.0.1:7890 not listening"
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

