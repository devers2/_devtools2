# ==============================================================================
# WSL2 설치 스크립트
#
# 주요 기능:
#   1. Z: (개발자 드라이브/refs) 존재 여부 확인
#      - 없으면: 기본 경로 설치 여부 확인 (y/n)
#      - 있으면: Z:\WSL\(이름) 경로에 설치
#   2. Ubuntu 배포판 버전 선택 (최신LTS / 24.04 / 22.04)
#   3. WSL 인스턴스 이름 입력 (기본값: Ubuntu)
#   4. WSL 업데이트 → WSL2 기본 설정 → 배포판 설치
#   5. %USERPROFILE%\.devtools2 파일에 WSL 인스턴스 이름 저장
#
# 사용 방법:
#   PowerShell 을 관리자 권한으로 열고 실행:
#   .\0.setup-wsl.ps1
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
# [Step 0] 관리자 권한 확인 및 재실행
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
Write-Host "  🐧 WSL2 설치 스크립트" -ForegroundColor Magenta
Write-Host "===========================================================================" -ForegroundColor Magenta

# ==============================================================================
# [Step 1] Z: 드라이브(개발자 드라이브/refs) 존재 여부 확인
# ==============================================================================
Write-Step "[Step 1] 개발자 드라이브(Z:) 확인"

$hasDevDrive = Test-Path "Z:\"
$installRoot = $null   # 최종 결정된 WSL 설치 루트 경로

if ($hasDevDrive) {
    Write-Success "Z: 개발자 드라이브가 감지되었습니다."
    Write-Info    "WSL 은 Z:\WSL\(이름) 경로에 설치됩니다."
    $installRoot = "Z:\WSL"
}
else {
    Write-Warn "Z: 드라이브(개발자 드라이브)를 찾을 수 없습니다."
    Write-Host ""
    Write-Host "  개발자 드라이브가 없으면 WSL 을 기본 경로에 설치합니다." -ForegroundColor White
    Write-Host "  (기본 경로: %LOCALAPPDATA%\Packages\... 또는 %USERPROFILE%\AppData\Local\...)" -ForegroundColor DarkGray
    Write-Host ""

    do {
        $answer = Read-Host "  기본 경로에 WSL 을 설치하시겠습니까? (y/n)"
        $answer = $answer.Trim().ToLower()
    } while ($answer -ne "y" -and $answer -ne "n")

    if ($answer -eq "n") {
        Write-Host ""
        Write-Warn "설치를 취소합니다."
        Write-Host ""
        Write-Host "  개발자 드라이브(Dev Drive) 설정 방법:" -ForegroundColor White
        Write-Host "  1. 설정 → 시스템 → 저장소 → 개발자 드라이브" -ForegroundColor DarkGray
        Write-Host "  2. 또는: https://learn.microsoft.com/ko-kr/windows/dev-drive" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  개발자 드라이브 설정 후 이 스크립트를 다시 실행해주세요." -ForegroundColor Yellow
        Write-Host ""
        Pause-Script
        exit 0
    }

    # y 선택: 기본 경로 사용 (--location 없이 wsl --install)
    $installRoot = $null
    Write-Info "기본 경로에 설치를 진행합니다."
}

# ==============================================================================
# [Step 2] Ubuntu 배포판 버전 선택
# ==============================================================================
Write-Step "[Step 2] Ubuntu 배포판 버전 선택"

Write-Host ""
Write-Host "  설치할 Ubuntu 버전을 선택하세요:" -ForegroundColor White
Write-Host ""
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
    "1" { $distroId = "Ubuntu";       $distroLabel = "Ubuntu (최신 LTS)" }
    "2" { $distroId = "Ubuntu-24.04"; $distroLabel = "Ubuntu 24.04 LTS"  }
    "3" { $distroId = "Ubuntu-22.04"; $distroLabel = "Ubuntu 22.04 LTS"  }
}

Write-Info "선택된 배포판: $distroLabel"

# ==============================================================================
# [Step 3] WSL 인스턴스 이름 입력
# ==============================================================================
Write-Step "[Step 3] WSL 인스턴스 이름 입력"

Write-Host ""
Write-Host "  WSL 인스턴스에 사용할 이름을 입력하세요." -ForegroundColor White
Write-Host "  여러 WSL 인스턴스를 구분할 때 사용됩니다." -ForegroundColor DarkGray
Write-Host "  (예: Ubuntu, dev-ubuntu, work-ubuntu)" -ForegroundColor DarkGray
Write-Host ""

$wslName = Read-Host "  인스턴스 이름 (기본값: Ubuntu)"
$wslName = $wslName.Trim()
if ($wslName -eq "") { $wslName = "Ubuntu" }

# 이름 유효성 검사: 공백, 특수문자 불허
if ($wslName -match "[^a-zA-Z0-9\-_\.]") {
    Write-Warn "이름에 영문자, 숫자, 하이픈(-), 언더스코어(_), 점(.) 만 사용 가능합니다."
    Write-Warn "이름을 'Ubuntu' 로 초기화합니다."
    $wslName = "Ubuntu"
}

Write-Info "WSL 인스턴스 이름: $wslName"

# 최종 설치 경로 결정
if ($null -ne $installRoot) {
    $wslInstallPath = "$installRoot\$wslName"
    Write-Info "설치 경로: $wslInstallPath"
}
else {
    Write-Info "설치 경로: Windows 기본 경로 (자동)"
}

# ==============================================================================
# 설치 요약 출력 및 최종 확인
# ==============================================================================
Write-Host ""
Write-Host "---------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  📋 설치 요약" -ForegroundColor Cyan
Write-Host "---------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  배포판    : $distroLabel ($distroId)" -ForegroundColor White
Write-Host "  인스턴스명: $wslName" -ForegroundColor White
if ($null -ne $installRoot) {
    Write-Host "  설치 경로 : $wslInstallPath" -ForegroundColor White
}
else {
    Write-Host "  설치 경로 : Windows 기본 경로" -ForegroundColor White
}
Write-Host "---------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

do {
    $confirm = Read-Host "  위 설정으로 설치를 시작하시겠습니까? (y/n)"
    $confirm = $confirm.Trim().ToLower()
} while ($confirm -ne "y" -and $confirm -ne "n")

if ($confirm -eq "n") {
    Write-Warn "설치를 취소합니다. 스크립트를 다시 실행해주세요."
    Pause-Script
    exit 0
}

# ==============================================================================
# [Step 4] WSL 업데이트 및 버전 설정
# ==============================================================================
Write-Step "[Step 4] WSL 업데이트 및 WSL2 기본 설정"

Write-Info "WSL 커널을 최신 버전으로 업데이트합니다..."
wsl --update
if ($LASTEXITCODE -ne 0) {
    Write-Warn "WSL 업데이트 중 경고가 발생했습니다. 계속 진행합니다."
}

Write-Info "WSL 기본 버전을 2로 설정합니다..."
wsl --set-default-version 2
if ($LASTEXITCODE -ne 0) {
    Write-Fail "WSL2 기본 설정에 실패했습니다."
    Write-Warn "Windows 기능 'Virtual Machine Platform' 이 활성화되어 있는지 확인해주세요."
    Pause-Script
    exit 1
}
Write-Success "WSL2 기본 설정 완료"

# ==============================================================================
# [Step 5] WSL 배포판 설치
# ==============================================================================
Write-Step "[Step 5] $distroLabel 설치"

if ($null -ne $installRoot) {
    # Z: 드라이브가 있을 경우: 경로 생성 후 --location 옵션으로 설치
    Write-Info "$wslInstallPath 폴더를 생성합니다..."
    if (-not (Test-Path $wslInstallPath)) {
        New-Item -ItemType Directory -Path $wslInstallPath -Force | Out-Null
        Write-Success "폴더 생성 완료: $wslInstallPath"
    }
    else {
        Write-Warn "폴더가 이미 존재합니다: $wslInstallPath"
    }

    Write-Info "$distroId 를 '$wslName' 이름으로 $wslInstallPath 에 설치합니다..."
    Write-Warn "설치 중 Ubuntu 초기 사용자 설정이 진행됩니다. 안내에 따라 입력해주세요."
    Write-Host ""

    wsl --install -d $distroId --name $wslName --location $wslInstallPath
}
else {
    # Z: 드라이브 없음: 기본 경로에 설치
    Write-Info "$distroId 를 '$wslName' 이름으로 기본 경로에 설치합니다..."
    Write-Warn "설치 중 Ubuntu 초기 사용자 설정이 진행됩니다. 안내에 따라 입력해주세요."
    Write-Host ""

    wsl --install -d $distroId --name $wslName
}

if ($LASTEXITCODE -ne 0) {
    Write-Fail "WSL 배포판 설치 중 오류가 발생했습니다 (종료 코드: $LASTEXITCODE)"
    Write-Warn "설치가 불완전할 수 있습니다. 아래 명령으로 상태를 확인하세요:"
    Write-Host "    wsl --list --verbose" -ForegroundColor DarkGray
    Pause-Script
    exit 1
}

Write-Success "$distroLabel ('$wslName') 설치 완료"

# ==============================================================================
# [Step 5-후처리] 실제 등록된 WSL 배포판 이름 검증 및 자동 보정
#
# 일부 Windows 버전에서 --name 플래그가 무시되어 기본값(Ubuntu 등)으로
# 등록될 수 있습니다. 설치 후 실제 이름을 확인하여 자동으로 보정합니다.
# ==============================================================================
Write-Info "실제 등록된 WSL 배포판 이름 검증 중..."

# 최대 20초 대기하며 WSL 목록에 나타날 때까지 확인
$verified = $false
for ($i = 0; $i -lt 10; $i++) {
    $registeredList = (wsl --list --quiet 2>$null) -replace "`0", "" |
        Where-Object { $_.Trim() -ne "" } |
        ForEach-Object { $_.Trim() }

    if ($registeredList -and $registeredList.Count -gt 0) {
        # 요청한 이름($wslName)이 목록에 있는지 확인
        $matchedName = $registeredList | Where-Object { $_ -eq $wslName } | Select-Object -First 1
        if ($matchedName) {
            Write-Success "배포판 이름 확인 완료: $wslName"
            $verified = $true
            break
        }

        # 목록에 없으면 가장 최근에 추가된 배포판(목록 첫 번째)을 실제 이름으로 사용
        $actualName = $registeredList[0]
        Write-Warn "--name '$wslName' 이 무시되어 '$actualName' 으로 등록되었습니다."
        Write-Warn "이름을 '$actualName' 으로 자동 보정합니다."
        $wslName = $actualName
        $verified = $true
        break
    }

    Write-Info "  WSL 배포판 등록 대기 중... ($($i + 1)/10)"
    Start-Sleep -Seconds 2
}

if (-not $verified) {
    Write-Warn "WSL 배포판 이름을 자동으로 확인하지 못했습니다. '$wslName' 이름으로 계속 진행합니다."
}

# ==============================================================================
# [Step 6] %USERPROFILE%\.devtools2 파일에 WSL 인스턴스 이름 저장
#
# 이후 1.setup-ghostty.ps1, 2.setup-zed.ps1 등에서 기본 배포판 이름으로 활용
# ==============================================================================
Write-Step "[Step 6] WSL 인스턴스 정보 저장 (~\.devtools2)"

$devtools2File = Join-Path $env:USERPROFILE ".devtools2"

$fileContent = @"
# DevTools2 WSL 설정 파일
# 이 파일은 0.setup-wsl.ps1 에 의해 자동 생성됩니다.
# scripts/windows/env/ 의 다른 스크립트가 기본 WSL 배포판 이름을 읽을 때 사용합니다.

WSL_DISTRO=$wslName
WSL_DISTRO_ID=$distroId
WSL_INSTALL_PATH=$wslInstallPath
CREATED_AT=$(Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
"@

try {
    $fileContent | Out-File -FilePath $devtools2File -Encoding UTF8 -Force
    Write-Success "설정 파일 저장: $devtools2File"
    Write-Host ""
    Write-Host "  저장된 내용:" -ForegroundColor DarkGray
    Get-Content $devtools2File | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
}
catch {
    Write-Fail "설정 파일 저장 실패: $($_.Exception.Message)"
}

# ==============================================================================
# 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host "🎉 WSL2 설치 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  설치된 배포판 : $distroLabel" -ForegroundColor White
Write-Host "  인스턴스 이름 : $wslName" -ForegroundColor White
if ($null -ne $installRoot) {
    Write-Host "  설치 경로     : $wslInstallPath" -ForegroundColor White
}
Write-Host "  설정 파일     : $devtools2File" -ForegroundColor White
Write-Host ""
Write-Host "  다음 단계:" -ForegroundColor Cyan
Write-Host "  1. WSL 에 접속:  wsl -d $wslName" -ForegroundColor White
Write-Host "  2. _devtools2 를 WSL 홈에 클론 또는 마운트" -ForegroundColor White
Write-Host "  3. WSL 내에서 scripts/linux/env/1.setup-dev-env.sh 실행" -ForegroundColor White
Write-Host "  4. WSL 내에서 scripts/linux/env/2.install-devtools2.sh 실행" -ForegroundColor White
Write-Host "  5. Windows 에서 scripts/windows/env/1.setup-ghostty.ps1 실행" -ForegroundColor White
Write-Host "  6. Windows 에서 scripts/windows/env/2.setup-zed.ps1 실행" -ForegroundColor White
Write-Host ""
Write-Host "  설치된 배포판 목록 확인:" -ForegroundColor DarkGray
Write-Host "    wsl --list --verbose" -ForegroundColor DarkGray
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host ""

Pause-Script
