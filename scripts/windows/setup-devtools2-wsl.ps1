#==============================================================================
# DevTools2 Windows/WSL2 통합 자동 설치 마스터 스크립트 (setup-devtools2-wsl.ps1)
#
# 주요 기능:
#   1. Windows WSL2 가상 머신 생성 및 활성화 (0.setup-wsl.ps1)
#   2. WSL2 내부로 Linux 초기화 스크립트를 복사 및 실행하여 깃 자격증명 설정 및 클론 진행
#   3. WSL2 내부의 환경변수 설정, 핵심 개발 런타임 및 CLI 유틸리티 도구 일괄 자동 설치
#   4. Windows 호스트용 WezTerm 및 Zed 에디터 자동 설치 및 WSL2 설정 연동
#
# [중요] 한글 깨짐 방지 안내 (Encoding Notice):
#   - 로컬 실행 시: 본 스크립트는 UTF-8(BOM 없음)로 저장되어 있어, 구버전 윈도우 기본
#     PowerShell 5.1 콘솔에서 직접 로컬 실행할 경우 한글 주석 및 메시지가 깨질 수 있습니다.
#     로컬 실행 시에는 가급적 PowerShell 7 (pwsh)을 설치한 후 실행하시기 바랍니다.
#   - 온라인 실행 시: 웹 브라우저나 원격 다운로드 명령(irm | iex 등)을 사용해 온라인에서
#     실시간으로 실행하는 경우에는 인코딩 다운로드 보정이 적용되어 문제없이 정상 동작합니다.
#
# 사용 방법:
#   PowerShell 을 관리자 권한으로 열고 실행:
#   .\setup-devtools2-wsl.ps1
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
    Write-Host "===========================================================================" -ForegroundColor DarkCyan
    Write-Host "  $Message" -ForegroundColor DarkCyan
    Write-Host "===========================================================================" -ForegroundColor DarkCyan
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
    Write-Host "👉 계속하려면 엔터(Enter) 키를 누르세요: " -ForegroundColor Yellow -NoNewline
    [void][System.Console]::ReadLine()
}

# 파일/심볼릭 링크(dangling 포함)를 안전하게 제거하는 헬퍼
# Test-Path는 대상이 없는 dangling symlink를 $false로 반환하여 기존 링크가 남아
# mklink 재실행 시 "파일이 이미 있습니다" 오류를 유발하므로, Get-Item -Force 로 실제 존재 여부를 확인합니다.
function Remove-FileOrSymlink {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -ne $item) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        return $true   # 삭제 수행
    }
    # Get-Item도 못 찾은 경우 cmd dir로 최종 확인 (극히 드문 케이스 대비)
    $cmdCheck = cmd.exe /c "if exist `"$Path`" echo exists" 2>$null
    if ($cmdCheck -match 'exists') {
        cmd.exe /c "del /f /q `"$Path`"" 2>$null | Out-Null
        return $true
    }
    return $false  # 애초에 없었음
}

# 심볼릭 링크를 멱등성 있게 생성하는 헬퍼 (dangling symlink 포함 기존 항목 자동 정리 후 재생성)
function New-SymlinkIdempotent {
    param(
        [string]$LinkPath,
        [string]$TargetPath,
        [string]$Description = ""
    )
    $label = if ($Description) { $Description } else { Split-Path $LinkPath -Leaf }

    # 1) 대상(WSL 경로)이 존재하는지 확인
    if (-not (Test-Path $TargetPath)) {
        Write-Warn "$label 대상 경로가 존재하지 않아 심볼릭 링크를 건너뜁니다: $TargetPath"
        return $false
    }

    # 2) 기존 파일/링크(dangling 포함) 제거
    $removed = Remove-FileOrSymlink -Path $LinkPath
    if ($removed) {
        Write-Info "$label 기존 항목 제거 완료: $LinkPath"
    }

    # 3) 심볼릭 링크 생성
    Write-Info "$label 심볼릭 링크 생성 중..."
    $result = cmd.exe /c "mklink `"$LinkPath`" `"$TargetPath`"" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "$label 심볼릭 링크 생성 실패: $result"
        return $false
    }
    Write-Success "$label 심볼릭 링크 생성 완료"
    return $true
}

# 단순 프로세스/조건 대기형 스피너 헬퍼
function Wait-WithSpinner {
    param(
        [string]$Message,
        [scriptblock]$Condition,
        [int]$MaxTimeoutSeconds = 600
    )
    $spinner = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $i = 0
    $startTime = Get-Date
    while ($true) {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -gt $MaxTimeoutSeconds) {
            Write-Host "`r  [시간 초과] $Message (제한 시간 초과)   " -ForegroundColor Red
            return $false
        }

        $success = & $Condition
        if ($success) {
            Write-Host "`r  [완료] $Message 완료!   " -ForegroundColor Green
            return $true
        }

        $char = $spinner[$i % $spinner.Count]
        Write-Host -NoNewline "`r  [$char] $Message...   "
        Start-Sleep -Milliseconds 150
        $i++
    }
}

# ==============================================================================
# [Step 0] 관리자 권한 확인 및 재실행
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

# 관리자 권한이 없는 경우에만 UAC 권한 승격 재실행 (이미 관리자 모드이면 이 블록 건너뜀)
if (-not $isAdmin) {
    # PowerShell 7(pwsh) UAC 승격 가능 여부 판단:
    # - Microsoft Store 설치 경로(WindowsApps)는 Start-Process -Verb RunAs 가 차단됩니다.
    # - winget 직접 설치(C:\Program Files\PowerShell\)는 UAC 승격이 정상 동작합니다.
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    $pwshPath = if ($pwshCmd) { $pwshCmd.Source } else { $null }
    $isStorePwsh = $pwshPath -and ($pwshPath -like '*WindowsApps*')

    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        # ── 온라인 실행 모드 (irm ... | iex) ──────────────────────────────────
        # 스크립트가 메모리에서 실행되므로 BOM/인코딩 문제 없음
        # Store pwsh 여부와 관계없이 기본 powershell.exe 로 UAC 승격 후 재실행 가능
        Write-Warn "관리자 권한이 필요합니다. UAC 승격 후 새 창에서 원격 설치를 계속합니다..."
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/setup-devtools2-wsl.ps1 | iex`"" -Verb RunAs
        exit
    } else {
        # ── 로컬 파일 실행 모드 ────────────────────────────────────────────────
        # 파일을 디스크에서 읽으므로 UTF-8(BOM 없음) 처리를 위해 반드시 PowerShell 7 필요
        if ($isStorePwsh) {
            # Store 버전 pwsh는 -Verb RunAs 차단됨 → 사용자에게 수동 실행 안내
            Write-Host ""
            Write-Host "=============================================================================" -ForegroundColor Red
            Write-Host " [오류] Microsoft Store 설치 PowerShell 은 UAC 자동 권한 승격이 차단됩니다." -ForegroundColor Red
            Write-Host "=============================================================================" -ForegroundColor Red
            Write-Host ""
            Write-Host " PowerShell 7 을 '관리자 권한으로 실행' 후 아래 명령어를 다시 입력해 주세요:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "   Set-ExecutionPolicy Bypass -Scope Process -Force; & `"$PSCommandPath`"" -ForegroundColor Cyan
            Write-Host ""
            Write-Host " (또는 탐색기에서 setup-devtools2-wsl.ps1 우클릭 → PowerShell 7 관리자로 실행)" -ForegroundColor DarkGray
            Write-Host ""
            Read-Host "엔터를 누르면 종료합니다"
            exit 1
        } else {
            # 직접 설치 pwsh → UAC 자동 승격 재실행
            $psExe = if ($pwshPath) { $pwshPath } else { 'powershell.exe' }
            Write-Warn "전체 환경 구축을 위해 관리자 권한으로 스크립트를 재실행합니다..."
            Start-Process $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
            exit
        }
    }
}


Clear-Host
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🌟 DevTools2 Windows & WSL2 통합 설치 마스터 자동화" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan

# ==============================================================================
# [사전 정리] AutoHotkey 프로세스 종료 및 구형 Startup 항목 제거
# ==============================================================================
# 최초 설치 또는 재설치 시, WSL 이 아직 없는 상태에서 이전 설치로 생긴
# Startup 폴더의 .lnk/.ahk 바로가기가 오류 팝업을 일으킬 수 있으므로
# Step 1 (WSL 설치) 이전에 먼저 정리합니다.

# 대상 WSL 배포판 이름 (코드 전체에서 고정될 상수 미리 선언)
$wslDistro = "devtools2"
$_startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

# 1. 실행 중인 AutoHotkey 인스턴스 전체 종료
Get-Process -Name "AutoHotkey*" -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

# 2. Startup 폴더의 raw .ahk 파일은 모두 제거 (포터블 AHK 환경에서 직접 .ahk 가 있으면 앱 선택 팝업 원인)
Get-ChildItem -Path $_startupDir -Filter "*.ahk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# 3. Startup 폴더의 .lnk 중 AutoHotkey.exe + \\wsl.localhost\$wslDistro 경로를 인수로
#    가진 바로가기만 선택적으로 제거 (다른 용도의 .lnk 는 절대 건드리지 않음)
$_wslUncPattern = [regex]::Escape("\\wsl.localhost\$wslDistro")
$_wshShell = New-Object -ComObject WScript.Shell
Get-ChildItem -Path $_startupDir -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $sc = $_wshShell.CreateShortcut($_.FullName)
        $isAhk     = $sc.TargetPath -match 'AutoHotkey' -or $sc.TargetPath -match '\.ahk$'
        $isWslPath = $sc.Arguments  -match $_wslUncPattern
        if ($isAhk -and $isWslPath) {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Info "WSL AHK 바로가기 제거: $($_.Name)"
        }
    } catch {}
}
Write-Info "AutoHotkey Startup 항목 사전 정리 완료"

$isLocalMode = $false
if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
    $BaseDir = $PSScriptRoot
    $ToolsDir = Join-Path $BaseDir "dev-env"

    # 로컬 하위 스크립트 경로 존재 여부 점검 (로컬 모드/온라인 모드 자동 판정)
    $setupWslScript = Join-Path $ToolsDir "0.setup-wsl.ps1"
    $setupWeztermScript = Join-Path $ToolsDir "1.setup-wezterm.ps1"
    $setupZedScript = Join-Path $ToolsDir "2.setup-zed.ps1"

    if ((Test-Path $setupWslScript) -and (Test-Path $setupWeztermScript) -and (Test-Path $setupZedScript)) {
        $isLocalMode = $true
    }
}

if ($isLocalMode) {
    Write-Info "로컬 스크립트가 감지되었습니다. [로컬 오프라인 모드]로 설치를 진행합니다."
} else {
    Write-Warn "로컬 스크립트가 존재하지 않거나 원격 실행 중입니다. GitHub 공개 저장소에서 다운로드하는 [온라인 원격 모드]로 설치를 진행합니다."
}

# ==============================================================================
# [Step 1] Windows WSL2 가상 머신 생성 및 활성화
# ==============================================================================
Write-Step "[Step 1] WSL2 가상 머신 인스턴스 생성"

# 하위 스크립트 실행기: pwsh(PS7) 우선, 없으면 powershell.exe(PS5) 폴백
# UTF-8 BOM 없는 파일을 PS7에서 실행해야 브레일 스피너 등 유니코드 문자 파싱 오류를 방지할 수 있음
$_psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell.exe' }

if ($isLocalMode) {
    & $_psExe -NoProfile -ExecutionPolicy Bypass -File $setupWslScript
} else {
    Write-Info "GitHub에서 WSL 설치 스크립트 다운로드 중..."
    $rawWslScript = Invoke-RestMethod "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/0.setup-wsl.ps1"

    # temp 파일 저장 없이 메모리에서 직접 실행 (irm | iex 방식과 동일)
    # HTTP 헤더(charset=utf-8)를 통해 인코딩이 이미 올바르게 처리되므로 BOM 불필요
    Invoke-Expression $rawWslScript
}

# 설치 중 에러가 발생한 경우 예외 처리
if ($LASTEXITCODE -ne 0) {
    Write-Fail "WSL 설치 스크립트 실행 중 에러가 발생했습니다 (종료 코드: $LASTEXITCODE)."
    Pause-Script
    exit 1
}

# 대상 WSL2 배포판 이름은 'devtools2'로 고정입니다.
$wslDistro = "devtools2"
Write-Info "대상 WSL2 배포판: $wslDistro"

# ==============================================================================
# [Step 1-후처리] WSL2 배포판 접근 가능 여부 확인 (신규 설치 후 등록 지연 대응)
# ==============================================================================
Write-Info "WSL2 배포판($wslDistro) 접근 가능 여부 확인 중..."
$maxRetry = 15
$retryCount = 0
$distroReady = $false
$spinner = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
$sIdx = 0

while ($retryCount -lt $maxRetry) {
    # WSL ready 확인을 백그라운드로 띄워 스피너 표시
    $checkProc = Start-Process wsl.exe -ArgumentList "-d $wslDistro -- echo ready" -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\wsl_ready_check.txt" -ErrorAction SilentlyContinue

    # 2초 동안 스피너 회전 대기
    for ($i = 0; $i -lt 8; $i++) {
        $char = $spinner[$sIdx % $spinner.Count]
        Write-Host -NoNewline "`r  [$char] WSL2 배포판 준비 상태 조회 중...   "
        Start-Sleep -Milliseconds 150
        $sIdx++
        if ($checkProc.HasExited) { break }
    }

    if ($checkProc.HasExited) {
        $testResult = Get-Content "$env:TEMP\wsl_ready_check.txt" -Raw 2>$null
        # ready 문자열이 포함되어 있으면 통과 (경고 메세지와 섞여 있어도 검출 가능)
        if ($testResult -match "ready") {
            $distroReady = $true
            Write-Host "`r  [완료] WSL2 배포판 접근 확인 완료: $wslDistro   " -ForegroundColor Green
            Remove-Item "$env:TEMP\wsl_ready_check.txt" -Force -ErrorAction SilentlyContinue
            break
        }
    }
    Remove-Item "$env:TEMP\wsl_ready_check.txt" -Force -ErrorAction SilentlyContinue

    $retryCount++
    Write-Host ""
    Write-Info "  WSL2 배포판 준비 대기 중... ($retryCount/$maxRetry)"
    Start-Sleep -Seconds 2
}

if (-not $distroReady) {
    Write-Fail "WSL2 배포판($wslDistro)에 접근할 수 없습니다."
    Write-Warn "잠시 후 다시 시도하거나 아래 명령으로 WSL 상태를 직접 확인해주세요:"
    Write-Host "    wsl --list --verbose" -ForegroundColor Gray
    Pause-Script
    exit 1
}

# ==============================================================================
# [Step 2] WSL2 내부 개발도구 디렉터리 및 권한 초기화
# ==============================================================================
Write-Step "[Step 2] WSL2 내부 개발도구 디렉터리 및 권한 초기화"

# WSL sudo 권한 획득을 위한 비밀번호 입력
Write-Host ""
Write-Host "┌──────────────────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
Write-Host "│ 🔑  WSL2 sudo 관리자 권한 실행을 위한 비밀번호 입력                      │" -ForegroundColor Yellow
Write-Host "├──────────────────────────────────────────────────────────────────────────┤" -ForegroundColor Yellow
Write-Host "│  WSL2 내부의 시스템 패키지(apt) 및 개발 환경 설정을 위해                 │" -ForegroundColor White
Write-Host "│  Ubuntu 설치 시 생성했던 계정의 비밀번호 입력이 필요합니다.              │" -ForegroundColor White
Write-Host "└──────────────────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
Write-Host ""

$wslTmpForPw = "\\wsl.localhost\$wslDistro\tmp\.wsl_pw_tmp"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

while ($true) {
    Write-Host "👉 비밀번호(password) 입력: " -ForegroundColor Yellow -NoNewline
    $wslPassword = Read-Host -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($wslPassword)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    # 비밀번호 뒤에 줄바꿈을 추가해야 sudo -S 가 안정적으로 읽음
    [System.IO.File]::WriteAllText($wslTmpForPw, ($plainPassword + "`n"), $utf8NoBom)
    $plainPassword = $null

    # sudo -k 후 비밀번호 검증
    wsl -d $wslDistro -- bash -c "sudo -k; cat /tmp/.wsl_pw_tmp | sudo -S -v 2>/dev/null"
    if ($LASTEXITCODE -eq 0) {
        Write-Success "비밀번호 인증 성공"
        Write-Host ""
        break
    } else {
        Remove-Item $wslTmpForPw -Force -ErrorAction SilentlyContinue
        Write-Fail "비밀번호가 올바르지 않습니다. 다시 입력해주세요."
        Write-Host ""
    }
}

# WSL2 저장소 초기화 및 깃 클론 (0.init-devtools2.sh 실행)
Write-SubStep "▶ WSL2 저장소 초기화 및 Git 클론 실행 (0.init-devtools2.sh)"
$RAW_BASE = "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env"

if ($isLocalMode) {
    wsl -d $wslDistro -- bash -c 'cat /tmp/.wsl_pw_tmp | sudo -S bash $DEVTOOLS2/scripts/linux/dev-env/0.init-devtools2.sh'
} else {
    wsl -d $wslDistro -- bash -c "cat /tmp/.wsl_pw_tmp | sudo -S bash <(curl -sSfL '$RAW_BASE/0.init-devtools2.sh')"
}

if ($LASTEXITCODE -ne 0) {
    Write-Fail "0.init-devtools2.sh 초기화 실패"
    Pause-Script
    exit 1
}

# ==============================================================================
# [사전 질문 및 Windows 에디터 설치]
# ==============================================================================
Write-SubStep "▶ Windows 개발 에디터(VS Code / Zed) 설치 의사 확인"

# 1. VSCode 설치 여부 사전 확인 및 설치
$vscodeAlreadyInstalled = $false
try {
    if (Get-Command code -ErrorAction SilentlyContinue) {
        $vscodeAlreadyInstalled = $true
    } elseif (Test-Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe") {
        $vscodeAlreadyInstalled = $true
    } elseif (Test-Path "$env:ProgramFiles\Microsoft VS Code\Code.exe") {
        $vscodeAlreadyInstalled = $true
    }
} catch {}

$userChoseVscode = $false
if (-not $vscodeAlreadyInstalled) {
    Write-Host ""
    Write-Host "👉 VS Code (Visual Studio Code)를 설치하시겠습니까? [y/" -ForegroundColor Yellow -NoNewline
    Write-Host "N" -ForegroundColor Green -NoNewline
    Write-Host "]: " -ForegroundColor Yellow -NoNewline
    $installVscodeInput = Read-Host
    $userChoseVscode = $installVscodeInput -match '^[Yy]'

    if ($userChoseVscode) {
        Write-Info "VSCode(Visual Studio Code)를 winget으로 자동 설치합니다..."
        $p = Start-Process winget -ArgumentList "install --id Microsoft.VisualStudioCode --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -PassThru
        $spinner = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
        $sIdx = 0
        while (-not $p.HasExited) {
            $char = $spinner[$sIdx % $spinner.Count]
            Write-Host -NoNewline "`r  [$char] VSCode 패키지 설치 진행 중...   "
            Start-Sleep -Milliseconds 150
            $sIdx++
        }
        Write-Host "`r  [완료] VSCode 패키지 설치 완료!   " -ForegroundColor Green
        if ($p.ExitCode -ne 0) {
            Write-Warn "winget 설치 종료 코드: $($p.ExitCode) (이미 설치되었거나 다른 이유일 수 있습니다)"
        }
        # PATH 갱신: winget 설치 후 code CLI를 현재 세션 및 WSL Interop에서 즉시 사용 가능하게 함
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    } else {
        Write-Skip "VS Code 설치를 건너뜁니다."
    }
} else {
    Write-Skip "VSCode(Visual Studio Code)가 이미 설치되어 있습니다."
}

# 2. Zed 에디터 설치 여부 사전 확인
Write-Host ""
Write-Host "👉 Zed 에디터를 설치하시겠습니까? [y/" -ForegroundColor Yellow -NoNewline
Write-Host "N" -ForegroundColor Green -NoNewline
Write-Host "]: " -ForegroundColor Yellow -NoNewline
$installZedInput = Read-Host
$userChoseZed = $installZedInput -match '^[Yy]'

# ==============================================================================
# [Step 3] WSL2 내부 런타임 및 도구 일괄 설치
# ==============================================================================
Write-Step "[Step 3] WSL2 개발 환경 빌드 및 패키지 일괄 설치"

$RAW_BASE = "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env"

Write-SubStep "▶ (1/3) WSL2 환경 변수 주입 (~/.bashrc)"
if ($isLocalMode) {
    wsl -d $wslDistro -- bash -c 'DEVTOOLS2=/var/opt/_devtools2 bash -l $DEVTOOLS2/scripts/linux/dev-env/1.setup-env.sh'
} else {
    wsl -d $wslDistro -- bash -c "DEVTOOLS2=/var/opt/_devtools2 bash -l <(curl -sSfL '$RAW_BASE/1.setup-env.sh')"
}
if ($LASTEXITCODE -ne 0) { Write-Fail "환경 변수 설정 실패"; Pause-Script; exit 1 }

Write-SubStep "▶ (2/3) WSL2 핵심 개발 도구 설치 (Java, Node.js, Python, Neovim, VSCode 확장)"
if ($isLocalMode) {
    wsl -d $wslDistro -- bash -c 'bash -l $DEVTOOLS2/scripts/linux/dev-env/2.install-core-tools.sh'
} else {
    wsl -d $wslDistro -- bash -c "bash -l <(curl -sSfL '$RAW_BASE/2.install-core-tools.sh')"
}
if ($LASTEXITCODE -ne 0) { Write-Fail "핵심 도구 설치 실패"; Pause-Script; exit 1 }

Write-SubStep "▶ (3/3) WSL2 CLI 유틸리티 및 apt 패키지 설치"
if ($isLocalMode) {
    wsl -d $wslDistro -- bash -c 'bash -l $DEVTOOLS2/scripts/linux/dev-env/3.install-cli-tools.sh'
} else {
    wsl -d $wslDistro -- bash -c "bash -l <(curl -sSfL '$RAW_BASE/3.install-cli-tools.sh')"
}
if ($LASTEXITCODE -ne 0) { Write-Fail "CLI 유틸리티 설치 실패"; Pause-Script; exit 1 }


Write-Success "WSL2 내부 가상 머신 개발 환경 구축 완료!"


# ==============================================================================
# [Step 4] Windows 호스트 전용 개발도구 연동
# ==============================================================================
Write-Step "[Step 4] Windows 호스트 전용 개발도구 연동"

# ── 4-1. WezTerm ──────────────────────────────────────────────────────────────
if ($isLocalMode) {
    Write-SubStep "▶ (1/3) WezTerm 설치 및 설정 연동 (로컬)"
    & $setupWeztermScript -WslDistro $wslDistro
} else {
    Write-SubStep "▶ (1/3) WezTerm 설치 및 설정 연동 (온라인)"
    $rawWeztermScript = Invoke-RestMethod "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/1.setup-wezterm.ps1"
    $weztermScriptBlock = [scriptblock]::Create($rawWeztermScript)
    & $weztermScriptBlock -WslDistro $wslDistro
}

# ── 4-2. VSCode 설정 및 Windows 로컬 확장 연동 ───────────────────────────────
Write-SubStep "▶ (2/3) VSCode 설정 연동 및 Windows 로컬 확장 설치"

$skipVsCodeLink = -not ($userChoseVscode -or $vscodeAlreadyInstalled)

if ($skipVsCodeLink) {
    Write-Skip "VS Code 미설치 상태로 설정 연동을 건너뜁니다."
} else {
    Write-Info "VSCode 설정, 확장 목록 및 Gradle 자격증명 연동 (심볼릭 링크)"
    $vscodeUserDir = "$env:APPDATA\Code\User"
    if (-not (Test-Path $vscodeUserDir)) {
        New-Item -ItemType Directory -Path $vscodeUserDir -Force | Out-Null
    }

    # 윈도우 사용자 환경 변수에 %DEVTOOLS2% 자동 등록
    $wslDevtools2Root = "\\wsl.localhost\$wslDistro\var\opt\_devtools2"
    if (Test-Path $wslDevtools2Root) {
        [Environment]::SetEnvironmentVariable("DEVTOOLS2", $wslDevtools2Root, "User")
        $env:DEVTOOLS2 = $wslDevtools2Root
        Write-Success "Windows 사용자 환경 변수 %DEVTOOLS2% 연동 완료: $wslDevtools2Root"
    }

    $devtools2Root = if ($env:DEVTOOLS2) { $env:DEVTOOLS2 } else { $wslDevtools2Root }

    # WSL2 내 대상 파일 경로
    $targetSettings    = "$devtools2Root\.config\vscode\settings.json"
    $targetKeybindings = "$devtools2Root\.config\vscode\keybindings.json"
    $targetTasks       = "$devtools2Root\.config\vscode\tasks.json"

    # settings.json
    $settingsItem = Get-Item -LiteralPath "$vscodeUserDir\settings.json" -Force -ErrorAction SilentlyContinue
    if ($null -ne $settingsItem) {
        $isLink = $settingsItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint
        if (-not $isLink) {
            if (-not (Test-Path "$vscodeUserDir\settings.json.bak")) {
                Move-Item "$vscodeUserDir\settings.json" "$vscodeUserDir\settings.json.bak" -Force
                Write-Info "기존 settings.json을 settings.json.bak으로 백업했습니다."
            } else {
                Remove-Item "$vscodeUserDir\settings.json" -Force
            }
        } else {
            Remove-Item -LiteralPath "$vscodeUserDir\settings.json" -Force -ErrorAction SilentlyContinue
        }
    } else {
        $cmdCheck = cmd.exe /c "if exist `"$vscodeUserDir\settings.json`" echo exists" 2>$null
        if ($cmdCheck -match 'exists') {
            cmd.exe /c "del /f /q `"$vscodeUserDir\settings.json`"" 2>$null | Out-Null
            Write-Info "settings.json dangling symlink 제거 완료"
        }
    }

    # keybindings.json
    $kbItem = Get-Item -LiteralPath "$vscodeUserDir\keybindings.json" -Force -ErrorAction SilentlyContinue
    if ($null -ne $kbItem) {
        $isLink = $kbItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint
        if (-not $isLink) {
            if (-not (Test-Path "$vscodeUserDir\keybindings.json.bak")) {
                Move-Item "$vscodeUserDir\keybindings.json" "$vscodeUserDir\keybindings.json.bak" -Force
                Write-Info "기존 keybindings.json을 keybindings.json.bak으로 백업했습니다."
            } else {
                Remove-Item "$vscodeUserDir\keybindings.json" -Force
            }
        } else {
            Remove-Item -LiteralPath "$vscodeUserDir\keybindings.json" -Force -ErrorAction SilentlyContinue
        }
    } else {
        $cmdCheck = cmd.exe /c "if exist `"$vscodeUserDir\keybindings.json`" echo exists" 2>$null
        if ($cmdCheck -match 'exists') {
            cmd.exe /c "del /f /q `"$vscodeUserDir\keybindings.json`"" 2>$null | Out-Null
            Write-Info "keybindings.json dangling symlink 제거 완료"
        }
    }

    # tasks.json
    $tasksItem = Get-Item -LiteralPath "$vscodeUserDir\tasks.json" -Force -ErrorAction SilentlyContinue
    if ($null -ne $tasksItem) {
        $isLink = $tasksItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint
        if (-not $isLink) {
            if (-not (Test-Path "$vscodeUserDir\tasks.json.bak")) {
                Move-Item "$vscodeUserDir\tasks.json" "$vscodeUserDir\tasks.json.bak" -Force
                Write-Info "기존 tasks.json을 tasks.json.bak으로 백업했습니다."
            } else {
                Remove-Item "$vscodeUserDir\tasks.json" -Force
            }
        } else {
            Remove-Item -LiteralPath "$vscodeUserDir\tasks.json" -Force -ErrorAction SilentlyContinue
        }
    } else {
        $cmdCheck = cmd.exe /c "if exist `"$vscodeUserDir\tasks.json`" echo exists" 2>$null
        if ($cmdCheck -match 'exists') {
            cmd.exe /c "del /f /q `"$vscodeUserDir\tasks.json`"" 2>$null | Out-Null
            Write-Info "tasks.json dangling symlink 제거 완료"
        }
    }

    # 심볼릭 링크 생성
    New-SymlinkIdempotent -LinkPath "$vscodeUserDir\settings.json"    -TargetPath $targetSettings    -Description "VSCode settings.json"
    New-SymlinkIdempotent -LinkPath "$vscodeUserDir\keybindings.json" -TargetPath $targetKeybindings -Description "VSCode keybindings.json"
    if (Test-Path $targetTasks) {
        New-SymlinkIdempotent -LinkPath "$vscodeUserDir\tasks.json" -TargetPath $targetTasks -Description "VSCode tasks.json"
    }

    # 🌟 VSCode 확장 목록(extensions.txt) 동기화 자동 설치 (Windows 로컬)
    $targetExtensionsList = "$devtools2Root\.config\vscode\extensions.txt"
    if (Test-Path $targetExtensionsList) {
        if (Get-Command code -ErrorAction SilentlyContinue) {
            # [1] Windows 로컬 확장 설치
            $installedExts = @((code --list-extensions 2>$null) | ForEach-Object { $_.Trim().ToLower() })

            $toInstall = @()
            Get-Content $targetExtensionsList | ForEach-Object {
                $ext = $_.Trim()
                if ($ext -and -not $ext.StartsWith("#") -and ($ext -match '^[a-zA-Z0-9][a-zA-Z0-9_-]*\.[a-zA-Z0-9][a-zA-Z0-9_-]*$')) {
                    if (-not ($installedExts -contains $ext.ToLower())) {
                        $toInstall += $ext
                    }
                }
            }

            if ($toInstall.Count -gt 0) {
                Write-Info "Windows 로컬: 신규/미설치 확장 $($toInstall.Count)개 설치 중..."
                foreach ($ext in $toInstall) {
                    code --install-extension $ext --force | Out-Null
                }
                Write-Success "Windows 로컬 확장 $($toInstall.Count)개 설치 완료"
            } else {
                Write-Skip "Windows 로컬: 모든 확장 프로그램이 이미 설치되어 있습니다."
            }

            # [2] WSL Remote 확장 설치 (WSL Remote Server에 별도 설치 필요)
            Write-Info "WSL Remote: VSCode 확장 프로그램 설치 중 (WSL 내부 bash 실행)..."
            $wslExtScript = 'VSCODE_BIN=""; command -v code >/dev/null 2>&1 && VSCODE_BIN="code"; [ -z "$VSCODE_BIN" ] && command -v code.cmd >/dev/null 2>&1 && VSCODE_BIN="code.cmd"; [ -z "$VSCODE_BIN" ] && { echo "[WSL-SKIP] code CLI not found"; exit 0; }; EXT_LIST="$DEVTOOLS2/.config/vscode/extensions.txt"; [ ! -f "$EXT_LIST" ] && { echo "[WSL-SKIP] extensions.txt not found"; exit 0; }; _INST=$("$VSCODE_BIN" --list-extensions 2>/dev/null | tr [:upper:] [:lower:]); _cnt=0; while IFS= read -r line || [ -n "$line" ]; do ext=$(echo "$line" | tr -d \r | sed "s/#.*//" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//"); [ -z "$ext" ] && continue; ext_lower=$(echo "$ext" | tr [:upper:] [:lower:]); if echo "$_INST" | grep -qF "$ext_lower"; then echo "[SKIP] $ext"; else echo "[Install] $ext"; "$VSCODE_BIN" --install-extension "$ext" --force >/dev/null 2>&1 && echo "[OK] $ext" || echo "[FAIL] $ext"; _cnt=$((_cnt+1)); fi; done < "$EXT_LIST"; echo "[WSL Done] New installs: ${_cnt}"'
            try {
                wsl -d $wslDistro -- bash -c "DEVTOOLS2='/var/opt/_devtools2'; $wslExtScript" 2>$null
            } catch {
                Write-Warn "WSL Remote 확장 설치 중 오류: $_"
            }
        } else {
            Write-Warn "VSCode CLI('code')를 찾을 수 없어서 확장 프로그램 자동 설치를 건너럹니다."
        }
    }

    Write-Success "VSCode 설정 연동 완료"
}

# ── 4-3. Zed ─────────────────────────────────────────────────────────────────
Write-SubStep "▶ (3/3) Zed 에디터 설치 및 설정 연동"
if ($userChoseZed) {
    if ($isLocalMode) {
        & $setupZedScript -WslDistro $wslDistro
    } else {
        $rawZedScript = Invoke-RestMethod "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/2.setup-zed.ps1"
        $zedScriptBlock = [scriptblock]::Create($rawZedScript)
        & $zedScriptBlock -WslDistro $wslDistro
    }
} else {
    Write-Skip "Zed 에디터 설치를 건너뜁니다. 기존 설정은 유지됩니다."
}

# 🌟 [Gradle gradle.properties 윈도우 ↔ WSL2 심볼릭 링크 연동]
# - 보안 자격증명 정보(Git Token/Maven Auth) 손실 방지 및 이중 환경 호환성 확보
# - dotfiles repository에 올리지 않고, WSL2 사용자 홈(~/.gradle/gradle.properties)을 직접 윈도우 홈으로 링크
$winGradleDir = "$env:USERPROFILE\.gradle"
if (-not (Test-Path $winGradleDir)) {
    New-Item -ItemType Directory -Path $winGradleDir -Force | Out-Null
}

$wslUser = (wsl -d $wslDistro -- bash -c "whoami" 2>$null).Trim()
if ([string]::IsNullOrEmpty($wslUser)) { $wslUser = "eseungsu" }
$wslGradleProps = "\\wsl.localhost\$wslDistro\home\$wslUser\.gradle\gradle.properties"
$winGradleProps = "$winGradleDir\gradle.properties"

if (Test-Path $wslGradleProps) {
    # dangling symlink 포함 기존 항목 안전 제거 후 재생성 (멱등성 보장)
    Remove-FileOrSymlink -Path $winGradleProps | Out-Null
    Write-Info "Gradle gradle.properties 윈도우 ↔ WSL2 심볼릭 링크 연동 중..."
    $result = cmd.exe /c "mklink `"$winGradleProps`" `"$wslGradleProps`"" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Gradle gradle.properties 연동 완료:`n    $wslGradleProps -> $winGradleProps"
    } else {
        Write-Warn "Gradle gradle.properties 심볼릭 링크 생성 실패 (수동으로 확인해 주세요): $result"
    }
} else {
    Write-Warn "WSL2 경로에 gradle.properties 파일이 존재하지 않아 연동을 건너뜁니다: $wslGradleProps"
}

# ==============================================================================
# 전체 설치 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 DevTools2 Windows 및 WSL2 전체 개발 환경 통합 구축 완료!" -ForegroundColor Green
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
Write-Info "  윈도우와 WSL2가 완벽하게 상호 연동되어 동작합니다."
Write-Info "  - Windows 셸에서 'wsl'을 치면 설정이 완료된 Ubuntu 개발 환경에 바로 진입합니다."
Write-Info "  - Windows에 설치된 WezTerm 및 Zed 에디터의 설정은 WSL2 내부 설정과 실시간 공유됩니다."
Write-Host ""
Write-Host "  설치 성공을 확인하시려면 아래 도구들을 실행해 보세요:"
Write-Host "    - Windows: WezTerm 터미널 열기 (WSL2 바로 진입 확인)" -ForegroundColor Gray
Write-Host "    - Windows: Zed 에디터 열기" -ForegroundColor Gray
Write-Host "    - WSL2 내부: nvim --version, java -version, node -v 실행 확인" -ForegroundColor Gray
Write-Host ""
Write-Info "💡 [참고: 'Exec format error' 트러블슈팅]"
Write-Info "  WSL2 터미널에서 'code .' 실행 시 'Exec format error'가 발생하는 경우:"
Write-Info "  -> PowerShell에서 'wsl --shutdown' 실행 후 WSL 터미널을 다시 열어주시면 해결됩니다."
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""

Pause-Script
