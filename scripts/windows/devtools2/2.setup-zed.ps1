# ==============================================================================
# Zed 에디터 설치 및 WSL2 설정 파일 심볼릭 링크 생성 스크립트
#
# 주요 기능:
#   1. winget 을 통해 Zed 에디터를 자동 설치 (이미 설치되어 있으면 건너뜀)
#   2. WSL2 의 _devtools2/.config/zed/ 내 설정 파일을 Windows Zed 설정 경로로 링크 생성
#      - settings.json  : 에디터 전역 설정  (%APPDATA%\Zed\settings.json)
#      - keymap.json    : 키보드 단축키 설정 (%APPDATA%\Zed\keymap.json)
#
#   Zed 는 설정 외에도 캐시(extensions, state.json, workspaces 등)를 같은 폴더에
#   자동 생성하므로, 폴더 전체가 아닌 필요한 파일별로만 링크를 생성합니다.
#
# 사전 조건:
#   - WSL2 에 Ubuntu 계열 배포판이 설치되어 있어야 합니다.
#   - Windows 에서 관리자 권한이 필요합니다 (심볼릭 링크 생성).
#   - winget 이 설치되어 있어야 합니다 (Windows 10 1809+ / Windows 11 기본 포함).
#
# 사용 방법:
#   PowerShell 을 관리자 권한으로 열고 실행:
#   .\2.setup-zed.ps1
#   또는 WSL2 배포판 이름을 직접 지정:
#   .\2.setup-zed.ps1 -WslDistro "Ubuntu-24.04"
# ==============================================================================

param(
    # WSL2 배포판 이름 (기본값: 첫 번째로 찾은 기본 배포판 자동 감지)
    [string]$WslDistro = ""
)

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

function Write-Skip {
    param([string]$Message)
    Write-Host "[건너뜀] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[오류] $Message" -ForegroundColor Red
}

# 파일 심볼릭 링크를 안전하게 생성하는 함수
# - 대상이 이미 심볼릭 링크이면 건너뜀
# - 대상이 일반 파일이면 .bak 으로 백업 후 링크 생성
# - 부모 디렉터리가 없으면 자동 생성
function New-SafeFileSymlink {
    param(
        [string]$LinkPath,   # 생성할 링크 경로 (Windows 측)
        [string]$TargetPath  # 링크가 가리킬 실제 경로 (WSL2 측)
    )

    # 부모 디렉터리 생성
    $parentDir = Split-Path $LinkPath -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    if (Test-Path $LinkPath) {
        $item = Get-Item $LinkPath -Force
        if ($item.LinkType -eq "SymbolicLink") {
            Write-Skip "'$(Split-Path $LinkPath -Leaf)' 는 이미 심볼릭 링크입니다."
            return
        }
        else {
            # 기존 파일을 .bak 으로 백업
            $backupPath = "$LinkPath.bak"
            Write-Host "  [백업] '$LinkPath' -> '$backupPath'" -ForegroundColor Yellow
            Move-Item -Path $LinkPath -Destination $backupPath -Force
        }
    }

    # WSL2 경로 접근 가능 여부 확인
    if (-not (Test-Path $TargetPath)) {
        Write-Fail "WSL2 소스 파일을 찾을 수 없습니다: $TargetPath"
        Write-Host "  WSL2 에서 먼저 1.setup-dev-env.sh 를 실행해주세요." -ForegroundColor Yellow
        return
    }

    try {
        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
        Write-Success "링크 생성: '$(Split-Path $LinkPath -Leaf)'"
        Write-Host "    Windows : $LinkPath" -ForegroundColor DarkGray
        Write-Host "    WSL2    : $TargetPath" -ForegroundColor DarkGray
    }
    catch {
        Write-Fail "심볼릭 링크 생성 실패 ('$(Split-Path $LinkPath -Leaf)'): $($_.Exception.Message)"
    }
}

# ==============================================================================
# [Step 0] 관리자 권한 확인 및 재실행
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host "[경고] 심볼릭 링크 생성에는 관리자 권한이 필요합니다." -ForegroundColor Yellow
    Write-Host "       관리자 권한으로 스크립트를 재실행합니다..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -WslDistro `"$WslDistro`"" -Verb RunAs
    exit
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host "🚀 Zed 에디터 설치 및 설정 파일 링크 생성 스크립트" -ForegroundColor Magenta
Write-Host "===========================================================================" -ForegroundColor Magenta

# ==============================================================================
# [Step 1] WSL2 배포판 이름 자동 감지
# ==============================================================================
Write-Step "[Step 1] WSL2 배포판 감지"

if ($WslDistro -eq "") {
    # 1순위: %USERPROFILE%\.devtools2 파일에서 0.setup-wsl.ps1 이 저장한 이름 사용
    $devtools2File = Join-Path $env:USERPROFILE ".devtools2"
    if (Test-Path $devtools2File) {
        $saved = Get-Content $devtools2File | Where-Object { $_ -match "^WSL_DISTRO=" } | Select-Object -First 1
        if ($saved) {
            $WslDistro = ($saved -split "=", 2)[1].Trim()
            Write-Host "  .devtools2 파일에서 읽은 배포판: $WslDistro" -ForegroundColor White
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

$WslRoot = "\\wsl.localhost\$WslDistro"

# WSL2 내 사용자 이름 확인
$WslUsername = (wsl -d $WslDistro -- whoami).Trim()
$WslHome = "$WslRoot\home\$WslUsername"

Write-Host "  WSL2 홈 경로: $WslHome" -ForegroundColor White

# _devtools2 경로 확인
$DevTools2Wsl = "$WslHome\_devtools2"
if (-not (Test-Path $DevTools2Wsl)) {
    Write-Fail "WSL2 에서 '_devtools2' 폴더를 찾을 수 없습니다: $DevTools2Wsl"
    Write-Host "  WSL2 에서 먼저 1.setup-dev-env.sh 를 실행해주세요." -ForegroundColor Yellow
    Read-Host "계속하려면 엔터를 누르세요"
    exit 1
}
Write-Host "  _devtools2 경로: $DevTools2Wsl" -ForegroundColor White

# ==============================================================================
# [Step 2] Zed 에디터 설치
# ==============================================================================
Write-Step "[Step 2] Zed 에디터 설치"

$zedInstalled = $false
try {
    $result = winget list --id Zed.Zed 2>$null
    if ($result -match "Zed.Zed") {
        $zedInstalled = $true
    }
}
catch {}

if ($zedInstalled) {
    Write-Skip "Zed 에디터가 이미 설치되어 있습니다."
}
else {
    Write-Host "  Zed 에디터를 winget 으로 설치합니다..." -ForegroundColor White
    winget install --id Zed.Zed --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Zed 에디터 설치 완료"
    }
    else {
        Write-Fail "Zed 설치 실패 (종료 코드: $LASTEXITCODE)"
        Write-Host "  수동 설치: https://zed.dev/download" -ForegroundColor Yellow
    }
}

# ==============================================================================
# [Step 3] Zed 설정 파일 심볼릭 링크 생성
#
# Zed Windows 설정 경로: %APPDATA%\Zed\
#   - settings.json  : 에디터 전역 설정
#   - keymap.json    : 키보드 단축키
#
# 링크하지 않는 항목 (Zed 가 자동 생성, gitignore 에 포함):
#   - state.json, session.json, workspaces/, extensions/, *.log
#
# WSL2 소스: \\wsl.localhost\<Distro>\home\<user>\_devtools2\.config\zed\
# ==============================================================================
Write-Step "[Step 3] Zed 설정 파일 심볼릭 링크 생성"

$WslZedConfig = "$DevTools2Wsl\.config\zed"
$WinZedDir    = "$env:APPDATA\Zed"

Write-Host "  소스 (WSL2): $WslZedConfig" -ForegroundColor DarkGray
Write-Host "  링크 대상  : $WinZedDir" -ForegroundColor DarkGray
Write-Host ""

# settings.json 링크
Write-Host "  📄 settings.json 링크 생성 중..."
New-SafeFileSymlink -LinkPath "$WinZedDir\settings.json" `
                    -TargetPath "$WslZedConfig\settings.json"

Write-Host ""

# keymap.json 링크
Write-Host "  📄 keymap.json 링크 생성 중..."
New-SafeFileSymlink -LinkPath "$WinZedDir\keymap.json" `
                    -TargetPath "$WslZedConfig\keymap.json"

# ==============================================================================
# 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host "🎉 Zed 설정 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  링크된 설정 파일 목록:" -ForegroundColor White
Write-Host "    $WinZedDir\settings.json -> (WSL2) .config\zed\settings.json" -ForegroundColor DarkGray
Write-Host "    $WinZedDir\keymap.json   -> (WSL2) .config\zed\keymap.json" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  링크하지 않은 항목 (Zed 자동 생성):" -ForegroundColor White
Write-Host "    state.json, session.json, workspaces/, extensions/, *.log" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Zed 를 재시작하면 설정이 적용됩니다." -ForegroundColor Yellow
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host ""

Read-Host "계속하려면 엔터를 누르세요"
