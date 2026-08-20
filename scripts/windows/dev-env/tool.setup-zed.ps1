param(
    [string]$WslDistro = ""
)

# ==============================================================================
# Zed 에디터 설치 및 WSL2 설정 파일 복사 스크립트 (tool.setup-zed.ps1)
#
# 주요 기능:
#   0. Zed 설치 의사 확인 ([y/N], 기본값 N) — 단독 실행/마스터 호출 모두 여기서 질문
#   1. winget 을 통해 Zed 에디터를 자동 설치 (이미 설치되어 있으면 건너뜀)
#   2. WSL2 의 _devtools2/.config/zed/ 내 설정 파일을 Windows Zed 설정 경로로 복사
#      - settings.json  : 에디터 전역 설정  (%APPDATA%\Zed\settings.json)
#      - keymap.json    : 키보드 단축키 설정 (%APPDATA%\Zed\keymap.json)
#
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
# 5. 서브스크립트 종료 처리: 마스터 스크립트 인라인 호출 시 전체 프로세스가 종료되는 것을 방지하기 위해
#    조기 종료/건너뛰기 시에는 `exit` 대신 반드시 `return`을 사용해야 합니다.
# ------------------------------------------------------------------------------
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'

$_colorsHeaders = @{ 'Cache-Control' = 'no-cache, no-store, must-revalidate'; 'Pragma' = 'no-cache' }
$_colorsContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/_colors.ps1" -Headers $_colorsHeaders -ErrorAction Stop
. ([scriptblock]::Create($_colorsContent))

# ==============================================================================
# [Step 0] 관리자 권한 확인 및 재실행
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "[경고] 관리자 권한으로 스크립트를 재실행합니다..." -ForegroundColor Yellow
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/tool.setup-zed.ps1 | iex`"" -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -WslDistro `"$WslDistro`"" -Verb RunAs
    }
    return
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🚀 Zed 에디터 설치 및 설정 파일 링크 생성 스크립트 (tool.setup-zed.ps1)" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan

# ==============================================================================
# [Step 1] 설치 의사 확인 ([y/N])
# ==============================================================================
Write-Step "[Step 1] Zed 설치 의사 확인"

Write-Host ""
Write-Host "👉 Zed 에디터를 설치하시겠습니까? [y/" -ForegroundColor Yellow -NoNewline
Write-Host "N" -ForegroundColor Green -NoNewline
Write-Host "]: " -ForegroundColor Yellow -NoNewline
$installInput = Read-Host
if (-not ($installInput -match '^[Yy]')) {
    Write-Skip "Zed 에디터 설치를 건너뜁니다. 기존 설정은 유지됩니다."
    Write-Host ""
    return
}

# ==============================================================================
# [Step 2] WSL2 배포판 이름 자동 감지
# ==============================================================================
Write-Step "[Step 2] WSL2 배포판 감지"

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
            return
        }
        $WslDistro = $distroList[0] -replace "`0", "" | ForEach-Object { $_.Trim() }
        Write-Host "  자동 감지된 배포판: $WslDistro" -ForegroundColor White
    }
} else {
    Write-Host "  지정된 배포판: $WslDistro" -ForegroundColor White
}

$WslRoot = "\\wsl.localhost\$WslDistro"
$DevTools2Wsl = if ($env:DEVTOOLS2 -and (Test-Path $env:DEVTOOLS2)) { $env:DEVTOOLS2 } else { "$WslRoot\var\opt\_devtools2" }

if (-not (Test-Path $DevTools2Wsl)) {
    Write-Fail "WSL2 에서 '_devtools2' 폴더를 찾을 수 없습니다: $DevTools2Wsl"
    Write-Host "  마스터 설치 스크립트(setup-devtools2-wsl.ps1)를 먼저 실행해주세요." -ForegroundColor Yellow
    Read-Host "계속하려면 엔터를 누르세요"
    return
}
Write-Host "  _devtools2 경로: $DevTools2Wsl" -ForegroundColor White

# ==============================================================================
# [Step 3] Zed 에디터 설치
# ==============================================================================
Write-Step "[Step 3] Zed 에디터 설치"

try {
    Write-Host "  winget 패키지 매니저 소스를 확인하는 중..." -ForegroundColor White
    $pSrc = Start-Process winget -ArgumentList "source update" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\zed_source_update.log" -RedirectStandardError "$env:TEMP\zed_source_error.log" -ErrorAction SilentlyContinue
    Wait-ProcessWithSpinner -Process $pSrc -Message "winget 소스 업데이트 중"
    Remove-Item "$env:TEMP\zed_source_update.log", "$env:TEMP\zed_source_error.log" -Force -ErrorAction SilentlyContinue
} catch {}

$zedInstalled = $false
try {
    $zedPaths = @(
        "$env:LOCALAPPDATA\Programs\Zed\Zed.exe",
        "$env:LOCALAPPDATA\Zed\bin\zed.exe",
        "$env:ProgramFiles\Zed\Zed.exe"
    )
    foreach ($p in $zedPaths) {
        if (Test-Path $p) { $zedInstalled = $true; break }
    }
    if (-not $zedInstalled -and (Get-Command zed -ErrorAction SilentlyContinue)) {
        $zedInstalled = $true
    }
    if (-not $zedInstalled) {
        $wgList = winget list --id ZedIndustries.Zed 2>$null
        if ($LASTEXITCODE -eq 0 -and ($wgList -join "") -match "Zed") { $zedInstalled = $true }
    }
} catch {}

if ($zedInstalled) {
    Write-Skip "Zed 에디터가 이미 설치되어 있습니다."
} else {
    Write-Host "  Zed 에디터를 winget으로 설치합니다..." -ForegroundColor White
    $zedIds = @("ZedIndustries.Zed")
    $zedInstallSuccess = $false
    foreach ($zedId in $zedIds) {
        $p = Start-Process winget -ArgumentList "install --id $zedId --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\zed_install.log" -RedirectStandardError "$env:TEMP\zed_install_err.log"
        Wait-ProcessWithSpinner -Process $p -Message "Zed 에디터 설치 진행 중 ($zedId)"
        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq -1978335189) {
            Write-Success "Zed 에디터 설치/확인 완료 ($zedId)"
            $zedInstallSuccess = $true
            Remove-Item "$env:TEMP\zed_install.log", "$env:TEMP\zed_install_err.log" -Force -ErrorAction SilentlyContinue
            break
        }
        Remove-Item "$env:TEMP\zed_install.log", "$env:TEMP\zed_install_err.log" -Force -ErrorAction SilentlyContinue
    }
    if (-not $zedInstallSuccess) {
        Write-Warn "Zed winget 설치 실패. 수동 설치: https://zed.dev/download"
        Write-Warn "(Zed Windows 버전이 아직 Preview 상태일 수 있습니다)"
    }
}

# ==============================================================================
# [Step 4] Zed 설정 파일 복사
# ==============================================================================
Write-Step "[Step 4] Zed 설정 파일 복사"

$WslZedConfig = "$DevTools2Wsl\.config\zed"
$WinZedDir    = "$env:APPDATA\Zed"

Write-Host "  소스 (WSL2): $WslZedConfig" -ForegroundColor DarkGray
Write-Host "  대상 (Win) : $WinZedDir" -ForegroundColor DarkGray
Write-Host ""

if (-not (Test-Path $WslZedConfig)) {
    Write-Warn "WSL2에 Zed 설정 폴더가 없습니다. 기본 폴더를 생성합니다..."
    wsl -d $WslDistro -- bash -c 'mkdir -p $DEVTOOLS2/.config/zed'
}
if (-not (Test-Path "$WslZedConfig\settings.json")) {
    wsl -d $WslDistro -- bash -c 'echo "{}" > $DEVTOOLS2/.config/zed/settings.json'
}
if (-not (Test-Path "$WslZedConfig\keymap.json")) {
    wsl -d $WslDistro -- bash -c 'echo "[]" > $DEVTOOLS2/.config/zed/keymap.json'
}

if (Test-Path $WinZedDir) {
    $item = Get-Item $WinZedDir -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq "SymbolicLink") {
        Write-Host "  기존 심볼릭 링크 폴더를 제거합니다..." -ForegroundColor Yellow
        Remove-Item $WinZedDir -Force -ErrorAction SilentlyContinue
        cmd.exe /c "rd /s /q `"$WinZedDir`"" 2>$null | Out-Null
    }
}
if (-not (Test-Path $WinZedDir)) {
    New-Item -ItemType Directory -Path $WinZedDir -Force | Out-Null
}

if (Test-Path "$WslZedConfig\settings.json") {
    $targetFile = "$WinZedDir\settings.json"
    if (Test-Path $targetFile) {
        $fi = Get-Item $targetFile -Force
        if ($fi.LinkType -eq "SymbolicLink") { Remove-Item $targetFile -Force }
    }
    Copy-Item -Path "$WslZedConfig\settings.json" -Destination $targetFile -Force
    Write-Success "settings.json 파일 복사 완료"
}

if (Test-Path "$WslZedConfig\keymap.json") {
    $targetFile = "$WinZedDir\keymap.json"
    if (Test-Path $targetFile) {
        $fi = Get-Item $targetFile -Force
        if ($fi.LinkType -eq "SymbolicLink") { Remove-Item $targetFile -Force }
    }
    Copy-Item -Path "$WslZedConfig\keymap.json" -Destination $targetFile -Force
    Write-Success "keymap.json 파일 복사 완료"
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 Zed 설정 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  복사된 설정 파일 목록:" -ForegroundColor White
Write-Host "    $WinZedDir\settings.json" -ForegroundColor DarkGray
Write-Host "    $WinZedDir\keymap.json" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Zed 를 재시작하면 설정이 적용됩니다." -ForegroundColor Yellow
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
