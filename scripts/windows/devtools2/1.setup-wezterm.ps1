# ==============================================================================
# WezTerm 설치 및 WSL2 설정 폴더 심볼릭 링크 생성 스크립트 (1.setup-wezterm.ps1)
#
# 주요 기능:
#   1. winget 또는 GitHub 최신 릴리즈를 통해 WezTerm 자동/재설치 (이미 설치 시 다시 설치 여부 확인)
#   2. WSL2 의 _devtools2/.config/wezterm/.wezterm.lua 설정을 Windows 홈 디렉토리로 심볼릭 링크 생성
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
            # UNC\ 로 시작하는 경로를 \\ 형식으로 정규화하여 대조
            $normalizedCurrent = $currentTarget
            if ($normalizedCurrent -like "UNC\*") {
                $normalizedCurrent = "\\" + $normalizedCurrent.Substring(4)
            }
            $normalizedTarget = $TargetPath
            if ($normalizedTarget -like "UNC\*") {
                $normalizedTarget = "\\" + $normalizedTarget.Substring(4)
            }

            if ($normalizedCurrent.Replace("/", "\").TrimEnd("\") -eq $normalizedTarget.Replace("/", "\").TrimEnd("\")) {
                Write-Skip "'$(Split-Path $LinkPath -Leaf)' 심볼릭 링크가 이미 올바릅니다."
                return
            }
            else {
                # 기존 파일/폴더를 .bak 으로 백업
                $backupPath = "$LinkPath.bak"
                Write-Host "  [백업] 기존 '$LinkPath' -> '$backupPath' (대상 불일치: '$normalizedCurrent' != '$normalizedTarget')" -ForegroundColor Yellow
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
    Write-Host "[경고] 설치 및 심볼릭 링크 생성을 위해 관리자 권한이 필요합니다." -ForegroundColor Yellow
    Write-Host "       관리자 권한으로 스크립트를 재실행합니다..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -WslDistro `"$WslDistro`"" -Verb RunAs
    exit
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🚀 WezTerm 설치 및 설정 파일 심볼릭 링크 연동" -ForegroundColor DarkCyan
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
# [Step 2] WezTerm 설치
# ==============================================================================
Write-Step "[Step 2] WezTerm 설치"

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

$doInstall = -not $weztermInstalled

if ($weztermInstalled) {
    Write-Host ""
    Write-Host "👉 다시 설치하시겠습니까? (y/N, 기본값: N): " -ForegroundColor Yellow -NoNewline
    $reinstallChoice = Read-Host
    if ($reinstallChoice -match '^[Yy]') {
        Write-Host "  → 기존 WezTerm 재설치를 진행합니다..." -ForegroundColor White
        $doInstall = $true
    }
    else {
        Write-Skip "기존 WezTerm 설치를 유지합니다."
        $doInstall = $false
    }
}

if ($doInstall) {
    # 나이틀리 / 안정화 버전 선택
    Write-Host ""
    Write-Host "  WezTerm 버전을 선택하세요:" -ForegroundColor Cyan
    Write-Host "    [Y] Nightly  - 최신 기능 포함 나이틀리 버전 (권장, 기본값)" -ForegroundColor Green
    Write-Host "    [N] Stable   - 안정화 버전 (2024년 2월 최종 업데이트)" -ForegroundColor Gray
    Write-Host "👉 나이틀리 버전으로 설치할까요? (Y/n, 기본값: Y): " -ForegroundColor Yellow -NoNewline
    $versionChoice = Read-Host

    if ($versionChoice -match '^[Nn]') {
        # ── 안정화: winget 으로 설치 ──────────────────────────────────────────
        $weztermVersionLabel = "안정화(Stable)"
        Write-Host "  WezTerm $weztermVersionLabel 버전을 winget 으로 설치합니다..." -ForegroundColor White
        $p = Start-Process winget -ArgumentList "install --id wez.wezterm --silent --accept-source-agreements --accept-package-agreements" -WindowStyle Hidden -PassThru
        Wait-ProcessWithSpinner -Process $p -Message "WezTerm $weztermVersionLabel 패키지 설치 진행 중"
        $weztermSuccessCodes = @(0, 3010, -1978335189, -1978335212)
        if ($weztermSuccessCodes -contains $p.ExitCode) {
            Write-Success "WezTerm $weztermVersionLabel 설치/확인 완료 (종료 코드: $($p.ExitCode))"
        }
        else {
            $weztermNow = (Get-Command wezterm -ErrorAction SilentlyContinue) -or `
                          (Test-Path "$env:ProgramFiles\WezTerm\wezterm.exe") -or `
                          (Test-Path "${env:ProgramFiles(x86)}\WezTerm\wezterm.exe")
            if ($weztermNow) {
                Write-Success "WezTerm $weztermVersionLabel 설치 확인 완료 (종료 코드 $($p.ExitCode) 이지만 실제 설치됨)"
            }
            else {
                Write-Fail "WezTerm $weztermVersionLabel 설치 실패 (종료 코드: $($p.ExitCode))"
                Write-Host "  수동 설치: https://wezfurlong.org/wezterm/install/windows.html" -ForegroundColor Yellow
            }
        }
    }
    else {
        # ── WezTerm Nightly 설치 ─────────────────────────────────────────────
        # winget 에는 wez.wezterm.nightly 패키지가 없으므로 GitHub 직접 설치 방식 사용
        $weztermVersionLabel = "Nightly"
        $nightlyUrl = "https://github.com/wez/wezterm/releases/download/nightly/WezTerm-nightly-setup.exe"
        $nightlyInstaller = Join-Path $env:TEMP "WezTerm-nightly-setup.exe"

        Write-Host "  WezTerm $weztermVersionLabel 인스톨러를 GitHub에서 다운로드 중..." -ForegroundColor White

        try {
            $prevProgress = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'

            Invoke-WebRequest -Uri $nightlyUrl -OutFile $nightlyInstaller -ErrorAction Stop
            $ProgressPreference = $prevProgress

            Write-Host "  WezTerm $weztermVersionLabel 설치 중..." -ForegroundColor White

            # Inno Setup 무인 설치 인수 (/VERYSILENT 와 /SUPPRESSMSGBOXES 조합 필수)
            $installArgs = "/VERYSILENT", "/NORESTART", "/SUPPRESSMSGBOXES"

            # 관리자 권한 여부에 따라 실행 방식 분기
            # - 관리자: 현재 컨텍스트로 직접 실행 (-PassThru -Wait 로 ExitCode 추적 가능)
            # - 비관리자: -Verb RunAs 로 권한 상승 후 실행 (ExitCode 추적 불가 → $weztermExists 로 판정)
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

            if ($isAdmin) {
                $p = Start-Process -FilePath $nightlyInstaller -ArgumentList $installArgs -PassThru -Wait -ErrorAction Stop
                Remove-Item $nightlyInstaller -Force -ErrorAction SilentlyContinue
                $installExitCode = $p.ExitCode
            }
            else {
                Write-Warn "  관리자 권한이 없습니다. UAC 창이 표시되면 허용해 주세요..."
                $p = Start-Process -FilePath $nightlyInstaller -ArgumentList $installArgs -Verb RunAs -PassThru -Wait -ErrorAction Stop
                Remove-Item $nightlyInstaller -Force -ErrorAction SilentlyContinue
                # RunAs 프로세스는 ExitCode 추적 불가 → 파일 존재 여부로만 판정
                $installExitCode = $null
            }

            # 설치 성공 확인 (ExitCode 0 또는 실제 파일 존재 여부)
            $weztermExists = (Get-Command wezterm -ErrorAction SilentlyContinue) -or
                             (Test-Path "$env:ProgramFiles\WezTerm\wezterm.exe") -or
                             (Test-Path "${env:ProgramFiles(x86)}\WezTerm\wezterm.exe")

            if ($weztermExists -or $installExitCode -eq 0) {
                Write-Success "WezTerm Nightly 설치 완료"
            }
            else {
                Write-Fail "WezTerm Nightly 설치 실패 (ExitCode: $installExitCode)"
                Write-Host "  → 수동 설치: https://github.com/wez/wezterm/releases/tag/nightly" -ForegroundColor Yellow
            }
        }
        catch {
            $ProgressPreference = $prevProgress
            Remove-Item $nightlyInstaller -Force -ErrorAction SilentlyContinue
            Write-Fail "WezTerm Nightly 다운로드 또는 설치 실패: $($_.Exception.Message)"
            Write-Host "  → 수동 설치 링크: https://github.com/wez/wezterm/releases/tag/nightly" -ForegroundColor Yellow
        }
    }
}

# ==============================================================================
# [Step 3] 필수 폰트 설치 (assets/fonts → Windows 사용자 폰트)
# WezTerm 은 Windows 네이티브 앱이므로 폰트를 Windows 에 직접 설치해야 합니다.
# ==============================================================================
Write-Step "[Step 3] 필수 폰트 설치"

$WslFontsDir = "$DevTools2Wsl\assets\fonts"
$UserFontsDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$FontRegPath  = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

if (-not (Test-Path $UserFontsDir)) {
    New-Item -ItemType Directory -Path $UserFontsDir -Force | Out-Null
}
if (-not (Test-Path $FontRegPath)) {
    New-Item -Path $FontRegPath -Force | Out-Null
}

$fontNames = @(
    "D2Coding-Ver1.3.2-20180524-ligature.ttc",
    "JetBrainsMonoNerdFontMono-Regular.ttf",
    "JetBrainsMonoNerdFontMono-Bold.ttf",
    "JetBrainsMonoNerdFontMono-Italic.ttf",
    "JetBrainsMonoNerdFontMono-BoldItalic.ttf"
)

# 1) WSL 명령어로 폰트 존재 여부를 직접 확인 (UNC 경로는 WSL 심볼릭 링크를 못 따라가므로)
$wslFontCount = 0
try {
    $wslFontCount = [int](wsl -d $WslDistro -- bash -c "ls /var/opt/_devtools2/assets/fonts/*.ttf /var/opt/_devtools2/assets/fonts/*.ttc 2>/dev/null | wc -l")
} catch {}

$hasWslFonts = ($wslFontCount -gt 0)

if ($hasWslFonts) {
    Write-Host "  WSL2 내부 경로에서 폰트 파일을 찾았습니다. ($wslFontCount 개)" -ForegroundColor White

    # WSL에서 Windows 임시 폴더로 폰트 복사
    $tempFontDir = Join-Path $env:TEMP "devtools2_wsl_fonts"
    if (-not (Test-Path $tempFontDir)) {
        New-Item -ItemType Directory -Path $tempFontDir -Force | Out-Null
    }

    foreach ($fontName in $fontNames) {
        $destPath = "$UserFontsDir\$fontName"
        if (Test-Path $destPath) {
            Write-Skip "폰트 이미 설치됨: $fontName"
        } else {
            $wslFontPath = "/var/opt/_devtools2/assets/fonts/$fontName"
            # Windows 경로를 WSL 경로로 변환하여 cp 명령 실행
            $winTempPath = $tempFontDir.Replace("\", "/").Replace("C:", "/mnt/c").Replace("c:", "/mnt/c")
            wsl -d $WslDistro -- bash -c "[ -f '$wslFontPath' ] && cp '$wslFontPath' '$winTempPath/$fontName'" 2>$null

            $copiedFile = Join-Path $tempFontDir $fontName
            if (Test-Path $copiedFile) {
                try {
                    Copy-Item -Path $copiedFile -Destination $destPath -Force
                    $regName = [System.IO.Path]::GetFileNameWithoutExtension($fontName) + ' (TrueType)'
                    Set-ItemProperty -Path $FontRegPath -Name $regName -Value $destPath -Force
                    Write-Success "폰트 설치: $fontName"
                } catch {
                    Write-Host "  [경고] 폰트 설치 실패: $fontName - $_" -ForegroundColor Yellow
                }
            }
        }
    }

    if (Test-Path $tempFontDir) {
        Remove-Item -Path $tempFontDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 2) WSL2에도 없으면 GitHub 원격에서 다운로드
if (-not $hasWslFonts) {
    Write-Host "  WSL2 내부에 폰트가 없습니다. GitHub 원격 저장소에서 직접 다운로드합니다..." -ForegroundColor Yellow

    $tempDownloadDir = Join-Path $env:TEMP "devtools2_fonts_tmp"
    if (-not (Test-Path $tempDownloadDir)) {
        New-Item -ItemType Directory -Path $tempDownloadDir -Force | Out-Null
    }

    $gitHubFontBaseUrl = "https://raw.githubusercontent.com/devers2/_devtools2/main/assets/fonts"

    foreach ($fontName in $fontNames) {
        $destPath = "$UserFontsDir\$fontName"
        if (Test-Path $destPath) {
            Write-Skip "폰트 이미 설치됨: $fontName"
        } else {
            $tempFile = Join-Path $tempDownloadDir $fontName
            $url = "$gitHubFontBaseUrl/$fontName"
            try {
                Write-Host "  다운로드 중: $fontName..." -ForegroundColor White
                Invoke-RestMethod -Uri $url -OutFile $tempFile -ErrorAction Stop
                Copy-Item -Path $tempFile -Destination $destPath -Force
                $regName = [System.IO.Path]::GetFileNameWithoutExtension($fontName) + ' (TrueType)'
                Set-ItemProperty -Path $FontRegPath -Name $regName -Value $destPath -Force
                Write-Success "원격 다운로드 및 폰트 설치 완료: $fontName"
            } catch {
                Write-Host "  [경고] 원격 폰트 다운로드/설치 실패: $fontName - $_" -ForegroundColor Yellow
            }
        }
    }

    if (Test-Path $tempDownloadDir) {
        Remove-Item -Path $tempDownloadDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ==============================================================================
# [Step 4] WezTerm 설정 파일 심볼릭 링크 연동
# ==============================================================================
Write-Step "[Step 4] WezTerm 설정 파일 심볼릭 링크 연동"

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

# 기존 파일, 심볼릭 링크, 깨진 링크(dangling symlink) 포함하여 확실히 삭제 후 mklink 생성
if (Get-Item -Path $WinWeztermConfig -Force -ErrorAction SilentlyContinue) {
    Remove-Item -Path $WinWeztermConfig -Force -ErrorAction SilentlyContinue
}
cmd.exe /c "del /f /q /a `"$WinWeztermConfig`"" 2>$null | Out-Null

$mklinkResult = cmd.exe /c "mklink `"$WinWeztermConfig`" `"$WslWeztermConfig`"" 2>&1
if (Get-Item -Path $WinWeztermConfig -Force -ErrorAction SilentlyContinue) {
    Write-Success "WezTerm 심볼릭 링크 연동 완료: '$WinWeztermConfig' -> '$WslWeztermConfig'"
} else {
    Write-Fail "WezTerm 심볼릭 링크 생성 실패: $mklinkResult"
}


# ==============================================================================
# [Step 5] AutoHotkey v2 포터블 배포 및 WezTerm Ctrl+Alt+T 단축키 등록
# winget 설치 없이 AutoHotkey v2 포터블 zip 을 %LOCALAPPDATA%\_devtools2\modules\autohotkey 에 설치하고
# Windows 사용자 환경 변수(PATH) 등록 및 시작 프로그램(Startup) 폴더에 자동 실행을 연동합니다.
# ==============================================================================
Write-Step "[Step 5] AutoHotkey v2 포터블 배포 및 Ctrl+Alt+T 단축키 등록"

# ── (1) modules/autohotkey 포터블 설치 경로 결정 ─────────────────────────────
$ahkModuleDir = "$env:LOCALAPPDATA\_devtools2\modules\autohotkey"
$ahkExe = Join-Path $ahkModuleDir "AutoHotkey64.exe"
if (-not (Test-Path $ahkExe)) {
    $ahkExe = Join-Path $ahkModuleDir "AutoHotkey.exe"
}

# ── (2) 포터블 AutoHotkey v2 다운로드 및 압축 해제 ───────────────────────────
if (Test-Path $ahkExe) {
    Write-Info "AutoHotkey v2 포터블 이미 존재: $ahkExe"
} else {
    Write-Info "AutoHotkey v2 포터블을 다운로드합니다..."
    Write-Info "  설치 경로: $ahkModuleDir"

    New-Item -ItemType Directory -Path $ahkModuleDir -Force | Out-Null

    $ahkZipUrl  = "https://www.autohotkey.com/download/ahk-v2.zip"
    $ahkZipTemp = Join-Path $env:TEMP "ahk-v2.zip"

    try {
        $prevProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $ahkZipUrl -OutFile $ahkZipTemp -ErrorAction Stop
        $ProgressPreference = $prevProgress

        Write-Info "  압축 해제 중..."
        Expand-Archive -Path $ahkZipTemp -DestinationPath $ahkModuleDir -Force
        Remove-Item $ahkZipTemp -Force -ErrorAction SilentlyContinue

        $ahkExe = Join-Path $ahkModuleDir "AutoHotkey64.exe"
        if (-not (Test-Path $ahkExe)) {
            $ahkExe = Join-Path $ahkModuleDir "AutoHotkey.exe"
        }

        if (Test-Path $ahkExe) {
            Write-Success "AutoHotkey v2 포터블 배포 완료: $ahkExe"
        } else {
            Write-Warn "압축 해제 후 AutoHotkey 실행 파일을 찾지 못했습니다: $ahkModuleDir"
        }
    } catch {
        $ProgressPreference = $prevProgress
        Remove-Item $ahkZipTemp -Force -ErrorAction SilentlyContinue
        Write-Warn "AutoHotkey v2 포터블 다운로드 실패: $($_.Exception.Message)"
    }
}

# ── (3) 사용자 PATH 환경변수에 AutoHotkey 디렉터리 추가 ──────────────────────
if (Test-Path $ahkModuleDir) {
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -notlike "*$ahkModuleDir*") {
        $newUserPath = "$userPath;$ahkModuleDir".Trim(';')
        [Environment]::SetEnvironmentVariable("PATH", $newUserPath, "User")
        $env:PATH = "$env:PATH;$ahkModuleDir"
        Write-Success "사용자 PATH 환경 변수에 AutoHotkey 경로 추가 완료: $ahkModuleDir"
    } else {
        Write-Info "사용자 PATH 환경 변수에 AutoHotkey 경로가 이미 존재합니다."
    }
}

# ── (4) AHK 스크립트 복사 및 부팅 자동 실행 연동 ─────────────────────────────
$startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$ahkDest    = "$startupDir\wezterm-hotkey.ahk"

# 소스 AHK 파일 가져오기
$ahkSourceLocal = $null
if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
    $ahkSourceLocal = Join-Path (Split-Path $PSScriptRoot -Parent) "autohotkey\wezterm-hotkey.ahk"
}

if ($ahkSourceLocal -and (Test-Path $ahkSourceLocal)) {
    Write-Info "AHK 스크립트 복사(덮어쓰기) 중: $ahkSourceLocal"
    Copy-Item -Path $ahkSourceLocal -Destination $ahkDest -Force
} else {
    Write-Info "GitHub 에서 AHK 스크립트 다운로드 중..."
    try {
        $ahkRaw = "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/autohotkey/wezterm-hotkey.ahk"
        Invoke-WebRequest -Uri $ahkRaw -OutFile $ahkDest -ErrorAction Stop
    } catch {
        Write-Warn "AHK 스크립트 다운로드 실패: $($_.Exception.Message)"
    }
}

# 포터블 AutoHotkey 부팅 자동 실행용 바로가기(.lnk) 생성
if (Test-Path $ahkExe) {
    $shortcutPath = "$startupDir\WezTerm-Hotkey-Launcher.lnk"
    try {
        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath       = $ahkExe
        $shortcut.Arguments        = "`"$ahkDest`""
        $shortcut.WorkingDirectory = $ahkModuleDir
        $shortcut.WindowStyle      = 7  # 7 = Minimized / Background
        $shortcut.Description      = "WezTerm Ctrl+Alt+T Hotkey Launcher"
        $shortcut.Save()
    } catch {}
}

# ── (5) 기존 프로세스 종료 후 즉시 재실행 ──────────────────────────────────
if (Test-Path $ahkDest) {
    Write-Success "AHK 스크립트 배포 완료: $ahkDest"

    # 기존 인스턴스 강제 종료
    Get-Process -Name "AutoHotkey*" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

    # 포터블 exe 로 백그라운드 구동
    if ($ahkExe -and (Test-Path $ahkExe)) {
        Start-Process -FilePath $ahkExe -ArgumentList "`"$ahkDest`"" -WindowStyle Hidden
        Write-Success "Ctrl+Alt+T 단축키가 즉시 활성화되었습니다 (포터블 AutoHotkey)."
    }
} else {
    Write-Warn "AHK 스크립트 배포에 실패했습니다."
}

# ==============================================================================
# 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 WezTerm 설정 연동 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  설정 파일 공유(심볼릭 링크)가 완료되었습니다." -ForegroundColor White
Write-Host "  이제 리눅스 혹은 윈도우 어느 쪽에서든 설정을 편집하면 양쪽 모두에 즉시 반영됩니다." -ForegroundColor White
Write-Host "  Ctrl+Alt+T 단축키로 WezTerm 새 창을 빠르게 열 수 있습니다. (AutoHotkey)" -ForegroundColor White
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
