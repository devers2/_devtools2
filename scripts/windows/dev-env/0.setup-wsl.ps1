# ==============================================================================
# WSL2 설치 및 마이그레이션 스크립트 (0.setup-wsl.ps1)
#
# ------------------------------------------------------------------------------
# ⚠️ [AI / 개발자 필독 - 설계 절대 원칙]
# 1. 100% 온라인 전용: 스크립트는 항상 GitHub main 브랜치 최신 원격 raw URL에서 호출됩니다.
# 2. 순수 UTF-8 NoBOM 보장: BOM(Byte Order Mark) 헤더를 절대 삽입하거나 조작하지 마십시오.
# 3. PS5.1 & PS7 무구분 호환: param() 이 필요한 경우 반드시 스크립트 맨 첫 줄(Line 1)에 위치해야 합니다.
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
# Write-Step/Write-Success/Pause-Script/Wait-WithSpinner 등은 여러 ps1 파일에
# 거의 동일하게 복붙되어 있던 걸 _common.ps1(scripts/windows/dev-env/_common.ps1)
# 공용 파일로 통합했습니다(bash의 _colors.sh와 동일한 패턴). 한쪽 사본에서만 고쳐진
# 버그(Pause-Script 문구)가 다른 사본에는 전파되지 않는 드리프트가 실제로 있었습니다.
# 항상 온라인 최신본을 dot-source(다른 스크립트 스트리밍 실행과 동일한 캐시 우회 원칙).
$_commonHeaders = @{ 'Cache-Control' = 'no-cache, no-store, must-revalidate'; 'Pragma' = 'no-cache' }
$_commonContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/_common.ps1" -Headers $_commonHeaders -ErrorAction Stop
. ([scriptblock]::Create($_commonContent))

function Show-BiosVirtualizationHelp {
    Write-Host ""
    Write-Host "===========================================================================" -ForegroundColor Red
    Write-Host "  ❌ 메인보드(BIOS/UEFI) 가상화(Virtualization) 비활성화 오류" -ForegroundColor Red
    Write-Host "===========================================================================" -ForegroundColor Red
    Write-Host "  WSL2 가상 머신을 실행하려면 CPU 가상화 기능(VT-x / AMD-V)이" -ForegroundColor Yellow
    Write-Host "  BIOS/UEFI 설정에서 활성화되어 있어야 합니다." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [BIOS/UEFI 가상화 활성화 방법 안내]" -ForegroundColor White
    Write-Host "  1. 컴퓨터를 재부팅한 후, 부팅 화면에서 [F2], [Del], 또는 [F12] 키를 누릅니다." -ForegroundColor White
    Write-Host "  2. Advanced / CPU Configuration / Security 메뉴로 이동합니다." -ForegroundColor White
    Write-Host "     • Intel CPU : 'Intel Virtualization Technology' 또는 'VT-x' → [Enabled]" -ForegroundColor Cyan
    Write-Host "     • AMD CPU   : 'SVM Mode' 또는 'AMD-V' → [Enabled]" -ForegroundColor Cyan
    Write-Host "  3. [F10] 키를 눌러 저장 후 재부팅(Save & Exit)을 진행합니다." -ForegroundColor White
    Write-Host "  4. 윈도우 재부팅 후 이 스크립트를 다시 실행해 주세요." -ForegroundColor Yellow
    Write-Host "===========================================================================" -ForegroundColor Red
    Write-Host ""
}

# ==============================================================================
# [Step 0] 관리자 권한 확인
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Warn "WSL 설치에는 관리자 권한이 필요합니다."
    Write-Warn "관리자 권한으로 스크립트를 재실행합니다..."
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/0.setup-wsl.ps1 | iex`"" -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    }
    return
}

Clear-Host
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "  🐧 WSL2 설치 및 설정 스크립트 (인스턴스명: devtools2)"
Write-Host "===========================================================================" -ForegroundColor DarkCyan

# 고정된 인스턴스 이름 설정
$wslName = "devtools2"
$devtools2File = Join-Path $env:USERPROFILE ".devtools2"

# ==============================================================================
# [Step 1] WSL2 가상 머신 상태 확인 및 설치 진행
# ==============================================================================
Write-Step "[Step 1] WSL2 가상 머신 상태 확인"

# 1. wsl.exe 파일 존재 확인 (구형 Windows 대응)
$wslExePath = "$env:SystemRoot\System32\wsl.exe"
if (-not (Test-Path $wslExePath)) {
    Write-Host ""
    Write-Host "===========================================================================" -ForegroundColor Red
    Write-Host "  ❌ wsl.exe 를 찾을 수 없습니다." -ForegroundColor Red
    Write-Host "===========================================================================" -ForegroundColor Red
    Write-Host "  WSL2 설치에는 Windows 10 버전 2004 이상 또는 Windows 11 이 필요합니다." -ForegroundColor Yellow
    Write-Host "  Windows 업데이트를 실행한 후 이 스크립트를 다시 실행해 주세요." -ForegroundColor Yellow
    Write-Host "===========================================================================" -ForegroundColor Red
    Pause-Script
    exit 1
}

# 2. wsl --version 으로 WSL 엔진 설치 여부 확인
# (WSL 미설치/인박스 환경에서는 wsl --version 이 무한 대기하거나 오래 멈출 수 있으므로 5초 타임아웃을 적용합니다)
$versionProc = Start-Process wsl.exe -ArgumentList "--version" -PassThru -NoNewWindow `
    -RedirectStandardOutput "$env:TEMP\wsl_version_check.txt" `
    -RedirectStandardError "$env:TEMP\wsl_version_error.txt" `
    -ErrorAction SilentlyContinue

Wait-WithSpinner -Message "WSL 엔진 버전 확인 중" -Condition {
    return (-not $versionProc) -or $versionProc.HasExited
} -MaxTimeoutSeconds 5 | Out-Null

if ($versionProc -and -not $versionProc.HasExited) {
    try { $versionProc | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
}

$isWslEngineInstalled = ($versionProc -and $versionProc.HasExited -and $versionProc.ExitCode -eq 0)

if (Test-Path "$env:TEMP\wsl_version_check.txt") { Remove-Item "$env:TEMP\wsl_version_check.txt" -Force -ErrorAction SilentlyContinue }
if (Test-Path "$env:TEMP\wsl_version_error.txt") { Remove-Item "$env:TEMP\wsl_version_error.txt" -Force -ErrorAction SilentlyContinue }

# 3. WSL 엔진 미설치 → wsl --install --no-distribution 으로 설치
if (-not $isWslEngineInstalled) {
    Write-Warn "WSL2 구성 요소가 설치되어 있지 않거나 반응하지 않습니다. 설치를 진행합니다..."
    # stderr를 캡처해두는 이유: 아래에서 실패 원인이 실제로 BIOS/UEFI 가상화 비활성화인지,
    # 아니면 네트워크/Windows Update 등 다른 이유인지 구분해야 하기 때문입니다.
    $installErrPath = "$env:TEMP\wsl_install_error.txt"
    $installProc = Start-Process wsl.exe -ArgumentList "--install --no-distribution" -PassThru -NoNewWindow `
        -RedirectStandardError $installErrPath -ErrorAction SilentlyContinue

    if ($null -eq $installProc) {
        Write-Fail "WSL 설치 프로세스를 시작할 수 없습니다."
        Pause-Script
        exit 1
    }

    $waitSuccess = Wait-WithSpinner -Message "WSL2 구성 요소 다운로드 및 기능 활성화 진행 중" -Condition {
        return $installProc.HasExited
    } -MaxTimeoutSeconds 900

    # ⚠️ $waitSuccess를 체크하지 않으면, 타임아웃(900초) 후에도 프로세스가 아직 실행
    # 중인 상태로 바로 아래 ExitCode를 확인하게 됩니다. PowerShell은 이 경우 예외를
    # 던지지 않고 그냥 빈 값을 반환하므로(직접 테스트로 확인) "-eq 3010"이 조용히
    # false가 되어, 설치가 실제로 끝나지도 않았는데 아무 경고 없이 다음 단계로
    # 넘어가 버립니다. 타임아웃을 명시적으로 처리합니다.
    if (-not $waitSuccess) {
        Write-Fail "WSL2 설치가 제한 시간(900초) 내에 완료되지 않았습니다."
        Write-Warn "설치가 백그라운드에서 계속 진행 중일 수 있습니다. 잠시 기다린 후 이 스크립트를 다시 실행해 주세요."
        Pause-Script
        exit 1
    }

    $installErrContent = ""
    if (Test-Path $installErrPath) {
        $installErrContent = Get-Content $installErrPath -Raw -ErrorAction SilentlyContinue
        Remove-Item $installErrPath -Force -ErrorAction SilentlyContinue
    }

    if ($installProc.ExitCode -eq 3010) {
        Write-Host ""
        Write-Host "===========================================================================" -ForegroundColor Red
        Write-Host "  ⚠️  WSL2 설치를 완료하기 위해 시스템 재부팅이 필요합니다." -ForegroundColor Red
        Write-Host "===========================================================================" -ForegroundColor Red
        Write-Host "  컴퓨터를 재부팅한 후 이 스크립트를 다시 실행해 주세요." -ForegroundColor Yellow
        Write-Host "===========================================================================" -ForegroundColor Red
        Pause-Script
        exit 3010
    }
    # ⚠️ $installProc.ExitCode가 $null인 경우가 실제로 발생합니다(HasExited는 true인데
    # ExitCode 프로퍼티만 비어 있는 케이스). PowerShell에서 "$null -ne 0"은 $true이므로,
    # 이 상태를 걸러내지 않으면 "종료 코드를 못 읽음"까지 전부 "설치 실패"로 오판됩니다.
    # 이런 애매한 경우는 여기서 바로 실패 처리하지 않고, 뒤이은 "wsl --list" 등
    # 실제 설치 상태 확인 단계로 넘겨 판단합니다.
    elseif ($null -ne $installProc.ExitCode -and $installProc.ExitCode -ne 0) {
        Write-Fail "WSL2 설치가 실패했습니다. (종료 코드: $($installProc.ExitCode))"
        if (-not [string]::IsNullOrWhiteSpace($installErrContent)) {
            Write-Host "  [상세 오류 메시지]" -ForegroundColor Yellow
            Write-Host "  $($installErrContent.Trim())" -ForegroundColor Gray
        }
        # ⚠️ 이 단계(--install --no-distribution)는 Windows 기능 활성화/커널 다운로드
        # 단계일 뿐입니다. BIOS/UEFI 가상화(VT-x/AMD-V) 비활성화는 보통 이 단계가 아니라
        # "VM을 실제로 구동"할 때 나는 오류이므로, 여기서 나는 모든 실패를 가상화
        # 문제로 단정하면 오탐이 발생합니다(원인은 네트워크/Windows Update/재부팅
        # 대기 등 다양함). 오류 메시지에 가상화 관련 키워드가 실제로 포함된 경우에만
        # BIOS 안내를 보여주고, 그 외에는 일반 실패 안내만 표시합니다.
        if ($installErrContent -match "0x80370102|0x80370109|가상화|Virtualization|Hyper-V") {
            Show-BiosVirtualizationHelp
        } else {
            Write-Warn "네트워크 연결, Windows Update 서비스 상태, 또는 재부팅 대기 여부를 확인한 후 스크립트를 다시 실행해 주세요."
        }
        Pause-Script
        exit 1
    }
}

# 4. 배포판 목록 확인 (wsl --list --quiet, 5초 타임아웃)
$registeredDistros = @()
$isUpdateRequired = $false

$listProc = Start-Process wsl.exe -ArgumentList "--list --quiet" -PassThru -NoNewWindow `
    -RedirectStandardOutput "$env:TEMP\wsl_list_check.txt" `
    -RedirectStandardError "$env:TEMP\wsl_list_error.txt" `
    -ErrorAction SilentlyContinue

Wait-WithSpinner -Message "WSL2 배포판 목록 확인 중" -Condition {
    return (-not $listProc) -or $listProc.HasExited
} -MaxTimeoutSeconds 5 | Out-Null

if ($listProc -and -not $listProc.HasExited) {
    try { $listProc | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
}

# stderr 에서 업데이트 경고 감지
$errContent = ""
if (Test-Path "$env:TEMP\wsl_list_error.txt") {
    $errContent = Get-Content "$env:TEMP\wsl_list_error.txt" -Raw -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\wsl_list_error.txt" -Force -ErrorAction SilentlyContinue
}
if ($errContent -match "업데이트해야 합니다" -or $errContent -match "--update") {
    $isUpdateRequired = $true
}

# stdout 에서 배포판 목록 읽기
if (Test-Path "$env:TEMP\wsl_list_check.txt") {
    if (-not $isUpdateRequired) {
        $registeredDistros = (Get-Content "$env:TEMP\wsl_list_check.txt" -Raw -ErrorAction SilentlyContinue) `
            -replace "`0", "" -split "`r`n" |
            Where-Object { $_.Trim() -ne "" } |
            ForEach-Object { $_.Trim() }
    }
    Remove-Item "$env:TEMP\wsl_list_check.txt" -Force -ErrorAction SilentlyContinue
}

# 5. 업데이트 필요 → wsl --update 실행
if ($isUpdateRequired) {
    Write-Warn "Linux용 Windows 하위 시스템(WSL)의 최신 버전 업데이트가 필요합니다. 업데이트를 진행합니다..."
    $updateProc = Start-Process wsl.exe -ArgumentList "--update" -PassThru -NoNewWindow -ErrorAction SilentlyContinue
    
    if ($updateProc) {
        $waitSuccess = Wait-WithSpinner -Message "WSL 패키지 업데이트 진행 중" -Condition {
            return $updateProc.HasExited
        } -MaxTimeoutSeconds 600

        # ⚠️ 위 설치 단계와 동일한 이유로 타임아웃 여부를 먼저 확인합니다 — 체크하지
        # 않으면 업데이트가 실제로 끝나지 않았는데도 조용히 다음 단계로 넘어갑니다.
        if (-not $waitSuccess) {
            Write-Warn "WSL 업데이트가 제한 시간(600초) 내에 완료되지 않았습니다. 업데이트를 건너뛰고 계속 진행합니다."
        }
        elseif ($updateProc.ExitCode -eq 3010) {
            Write-Host ""
            Write-Host "===========================================================================" -ForegroundColor Red
            Write-Host "  ⚠️  WSL 업데이트 적용을 완료하기 위해 시스템 재부팅이 필요합니다." -ForegroundColor Red
            Write-Host "===========================================================================" -ForegroundColor Red
            Write-Host "  컴퓨터를 재부팅한 후 이 스크립트를 다시 실행해 주세요." -ForegroundColor Yellow
            Write-Host "===========================================================================" -ForegroundColor Red
            Pause-Script
            exit 3010
        }
    }

    # 업데이트 완료 후 배포판 목록 재확인
    $listProc2 = Start-Process wsl.exe -ArgumentList "--list --quiet" -PassThru -NoNewWindow `
        -RedirectStandardOutput "$env:TEMP\wsl_list_check.txt" -ErrorAction SilentlyContinue
    $listProc2 | Wait-Process -Timeout 3 -ErrorAction SilentlyContinue
    if (Test-Path "$env:TEMP\wsl_list_check.txt") {
        $registeredDistros = (Get-Content "$env:TEMP\wsl_list_check.txt" -Raw -ErrorAction SilentlyContinue) `
            -replace "`0", "" -split "`r`n" |
            Where-Object { $_.Trim() -ne "" } |
            ForEach-Object { $_.Trim() }
        Remove-Item "$env:TEMP\wsl_list_check.txt" -Force -ErrorAction SilentlyContinue
    }
}

# 4. 'devtools2'가 이미 등록되어 있다면 신규 설치를 건너뛰고 계속 진행
if ($registeredDistros -contains $wslName) {
    Write-Success "기존에 설치된 WSL2 배포판 '$wslName'이 이미 존재하여 이를 그대로 사용합니다."
    Write-Warn "---------------------------------------------------------------------------"
    Write-Warn " [새로운 배포판으로 깨끗하게 다시 설치하고 싶으신가요?]"
    Write-Warn " 아래 명령어를 실행하여 기존 배포판을 완전히 삭제한 뒤, 이 스크립트를 다시 실행해 주세요."
    Write-Host ""
    Write-Host "   wsl --unregister $wslName" -ForegroundColor Red
    Write-Warn "   (※ 주의: 기존 배포판 내의 모든 파일과 설정이 영구적으로 지워집니다.)"
    Write-Warn "---------------------------------------------------------------------------"
    Write-Host ""
    Write-Success "기존 배포판 사용 준비 완료. 다음 단계로 진행합니다."
} else {

# 5. 임시 설치를 위한 base Ubuntu 가 등록되어 있는지 확인
# (Ubuntu, Ubuntu-24.04, Ubuntu-22.04 등 우분투 계열 배포판 스캔)
$distroId = $registeredDistros | Where-Object { $_ -match "^Ubuntu" } | Select-Object -First 1
$isBaseRegistered = -not [string]::IsNullOrEmpty($distroId)

# WSL2 초기 일반 사용자(non-root, UID >= 1000) 계정이 실제로 정상 생성되었는지 검증
function Test-WslUserAccountConfigured {
    param([string]$distro)
    if ([string]::IsNullOrEmpty($distro)) { return $false }

    try {
        $whoamiResult = wsl -d $distro -e whoami 2>$null
        $uidResult = wsl -d $distro -e id -u 2>$null

        if ($LASTEXITCODE -eq 0 -and $whoamiResult -and $uidResult) {
            $uName = $whoamiResult.Trim()
            $uidStr = $uidResult.Trim()
            $uid = 0
            [int]::TryParse($uidStr, [ref]$uid) | Out-Null

            # root가 아니고 UID가 1000 이상인 일반 사용자 계정이 준비된 경우만 통과
            if ($uName -and $uName -ne "root" -and $uid -ge 1000 -and $uName -notmatch "error" -and $uName -notmatch "Wsl/Service") {
                return $true
            }
        }
    } catch {}

    return $false
}

$isUserConfigured = $false
$createdUsername = ""
if ($isBaseRegistered) {
    if (Test-WslUserAccountConfigured -distro $distroId) {
        $createdUsername = (wsl -d $distroId -e whoami 2>$null).Trim()
        $isUserConfigured = $true
    }
}

if (-not $isBaseRegistered) {
    # --------------------------------------------------------------------------
    # Phase 1: WSL2 기본 설치 (최초 실행 및 버전 선택)
    # --------------------------------------------------------------------------
    Write-Step "[Step 2] Ubuntu 배포판 버전 선택 및 설치 진행"
    
    Write-Host "  설치할 Ubuntu 버전을 선택하세요:" -ForegroundColor White
    Write-Host "    1) Ubuntu        (최신 LTS - 권장)" -ForegroundColor White
    Write-Host "    2) Ubuntu-24.04  (24.04 LTS)" -ForegroundColor White
    Write-Host "    3) Ubuntu-22.04  (22.04 LTS)" -ForegroundColor White

    $versionIdx = Prompt-Choice "👉 번호를 입력하세요" @("Ubuntu (최신 LTS - 권장)", "Ubuntu-24.04 (24.04 LTS)", "Ubuntu-22.04 (22.04 LTS)") 1
    switch ($versionIdx) {
        1 { $distroId = "Ubuntu" }
        2 { $distroId = "Ubuntu-24.04" }
        3 { $distroId = "Ubuntu-22.04" }
    }

    Write-Info "선택된 배포판: $distroId"
    Write-Warn "설치 중 또는 완료 후 새 창이 열리며 Ubuntu 초기 사용자 설정(Username/Password)이 진행됩니다."
    Write-Host ""

    # 설치를 백그라운드 프로세스로 실행하여 메인 터미널이 대기 루프로 진입할 수 있도록 함
    Start-Process wsl.exe -ArgumentList "--install -d $distroId --web-download"
    # 프로세스 시작을 위해 1초 대기
    Start-Sleep -Seconds 1
}

# --------------------------------------------------------------------------
# 사용자 계정 설정 대기 루프 (설정이 아직 완료되지 않은 경우 실행)
# --------------------------------------------------------------------------
if (-not $isUserConfigured) {
    Write-Step "[Step 2-1] WSL2 초기 사용자 설정 완료 대기"
    
    # 이미 배포판은 등록되었으나 계정이 없는 경우, 사용자 설정을 위해 배포판 창을 직접 띄움
    if ($isBaseRegistered) {
        Write-Info "기본 배포판($distroId)이 감지되었으나 사용자 설정이 완료되지 않았습니다."
        Write-Info "사용자 설정을 위해 배포판($distroId) 창을 실행합니다..."
        try {
            Start-Process wsl.exe -ArgumentList "-d $distroId" -ErrorAction SilentlyContinue
        } catch {
            Write-Warn "배포판 실행에 실패했습니다. 수동으로 실행해 주세요."
        }
    }

    $loopCount = 0
    while (-not $isUserConfigured) {
        Write-Host ""
        Write-Host "===========================================================================" -ForegroundColor Yellow
        Write-Host " 📢 WSL2 초기 사용자 설정 대기 중 (인스턴스: $distroId)" -ForegroundColor Yellow
        Write-Host "===========================================================================" -ForegroundColor Yellow
        Write-Host "  1. 새로 열린 리눅스(Ubuntu) 창에서 사용자 이름(Username)과 비밀번호를 설정해 주세요."
        Write-Host "  2. 사용자 계정 생성이 완전히 완료된 후, 해당 리눅스 창을 닫아주세요."
        Write-Host "  3. 계정 생성이 정상 완료되었다면, 아래에서 엔터(Enter)를 입력하여 다음 단계를 진행합니다."
        Write-Host "===========================================================================" -ForegroundColor Yellow
        Write-Host "  (※ 창이 자동으로 열리지 않았다면 시작 메뉴에서 $distroId 를 실행해 주세요.)" -ForegroundColor Gray
        Write-Host ""
        
        Write-Host "👉 계정 생성을 완료한 후 엔터(Enter) 키를 누르세요: " -ForegroundColor Yellow -NoNewline
        [void][System.Console]::ReadLine()
        
        # 1) wsl --list에서 배포판이 실제로 등록되었는지 재확인 (특히 최초 설치 시)
        $registeredDistros = (wsl --list --quiet 2>$null) -replace "`0", "" |
            Where-Object { $_.Trim() -ne "" } |
            ForEach-Object { $_.Trim() }
            
        $actualDistroId = $registeredDistros | Where-Object { $_ -match "^Ubuntu" } | Select-Object -First 1
        
        if (-not [string]::IsNullOrEmpty($actualDistroId)) {
            $distroId = $actualDistroId
            
            # whoami 및 id -u(UID >= 1000) 검증으로 일반 사용자 계정 생성 완료 여부 엄격 확인
            if (Test-WslUserAccountConfigured -distro $distroId) {
                $createdUsername = (wsl -d $distroId -e whoami 2>$null).Trim()
                $isUserConfigured = $true
                Write-Success "WSL2 사용자 설정이 완료되었습니다! (사용자 계정: $createdUsername)"
            } else {
                Write-Warn "아직 Ubuntu 설치/다운로드 중이거나 초기 사용자 계정(Username/Password) 설정이 완료되지 않았습니다."
                Write-Warn "우측 Ubuntu 창에서 계정 생성을 완전히 마친 후(일반 사용자 계정 생성 필수) 다시 엔터를 눌러주세요."
            }
        } else {
            Write-Warn "아직 Ubuntu 배포판이 등록되지 않았습니다."
            Write-Warn "설치 창에서 다운로드 및 설치가 완료될 때까지 기다린 후 계정을 생성해 주세요."
        }
        
        $loopCount++
        # 혹시 너무 오랫동안 감지가 안 될 경우를 대비해 배포판 수동 실행 안내 혹은 자동 재실행 시도
        if ($loopCount -gt 0 -and -not $isUserConfigured -and -not [string]::IsNullOrEmpty($distroId)) {
            Write-Info "배포판($distroId) 창이 닫혀있다면 백그라운드/수동 실행을 재시도합니다..."
            try { Start-Process wsl.exe -ArgumentList "-d $distroId" -ErrorAction SilentlyContinue } catch {}
        }
    }
}

# --------------------------------------------------------------------------
# Phase 2: 'devtools2'로 마이그레이션 및 WSL 설정 (재부팅 후 또는 배포판 감지 시)
# --------------------------------------------------------------------------
Write-Step "[Step 3] devtools2 인스턴스 마이그레이션 및 설정"

# ==============================================================================
# 설치 경로 결정 - 개발자 드라이브(Dev Drive / ReFS) 자동 감지 및 사용자 선택
# ------------------------------------------------------------------------------
# 같은 PC의 여러 Windows 사용자가 드라이브를 공유할 수 있으므로,
# 파일 충돌 방지를 위해 경로에 Windows 계정명($env:USERNAME)을 포함합니다.
# (배포판 이름 'devtools2'는 고정 유지 - WSL 등록은 사용자별로 독립적)
# ==============================================================================
$windowsUser = $env:USERNAME.ToLower()

# 모든 드라이브를 순회하여 개발자 드라이브(ReFS 포맷) 자동 감지
# Win32_Volume WMI 쿼리: FileSystem=ReFS 이면서 실제 접근 가능한 드라이브만 수집
$devDrives = @()
try {
    $volumes = Get-CimInstance -ClassName Win32_Volume -Filter "DriveType=3" -ErrorAction SilentlyContinue |
        Where-Object { $_.FileSystem -eq 'ReFS' -and -not [string]::IsNullOrEmpty($_.DriveLetter) } |
        Sort-Object DriveLetter
    foreach ($vol in $volumes) {
        $letter = $vol.DriveLetter.TrimEnd('\')   # "Z:" 형태로 정규화
        if (Test-Path "$letter\") {
            $devDrives += $letter
        }
    }
} catch {
    # WMI 조회 실패 시 빈 목록으로 폴백 (설치에는 영향 없음)
    $devDrives = @()
}

$cDriveDefault = Join-Path $env:USERPROFILE "AppData\Local\WSL\$wslName"

# 안내 배너
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "  📂 WSL2 가상 머신 설치 드라이브 선택" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  💡 개발자 드라이브(Dev Drive / ReFS)에 설치하면 WSL2 파일 I/O 성능이" -ForegroundColor Yellow
Write-Host "     크게 향상됩니다. 가능하다면 개발자 드라이브를 선택하는 것을 권장합니다." -ForegroundColor Yellow
Write-Host ""

# 선택 목록 구성
$choices = @()   # 각 항목: @{ Label=; Path= }

if ($devDrives.Count -gt 0) {
    Write-Host "  ✅ 감지된 개발자 드라이브 (권장):" -ForegroundColor Green
    foreach ($drv in $devDrives) {
        $installPath = "$drv\wsl\devtools2\$windowsUser"
        $idx = $choices.Count + 1
        Write-Host ("  {0}) ★ {1}  →  {2}" -f $idx, $drv, $installPath) -ForegroundColor Cyan
        $choices += @{ Label = "$drv (개발자 드라이브)"; Path = $installPath }
    }
    Write-Host ""
}

# C: 폴백 옵션 (항상 마지막 번호로 추가)
$cIdx = $choices.Count + 1
Write-Host ("  {0}) C: (일반 드라이브)  →  {1}" -f $cIdx, $cDriveDefault) -ForegroundColor Gray
$choices += @{ Label = "C: (일반 드라이브)"; Path = $cDriveDefault }

Write-Host ""
Write-Host "---------------------------------------------------------------------------" -ForegroundColor DarkGray

$driveIdx = Prompt-Choice "👉 설치할 드라이브 번호를 입력하세요" ($choices | ForEach-Object { $_.Label }) 1
$wslInstallPath = $choices[$driveIdx - 1].Path
$selectedLabel  = $choices[$driveIdx - 1].Label

Write-Host ""
Write-Success "선택 완료: $selectedLabel"
Write-Info    "WSL2 가상 머신 설치 경로: $wslInstallPath"
Write-Host ""
Write-Info "Ubuntu($distroId)를 '$wslName'으로 마이그레이션(Export/Import)합니다..."

# 1. 사용자 계정명 확인
if ([string]::IsNullOrEmpty($createdUsername)) {
    Write-Info "설정된 사용자 계정 정보를 읽어오는 중..."
    try {
        $whoamiResult = wsl -d $distroId -e whoami 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrEmpty($whoamiResult)) {
            $createdUsername = $whoamiResult.Trim()
        }
    } catch {}
}

if ([string]::IsNullOrEmpty($createdUsername) -or $createdUsername -match "error" -or $createdUsername -match "실패" -or $createdUsername -match "Wsl/Service") {
    $createdUsername = "ubuntu"
}
Write-Success "생성된 사용자 계정 확인: $createdUsername"

# 2. 임시 tar 백업 파일 생성
$tempTarPath = Join-Path $env:TEMP "wsl_temp_$($wslName).tar"

# 3. 배포판 내보내기 (Export) - wsl.exe가 자체 진행률(MB)을 출력하므로 직접 실행
Write-Info "배포판을 백업 파일로 내보내는 중... ($distroId -> $tempTarPath)"
Write-Info "(몇 분 정도 소요될 수 있습니다)"
wsl --export $distroId $tempTarPath
if ($LASTEXITCODE -ne 0) {
    Write-Fail "배포판 내보내기(Export)에 실패했습니다. (종료 코드: $LASTEXITCODE)"
    if (Test-Path $tempTarPath) { Remove-Item $tempTarPath -Force }
    Pause-Script
    exit 1
}
Write-Success "배포판 내보내기 완료"

# 4. 기존 임시 배포판 제거 (Unregister)
Write-Info "임시 설치된 기본 배포판을 해제합니다..."
wsl --unregister $distroId

# 5. 최종 경로 폴더 준비
if (-not (Test-Path $wslInstallPath)) {
    New-Item -ItemType Directory -Path $wslInstallPath -Force | Out-Null
}

# 6. 새로운 이름/경로로 가져오기 (Import) - 마찬가지로 직접 실행
Write-Info "배포판을 '$wslName' 이름으로 가져오는 중... ($wslInstallPath)"
Write-Info "(몇 분 정도 소요될 수 있습니다)"
wsl --import $wslName $wslInstallPath $tempTarPath
if ($LASTEXITCODE -ne 0) {
    Write-Fail "배포판 가져오기(Import)에 실패했습니다. (종료 코드: $LASTEXITCODE)"
    Write-Warn "데이터 보존을 위해 백업 파일($tempTarPath)을 유지합니다. 원인 파악 후 'wsl --import $wslName $wslInstallPath $tempTarPath'로 직접 시도하세요."
    Pause-Script
    exit 1
}
Write-Success "배포판 가져오기 완료"

# 7. 기본 로그인 사용자, hostname 및 Windows Interop 설정 (wsl.conf / hostname 수정)
wsl -d $wslName -u root -e bash -c "echo 'devtools2' > /etc/hostname && echo -e '[user]\ndefault=$createdUsername\n\n[interop]\nenabled=true\nappendWindowsPath=true' > /etc/wsl.conf"

# 8. 임시 파일 삭제
if (Test-Path $tempTarPath) {
    Remove-Item $tempTarPath -Force
}

# 9. Windows 사용자 프로필에 .wslconfig (네트워크 미러링) 자동 설정
#    WSL2 내부 포트(8881, 8080, 5005 등)를 Windows 호스트 localhost에서 별도 포트포워딩 없이 바로 접속 가능하도록 동기화
Write-Info "Windows-WSL2 네트워크 포트 직통 연결(mirrored)을 위한 .wslconfig 설정 확인 중..."
$wslConfigFile = Join-Path $env:USERPROFILE ".wslconfig"
if (Test-Path $wslConfigFile) {
    $existing = Get-Content $wslConfigFile -Raw -ErrorAction SilentlyContinue
    if ($existing -notmatch "networkingMode\s*=\s*mirrored") {
        if ($existing -match "\[wsl2\]") {
            Add-Content -Path $wslConfigFile -Value "`nnetworkingMode=mirrored`nautoProxy=true" -Encoding UTF8
        } else {
            Add-Content -Path $wslConfigFile -Value "`n[wsl2]`nnetworkingMode=mirrored`nautoProxy=true" -Encoding UTF8
        }
        Write-Success ".wslconfig 에 네트워크 미러링(networkingMode=mirrored) 설정이 추가되었습니다."
    } else {
        Write-Success ".wslconfig (networkingMode=mirrored) 설정이 이미 적용되어 있습니다."
    }
} else {
    $defaultWslConfig = @"
[wsl2]
networkingMode=mirrored
autoProxy=true
"@
    Set-Content -Path $wslConfigFile -Value $defaultWslConfig -Encoding UTF8
    Write-Success "새 .wslconfig (networkingMode=mirrored) 파일 생성 완료!"
}

# 10. %USERPROFILE%\.devtools2 통일 디렉터리 보장 및 배포판 정보 저장
$devtools2Dir = Join-Path $env:USERPROFILE ".devtools2"
if (-not (Test-Path $devtools2Dir)) {
    New-Item -ItemType Directory -Path $devtools2Dir -Force | Out-Null
} elseif (Test-Path $devtools2Dir -PathType Leaf) {
    Remove-Item $devtools2Dir -Force
    New-Item -ItemType Directory -Path $devtools2Dir -Force | Out-Null
}
$distroSaveFile = Join-Path $devtools2Dir "wsl_distro"
Set-Content -Path $distroSaveFile -Value "WSL_DISTRO=$wslName" -Encoding UTF8

# --------------------------------------------------------------------------
# [Step 4] 완료
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 WSL2 설치 및 환경 설정 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  설치된 배포판 : Ubuntu ($distroId)" -ForegroundColor White
Write-Host "  인스턴스 이름 : $wslName" -ForegroundColor White
Write-Host "  설치 경로     : $wslInstallPath" -ForegroundColor White
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
}

# 스크립트 정상 종료 (부모 스크립트의 $LASTEXITCODE 오판 방지)
$global:LASTEXITCODE = 0
return 0
