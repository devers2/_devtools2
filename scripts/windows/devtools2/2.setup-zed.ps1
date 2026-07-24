# ==============================================================================
# Zed 에디터 설치 및 WSL2 설정 파일 복사 스크립트 (2.setup-zed.ps1)
#
# 주요 기능:
#   1. winget 을 통해 Zed 에디터를 자동 설치 (이미 설치되어 있으면 건너뜀)
#   2. WSL2 의 _devtools2/.config/zed/ 내 설정 파일을 Windows Zed 설정 경로로 복사
#      - settings.json  : 에디터 전역 설정  (%APPDATA%\Zed\settings.json)
#      - keymap.json    : 키보드 단축키 설정 (%APPDATA%\Zed\keymap.json)
#
# [중요] 한글 깨짐 방지 안내 (Encoding Notice):
#   - 로컬 실행 시: 본 스크립트는 UTF-8(BOM 없음)로 저장되어 있어, 구버전 윈도우 기본 
#     PowerShell 5.1 콘솔에서 직접 로컬 실행할 경우 한글 주석 및 메시지가 깨질 수 있습니다.
#     로컬 실행 시에는 가급적 PowerShell 7 (pwsh)을 설치한 후 실행하시기 바랍니다.
#   - 온라인 실행 시: 웹 브라우저나 원격 다운로드 명령(irm | iex 등)을 사용해 온라인에서
#     실시간으로 실행하는 경우에는 인코딩 다운로드 보정이 적용되어 문제없이 정상 동작합니다.
#
# 사전 조건:
#   - WSL2 에 Ubuntu 계열 배포판이 설치되어 있어야 합니다.
#   - Windows 에서 관리자 권한이 필요합니다 (심볼릭 링크 생성).
#   - winget 이 설치되어 있어야 합니다.
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



# 프로세스 종료 시까지 스피너를 표시해 대기하는 함수
function Wait-ProcessWithSpinner {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Message
    )

    $spinner = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $spinIdx = 0
    while (-not $Process.HasExited) {
        $char = $spinner[$spinIdx]
        Write-Host -NoNewline "`r  [$char] $Message...   " -ForegroundColor Cyan
        $spinIdx = ($spinIdx + 1) % $spinner.Count
        Start-Sleep -Milliseconds 150
    }
    Write-Host "`r  [완료] $Message 완료!   " -ForegroundColor Green
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
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🚀 Zed 에디터 설치 및 설정 파일 링크 생성 스크립트" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan

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

# WSL2 UNC 경로 기본값 (\\wsl.localhost\<Distro>\...)
$WslRoot = "\\wsl.localhost\$WslDistro"

# WSL 심볼릭 링크는 Windows UNC 경로에서 따라가지 못하므로
# _devtools2 고정 경로를 직접 참조합니다: /var/opt/_devtools2
$DevTools2Wsl = "$WslRoot\var\opt\_devtools2"

if (-not (Test-Path $DevTools2Wsl)) {
    Write-Fail "WSL2 에서 '_devtools2' 폴더를 찾을 수 없습니다: $DevTools2Wsl"
    Write-Host "  마스터 설치 스크립트(setup-devtools2-wsl.ps1)를 먼저 실행해주세요." -ForegroundColor Yellow
    Read-Host "계속하려면 엔터를 누르세요"
    exit 1
}
Write-Host "  _devtools2 경로: $DevTools2Wsl" -ForegroundColor White

# ==============================================================================
# [Step 2] Zed 에디터 설치
# ==============================================================================
Write-Step "[Step 2] Zed 에디터 설치"

# winget 소스 업데이트 (최초 실행 시 동의 질문으로 인한 무한 대기 멈춤 방지)
try {
    Write-Host "  winget 패키지 매니저 소스를 확인하는 중..." -ForegroundColor White
    $pSrc = Start-Process winget -ArgumentList "source update" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\zed_source_update.log" -RedirectStandardError "$env:TEMP\zed_source_error.log" -ErrorAction SilentlyContinue
    Wait-ProcessWithSpinner -Process $pSrc -Message "winget 소스 업데이트 중"
    Remove-Item "$env:TEMP\zed_source_update.log", "$env:TEMP\zed_source_error.log" -Force -ErrorAction SilentlyContinue
} catch {}

# Zed 윈도우 에디터 설치 (다양한 패키지 ID 시도)
$zedInstalled = $false
try {
    # 1순위: 로컬 실행 파일 경로 및 Get-Command로 빠른 검사 (winget list 보다 빠르고 안 멈춤)
    $zedPaths = @(
        "$env:LOCALAPPDATA\Programs\Zed\Zed.exe",
        "$env:LOCALAPPDATA\Zed\bin\zed.exe",
        "$env:ProgramFiles\Zed\Zed.exe"
    )
    foreach ($p in $zedPaths) {
        if (Test-Path $p) { $zedInstalled = $true; break }
    }
    
    if (-not $zedInstalled -and (Get-Command zed -ErrorAction SilentlyContinue)) {
        $zedInstalled = $true
    }

    # 2순위: 로컬에 파일이 없으면 winget 리스트 확인
    if (-not $zedInstalled) {
        $wgList = winget list --id ZedIndustries.Zed 2>$null
        if ($LASTEXITCODE -eq 0 -and ($wgList -join "") -match "Zed") { $zedInstalled = $true }
    }
}
catch {}

if ($zedInstalled) {
    Write-Skip "Zed 에디터가 이미 설치되어 있습니다."
}
else {
    Write-Host "  Zed 에디터를 winget으로 설치합니다..." -ForegroundColor White
    $zedIds = @("ZedIndustries.Zed")
    $zedInstallSuccess = $false
    foreach ($zedId in $zedIds) {
        $p = Start-Process winget -ArgumentList "install --id $zedId --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\zed_install.log" -RedirectStandardError "$env:TEMP\zed_install_err.log"
        Wait-ProcessWithSpinner -Process $p -Message "Zed 에디터 설치 진행 중 ($zedId)"
        # -1978335189 = APPINSTALLER_CLI_ERROR_NO_APPLICABLE_UPGRADE (이미 최신 버전 설치됨)
        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq -1978335189) {
            Write-Success "Zed 에디터 설치/확인 완료 ($zedId)"
            $zedInstallSuccess = $true
            Remove-Item "$env:TEMP\zed_install.log", "$env:TEMP\zed_install_err.log" -Force -ErrorAction SilentlyContinue
            break
        }
        Remove-Item "$env:TEMP\zed_install.log", "$env:TEMP\zed_install_err.log" -Force -ErrorAction SilentlyContinue
    }
    if (-not $zedInstallSuccess) {
        Write-Warn "Zed winget 설치 실패. 수동 설치: https://zed.dev/download"
        Write-Warn "(Zed Windows 버전이 아직 Preview 상태일 수 있습니다)"
    }
}

# ==============================================================================
# [Step 3] Zed 설정 파일 복사
#
# WSL2 내의 settings.json 및 keymap.json 실물 파일을
# Windows용 Zed 설정 경로인 %APPDATA%\Zed\ 하위로 안전하게 복사해줍니다.
# ==============================================================================
Write-Step "[Step 3] Zed 설정 파일 복사"

$WslZedConfig = "$DevTools2Wsl\.config\zed"
$WinZedDir    = "$env:APPDATA\Zed"

Write-Host "  소스 (WSL2): $WslZedConfig" -ForegroundColor DarkGray
Write-Host "  대상 (Win) : $WinZedDir" -ForegroundColor DarkGray
Write-Host ""

# Zed 설정 폴더가 WSL2에 없으면 기본 폴더를 생성
if (-not (Test-Path $WslZedConfig)) {
    Write-Warn "WSL2에 Zed 설정 폴더가 없습니다. 기본 폴더를 생성합니다..."
    wsl -d $WslDistro -- bash -c "mkdir -p /var/opt/_devtools2/.config/zed"
}

# settings.json과 keymap.json이 없으면 기본 뼈대 파일 생성
if (-not (Test-Path "$WslZedConfig\settings.json")) {
    wsl -d $WslDistro -- bash -c "echo '{}' > /var/opt/_devtools2/.config/zed/settings.json"
}
if (-not (Test-Path "$WslZedConfig\keymap.json")) {
    wsl -d $WslDistro -- bash -c "echo '[]' > /var/opt/_devtools2/.config/zed/keymap.json"
}

# 기존에 설정된 심볼릭 링크나 디렉터리 링크가 있을 경우 완전히 제거하고 물리 폴더 생성
if (Test-Path $WinZedDir) {
    $item = Get-Item $WinZedDir -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq "SymbolicLink") {
        Write-Host "  기존 심볼릭 링크 폴더를 제거합니다..." -ForegroundColor Yellow
        Remove-Item $WinZedDir -Force -ErrorAction SilentlyContinue
        cmd.exe /c "rd /s /q `"$WinZedDir`"" 2>$null | Out-Null
    }
}
if (-not (Test-Path $WinZedDir)) {
    New-Item -ItemType Directory -Path $WinZedDir -Force | Out-Null
}

# settings.json 복사
if (Test-Path "$WslZedConfig\settings.json") {
    $targetFile = "$WinZedDir\settings.json"
    if (Test-Path $targetFile) {
        $fi = Get-Item $targetFile -Force
        if ($fi.LinkType -eq "SymbolicLink") { Remove-Item $targetFile -Force }
    }
    Copy-Item -Path "$WslZedConfig\settings.json" -Destination $targetFile -Force
    Write-Success "settings.json 파일 복사 완료"
}

# keymap.json 복사
if (Test-Path "$WslZedConfig\keymap.json") {
    $targetFile = "$WinZedDir\keymap.json"
    if (Test-Path $targetFile) {
        $fi = Get-Item $targetFile -Force
        if ($fi.LinkType -eq "SymbolicLink") { Remove-Item $targetFile -Force }
    }
    Copy-Item -Path "$WslZedConfig\keymap.json" -Destination $targetFile -Force
    Write-Success "keymap.json 파일 복사 완료"
}

# ==============================================================================
# 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 Zed 설정 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  복사된 설정 파일 목록:" -ForegroundColor White
Write-Host "    $WinZedDir\settings.json" -ForegroundColor DarkGray
Write-Host "    $WinZedDir\keymap.json" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Zed 를 재시작하면 설정이 적용됩니다." -ForegroundColor Yellow
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""


