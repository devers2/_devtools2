param(
    [string]$WslDistro = ""
)

# ==============================================================================
# Sublime Merge 설치 및 WSL2 설정 동기화 스크립트 (tool.setup-sublime-merge.ps1)
#
# 주요 기능:
#   1. winget 을 통해 Sublime Merge 를 자동 설치 (이미 설치되어 있으면 건너뜀)
#   2. WSL2 의 _devtools2/.config/sublime-merge/Packages/User 내 설정을
#      Windows %APPDATA%\Sublime Merge\Packages\User 경로로 동기화
#   3. Git difftool 및 mergetool 설정
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

# ==============================================================================
# [Step 0] 관리자 권한 확인 및 재실행
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "[경고] 관리자 권한으로 스크립트를 재실행합니다..." -ForegroundColor Yellow
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/devers2/_devtools2/$_dt2Ref/scripts/windows/dev-env/tool.setup-sublime-merge.ps1 | iex`"" -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -WslDistro `"$WslDistro`"" -Verb RunAs
    }
    return
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🔀 Sublime Merge 설치 및 설정 동기화 스크립트 (tool.setup-sublime-merge.ps1)" -ForegroundColor DarkCyan
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
# [Step 2] Sublime Merge 설치 (winget)
# ==============================================================================
Write-Step "[Step 2] Sublime Merge 설치"

try {
    Write-Host "  winget 패키지 매니저 소스를 확인하는 중..." -ForegroundColor White
    $pSrc = Start-Process winget -ArgumentList "source update" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\smerge_source_update.log" -RedirectStandardError "$env:TEMP\smerge_source_error.log" -ErrorAction SilentlyContinue
    Wait-ProcessWithSpinner -Process $pSrc -Message "winget 소스 업데이트 중"
    Remove-Item "$env:TEMP\smerge_source_update.log", "$env:TEMP\smerge_source_error.log" -Force -ErrorAction SilentlyContinue
} catch {}

$smergeInstalled = $false
try {
    $smergePaths = @(
        "$env:ProgramFiles\Sublime Merge\smerge.exe",
        "${env:ProgramFiles(x86)}\Sublime Merge\smerge.exe",
        "$env:LOCALAPPDATA\Programs\Sublime Merge\smerge.exe"
    )
    foreach ($p in $smergePaths) {
        if (Test-Path $p) { $smergeInstalled = $true; break }
    }
    if (-not $smergeInstalled -and (Get-Command smerge -ErrorAction SilentlyContinue)) {
        $smergeInstalled = $true
    }
    if (-not $smergeInstalled) {
        $wgList = winget list --id SublimeHQ.SublimeMerge 2>$null
        if ($LASTEXITCODE -eq 0 -and ($wgList -join "") -match "Sublime Merge") { $smergeInstalled = $true }
    }
} catch {}

$null = Install-OrUpdateWingetPackage -PackageId "SublimeHQ.SublimeMerge" -DisplayName "Sublime Merge" -IsInstalled $smergeInstalled -PromptDefault "Y"

# ==============================================================================
# [Step 3] Sublime Merge 설정 파일 동기화
# ==============================================================================
Write-Step "[Step 3] Sublime Merge 설정 파일 동기화"

$WslSmergeConfig = "$DevTools2Wsl\.config\sublime-merge\Packages\User"
$WinSmergeUserDir = "$env:APPDATA\Sublime Merge\Packages\User"

Write-Host "  소스 (WSL2): $WslSmergeConfig" -ForegroundColor DarkGray
Write-Host "  대상 (Win) : $WinSmergeUserDir" -ForegroundColor DarkGray
Write-Host ""

if (Test-Path $DevTools2Wsl) {
    if (-not (Test-Path $WslSmergeConfig)) {
        Write-Warn "WSL2에 Sublime Merge 설정 폴더가 없습니다. 기본 폴더를 생성합니다..."
        wsl -d $WslDistro -e bash -c 'mkdir -p ${DEVTOOLS2:-/var/opt/_devtools2}/.config/sublime-merge/Packages/User'
    }

    if (-not (Test-Path $WinSmergeUserDir)) {
        New-Item -ItemType Directory -Path $WinSmergeUserDir -Force | Out-Null
    }

    # Preferences.sublime-settings 동기화
    $srcPref = "$WslSmergeConfig\Preferences.sublime-settings"
    $dstPref = "$WinSmergeUserDir\Preferences.sublime-settings"
    if (Test-Path $srcPref) {
        if (Test-Path $dstPref) {
            $fi = Get-Item $dstPref -Force
            if ($fi.LinkType -eq "SymbolicLink") {
                Remove-Item $dstPref -Force
            } elseif ((Get-FileHash $dstPref).Hash -ne (Get-FileHash $srcPref).Hash) {
                $bak = "$dstPref.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
                Copy-Item -Path $dstPref -Destination $bak -Force
                Write-Info "기존 Windows Preferences.sublime-settings 를 백업했습니다: $bak"
            }
        }
        Copy-Item -Path $srcPref -Destination $dstPref -Force
        Write-Success "Preferences.sublime-settings 동기화 완료"
    }

    # Default.sublime-keymap 동기화
    $srcKeymap = "$WslSmergeConfig\Default.sublime-keymap"
    $dstKeymap = "$WinSmergeUserDir\Default (Windows).sublime-keymap"
    if (Test-Path $srcKeymap) {
        if (Test-Path $dstKeymap) {
            $fi = Get-Item $dstKeymap -Force
            if ($fi.LinkType -eq "SymbolicLink") {
                Remove-Item $dstKeymap -Force
            } elseif ((Get-FileHash $dstKeymap).Hash -ne (Get-FileHash $srcKeymap).Hash) {
                $bak = "$dstKeymap.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
                Copy-Item -Path $dstKeymap -Destination $bak -Force
                Write-Info "기존 Windows Default (Windows).sublime-keymap 를 백업했습니다: $bak"
            }
        }
        Copy-Item -Path $srcKeymap -Destination $dstKeymap -Force
        Write-Success "Default.sublime-keymap 동기화 완료"
    }

    # kanagawa.sublime-color-scheme 동기화 (Neovim 과 동일한 테마)
    $srcScheme = "$WslSmergeConfig\kanagawa.sublime-color-scheme"
    $dstScheme = "$WinSmergeUserDir\kanagawa.sublime-color-scheme"
    if (Test-Path $srcScheme) {
        if (Test-Path $dstScheme) {
            $fi = Get-Item $dstScheme -Force
            if ($fi.LinkType -eq "SymbolicLink") {
                Remove-Item $dstScheme -Force
            } elseif ((Get-FileHash $dstScheme).Hash -ne (Get-FileHash $srcScheme).Hash) {
                $bak = "$dstScheme.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
                Copy-Item -Path $dstScheme -Destination $bak -Force
            }
        }
        Copy-Item -Path $srcScheme -Destination $dstScheme -Force
        Write-Success "kanagawa.sublime-color-scheme 동기화 완료"
    }
}

# ==============================================================================
# [Step 4] WSL2 홈 및 저장소 기본 경로 세션 등록 (Local Repositories & Open)
# ==============================================================================
Write-Step "[Step 4] Sublime Merge 시작 경로 및 세션 등록"

$wslUser = (wsl.exe -d $WslDistro -e whoami 2>$null)
if (-not [string]::IsNullOrWhiteSpace($wslUser)) { $wslUser = $wslUser.Trim() }
$wslHomePosix = (wsl.exe -d $WslDistro -e sh -c 'echo $HOME' 2>$null)
if (-not [string]::IsNullOrWhiteSpace($wslHomePosix)) { $wslHomePosix = $wslHomePosix.Trim() }

if (-not [string]::IsNullOrWhiteSpace($wslHomePosix)) {
    # Windows UNC 경로 동적 산출 (예: \\wsl.localhost\devtools2\home\eseungsu)
    $wslHomeUnc = "\\wsl.localhost\$WslDistro" + ($wslHomePosix -replace '/', '\')
    $wslDevtools2Unc = "\\wsl.localhost\$WslDistro" + ($DevTools2Wsl -replace '/', '\')
    $wslUserDevtools2Unc = "$wslHomeUnc\_devtools2"

    Write-Host "  감지된 WSL2 홈 UNC 경로: $wslHomeUnc" -ForegroundColor White

    $smergeLocalDir = "$env:APPDATA\Sublime Merge\Local"
    $smergeSessionFile = "$smergeLocalDir\Session.sublime_session"

    if (-not (Test-Path $smergeLocalDir)) {
        New-Item -ItemType Directory -Path $smergeLocalDir -Force | Out-Null
    }

    $sessionObj = if (Test-Path $smergeSessionFile) {
        try {
            Get-Content $smergeSessionFile -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            [PSCustomObject]@{}
        }
    } else {
        [PSCustomObject]@{}
    }

    if (-not $sessionObj) { $sessionObj = [PSCustomObject]@{} }
    if (-not $sessionObj.recent) {
        $sessionObj | Add-Member -NotePropertyName recent -NotePropertyValue ([PSCustomObject]@{ folders = @() }) -Force
    }
    if (-not $sessionObj.recent.folders) {
        $sessionObj.recent | Add-Member -NotePropertyName folders -NotePropertyValue @() -Force
    }

    # 기본 표시 대상 저장소 후보군 (우선순위 순서대로)
    $candidateList = @($wslUserDevtools2Unc, $wslDevtools2Unc, $wslHomeUnc)
    $mergedFolders = [System.Collections.Generic.List[string]]::new()

    foreach ($cand in $candidateList) {
        if (-not [string]::IsNullOrWhiteSpace($cand) -and -not $mergedFolders.Contains($cand)) {
            $mergedFolders.Add($cand)
        }
    }

    # 기존 최근 목록 보존
    if ($sessionObj.recent.folders) {
        foreach ($oldF in $sessionObj.recent.folders) {
            if (-not [string]::IsNullOrWhiteSpace($oldF) -and -not $mergedFolders.Contains($oldF)) {
                $mergedFolders.Add($oldF)
            }
        }
    }

    $sessionObj.recent.folders = @($mergedFolders)

    $sessionJson = $sessionObj | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($smergeSessionFile, $sessionJson, [System.Text.UTF8Encoding]::new($false))
    Write-Success "Sublime Merge 시작 목록(Local Repositories)에 등록 완료: $wslHomeUnc"

    # Windows 탐색기 / 파일 열기 대화상자의 '즐겨찾기(Quick Access)'에 핀 등록 시도
    try {
        $shellApp = New-Object -ComObject Shell.Application
        $folderObj = $shellApp.Namespace($wslHomeUnc)
        if ($folderObj) {
            $folderObj.Self.InvokeVerb("pintohome")
            Write-Success "Windows 파일 열기 대화상자 즐겨찾기(Quick Access)에 핀 고정 완료"
        }
    } catch {}
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 Sublime Merge 설정 완료!" -ForegroundColor Green
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
