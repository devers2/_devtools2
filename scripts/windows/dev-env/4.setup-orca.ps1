param(
    # WSL2 배포판 이름 (기본값: 첫 번째로 찾은 기본 배포판 자동 감지)
    [string]$WslDistro = ""
)

# ==============================================================================
# Orca GUI 클라이언트 설치 및 WSL2 헤드리스 서버 페어링 안내 스크립트 (4.setup-orca.ps1)
#
# 주요 기능:
#   1. winget 을 통해 Orca 데스크톱 앱을 자동 설치 (이미 설치되어 있으면 건너뜀)
#   2. WSL2 내부에서 'orca serve' 헤드리스 서버가 떠 있는지 확인/기동
#   3. Windows Orca 앱 ↔ WSL2 orca serve 페어링 방법 안내
#
# ------------------------------------------------------------------------------
# ⚠️ [Zed(3.setup-zed.ps1)와 구조가 다른 이유]
# Zed는 순수 에디터라 Windows 네이티브 앱이 WSL2의 파일을 UNC 경로로 열기만 하면 됩니다.
# 반면 Orca는 Claude Code/Codex/Gemini 같은 CLI 에이전트 "프로세스"를 직접 실행(spawn)해야
# 하는 오케스트레이터입니다. 그 CLI들은 전부 WSL2 내부에 설치되어 있어(npm i -g 등),
# Orca를 Windows 네이티브로만 설치하면 그 바이너리들을 실행할 방법이 없습니다(공식 문서에
# WSL 브릿지 기능 없음). 그래서 Orca 공식 "Remote Orca Servers" 모드를 그대로 씁니다:
#   - 에이전트 실행부(orca serve)는 CLI가 실제로 있는 WSL2에 헤드리스로 둡니다
#     (2.install-core-tools.sh 9단계에서 이미 설치/등록됨).
#   - 이 스크립트는 Windows에 "페어링만 하는" 가벼운 GUI 클라이언트를 설치합니다.
# 그래서 Zed처럼 settings.json을 WSL2 → Windows로 복사하는 단계가 없습니다 — 동기화할
# "설정 파일"이 아니라 페어링 상태(계정/키)라서 애초에 복사 대상이 아닙니다.
# ------------------------------------------------------------------------------
# ⚠️ [AI / 개발자 필독 - 설계 절대 원칙]
# 1. 100% 온라인 전용: 스크립트는 항상 GitHub main 브랜치 최신 원격 raw URL에서 호출됩니다.
# 2. 순수 UTF-8 NoBOM 보장: BOM(Byte Order Mark) 헤더를 절대 삽입하거나 조작하지 마십시오.
# 3. PS5.1 & PS7 무구분 호환: param() 구문은 반드시 스크립트 맨 첫 줄(Line 1)에 위치해야 합니다.
# 4. sh와의 관계: scripts/linux/dev-env/_colors.sh, _install-utils.sh 같은 bash 공용 헬퍼도
#    지금은 온라인 전용(로컬 파일을 보지 않음)입니다 — 다만 이유는 다릅니다. bash는 로컬을 먼저
#    봐도 인코딩상 안전하지만, 이 설치 스크립트들이 어차피 네트워크 없이는 동작 못 해서 로컬
#    폴백을 뺀 것뿐입니다(순수 단순화). 반면 ps1은 로컬 NoBOM 파일을 PowerShell 5.1이 직접
#    읽으면 한글 등이 깨질 위험이 있어 애초에 로컬을 볼 수조차 없습니다 — ps1은 위 1번 원칙대로
#    항상 온라인에서 새로 가져와 실행해야 합니다.
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

# 프로세스 종료 시까지 스피너를 표시해 대기하는 함수
function Wait-ProcessWithSpinner {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Message
    )

    $spinner = @([char]0x280B, [char]0x2819, [char]0x2839, [char]0x2838, [char]0x283C, [char]0x2834, [char]0x2826, [char]0x2827, [char]0x2807, [char]0x280F)
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
# Orca 자체 설치/페어링에는 관리자 권한이 꼭 필요하진 않지만, 이 저장소의 다른 Windows
# 컴패니언 스크립트(3.setup-zed.ps1 등)와 동일하게 독립 실행 시에도 안전하도록 맞춥니다.
# (마스터 스크립트를 통해 호출될 때는 이미 상위 프로세스가 관리자 권한이라 이 블록은 그냥 통과됩니다.)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host "[경고] 관리자 권한으로 스크립트를 재실행합니다..." -ForegroundColor Yellow
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/4.setup-orca.ps1 | iex`"" -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -WslDistro `"$WslDistro`"" -Verb RunAs
    }
    return
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🐋 Orca GUI 클라이언트 설치 및 WSL2 서버 페어링 스크립트" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan

# ==============================================================================
# [Step 1] WSL2 배포판 이름 자동 감지
# ==============================================================================
Write-Step "[Step 1] WSL2 배포판 감지"

if ($WslDistro -eq "") {
    $devtools2Dir  = Join-Path $env:USERPROFILE ".devtools2"
    $devtools2File = if (Test-Path $devtools2Dir -PathType Container) { Join-Path $devtools2Dir "wsl_distro" } else { $devtools2Dir }
    if (Test-Path $devtools2File) {
        $saved = Get-Content $devtools2File | Where-Object { $_ -match "^WSL_DISTRO=" } | Select-Object -First 1
        if ($saved) {
            $WslDistro = ($saved -split "=", 2)[1].Trim()
            Write-Host "  .devtools2 에서 읽은 배포판: $WslDistro" -ForegroundColor White
        }
    }

    if ($WslDistro -eq "") {
        $distroList = (wsl --list --quiet 2>$null) | Where-Object { $_ -ne "" }
        if ($distroList.Count -eq 0) {
            Write-Fail "WSL2 배포판을 찾을 수 없습니다. WSL2 를 먼저 설치해주세요."
            Read-Host "계속하려면 엔터를 누르세요"
            exit 1
        }
        $WslDistro = $distroList[0] -replace "`0", "" | ForEach-Object { $_.Trim() }
        Write-Host "  자동 감지된 배포판: $WslDistro" -ForegroundColor White
    }
}
else {
    Write-Host "  지정된 배포판: $WslDistro" -ForegroundColor White
}

# WSL2 쪽 Orca(orca serve 헤드리스)가 먼저 설치되어 있어야 이 스크립트의 나머지 단계가
# 의미가 있습니다(2.install-core-tools.sh 9단계). 없으면 뒤에서 "시작 시도 실패 → 존재하지도
# 않는 파일을 실행하라"는 혼란스러운 메시지로 이어지므로, 여기서 명확하게 먼저 안내합니다.
[string]$orcaAppImageCheck = (wsl -d $WslDistro -- bash -c "test -f /var/opt/_devtools2/modules/orca/orca-linux.AppImage -o -f /var/opt/_devtools2/modules/orca/orca-linux-arm64.AppImage && echo FOUND")
if ($orcaAppImageCheck.Trim() -ne "FOUND") {
    Write-Fail "WSL2 쪽에 Orca가 설치되어 있지 않습니다."
    Write-Info "  먼저 WSL2에서 2.install-core-tools.sh 를 실행해 Orca 설치 질문에 'y'로 답해주세요"
    Write-Info "  (보통은 setup-devtools2-wsl.ps1 마스터 스크립트를 통해 자동으로 순서대로 진행됩니다)."
    Read-Host "계속하려면 엔터를 누르세요"
    exit 1
}

# ==============================================================================
# [Step 2] Orca 데스크톱 앱 설치 (winget: StablyAI.Orca)
# ==============================================================================
Write-Step "[Step 2] Orca 데스크톱 앱(GUI 클라이언트) 설치"

try {
    Write-Host "  winget 패키지 매니저 소스를 확인하는 중..." -ForegroundColor White
    $pSrc = Start-Process winget -ArgumentList "source update" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\orca_source_update.log" -RedirectStandardError "$env:TEMP\orca_source_error.log" -ErrorAction SilentlyContinue
    Wait-ProcessWithSpinner -Process $pSrc -Message "winget 소스 업데이트 중"
    Remove-Item "$env:TEMP\orca_source_update.log", "$env:TEMP\orca_source_error.log" -Force -ErrorAction SilentlyContinue
} catch {}

$orcaInstalled = $false
try {
    $orcaPaths = @(
        "$env:LOCALAPPDATA\Programs\orca\Orca.exe",
        "$env:LOCALAPPDATA\Programs\Orca\Orca.exe",
        "$env:ProgramFiles\Orca\Orca.exe"
    )
    foreach ($p in $orcaPaths) {
        if (Test-Path $p) { $orcaInstalled = $true; break }
    }

    if (-not $orcaInstalled) {
        $wgList = winget list --id StablyAI.Orca 2>$null
        if ($LASTEXITCODE -eq 0 -and ($wgList -join "") -match "Orca") { $orcaInstalled = $true }
    }
} catch {}

if ($orcaInstalled) {
    Write-Skip "Orca 데스크톱 앱이 이미 설치되어 있습니다."
}
else {
    Write-Host "  Orca 데스크톱 앱을 winget으로 설치합니다..." -ForegroundColor White
    $p = Start-Process winget -ArgumentList "install --id StablyAI.Orca --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\orca_install.log" -RedirectStandardError "$env:TEMP\orca_install_err.log"
    Wait-ProcessWithSpinner -Process $p -Message "Orca 데스크톱 앱 설치 진행 중"
    # -1978335189 = APPINSTALLER_CLI_ERROR_NO_APPLICABLE_UPGRADE (이미 최신 버전 설치됨)
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq -1978335189) {
        Write-Success "Orca 데스크톱 앱 설치/확인 완료"
    } else {
        Write-Warn "Orca winget 설치 실패(종료 코드: $($p.ExitCode)). 수동 설치: https://www.onorca.dev/"
    }
    Remove-Item "$env:TEMP\orca_install.log", "$env:TEMP\orca_install_err.log" -Force -ErrorAction SilentlyContinue
}

# ==============================================================================
# [Step 3] WSL2 헤드리스 orca serve 상태 확인
#
# 실제 설치/자동 실행 등록은 2.install-core-tools.sh 9단계(WSL2 분기)에서 이미
# 처리됩니다. 여기서는 그 결과가 살아있는지만 확인하고, 죽어 있으면 한 번 더 살립니다.
# ==============================================================================
Write-Step "[Step 3] WSL2 'orca serve' 헤드리스 서버 상태 확인"

[string]$orcaServeStatus = (wsl -d $WslDistro -- bash -c "systemctl --user is-active orca-serve.service 2>/dev/null")
$orcaServeStatus = $orcaServeStatus.Trim()

if ($orcaServeStatus -eq "active") {
    Write-Success "WSL2 'orca serve'가 이미 실행 중입니다 (포트 6768)."
}
else {
    Write-Info "WSL2 'orca serve'가 실행 중이 아닙니다. 시작을 시도합니다..."
    $startResult = wsl -d $WslDistro -- bash -c "systemctl --user start orca-serve.service 2>&1"
    Start-Sleep -Seconds 1
    [string]$recheck = (wsl -d $WslDistro -- bash -c "systemctl --user is-active orca-serve.service 2>/dev/null")
    $recheck = $recheck.Trim()
    if ($recheck -eq "active") {
        Write-Success "WSL2 'orca serve' 시작 완료 (포트 6768)."
    } else {
        Write-Warn "WSL2 'orca serve'를 systemd로 시작하지 못했습니다(WSL2 systemd 미활성 환경일 수 있음)."
        Write-Info "  WSL2 터미널에서 직접 실행해주세요:"
        Write-Info "    `$DEVTOOLS2/modules/orca/orca-serve-wrapper.sh &"
    }
}

# ==============================================================================
# [Step 4] Windows Orca ↔ WSL2 orca serve 페어링
#
# ⚠️ Orca 공식 문서는 127.0.0.1을 "원격 클라이언트 페어링에 쓰지 말라"고 명시적으로
# 경고합니다. 대신 2.install-core-tools.sh가 WSL2 자체 IP로 만들어 둔 페어링 링크
# (orca://pair?...)를 그대로 읽어와 시도합니다.
#
# ⚠️ 헤드리스 Linux orca serve는 페어링 코드가 아예 출력되지 않는 알려진 미해결
# 버그가 있어(stablyai/orca#9759) 링크를 못 찾을 수 있습니다 — 그 경우 WSL2 IP로
# 수동 연결하는 방법을 안내합니다. orca:// 링크를 자동으로 열어도 Windows에 등록된
# 핸들러가 없으면 조용히 무시될 수 있으므로, 링크 자체도 항상 화면에 그대로 남깁니다.
# ==============================================================================
Write-Step "[Step 4] Windows Orca 앱 ↔ WSL2 orca serve 페어링"

[string]$pairingLink = (wsl -d $WslDistro -- bash -c "cat /var/opt/_devtools2/data/orca-pairing-link.txt 2>/dev/null")
$pairingLink = $pairingLink.Trim()
if ([string]::IsNullOrWhiteSpace($pairingLink)) {
    Write-Info "저장된 페어링 링크가 없어 저널에서 즉석 조회를 한 번 더 시도합니다..."
    [string]$pairingLink = (wsl -d $WslDistro -- bash -c "journalctl --user -u orca-serve.service --no-pager -n 80 2>/dev/null | grep -oE 'orca://pair[^[:space:]]*' | tail -1")
    $pairingLink = $pairingLink.Trim()
}

$wslIp = (wsl -d $WslDistro -- hostname -I 2>$null)
if ($wslIp) { $wslIp = ($wslIp -split '\s+')[0].Trim() }

if (-not [string]::IsNullOrWhiteSpace($pairingLink)) {
    Write-Success "페어링 링크를 찾았습니다."
    Write-Host "    $pairingLink" -ForegroundColor Yellow
    Write-Host ""
    Write-Info "Orca 앱으로 자동 페어링을 시도합니다(등록된 orca:// 핸들러가 없으면 조용히 무시됩니다)..."
    try {
        Start-Process $pairingLink -ErrorAction Stop
        Write-Success "Orca 앱을 열었습니다. 자동으로 페어링됐는지 앱에서 확인해주세요."
    } catch {
        Write-Warn "자동 실행에 실패했습니다."
    }
    Write-Info "자동으로 안 됐다면 위 링크를 Orca 앱의 'Settings → Remote Orca Servers → Add Server'에 직접 붙여넣어 주세요."
} else {
    Write-Warn "페어링 링크를 자동으로 찾지 못했습니다(헤드리스 Linux의 알려진 미해결 버그일 수 있음)."
    Write-Info "  참고: https://github.com/stablyai/orca/issues/9759"
    Write-Host ""
    Write-Info "  수동으로 연결하려면 Orca 앱에서 'Settings → Remote Orca Servers → Add Server'로 이동해"
    if ($wslIp) {
        Write-Info "  아래 주소를 직접 추가해보세요 (127.0.0.1은 Orca가 원격 클라이언트용으로 권장하지 않습니다):"
        Write-Host "    $wslIp`:6768" -ForegroundColor Yellow
        Write-Info "  ※ WSL2 IP는 재부팅마다 바뀔 수 있습니다 — 연결이 끊기면 이 스크립트를 다시 실행해 최신 IP를 확인하세요."
    } else {
        Write-Info "  WSL2 IP 확인에 실패했습니다. WSL2 터미널에서 'hostname -I' 로 직접 확인해주세요."
    }
}

# ==============================================================================
# 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 Orca 설치 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  이후에는 Windows Orca 앱이 WSL2에서 실행 중인 claude/codex/gemini 등" -ForegroundColor Gray
Write-Host "  CLI 에이전트를 그대로 오케스트레이션합니다(페어링이 아직이라면 위 안내 참고)." -ForegroundColor Gray
Write-Host ""
Write-Info "  참고: 계정 인증(예: Claude/Codex 로그인)은 WSL2 쪽에서 등록합니다:"
Write-Info "    wsl -d $WslDistro -- /var/opt/_devtools2/modules/orca/orca account add --agent claude"
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
