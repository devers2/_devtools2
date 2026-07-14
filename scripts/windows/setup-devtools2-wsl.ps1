# ==============================================================================
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

# 재부팅 지점 처리 (종료 코드 3010)
if ($LASTEXITCODE -eq 3010) {
    Write-Warn "==========================================================================="
    Write-Warn " 🔄 WSL2 설치 완료를 위해 컴퓨터를 다시 시작(재부팅)해야 합니다."
    Write-Warn "==========================================================================="
    Write-Host ""
    Write-Host "  [재부팅 후 진행 방법]" -ForegroundColor Cyan
    Write-Host "  1. 컴퓨터를 다시 시작(재부팅)해 주세요." -ForegroundColor White
    Write-Host "  2. 로그인 후 자동으로 리눅스 설치 창이 열리면 사용자 이름과 비밀번호를 입력해 계정 생성을 완료합니다." -ForegroundColor White
    Write-Host "  3. 계정 생성이 완료되면, 아래 명령어를 PowerShell(관리자 권한)에 다시 입력하여" -ForegroundColor White
    Write-Host "     남은 환경 설정을 자동으로 이어 나가세요:" -ForegroundColor White
    Write-Host ""
    Write-Host "     irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/setup-devtools2-wsl.ps1 | iex" -ForegroundColor Green
    Write-Host ""
    Write-Warn "==========================================================================="
    Pause-Script
    exit 0
}

if ($LASTEXITCODE -ne 0) {
    Write-Fail "WSL 설치 스크립트 실행 중 에러가 발생했습니다 (종료 코드: $LASTEXITCODE)."
    Pause-Script
    exit 1
}

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
# [Step 1-후처리] WSL2 배포판 접근 가능 여부 확인 (신규 설치 후 등록 지연 대응)
# ==============================================================================
Write-Info "WSL2 배포판($wslDistro) 접근 가능 여부 확인 중..."
$maxRetry = 15
$retryCount = 0
$distroReady = $false

while ($retryCount -lt $maxRetry) {
    $testResult = wsl -d $wslDistro -- echo "ready" 2>$null
    if ($testResult -match "ready") {
        $distroReady = $true
        Write-Success "WSL2 배포판 접근 확인 완료: $wslDistro"
        break
    }

    # --name 플래그가 일부 Windows 버전에서 무시될 수 있으므로
    # 실제 등록된 배포판 이름과 비교하여 자동 보정
    $actualDistros = (wsl --list --quiet 2>$null) -replace "`0", "" |
        Where-Object { $_.Trim() -ne "" } |
        ForEach-Object { $_.Trim() }

    if ($actualDistros -and $actualDistros.Count -gt 0) {
        $actualName = $actualDistros[0]
        if ($actualName -ne $wslDistro) {
            Write-Warn "배포판이 '$actualName' 이름으로 등록되었습니다. (요청한 이름: $wslDistro)"
            Write-Warn "메타데이터를 실제 이름으로 자동 보정합니다."
            $wslDistro = $actualName
            # .devtools2 메타데이터 파일도 실제 이름으로 업데이트
            (Get-Content $devtools2File) -replace "^WSL_DISTRO=.*", "WSL_DISTRO=$wslDistro" |
                Set-Content $devtools2File -Encoding UTF8
 
            $testResult = wsl -d $wslDistro -- echo "ready" 2>$null
            if ($testResult -match "ready") {
                $distroReady = $true
                Write-Success "WSL2 배포판 접근 확인 완료 (보정된 이름): $wslDistro"
                break
            }
        }
    }

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
# WSL2 대화형 셸을 통해 sudo 권한으로 init 스크립트 실행
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
