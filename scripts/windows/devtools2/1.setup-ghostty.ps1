# ==============================================================================
# Ghostty (Winghostty) 설치 및 WSL2 설정 폴더 심볼릭 링크 생성 스크립트
#
# 주요 기능:
#   1. PowerShell 7 (pwsh) 설치 여부 확인 및 winget 을 통한 자동 설치
#   2. winget 을 통해 Winghostty 를 자동 설치 (이미 설치되어 있으면 건너뜀)
#   3. WSL2 의 _devtools2/.config/ghostty/config.ghostty 설정을 Windows 설정 경로로 심볼릭 링크 생성
#      - 공통 설정의 `command = "pwsh.exe"` 지시어를 그대로 심볼릭 링크로 공유합니다.
#      - (리눅스 환경에서는 scripts/linux/cmd/pwsh.exe 래퍼가 가로채어 bash 쉘을 띄워 오류를 예외 처리합니다.)
#
# 사전 조건:
#   - WSL2 에 Ubuntu 계열 배포판이 설치되어 있어야 합니다.
#   - Windows 에서 관리자 권한이 필요합니다.
#   - winget 이 설치되어 있어야 합니다.
#
# 사용 방법:
#   PowerShell 을 관리자 권한으로 열고 실행:
#   .\1.setup-ghostty.ps1
#   또는 WSL2 배포판 이름을 직접 지정:
#   .\1.setup-ghostty.ps1 -WslDistro "Ubuntu-24.04"
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

function Write-Info {
    param([string]$Message)
    Write-Host "[정보] $Message" -ForegroundColor White
}

# 심볼릭 링크를 안전하게 생성하는 함수
function New-SafeSymlink {
    param(
        [string]$LinkPath,   # 생성할 링크 경로 (Windows 측)
        [string]$TargetPath, # 링크가 가리킬 실제 경로 (WSL2 측)
        [string]$ItemType    # "Directory" 또는 "SymbolicLink"
    )

    if (Test-Path $LinkPath -PathType Any) {
        $item = Get-Item $LinkPath -Force
        if ($item.LinkType -eq "SymbolicLink") {
            $currentTarget = $item.Target
            if ($currentTarget -eq $TargetPath) {
                Write-Skip "'$(Split-Path $LinkPath -Leaf)' 심볼릭 링크가 이미 올바릅니다."
                return
            }
            else {
                # 대상 경로가 다르면 삭제 후 재생성
                Write-Host "  [재생성] 심볼릭 링크 대상이 다릅니다. 삭제 후 재생성합니다..." -ForegroundColor Yellow
                Write-Host "    기존: $currentTarget" -ForegroundColor DarkGray
                Write-Host "    신규: $TargetPath" -ForegroundColor DarkGray
                Remove-Item $LinkPath -Force
            }
        }
        else {
            # 기존 파일/폴더를 .bak 으로 백업
            $backupPath = "$LinkPath.bak"
            Write-Host "  [백업] 기존 '$LinkPath' -> '$backupPath'" -ForegroundColor Yellow
            Move-Item -Path $LinkPath -Destination $backupPath -Force
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
        Write-Success "심볼릭 링크 생성: '$LinkPath' -> '$TargetPath'"
    }
    catch {
        Write-Fail "심볼릭 링크 생성 실패: $($_.Exception.Message)"
    }
}

# ==============================================================================
# [Step 0] 관리자 권한 확인 및 재실행
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host "[경고] 설치 및 심볼릭 링크 생성을 위해 관리자 권한이 필요합니다." -ForegroundColor Yellow
    Write-Host "       관리자 권한으로 스크립트를 재실행합니다..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -WslDistro `"$WslDistro`"" -Verb RunAs
    exit
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host "🚀 Ghostty (Winghostty) 설치 및 설정 파일 심볼릭 링크 연동" -ForegroundColor Magenta
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
# [Step 2] PowerShell 7 (pwsh.exe) 설치 여부 확인 및 설치
# ==============================================================================
Write-Step "[Step 2] PowerShell 7 설치 확인"

$pwshInstalled = $false
try {
    $null = Get-Command pwsh -ErrorAction SilentlyContinue
    $pwshInstalled = $true
}
catch {}

if ($pwshInstalled) {
    Write-Skip "PowerShell 7 이 이미 시스템에 설치되어 있습니다."
}
else {
    Write-Info "PowerShell 7 이 감지되지 않았습니다. winget 으로 설치를 진행합니다..."
    winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-Success "PowerShell 7 설치 완료"
    }
    else {
        Write-Fail "PowerShell 7 설치 실패 (종료 코드: $LASTEXITCODE)"
        Write-Host "  수동 설치를 권장합니다: https://aka.ms/powershell-release" -ForegroundColor Yellow
    }
}

# ==============================================================================
# [Step 3] Ghostty (Winghostty) 설치
# ==============================================================================
Write-Step "[Step 3] Ghostty (Winghostty) 설치"

$ghosttyInstalled = $false
try {
    # winget list 로 설치 여부 우선 확인 (가장 정확)
    $wgList = winget list --id AmanThanvi.winghostty 2>$null
    if ($LASTEXITCODE -eq 0 -and ($wgList -join "") -match "winghostty") { $ghosttyInstalled = $true }
    # 실행 파일 경로로 추가 확인
    if (-not $ghosttyInstalled) {
        $ghosttyPaths = @(
            "$env:LOCALAPPDATA\Programs\winghostty\winghostty.exe",
            "$env:LOCALAPPDATA\Programs\ghostty\bin\ghostty.exe",
            "$env:ProgramFiles\Ghostty\bin\ghostty.exe",
            "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\AmanThanvi.winghostty_Microsoft.Winget.Source_8wekyb3d8bbwe\winghostty.exe"
        )
        foreach ($p in $ghosttyPaths) {
            if (Test-Path $p) { $ghosttyInstalled = $true; break }
        }
    }
}
catch {}

if ($ghosttyInstalled) {
    Write-Skip "Ghostty/Winghostty 가 이미 설치되어 있습니다."
}
else {
    Write-Host "  Winghostty 를 winget 으로 설치합니다..." -ForegroundColor White
    winget install --id AmanThanvi.winghostty --silent --accept-source-agreements --accept-package-agreements
    # -1978335189 = APPINSTALLER_CLI_ERROR_NO_APPLICABLE_UPGRADE (이미 최신 버전 설치됨)
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
        Write-Success "Winghostty 설치/확인 완료"
    }
    else {
        Write-Fail "Winghostty 설치 실패 (종료 코드: $LASTEXITCODE)"
        Write-Host "  수동 설치: https://winghostty.com" -ForegroundColor Yellow
    }
}

# ==============================================================================
# [Step 4] Ghostty 설정 파일 심볼릭 링크 연동
#
# 원본 config.ghostty 내에 command = "pwsh.exe" 가 등록되어 있습니다.
# 이 파일을 그대로 윈도우 측에 심볼릭 링크하여 100% 동일하게 공유합니다.
# ==============================================================================
Write-Step "[Step 4] Ghostty 설정 파일 심볼릭 링크 연동"

$WslGhosttyConfig = "$DevTools2Wsl\.config\ghostty"
$WinLocalAppData  = $env:LOCALAPPDATA

# Winghostty 설정 폴더 링크
$WinGhosttyDir = "$WinLocalAppData\winghostty"
if (-not (Test-Path $WinGhosttyDir)) {
    New-Item -ItemType Directory -Path $WinGhosttyDir -Force | Out-Null
}

Write-Host "  공유 설정 (WSL2): $WslGhosttyConfig" -ForegroundColor DarkGray
Write-Host "  Windows 설정   : $WinGhosttyDir\config.ghostty" -ForegroundColor DarkGray
Write-Host ""

# Windows 전용 config.ghostty 생성
# ─ 이유: 공유 config 의 command = "pwsh.exe" 는 Linux 전용 래퍼를 거치며,
#         Windows(winghostty) 에서는 wsl.exe 로 WSL 배포판을 직접 실행해야 합니다.
# ─ 공유 설정(폰트/테마 등)은 config-file 로 포함하되,
#   마지막에 Windows 전용 command 를 덮어씁니다.
$ghosttyConfigPathForGhostty = "$WslGhosttyConfig\config.ghostty" -replace '\\', '/'
$winConfigContent = @"
# ====================================================
# Windows (Winghostty) 전용 설정
# 이 파일은 자동 생성됩니다. 직접 편집하지 마세요.
# 공유 설정은 WSL2 내 .config/ghostty/config.ghostty 를 편집하세요.
# ====================================================

# 공유 설정 포함 (폰트/테마/단축키 등)
config-file = "$ghosttyConfigPathForGhostty"

# Windows 전용 덮어쓰기: WSL2 $WslDistro 배포판을 기본 셸로 사용
command = wsl.exe -d $WslDistro
"@

# 기존 파일이 심볼릭 링크라면 삭제 후 실제 파일로 교체
if (Test-Path "$WinGhosttyDir\config.ghostty") {
    $existingItem = Get-Item "$WinGhosttyDir\config.ghostty" -Force
    if ($existingItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Write-Host "  기존 심볼릭 링크 제거 후 실제 파일로 교체합니다..." -ForegroundColor DarkGray
        Remove-Item "$WinGhosttyDir\config.ghostty" -Force
    }
}

Set-Content -Path "$WinGhosttyDir\config.ghostty" -Value $winConfigContent -Encoding UTF8 -Force
Write-Success "Windows 전용 config.ghostty 생성 완료"

# 혹시 InsipidPoint/ghostty-windows 빌드도 사용 중일 경우 대비
$WinGhosttyAltDir = "$WinLocalAppData\ghostty"
if (Test-Path $WinGhosttyAltDir) {
    Write-Host ""
    Write-Host "  [추가] InsipidPoint/ghostty-windows 빌드 경로도 감지됨. 추가 링크 생성..." -ForegroundColor DarkGray
    New-SafeSymlink -LinkPath "$WinGhosttyAltDir\config" `
                    -TargetPath "$WslGhosttyConfig\config.ghostty" `
                    -ItemType "SymbolicLink"
}

# ==============================================================================
# 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host "🎉 Ghostty 설정 연동 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  설정 파일 공유(심볼릭 링크)가 완료되었습니다." -ForegroundColor White
Write-Host "  이제 리눅스 혹은 윈도우 어느 쪽에서든 설정을 편집하면 양쪽 모두에 즉시 반영됩니다." -ForegroundColor White
Write-Host ""
Write-Host "  - Windows : PowerShell 7 (pwsh.exe)로 기본 구동됩니다." -ForegroundColor White
Write-Host "  - Linux   : scripts/linux/cmd/pwsh.exe 가 가로채어 bash 쉘을 오류 없이 띄웁니다." -ForegroundColor White
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host ""

