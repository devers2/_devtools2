# ==============================================================================
# WezTerm 설치 및 WSL2 설정 폴더 심볼릭 링크 생성 스크립트 (1.setup-wezterm.ps1)
#
# 주요 기능:
#   1. PowerShell 7 (pwsh) 설치 여부 확인 및 winget 을 통한 자동 설치
#   2. winget 을 통해 WezTerm 을 자동 설치 (이미 설치되어 있으면 건너뜀)
#   3. WSL2 의 _devtools2/.config/wezterm/.wezterm.lua 설정을 Windows 홈 디렉토리로 심볼릭 링크 생성
#
# 사전 조건:
#   - WSL2 에 Ubuntu 계열 배포판이 설치되어 있어야 합니다.
#   - Windows 에서 관리자 권한이 필요합니다.
#   - winget 이 설치되어 있어야 합니다.
#
# 사용 방법:
#   PowerShell 을 관리자 권한으로 열고 실행:
#   .\1.setup-wezterm.ps1
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
                # 기존 파일/폴더를 .bak 으로 백업
                $backupPath = "$LinkPath.bak"
                Write-Host "  [백업] 기존 '$LinkPath' -> '$backupPath'" -ForegroundColor Yellow
                Move-Item -Path $LinkPath -Destination $backupPath -Force
            }
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

# 프로세스 종료 시까지 스피너를 표시해 대기하는 함수
function Wait-ProcessWithSpinner {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Message
    )

    $spinChars = @('|', '/', '-', '\')
    $spinIdx = 0
    Write-Host "  $Message " -NoNewline -ForegroundColor Cyan
    while (-not $Process.HasExited) {
        $char = $spinChars[$spinIdx]
        Write-Host -NoNewline "`b$char"
        $spinIdx = ($spinIdx + 1) % $spinChars.Count
        Start-Sleep -Milliseconds 200
    }
    # 백스페이스로 스피너 문자를 지우고 완료 출력
    Write-Host -NoNewline "`b`b => 완료!`n" -ForegroundColor Green
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
Write-Host "🚀 WezTerm 설치 및 설정 파일 심볼릭 링크 연동" -ForegroundColor Magenta
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

# winget 소스 업데이트 (최초 실행 시 동의 질문으로 인한 무한 대기 멈춤 방지)
try {
    Write-Host "  winget 패키지 매니저 소스를 확인하는 중..." -ForegroundColor White
    $pSrc = Start-Process winget -ArgumentList "source update --accept-source-agreements" -NoNewWindow -PassThru -ErrorAction SilentlyContinue
    Wait-ProcessWithSpinner -Process $pSrc -Message "winget 소스 업데이트 중"
} catch {}

$pwshInstalled = $false
# Get-Command에 -ErrorAction SilentlyContinue를 주더라도 $null 리턴값을 정확하게 검사해야 함
$pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($pwshCmd -ne $null) {
    $pwshInstalled = $true
}

if ($pwshInstalled) {
    Write-Skip "PowerShell 7 이 이미 시스템에 설치되어 있습니다."
}
else {
    Write-Info "PowerShell 7 이 감지되지 않았습니다. winget 으로 설치를 진행합니다..."
    $p = Start-Process winget -ArgumentList "install --id Microsoft.PowerShell --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -PassThru
    Wait-ProcessWithSpinner -Process $p -Message "PowerShell 7 패키지 설치 진행 중"
    if ($p.ExitCode -eq 0) {
        Write-Success "PowerShell 7 설치 완료"
    }
    else {
        Write-Fail "PowerShell 7 설치 실패 (종료 코드: $($p.ExitCode))"
        Write-Host "  수동 설치를 권장합니다: https://aka.ms/powershell-release" -ForegroundColor Yellow
    }
}

# ==============================================================================
# [Step 3] WezTerm 설치
# ==============================================================================
Write-Step "[Step 3] WezTerm 설치"

$weztermInstalled = $false
try {
    # 1순위: 실행 파일 경로 및 Get-Command로 로컬 검사 ( winget list 호출보다 무해하고 안 멈춤 )
    if (Get-Command wezterm -ErrorAction SilentlyContinue) {
        $weztermInstalled = $true
    }
    elseif (Test-Path "$env:ProgramFiles\WezTerm\wezterm.exe") {
        $weztermInstalled = $true
    }
    elseif (Test-Path "${env:ProgramFiles(x86)}\WezTerm\wezterm.exe") {
        $weztermInstalled = $true
    }
    
    # 2순위: 로컬에 파일이 없으면 winget 리스트 확인
    if (-not $weztermInstalled) {
        $wgList = winget list --id wez.wezterm 2>$null
        if ($LASTEXITCODE -eq 0 -and ($wgList -join "") -match "wezterm") {
            $weztermInstalled = $true
        }
    }
}
catch {}

if ($weztermInstalled) {
    Write-Skip "WezTerm 이 이미 설치되어 있습니다."
}
else {
    Write-Host "  WezTerm 을 winget 으로 설치합니다..." -ForegroundColor White
    $p = Start-Process winget -ArgumentList "install --id wez.wezterm --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -PassThru
    Wait-ProcessWithSpinner -Process $p -Message "WezTerm 패키지 설치 진행 중"
    # -1978335189 = APPINSTALLER_CLI_ERROR_NO_APPLICABLE_UPGRADE (이미 최신 버전 설치됨)
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq -1978335189) {
        Write-Success "WezTerm 설치/확인 완료"
    }
    else {
        Write-Fail "WezTerm 설치 실패 (종료 코드: $($p.ExitCode))"
        Write-Host "  수동 설치: https://wezfurlong.org/wezterm/install/windows.html" -ForegroundColor Yellow
    }
}

# ==============================================================================
# [Step 4] 필수 폰트 설치 (assets/fonts → Windows 사용자 폰트)
# WezTerm 은 Windows 네이티브 앱이므로 폰트를 Windows 에 직접 설치해야 합니다.
# ==============================================================================
Write-Step "[Step 4] 필수 폰트 설치"

$WslFontsDir  = "$DevTools2Wsl\assets\fonts"
$UserFontsDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$FontRegPath  = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

if (-not (Test-Path $WslFontsDir)) {
    Write-Warn "폰트 소스 경로를 찾을 수 없습니다: $WslFontsDir (건너뜀)"
} else {
    if (-not (Test-Path $UserFontsDir)) {
        New-Item -ItemType Directory -Path $UserFontsDir -Force | Out-Null
    }
    if (-not (Test-Path $FontRegPath)) {
        New-Item -Path $FontRegPath -Force | Out-Null
    }

    $fontFiles = Get-ChildItem -Path $WslFontsDir -Include "*.ttf", "*.ttc", "*.otf" -File -ErrorAction SilentlyContinue
    foreach ($fontFile in $fontFiles) {
        $destPath = "$UserFontsDir\$($fontFile.Name)"
        if (Test-Path $destPath) {
            Write-Skip "폰트 이미 설치됨: $($fontFile.Name)"
        } else {
            try {
                Copy-Item -Path $fontFile.FullName -Destination $destPath -Force
                $regName = [System.IO.Path]::GetFileNameWithoutExtension($fontFile.Name) + ' (TrueType)'
                Set-ItemProperty -Path $FontRegPath -Name $regName -Value $destPath -Force
                Write-Success "폰트 설치: $($fontFile.Name)"
            } catch {
                Write-Warn "폰트 설치 실패: $($fontFile.Name) - $_"
            }
        }
    }
}

# ==============================================================================
# [Step 5] WezTerm 설정 파일 심볼릭 링크 연동
# ==============================================================================
Write-Step "[Step 5] WezTerm 설정 파일 심볼릭 링크 연동"

$WslWeztermConfig = "$DevTools2Wsl\.config\wezterm\.wezterm.lua"
$WinWeztermConfig = "$env:USERPROFILE\.wezterm.lua"

# WezTerm 설정 파일 존재 여부 확인 및 보강
if (-not (Test-Path $WslWeztermConfig)) {
    Write-Warn "WSL2 내 설정 파일(.wezterm.lua)이 없습니다. 기본 파일 생성 중..."
    wsl -d $WslDistro -- bash -c "mkdir -p /var/opt/_devtools2/.config/wezterm && touch /var/opt/_devtools2/.config/wezterm/.wezterm.lua"
}

Write-Host "  공유 설정 (WSL2): $WslWeztermConfig" -ForegroundColor DarkGray
Write-Host "  Windows 설정   : $WinWeztermConfig" -ForegroundColor DarkGray
Write-Host ""

New-SafeSymlink -LinkPath $WinWeztermConfig -TargetPath $WslWeztermConfig -ItemType "SymbolicLink"

# ==============================================================================
# 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host "🎉 WezTerm 설정 연동 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  설정 파일 공유(심볼릭 링크)가 완료되었습니다." -ForegroundColor White
Write-Host "  이제 리눅스 혹은 윈도우 어느 쪽에서든 설정을 편집하면 양쪽 모두에 즉시 반영됩니다." -ForegroundColor White
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host ""
