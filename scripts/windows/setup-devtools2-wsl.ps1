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

# --- 한글 깨짐 방지: 출력 인코딩을 UTF-8 로 설정
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- 윈도우 PowerShell 기본 파란색 프로그레스바 팝업 끄기 (텍스트 깨짐 및 커서 겹침 방지)
$ProgressPreference = 'SilentlyContinue'

# ==============================================================================
# 헬퍼 함수
# ==============================================================================
# Write-Step/Write-Success/Pause-Script/Wait-WithSpinner 등은 여러 ps1 파일에
# 거의 동일하게 복붙되어 있던 걸 _common.ps1(scripts/windows/dev-env/_common.ps1)
# 공용 파일로 통합했습니다(bash의 _colors.sh와 동일한 패턴).
# 항상 온라인 최신본을 dot-source(다른 스크립트 스트리밍 실행과 동일한 캐시 우회 원칙).
$_commonHeaders = @{ 'Cache-Control' = 'no-cache, no-store, must-revalidate'; 'Pragma' = 'no-cache' }
$_commonContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/_common.ps1" -Headers $_commonHeaders -ErrorAction Stop
. ([scriptblock]::Create($_commonContent))

# 세션 한정 마우스 클릭 멈춤(프리징) 방지: QuickEdit 모드 안전 비활성화 (스크립트 종료/Ctrl+C 시 자동 복원)
Disable-ConsoleQuickEdit | Out-Null

# ⚠️ Show-BiosVirtualizationHelp는 예전에 여기 정의되어 있었으나, 실제 WSL 설치는
# 항상 0.setup-wsl.ps1(Invoke-RemotePsScript로 스트리밍 실행)에 위임되어 있어 이
# 마스터 스크립트에서는 절대 호출되지 않는 도달 불가능한 중복 코드였습니다. 실제
# BIOS/UEFI 가상화 안내는 0.setup-wsl.ps1 자신의 동일한 함수가 담당합니다.

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

# 기존 파일 위치를 심볼릭 링크로 교체하는 헬퍼 (VSCode settings.json/keybindings.json/tasks.json 등에서 공용 사용)
# - 실제 파일(심볼릭 링크가 아님)이 있으면 최초 1회만 .bak으로 백업하고, 이후 재실행 시에는 그냥 제거
# - 심볼릭 링크(정상 또는 dangling)면 Remove-FileOrSymlink로 안전하게 제거
# - 정리 후 New-SymlinkIdempotent로 새 심볼릭 링크 생성
function Backup-AndLink {
    param(
        [string]$LinkPath,
        [string]$TargetPath,
        [string]$Description = ""
    )
    $label = if ($Description) { $Description } else { Split-Path $LinkPath -Leaf }

    $item = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
    if ($null -ne $item) {
        $isLink = $item.Attributes -band [System.IO.FileAttributes]::ReparsePoint
        if (-not $isLink) {
            $backupPath = "$LinkPath.bak"
            if (-not (Test-Path $backupPath)) {
                Move-Item -LiteralPath $LinkPath -Destination $backupPath -Force
                Write-Info "기존 $label 을(를) $(Split-Path $backupPath -Leaf)으로 백업했습니다."
            } else {
                Remove-Item -LiteralPath $LinkPath -Force
            }
        } else {
            Remove-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
        }
    } else {
        # Get-Item으로도 못 찾는 dangling 심볼릭 링크까지 안전하게 정리
        Remove-FileOrSymlink -Path $LinkPath | Out-Null
    }

    return New-SymlinkIdempotent -LinkPath $LinkPath -TargetPath $TargetPath -Description $label
}



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

# 서브스크립트 GitHub raw URL 기준 상수
# 로컬/온라인 실행 여부와 무관하게 항상 GitHub main 최신 버전 기준으로 실행됩니다.
$RAW_WIN   = "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env"
$RAW_LINUX = "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env"

Write-Info "서브스크립트는 항상 GitHub main 브랜치 최신 버전으로 실행됩니다. (캐시 우회 포함)"

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

    # 재개 플래그 파일 저장 (재시작 후 이어서 진행하기 위해)
    Set-Content -Path $_wslResumeFlagFile -Value (Get-Date).ToString() -Encoding UTF8

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
    $wslPassword = Prompt-Password "👉 비밀번호(password) 입력: "
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
# ── 비밀번호와 스크립트를 분리 실행: sudo 인증 캐시 문제로 비밀번호가 bash stdin으로 노출되는 것 방지
# sudo -k 로 캐시를 초기화한 뒤 스크립트를 WSL 임시 파일로 먼저 저장하고, 별도로 sudo -S 실행
Write-SubStep "▶ WSL2 저장소 초기화 및 Git 클론 실행 (0.init-devtools2.sh)"
$wslTmpScript = "/tmp/_dt2_init.sh"

wsl -d $wslDistro -- bash -c "curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' '$RAW_LINUX/0.init-devtools2.sh' -o $wslTmpScript && chmod +x $wslTmpScript"

# sudo -k 로 캐시 초기화 후 비밀번호 stdin → sudo -S bash /tmp/script 실행 (비밀번호가 bash stdin으로 유입되지 않음)
# 이 호출이 비밀번호 파일의 마지막 사용처이므로, 성공/실패 여부와 무관하게(세미콜론 연결)
# WSL 안의 평문 비밀번호 임시 파일을 즉시 제거한다.
wsl -d $wslDistro -- bash -c "sudo -k; cat /tmp/.wsl_pw_tmp | sudo -S bash $wslTmpScript; rm -f $wslTmpScript /tmp/.wsl_pw_tmp"

if ($LASTEXITCODE -ne 0) {
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
$interopCheck = wsl -d $wslDistro -- bash -c "test -f /proc/sys/fs/binfmt_misc/WSLInterop && echo OK || echo MISSING" 2>$null
if ($interopCheck -ne "OK") {
    Write-Warn "WSL Interop 비활성 감지 (binfmt_misc/WSLInterop 미등록)"
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
    $interopCheck2 = wsl -d $wslDistro -- bash -c "test -f /proc/sys/fs/binfmt_misc/WSLInterop && echo OK || echo MISSING" 2>$null
    if ($interopCheck2 -ne "OK") {
        Write-Fail "WSL 재시작 후에도 WSL Interop 복구 실패."
        Write-Info "  → PC를 재부팅한 후 다시 실행해 주세요."
        Pause-Script
        exit 1
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
wsl -d $wslDistro -- bash -c "curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' '$RAW_LINUX/1.setup-env.sh' -o /tmp/_dt2_1.sh && DEVTOOLS2=/var/opt/_devtools2 bash -l /tmp/_dt2_1.sh"
$envExit = $LASTEXITCODE
wsl -d $wslDistro -- rm -f /tmp/_dt2_1.sh 2>$null
if ($envExit -ne 0) { Write-Fail "환경 변수 설정 실패"; Pause-Script; exit 1 }

Write-SubStep "▶ (2/3) WSL2 핵심 개발 도구 설치 (Java, Node.js, Python, Neovim, Ghostty)"
wsl -d $wslDistro -- bash -c "curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' '$RAW_LINUX/2.install-core-tools.sh' -o /tmp/_dt2_2.sh && DEVTOOLS2=/var/opt/_devtools2 bash -l /tmp/_dt2_2.sh"
$coreExit = $LASTEXITCODE
wsl -d $wslDistro -- rm -f /tmp/_dt2_2.sh 2>$null
if ($coreExit -ne 0) { Write-Fail "핵심 도구 설치 실패"; Pause-Script; exit 1 }

Write-SubStep "▶ (3/3) WSL2 CLI 유틸리티 및 apt 패키지 설치"
wsl -d $wslDistro -- bash -c "curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' '$RAW_LINUX/3.install-cli-tools.sh' -o /tmp/_dt2_3.sh && DEVTOOLS2=/var/opt/_devtools2 bash -l /tmp/_dt2_3.sh"
$cliExit = $LASTEXITCODE
wsl -d $wslDistro -- rm -f /tmp/_dt2_3.sh 2>$null
if ($cliExit -ne 0) { Write-Fail "CLI 유틸리티 설치 실패"; Pause-Script; exit 1 }


Write-Success "WSL2 내부 가상 머신 개발 환경 구축 완료!"


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
Invoke-RemotePsScript -Url "$RAW_WIN/tool.setup-orca.ps1" -Arguments @{ WslDistro = $wslDistro }

# 🌟 [Gradle gradle.properties 윈도우 ↔ WSL2 심볼릭 링크 연동]
# - 보안 자격증명 정보(Git Token/Maven Auth) 손실 방지 및 이중 환경 호환성 확보
# - dotfiles repository에 올리지 않고, WSL2 사용자 홈(~/.gradle/gradle.properties)을 직접 윈도우 홈으로 링크
$winGradleDir = "$env:USERPROFILE\.gradle"
if (-not (Test-Path $winGradleDir)) {
    New-Item -ItemType Directory -Path $winGradleDir -Force | Out-Null
}

$wslUser = (wsl -d $wslDistro -- bash -c "whoami" 2>$null).Trim()
if ([string]::IsNullOrEmpty($wslUser)) { $wslUser = $env:USERNAME.ToLower() }
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
Write-Info "  - Windows에 설치된 Zed 에디터의 설정은 설치 시점에 WSL2 내부 설정을 복사해 적용됩니다"
Write-Info "    (WSL 심볼릭 링크가 Windows UNC 경로를 못 따라가 복사 방식을 씀 — 실시간 공유 아님, 재설치 스크립트로 갱신)."
Write-Info "  - Windows Terminal의 폰트/테마/단축키는 설치 시점에 WSL2 설정을 복사해 적용됩니다(실시간 공유 아님 — 재설치 스크립트로 갱신)."
if ($userChoseOrca) {
    Write-Info "  - Orca는 에이전트 CLI가 있는 WSL2에서 'orca serve'로 실행되고, Windows GUI는 거기 페어링만 합니다."
    Write-Info "    (자동/수동 페어링 방법은 방금 위 4.setup-orca.ps1 실행 결과에 안내되어 있습니다.)"
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

