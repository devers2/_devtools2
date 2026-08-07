param(
    # WSL2 배포판 이름 (기본값: 첫 번째로 찾은 기본 배포판 자동 감지)
    [string]$WslDistro = ""
)

# ==============================================================================
# WezTerm 설치 및 WSL2 설정 폴더 심볼릭 링크 생성 스크립트 (1.setup-wezterm.ps1)
#
# 주요 기능:
#   1. winget 또는 GitHub 최신 릴리즈를 통해 WezTerm 자동/재설치 (이미 설치 시 다시 설치 여부 확인)
#   2. WSL2 의 _devtools2/.config/wezterm/.wezterm.lua 설정을 Windows 홈 디렉토리로 심볼릭 링크 생성
#
# ------------------------------------------------------------------------------
# ⚠️ [AI / 개발자 필독 - 설계 절대 원칙]
# 1. 100% 온라인 전용: 스크립트는 항상 GitHub main 브랜치 최신 원격 raw URL에서 호출됩니다.
# 2. 순수 UTF-8 NoBOM 보장: BOM(Byte Order Mark) 헤더를 절대 삽입하거나 조작하지 마십시오.
# 3. PS5.1 & PS7 무구분 호환: param() 구문은 반드시 스크립트 맨 첫 줄(Line 1)에 위치해야 합니다.
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

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "---------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor Cyan
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

function Write-Warn {
    param([string]$Message)
    Write-Host "[경고] $Message" -ForegroundColor Yellow
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

# 조건 만족 시까지 스피너를 표시해 대기하는 일반 함수
function Wait-WithSpinner {
    param(
        [string]$Message,
        [scriptblock]$Condition,
        [int]$MaxTimeoutSeconds = 300
    )
    $spinner = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $spinIdx = 0
    $startTime = Get-Date
    while ($true) {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -gt $MaxTimeoutSeconds) {
            Write-Host "`r  [시간 초과] $Message (제한 시간 초과)   " -ForegroundColor Red
            return $false
        }
        $done = & $Condition
        if ($done) {
            Write-Host "`r  [완료] $Message 완료!   " -ForegroundColor Green
            return $true
        }
        $char = $spinner[$spinIdx % $spinner.Count]
        Write-Host -NoNewline "`r  [$char] $Message...   " -ForegroundColor Cyan
        Start-Sleep -Milliseconds 150
        $spinIdx++
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
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/1.setup-wezterm.ps1 | iex`"" -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -WslDistro `"$WslDistro`"" -Verb RunAs
    }
    return
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
    # 1순위: %USERPROFILE%\.devtools2 디렉터리 내 wsl_distro 또는 단일 .devtools2 파일에서 읽기
    $devtools2Dir  = Join-Path $env:USERPROFILE ".devtools2"
    $devtools2File = if (Test-Path $devtools2Dir -PathType Container) { Join-Path $devtools2Dir "wsl_distro" } else { $devtools2Dir }
    if (Test-Path $devtools2File) {
        $saved = Get-Content $devtools2File | Where-Object { $_ -match "^WSL_DISTRO=" } | Select-Object -First 1
        if ($saved) {
            $WslDistro = ($saved -split "=", 2)[1].Trim()
            Write-Host "  .devtools2 에서 읽은 배포판: $WslDistro" -ForegroundColor White
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
# _devtools2 경로를 참조합니다: %DEVTOOLS2% 환경 변수 또는 /var/opt/_devtools2
$DevTools2Wsl = if ($env:DEVTOOLS2 -and (Test-Path $env:DEVTOOLS2)) { $env:DEVTOOLS2 } else { "$WslRoot\var\opt\_devtools2" }

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
    Write-Host "👉 다시 설치하시겠습니까? [y/" -ForegroundColor Yellow -NoNewline
    Write-Host "N" -ForegroundColor Green -NoNewline
    Write-Host "]: " -ForegroundColor Yellow -NoNewline
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
    Write-Host "👉 나이틀리 버전으로 설치할까요? [" -ForegroundColor Yellow -NoNewline
    Write-Host "Y" -ForegroundColor Green -NoNewline
    Write-Host "/n]: " -ForegroundColor Yellow -NoNewline
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
# [Step 2-1] 스마트 앱 컨트롤(SAC), MOTW(Unblock-File) 및 Defender 예외 설정
# ==============================================================================
Write-SubStep "▶ WezTerm 실행 파일 차단 해제(Unblock-File) 및 스마트 앱 컨트롤/보안 예외 설정"

# 1) Windows 11 스마트 앱 컨트롤(Smart App Control, SAC) 레지스트리 비활성화 처리
$sacRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
if (Test-Path $sacRegPath) {
    $sacVal = (Get-ItemProperty -Path $sacRegPath -Name "VerifiedAndReputablePolicyState" -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
    if ($sacVal -eq 1 -or $sacVal -eq 2) {
        Write-Warn "Windows 11 스마트 앱 컨트롤(Smart App Control)이 활성화되어 있어 개발도구(WezTerm) 차단이 발생할 수 있습니다. (현재 상태: $sacVal)"
        Write-Info "스마트 앱 컨트롤을 비활성화(Off, VerifiedAndReputablePolicyState = 0)로 자동 설정합니다..."
        try {
            Set-ItemProperty -Path $sacRegPath -Name "VerifiedAndReputablePolicyState" -Value 0 -Force -ErrorAction SilentlyContinue
            $ciTool = "$env:windir\System32\CiTool.exe"
            if (Test-Path $ciTool) {
                Start-Process -FilePath $ciTool -ArgumentList "-r" -NoNewWindow -ErrorAction SilentlyContinue
            }
            Write-Success "스마트 앱 컨트롤 비활성화 설정 완료 (VerifiedAndReputablePolicyState = 0)"
        } catch {
            Write-Warn "스마트 앱 컨트롤 레지스트리 자동 변경 실패: $($_.Exception.Message)"
            Write-Info "수동 해제 방법: Windows 설정 > 보안 > 앱 및 브라우저 컨트롤 > 스마트 앱 컨트롤 > [끄기]"
        }
    } else {
        Write-Info "스마트 앱 컨트롤(Smart App Control) 비활성화 상태 확인 완료 (현재 상태: $sacVal)"
    }
}

# 2) WezTerm 설치 폴더 내 모든 파일 및 실행 파일 MOTW(Mark of the Web) 차단 해제
$wezDirs = @("$env:ProgramFiles\WezTerm", "${env:ProgramFiles(x86)}\WezTerm")
foreach ($dir in $wezDirs) {
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Recurse -Force -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
        @("wezterm-gui.exe", "wezterm.exe", "wezterm-mux-server.exe", "open-wezterm-here.exe") | ForEach-Object {
            $exePath = Join-Path $dir $_
            if (Test-Path $exePath) {
                Unblock-File -Path $exePath -ErrorAction SilentlyContinue
            }
        }
        Write-Success "WezTerm 파일 및 실행 파일 차단 해제(Unblock-File) 완료: $dir"
    }
}

# 3) Windows Defender 보안 예외(Exclusion) 등록
try {
    foreach ($dir in $wezDirs) {
        if (Test-Path $dir) {
            Add-MpPreference -ExclusionPath $dir -ErrorAction SilentlyContinue
        }
    }
    Add-MpPreference -ExclusionProcess "wezterm-gui.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "wezterm.exe" -ErrorAction SilentlyContinue
    Write-Success "Windows Defender 보안 예외(Exclusion) 등록 완료 (WezTerm 경로 및 프로세스)"
} catch {
    Write-Warn "Windows Defender 예외 등록 중 경고 (권한 부족 또는 Defender 비활성화 상태일 수 있음)"
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

# 1) WSL2 내부 폰트 존재 여부 확인 (UNC 경로 및 bash 명령어 이중 확인)
$wslFontCount = 0
$wslFontDir = "$DevTools2Wsl\assets\fonts"
if (Test-Path $wslFontDir) {
    $wslFontCount = (Get-ChildItem -Path $wslFontDir -File 2>$null | Where-Object { $_.Extension -in '.ttf','.ttc' }).Count
}
if ($wslFontCount -eq 0) {
    try {
        $wslFontCount = [int](wsl -d $WslDistro -- bash -c 'ls "$DEVTOOLS2/assets/fonts/"*.ttf "$DEVTOOLS2/assets/fonts/"*.ttc 2>/dev/null | wc -l')
    } catch {}
}

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
            # WSL2 UNC 경로에서 윈도우 임시 폴더로 폰트 직접 복사
            $wslFontFile = "$DevTools2Wsl\assets\fonts\$fontName"
            if (Test-Path $wslFontFile) {
                Copy-Item -Path $wslFontFile -Destination $tempFontDir -Force 2>$null
            }

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
    wsl -d $WslDistro -- bash -c 'mkdir -p $DEVTOOLS2/.config/wezterm && touch $DEVTOOLS2/.config/wezterm/.wezterm.lua'
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
    Write-Success "WezTerm 심볼릭 링크 연동 완료:`n    $WinWeztermConfig -> $WslWeztermConfig"
} else {
    Write-Fail "WezTerm 심볼릭 링크 생성 실패: $mklinkResult"
}


# ==============================================================================
# [Step 5] AutoHotkey v2 포터블 배포 및 WezTerm Ctrl+Alt+T 단축키 등록
# winget 설치 없이 AutoHotkey v2 포터블 zip 을 %LOCALAPPDATA%\_devtools2\modules\autohotkey 에 설치하고
# Windows 사용자 환경 변수(PATH) 등록 및 시작 프로그램(Startup) 폴더에 자동 실행을 연동합니다.
# ==============================================================================
Write-Step "[Step 5] AutoHotkey v2 포터블 배포 및 Ctrl+Alt+T 단축키 등록"

# ── AutoHotkey 설치 여부 확인 ─────────────────────────────────────────────────
Write-Host ""
Write-Host ""
Write-Host "👉 AutoHotKey를 설치하시겠습니까? [" -ForegroundColor Yellow -NoNewline
Write-Host "Y" -ForegroundColor Green -NoNewline
Write-Host "/n]: " -ForegroundColor Yellow -NoNewline
$installAhk = Read-Host

if ($installAhk -match '^[Nn]') {
    # ── n 선택: devtools2 관련 AHK만 동적으로 감지하여 정리 ─────────────────────
    Write-Info "AutoHotKey 설치를 건너뜁니다. devtools2 관련 AHK 기능을 비활성화합니다..."

    $ahkModuleDir = "$env:LOCALAPPDATA\_devtools2\modules\autohotkey"
    $startupDir   = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

    # devtools2 경로 식별 패턴 — 특정 ahk 파일명을 하드코딩하지 않고
    # 'wsl.localhost\<배포판명>' 또는 '_devtools2' 경로를 가리키는 대상만 동적으로 식별합니다.
    $wslPattern   = [regex]::Escape("wsl.localhost\$WslDistro")
    $localPattern = [regex]::Escape("_devtools2")

    # (1) devtools2 경로(WSL UNC 또는 _devtools2)를 가리키는 AHK 프로세스만 동적으로 종료
    try {
        $killedCount = 0
        Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" -ErrorAction SilentlyContinue |
            Where-Object {
                $cmd = $_.CommandLine
                ($cmd -match $wslPattern) -or ($cmd -match $localPattern)
            } |
            ForEach-Object {
                Write-Info "devtools2 AHK 프로세스 종료: PID=$($_.ProcessId)"
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
                $killedCount++
            }
        if ($killedCount -eq 0) {
            Write-Info "종료할 devtools2 AHK 프로세스가 없습니다."
        }
    } catch {
        Write-Warn "AHK 프로세스 확인 중 오류 (WMI 사용 불가): $($_.Exception.Message)"
    }

    # (2) Startup 폴더의 .lnk 중 TargetPath 나 Arguments 가 devtools2 경로를 가리키는 바로가기만 동적으로 삭제
    $wshShellClean = New-Object -ComObject WScript.Shell
    Get-ChildItem -Path $startupDir -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $sc = $wshShellClean.CreateShortcut($_.FullName)
            $combined = "$($sc.Arguments) $($sc.TargetPath)"
            if (($combined -match $wslPattern) -or ($combined -match $localPattern)) {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                Write-Info "devtools2 AHK 바로가기 제거: $($_.Name)"
            }
        } catch {}
    }
    Write-Info "Startup 폴더 devtools2 AHK 바로가기 정리 완료."

    # (3) modules/autohotkey 폴더의 *.ahk 삭제 (WSL 연동 실패 시 폴백으로 로컬에 복사된 물리 파일들)
    #     ※ WSL 내부 원본(\\wsl.localhost\...\scripts\windows\autohotkey\*.ahk)은 건드리지 않음
    $localAhkFiles = Get-ChildItem -Path $ahkModuleDir -Filter "*.ahk" -ErrorAction SilentlyContinue
    if ($localAhkFiles) {
        $localAhkFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Info "로컬 폴백 AHK 파일 제거: $ahkModuleDir\*.ahk ($($localAhkFiles.Count)개)"
    }

    Write-Success "AutoHotkey의 devtools2 관련 기능이 비활성화되었습니다."
    Write-Info "다른 용도의 AutoHotkey 프로세스는 영향을 받지 않습니다."
} else {

# ── (1) modules/autohotkey 포터블 설치 경로 결정 ─────────────────────────────
$ahkModuleDir = "$env:LOCALAPPDATA\_devtools2\modules\autohotkey"
$ahkExe = Join-Path $ahkModuleDir "AutoHotkey64.exe"
if (-not (Test-Path $ahkExe)) {
    $ahkExe = Join-Path $ahkModuleDir "AutoHotkey.exe"
}

Write-Info "AutoHotKey 기능 연동을 진행합니다..."
Write-Host "  📌 [안내] WSL2 저장소의 AHK 스크립트 원본(%DEVTOOLS2%\scripts\windows\autohotkey)을 Windows 로컬로 복사해 연동합니다." -ForegroundColor DarkGray
Write-Host "     (재부팅 후 WSL2 미실행 상태에서도 즉시 동작을 보장하며, 설치 스크립트 재실행 시 최신 내용으로 자동 갱신됩니다)" -ForegroundColor DarkGray
Write-Host ""

# ── (2) 포터블 AutoHotkey v2 다운로드 및 압축 해제 ───────────────────────────
if (Test-Path $ahkExe) {
    Write-Info "AutoHotkey v2 포터블 이미 존재: $ahkExe"
    Write-Info "AHK 스크립트 배포 및 시작 프로그램 연동 중..."
} else {
    Write-Info "AutoHotkey v2 포터블 패키지 다운로드 및 압축 해제 중..."
    Write-Info "  설치 경로: $ahkModuleDir"

    New-Item -ItemType Directory -Path $ahkModuleDir -Force | Out-Null

    $ahkZipUrl  = "https://www.autohotkey.com/download/ahk-v2.zip"
    $ahkZipTemp = Join-Path $env:TEMP "ahk-v2.zip"

    try {
        # 비동기 백그라운드다운로드 및 스피너 대기
        $prevProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'

        $dlJob = Start-Job -ScriptBlock {
            param($url, $dest)
            Invoke-WebRequest -Uri $url -OutFile $dest -ErrorAction Stop
        } -ArgumentList $ahkZipUrl, $ahkZipTemp

        Wait-WithSpinner -Message "AutoHotkey v2 패키지 다운로드 중" -Condition { $dlJob.State -ne 'Running' } -MaxTimeoutSeconds 120
        Receive-Job -Job $dlJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $dlJob -Force -ErrorAction SilentlyContinue

        $ProgressPreference = $prevProgress

        if (Test-Path $ahkZipTemp) {
            # 백그라운드 압축 해제 및 스피너 대기
            $unzipJob = Start-Job -ScriptBlock {
                param($zip, $target)
                Expand-Archive -Path $zip -DestinationPath $target -Force
            } -ArgumentList $ahkZipTemp, $ahkModuleDir

            Wait-WithSpinner -Message "AutoHotkey v2 압축 해제 중" -Condition { $unzipJob.State -ne 'Running' } -MaxTimeoutSeconds 120
            Receive-Job -Job $unzipJob -ErrorAction SilentlyContinue | Out-Null
            Remove-Job -Job $unzipJob -Force -ErrorAction SilentlyContinue

            Remove-Item $ahkZipTemp -Force -ErrorAction SilentlyContinue
        }

        $ahkExe = Join-Path $ahkModuleDir "AutoHotkey64.exe"
        if (-not (Test-Path $ahkExe)) {
            $ahkExe = Join-Path $ahkModuleDir "AutoHotkey.exe"
        }

        if (Test-Path $ahkExe) {
            Write-Success "AutoHotkey v2 포터블 배포 완료: $ahkExe"

            # ── 사용자 레지스트리(HKCU)에 .ahk 확장자 자동 연결 등록 (오프라인 환경/더블클릭 대비) ──
            try {
                $ahkClassKey = "HKCU:\Software\Classes\AutoHotkeyScript\shell\open\command"
                if (-not (Test-Path $ahkClassKey)) { New-Item -Path $ahkClassKey -Force | Out-Null }
                Set-ItemProperty -Path $ahkClassKey -Name "(default)" -Value "`"$ahkExe`" `"%1`" %*" -ErrorAction SilentlyContinue

                $ahkExtKey = "HKCU:\Software\Classes\.ahk"
                if (-not (Test-Path $ahkExtKey)) { New-Item -Path $ahkExtKey -Force | Out-Null }
                Set-ItemProperty -Path $ahkExtKey -Name "(default)" -Value "AutoHotkeyScript" -ErrorAction SilentlyContinue
                Write-Success ".ahk 파일 확장자가 포터블 AutoHotkey에 자동 연결되었습니다."
            } catch {}
        } else {
            Write-Warn "압축 해제 후 AutoHotkey 실행 파일을 찾지 못했습니다: $ahkModuleDir"
        }
    } catch {
        $ProgressPreference = $prevProgress
        Remove-Item $ahkZipTemp -Force -ErrorAction SilentlyContinue
        Write-Warn "AutoHotkey v2 포터블 다운로드 실패: $($_.Exception.Message)"
    }
}



# ── (3) AHK 스크립트 배포 및 시작 프로그램 자동 실행 연동 ────────────────────
$startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

$ahkSetupJob = Start-Job -ScriptBlock {
    param($WslDistro, $startupDir, $ahkModuleDir, $ahkExe, $PSScriptRoot)

    # 헬퍼: WSL2 파일 존재 여부를 UNC Test-Path 대신 wsl test -f 로 0.01초만에 빠르게 검사
    function Test-WslFileFast {
        param($distro, $linuxPath)
        $res = wsl -d $distro -- bash -c "test -f '$linuxPath' && echo 'OK'" 2>$null
        return ($res -eq 'OK')
    }
    function Test-WslDirFast {
        param($distro, $linuxPath)
        $res = wsl -d $distro -- bash -c "test -d '$linuxPath' && echo 'OK'" 2>$null
        return ($res -eq 'OK')
    }

    # 🌟 통합 devtools2-hotkey.ahk 연동 및 시작 프로그램 등록
    # 포터블 AHK 실행 파일(AutoHotkey64.exe)을 원본 파일명 그대로 유지하여
    # 차후 독립적인 사용자 스크립트 실행 등 다목적 활용이 가능하도록 보장합니다.

    # 🌟 기존 AutoHotkey 관련 중복 항목 정리 (Startup 바로가기 & 레지스트리 Run 키 & 구형 Task Scheduler)
    Get-ChildItem -Path $startupDir -Filter "*.ahk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $startupDir -Filter "*AutoHotkey*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $startupDir -Filter "*WezTerm-Hotkey*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $startupDir -Filter "*Keyboard-Remap*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $startupDir -Filter "*DevTools2-Hotkey*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    $runRegPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($regPath in $runRegPaths) {
        if (Test-Path $regPath) {
            $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            if ($props) {
                $props.psobject.Properties | Where-Object { $_.Name -like "*AutoHotkey*" } | ForEach-Object {
                    Remove-ItemProperty -Path $regPath -Name $_.Name -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # 구형 Task Scheduler 잔여 항목 정리 (이전 버전 호환)
    try {
        $tsClean = New-Object -ComObject Schedule.Service
        $tsClean.Connect()
        $rootClean = $tsClean.GetFolder("\")
        @("DevTools2-Hotkey", "DevTools2-AutoHotkey") | ForEach-Object {
            try { $rootClean.DeleteTask($_, 0) } catch {}
        }
    } catch {}

    # %DEVTOOLS2% 환경 변수 연동
    $wslDevtools2Root = if ($env:DEVTOOLS2 -and (Test-Path $env:DEVTOOLS2)) { $env:DEVTOOLS2 } else { "\\wsl.localhost\$WslDistro\var\opt\_devtools2" }
    if (Test-WslDirFast $WslDistro '$DEVTOOLS2') {
        [Environment]::SetEnvironmentVariable("DEVTOOLS2", $wslDevtools2Root, "User")
        $env:DEVTOOLS2 = $wslDevtools2Root
    }

    # devtools2-hotkey.ahk 통합 스크립트 경로 지정
    # 재부팅 직후 WSL이 아직 기동하지 않은 상태에서도 AHK가 즉시 실행될 수 있도록
    # 항상 Windows 로컬 경로에 복사해 두고, 바로가기는 로컬 경로를 가리킵니다.
    # (설치 스크립트 재실행 시 WSL 원본에서 자동으로 덮어씁니다)
    $ahkDest = Join-Path $ahkModuleDir "devtools2-hotkey.ahk"
    $wslAhkRel = '$DEVTOOLS2/scripts/windows/autohotkey/devtools2-hotkey.ahk'

    if (Test-WslFileFast $WslDistro $wslAhkRel) {
        # WSL 원본 → Windows 로컬 복사 (재설치 시 자동 갱신)
        $wslAhkFull = "$wslDevtools2Root\scripts\windows\autohotkey\devtools2-hotkey.ahk"
        Copy-Item -Path $wslAhkFull -Destination $ahkDest -Force -ErrorAction SilentlyContinue
    } else {
        $ahkSourceLocal = $null
        if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
            $ahkSourceLocal = Join-Path (Split-Path $PSScriptRoot -Parent) "autohotkey\devtools2-hotkey.ahk"
        }
        if ($ahkSourceLocal -and (Test-Path $ahkSourceLocal)) {
            Copy-Item -Path $ahkSourceLocal -Destination $ahkDest -Force
        } else {
            try {
                $ahkRaw = "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/autohotkey/devtools2-hotkey.ahk"
                Invoke-WebRequest -Uri $ahkRaw -OutFile $ahkDest -ErrorAction Stop
            } catch {}
        }
    }

    # 통합 AutoHotkey 자동 실행 등록 (Task Scheduler)
    # Startup 폴더 바로가기는 Windows가 수 분간 지연 실행하는 문제가 있으므로
    # Task Scheduler 로그온 트리거를 사용해 로그온 즉시 실행합니다.
    # AHK 파일이 Windows 로컬 경로이므로 WSL 의존 없이 즉시 실행 가능합니다.
    if (Test-Path $ahkExe) {
        $taskName = "DevTools2-Hotkey"
        $registered = $false
        try {
            $ts   = New-Object -ComObject Schedule.Service
            $ts.Connect()
            $root = $ts.GetFolder("\")

            # 기존 동일 작업 삭제 후 재등록
            try { $root.DeleteTask($taskName, 0) } catch {}

            $task = $ts.NewTask(0)
            $task.Settings.ExecutionTimeLimit         = "PT0S"  # 시간제한 없음
            $task.Settings.MultipleInstances          = 3        # 이미 실행 중이면 무시
            $task.Settings.StopIfGoingOnBatteries     = $false
            $task.Settings.DisallowStartIfOnBatteries = $false

            # 트리거: 현재 사용자 로그온 시 즉시 실행 (지연 없음)
            $trigger         = $task.Triggers.Create(9)  # 9 = TASK_TRIGGER_LOGON
            $trigger.UserId  = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $trigger.Delay   = "PT0S"  # 지연 없음

            # 동작: AHK 실행 (Windows 로컬 경로 — WSL 불필요)
            $action                   = $task.Actions.Create(0)  # 0 = TASK_ACTION_EXEC
            $action.Path              = $ahkExe
            $action.Arguments         = "`"$ahkDest`""
            $action.WorkingDirectory  = $ahkModuleDir

            # 현재 사용자 권한으로 실행 (관리자 권한 불필요)
            $task.Principal.UserId    = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $task.Principal.LogonType = 3  # 3 = TASK_LOGON_INTERACTIVE_TOKEN
            $task.Principal.RunLevel  = 0  # 0 = TASK_RUNLEVEL_LUA (일반 사용자 권한)

            $root.RegisterTaskDefinition($taskName, $task, 6, $null, $null, 3) | Out-Null
            $registered = $true
        } catch {}

        # Task Scheduler 등록 실패 시 Startup 바로가기로 폴백
        if (-not $registered) {
            $shortcutPath = "$startupDir\DevTools2-Hotkey.lnk"
            try {
                $wshShell = New-Object -ComObject WScript.Shell
                $shortcut = $wshShell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath       = $ahkExe
                $shortcut.Arguments        = "`"$ahkDest`""
                $shortcut.WorkingDirectory = $ahkModuleDir
                $shortcut.WindowStyle      = 7
                $shortcut.Description      = "DevTools2 AutoHotkey Service (WezTerm Hotkey & Keyboard Remap)"
                $shortcut.Save()
            } catch {}
        }
    }

    # 기존 AutoHotkey 프로세스 전체 종료 후 통합 프로세스 단 1개만 실행
    Get-Process -Name "AutoHotkey*" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

    if ($ahkExe -and (Test-Path $ahkExe) -and $ahkDest -and (Test-Path $ahkDest)) {
        Start-Process -FilePath $ahkExe -ArgumentList "`"$ahkDest`"" -WindowStyle Hidden
    }

    return @{ AhkDest = $ahkDest }
} -ArgumentList $WslDistro, $startupDir, $ahkModuleDir, $ahkExe, $PSScriptRoot

# 스피너로 백그라운드 작업 대기
Wait-WithSpinner -Message "AutoHotkey 기능 연동 및 시작 프로그램 구성 중" -Condition { $ahkSetupJob.State -ne 'Running' } -MaxTimeoutSeconds 60

$jobRes = Receive-Job -Job $ahkSetupJob -ErrorAction SilentlyContinue
Remove-Job -Job $ahkSetupJob -Force -ErrorAction SilentlyContinue

Write-Success "AutoHotkey 기능(WezTerm Ctrl+Alt+T 단축키 및 CapsLock 리매핑)이 정상 연동되었습니다."
} # end if ($installAhk -notmatch '^[Nn]')

# ==============================================================================
# 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 WezTerm 설정 연동 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  설정 파일 공유(심볼릭 링크)가 완료되었습니다." -ForegroundColor White
Write-Host "  이제 리눅스 혹은 윈도우 어느 쪽에서든 설정을 편집하면 양쪽 모두에 즉시 반영됩니다." -ForegroundColor White
Write-Host ""
if (-not ($installAhk -match '^[Nn]')) {
    Write-Host "  [AutoHotkey 연동 안내]" -ForegroundColor Cyan
    Write-Host "  · AHK 소스: WSL2 레포 원본 (%DEVTOOLS2%/.../devtools2-hotkey.ahk) -> Windows 로컬 동기화" -ForegroundColor DarkGray
    Write-Host "  · AHK 수정 시 설치 스크립트를 재실행하면 최신 스크립트가 로컬로 즉시 반영됩니다." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [단축키]" -ForegroundColor Cyan
    Write-Host "  Ctrl+Alt+T          : WezTerm 새 창 열기" -ForegroundColor White
    Write-Host "  CapsLock (단독 탭)  : ESC" -ForegroundColor White
    Write-Host "  CapsLock + 다른 키  : Ctrl 조합" -ForegroundColor White
    Write-Host "  Shift + CapsLock    : 대문자 고정 ON" -ForegroundColor White
    Write-Host "  (고정ON) CapsLock/ESC: 대문자 고정 OFF" -ForegroundColor White
} else {
    Write-Host "  [안내] AutoHotkey 설치를 건너뛰어 devtools2 관련 AHK 기능이 비활성화되었습니다." -ForegroundColor Yellow
}
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
