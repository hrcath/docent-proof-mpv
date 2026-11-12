<#
  Docent-Proof MPV - turn OFF the settings web page.
  The player keeps running. The page comes back the next time
  start-docent.bat runs (it also runs automatically at login).
#>
$App     = $PSScriptRoot
$LogFile = Join-Path $App 'config-server.log'

$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -like '*config-server.ps1*' })

if ($procs.Count -eq 0) {
    Write-Host 'The settings web page was not running.'
} else {
    foreach ($p in $procs) {
        try {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
            Write-Host "Stopped settings web page (process $($p.ProcessId))."
        } catch {
            Write-Host "Could not stop process $($p.ProcessId): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    try {
        Add-Content -LiteralPath $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss}  Config panel stopped by stop-panel.bat" -f (Get-Date))
    } catch { }
}
Write-Host 'Run start-docent.bat to turn it back on.'
