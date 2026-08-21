param(
    # WSL2 배포판 이름 (기본값: 첫 번째로 찾은 기본 배포판 자동 감지)
    [string]$WslDistro = ""
)

# ==============================================================================
# AutoHotkey v2 포터블 배포 및 전역 단축키 등록 스크립트 (1.setup-autohotkey.ps1)
#
# 주요 기능:
#   1. AutoHotkey v2 포터블 zip을 %LOCALAPPDATA%\_devtools2\modules\autohotkey 에 설치
#   2. devtools2-hotkey.ahk(CapsLock 리매핑 + Ctrl+Alt+T 로 WSL 터미널 열기)를 온라인에서
#      받아와 로그온 시 자동 실행되도록 Task Scheduler에 등록
#
# ※ 예전에는 이 스크립트가 WezTerm 설치까지 겸했지만, WezTerm(Nightly는 Smart App
#   Control 차단, Stable은 2년 반 넘게 미업데이트)을 걷어내고 Windows Terminal로
#   전환하면서 AutoHotkey 배포와 터미널 앱 설정(2.setup-windows-terminal.ps1)을
#   분리했습니다. Ctrl+Alt+T는 이제 devtools2-hotkey.ahk가 Windows Terminal을 통해
#   WSL을 엽니다.
#
# ------------------------------------------------------------------------------
# ⚠️ [AI / 개발자 필독 - 설계 절대 원칙]
# 1. 100% 온라인 전용: 스크립트는 항상 GitHub main 브랜치 최신 원격 raw URL에서 호출됩니다.
# 2. 순수 UTF-8 NoBOM 보장: BOM(Byte Order Mark) 헤더를 절대 삽입하거나 조작하지 마십시오.
# 3. PS5.1 & PS7 무구분 호환: param() 구문은 반드시 스크립트 맨 첫 줄(Line 1)에 위치해야 합니다.
# 4. sh와의 관계: scripts/linux/dev-env/_colors.sh, _install-utils.sh 같은 bash 공용 헬퍼도
#    지금은 온라인 전용(로컬 파일을 보지 않음)입니다 — 다만 이유는 다릅니다. bash는 로컬을 먼저
#    봐도 인코딩상 안전하지만, 이 설치 스크립트들이 어차피 네트워크 없이는 동작 못 해서 로컬
#    폴백을 뺀 것뿐입니다(순수 단순화). 반면 ps1은 로컬 NoBOM 파일을 PowerShell 5.1이 직접
#    읽으면 한글 등이 깨질 위험이 있어 애초에 로컬을 볼 수조차 없습니다 — ps1은 위 1번 원칙대로
#    항상 온라인에서 새로 가져와 실행해야 합니다.
# ------------------------------------------------------------------------------
# ==============================================================================

# --- 한글 깨짐 방지: 출력 인코딩을 UTF-8 로 설정
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- 윈도우 PowerShell 기본 파란색 프로그레스바 팝업 끄기 (텍스트 깨짐 및 커서 겹침 방지)
$ProgressPreference = 'SilentlyContinue'

# ==============================================================================
# 헬퍼 함수
# ==============================================================================
# 여러 ps1 파일에 거의 동일하게 복붙되어 있던 Write-*/Wait-* 헬퍼를 _common.ps1
# 공용 파일로 통합했습니다(scripts/windows/dev-env/_common.ps1, bash _colors.sh와
# 동일한 패턴). 항상 온라인 최신본을 dot-source합니다.
$_commonHeaders = @{ 'Cache-Control' = 'no-cache, no-store, must-revalidate'; 'Pragma' = 'no-cache' }
$_commonContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/_common.ps1" -Headers $_commonHeaders -ErrorAction Stop
. ([scriptblock]::Create($_commonContent))

# ==============================================================================
# [Step 0] 관리자 권한 확인 및 재실행
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host "[경고] Task Scheduler 등록을 위해 관리자 권한이 필요합니다." -ForegroundColor Yellow
    Write-Host "       관리자 권한으로 스크립트를 재실행합니다..." -ForegroundColor Yellow
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/1.setup-autohotkey.ps1 | iex`"" -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -WslDistro `"$WslDistro`"" -Verb RunAs
    }
    return
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🚀 AutoHotkey 배포 및 전역 단축키 등록" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan

# ==============================================================================
# [Step 1] WSL2 배포판 이름 자동 감지
# ==============================================================================
Write-Step "[Step 1] WSL2 배포판 감지"

if ($WslDistro -eq "") {
    # 1순위: %USERPROFILE%\.devtools2 디렉터리 내 wsl_distro 또는 단일 .devtools2 파일에서 읽기
    $devtools2Dir  = Join-Path $env:USERPROFILE ".devtools2"
    $devtools2File = if (Test-Path $devtools2Dir -PathType Container) { Join-Path $devtools2Dir "wsl_distro" } else { $devtools2Dir }
    if (Test-Path $devtools2File) {
        $saved = Get-Content $devtools2File | Where-Object { $_ -match "^WSL_DISTRO=" } | Select-Object -First 1
        if ($saved) {
            $WslDistro = ($saved -split "=", 2)[1].Trim()
            Write-Host "  .devtools2 에서 읽은 배포판: $WslDistro" -ForegroundColor White
        }
    }

    # 2순위: wsl --list --quiet 로 첫 번째 배포판 자동 선택
    if ($WslDistro -eq "") {
        $distroList = (wsl --list --quiet 2>$null) | Where-Object { $_ -ne "" }
        if ($distroList.Count -eq 0) {
            Write-Fail "WSL2 배포판을 찾을 수 없습니다. WSL2 를 먼저 설치해주세요."
            Read-Host "계속하려면 엔터를 누르세요"
            exit 1
        }
        # NUL 문자 제거
        $WslDistro = $distroList[0] -replace "`0", "" | ForEach-Object { $_.Trim() }
        Write-Host "  자동 감지된 배포판: $WslDistro" -ForegroundColor White
    }
}
else {
    Write-Host "  지정된 배포판: $WslDistro" -ForegroundColor White
}

# ==============================================================================
# [Step 2] AutoHotkey v2 포터블 배포 및 Ctrl+Alt+T 단축키 등록
# winget 설치 없이 AutoHotkey v2 포터블 zip 을 %LOCALAPPDATA%\_devtools2\modules\autohotkey 에 설치하고
# Task Scheduler 로그온 트리거로 자동 실행을 연동합니다.
# ==============================================================================
Write-Step "[Step 2] AutoHotkey v2 포터블 배포 및 단축키 등록"

# ── AutoHotkey 설치 여부 확인 ─────────────────────────────────────────────────
if (-not (Prompt-Confirm "👉 AutoHotKey를 설치하시겠습니까?" "Y")) {
    # ── n 선택: devtools2 관련 AHK만 동적으로 감지하여 정리 ─────────────────────
    Write-Info "AutoHotKey 설치를 건너뜁니다. devtools2 관련 AHK 기능을 비활성화합니다..."

    $ahkModuleDir = "$env:LOCALAPPDATA\_devtools2\modules\autohotkey"
    $startupDir   = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

    # devtools2 경로 식별 패턴 — 특정 ahk 파일명을 하드코딩하지 않고
    # 'wsl.localhost\<배포판명>' 또는 '_devtools2' 경로를 가리키는 대상만 동적으로 식별합니다.
    $wslPattern   = [regex]::Escape("wsl.localhost\$WslDistro")
    $localPattern = [regex]::Escape("_devtools2")

    # (1) devtools2 경로(WSL UNC 또는 _devtools2)를 가리키는 AHK 프로세스만 동적으로 종료
    try {
        $killedCount = 0
        Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" -ErrorAction SilentlyContinue |
            Where-Object {
                $cmd = $_.CommandLine
                ($cmd -match $wslPattern) -or ($cmd -match $localPattern)
            } |
            ForEach-Object {
                Write-Info "devtools2 AHK 프로세스 종료: PID=$($_.ProcessId)"
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
                $killedCount++
            }
        if ($killedCount -eq 0) {
            Write-Info "종료할 devtools2 AHK 프로세스가 없습니다."
        }
    } catch {
        Write-Warn "AHK 프로세스 확인 중 오류 (WMI 사용 불가): $($_.Exception.Message)"
    }

    # (2) Startup 폴더의 .lnk 중 TargetPath 나 Arguments 가 devtools2 경로를 가리키는 바로가기만 동적으로 삭제
    $wshShellClean = New-Object -ComObject WScript.Shell
    Get-ChildItem -Path $startupDir -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $sc = $wshShellClean.CreateShortcut($_.FullName)
            $combined = "$($sc.Arguments) $($sc.TargetPath)"
            if (($combined -match $wslPattern) -or ($combined -match $localPattern)) {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                Write-Info "devtools2 AHK 바로가기 제거: $($_.Name)"
            }
        } catch {}
    }
    Write-Info "Startup 폴더 devtools2 AHK 바로가기 정리 완료."

    # (3) modules/autohotkey 폴더의 *.ahk 삭제 (WSL 연동 실패 시 폴백으로 로컬에 복사된 물리 파일들)
    #     ※ WSL 내부 원본(\\wsl.localhost\...\scripts\windows\autohotkey\*.ahk)은 건드리지 않음
    $localAhkFiles = Get-ChildItem -Path $ahkModuleDir -Filter "*.ahk" -ErrorAction SilentlyContinue
    if ($localAhkFiles) {
        $localAhkFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Info "로컬 폴백 AHK 파일 제거: $ahkModuleDir\*.ahk ($($localAhkFiles.Count)개)"
    }

    Write-Success "AutoHotkey의 devtools2 관련 기능이 비활성화되었습니다."
    Write-Info "다른 용도의 AutoHotkey 프로세스는 영향을 받지 않습니다."
} else {

# ── (1) modules/autohotkey 포터블 설치 경로 결정 ─────────────────────────────
$ahkModuleDir = "$env:LOCALAPPDATA\_devtools2\modules\autohotkey"
$ahkExe = Join-Path $ahkModuleDir "AutoHotkey64.exe"
if (-not (Test-Path $ahkExe)) {
    $ahkExe = Join-Path $ahkModuleDir "AutoHotkey.exe"
}

Write-Info "AutoHotKey 기능 연동을 진행합니다..."

# ── (2) 포터블 AutoHotkey v2 다운로드 및 압축 해제 ───────────────────────────
if (Test-Path $ahkExe) {
    Write-Info "AutoHotkey v2 포터블 이미 존재: $ahkExe"
    Write-Info "AHK 스크립트 배포 및 자동 실행 등록 중..."
} else {
    Write-Info "AutoHotkey v2 포터블 패키지 다운로드 및 압축 해제 중..."
    Write-Info "  설치 경로: $ahkModuleDir"

    New-Item -ItemType Directory -Path $ahkModuleDir -Force | Out-Null

    $ahkZipUrl  = "https://www.autohotkey.com/download/ahk-v2.zip"
    $ahkZipTemp = Join-Path $env:TEMP "ahk-v2.zip"

    try {
        # 비동기 백그라운드다운로드 및 스피너 대기
        $prevProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'

        $dlJob = Start-Job -ScriptBlock {
            param($url, $dest)
            Invoke-WebRequest -Uri $url -OutFile $dest -ErrorAction Stop
        } -ArgumentList $ahkZipUrl, $ahkZipTemp

        Wait-WithSpinner -Message "AutoHotkey v2 패키지 다운로드 중" -Condition { $dlJob.State -ne 'Running' } -MaxTimeoutSeconds 120
        Receive-Job -Job $dlJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $dlJob -Force -ErrorAction SilentlyContinue

        $ProgressPreference = $prevProgress

        if (Test-Path $ahkZipTemp) {
            # 백그라운드 압축 해제 및 스피너 대기
            $unzipJob = Start-Job -ScriptBlock {
                param($zip, $target)
                Expand-Archive -Path $zip -DestinationPath $target -Force
            } -ArgumentList $ahkZipTemp, $ahkModuleDir

            Wait-WithSpinner -Message "AutoHotkey v2 압축 해제 중" -Condition { $unzipJob.State -ne 'Running' } -MaxTimeoutSeconds 120
            Receive-Job -Job $unzipJob -ErrorAction SilentlyContinue | Out-Null
            Remove-Job -Job $unzipJob -Force -ErrorAction SilentlyContinue

            Remove-Item $ahkZipTemp -Force -ErrorAction SilentlyContinue
        }

        $ahkExe = Join-Path $ahkModuleDir "AutoHotkey64.exe"
        if (-not (Test-Path $ahkExe)) {
            $ahkExe = Join-Path $ahkModuleDir "AutoHotkey.exe"
        }

        if (Test-Path $ahkExe) {
            Write-Success "AutoHotkey v2 포터블 배포 완료: $ahkExe"

            # ── 사용자 레지스트리(HKCU)에 .ahk 확장자 자동 연결 등록 (오프라인 환경/더블클릭 대비) ──
            try {
                $ahkClassKey = "HKCU:\Software\Classes\AutoHotkeyScript\shell\open\command"
                if (-not (Test-Path $ahkClassKey)) { New-Item -Path $ahkClassKey -Force | Out-Null }
                Set-ItemProperty -Path $ahkClassKey -Name "(default)" -Value "`"$ahkExe`" `"%1`" %*" -ErrorAction SilentlyContinue

                $ahkExtKey = "HKCU:\Software\Classes\.ahk"
                if (-not (Test-Path $ahkExtKey)) { New-Item -Path $ahkExtKey -Force | Out-Null }
                Set-ItemProperty -Path $ahkExtKey -Name "(default)" -Value "AutoHotkeyScript" -ErrorAction SilentlyContinue
                Write-Success ".ahk 파일 확장자가 포터블 AutoHotkey에 자동 연결되었습니다."
            } catch {}
        } else {
            Write-Warn "압축 해제 후 AutoHotkey 실행 파일을 찾지 못했습니다: $ahkModuleDir"
        }
    } catch {
        $ProgressPreference = $prevProgress
        Remove-Item $ahkZipTemp -Force -ErrorAction SilentlyContinue
        Write-Warn "AutoHotkey v2 포터블 다운로드 실패: $($_.Exception.Message)"
    }
}

# ── (3) AHK 스크립트 배포 및 자동 실행 연동 ───────────────────────────────────
$startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

$ahkSetupJob = Start-Job -ScriptBlock {
    param($WslDistro, $startupDir, $ahkModuleDir, $ahkExe)

    # 헬퍼: WSL2 디렉터리 존재 여부를 UNC Test-Path 대신 wsl test -d 로 0.01초만에 빠르게 검사
    # ⚠️ 호출부(아래)는 '$DEVTOOLS2'처럼 bash 변수 참조 리터럴을 넘겨 "WSL 안에서
    # $DEVTOOLS2가 실제로 유효한 디렉터리를 가리키는지" 검사하려는 의도입니다.
    # bash에서 작은따옴표는 변수 확장을 막으므로 test -d '$linuxPath'는 "$DEVTOOLS2"라는
    # 리터럴 이름의 디렉터리를 찾게 되어 항상 실패합니다(직접 테스트로 확인됨). 큰따옴표로
    # 바꾸면 변수 참조는 정상 확장되면서, 공백이 포함된 일반 경로도 여전히 안전합니다.
    function Test-WslDirFast {
        param($distro, $linuxPath)
        $res = wsl -d $distro -- bash -c "test -d ""$linuxPath"" && echo 'OK'" 2>$null
        return ($res -eq 'OK')
    }

    # 🌟 통합 devtools2-hotkey.ahk 연동 및 자동 실행 등록
    # 포터블 AHK 실행 파일(AutoHotkey64.exe)을 원본 파일명 그대로 유지하여
    # 차후 독립적인 사용자 스크립트 실행 등 다목적 활용이 가능하도록 보장합니다.

    # 🌟 기존 AutoHotkey 관련 중복 항목 정리 (Startup 바로가기 & 레지스트리 Run 키 & 구형 Task Scheduler)
    Get-ChildItem -Path $startupDir -Filter "*.ahk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $startupDir -Filter "*AutoHotkey*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $startupDir -Filter "*WezTerm-Hotkey*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $startupDir -Filter "*Keyboard-Remap*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $startupDir -Filter "*DevTools2-Hotkey*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    $runRegPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($regPath in $runRegPaths) {
        if (Test-Path $regPath) {
            $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            if ($props) {
                $props.psobject.Properties | Where-Object { $_.Name -like "*AutoHotkey*" } | ForEach-Object {
                    Remove-ItemProperty -Path $regPath -Name $_.Name -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # 구형 Task Scheduler 잔여 항목 정리 (이전 버전 호환)
    try {
        $tsClean = New-Object -ComObject Schedule.Service
        $tsClean.Connect()
        $rootClean = $tsClean.GetFolder("\")
        # DevTools2_Kanata: _devtools2와 무관한 kanata(키보드 리매퍼)를 실행하던 잔여 작업 —
        # AutoHotkey와 저수준 키보드 후킹이 충돌해 로그온 시 AHK 실행 자체가 실패하므로 정리.
        @("DevTools2-Hotkey", "DevTools2-AutoHotkey", "DevTools2_Kanata") | ForEach-Object {
            try { $rootClean.DeleteTask($_, 0) } catch {}
        }
    } catch {}

    # %DEVTOOLS2% 환경 변수 연동
    $wslDevtools2Root = if ($env:DEVTOOLS2 -and (Test-Path $env:DEVTOOLS2)) { $env:DEVTOOLS2 } else { "\\wsl.localhost\$WslDistro\var\opt\_devtools2" }
    if (Test-WslDirFast $WslDistro '$DEVTOOLS2') {
        [Environment]::SetEnvironmentVariable("DEVTOOLS2", $wslDevtools2Root, "User")
        $env:DEVTOOLS2 = $wslDevtools2Root
    }

    # devtools2-hotkey.ahk 통합 스크립트 배포
    # 재부팅 직후 WSL이 아직 기동하지 않은 상태에서도 AHK가 즉시 실행될 수 있도록
    # 항상 Windows 로컬 경로에 복사해 둡니다.
    # [온라인 전용] WSL 클론이 git pull 되지 않은 채 남아있으면 로컬(WSL) 복사가
    # 구버전을 배포할 위험이 있으므로, 로컬/WSL 파일은 사용하지 않고 매번 GitHub main
    # 최신 버전을 캐시 우회 헤더와 함께 직접 받아옵니다 (_colors.sh 등과 동일한 온라인
    # 전용 원칙 — scripts/linux/dev-env/_install-utils.sh 헤더 참고).
    $ahkDest = Join-Path $ahkModuleDir "devtools2-hotkey.ahk"
    $ahkRaw  = "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/autohotkey/devtools2-hotkey.ahk"
    $ahkNoCacheHeaders = @{ 'Cache-Control' = 'no-cache, no-store, must-revalidate'; 'Pragma' = 'no-cache' }
    $ahkFetchError = $null
    # 임시 파일로 먼저 받아서 성공했을 때만 $ahkDest로 교체 — 다운로드 도중 실패해도
    # 기존에 정상 배포돼 있던 로컬 사본이 손상된 파일로 덮어써지지 않도록 보장합니다.
    $ahkTmp = "$ahkDest.download"
    try {
        Invoke-WebRequest -Uri $ahkRaw -OutFile $ahkTmp -Headers $ahkNoCacheHeaders -ErrorAction Stop
        Move-Item -Path $ahkTmp -Destination $ahkDest -Force
    } catch {
        $ahkFetchError = $_.Exception.Message
        Remove-Item -Path $ahkTmp -Force -ErrorAction SilentlyContinue
    }

    # 통합 AutoHotkey 자동 실행 등록 (Task Scheduler)
    # Startup 폴더 바로가기는 로그온 후 수 분씩 지연 실행되는 문제가 있어서,
    # 지연 없이(PT0S) 즉시 실행되는 로그온 트리거로 등록합니다.
    #
    # ⚠️ CapsLock이 안 먹히거나 이 작업이 실패하면(LastTaskResult 확인):
    #   원인은 kanata(별도 키보드 리매퍼, _devtools2와 무관, 수동 설치됨)가 같이 떠 있어서
    #   AutoHotkey와 저수준 키보드 후킹이 충돌하는 것이었음(실측 확인 — SAC 차단 아니었음).
    #   위에서 "DevTools2_Kanata" 작업은 자동 정리하지만, kanata.exe 자체가 다른 방식으로
    #   계속 실행 중이면 또 충돌할 수 있음 (Get-Process kanata로 확인).
    #
    # 💡 kanata 필요성: AHK의 CapsLock 파트(Part 1: 탭=ESC, 홀드=Ctrl, Shift+CapsLock
    #   토글 등)가 kanata 설정보다 기능이 더 많아서, 이 프로젝트에서는 kanata가 필요 없음.
    #   나중에 kanata를 다시 쓰고 싶다면 AHK의 CapsLock 파트를 빼거나 kanata를 꺼야 함
    #   — 둘을 동시에 실행하면 안 됨.
    if (Test-Path $ahkExe) {
        $taskName = "DevTools2-Hotkey"
        $registered = $false
        try {
            $ts   = New-Object -ComObject Schedule.Service
            $ts.Connect()
            $root = $ts.GetFolder("\")

            # 기존 동일 작업 삭제 후 재등록
            try { $root.DeleteTask($taskName, 0) } catch {}

            $task = $ts.NewTask(0)
            $task.Settings.ExecutionTimeLimit         = "PT0S"  # 시간제한 없음
            $task.Settings.MultipleInstances          = 3        # 이미 실행 중이면 무시
            $task.Settings.StopIfGoingOnBatteries     = $false
            $task.Settings.DisallowStartIfOnBatteries = $false

            # 트리거: 현재 사용자 로그온 시 즉시 실행 (지연 없음)
            $trigger         = $task.Triggers.Create(9)  # 9 = TASK_TRIGGER_LOGON
            $trigger.UserId  = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $trigger.Delay   = "PT0S"  # 지연 없음

            # 동작: AHK 실행 (Windows 로컬 경로 — WSL 불필요)
            $action                   = $task.Actions.Create(0)  # 0 = TASK_ACTION_EXEC
            $action.Path              = $ahkExe
            $action.Arguments         = "`"$ahkDest`""
            $action.WorkingDirectory  = $ahkModuleDir

            # 현재 사용자 권한으로 실행 (관리자 권한 불필요)
            $task.Principal.UserId    = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $task.Principal.LogonType = 3  # 3 = TASK_LOGON_INTERACTIVE_TOKEN
            $task.Principal.RunLevel  = 0  # 0 = TASK_RUNLEVEL_LUA (일반 사용자 권한)

            $root.RegisterTaskDefinition($taskName, $task, 6, $null, $null, 3) | Out-Null
            $registered = $true
        } catch {}

        # Task Scheduler 등록 실패 시 Startup 바로가기로 폴백
        if (-not $registered) {
            $shortcutPath = "$startupDir\DevTools2-Hotkey.lnk"
            try {
                $wshShell = New-Object -ComObject WScript.Shell
                $shortcut = $wshShell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath       = $ahkExe
                $shortcut.Arguments        = "`"$ahkDest`""
                $shortcut.WorkingDirectory = $ahkModuleDir
                $shortcut.WindowStyle      = 7
                $shortcut.Description      = "DevTools2 AutoHotkey Service (Terminal Hotkey & Keyboard Remap)"
                $shortcut.Save()
            } catch {}
        }
    }

    # 기존 AutoHotkey 프로세스 전체 종료 후 통합 프로세스 단 1개만 실행
    Get-Process -Name "AutoHotkey*" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

    if ($ahkExe -and (Test-Path $ahkExe) -and $ahkDest -and (Test-Path $ahkDest)) {
        Start-Process -FilePath $ahkExe -ArgumentList "`"$ahkDest`"" -WindowStyle Hidden
    }

    return @{ AhkDest = $ahkDest; AhkFetchError = $ahkFetchError }
} -ArgumentList $WslDistro, $startupDir, $ahkModuleDir, $ahkExe

# 스피너로 백그라운드 작업 대기
Wait-WithSpinner -Message "AutoHotkey 기능 연동 및 자동 실행 구성 중" -Condition { $ahkSetupJob.State -ne 'Running' } -MaxTimeoutSeconds 60

$jobRes = Receive-Job -Job $ahkSetupJob -ErrorAction SilentlyContinue
Remove-Job -Job $ahkSetupJob -Force -ErrorAction SilentlyContinue

if ($jobRes -and $jobRes.AhkFetchError) {
    Write-Warn "devtools2-hotkey.ahk 온라인 다운로드 실패 (네트워크 확인 필요): $($jobRes.AhkFetchError)"
    Write-Warn "  기존에 배포된 로컬 사본이 있다면 그대로 사용됩니다. 없다면 단축키가 동작하지 않습니다."
} else {
    Write-Success "AutoHotkey 기능(Ctrl+Alt+T 단축키 및 CapsLock 리매핑)이 정상 연동되었습니다."
}
} # end if ($installAhk -notmatch '^[Nn]')

# ==============================================================================
# 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 AutoHotkey 설정 완료!" -ForegroundColor Green
Write-Host ""
if (-not ($installAhk -match '^[Nn]')) {
    Write-Host "  [AutoHotkey 연동 안내]" -ForegroundColor Cyan
    Write-Host "  · AHK 소스: GitHub main 최신 버전 (온라인 전용) -> Windows 로컬 동기화" -ForegroundColor DarkGray
    Write-Host "  · AHK 수정 후 GitHub에 푸시하고 설치 스크립트를 재실행하면 최신 스크립트가 로컬로 즉시 반영됩니다." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [단축키]" -ForegroundColor Cyan
    Write-Host "  Ctrl+Alt+T          : Windows Terminal(WSL) 새 창 열기" -ForegroundColor White
    Write-Host "  CapsLock (단독 탭)  : ESC" -ForegroundColor White
    Write-Host "  CapsLock + 다른 키  : Ctrl 조합" -ForegroundColor White
    Write-Host "  Shift + CapsLock    : 대문자 고정 ON" -ForegroundColor White
    Write-Host "  (고정ON) CapsLock/ESC: 대문자 고정 OFF" -ForegroundColor White
} else {
    Write-Host "  [안내] AutoHotkey 설치를 건너뛰어 devtools2 관련 AHK 기능이 비활성화되었습니다." -ForegroundColor Yellow
}
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
