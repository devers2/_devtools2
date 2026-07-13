# ==============================================================================
# DevTools2 Windows/WSL2 통합 자동 설치 마스터 스크립트 (setup-devtools2.ps1)
#
# 주요 기능:
#   1. Windows WSL2 가상 머신 생성 및 활성화 (0.setup-wsl.ps1)
#   2. WSL2 내부로 Linux 초기화 스크립트를 복사 및 실행하여 깃 자격증명 설정 및 클론 진행
#   3. WSL2 내부의 환경변수 설정, 핵심 개발 런타임 및 CLI 유틸리티 도구 일괄 자동 설치
#   4. Windows 호스트용 Ghostty 및 Zed 에디터 자동 설치 및 WSL2 설정 연동
#
# 사용 방법:
#   PowerShell 을 관리자 권한으로 열고 실행:
#   .\setup-devtools2.ps1
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
    Write-Host "===========================================================================" -ForegroundColor Magenta
    Write-Host "  $Message" -ForegroundColor Magenta
    Write-Host "===========================================================================" -ForegroundColor Magenta
}

function Write-SubStep {
    param([string]$Message)
    Write-Host ""
    Write-Host "---------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  $Message" -ForegroundColor Cyan
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
    Write-Warn "DevTools2 전체 환경 구축을 위해서는 관리자 권한이 필요합니다."
    Write-Warn "관리자 권한으로 스크립트를 재실행합니다..."
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🌟 DevTools2 Windows & WSL2 통합 설치 마스터 자동화" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan

$BaseDir = $PSScriptRoot
$ToolsDir = Join-Path $BaseDir "devtools2"

# 하위 스크립트 경로 존재 여부 사전 점검
$setupWslScript = Join-Path $ToolsDir "0.setup-wsl.ps1"
$setupGhosttyScript = Join-Path $ToolsDir "1.setup-ghostty.ps1"
$setupZedScript = Join-Path $ToolsDir "2.setup-zed.ps1"

if (-not (Test-Path $setupWslScript) -or -not (Test-Path $setupGhosttyScript) -or -not (Test-Path $setupZedScript)) {
    Write-Fail "필수 설치 스크립트 파일을 찾을 수 없습니다. 경로를 확인해 주세요."
    Write-Fail "예상 경로: $ToolsDir"
    Pause-Script
    exit 1
}

# ==============================================================================
# [Step 1] Windows WSL2 가상 머신 생성 및 활성화
# ==============================================================================
Write-Step "[Step 1] WSL2 가상 머신 인스턴스 생성"
& $setupWslScript

# 생성된 메타데이터 조회하여 배포판 이름(WSL_DISTRO) 파싱
$devtools2File = Join-Path $env:USERPROFILE ".devtools2"
if (-not (Test-Path $devtools2File)) {
    Write-Fail "WSL2 설치 과정에서 메타데이터 파일이 생성되지 않았습니다."
    Write-Fail "WSL 설치에 실패했거나 취소되었습니다. 마스터 설정을 중단합니다."
    Pause-Script
    exit 1
}

$savedDistro = Get-Content $devtools2File | Where-Object { $_ -match "^WSL_DISTRO=" } | Select-Object -First 1
if (-not $savedDistro) {
    Write-Fail ".devtools2 파일에서 WSL_DISTRO 정보를 읽을 수 없습니다."
    Pause-Script
    exit 1
}
$wslDistro = ($savedDistro -split "=", 2)[1].Trim()
Write-Info "대상 WSL2 배포판: $wslDistro"

# ==============================================================================
# [Step 2] WSL2 내부로 Linux 초기화 스크립트 복사 및 실행
# ==============================================================================
Write-Step "[Step 2] WSL2 내부 개발도구 디렉터리 및 Git 자격 증명 설정"

$linuxInitScriptSource = Join-Path $BaseDir "..\linux\devtools2\0.init-devtools2.sh"
if (-not (Test-Path $linuxInitScriptSource)) {
    Write-Fail "리눅스 초기화 스크립트 원본을 찾을 수 없습니다: $linuxInitScriptSource"
    Pause-Script
    exit 1
}

# WSL2 내부의 /tmp 경로 확인 및 스크립트 복사
$wslTmpPath = "\\wsl.localhost\$wslDistro\tmp"
if (-not (Test-Path $wslTmpPath)) {
    Write-Fail "WSL2의 /tmp 디렉터리에 접근할 수 없습니다: $wslTmpPath"
    Pause-Script
    exit 1
}

Write-Info "WSL2 내부로 설치 초기화 스크립트를 전송합니다..."
$wslInitScriptTarget = Join-Path $wslTmpPath "0.init-devtools2.sh"
Copy-Item -Path $linuxInitScriptSource -Destination $wslInitScriptTarget -Force -ErrorAction Stop
Write-Success "스크립트 전송 완료"

Write-Info "WSL2 내부에서 초기화 마법사를 실행합니다. 안내에 따라 깃 허브 계정 정보를 입력하세요."
Write-Warn "⚠️ 입력 창이 전환되오니 프롬프트를 주의 깊게 봐주세요."
Write-Host ""

# WSL2 대화형 셸을 통해 sudo 권한으로 init 스크립트 실행
# (SUDO_USER 인식을 위해 일반 로그인 유저 상태로 접근하여 내부에서 sudo 호출)
wsl -d $wslDistro -- bash -c "sudo bash /tmp/0.init-devtools2.sh"

if ($LASTEXITCODE -ne 0) {
    Write-Fail "WSL2 내부 초기화 스크립트 실행 중 에러가 발생했습니다."
    Pause-Script
    exit 1
}
Write-Success "WSL2 내에 개발도구 저장소 클론 및 권한 설정 완료"

# ==============================================================================
# [Step 3] WSL2 내부 런타임 및 도구 일괄 설치
# ==============================================================================
Write-Step "[Step 3] WSL2 개발 환경 빌드 및 패키지 일괄 설치"

Write-SubStep "▶ (1/3) WSL2 환경 변수 주입 (~/.bashrc)"
wsl -d $wslDistro -- bash -l /var/opt/_devtools2/scripts/linux/devtools2/1.setup-env.sh
if ($LASTEXITCODE -ne 0) { Write-Fail "환경 변수 설정 실패"; Pause-Script; exit 1 }

Write-SubStep "▶ (2/3) WSL2 핵심 개발 도구 설치 (Java, Node.js, Python, Neovim)"
wsl -d $wslDistro -- bash -l /var/opt/_devtools2/scripts/linux/devtools2/2.install-core-tools.sh
if ($LASTEXITCODE -ne 0) { Write-Fail "핵심 도구 설치 실패"; Pause-Script; exit 1 }

Write-SubStep "▶ (3/3) WSL2 CLI 유틸리티 및 apt 패키지 설치"
wsl -d $wslDistro -- bash -l /var/opt/_devtools2/scripts/linux/devtools2/3.install-cli-tools.sh
if ($LASTEXITCODE -ne 0) { Write-Fail "CLI 유틸리티 설치 실패"; Pause-Script; exit 1 }

Write-Success "WSL2 내부 가상 머신 개발 환경 구축 완료!"

# ==============================================================================
# [Step 4] Windows 호스트 전용 Ghostty 및 Zed 에디터 연동
# ==============================================================================
Write-Step "[Step 4] Windows 호스트 전용 개발도구 연동"

Write-SubStep "▶ (1/2) Ghostty (Winghostty) 설치 및 설정 연동"
& $setupGhosttyScript -WslDistro $wslDistro

Write-SubStep "▶ (2/2) Zed 에디터 설치 및 설정 연동"
& $setupZedScript -WslDistro $wslDistro

# ==============================================================================
# 전체 설치 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host "🎉 DevTools2 Windows 및 WSL2 전체 개발 환경 통합 구축 완료!" -ForegroundColor Green
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Info "  윈도우와 WSL2가 완벽하게 상호 연동되어 동작합니다."
Write-Info "  - Windows 셸에서 'wsl'을 치면 설정이 완료된 Ubuntu 개발 환경에 바로 진입합니다."
Write-Info "  - Windows에 설치된 Ghostty 및 Zed 에디터의 설정은 WSL2 내부 설정과 실시간 공유됩니다."
Write-Host ""
Write-Host "  설치 성공을 확인하시려면 아래 도구들을 실행해 보세요:"
Write-Host "    - Windows: Ghostty 터미널 열기 (PowerShell 7 실행 확인)" -ForegroundColor Gray
Write-Host "    - Windows: Zed 에디터 열기" -ForegroundColor Gray
Write-Host "    - WSL2 내부: nvim --version, java -version, node -v 실행 확인" -ForegroundColor Gray
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host ""

Pause-Script
