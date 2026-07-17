#==============================================================================
# DevTools2 Windows/WSL2 통합 자동 설치 마스터 스크립트 (setup-devtools2-wsl.ps1)
#
# 주요 기능:
#   1. Windows WSL2 가상 머신 생성 및 활성화 (0.setup-wsl.ps1)
#   2. WSL2 내부로 Linux 초기화 스크립트를 복사 및 실행하여 깃 자격증명 설정 및 클론 진행
#   3. WSL2 내부의 환경변수 설정, 핵심 개발 런타임 및 CLI 유틸리티 도구 일괄 자동 설치
#   4. Windows 호스트용 Ghostty 및 Zed 에디터 자동 설치 및 WSL2 설정 연동
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
            Write-Host "`r  [시간 초과] $Message (제한 시간 초과)                   " -ForegroundColor Red
            return $false
        }
        
        $success = & $Condition
        if ($success) {
            Write-Host "`r  [완료] $Message 완료!                               " -ForegroundColor Green
            return $true
        }
        
        $char = $spinner[$i % 4]
        Write-Host -NoNewline "`r  [$char] $Message..."
        Start-Sleep -Milliseconds 250
        $i++
    }
}

# ==============================================================================
# [Step 0] 관리자 권한 확인 및 재실행
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        # 원격 Raw 실행 시 UAC를 통해 원격 명령어를 새 창에서 관리자 권한으로 자동 재실행
        Write-Warn "관리자 권한이 필요합니다. UAC 승격 후 새 창에서 원격 설치를 계속합니다..."
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/setup-devtools2-wsl.ps1 | iex`"" -Verb RunAs
        exit
    } else {
        # 로컬 파일 실행 시에는 기존처럼 UAC 권한 승격 재실행
        Write-Warn "전체 환경 구축을 위해 관리자 권한으로 스크립트를 재실행합니다..."
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}

Clear-Host
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🌟 DevTools2 Windows & WSL2 통합 설치 마스터 자동화" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan

$isLocalMode = $false
if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
    $BaseDir = $PSScriptRoot
    $ToolsDir = Join-Path $BaseDir "devtools2"

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

if ($isLocalMode) {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupWslScript
} else {
    Write-Info "GitHub에서 WSL 설치 스크립트 다운로드 중..."
    $rawWslScript = Invoke-RestMethod "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/devtools2/0.setup-wsl.ps1"
    
    # 원격 실행 시 임시 파일로 저장 후 powershell.exe -File로 실행하여 exit 코드 확보
    $tempWslScriptFile = Join-Path $env:TEMP "temp_setup_wsl.ps1"
    $rawWslScript | Out-File -FilePath $tempWslScriptFile -Encoding UTF8 -Force
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempWslScriptFile
    if (Test-Path $tempWslScriptFile) { Remove-Item $tempWslScriptFile -Force }
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
        $char = $spinner[$sIdx % 4]
        Write-Host -NoNewline "`r  [$char] WSL2 배포판 준비 상태 조회 중..."
        Start-Sleep -Milliseconds 250
        $sIdx++
        if ($checkProc.HasExited) { break }
    }
    
    if ($checkProc.HasExited) {
        $testResult = Get-Content "$env:TEMP\wsl_ready_check.txt" -Raw 2>$null
        # ready 문자열이 포함되어 있으면 통과 (경고 메세지와 섞여 있어도 검출 가능)
        if ($testResult -match "ready") {
            $distroReady = $true
            Write-Host "`r  [완료] WSL2 배포판 접근 확인 완료: $wslDistro" -ForegroundColor Green
            Remove-Item "$env:TEMP\wsl_ready_check.txt" -Force -ErrorAction SilentlyContinue
            break
        }
    }
    Remove-Item "$env:TEMP\wsl_ready_check.txt" -Force -ErrorAction SilentlyContinue

    $retryCount++
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
Write-Host "===========================================================================" -ForegroundColor Yellow
Write-Host " 📢 WSL2 sudo 관리자 권한 실행을 위한 비밀번호 입력" -ForegroundColor Yellow
Write-Host "===========================================================================" -ForegroundColor Yellow
Write-Host "  WSL2 내부의 시스템 패키지(apt) 및 개발 환경 설정을 위해"
Write-Host "  Ubuntu 설치 시 생성했던 계정의 비밀번호 입력이 필요합니다."
Write-Host "===========================================================================" -ForegroundColor Yellow
Write-Host ""

$wslPassword = Read-Host "비밀번호(password)" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($wslPassword)
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
Write-Host ""

if ($isLocalMode) {
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
} else {
    Write-Info "WSL2 내부에서 curl을 통해 원격 0.init-devtools2.sh 직접 다운로드 중..."
    wsl -d $wslDistro -- curl -sSfL "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/devtools2/0.init-devtools2.sh" -o /tmp/0.init-devtools2.sh
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "원격 초기화 스크립트 다운로드에 실패했습니다. 네트워크 연결 상태를 확인해주세요."
        Pause-Script
        exit 1
    }
}

Write-Host ""
# WSL2 대화형 셸을 통해 sudo 권한으로 init 스크립트 실행 (입력받은 패스워드 주입)
# WSL의 /tmp에 임시 파일로 비밀번호 전달
# [중요] [System.Text.Encoding]::UTF8 은 BOM(EF BB BF)을 포함하므로 사용 금지
#        반드시 UTF8Encoding(false) 로 BOM 없이 써야 sudo 인증이 정상 작동함
$wslTmpForPw = "\\wsl.localhost\$wslDistro\tmp\.wsl_pw_tmp"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
# 비밀번호 뒤에 줄바꿈을 추가해야 sudo -S 가 안정적으로 읽음
[System.IO.File]::WriteAllText($wslTmpForPw, ($plainPassword + "`n"), $utf8NoBom)
$plainPassword = $null

# cat 파이프 방식으로 sudo -S에 비밀번호를 안전하게 전달
# 스크립트의 실행 결과 코드를 확보하고 임시 파일 삭제 후 최종 종료 코드를 마스터로 전달
wsl -d $wslDistro -- bash -c "cat /tmp/.wsl_pw_tmp | sudo -S bash /tmp/0.init-devtools2.sh; RC=`$?; rm -f /tmp/.wsl_pw_tmp; exit `$RC"

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

if ($isLocalMode) {
    Write-SubStep "▶ (1/2) WezTerm 설치 및 설정 연동 (로컬)"
    & $setupWeztermScript -WslDistro $wslDistro

    Write-SubStep "▶ (2/2) Zed 에디터 설치 및 설정 연동 (로컬)"
    & $setupZedScript -WslDistro $wslDistro
} else {
    Write-SubStep "▶ (1/2) WezTerm 설치 및 설정 연동 (온라인)"
    $rawWeztermScript = Invoke-RestMethod "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/devtools2/1.setup-wezterm.ps1"
    $weztermScriptBlock = [scriptblock]::Create($rawWeztermScript)
    & $weztermScriptBlock -WslDistro $wslDistro

    Write-SubStep "▶ (2/2) Zed 에디터 설치 및 설정 연동 (온라인)"
    $rawZedScript = Invoke-RestMethod "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/devtools2/2.setup-zed.ps1"
    $zedScriptBlock = [scriptblock]::Create($rawZedScript)
    & $zedScriptBlock -WslDistro $wslDistro
}

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
