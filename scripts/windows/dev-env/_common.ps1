# ==============================================================================
# _common.ps1 — Windows dev-env 스크립트 공용 콘솔 출력/대기 헬퍼
# (scripts/linux/dev-env/_common.sh 의 PowerShell 대응 버전)
#
# [사용법 — 항상 온라인에서 받아 dot-source]
#   $headers = @{ 'Cache-Control' = 'no-cache, no-store, must-revalidate'; 'Pragma' = 'no-cache' }
#   $colorsContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/_common.ps1" -Headers $headers -ErrorAction Stop
#   . ([scriptblock]::Create($colorsContent))
#
# [배경]
# Write-Step/Write-Success/Pause-Script/Wait-WithSpinner 등이 0.setup-wsl.ps1,
# 1.setup-autohotkey.ps1, 2.setup-windows-terminal.ps1, 3-1.setup-vscode.ps1,
# 3-2.setup-zed.ps1, 3-3.setup-orca.ps1 파일에 거의 동일하게 복붙되어 있었습니다. bash 쪽은
# _common.sh 라는 공용 라이브러리로 이미 이 문제를 해결했는데(온라인 source),
# PowerShell 쪽엔 대응 파일이 없어서 한쪽에서 고친 버그(Pause-Script 문구 등)가
# 다른 사본에는 전파되지 않는 드리프트가 실제로 발생했습니다(실측 확인).
# 이 파일이 그 공용 버전입니다 — ps1 원칙(항상 온라인 최신본, NoBOM, param()은
# 없음 — 이 파일은 함수 정의만 있어 param 블록이 필요 없음)을 그대로 따릅니다.
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
    # 기본 메시지: 이 함수를 부르는 호출부는 대부분 곧이어 exit 하는 상황이라
    # "계속하려면"이 아니라 "종료합니다"가 정확합니다(0.setup-wsl.ps1에서 실측 확인 —
    # 8곳 호출부 전부 Pause-Script 바로 다음 줄이 exit였음). 정말로 스크립트를 계속
    # 진행해야 하는 드문 호출부가 있다면 그때만 -Message 로 다른 문구를 넘기면 됩니다.
    param([string]$Message = "엔터(Enter) 키를 누르면 종료합니다")
    Write-Host ""
    Write-Host "👉 ${Message}: " -ForegroundColor Yellow -NoNewline
    [void][System.Console]::ReadLine()
}

# Yes/No 대화형 확인 프롬프트 공용 헬퍼 (bash _common.sh 의 prompt_confirm 대응)
# 사용법: if (Prompt-Confirm "👉 AutoHotKey를 설치하시겠습니까?" "Y") { ... }
function Prompt-Confirm {
    param(
        [string]$Message,
        [string]$Default = "N"
    )
    Write-Host ""
    if ($Default -eq "Y" -or $Default -eq "y") {
        Write-Host "$Message [" -ForegroundColor Yellow -NoNewline
        Write-Host "Y" -ForegroundColor Green -NoNewline
        Write-Host "/n]: " -ForegroundColor Yellow -NoNewline
        $ans = Read-Host
        if ([string]::IsNullOrWhiteSpace($ans)) { return $true }
        return ($ans -match '^[Yy]')
    } else {
        Write-Host "$Message [y/" -ForegroundColor Yellow -NoNewline
        Write-Host "N" -ForegroundColor Green -NoNewline
        Write-Host "]: " -ForegroundColor Yellow -NoNewline
        $ans = Read-Host
        if ([string]::IsNullOrWhiteSpace($ans)) { return $false }
        return ($ans -match '^[Yy]')
    }
}

# 프로세스 종료 시까지 스피너를 표시해 대기 (타임아웃 없음 — 프로세스가 끝날 때까지 무조건 대기)
function Wait-ProcessWithSpinner {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Message
    )
    $spinner = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $spinIdx = 0
    Write-Host "  $Message" -ForegroundColor Cyan
    while (-not $Process.HasExited) {
        $char = $spinner[$spinIdx]
        Write-Host -NoNewline "`r  [$char] 처리 중...   " -ForegroundColor Cyan
        $spinIdx = ($spinIdx + 1) % $spinner.Count
        Start-Sleep -Milliseconds 150
    }
    Write-Host "`r  [완료] $Message 완료!   " -ForegroundColor Green
}

# 조건(scriptblock)이 참이 될 때까지 스피너를 표시해 대기 (타임아웃 지원, 초과 시 $false 반환)
# ⚠️ 호출부는 반드시 반환값을 확인해야 합니다 — 확인하지 않으면 타임아웃 후에도 마치
# 정상 완료된 것처럼 다음 단계로 조용히 넘어갈 수 있습니다(0.setup-wsl.ps1에서 실측 확인:
# PowerShell은 아직 안 끝난 프로세스의 .ExitCode를 읽어도 예외 없이 빈 값만 반환하므로
# "-eq 3010" 등의 비교가 조용히 false가 되어버림).
function Wait-WithSpinner {
    param(
        [string]$Message,
        [scriptblock]$Condition,
        [int]$MaxTimeoutSeconds = 300
    )
    $spinner = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $spinIdx = 0
    Write-Host "  $Message" -ForegroundColor Cyan
    $startTime = Get-Date
    while ($true) {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -gt $MaxTimeoutSeconds) {
            Write-Host "`r  [시간 초과] $Message (제한 시간 초과)   " -ForegroundColor Red
            return $false
        }
        $done = [bool](& $Condition)
        if ($done) {
            Write-Host "`r  [완료] $Message 완료!   " -ForegroundColor Green
            return $true
        }
        $char = $spinner[$spinIdx % $spinner.Count]
        Write-Host -NoNewline "`r  [$char] 처리 중...   " -ForegroundColor Cyan
        Start-Sleep -Milliseconds 150
        $spinIdx++
    }
}
