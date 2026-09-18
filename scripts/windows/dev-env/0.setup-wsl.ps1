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
# 5. [절대 원칙] 기존 배포판 보호 & rootfs 직접 Import 방식 유지:
#    기존에 PC에 설치되어 있는 다른 Ubuntu 배포판(Ubuntu, Ubuntu-22.04 등)을
#    절대 조회·해제(unregister)·이동하지 마십시오. 이 스크립트는 Canonical 공식
#    Ubuntu WSL rootfs 이미지를 직접 다운로드하여 'wsl --import'로 단번에
#    devtools2 전용 배포판을 생성합니다. 사용자 계정은 useradd + chpasswd로
#    내부에서 직접 설정합니다.
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

# 세션 한정 마우스 클릭 멈춤(프리징) 방지: QuickEdit 모드 안전 비활성화 (스크립트 종료/Ctrl+C 시 자동 복원)
Disable-ConsoleQuickEdit | Out-Null

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

# ==============================================================================
# [Step 2] 설치 경로 결정 - 개발자 드라이브(Dev Drive / ReFS) 자동 감지 및 사용자 선택
# ------------------------------------------------------------------------------
# 같은 PC의 여러 Windows 사용자가 드라이브를 공유할 수 있으므로,
# 파일 충돌 방지를 위해 경로에 Windows 계정명($env:USERNAME)을 포함합니다.
# (배포판 이름 'devtools2'는 고정 유지 - WSL 등록은 사용자별로 독립적)
# ==============================================================================
Write-Step "[Step 2] WSL2 가상 머신 설치 경로 결정"

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
    $devDrives = @()
}

$cDriveDefault = Join-Path $env:USERPROFILE "AppData\Local\WSL\$wslName"

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "  📂 WSL2 가상 머신 설치 드라이브 선택" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  💡 개발자 드라이브(Dev Drive / ReFS)에 설치하면 WSL2 파일 I/O 성능이" -ForegroundColor Yellow
Write-Host "     크게 향상됩니다. 가능하다면 개발자 드라이브를 선택하는 것을 권장합니다." -ForegroundColor Yellow
Write-Host ""

$choices = @()

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

# ==============================================================================
# [Step 3] 가상 머신 존재 확인 또는 공식 RootFS 직접 Import 생성
# ------------------------------------------------------------------------------
# ⚠️ [보안 및 안정성 원칙]
# - 기존에 PC에 설치되어 있던 다른 Ubuntu 배포판(Ubuntu, Ubuntu-22.04 등)을
#   절대 조회하거나 해제(unregister)하지 않습니다.
# - Canonical 공식 Ubuntu WSL 경량 rootfs 이미지를 다운로드하여 지정된 경로에
#   'wsl --import'로 직접 단번에 배포판을 생성합니다.
# ==============================================================================
$existingVhdx = Join-Path $wslInstallPath "ext4.vhdx"
$skipDownload = $false
$installedDistroDesc = "Ubuntu"

if (Test-Path $existingVhdx) {
    Write-Host ""
    Write-Success "지정된 경로에 기존 WSL2 가상 디스크(ext4.vhdx)가 발견되었습니다:"
    Write-Host "   $existingVhdx" -ForegroundColor Cyan
    Write-Host ""
    $useExisting = Prompt-Confirm "기존 가상 디스크를 '$wslName' 배포판으로 즉시 재등록하여 사용하시겠습니까?" $true
    if ($useExisting) {
        Write-Info "기존 가상 디스크를 '$wslName'으로 등록 중..."
        wsl --import $wslName $wslInstallPath $existingVhdx --vhd
        if ($LASTEXITCODE -eq 0) {
            Write-Success "기존 가상 디스크 재등록 완료!"
            $skipDownload = $true
            $installedDistroDesc = "Ubuntu (기존 가상 디스크 재등록)"
        } else {
            Write-Warn "기존 가상 디스크 재등록에 실패했습니다. 새로운 배포판 설치를 진행합니다."
        }
    }
}

if (-not $skipDownload) {
    # ── 1. Ubuntu 배포판 버전 선택 (동적 탐지) ─────────────────────────────
    # cloud-images.ubuntu.com/wsl/releases/ 에서 사용 가능한 LTS 버전을
    # 런타임에 자동 탐지합니다. 각 버전의 /current/ 디렉터리에서 rootfs
    # 파일명을 파싱하여 codename(noble, jammy 등)을 추출합니다.
    # --------------------------------------------------------------------------
    Write-Step "[Step 3-1] Ubuntu 배포판 버전 선택"
    Write-Info "설치 가능한 Ubuntu LTS 버전을 확인하는 중..."

    $availableVersions = @()
    try {
        $releasesHtml = Invoke-RestMethod -Uri "https://cloud-images.ubuntu.com/wsl/releases/" -TimeoutSec 15 -ErrorAction Stop
        # HTML 디렉터리 목록에서 "22.04/", "24.04/" 같은 버전 링크 추출
        # Apache 버전(2.4, 3.2 등)을 제외하기 위해 >= 20.00 필터 적용
        $versionMatches = [regex]::Matches($releasesHtml, 'href="(\d+\.\d+)/"')
        foreach ($m in $versionMatches) {
            $ver = $m.Groups[1].Value
            if ([double]$ver -ge 20.0) {
                $availableVersions += $ver
            }
        }
        # 최신 버전이 맨 앞에 오도록 내림차순 정렬
        $availableVersions = $availableVersions | Sort-Object { [System.Version]($_ + ".0") } -Descending
    } catch {
        Write-Warn "온라인 버전 목록 조회에 실패했습니다. 기본 버전(24.04, 22.04)을 사용합니다."
        $availableVersions = @("24.04", "22.04")
    }

    if ($availableVersions.Count -eq 0) {
        Write-Warn "사용 가능한 Ubuntu 버전을 찾을 수 없습니다. 기본 버전(24.04, 22.04)을 사용합니다."
        $availableVersions = @("24.04", "22.04")
    }

    # 각 버전의 codename 을 rootfs 파일명에서 동적으로 추출
    # 예: ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz → "noble"
    $versionMap = [ordered]@{}
    foreach ($ver in $availableVersions) {
        $codename = $null
        try {
            $currentHtml = Invoke-RestMethod -Uri "https://cloud-images.ubuntu.com/wsl/releases/$ver/current/" -TimeoutSec 10 -ErrorAction Stop
            $codenameMatch = [regex]::Match($currentHtml, 'ubuntu-([a-z]+)-wsl-')
            if ($codenameMatch.Success) {
                $codename = $codenameMatch.Groups[1].Value
            }
        } catch {
            # codename 조회 실패 시 무시 — 아래에서 폴백 처리
        }
        # 잘 알려진 LTS codename 폴백 매핑
        if ([string]::IsNullOrEmpty($codename)) {
            $knownCodenames = @{
                "24.04" = "noble"; "22.04" = "jammy"; "20.04" = "focal"
                "26.04" = "euphoric"; "28.04" = "unknown"
            }
            if ($knownCodenames.ContainsKey($ver)) {
                $codename = $knownCodenames[$ver]
            } else {
                $codename = "unknown"
            }
        }
        $versionMap[$ver] = $codename
    }

    # 사용자에게 선택지 제시 (최신 버전 = 1번 = 기본 선택)
    Write-Host "  설치할 Ubuntu 버전을 선택하세요:" -ForegroundColor White
    $versionChoices = @()
    $isFirst = $true
    foreach ($ver in $versionMap.Keys) {
        $cn = $versionMap[$ver]
        $cnCapital = (Get-Culture).TextInfo.ToTitleCase($cn)
        $label = if ($isFirst) {
            "Ubuntu $ver LTS ($cnCapital - 최신 LTS 권장)"
        } else {
            "Ubuntu $ver LTS ($cnCapital)"
        }
        $versionChoices += $label
        $isFirst = $false
    }
    $versionIdx = Prompt-Choice "👉 번호를 입력하세요" $versionChoices 1

    $selectedVer = @($versionMap.Keys)[$versionIdx - 1]
    $ubuntuVer = $selectedVer
    $ubuntuCodename = $versionMap[$selectedVer]
    $installedDistroDesc = "Ubuntu $ubuntuVer LTS ($ubuntuCodename)"
    Write-Info "선택된 Ubuntu 버전: $installedDistroDesc"

    # ── 2. WSL2 내부 기본 사용자 계정 및 비밀번호 설정 ─────────────────────
    Write-Step "[Step 3-2] WSL2 기본 사용자 계정 설정"
    Write-Host "  WSL2 내부에서 사용할 기본 사용자 계정과 비밀번호를 설정합니다." -ForegroundColor White
    Write-Host ""
    Write-Host "👉 사용자 이름(Username) 입력 [기본값: $windowsUser]: " -ForegroundColor Yellow -NoNewline
    $inputUser = [Console]::ReadLine()
    $createdUsername = if ([string]::IsNullOrWhiteSpace($inputUser)) { $windowsUser } else { $inputUser.Trim() }
    Write-Success "사용자 계정명: $createdUsername"

    $plainPassword = ""
    while ([string]::IsNullOrEmpty($plainPassword)) {
        $pw1 = Prompt-Password "👉 비밀번호(Password) 입력: "
        $bstr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw1)
        $plain1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr1)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)

        $pw2 = Prompt-Password "👉 비밀번호(Password) 확인: "
        $bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw2)
        $plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr2)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)

        if ($plain1 -eq $plain2 -and -not [string]::IsNullOrEmpty($plain1)) {
            $plainPassword = $plain1
            Write-Success "비밀번호 설정 확인 완료"
        } else {
            Write-Fail "비밀번호가 일치하지 않거나 비어있습니다. 다시 입력해 주세요."
            Write-Host ""
        }
    }

    # ── 3. Canonical 공식 Ubuntu WSL RootFS 다운로드 (미러 및 원본 폴백 지원) ──
    Write-Step "[Step 3-3] Ubuntu WSL RootFS 다운로드"
    $isArm64 = ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64)
    $arch = if ($isArm64) { "arm64" } else { "amd64" }
    $rootfsFileName = "ubuntu-$ubuntuCodename-wsl-$arch-wsl.rootfs.tar.gz"

    # 우선순위 미러 및 공식 CDN URL 목록 (다중 URL 자동 폴백 지원)
    $rootfsUrls = @(
        "https://cloud-images.ubuntu.com/wsl/releases/$ubuntuVer/current/$rootfsFileName",
        "https://cloud-images.ubuntu.com/wsl/$ubuntuCodename/current/$rootfsFileName"
    )

    $tempTarPath = Join-Path $env:TEMP "ubuntu-$ubuntuCodename-wsl-$arch.rootfs.tar.gz"
    $downloadOk = Download-WithProgress -Urls $rootfsUrls -DestinationPath $tempTarPath -Description "Ubuntu $ubuntuVer LTS ($arch)"

    if (-not $downloadOk -or -not (Test-Path $tempTarPath)) {
        Write-Fail "Ubuntu RootFS 다운로드에 실패했습니다. 네트워크 연결 상태를 확인해 주세요."
        Pause-Script
        exit 1
    }

    # ── 4. 지정 경로에 WSL2 배포판 직접 Import ─────────────────────────────
    Write-Step "[Step 3-4] WSL2 배포판 직접 생성 (wsl --import)"
    if (-not (Test-Path $wslInstallPath)) {
        New-Item -ItemType Directory -Path $wslInstallPath -Force | Out-Null
    }

    Write-Info "배포판을 '$wslName' 이름으로 생성 중... ($wslInstallPath)"
    Write-Info "(압축 해제 및 가상 디스크 생성에 약 10~30초 소요됩니다)"
    wsl --import $wslName $wslInstallPath $tempTarPath --version 2
    $importExit = $LASTEXITCODE
    Remove-Item $tempTarPath -Force -ErrorAction SilentlyContinue

    if ($importExit -ne 0) {
        Write-Fail "배포판 가져오기(Import) 실패 (종료 코드: $importExit)"
        Pause-Script
        exit 1
    }
    Write-Success "WSL2 배포판 '$wslName' 생성 완료!"

    # ── 5. 기본 계정 생성 및 시스템 설정 초기화 (root 권한 1회 설정) ─────────
    Write-Step "[Step 3-5] 기본 계정 및 시스템 환경 구성"
    Write-Info "사용자 계정($createdUsername) 생성 및 wsl.conf(systemd=true 포함) 구성 중..."

    # 1) 일반 사용자 계정 생성 (sudo, adm, users 그룹 등록) 및 비밀번호 설정
    wsl -d $wslName -u root -- bash -c "useradd -m -s /bin/bash -G sudo,adm,users '$createdUsername' && echo '$createdUsername:$plainPassword' | chpasswd"
    $plainPassword = $null

    # 2) hostname 및 /etc/wsl.conf 설정 (default user, systemd=true, interop 포함)
    wsl -d $wslName -u root -- bash -c "echo '$wslName' > /etc/hostname && echo -e '[user]\ndefault=$createdUsername\n\n[interop]\nenabled=true\nappendWindowsPath=true\n\n[boot]\nsystemd=true' > /etc/wsl.conf"

    # 3) Windows Interop 핸들러 등록
    wsl -d $wslName -u root -- bash -c "mkdir -p /etc/binfmt.d /usr/lib/binfmt.d && echo ':WSLInterop:M::MZ::/init:PF' > /etc/binfmt.d/WSLInterop.conf && echo ':WSLInterop:M::MZ::/init:PF' > /usr/lib/binfmt.d/WSLInterop.conf && ([ -f /proc/sys/fs/binfmt_misc/register ] && echo ':WSLInterop:M::MZ::/init:PF' > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true)"

    Write-Success "WSL2 시스템 환경 및 사용자($createdUsername) 구성 완료!"
}

# 9. Windows 사용자 프로필에 .wslconfig (네트워크 미러링) 자동 설정
#    WSL2 내부 포트(8881, 8080, 5005 등)를 Windows 호스트 localhost에서 별도 포트포워딩 없이 바로 접속 가능하도록 동기화
Write-Info "Windows-WSL2 네트워크 포트 직통 연결(mirrored)을 위한 .wslconfig 설정 확인 중..."
$wslConfigFile = Join-Path $env:USERPROFILE ".wslconfig"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

if (Test-Path $wslConfigFile) {
    $existing = Get-Content $wslConfigFile -Raw -ErrorAction SilentlyContinue
    if ($existing -notmatch "networkingMode\s*=\s*mirrored") {
        if ($existing -match "\[wsl2\]") {
            $updated = $existing + "`nnetworkingMode=mirrored`nautoProxy=true`n"
        } else {
            $updated = $existing + "`n[wsl2]`nnetworkingMode=mirrored`nautoProxy=true`n"
        }
        [System.IO.File]::WriteAllText($wslConfigFile, $updated, $utf8NoBom)
        Write-Success ".wslconfig 에 네트워크 미러링(networkingMode=mirrored) 설정이 추가되었습니다."
    } else {
        Write-Success ".wslconfig (networkingMode=mirrored) 설정이 이미 적용되어 있습니다."
    }
} else {
    $defaultWslConfig = "[wsl2]`r`nnetworkingMode=mirrored`r`nautoProxy=true`r`n"
    [System.IO.File]::WriteAllText($wslConfigFile, $defaultWslConfig, $utf8NoBom)
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
[System.IO.File]::WriteAllText($distroSaveFile, "WSL_DISTRO=$wslName`n", $utf8NoBom)

# --------------------------------------------------------------------------
# [Step 4] 완료
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 WSL2 설치 및 환경 설정 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  설치된 배포판 : $installedDistroDesc" -ForegroundColor White
Write-Host "  인스턴스 이름 : $wslName" -ForegroundColor White
Write-Host "  설치 경로     : $wslInstallPath" -ForegroundColor White
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
}

# 세션 한정 빠른 편집 모드(QuickEdit) 원래대로 복원
Restore-ConsoleQuickEdit | Out-Null

# 스크립트 정상 종료 (부모 스크립트의 $LASTEXITCODE 오판 방지)
$global:LASTEXITCODE = 0
return 0

