param(
    [string]$WslDistro = ""
)

# ==============================================================================
# Gittyup & Meld 설치 및 WSL2 설정 동기화 스크립트 (tool.setup-gittyup.ps1)
#
# 주요 기능:
#   1. winget 을 통해 Gittyup (오픈소스 C++/Qt Git 클라이언트) 및 Meld (3-Way 머지 도구) 설치
#   2. Gittyup 다크 테마 및 폰트 설정 구성
#   3. Git 글로벌 difftool 및 mergetool 로 Meld 등록 (Gittyup 내 3-Way 머지 원클릭 연동)
#   4. WSL2 환경과의 상호운용 및 시작 경로 동기화
#
# ------------------------------------------------------------------------------
# ⚠️ [AI / 개발자 필독 - 설계 절대 원칙]
# 1. 100% 온라인 전용: 스크립트는 항상 GitHub main 브랜치 최신 원격 raw URL에서 호출됩니다.
# 2. 순수 UTF-8 NoBOM 보장: BOM(Byte Order Mark) 헤더를 절대 삽입하거나 조작하지 마십시오.
# 3. PS5.1 & PS7 무구분 호환: param() 구문은 반드시 스크립트 맨 첫 줄(Line 1)에 위치해야 합니다.
# 4. 서브스크립트 종료 처리: 마스터 스크립트 인라인 호출 시 전체 프로세스가 종료되는 것을 방지하기 위해
#    조기 종료/건너뛰기 시에는 `exit` 대신 반드시 `return`을 사용해야 합니다.
# ------------------------------------------------------------------------------
# ==============================================================================

$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$ProgressPreference = 'SilentlyContinue'

$_dt2Ref = if ($env:DT2_REF) { $env:DT2_REF } else { 'main' }

$_commonHeaders = @{ 'Cache-Control' = 'no-cache, no-store, must-revalidate'; 'Pragma' = 'no-cache' }
$_commonContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/devers2/_devtools2/$_dt2Ref/scripts/windows/dev-env/_common.ps1" -Headers $_commonHeaders -ErrorAction Stop
. ([scriptblock]::Create($_commonContent))

# DevTools2 중앙 UI 기본값 로드 (.config/devtools2/ui-defaults.json)
$_uiDefaultsUrl = "https://raw.githubusercontent.com/devers2/_devtools2/$_dt2Ref/.config/devtools2/ui-defaults.json"
try {
    $_uiDefaults = Invoke-RestMethod -Uri $_uiDefaultsUrl -Headers $_commonHeaders -ErrorAction Stop
    $_dt2FontSize = $_uiDefaults.font.size
    $_dt2GuiFont = $_uiDefaults.font.gui_face
} catch {
    Write-Warn "ui-defaults.json 로드 실패, 기본값 사용 (font.size=11.5, gui_face=D2Coding ligature)"
    $_dt2FontSize = 11.5
    $_dt2GuiFont = "D2Coding ligature"
}

# ==============================================================================
# [Step 0] 관리자 권한 확인 및 재실행
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "[경고] 관리자 권한으로 스크립트를 재실행합니다..." -ForegroundColor Yellow
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/devers2/_devtools2/$_dt2Ref/scripts/windows/dev-env/tool.setup-gittyup.ps1 | iex`"" -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -WslDistro `"$WslDistro`"" -Verb RunAs
    }
    return
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🔀 Gittyup & Meld 설치 및 연동 스크립트 (tool.setup-gittyup.ps1)" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan

# ==============================================================================
# [Step 1] WSL2 배포판 이름 자동 감지
# ==============================================================================
Write-Step "[Step 1] WSL2 배포판 감지"

$WslDistro = Resolve-WslDistro $WslDistro
Write-Host "  적용 대상 WSL 배포판: $WslDistro" -ForegroundColor White

$DevTools2Wsl = if ($env:DEVTOOLS2 -and (Test-Path $env:DEVTOOLS2)) {
    $env:DEVTOOLS2
} else {
    Get-WslDevtools2Path $WslDistro
}

if (-not (Test-Path $DevTools2Wsl)) {
    Write-Warn "WSL2 에서 '_devtools2' 폴더를 찾을 수 없습니다: $DevTools2Wsl"
} else {
    Write-Host "  _devtools2 경로: $DevTools2Wsl" -ForegroundColor White
}

# ==============================================================================
# [Step 2] Gittyup 및 Meld 설치 (winget)
# ==============================================================================
Write-Step "[Step 2] Gittyup & Meld 설치 (winget)"

try {
    Write-Host "  winget 패키지 매니저 소스를 확인하는 중..." -ForegroundColor White
    $pSrc = Start-Process winget -ArgumentList "source update" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\dt2_winget_src_upd.log" -RedirectStandardError "$env:TEMP\dt2_winget_src_err.log" -ErrorAction SilentlyContinue
    Wait-ProcessWithSpinner -Process $pSrc -Message "winget 소스 업데이트 중"
    Remove-Item "$env:TEMP\dt2_winget_src_upd.log", "$env:TEMP\dt2_winget_src_err.log" -Force -ErrorAction SilentlyContinue
} catch {}

# 1) Gittyup 확인 및 설치
$gittyupInstalled = $false
try {
    $gittyupPaths = @(
        "$env:ProgramFiles\Gittyup\bin\gittyup.exe",
        "$env:ProgramFiles\Gittyup\gittyup.exe",
        "${env:ProgramFiles(x86)}\Gittyup\bin\gittyup.exe",
        "${env:ProgramFiles(x86)}\Gittyup\gittyup.exe",
        "$env:LOCALAPPDATA\Programs\Gittyup\bin\gittyup.exe",
        "$env:LOCALAPPDATA\Programs\Gittyup\gittyup.exe"
    )
    foreach ($p in $gittyupPaths) {
        if (Test-Path $p) { $gittyupInstalled = $true; break }
    }
    if (-not $gittyupInstalled -and (Get-Command gittyup -ErrorAction SilentlyContinue)) {
        $gittyupInstalled = $true
    }
    if (-not $gittyupInstalled) {
        $wgList = winget list --id Murmele.Gittyup 2>$null
        if ($LASTEXITCODE -eq 0 -and ($wgList -join "") -match "Gittyup") { $gittyupInstalled = $true }
    }
} catch {}

$null = Install-OrUpdateWingetPackage -PackageId "Murmele.Gittyup" -DisplayName "Gittyup" -IsInstalled $gittyupInstalled -SkipPrompt

# 2) Meld 확인 및 설치
$meldInstalled = $false
try {
    $meldPaths = @(
        "$env:ProgramFiles\Meld\Meld.exe",
        "$env:ProgramFiles\Meld\meld.exe",
        "${env:ProgramFiles(x86)}\Meld\Meld.exe",
        "${env:ProgramFiles(x86)}\Meld\meld.exe",
        "$env:LOCALAPPDATA\Programs\Meld\Meld.exe",
        "$env:LOCALAPPDATA\Programs\Meld\meld.exe"
    )
    foreach ($p in $meldPaths) {
        if (Test-Path $p) { $meldInstalled = $true; break }
    }
    if (-not $meldInstalled -and (Get-Command meld -ErrorAction SilentlyContinue)) {
        $meldInstalled = $true
    }
    if (-not $meldInstalled) {
        $wgListM = winget list --id Meld.Meld 2>$null
        if ($LASTEXITCODE -eq 0 -and ($wgListM -join "") -match "Meld") { $meldInstalled = $true }
    }
} catch {}

$null = Install-OrUpdateWingetPackage -PackageId "Meld.Meld" -DisplayName "Meld" -IsInstalled $meldInstalled -SkipPrompt

# ==============================================================================
# [Step 3] Gittyup 및 Git 글로벌 Merge/Diff 도구 연동 (Meld)
# ==============================================================================
Write-Step "[Step 3] Gittyup 다크 테마 및 Meld 3-Way 병합 도구 연동"

# Meld 실행 파일 탐색
$meldExe = ""
$candMeld = @(
    "$env:ProgramFiles\Meld\Meld.exe",
    "$env:ProgramFiles\Meld\meld.exe",
    "${env:ProgramFiles(x86)}\Meld\Meld.exe",
    "${env:ProgramFiles(x86)}\Meld\meld.exe",
    "$env:LOCALAPPDATA\Programs\Meld\Meld.exe",
    "$env:LOCALAPPDATA\Programs\Meld\meld.exe"
)
foreach ($m in $candMeld) {
    if (Test-Path $m) { $meldExe = $m; break }
}
if ([string]::IsNullOrEmpty($meldExe)) {
    $cmdMeld = Get-Command meld.exe -ErrorAction SilentlyContinue
    if ($cmdMeld) { $meldExe = $cmdMeld.Source }
}

# Windows 환경 Git 전역 mergetool / difftool 등록
if (Get-Command git.exe -ErrorAction SilentlyContinue) {
    try {
        git config --global merge.tool meld
        git config --global diff.tool meld
        git config --global mergetool.prompt false
        git config --global difftool.prompt false
        if (-not [string]::IsNullOrEmpty($meldExe)) {
            $meldEscaped = $meldExe -replace '\\', '/'
            git config --global mergetool.meld.cmd "`"$meldEscaped`" `"`$LOCAL`" `"`$BASE`" `"`$REMOTE`" --output `"`$MERGED`""
            git config --global difftool.meld.cmd "`"$meldEscaped`" `"`$LOCAL`" `"`$REMOTE`""
        }
        Write-Success "Windows Git 설정 완료: merge.tool=meld, diff.tool=meld"
    } catch {
        Write-Warn "Windows Git 설정 등록 중 경고: $($_.Exception.Message)"
    }
}

# WSL2 내부 Git 전역 mergetool / difftool 동기화
if (-not [string]::IsNullOrWhiteSpace($WslDistro)) {
    try {
        wsl.exe -d $WslDistro -e git config --global merge.tool meld 2>$null
        wsl.exe -d $WslDistro -e git config --global diff.tool meld 2>$null
        wsl.exe -d $WslDistro -e git config --global mergetool.prompt false 2>$null
        wsl.exe -d $WslDistro -e git config --global difftool.prompt false 2>$null
        Write-Success "WSL2($WslDistro) Git 설정 동기화 완료: merge.tool=meld"
    } catch {}
}

# Gittyup 다크 테마 및 폰트 설정 (%APPDATA%\Gittyup\Gittyup.ini)
try {
    $gittyupConfigDir = "$env:APPDATA\Gittyup"
    if (-not (Test-Path $gittyupConfigDir)) {
        New-Item -ItemType Directory -Path $gittyupConfigDir -Force | Out-Null
    }
    $gittyupIni = Join-Path $gittyupConfigDir "Gittyup.ini"

    # 기존 설정이 있으면 보존하며 다크 테마 및 폰트 주입
    $iniLines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path $gittyupIni) {
        $existing = [System.IO.File]::ReadAllLines($gittyupIni, [System.Text.Encoding]::UTF8)
        foreach ($line in $existing) {
            # 테마 및 폰트 기존 줄 필터링
            if ($line -notmatch '^theme=' -and $line -notmatch '^font=' -and $line -notmatch '^fontSize=') {
                $iniLines.Add($line)
            }
        }
    }

    # [General] 섹션 위치 확인 또는 추가
    $genIndex = $iniLines.IndexOf("[General]")
    if ($genIndex -eq -1) {
        $iniLines.Insert(0, "[General]")
        $genIndex = 0
    }

    $iniLines.Insert($genIndex + 1, "theme=Dark")
    $iniLines.Insert($genIndex + 2, "font=$_dt2GuiFont")
    $iniLines.Insert($genIndex + 3, "fontSize=$_dt2FontSize")

    [System.IO.File]::WriteAllLines($gittyupIni, $iniLines, [System.Text.UTF8Encoding]::new($false))
    Write-Success "Gittyup 다크 테마 및 폰트($_dt2GuiFont, ${_dt2FontSize}pt) 설정 완료"
} catch {
    Write-Warn "Gittyup.ini 설정 구성 중 경고: $($_.Exception.Message)"
}

# ==============================================================================
# [Step 4] 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 Gittyup & Meld 설정 완료!" -ForegroundColor Green
Write-Host "  · Git 클라이언트: Gittyup (오픈소스 C++/Qt, 완전 무료 올블랙 다크 모드)" -ForegroundColor White
Write-Host "  · 3-Way 병합도구: Meld (Gittyup 내 충돌 발생 시 원클릭 3-Way 해결 연동)" -ForegroundColor White
Write-Host "  · Neovim 단축키 : <leader>gu (현재 프로젝트 Gittyup GUI 즉시 열기)" -ForegroundColor White
Write-Host "  · 전역 단축키   : Ctrl + Alt + G (Gittyup 즉시 활성화/실행)" -ForegroundColor White
Write-Host "===========================================================================" -ForegroundColor DarkCyan
