# ==============================================================================
# DevTools2 Windows/WSL2 통합 자동 설치 마스터 스크립트 (setup-devtools2-wsl.ps1)
#
# 주요 기능:
#   1. Windows WSL2 가상 머신 생성 및 활성화 (0.setup-wsl.ps1)
#   2. WSL2 내부로 Linux 초기화 스크립트를 실행하여 깃 자격증명 설정 및 클론 진행
#   3. WSL2 내부의 환경변수 설정, 핵심 개발 런타임 및 CLI 유틸리티 도구 일괄 자동 설치
#   4. Windows 호스트용 AutoHotkey, Windows Terminal, VS Code, Zed, Orca 자동 설치 및 설정 연동
#
# ------------------------------------------------------------------------------
# ⚠️ [AI / 개발자 필독 - 설계 절대 원칙]
# 1. 100% 온라인 전용: 서브스크립트는 무조건 GitHub main 브랜치 원격 raw URL에서 가져옵니다.
#    로컬 파일 실행 분기($isLocalMode 등)를 다시 추가하지 마십시오.
# 2. 순수 UTF-8 NoBOM 보장: BOM(Byte Order Mark) 헤더를 절대 삽입하거나 조작하지 마십시오.
#    BOM 덧붙이기/보정 편법 코드를 작성하지 마십시오. 스크립트는 항상 순수 NoBOM으로 유지되어야 합니다.
# 3. PS5.1 & PS7 무구분 호환: param() 구문은 항상 스크립트 맨 첫 줄(Line 1)에 위치시켜
#    순정 Windows PowerShell 5.1 과 PowerShell 7 모두에서 BOM 없이도 문법 에러 없이 작동합니다.
# 4. sh와의 관계: scripts/linux/dev-env/_colors.sh, _install-utils.sh 같은 bash 공용 헬퍼도
#    지금은 온라인 전용(로컬 파일을 보지 않음)입니다 — 다만 이유는 다릅니다. bash는 로컬을 먼저
#    봐도 인코딩상 안전하지만, 이 설치 스크립트들이 어차피 네트워크 없이는 동작 못 해서 로컬
#    폴백을 뺀 것뿐입니다(순수 단순화). 반면 ps1은 로컬 NoBOM 파일을 PowerShell 5.1이 직접
#    읽으면 한글 등이 깨질 위험이 있어 애초에 로컬을 볼 수조차 없습니다 — ps1은 위 1번 원칙대로
#    항상 온라인에서 새로 가져와 실행해야 합니다.
# ------------------------------------------------------------------------------
#
# 사용 방법:
#   PowerShell (PS 5.1 또는 PS 7)을 관리자 권한으로 열고 실행:
#   .\setup-devtools2-wsl.ps1
# ==============================================================================

# --- 한글 깨짐 방지: 출력 인코딩을 UTF-8 NoBOM 으로 설정
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# --- 윈도우 PowerShell 기본 파란색 프로그레스바 팝업 끄기 (텍스트 깨짐 및 커서 겹침 방지)
$ProgressPreference = 'SilentlyContinue'

# ==============================================================================
# 헬퍼 함수
# ==============================================================================
# Write-Step/Write-Success/Pause-Script/Wait-WithSpinner 등은 여러 ps1 파일에
# 거의 동일하게 복붙되어 있던 걸 _common.ps1(scripts/windows/dev-env/_common.ps1)
# 공용 파일로 통합했습니다(bash의 _colors.sh와 동일한 패턴).
# 항상 온라인 최신본을 dot-source(다른 스크립트 스트리밍 실행과 동일한 캐시 우회 원칙).
$_localCommon = Join-Path $PSScriptRoot "dev-env\_common.ps1"
if (Test-Path $_localCommon) {
    . $_localCommon
} else {
    $_commonHeaders = @{ 'Cache-Control' = 'no-cache, no-store, must-revalidate'; 'Pragma' = 'no-cache' }
    $_commonContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/_common.ps1" -Headers $_commonHeaders -ErrorAction Stop
    . ([scriptblock]::Create($_commonContent))
}

# 세션 한정 마우스 클릭 멈춤(프리징) 방지: QuickEdit 모드 안전 비활성화 (스크립트 종료/Ctrl+C 시 자동 복원)
Disable-ConsoleQuickEdit | Out-Null

# 심볼릭 링크 헬퍼 3종(Remove-FileOrSymlink, New-SymlinkIdempotent, Backup-AndLink)은
# _common.ps1 로 일원화되어 공용으로 제공됩니다.



# GitHub raw URL에서 PowerShell 스크립트를 문자열로 받아 즉시 실행하는 헬퍼
#
# [설계 원칙]
# ① 캐시 방지: Cache-Control/Pragma 헤더로 CDN·프록시 캐시를 강제 우회
#              → 항상 GitHub main 브랜치 최신 내용이 실행됨을 보장
# ② 디스크를 거치지 않음: Invoke-WebRequest -OutFile 로 임시 파일에 저장했다가
#              -File 로 실행하면, pwsh(PS7) 없는 순정 Windows에서 powershell.exe(PS5.1)가
#              NoBOM 한글 파일을 잘못된 코드페이지로 읽어 파싱이 깨지는 것을 실측으로 확인했다
#              (irm | iex 가 안전한 것과 동일한 이유 — Invoke-RestMethod로 받은 문자열을
#              재인코딩하면 원본과 바이트 단위로 동일함을 확인함). 그래서 파일로 저장하지 않고
#              문자열로 받아 스크립트블록으로 바로 실행한다 — 임시 파일 생성/정리,
#              pwsh 설치 여부 판단, 외부 프로세스 실행 분기가 전부 필요 없어진다.
# ③ 인자는 반드시 해시테이블로: 배열을 @()로 스플래팅하면 "-Name" 문자열이 파라미터
#              이름으로 재해석되지 않고 그냥 위치 인자 값으로 들어가버리는 것을 실측으로
#              확인했다(예: -WslDistro 값이 통째로 누락됨). 해시테이블 스플래팅만 이름 있는
#              파라미터로 정확히 바인딩된다.
function Invoke-RemotePsScript {
    param(
        [string]$Url,
        [hashtable]$Arguments = @{}
    )
    $headers = @{
        'Cache-Control' = 'no-cache, no-store, must-revalidate'
        'Pragma'        = 'no-cache'
    }
    $content = Invoke-RestMethod -Uri $Url -Headers $headers -ErrorAction Stop
    $scriptBlock = [scriptblock]::Create($content)
    & $scriptBlock @Arguments
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
        # %TEMP% 임시 파일 사용 금지 지침 준수: 순수 메모리 상에서 Base64 EncodedCommand 로 UAC 승격
        Write-Warn "관리자 권한이 필요합니다. UAC 승격 후 원격 설치를 계속합니다..."
        $onlineCmd = "irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/setup-devtools2-wsl.ps1 | iex"
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($onlineCmd)
        $encodedCmd = [Convert]::ToBase64String($bytes)
        $psExe = if ($pwshPath -and -not $isStorePwsh) { $pwshPath } else { 'powershell.exe' }
        # ⚠️ conhost.exe로 감싸서 -Verb RunAs 승격 시도 금지 — "액세스 거부"로 실패함(실측).
        #   (목적: WT 자기파괴 방지였음 — 2.setup-windows-terminal.ps1의 WT_SESSION 감지로만 방어 중)
        Start-Process $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCmd" -Verb RunAs
        exit
    } else {
        # ── 로컬 파일 실행 모드 ────────────────────────────────────────────────
        # PS7(pwsh) 또는 순정 PS5.1(powershell.exe) 모두 지원
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
            # ⚠️ conhost.exe로 감싸서 -Verb RunAs 승격 시도 금지 — "액세스 거부"로 실패함(실측).
            #   (목적: WT 자기파괴 방지였음 — 2.setup-windows-terminal.ps1의 WT_SESSION 감지로만 방어 중)
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

# 로컬 파일 실행 감지 안내 (irm | iex 로 실행하면 $PSCommandPath 가 비어있어 이 블록 자체가 스킵됨)
if (-not [string]::IsNullOrEmpty($PSCommandPath)) {
    Write-Host ""
    Write-Host "  [안내] 로컬 파일 실행이 감지되었습니다." -ForegroundColor DarkYellow
    Write-Host "         서브스크립트는 로컬 파일을 사용하지 않고, 항상 GitHub main 브랜치" -ForegroundColor DarkYellow
    Write-Host "         최신 버전을 온라인에서 직접 다운로드하여 실행합니다." -ForegroundColor DarkYellow
    Write-Host "         또한 순정 Windows PowerShell 5.1(pwsh 미설치)에서 이 파일을 로컬로" -ForegroundColor DarkYellow
    Write-Host "         저장해 실행하면 한글 텍스트 때문에 파싱 자체가 실패할 수 있습니다." -ForegroundColor DarkYellow
    Write-Host "         가능하면 아래처럼 온라인에서 바로 실행하는 것을 권장합니다:" -ForegroundColor DarkYellow
    Write-Host "           irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/setup-devtools2-wsl.ps1 | iex" -ForegroundColor Cyan
    Write-Host ""
}

# ==============================================================================
# [사전 정리] AutoHotkey 프로세스 종료 및 구형 Startup 항목 제거
# ==============================================================================
# 최초 설치 또는 재설치 시, WSL 이 아직 없는 상태에서 이전 설치로 생긴
# Startup 폴더의 .lnk/.ahk 바로가기가 오류 팝업을 일으킬 수 있으므로
# Step 1 (WSL 설치) 이전에 먼저 정리합니다.

# 대상 WSL 배포판 이름 (코드 전체에서 고정될 상수 미리 선언)
$wslDistro = "devtools2"
$_startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

# 1. devtools2 관련 AutoHotkey 인스턴스만 선별적으로 종료 (다른 개인용 AHK 프로세스 보존)
$_wslPattern   = "wsl\.localhost\\$wslDistro"
$_localPattern = "_devtools2"
try {
    Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" -ErrorAction SilentlyContinue |
        Where-Object {
            $cmd = $_.CommandLine
            ($cmd -match $_wslPattern) -or ($cmd -match $_localPattern)
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
} catch {}

# 2. Startup 폴더에서 devtools2 관련 바로가기(.lnk) 및 .ahk 파일만 선별적으로 제거
$_wshShell = New-Object -ComObject WScript.Shell
Get-ChildItem -Path $_startupDir -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $sc = $_wshShell.CreateShortcut($_.FullName)
        $combined = "$($sc.Arguments) $($sc.TargetPath)"
        if (($combined -match $_wslPattern) -or ($combined -match $_localPattern) -or ($_.Name -like "*DevTools2-Hotkey*") -or ($_.Name -like "*Keyboard-Remap*")) {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Info "devtools2 AHK 바로가기 제거: $($_.Name)"
        }
    } catch {}
}
Get-ChildItem -Path $_startupDir -Filter "*devtools2*.ahk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Write-Info "AutoHotkey Startup 항목 사전 정리 완료 (개인 AHK 스크립트 보존)"

# ── 커밋 고정(Commit Pinning): 설치 도중 main 브랜치 푸시로 인한 스크립트 불일치 방지 ──
if (-not $env:DT2_REF) {
    try {
        $apiResp = Invoke-RestMethod -Uri "https://api.github.com/repos/devers2/_devtools2/commits/main" -Headers @{ "User-Agent" = "PowerShell" } -TimeoutSec 10 -ErrorAction Stop
        if ($apiResp -and $apiResp.sha) {
            $env:DT2_REF = $apiResp.sha
            Write-Info "설치 커밋 고정 완료: $($env:DT2_REF)"
        } else {
            $env:DT2_REF = "main"
        }
    } catch {
        $env:DT2_REF = "main"
        Write-Warn "GitHub API 커밋 SHA 조회 실패 → 'main' 브랜치 기본값 사용"
    }
}
$DT2_REF = $env:DT2_REF

# 서브스크립트 GitHub raw URL 기준 상수 (고정된 커밋 SHA 기반)
$RAW_WIN   = "https://raw.githubusercontent.com/devers2/_devtools2/$DT2_REF/scripts/windows/dev-env"
$RAW_LINUX = "https://raw.githubusercontent.com/devers2/_devtools2/$DT2_REF/scripts/linux/dev-env"

Write-Info "서브스크립트는 고정된 커밋($($DT2_REF.Substring(0, [Math]::Min(7, $DT2_REF.Length)))) 기준으로 원격 스트리밍 실행됩니다."

# ==============================================================================
# [Step 0-1] 순정 Windows 감지: WSL2 필수 선택적 기능 활성화 및 점검
# ==============================================================================
$_wslResumeFlagFile = "$env:TEMP\.devtools2_wsl_resume"

# 1. Windows 필수 선택적 기능 상태 확인 헬퍼
function Get-IsFeatureEnabled {
    param([string]$FeatureName)
    try {
        $feat = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        return ($null -ne $feat -and $feat.State -eq 'Enabled')
    } catch {
        return $false
    }
}

$wslFeatEnabled = Get-IsFeatureEnabled "Microsoft-Windows-Subsystem-Linux"
$vmFeatEnabled  = Get-IsFeatureEnabled "VirtualMachinePlatform"

# 필수 선택적 기능 중 하나라도 비활성화되어 있고 재개 플래그도 없는 경우 활성화 수행
if (-not ($wslFeatEnabled -and $vmFeatEnabled) -and -not (Test-Path $_wslResumeFlagFile)) {
    Write-Step "[Step 0-1] WSL2 필수 선택적 기능 활성화"
    Write-Warn "WSL2 실행에 필요한 Windows 선택적 기능이 비활성화되어 있습니다."
    Write-Info "선택적 기능(VirtualMachinePlatform 및 Microsoft-Windows-Subsystem-Linux)을 활성화합니다..."

    if (-not $wslFeatEnabled) {
        $p1 = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart -WarningAction SilentlyContinue | Out-Null`"" -PassThru -NoNewWindow
        Wait-WithSpinner -Message "Microsoft-Windows-Subsystem-Linux 기능 활성화" -Condition { $p1.HasExited }
    }
    if (-not $vmFeatEnabled) {
        $p2 = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart -WarningAction SilentlyContinue | Out-Null`"" -PassThru -NoNewWindow
        Wait-WithSpinner -Message "VirtualMachinePlatform 기능 활성화" -Condition { $p2.HasExited }
    }

    # wsl --install 로 WSL2 커널 및 기본 컴포넌트 설치 (배포판 없이)
    $pKernel = Start-Process wsl.exe -ArgumentList "--install --no-distribution" -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\wsl_kernel_install.txt" -ErrorAction SilentlyContinue
    Wait-WithSpinner -Message "WSL2 커널 컴포넌트 확인/설치" -Condition { $pKernel.HasExited }
    Remove-Item "$env:TEMP\wsl_kernel_install.txt" -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "===========================================================================" -ForegroundColor Yellow
    Write-Host "  ✅ WSL2 필수 선택적 기능 활성화 완료!" -ForegroundColor Green
    Write-Host "  🔄 변경 사항을 적용하려면 Windows를 재시작해야 합니다." -ForegroundColor Yellow
    Write-Host "===========================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  재시작 후 이 스크립트를 다시 실행하면 WSL2 배포판 설치부터 자동으로 이어서 진행됩니다." -ForegroundColor White
    Write-Host ""

    # 재개 플래그 파일 저장 (재시작 후 이어서 진행하기 위해, UTF-8 NoBOM 보장)
    [System.IO.File]::WriteAllText($_wslResumeFlagFile, (Get-Date).ToString(), [System.Text.UTF8Encoding]::new($false))

    if (Prompt-Confirm "👉 지금 바로 컴퓨터를 재시작하시겠습니까?" "Y") {
        Write-Info "컴퓨터를 재시작합니다..."
        Start-Sleep -Seconds 2
        Restart-Computer -Force
        exit 0
    } else {
        Write-Warn "재시작을 건너뛰었습니다. 수동으로 컴퓨터를 재시작한 후 이 스크립트를 다시 실행해 주세요."
        Write-Host ""
        Write-Host "   irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/setup-devtools2-wsl.ps1 | iex" -ForegroundColor Cyan
        Write-Host ""
        Pause-Script
        exit 0
    }
}

# 재개 플래그가 있으면 이전 실행에서 WSL 기능을 설치하고 재부팅한 것이므로 바로 진행
if (Test-Path $_wslResumeFlagFile) {
    Write-Info "재시작 후 설치 재개 감지. WSL2 배포판 설치를 이어서 진행합니다."
    Remove-Item $_wslResumeFlagFile -Force -ErrorAction SilentlyContinue

    # WSL2를 기본 버전으로 설정
    wsl --set-default-version 2 2>$null | Out-Null
}

# ==============================================================================
# [Step 1] Windows WSL2 가상 머신 생성 및 활성화
# ==============================================================================
Write-Step "[Step 1] WSL2 가상 머신 인스턴스 생성"

Write-Info "GitHub에서 WSL 설치 스크립트를 다운로드하여 실행합니다..."
Invoke-RemotePsScript -Url "$RAW_WIN/0.setup-wsl.ps1"

# 대상 WSL2 배포판 이름은 'devtools2'로 고정입니다.
$wslDistro = "devtools2"
Write-Info "대상 WSL2 배포판: $wslDistro"

# ==============================================================================
# [Step 1-후처리] WSL2 배포판 접근 가능 여부 확인 (신규 설치 후 등록 지연 대응)
# ==============================================================================
Write-Info "WSL2 배포판($wslDistro) 접근 가능 여부 확인 중..."
$distroReady = Wait-WithSpinner -Message "WSL2 배포판($wslDistro) 준비 확인" -Condition {
    $out = (wsl -d $wslDistro -- echo ready 2>$null) | Out-String
    ($out -replace "`0","").Trim() -eq "ready"
} -MaxTimeoutSeconds 60
if ($distroReady) {
    Write-Success "WSL2 배포판 접근 확인 완료: $wslDistro"
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

# WSL2 기본 사용자 계정 확인 (0.init-devtools2.sh에 SUDO_USER로 전달하여 소유권 설정 및 설치용 임시 권한 부여)
$wslUser = ((wsl -d $wslDistro -- whoami 2>$null) -replace "`0", "").Trim()
if ([string]::IsNullOrEmpty($wslUser) -or $wslUser -eq "root") {
    # /etc/wsl.conf 의 [user] default 설정값 조회 시도 (재기동 지연 대응)
    $confUser = ((wsl -d $wslDistro -u root -- bash -c "grep -E '^\s*default\s*=' /etc/wsl.conf 2>/dev/null | cut -d'=' -f2" 2>$null) -replace "`0", "").Trim()
    if (-not [string]::IsNullOrEmpty($confUser) -and $confUser -ne "root") {
        $wslUser = $confUser
    } elseif ([string]::IsNullOrEmpty($wslUser)) {
        $wslUser = $env:USERNAME.ToLower()
    }
}
Write-Info "WSL2 사용자 계정 감지: $wslUser"

# 임시 권한 회수 헬퍼 함수 (설치 완료 또는 비정상 중단 시 /etc/sudoers.d/$wslUser 회수)
function Revoke-WslTempSudo {
    if (-not [string]::IsNullOrEmpty($wslUser)) {
        $check = ((wsl -d $wslDistro -u root -- bash -c "test -f /etc/sudoers.d/$wslUser && echo EXISTS || echo NONE" 2>$null) -replace "`0", "").Trim()
        wsl -d $wslDistro -u root -- bash -c "rm -f /etc/sudoers.d/$wslUser /tmp/.wsl_pw_tmp" 2>$null
        if ($check -eq "EXISTS") {
            Write-Success "WSL2 임시 passwordless sudo 권한($wslUser)을 안전하게 회수했습니다. (이후 sudo 사용 시 비밀번호 필요)"
        }
    }
}

# WSL2 저장소 초기화 및 깃 클론 (0.init-devtools2.sh 실행)
# ── Windows 호스트에서는 'wsl -u root'로 비밀번호 입력 없이 안전하게 관리자 권한 실행 가능.
# ── 평문 비밀번호 파일(/tmp/.wsl_pw_tmp) 불필요 및 SUDO_USER 환경변수로 대상 사용자 전달
Write-SubStep "▶ WSL2 저장소 초기화 및 Git 클론 실행 (0.init-devtools2.sh)"
$wslTmpScript = "/tmp/_dt2_init.sh"

wsl -d $wslDistro -- bash -c "curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' '$RAW_LINUX/0.init-devtools2.sh' -o $wslTmpScript && chmod +x $wslTmpScript"

# root 권한으로 초기화 스크립트 실행 (SUDO_USER=$wslUser, DT2_REF=$DT2_REF 전달)
wsl -d $wslDistro -u root -- env SUDO_USER=$wslUser DT2_REF=$DT2_REF bash $wslTmpScript
$initExit = $LASTEXITCODE
wsl -d $wslDistro -u root -- rm -f $wslTmpScript /tmp/.wsl_pw_tmp 2>$null

if ($initExit -ne 0) {
    Revoke-WslTempSudo
    Write-Fail "0.init-devtools2.sh 초기화 실패"
    Pause-Script
    exit 1
}

# ==============================================================================
# [Step 3 사전] WSL Interop (Windows ↔ Linux 실행 파일 연동) 상태 확인
# ==============================================================================
#   WSL 신규 설치 직후 또는 wsl --shutdown 없이 재시작한 경우
#   binfmt_misc에 WSLInterop 핸들러가 등록되지 않아 Windows .exe 실행이 불가능함.
#   → code.exe, winget.exe 등 Windows ↔ WSL 연동이 필요한 모든 이후 단계에 영향.
#   → 감지 즉시 wsl --shutdown 후 자동 재시작하여 확인.
# ==============================================================================
Write-SubStep "▶ [사전 확인] WSL Interop 상태 점검"
$interopCheck = ((wsl -d $wslDistro -- bash -c "test -f /proc/sys/fs/binfmt_misc/WSLInterop && echo OK || echo MISSING" 2>$null) -replace "`0", "").Trim()
if ($interopCheck -ne "OK") {
    Write-Warn "WSL Interop 비활성 감지 (binfmt_misc/WSLInterop 미등록)"
    Write-Info "  → root 권한으로 WSL Interop 핸들러 및 binfmt.d 설정을 즉시 등록합니다..."
    wsl -d $wslDistro -u root -- bash -c "mkdir -p /etc/binfmt.d /usr/lib/binfmt.d && echo ':WSLInterop:M::MZ::/init:PF' > /etc/binfmt.d/WSLInterop.conf && echo ':WSLInterop:M::MZ::/init:PF' > /usr/lib/binfmt.d/WSLInterop.conf && ([ -f /proc/sys/fs/binfmt_misc/register ] && echo ':WSLInterop:M::MZ::/init:PF' > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true)"

    $interopCheck = ((wsl -d $wslDistro -- bash -c "test -f /proc/sys/fs/binfmt_misc/WSLInterop && echo OK || echo MISSING" 2>$null) -replace "`0", "").Trim()
    if ($interopCheck -ne "OK") {
        Write-Info "  → WSL Interop이 없으면 Windows 실행 파일(.exe) 연동이 불가능합니다."
        Write-Info "  → WSL을 완전히 재시작합니다..."

        # wsl --shutdown 후 디스트로가 실제로 멈출 때까지 대기 (최대 60초)
        if (-not (Invoke-WslShutdown -Distro $wslDistro -TimeoutSeconds 60 -ShutdownMessage "WSL Interop 복구를 위한 재시작 대기")) {
            Write-Fail "WSL이 지정 시간(60초) 내에 종료되지 않았습니다."
            Write-Info "  → PC를 재부팅한 후 다시 실행해 주세요."
            Pause-Script
            exit 1
        }

        # 재시작 후 재확인
        $interopCheck2 = ((wsl -d $wslDistro -- bash -c "test -f /proc/sys/fs/binfmt_misc/WSLInterop && echo OK || echo MISSING" 2>$null) -replace "`0", "").Trim()
        if ($interopCheck2 -ne "OK") {
            Write-Fail "WSL 재시작 후에도 WSL Interop 복구 실패."
            Write-Info "  → PC를 재부팅한 후 다시 실행해 주세요."
            Pause-Script
            exit 1
        }
    }
    Write-Success "WSL Interop 복구 완료! 설치를 계속합니다."
} else {
    Write-Success "WSL Interop 정상 (Windows ↔ Linux 연동 활성)"
}

# ==============================================================================
# [Step 3] WSL2 내부 런타임 및 도구 일괄 설치
# ==============================================================================
Write-Step "[Step 3] WSL2 개발 환경 빌드 및 패키지 일괄 설치"

Write-SubStep "▶ (1/3) WSL2 환경 변수 주입 (~/.bashrc)"
wsl -d $wslDistro -u $wslUser -- bash -c "curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' '$RAW_LINUX/1.setup-env.sh' -o /tmp/_dt2_1.sh && DEVTOOLS2=/var/opt/_devtools2 DT2_REF='$DT2_REF' bash -l /tmp/_dt2_1.sh"
$envExit = $LASTEXITCODE
wsl -d $wslDistro -u $wslUser -- rm -f /tmp/_dt2_1.sh 2>$null
if ($envExit -ne 0) { Revoke-WslTempSudo; Write-Fail "환경 변수 설정 실패"; Pause-Script; exit 1 }

Write-SubStep "▶ (2/3) WSL2 핵심 개발 도구 설치 (Java, Node.js, Python, Neovim, Ghostty)"
wsl -d $wslDistro -u $wslUser -- bash -c "curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' '$RAW_LINUX/2.install-core-tools.sh' -o /tmp/_dt2_2.sh && DEVTOOLS2=/var/opt/_devtools2 DT2_REF='$DT2_REF' bash -l /tmp/_dt2_2.sh"
$coreExit = $LASTEXITCODE
wsl -d $wslDistro -u $wslUser -- rm -f /tmp/_dt2_2.sh 2>$null
if ($coreExit -ne 0) { Revoke-WslTempSudo; Write-Fail "핵심 도구 설치 실패"; Pause-Script; exit 1 }

Write-SubStep "▶ (3/3) WSL2 CLI 유틸리티 및 apt 패키지 설치"
wsl -d $wslDistro -u $wslUser -- bash -c "curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' '$RAW_LINUX/3.install-cli-tools.sh' -o /tmp/_dt2_3.sh && DEVTOOLS2=/var/opt/_devtools2 DT2_REF='$DT2_REF' bash -l /tmp/_dt2_3.sh"
$cliExit = $LASTEXITCODE
wsl -d $wslDistro -u $wslUser -- rm -f /tmp/_dt2_3.sh 2>$null
if ($cliExit -ne 0) { Revoke-WslTempSudo; Write-Fail "CLI 유틸리티 설치 실패"; Pause-Script; exit 1 }


Write-Success "WSL2 내부 가상 머신 개발 환경 구축 완료!"

# ==============================================================================
# Windows 호스트 연동을 위한 %DEVTOOLS2% 경로 단일 1회 확정 및 등록
# ==============================================================================
# WSL 내부 /var/opt/_devtools2 에 접근 가능한 최적의 UNC 경로(\\wsl$ 또는 \\wsl.localhost)를
# 1회 탐지하여 프로세스 및 사용자 환경 변수에 등록합니다.
# 이후 실행되는 모든 서브스크립트(VSCode, Zed, AHK, Terminal 등)는 이 경로를 즉시 재사용합니다.
$wslDevtools2Root = Get-WslDevtools2Path $wslDistro
if (Test-Path $wslDevtools2Root) {
    $env:DEVTOOLS2 = $wslDevtools2Root
    [Environment]::SetEnvironmentVariable("DEVTOOLS2", $wslDevtools2Root, "User")
    Write-Success "Windows 호스트 연동용 %DEVTOOLS2% 경로 확정 완료: $wslDevtools2Root"
} else {
    Write-Warn "WSL2 _devtools2 디렉터리 UNC 경로를 확인할 수 없습니다: $wslDevtools2Root"
}

# ==============================================================================
# [Step 4] Windows 호스트 전용 개발도구 연동
# ==============================================================================
Write-Step "[Step 4] Windows 호스트 전용 개발도구 연동"

# ── 4-1. AutoHotkey (CapsLock 리매핑 + Ctrl+Alt+T 단축키) ────────────────────
Write-SubStep "▶ (1/5) AutoHotkey 배포 및 단축키 등록"
Invoke-RemotePsScript -Url "$RAW_WIN/1.setup-autohotkey.ps1" -Arguments @{ WslDistro = $wslDistro }

# ── 4-2. Windows Terminal (폰트/테마/fzf 단축키) ─────────────────────────────
Write-SubStep "▶ (2/5) Windows Terminal 폰트/테마/단축키 설정"
Invoke-RemotePsScript -Url "$RAW_WIN/2.setup-windows-terminal.ps1" -Arguments @{ WslDistro = $wslDistro }

# ── 4-3. VSCode (에디터 설치, 심볼릭 링크 및 확장 동기화) ────────────────────
Write-SubStep "▶ (3/5) VSCode 에디터 설치 및 설정/확장 연동"
Invoke-RemotePsScript -Url "$RAW_WIN/tool.setup-vscode.ps1" -Arguments @{ WslDistro = $wslDistro }

# ── 4-4. Zed ─────────────────────────────────────────────────────────────────
Write-SubStep "▶ (4/5) Zed 에디터 설치 및 설정 연동"
Invoke-RemotePsScript -Url "$RAW_WIN/tool.setup-zed.ps1" -Arguments @{ WslDistro = $wslDistro }

# ── 4-5. Orca (Windows GUI 클라이언트 — 에이전트 실행부는 WSL2의 orca serve) ──
Write-SubStep "▶ (5/5) Orca GUI 클라이언트 설치 및 WSL2 서버 페어링 안내"
$userChoseOrca = Invoke-RemotePsScript -Url "$RAW_WIN/tool.setup-orca.ps1" -Arguments @{ WslDistro = $wslDistro }

# 🌟 [Gradle gradle.properties 윈도우 ↔ WSL2 심볼릭 링크 연동]
# - 보안 자격증명 정보(Git Token/Maven Auth) 손실 방지 및 이중 환경 호환성 확보
# - dotfiles repository에 올리지 않고, WSL2 사용자 홈(~/.gradle/gradle.properties)을 직접 윈도우 홈으로 링크
$winGradleDir = "$env:USERPROFILE\.gradle"
if (-not (Test-Path $winGradleDir)) {
    New-Item -ItemType Directory -Path $winGradleDir -Force | Out-Null
}

if ([string]::IsNullOrEmpty($wslUser) -or $wslUser -eq "root") {
    $wslUser = ((wsl -d $wslDistro -- bash -c "whoami" 2>$null) -replace "`0", "").Trim()
}
$wslUncRoot = if (Test-Path "\\wsl$\$wslDistro") { "\\wsl$\$wslDistro" } else { "\\wsl.localhost\$wslDistro" }
$wslGradleProps = "$wslUncRoot\home\$wslUser\.gradle\gradle.properties"
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
# [정리] 설치 과정 편의를 위해 [Step 2]에서 부여했던 임시 passwordless sudo 권한 회수
# ==============================================================================
Write-Step "[정리] WSL2 설치용 임시 sudo 권한 회수"
Revoke-WslTempSudo

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
Write-Info "  - Windows에 설치된 Zed 에디터의 설정은 설치 시점에 WSL2 내부 설정을 복사해 적용됩니다"
Write-Info "    (WSL 심볼릭 링크가 Windows UNC 경로를 못 따라가 복사 방식을 씀 — 실시간 공유 아님, 재설치 스크립트로 갱신)."
Write-Info "  - Windows Terminal의 폰트/테마/단축키는 설치 시점에 WSL2 설정을 복사해 적용됩니다(실시간 공유 아님 — 재설치 스크립트로 갱신)."
if ($userChoseOrca) {
    Write-Info "  - Orca는 에이전트 CLI가 있는 WSL2에서 'orca serve'로 실행되고, Windows GUI는 거기 페어링만 합니다."
    Write-Info "    (자동/수동 페어링 방법은 방금 위 tool.setup-orca.ps1 실행 결과에 안내되어 있습니다.)"
}
Write-Host ""
Write-Host "  설치 성공을 확인하시려면 아래 도구들을 실행해 보세요:"
Write-Host "    - Windows: Ctrl+Alt+T 눌러 Windows Terminal로 WSL2 바로 진입 확인" -ForegroundColor Gray
Write-Host "    - Windows: Zed 에디터 열기" -ForegroundColor Gray
Write-Host "    - WSL2 내부: nvim --version, java -version, node -v 실행 확인" -ForegroundColor Gray
Write-Host ""
Write-Info "💡 [참고: 'Exec format error' 트러블슈팅]"
Write-Info "  WSL2 터미널에서 'code .' 실행 시 'Exec format error'가 발생하는 경우:"
Write-Info "  -> PowerShell에서 'wsl --shutdown' 실행 후 WSL 터미널을 다시 열어주시면 해결됩니다."
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""

# 세션 한정 빠른 편집 모드(QuickEdit) 원래대로 복원
Restore-ConsoleQuickEdit | Out-Null

Pause-Script "엔터(Enter) 키를 누르시면 설치를 마치고 종료합니다"

