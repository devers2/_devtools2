param(
    [string]$WslDistro = ""
)

# ==============================================================================
# Gittyup & Meld 설치 및 WSL2 설정 동기화 스크립트 (tool.setup-gittyup.ps1)
#
# 주요 기능:
#   1. winget 을 통해 Gittyup (오픈소스 C++/Qt Git 클라이언트) 및 Meld (3-Way 머지 도구) 설치
#   2. _devtools2/.config/gittyup 설정을 %APPDATA%\Gittyup 경로로 동기화 (다크 테마, D2Coding 폰트 11.5pt)
#   3. Meld 레지스트리 설정 동기화 (공식 다크 테마 meld-dark, D2Coding 폰트 11.5pt)
#   4. Git 글로벌 difftool 및 mergetool 로 Meld 등록 (Gittyup 내 3-Way 머지 원클릭 연동)
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
Write-Host "🔀 Gittyup & Meld 설치 및 설정 동기화 스크립트 (tool.setup-gittyup.ps1)" -ForegroundColor DarkCyan
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
# [Step 3] Gittyup 및 Meld 설정 파일 동기화 (.config -> %APPDATA% / Registry)
# ==============================================================================
Write-Step "[Step 3] Gittyup & Meld 설정 동기화 (다크 테마 및 폰트 11.5pt)"

$gittyupAppdata = "$env:APPDATA\Gittyup"
if (-not (Test-Path $gittyupAppdata)) {
    New-Item -ItemType Directory -Path $gittyupAppdata -Force | Out-Null
}

$WslGittyupConfig = "$DevTools2Wsl\.config\gittyup"

# 1) Gittyup 설정 파일 동기화 (theme.lua, Gittyup.ini, editor.lua)
$filesToSync = @("theme.lua", "Gittyup.ini", "editor.lua")
foreach ($fName in $filesToSync) {
    $srcFile = if (Test-Path $WslGittyupConfig) { Join-Path $WslGittyupConfig $fName } else { $null }
    $dstFile = Join-Path $gittyupAppdata $fName

    $content = $null
    if ($srcFile -and (Test-Path $srcFile)) {
        $content = [System.IO.File]::ReadAllText($srcFile, [System.Text.Encoding]::UTF8)
    } else {
        try {
            $rawUrl = "https://raw.githubusercontent.com/devers2/_devtools2/$_dt2Ref/.config/gittyup/$fName"
            $content = (Invoke-RestMethod -Uri $rawUrl -Headers $_commonHeaders -ErrorAction Stop)
        } catch {}
    }

    if ($content) {
        # ui-defaults.json 에서 읽은 폰트/사이즈를 theme.lua, editor.lua 및 Gittyup.ini 에 동적 주입
        if ($fName -in @("theme.lua", "editor.lua")) {
            $content = $content -replace 'family\s*=\s*"[^"]*"', ('family = "' + $_dt2GuiFont + '"')
            $content = $content -replace 'size\s*=\s*[\d.]+', ('size = ' + $_dt2FontSize)
        } elseif ($fName -eq "Gittyup.ini") {
            $content = $content -replace 'font=.*', ('font=' + $_dt2GuiFont)
            $content = $content -replace 'fontSize=.*', ('fontSize=' + $_dt2FontSize)
        }
        [System.IO.File]::WriteAllText($dstFile, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Success "Gittyup 설정 동기화 완료: $dstFile"
    }
}

# 2) Meld 다크 테마 및 폰트 레지스트리 동기화 (HKCU:\SOFTWARE\GSettings\org\gnome\meld\)
try {
    $meldRegPath = "HKCU:\SOFTWARE\GSettings\org\gnome\meld"
    if (-not (Test-Path $meldRegPath)) {
        New-Item -Path $meldRegPath -Force | Out-Null
    }

    # 공식 다크 테마 (meld-dark) 및 D2Coding ligature 11.5pt 설정 주입
    Set-ItemProperty -Path $meldRegPath -Name "style-scheme" -Value "meld-dark" -Force
    Set-ItemProperty -Path $meldRegPath -Name "use-custom-font" -Value $true -Force
    Set-ItemProperty -Path $meldRegPath -Name "custom-font" -Value "$_dt2GuiFont $_dt2FontSize" -Force
    Set-ItemProperty -Path $meldRegPath -Name "indent-width" -Value 2 -Force
    Set-ItemProperty -Path $meldRegPath -Name "show-line-numbers" -Value $true -Force

    Write-Success "Meld 다크 테마(meld-dark) 및 폰트($_dt2GuiFont $_dt2FontSize) 레지스트리 설정 완료"
} catch {
    Write-Warn "Meld 레지스트리 설정 중 경고: $($_.Exception.Message)"
}

# ==============================================================================
# [Step 4] Git 전역 Diff / Merge 도구 등록 (Meld)
# ==============================================================================
Write-Step "[Step 4] Git 글로벌 병합 도구 등록 (Meld)"

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

# ==============================================================================
# [Step 5] 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 Gittyup & Meld 설치 및 설정 동기화 완료!" -ForegroundColor Green
Write-Host "  · Git 클라이언트: Gittyup (오픈소스 C++/Qt, 완전 무료 올블랙 다크 모드)" -ForegroundColor White
Write-Host "  · 3-Way 병합도구: Meld (공식 meld-dark 테마, Gittyup 내 원클릭 3-Way 병합 연동)" -ForegroundColor White
Write-Host "  · 폰트 / 크기   : $_dt2GuiFont, ${_dt2FontSize}pt (nvim 및 Windows Terminal과 동일)" -ForegroundColor White
Write-Host "  · Neovim 단축키 : <leader>gu (현재 프로젝트 Gittyup GUI 즉시 열기)" -ForegroundColor White
Write-Host "  · 전역 단축키   : Ctrl + Alt + G (Gittyup 즉시 활성화/실행)" -ForegroundColor White
Write-Host "===========================================================================" -ForegroundColor DarkCyan
