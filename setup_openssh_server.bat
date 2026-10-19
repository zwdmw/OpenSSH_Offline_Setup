@echo off
setlocal EnableExtensions
title Windows OpenSSH Server Setup and Diagnostics

rem Pass the intended SSH login account as the first argument.
rem If omitted, the current Windows account is used.
if "%~1"=="" (
    set "SSH_LOGIN_USER=%USERNAME%"
) else (
    set "SSH_LOGIN_USER=%~1"
)
set "OPENSSH_SCRIPT_DIR=%~dp0"
set "OPENSSH_SCRIPT_PATH=%~f0"

fltmc >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting administrator privileges...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:OPENSSH_SCRIPT_PATH -ArgumentList $env:SSH_LOGIN_USER -Verb RunAs"
    exit /b
)

chcp 65001 >nul

for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"`) do set "LOG_TIMESTAMP=%%I"
if not defined LOG_TIMESTAMP set "LOG_TIMESTAMP=unknown_time"
set "LOG_FILE=%~dp0OpenSSH_Setup_%COMPUTERNAME%_%LOG_TIMESTAMP%.txt"

echo Running OpenSSH setup and diagnostics...
echo A detailed log will be saved to:
echo %LOG_FILE%
echo.

call :run_setup > "%LOG_FILE%" 2>&1
set "SETUP_RESULT=%errorlevel%"

type "%LOG_FILE%"
echo.
echo ============================================================
if "%SETUP_RESULT%"=="0" (
    echo RESULT: SUCCESS
) else (
    echo RESULT: FAILED - send the TXT log for further diagnosis.
)
echo LOG: %LOG_FILE%
echo ============================================================
pause
exit /b %SETUP_RESULT%

:run_setup
echo ============================================================
echo Windows OpenSSH Server Setup and Diagnostics
echo ============================================================
echo Start time: %date% %time%
echo Computer: %COMPUTERNAME%
echo Running account: %USERDOMAIN%\%USERNAME%
echo Intended SSH account: %SSH_LOGIN_USER%
echo Script: %~f0
echo Log: %LOG_FILE%

echo.
echo [PRE-CHECK] Collecting system state before changes...
call :collect_diagnostics

echo.
echo [1/4] Checking and installing OpenSSH Server...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1;" ^
  "if (-not $capability) { Write-Error 'OpenSSH Server capability is not available on this Windows version.'; exit 10 };" ^
  "Write-Host ('Capability before installation: ' + $capability.Name + ' / ' + $capability.State);" ^
  "$offlineMsi = Get-ChildItem -LiteralPath $env:OPENSSH_SCRIPT_DIR -Filter 'OpenSSH-Win64*.msi' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1;" ^
  "$existingService = Get-Service -Name 'sshd' -ErrorAction SilentlyContinue;" ^
  "if ($capability.State -eq 'Installed') {" ^
  "  Write-Host 'OpenSSH Server is already installed as a Windows capability.';" ^
  "} elseif ($existingService) {" ^
  "  Write-Host 'OpenSSH Server is already installed outside Windows capability management.';" ^
  "} elseif ($offlineMsi) {" ^
  "  Write-Host ('Installing offline MSI: ' + $offlineMsi.FullName);" ^
  "  $arguments = '/i ' + [char]34 + $offlineMsi.FullName + [char]34 + ' /qn /norestart';" ^
  "  $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru;" ^
  "  Write-Host ('MSI exit code: ' + $process.ExitCode);" ^
  "  if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) { Write-Error ('Offline MSI installation failed with exit code ' + $process.ExitCode); exit 11 };" ^
  "  if (-not (Get-Service -Name 'sshd' -ErrorAction SilentlyContinue)) { Write-Error 'Offline MSI completed but the sshd service was not found.'; exit 12 };" ^
  "  Write-Host 'Installation method: offline MSI';" ^
  "} else {" ^
  "  try {" ^
  "    Write-Host ('No offline MSI was found; trying Windows capability installation for ' + $capability.Name + ' ...');" ^
  "    $result = Add-WindowsCapability -Online -Name $capability.Name;" ^
  "    $result | Format-List Path, Online, RestartNeeded;" ^
  "    $capability = Get-WindowsCapability -Online -Name $capability.Name;" ^
  "    if ($capability.State -ne 'Installed') { throw 'Windows capability installation did not reach the Installed state.' };" ^
  "    Write-Host 'Installation method: Windows capability';" ^
  "  } catch {" ^
  "    Write-Error ('Windows capability installation failed and no offline MSI is available: ' + $_.Exception.Message); exit 13;" ^
  "  }" ^
  "};" ^
  "$capability = Get-WindowsCapability -Online -Name $capability.Name;" ^
  "Write-Host ('Capability after installation: ' + $capability.Name + ' / ' + $capability.State)"
if errorlevel 1 (
    set "FAILED_CODE=%errorlevel%"
    set "FAILED_STEP=OpenSSH Server installation"
    goto :setup_failed
)

echo.
echo [2/4] Starting SSH service and enabling automatic startup...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$service = Get-Service -Name 'sshd' -ErrorAction Stop;" ^
  "Set-Service -Name 'sshd' -StartupType Automatic;" ^
  "if ($service.Status -ne 'Running') { Start-Service -Name 'sshd' };" ^
  "Get-Service -Name 'sshd' | Format-Table Name, Status, StartType -AutoSize;" ^
  "Get-CimInstance Win32_Service | Where-Object { $_.Name -eq 'sshd' } | Format-List Name, State, StartMode, PathName, StartName"
if errorlevel 1 (
    set "FAILED_CODE=%errorlevel%"
    set "FAILED_STEP=sshd service startup"
    goto :setup_failed
)

echo.
echo [3/4] Configuring Windows Firewall...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$ruleName = 'OpenSSH-Server-In-TCP';" ^
  "$rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue;" ^
  "if ($rule) {" ^
  "  Enable-NetFirewallRule -Name $ruleName;" ^
  "  Set-NetFirewallRule -Name $ruleName -Enabled True -Action Allow -Direction Inbound;" ^
  "  Write-Host 'Updated the existing OpenSSH firewall rule.';" ^
  "} else {" ^
  "  New-NetFirewallRule -Name $ruleName -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Profile Any -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null;" ^
  "  Write-Host 'Created the OpenSSH firewall rule.';" ^
  "};" ^
  "Get-NetFirewallRule -Name $ruleName | Format-List Name, DisplayName, Enabled, Profile, Direction, Action"
if errorlevel 1 (
    set "FAILED_CODE=%errorlevel%"
    set "FAILED_STEP=Windows Firewall configuration"
    goto :setup_failed
)

echo.
echo [4/4] Validating configuration and TCP port 22...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$sshd = @((Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'), (Join-Path $env:ProgramFiles 'OpenSSH\sshd.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1;" ^
  "if (-not $sshd) { Write-Error 'sshd.exe was not found in the Windows capability or MSI installation paths.'; exit 14 };" ^
  "Write-Host ('sshd executable: ' + $sshd);" ^
  "Write-Host 'Running sshd configuration validation...';" ^
  "& $sshd -t 2>&1 | ForEach-Object { Write-Host $_ };" ^
  "if ($LASTEXITCODE -ne 0) { Write-Error ('sshd configuration validation failed with exit code ' + $LASTEXITCODE); exit 15 };" ^
  "$listener = Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue;" ^
  "if (-not $listener) { Write-Error 'sshd is not listening on TCP port 22.'; exit 16 };" ^
  "$test = Test-NetConnection -ComputerName 127.0.0.1 -Port 22 -WarningAction SilentlyContinue;" ^
  "$test | Format-List ComputerName, RemoteAddress, RemotePort, SourceAddress, TcpTestSucceeded;" ^
  "if (-not $test.TcpTestSucceeded) { Write-Error 'The local TCP connection test to port 22 failed.'; exit 17 };" ^
  "Write-Host 'OpenSSH configuration and local TCP port test succeeded.'"
if errorlevel 1 (
    set "FAILED_CODE=%errorlevel%"
    set "FAILED_STEP=OpenSSH validation"
    goto :setup_failed
)

echo.
echo [POST-CHECK] Collecting final system state...
call :collect_diagnostics

echo.
echo ============================================================
echo SETUP RESULT: SUCCESS
echo Connect from Linux with: ssh %SSH_LOGIN_USER%@TARGET_IP
echo End time: %date% %time%
echo ============================================================
exit /b 0

:setup_failed
echo.
echo ============================================================
echo SETUP RESULT: FAILED
echo Failed step: %FAILED_STEP%
echo Error level: %FAILED_CODE%
echo Collecting failure diagnostics...
echo ============================================================
call :collect_diagnostics
echo.
echo End time: %date% %time%
exit /b 1

:collect_diagnostics
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Continue';" ^
  "function Section([string]$title) { Write-Host ''; Write-Host ('----- ' + $title + ' -----') };" ^
  "Section 'System';" ^
  "Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime | Format-List;" ^
  "Get-CimInstance Win32_ComputerSystem | Select-Object Name, Domain, PartOfDomain, Manufacturer, Model | Format-List;" ^
  "Write-Host ('PowerShell version: ' + $PSVersionTable.PSVersion);" ^
  "Write-Host ('Current identity: ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name);" ^
  "Write-Host ('Administrator: ' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator));" ^
  "Section 'Target SSH account';" ^
  "$targetUser = Get-LocalUser -Name $env:SSH_LOGIN_USER -ErrorAction SilentlyContinue;" ^
  "if ($targetUser) { $targetUser | Select-Object Name, Enabled, PasswordRequired, PasswordExpires, UserMayChangePassword, LastLogon, Description | Format-List } else { Write-Warning ('Local user was not found: ' + $env:SSH_LOGIN_USER) };" ^
  "Section 'OpenSSH capability';" ^
  "Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Format-List Name, State, DisplayName, Description;" ^
  "Section 'Windows servicing configuration';" ^
  "Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue | Select-Object UseWUServer, NoAutoUpdate, AUOptions | Format-List;" ^
  "Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing' -ErrorAction SilentlyContinue | Format-List;" ^
  "$dismLog = Join-Path $env:WINDIR 'Logs\DISM\dism.log';" ^
  "if (Test-Path -LiteralPath $dismLog) { Write-Host ('Recent DISM log: ' + $dismLog); Get-Content -LiteralPath $dismLog -Tail 80 -ErrorAction SilentlyContinue } else { Write-Host 'DISM log was not found.' };" ^
  "Section 'sshd executable';" ^
  "$sshd = @((Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'), (Join-Path $env:ProgramFiles 'OpenSSH\sshd.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1;" ^
  "if ($sshd) { Get-Item -LiteralPath $sshd | Select-Object FullName, Length, LastWriteTime, @{Name='FileVersion';Expression={$_.VersionInfo.FileVersion}}, @{Name='ProductVersion';Expression={$_.VersionInfo.ProductVersion}} | Format-List } else { Write-Warning 'sshd.exe was not found in known installation paths.' };" ^
  "Section 'sshd service';" ^
  "Get-Service -Name 'sshd' -ErrorAction SilentlyContinue | Format-List Name, DisplayName, Status, StartType;" ^
  "Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'sshd' } | Format-List Name, State, Status, StartMode, ProcessId, PathName, StartName, ExitCode;" ^
  "sc.exe queryex sshd 2>&1; sc.exe qc sshd 2>&1;" ^
  "Section 'TCP port 22';" ^
  "Get-NetTCPConnection -LocalPort 22 -ErrorAction SilentlyContinue | Sort-Object State | Format-Table LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess -AutoSize;" ^
  "netstat.exe -ano 2>&1 | Select-String -Pattern ':22\s';" ^
  "Test-NetConnection -ComputerName 127.0.0.1 -Port 22 -InformationLevel Detailed -WarningAction SilentlyContinue | Format-List ComputerName, RemoteAddress, RemotePort, NameResolutionResults, SourceAddress, TcpTestSucceeded;" ^
  "Section 'Windows Firewall rule';" ^
  "$firewallRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue;" ^
  "if ($firewallRule) { $firewallRule | Format-List Name, DisplayName, Enabled, Profile, Direction, Action, PolicyStoreSourceType; $firewallRule | Get-NetFirewallPortFilter | Format-List Protocol, LocalPort, RemotePort } else { Write-Warning 'OpenSSH firewall rule was not found.' };" ^
  "Get-NetFirewallProfile | Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction -AutoSize;" ^
  "Section 'Network configuration';" ^
  "Get-NetIPConfiguration | Format-List InterfaceAlias, InterfaceDescription, NetProfile, IPv4Address, IPv4DefaultGateway, DNSServer;" ^
  "Section 'sshd_config';" ^
  "$config = Join-Path $env:ProgramData 'ssh\sshd_config';" ^
  "if (Test-Path -LiteralPath $config) { Write-Host ('Config path: ' + $config); Get-Content -LiteralPath $config } else { Write-Warning ('Config file was not found: ' + $config) };" ^
  "Section 'Effective sshd configuration';" ^
  "if (Test-Path -LiteralPath $sshd) { & $sshd -T 2>&1 | ForEach-Object { $_ } };" ^
  "Section 'Recent OpenSSH events';" ^
  "$events = Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 30 -ErrorAction SilentlyContinue;" ^
  "if ($events) { $events | Select-Object TimeCreated, Id, LevelDisplayName, Message | Format-List } else { Write-Host 'No OpenSSH/Operational events were found.' };" ^
  "Section 'End diagnostics'"
exit /b 0
