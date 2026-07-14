# ==============================================================================
# WSL2 설치 및 마이그레이션 스크립트 (0.setup-wsl.ps1)
# ==============================================================================

# --- 한글 깨짐 방지: 출력 인코딩을 UTF-8 로 설정
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==============================================================================
# 헬퍼 함수
# ==============================================================================

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "---------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[성공] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[정보] $Message" -ForegroundColor White
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[경고] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[오류] $Message" -ForegroundColor Red
}

function Pause-Script {
    Write-Host ""
    Read-Host "계속하려면 엔터를 누르세요"
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
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host "  🐧 WSL2 설치 및 설정 스크립트 (인스턴스명: devtools2)"
Write-Host "===========================================================================" -ForegroundColor Magenta

# 고정된 인스턴스 이름 설정
$wslName = "devtools2"
$devtools2File = Join-Path $env:USERPROFILE ".devtools2"

# ==============================================================================
# [Step 1] WSL2 가상 머신 상태 확인 및 설치 진행
# ==============================================================================
Write-Step "[Step 1] WSL2 가상 머신 상태 확인"

# 현재 등록된 WSL 배포판 목록 가져오기
$registeredDistros = (wsl --list --quiet 2>$null) -replace "`0", "" |
    Where-Object { $_.Trim() -ne "" } |
    ForEach-Object { $_.Trim() }

# 1. 'devtools2'가 이미 등록되어 있다면 설정 파일 복구 및 즉시 통과
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
    
    # 설정 파일이 없거나 내용이 다르면 생성/업데이트
    if (-not (Test-Path $devtools2File)) {
        Write-Info "설정 파일(.devtools2)을 작성/복구합니다..."
        $hasDevDrive = Test-Path "Z:\"
        $wslInstallPath = if ($hasDevDrive) { "Z:\WSL\$wslName" } else { Join-Path $env:USERPROFILE "AppData\Local\WSL\$wslName" }
        
        $fileContent = @"
# DevTools2 WSL 설정 파일
# 이 파일은 0.setup-wsl.ps1 에 의해 자동 생성됩니다.

WSL_DISTRO=$wslName
WSL_DISTRO_ID=Ubuntu
WSL_INSTALL_PATH=$wslInstallPath
CREATED_AT=$(Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
"@
        $fileContent | Out-File -FilePath $devtools2File -Encoding UTF8 -Force
    }
    
    Write-Success "환경 설정 복구 완료. 다음 단계로 진행합니다."
    Pause-Script
    exit 0
}

# 2. 임시 설치를 위한 base Ubuntu 가 등록되어 있는지 확인
# (Ubuntu, Ubuntu-24.04, Ubuntu-22.04 등 우분투 계열 배포판 스캔)
$distroId = $registeredDistros | Where-Object { $_ -match "^Ubuntu" } | Select-Object -First 1
$isBaseRegistered = -not [string]::IsNullOrEmpty($distroId)

if (-not $isBaseRegistered) {
    # --------------------------------------------------------------------------
    # Phase 1: WSL2 기본 설치 (최초 실행 및 버전 선택)
    # --------------------------------------------------------------------------
    Write-Step "[Step 2] Ubuntu 배포판 버전 선택 및 설치 진행"
    
    Write-Host "  설치할 Ubuntu 버전을 선택하세요:" -ForegroundColor White
    Write-Host "    1) Ubuntu        (최신 LTS - 권장)" -ForegroundColor White
    Write-Host "    2) Ubuntu-24.04  (24.04 LTS)" -ForegroundColor White
    Write-Host "    3) Ubuntu-22.04  (22.04 LTS)" -ForegroundColor White
    Write-Host ""

    do {
        $versionChoice = Read-Host "  번호를 입력하세요 [1/2/3] (기본값: 1)"
        $versionChoice = $versionChoice.Trim()
        if ($versionChoice -eq "") { $versionChoice = "1" }
    } while ($versionChoice -notmatch "^[123]$")

    switch ($versionChoice) {
        "1" { $distroId = "Ubuntu" }
        "2" { $distroId = "Ubuntu-24.04" }
        "3" { $distroId = "Ubuntu-22.04" }
    }

    Write-Info "선택된 배포판: $distroId"
    Write-Info "'$distroId' 배포판 설치를 시작합니다..."
    Write-Warn "설치 중 또는 완료 후 새 창이 열리며 Ubuntu 초기 사용자 설정(Username/Password)이 진행됩니다."
    Write-Host ""

    # 설치 시도
    wsl --install -d $distroId --web-download
    $exitCode = $LASTEXITCODE

    # 에러 코드에 따라 일반 설치 시도 (이미 등록된 오류 등을 제외한 실제 실패 시에만 실행)
    if ($exitCode -ne 0 -and $exitCode -ne 2147024894 -and $exitCode -ne 2147942420) {
        Write-Warn "--web-download 실패 또는 건너뜀. 일반 설치 모드로 재시도합니다..."
        wsl --install -d $distroId
    }

    Write-Host ""
    Write-Warn "---------------------------------------------------------------------------"
    Write-Warn " [설치 시작 완료 - 다음 조치 가이드]"
    Write-Warn " 1. 새로 열린 리눅스(Ubuntu) 창에서 사용자 계정명(Username)과 비밀번호를 설정해 주세요."
    Write-Warn "    (만약 창이 자동으로 열리지 않는다면, 시작 메뉴에서 Ubuntu를 실행하시거나"
    Write-Warn "     윈도우 기능 활성화를 위해 컴퓨터를 재부팅해 주시기 바랍니다.)"
    Write-Warn " 2. 계정 생성이 완료되면 해당 리눅스 창을 닫아주세요."
    Write-Warn " 3. 그 후, 처음에 실행했던 설치 명령어(마스터 스크립트)를 다시 실행해 주시면"
    Write-Warn "    devtools2로의 마이그레이션 및 개발도구 빌드가 자동으로 이어서 진행됩니다."
    Write-Warn "---------------------------------------------------------------------------"
    Write-Host ""
    Pause-Script
    exit 3010
}

# --------------------------------------------------------------------------
# Phase 2: 'devtools2'로 마이그레이션 및 WSL 설정 (재부팅 후 또는 배포판 감지 시)
# --------------------------------------------------------------------------
Write-Step "[Step 3] devtools2 인스턴스 마이그레이션 및 설정"

# 설치 경로 결정
# Z: 드라이브는 같은 PC의 여러 Windows 사용자가 공유할 수 있으므로,
# 파일 충돌 방지를 위해 경로에 Windows 계정명($env:USERNAME)을 포함합니다.
# (배포판 이름 'devtools2'는 고정 유지 - WSL 등록은 사용자별로 독립적)
$windowsUser = $env:USERNAME.ToLower()
$hasDevDrive = Test-Path "Z:\"
if ($hasDevDrive) {
    Write-Success "Z: 개발자 드라이브(ReFS)가 감지되었습니다."
    # 경로에 Windows 사용자명을 포함하여 다른 계정과 파일 충돌 방지
    $wslInstallPath = "Z:\wsl\devtools2\$windowsUser"
    Write-Info "WSL 가상 머신은 Z: 드라이브에 설치됩니다. (경로: $wslInstallPath)"
    Write-Info "(다른 Windows 계정과 Z: 드라이브를 공유하더라도 파일 경로가 분리됩니다.)"
} else {
    Write-Warn "Z: 개발자 드라이브를 찾을 수 없습니다. C: 드라이브 사용자 폴더로 설치를 계속 진행합니다."
    $wslInstallPath = Join-Path $env:USERPROFILE "AppData\Local\WSL\$wslName"
}

Write-Info "설치 경로: $wslInstallPath"
Write-Info "Ubuntu($distroId)를 '$wslName'으로 마이그레이션(Export/Import)합니다..."

# 1. 사용자 계정명 확인
Write-Info "설정된 사용자 계정 정보를 읽어오는 중..."
$createdUsername = ""
try {
    $whoamiResult = wsl -d $distroId -e whoami 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrEmpty($whoamiResult)) {
        $createdUsername = $whoamiResult.Trim()
    }
} catch {}

if ([string]::IsNullOrEmpty($createdUsername) -or $createdUsername -match "error" -or $createdUsername -match "실패" -or $createdUsername -match "Wsl/Service") {
    $createdUsername = "ubuntu"
}
Write-Success "생성된 사용자 계정 확인: $createdUsername"

# 2. 임시 tar 백업 파일 생성
$tempTarPath = Join-Path $env:TEMP "wsl_temp_$($wslName).tar"

# 3. 배포판 내보내기 (Export)
Write-Info "배포판을 백업 파일($tempTarPath)로 내보내는 중..."
wsl --export $distroId $tempTarPath
if ($LASTEXITCODE -ne 0) {
    Write-Fail "배포판 내보내기(Export)에 실패했습니다."
    Pause-Script
    exit 1
}

# 4. 기존 임시 배포판 제거 (Unregister)
Write-Info "임시 설치된 기본 배포판을 해제합니다..."
wsl --unregister $distroId

# 5. 최종 경로 폴더 준비
if (-not (Test-Path $wslInstallPath)) {
    New-Item -ItemType Directory -Path $wslInstallPath -Force | Out-Null
}

# 6. 새로운 이름/경로로 가져오기 (Import)
Write-Info "배포판을 '$wslName' 이름으로 $wslInstallPath 에 가져오는 중..."
wsl --import $wslName $wslInstallPath $tempTarPath
if ($LASTEXITCODE -ne 0) {
    Write-Fail "배포판 가져오기(Import)에 실패했습니다."
    if (Test-Path $tempTarPath) { Remove-Item $tempTarPath -Force }
    Pause-Script
    exit 1
}

# 7. 기본 로그인 사용자를 설정 (wsl.conf 수정)
wsl -d $wslName -u root -e bash -c "echo -e '[user]\ndefault=$createdUsername' > /etc/wsl.conf"

# 8. 임시 파일 삭제
if (Test-Path $tempTarPath) {
    Remove-Item $tempTarPath -Force
}

# --------------------------------------------------------------------------
# [Step 4] 설정 정보 저장 및 완료
# --------------------------------------------------------------------------
Write-Step "[Step 4] WSL 인스턴스 정보 저장 (~\.devtools2)"

$fileContent = @"
# DevTools2 WSL 설정 파일
# 이 파일은 0.setup-wsl.ps1 에 의해 자동 생성됩니다.

WSL_DISTRO=$wslName
WSL_DISTRO_ID=$distroId
WSL_INSTALL_PATH=$wslInstallPath
CREATED_AT=$(Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
"@

try {
    $fileContent | Out-File -FilePath $devtools2File -Encoding UTF8 -Force
    Write-Success "설정 파일 저장: $devtools2File"
}
catch {
    Write-Fail "설정 파일 저장 실패: $($_.Exception.Message)"
    Pause-Script
    exit 1
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host "🎉 WSL2 설치 및 환경 설정 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  설치된 배포판 : Ubuntu ($distroId)" -ForegroundColor White
Write-Host "  인스턴스 이름 : $wslName" -ForegroundColor White
Write-Host "  설치 경로     : $wslInstallPath" -ForegroundColor White
Write-Host "  설정 파일     : $devtools2File" -ForegroundColor White
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host ""

Pause-Script
