# ==============================================================================
# DevTools2 오프라인 가져오기 (import-devtools2-offline.ps1)
# ==============================================================================
#
# ■ 목적:
#   명령 팔레트의 "개발 환경 내보내기 (오프라인 PC 설치용)"(scripts/offline/export-wsl-bundle.sh)로 만든 묶음을, 인터넷이 없는 PC 에서
#   그대로 구성합니다. 묶음 폴더의 "DevTools2 개발 환경 가져오기.cmd" 를 실행하면 이 스크립트가 관리자 권한으로 실행됩니다.
#
# ■ ⚠️ AGENTS.md "오프라인 PC 개발 환경 가져오기 예외" — 이 파일(과 DevTools2 개발 환경 가져오기.cmd)만 로컬 파일로 실행됩니다:
#   다른 설치 스크립트는 GitHub 에서 받아 실행하는 온라인 전용(AGENTS.md 2번)이지만, 오프라인 PC 에는 인터넷이 없어
#   묶음 안의 파일로만 실행해야 합니다. 그래서 이 스크립트는 _common.ps1 등 온라인 공용 파일을 불러오지 않고 필요한 함수를
#   모두 스스로 정의하며, 인터넷 접속을 하지 않습니다. 기존 설치 스크립트에는 로컬 실행 분기를 넣지 않습니다.
#   - Windows PowerShell 5.1 은 디스크의 UTF-8(BOM 없음) 한글 스크립트를 CP949 로 잘못 읽으므로, DevTools2 개발 환경 가져오기.cmd 가
#     UTF-8 로 읽어 메모리에서 실행합니다(AGENTS.md 6번). 그래서 param() 대신 $global:DT2_BUNDLE 로 묶음 위치를 받습니다.
#
# ■ 하는 일 (모두 다시 실행해도 같은 상태 — 이미 된 단계는 건너뜀):
#   1. WSL 기능 켜기 (처음 켜면 재부팅 후 다시 실행)
#   2. WSL 설치 / 업데이트 (묶음의 wsl.<버전>.msi — 설치된 WSL 이 더 오래됐거나 없을 때)
#   3. WSL 배포판 가져오기 (wsl --import, 개발자 드라이브(ReFS)가 있으면 그곳 우선)
#   4. .wslconfig (없으면 묶음의 설정, WSL 메모리 상한은 이 PC 메모리로 계산 — 0.setup-wsl.ps1 과 같은 식)
#   5. 글꼴 (사용자 글꼴, 관리자 권한 없이도 되는 방식)
#   6. AutoHotkey 단축키 (포터블 복사 + 로그온 작업 등록 — 1.setup-autohotkey.ps1 과 같은 이름·위치)
#   7. Windows Terminal 설정 (기존 설정은 백업)
#   8. VS Code · Zed (지금 PC 와 같은 버전의 프로그램 폴더 + 확장 + 설정 — WSL 안 서버와 버전이 맞아야 하므로 설치 파일이 아닌 폴더째)
# ==============================================================================

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$ProgressPreference = 'SilentlyContinue'

# ── 출력 · 질문 헬퍼 (오프라인이라 _common.ps1 을 불러오지 않고 직접 정의) ─────
function Write-Step([string]$Msg) { Write-Host ""; Write-Host "▶ $Msg" -ForegroundColor Cyan }
function Write-Ok([string]$Msg) { Write-Host "  ✅ $Msg" -ForegroundColor Green }
function Write-Note([string]$Msg) { Write-Host "  ℹ️  $Msg" -ForegroundColor Gray }
function Write-Caution([string]$Msg) { Write-Host "  ⚠️  $Msg" -ForegroundColor Yellow }
function Write-Bad([string]$Msg) { Write-Host "  ❌ $Msg" -ForegroundColor Red }
function Ask-YesNo([string]$Msg, [string]$Default) {
    $hint = if ($Default -eq "Y") { "[Y/n]" } else { "[y/N]" }
    $ans = [string](Read-Host "  👉 $Msg $hint")
    if ([string]::IsNullOrWhiteSpace($ans)) { return ($Default -eq "Y") }
    return ($ans.Trim().ToLower() -eq "y")
}
# robocopy 로 폴더 복사 (병합, 실패 시 $false). robocopy 종료 코드 0~7 은 성공, 8 이상은 실패.
function Copy-Folder([string]$Src, [string]$Dst) {
    if (-not (Test-Path $Src)) { return $false }
    New-Item -ItemType Directory -Path $Dst -Force | Out-Null
    robocopy "$Src" "$Dst" /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
    return ($LASTEXITCODE -lt 8)
}
function Get-VersionTuple([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?')
    if (-not $m.Success) { return $null }
    $parts = @($m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value, $(if ($m.Groups[4].Success) { $m.Groups[4].Value } else { "0" }))
    return [version]($parts -join ".")
}

# ── 0. 묶음 · 권한 확인 ──────────────────────────────────────────────────────
$Bundle = ""
if (-not [string]::IsNullOrEmpty([string]$global:DT2_BUNDLE)) {
    $Bundle = ([string]$global:DT2_BUNDLE).TrimEnd('\')
} elseif (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
    $Bundle = $PSScriptRoot
} else {
    $Bundle = (Get-Location).Path
}
$WinDir = Join-Path $Bundle "windows"
$Rootfs = Join-Path $Bundle "devtools2-rootfs.tar.gz"

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "  📦 DevTools2 오프라인 가져오기" -ForegroundColor DarkCyan
Write-Host "  묶음: $Bundle" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Bad "관리자 권한이 필요합니다. 'DevTools2 개발 환경 가져오기.cmd' 로 실행하세요."
    return
}
if (-not (Test-Path $Rootfs)) {
    Write-Bad "배포판 파일이 없습니다: $Rootfs"
    return
}

# manifest.txt (key=value)
$Manifest = @{}
$manifestPath = Join-Path $Bundle "manifest.txt"
if (Test-Path $manifestPath) {
    foreach ($line in [System.IO.File]::ReadAllLines($manifestPath, [System.Text.Encoding]::UTF8)) {
        $kv = [string]$line
        $eq = $kv.IndexOf("=")
        if ($eq -gt 0) { $Manifest[$kv.Substring(0, $eq)] = $kv.Substring($eq + 1) }
    }
}
$Distro = if ($Manifest.ContainsKey("distro") -and -not [string]::IsNullOrWhiteSpace($Manifest["distro"])) { $Manifest["distro"].Trim() } else { "devtools2" }
$LinuxUser = if ($Manifest.ContainsKey("user")) { [string]$Manifest["user"] } else { "" }
Write-Note "배포판 이름: $Distro / Linux 사용자: $LinuxUser / 만든 날짜: $($Manifest['created'])"

# ── 1. WSL 기능 ──────────────────────────────────────────────────────────────
Write-Step "1. WSL 기능 확인"
$needReboot = $false
foreach ($feat in @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")) {
    $state = $null
    try { $state = (Get-WindowsOptionalFeature -Online -FeatureName $feat -ErrorAction Stop).State } catch { $state = $null }
    if ([string]$state -eq "Enabled") {
        Write-Ok "$feat 켜짐"
    } else {
        Write-Note "$feat 켜는 중..."
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName $feat -NoRestart -ErrorAction Stop | Out-Null
            Write-Ok "$feat 켬"
            $needReboot = $true
        } catch {
            Write-Bad "$feat 를 켜지 못했습니다: $($_.Exception.Message)"
            return
        }
    }
}
if ($needReboot) {
    Write-Caution "WSL 기능을 처음 켰습니다. PC 를 재부팅한 뒤 'DevTools2 개발 환경 가져오기.cmd' 를 한 번 더 실행하세요."
    return
}

# ── 2. WSL 설치 / 업데이트 ───────────────────────────────────────────────────
Write-Step "2. WSL 확인"
$installedVer = $null
$wslOut = [string](& wsl.exe --version 2>$null | Out-String)
if ($LASTEXITCODE -eq 0) { $installedVer = Get-VersionTuple ($wslOut -replace "`0", "") }
$msi = Get-ChildItem -Path (Join-Path $WinDir "wsl") -Filter "wsl.*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1
$bundleVer = if ($msi) { Get-VersionTuple $msi.Name } else { $null }
if ($installedVer -and (-not $bundleVer -or $installedVer -ge $bundleVer)) {
    Write-Ok "WSL $installedVer 설치됨"
} elseif ($msi) {
    Write-Note "WSL $bundleVer 설치 중 ($($msi.Name))..."
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$($msi.FullName)`" /passive /norestart" -Wait -PassThru
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
        Write-Ok "WSL 설치 완료"
        if ($p.ExitCode -eq 3010) {
            Write-Caution "재부팅이 필요합니다. 재부팅 후 'DevTools2 개발 환경 가져오기.cmd' 를 한 번 더 실행하세요."
            return
        }
    } else {
        Write-Bad "WSL 설치 실패 (종료 코드 $($p.ExitCode))"
        return
    }
} else {
    Write-Bad "WSL 이 설치되어 있지 않고 묶음에 WSL 설치 파일(windows\wsl\wsl.*.msi)도 없습니다."
    return
}

# ── 3. WSL 배포판 가져오기 ───────────────────────────────────────────────────
Write-Step "3. WSL 배포판 '$Distro' 가져오기"
$existing = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction SilentlyContinue |
    Where-Object { [string](Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DistributionName -eq $Distro }
$doImport = $true
if ($existing) {
    Write-Caution "'$Distro' 배포판이 이미 있습니다."
    if (Ask-YesNo "기존 배포판을 지우고 묶음으로 다시 가져올까요? (기존 배포판 안의 파일은 모두 삭제됨)" "N") {
        & wsl.exe --unregister $Distro | Out-Null
    } else {
        $doImport = $false
        Write-Ok "기존 배포판을 그대로 둡니다."
    }
}
if ($doImport) {
    # 설치 위치: 개발자 드라이브(ReFS) 우선 (0.setup-wsl.ps1 과 같은 경로 규칙), 없으면 %LOCALAPPDATA%\WSL\<배포판>
    $winUser = ([string]$env:USERNAME).ToLower()
    $target = Join-Path $env:LOCALAPPDATA "WSL\$Distro"
    try {
        $refs = Get-CimInstance -ClassName Win32_Volume -Filter "DriveType=3" -ErrorAction Stop |
            Where-Object { $_.FileSystem -eq 'ReFS' -and -not [string]::IsNullOrEmpty($_.DriveLetter) } | Sort-Object DriveLetter | Select-Object -First 1
        if ($refs) { $target = "$(([string]$refs.DriveLetter).TrimEnd('\'))\wsl\$Distro\$winUser" }
    } catch {}
    $inPath = [string](Read-Host "  👉 배포판 설치 위치 [기본값: $target]")
    if (-not [string]::IsNullOrWhiteSpace($inPath)) { $target = $inPath.Trim() }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Note "가져오는 중... (배포판 크기에 따라 수 분 ~ 수십 분)"
    & wsl.exe --import $Distro "$target" "$Rootfs" --version 2
    if ($LASTEXITCODE -ne 0) {
        Write-Bad "배포판 가져오기 실패 (종료 코드 $LASTEXITCODE)"
        return
    }
    Write-Ok "배포판 가져옴: $target"
    # 기본 사용자는 배포판 안의 /etc/wsl.conf [user] default 로 그대로 적용됨
    if (Ask-YesNo "'$Distro' 를 기본 배포판으로 설정할까요?" "Y") {
        & wsl.exe --set-default $Distro | Out-Null
        Write-Ok "기본 배포판: $Distro"
    }
}

# ── 4. .wslconfig ────────────────────────────────────────────────────────────
Write-Step "4. .wslconfig"
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$bundleCfg = Join-Path $WinDir "wslconfig.txt"
if (-not (Test-Path $wslConfigPath) -and (Test-Path $bundleCfg)) {
    [System.IO.File]::WriteAllText($wslConfigPath, [System.IO.File]::ReadAllText($bundleCfg, [System.Text.Encoding]::UTF8), [System.Text.UTF8Encoding]::new($false))
    Write-Ok "묶음의 설정으로 만들었습니다 (네트워크 미러링 등)"
}
$cfgText = ""
if (Test-Path $wslConfigPath) { $cfgText = [string][System.IO.File]::ReadAllText($wslConfigPath, [System.Text.Encoding]::UTF8) }
if ($cfgText -match '(?im)^\s*memory\s*=') {
    Write-Ok "WSL 메모리 상한이 이미 있어 그대로 둡니다."
} else {
    # 0.setup-wsl.ps1 9-1 과 같은 식: min(PC 메모리 × 0.625, PC 메모리 - 8GB) — 16GB 미만 PC 는 WSL 기본값(절반) 유지
    $hostMemBytes = 0
    try { $hostMemBytes = (Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | Measure-Object -Property Capacity -Sum).Sum } catch {}
    $hostMemGB = [int][Math]::Round($hostMemBytes / 1GB)
    if ($hostMemGB -ge 16) {
        $memGB = [Math]::Min([int][Math]::Floor($hostMemGB * 0.625), $hostMemGB - 8)
        if ($cfgText -match '(?im)^\s*\[wsl2\]\s*$') {
            $cfgText = [regex]::Replace($cfgText, '(?im)^\s*\[wsl2\]\s*$', "[wsl2]`r`nmemory=${memGB}GB", 1)
        } else {
            $cfgText = $cfgText.TrimEnd() + "`r`n[wsl2]`r`nmemory=${memGB}GB`r`n"
        }
        [System.IO.File]::WriteAllText($wslConfigPath, $cfgText, [System.Text.UTF8Encoding]::new($false))
        Write-Ok "WSL 메모리 상한 memory=${memGB}GB (PC 메모리 ${hostMemGB}GB)"
    } else {
        Write-Note "PC 메모리 ${hostMemGB}GB — WSL 기본값(절반)을 그대로 씁니다."
    }
}

# ── 5. 글꼴 ──────────────────────────────────────────────────────────────────
Write-Step "5. 글꼴"
$userFonts = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
New-Item -ItemType Directory -Path $userFonts -Force | Out-Null
$fontReg = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
if (-not (Test-Path $fontReg)) { New-Item -Path $fontReg -Force | Out-Null }
$fontCount = 0
foreach ($f in @(Get-ChildItem -Path (Join-Path $WinDir "fonts") -Filter "*.ttf" -ErrorAction SilentlyContinue)) {
    $dest = Join-Path $userFonts $f.Name
    if (-not (Test-Path $dest)) { Copy-Item $f.FullName $dest -Force }
    Set-ItemProperty -Path $fontReg -Name "$($f.BaseName) (TrueType)" -Value $dest -Force
    $fontCount++
}
Write-Ok "글꼴 ${fontCount}개 (사용자 글꼴)"

# ── 6. AutoHotkey 단축키 ─────────────────────────────────────────────────────
Write-Step "6. AutoHotkey 단축키"
$ahkDir = Join-Path $env:LOCALAPPDATA "_devtools2\modules\autohotkey"
if (Copy-Folder (Join-Path $WinDir "autohotkey") $ahkDir) {
    $ahkExe = Join-Path $ahkDir "AutoHotkey64.exe"
    $ahkScript = Join-Path $ahkDir "devtools2-hotkey.ahk"
    if ((Test-Path $ahkExe) -and (Test-Path $ahkScript)) {
        # 1.setup-autohotkey.ps1 과 같은 작업 이름 · 일반 사용자 권한(로그온 시 실행)
        $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action = New-ScheduledTaskAction -Execute $ahkExe -Argument "`"$ahkScript`"" -WorkingDirectory $ahkDir
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $me
        $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
        try {
            Register-ScheduledTask -TaskName "DevTools2-Hotkey" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
            Start-ScheduledTask -TaskName "DevTools2-Hotkey" -ErrorAction SilentlyContinue
            Write-Ok "단축키 등록·실행 (Ctrl+Alt+T 터미널, Ctrl+Alt+G Sublime Merge, CapsLock 리매핑, 한/영 자동 전환)"
        } catch {
            Write-Caution "로그온 작업 등록 실패: $($_.Exception.Message) — 시작 프로그램 바로 가기로 대신 등록합니다."
            $startup = [Environment]::GetFolderPath("Startup")
            $wsh = New-Object -ComObject WScript.Shell
            $lnk = $wsh.CreateShortcut((Join-Path $startup "devtools2-hotkey.lnk"))
            $lnk.TargetPath = $ahkExe
            $lnk.Arguments = "`"$ahkScript`""
            $lnk.WorkingDirectory = $ahkDir
            $lnk.Save()
            Write-Ok "시작 프로그램에 등록 (다음 로그인부터 실행)"
        }
    } else {
        Write-Caution "AutoHotkey 실행 파일 또는 단축키 스크립트가 묶음에 없습니다."
    }
} else {
    Write-Caution "묶음에 AutoHotkey 가 없습니다 — 건너뜀"
}

# ── 7. Windows Terminal ──────────────────────────────────────────────────────
Write-Step "7. Windows Terminal 설정"
$wtSrc = Join-Path $WinDir "terminal\settings.json"
$wtState = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA "Packages") -Filter "Microsoft.WindowsTerminal_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not (Test-Path $wtSrc)) {
    Write-Caution "묶음에 Windows Terminal 설정이 없습니다 — 건너뜀"
} elseif (-not $wtState) {
    Write-Caution "Windows Terminal 이 설치되어 있지 않습니다 (Windows 10 은 따로 설치 필요). 설치 후 다시 실행하면 적용됩니다."
} else {
    $wtDir = Join-Path $wtState.FullName "LocalState"
    New-Item -ItemType Directory -Path $wtDir -Force | Out-Null
    $wtDest = Join-Path $wtDir "settings.json"
    if (Test-Path $wtDest) { Copy-Item $wtDest "$wtDest.bak.$(Get-Date -Format 'yyyyMMddHHmmss')" -Force }
    Copy-Item $wtSrc $wtDest -Force
    Write-Ok "적용 (기존 설정은 settings.json.bak.* 로 백업)"
}

# ── 8. VS Code · Zed ─────────────────────────────────────────────────────────
# 프로그램 폴더를 그대로 복사합니다: WSL 안의 VS Code·Zed 서버와 버전이 같아야 오프라인에서 연결되는데,
# 설치 파일로는 같은 버전을 보장하기 어렵고 묶음을 만든 PC 의 폴더는 정확히 같은 버전입니다.
function Install-PortableApp([string]$Name, [string]$Src, [string]$Dst, [string]$Exe, [string]$BinDir) {
    if (-not (Test-Path $Src)) { Write-Caution "묶음에 $Name 이(가) 없습니다 — 건너뜀"; return }
    if (Test-Path (Join-Path $Dst $Exe)) {
        if (-not (Ask-YesNo "$Name 이(가) 이미 설치되어 있습니다. 묶음 버전으로 덮어쓸까요? (버전이 다르면 WSL 연결이 안 될 수 있음)" "N")) {
            Write-Ok "$Name 기존 설치를 그대로 둡니다."
            return
        }
    }
    if (-not (Copy-Folder $Src $Dst)) { Write-Bad "$Name 복사 실패"; return }
    # 시작 메뉴 바로 가기
    $programs = [Environment]::GetFolderPath("Programs")
    $wsh = New-Object -ComObject WScript.Shell
    $lnk = $wsh.CreateShortcut((Join-Path $programs "$Name.lnk"))
    $lnk.TargetPath = Join-Path $Dst $Exe
    $lnk.WorkingDirectory = $Dst
    $lnk.Save()
    # 명령줄 실행용 PATH (사용자)
    if (-not [string]::IsNullOrEmpty($BinDir)) {
        $binPath = Join-Path $Dst $BinDir
        $userPath = [string][Environment]::GetEnvironmentVariable("Path", "User")
        if ((Test-Path $binPath) -and ($userPath -notlike "*$binPath*")) {
            [Environment]::SetEnvironmentVariable("Path", ($userPath.TrimEnd(';') + ";" + $binPath), "User")
        }
    }
    Write-Ok "$Name 설치 (시작 메뉴 바로 가기)"
}

Write-Step "8. VS Code"
Install-PortableApp "Visual Studio Code" (Join-Path $WinDir "vscode\app") (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code") "Code.exe" "bin"
if (Copy-Folder (Join-Path $WinDir "vscode\extensions") (Join-Path $env:USERPROFILE ".vscode\extensions")) { Write-Ok "VS Code 확장 (Windows 쪽)" }
$codeUser = Join-Path $env:APPDATA "Code\User"
foreach ($f in @(Get-ChildItem -Path (Join-Path $WinDir "vscode\user") -Filter "*.json" -ErrorAction SilentlyContinue)) {
    New-Item -ItemType Directory -Path $codeUser -Force | Out-Null
    $dest = Join-Path $codeUser $f.Name
    if (-not (Test-Path $dest)) { Copy-Item $f.FullName $dest -Force }   # 이미 있는 사용자 설정은 덮어쓰지 않음
}

Write-Step "8. Zed"
Install-PortableApp "Zed" (Join-Path $WinDir "zed\app") (Join-Path $env:LOCALAPPDATA "Programs\Zed") "Zed.exe" "bin"
if (Copy-Folder (Join-Path $WinDir "zed\extensions") (Join-Path $env:LOCALAPPDATA "Zed\extensions")) { Write-Ok "Zed 확장 (Windows 쪽)" }
$zedCfg = Join-Path $env:APPDATA "Zed"
foreach ($f in @(Get-ChildItem -Path (Join-Path $WinDir "zed\config") -Filter "*.json" -ErrorAction SilentlyContinue)) {
    New-Item -ItemType Directory -Path $zedCfg -Force | Out-Null
    $dest = Join-Path $zedCfg $f.Name
    # Zed 설정은 저장소가 관리하는 복사본(tool.setup-zed.ps1 과 같음) — 다르면 백업 후 바꿈
    if ((Test-Path $dest) -and ((Get-FileHash $dest).Hash -ne (Get-FileHash $f.FullName).Hash)) {
        Copy-Item $dest "$dest.bak.$(Get-Date -Format 'yyyyMMddHHmmss')" -Force
    }
    Copy-Item $f.FullName $dest -Force
}
Write-Ok "Zed 설정"

# ── 완료 ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Green
Write-Host "  🎉 가져오기 완료" -ForegroundColor Green
Write-Host "===========================================================================" -ForegroundColor Green
Write-Host "  • 터미널: Ctrl + Alt + T  (또는 'wsl -d $Distro')"
Write-Host "  • .wslconfig 를 바꿨다면 'wsl --shutdown' 후 다시 열면 적용됩니다."
Write-Host "  • 인증 정보(GitHub·Bitwarden·API 키 등)는 묶음에 없습니다 — 오프라인에서는 쓰지 않습니다."
