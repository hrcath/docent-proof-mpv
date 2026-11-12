<#
  Docent-Proof MPV - one-time setup (needs Administrator; it will ask).
  Double-click "setup.bat" rather than running this directly.

    1. Lets the settings panel listen on the network (URL reservation)
    2. Opens the panel's port in Windows Firewall (local network only)
    3. Starts Docent-Proof MPV automatically when anyone logs in
    4. Stops the screen and PC from going to sleep (plugged in)
#>
param([switch]$Elevated)

$ErrorActionPreference = 'Stop'
$App = $PSScriptRoot

# --- re-launch as Administrator if needed
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($Elevated) { Write-Host 'Could not get Administrator rights.'; Read-Host 'Press Enter to close'; exit 1 }
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
    exit
}

# --- read the port from start-docent.bat so the two always match
$Port = 8080
$bat = Join-Path $App 'start-docent.bat'
$m = Select-String -LiteralPath $bat -Pattern 'set "PANEL_PORT=(\d+)"' | Select-Object -First 1
if ($m) { $Port = [int]$m.Matches[0].Groups[1].Value }
Write-Host "Docent-Proof MPV setup (panel port $Port)`n"

try {
    # 1. URL reservation so the panel can run without admin rights
    netsh http delete urlacl url="http://+:$Port/" 2>&1 | Out-Null
    $out = netsh http add urlacl url="http://+:$Port/" sddl="D:(A;;GX;;;WD)" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "URL reservation failed: $out" }
    Write-Host "[ok] Network access reserved for port $Port"

    # 2. Firewall: allow devices on the same local network only
    # (also removes the rule made by earlier versions, which used the old name)
    Get-NetFirewallRule -DisplayName 'Docent-Proof MPV Panel', 'Docent Player Panel' -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName 'Docent-Proof MPV Panel' -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort $Port -RemoteAddress LocalSubnet -Profile Any | Out-Null
    Write-Host "[ok] Firewall opened for port $Port (local network only)"

    # 3. Start at login (all users), console window minimized
    $startup = [Environment]::GetFolderPath('CommonStartup')
    $oldLnk  = Join-Path $startup 'Docent Player.lnk'     # name used by earlier versions
    if (Test-Path -LiteralPath $oldLnk) { Remove-Item -LiteralPath $oldLnk -Force }
    $lnkPath = Join-Path $startup 'Docent-Proof MPV.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($lnkPath)
    $lnk.TargetPath = $bat
    $lnk.WorkingDirectory = $App
    $lnk.WindowStyle = 7
    $lnk.Save()
    Write-Host "[ok] Starts automatically at login ($lnkPath)"

    # 4. Never sleep / blank the screen while plugged in
    powercfg /change monitor-timeout-ac 0
    powercfg /change standby-timeout-ac 0
    Write-Host "[ok] Screen and sleep timeouts disabled (plugged in)"

    if (-not (Test-Path -LiteralPath (Join-Path $App 'mpv\mpv.exe'))) {
        Write-Host "`n[!] mpv.exe is not in $App\mpv\ yet - see README.md, Installation step 2." -ForegroundColor Yellow
    }
    Write-Host "`nSetup complete. Double-click start-docent.bat (or log out and back in) to start."
} catch {
    Write-Host "`n[x] $($_.Exception.Message)" -ForegroundColor Red
}
Read-Host "`nPress Enter to close"
