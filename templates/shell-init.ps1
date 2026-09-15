# envpilot 0.4 PowerShell integration. Original profile content is preserved.
$EnvpilotConfigDirectory = if ($env:ENVPILOT_CONFIG_DIR) { $env:ENVPILOT_CONFIG_DIR } else { Join-Path $HOME '.config/envpilot' }
$EnvpilotCompiled = Join-Path $EnvpilotConfigDirectory 'shell/config.ps1'
if (Test-Path -LiteralPath $EnvpilotCompiled) { . $EnvpilotCompiled }
foreach ($EnvpilotPath in @((Join-Path $HOME '.local/bin')) + @($EnvpilotExtraPaths)) {
    if ($EnvpilotPath -and (Test-Path -LiteralPath $EnvpilotPath) -and $EnvpilotPath -notin ($env:PATH -split [IO.Path]::PathSeparator)) {
        $env:PATH += [IO.Path]::PathSeparator + $EnvpilotPath
    }
}
function Enable-EnvpilotProxy {
    $client = [Net.Sockets.TcpClient]::new()
    try { $task = $client.ConnectAsync('127.0.0.1', [int]$env:MIHOMO_PROXY_PORT); if (-not $task.Wait(1000) -or -not $client.Connected) { return } }
    catch { return } finally { $client.Dispose() }
    $env:http_proxy = $env:https_proxy = "http://127.0.0.1:$env:MIHOMO_PROXY_PORT"
    if ($env:BASHRC_PROXY_ENABLE_SOCKS -eq '1') { $env:all_proxy = "socks5h://127.0.0.1:$env:MIHOMO_PROXY_PORT" }
    $env:no_proxy = ((@($env:no_proxy -split ',') + @('localhost','127.0.0.1','::1')) | Where-Object { $_ } | Select-Object -Unique) -join ','
}
function Disable-EnvpilotProxy { 'http_proxy','https_proxy','all_proxy' | ForEach-Object { Remove-Item -LiteralPath "Env:$_" -ErrorAction SilentlyContinue } }
if ($env:BASHRC_AUTO_START_MIHOMO -eq '1') { & envpilot mihomo start *> $null }
if ($env:BASHRC_AUTO_ENABLE_PROXY -eq '1') { Enable-EnvpilotProxy }
if ($env:BASHRC_AUTO_LOAD_SECRETS -eq '1') {
    $EnvpilotCore = Join-Path $env:ENVPILOT_ROOT 'bin/envpilot-core.exe'
    if (-not (Test-Path -LiteralPath $EnvpilotCore)) { $EnvpilotCore = Join-Path $HOME '.local/lib/envpilot/0.4.0/envpilot-core.exe' }
    if (Test-Path -LiteralPath $EnvpilotCore) {
        $EnvpilotSecretData = & $EnvpilotCore secret-export --config $env:ENVPILOT_CONFIG_FILE 2>$null
        if ($LASTEXITCODE -eq 0 -and $EnvpilotSecretData) {
            foreach ($EnvpilotProperty in ($EnvpilotSecretData | ConvertFrom-Json).PSObject.Properties) {
                [Environment]::SetEnvironmentVariable($EnvpilotProperty.Name, [string]$EnvpilotProperty.Value)
            }
        }
        Remove-Variable EnvpilotSecretData, EnvpilotProperty -ErrorAction SilentlyContinue
    }
}
if ($env:BASHRC_INIT_CONDA -eq '1' -and -not (Get-Command conda -ErrorAction SilentlyContinue)) {
    $EnvpilotConda = Join-Path $env:EP_PREFIX 'miniconda3/shell/condabin/conda-hook.ps1'
    if (Test-Path -LiteralPath $EnvpilotConda) { . $EnvpilotConda }
}
if ($env:ENVPILOT_LEGACY_LOCAL -eq '1') {
    $EnvpilotLocal = Join-Path $EnvpilotConfigDirectory 'shell.local.ps1'
    if (Test-Path -LiteralPath $EnvpilotLocal) { . $EnvpilotLocal }
}
