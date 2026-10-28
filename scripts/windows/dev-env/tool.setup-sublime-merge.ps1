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
# [Step 3] Sublime Merge 설정 파일 동기화 (테마, 폰트, 키맵)
# ==============================================================================
Write-Step "[Step 3] Sublime Merge 설정 파일 동기화"

# Sublime Merge 실행 중이면 메모리 덮어쓰기 방지를 위해 안전 종료
$runningSmerge = Get-Process -Name "sublime_merge" -ErrorAction SilentlyContinue
if ($runningSmerge) {
    Write-Info "실행 중인 Sublime Merge 프로세스를 감지했습니다. 최신 설정 적용을 위해 안전하게 종료합니다..."
    $runningSmerge | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

$WslSmergeConfig = "$DevTools2Wsl\.config\sublime-merge\Packages\User"

# Sublime Merge 데이터 대상 폴더 탐색 (포터블 모드 Data 폴더 및 Roaming AppData 폴더 전수 지원)
$targetDataDirs = [System.Collections.Generic.List[string]]::new()

# 1) 표준 Roaming 디렉터리
$roamingDir = "$env:APPDATA\Sublime Merge"
if (-not $targetDataDirs.Contains($roamingDir)) { $targetDataDirs.Add($roamingDir) }

# 2) WinGet 포터블 패키지 Data 디렉터리 (포터블 모드 실행 시 %LOCALAPPDATA%\...\Data 를 직접 읽음)
$wingetPkgBase = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
if (Test-Path $wingetPkgBase) {
    Get-ChildItem -Path $wingetPkgBase -Filter "*SublimeMerge*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $pData = Join-Path $_.FullName "Data"
        if (-not (Test-Path $pData)) { New-Item -ItemType Directory -Path $pData -Force | Out-Null }
        if (-not $targetDataDirs.Contains($pData)) { $targetDataDirs.Add($pData) }
    }
}

# 3) 기타 포터블 디렉터리 후보군
$otherCandidates = @(
    "$env:LOCALAPPDATA\Programs\Sublime Merge\Data",
    "$env:ProgramFiles\Sublime Merge\Data"
)
foreach ($cand in $otherCandidates) {
    if (Test-Path $cand -and -not $targetDataDirs.Contains($cand)) {
        $targetDataDirs.Add($cand)
    }
}

Write-Host "  동기화 대상 데이터 디렉터리 수: $($targetDataDirs.Count)" -ForegroundColor White

if (Test-Path $DevTools2Wsl) {
    if (-not (Test-Path $WslSmergeConfig)) {
        Write-Warn "WSL2에 Sublime Merge 설정 폴더가 없습니다. 기본 폴더를 생성합니다..."
        wsl.exe -d $WslDistro -e bash -c 'mkdir -p ${DEVTOOLS2:-/var/opt/_devtools2}/.config/sublime-merge/Packages/User'
    }

    # 동기화할 설정 파일 매핑: @{ 소스파일명 = 타겟파일명 }
    $filesToSync = @{
        "Preferences.sublime-settings"                 = "Preferences.sublime-settings"
        "Default.sublime-keymap"                       = "Default (Windows).sublime-keymap"
        "kanagawa.sublime-color-scheme"                = "kanagawa.sublime-color-scheme"
        "Merge Dark.sublime-theme"                     = "Merge Dark.sublime-theme"
        "Merge.sublime-theme"                          = "Merge.sublime-theme"
        "Commit Message.sublime-settings"              = "Commit Message.sublime-settings"
        "Commit Message - Merge Dark.sublime-settings" = "Commit Message - Merge Dark.sublime-settings"
        "File Mode.sublime-settings"                   = "File Mode.sublime-settings"
        "File Mode - Merge Dark.sublime-settings"      = "File Mode - Merge Dark.sublime-settings"
        "Git Output.sublime-settings"                  = "Git Output.sublime-settings"
        "Git Output - Merge Dark.sublime-settings"     = "Git Output - Merge Dark.sublime-settings"
    }

    foreach ($dataDir in $targetDataDirs) {
        $userDir = Join-Path $dataDir "Packages\User"
        if (-not (Test-Path $userDir)) {
            New-Item -ItemType Directory -Path $userDir -Force | Out-Null
        }

        foreach ($srcName in $filesToSync.Keys) {
            $srcFile = Join-Path $WslSmergeConfig $srcName
            $dstName = $filesToSync[$srcName]
            $dstFile = Join-Path $userDir $dstName

            if (Test-Path $srcFile) {
                if (Test-Path $dstFile) {
                    $fi = Get-Item $dstFile -Force
                    if ($fi.LinkType -eq "SymbolicLink") {
                        Remove-Item $dstFile -Force
                    } elseif ((Get-FileHash $dstFile).Hash -ne (Get-FileHash $srcFile).Hash) {
                        $bak = "$dstFile.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
                        Copy-Item -Path $dstFile -Destination $bak -Force
                    }
                }
                Copy-Item -Path $srcFile -Destination $dstFile -Force
            }
        }
        Write-Success "설정 파일 동기화 완료: $userDir"
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

    # DevTools2Wsl 경로 정규화 (이중 \wsl$\ 중복 결합 방지)
    $wslDevtools2Unc = if ($DevTools2Wsl -match '^[a-zA-Z]:') {
        $DevTools2Wsl
    } elseif ($DevTools2Wsl -match '^\\') {
        $DevTools2Wsl -replace '^\\wsl\$\', '\\wsl.localhost\'
    } else {
        "\\wsl.localhost\$WslDistro" + ($DevTools2Wsl -replace '/', '\')
    }
    $wslUserDevtools2Unc = "$wslHomeUnc\_devtools2"

    Write-Host "  감지된 WSL2 홈 UNC 경로: $wslHomeUnc" -ForegroundColor White

    # Sublime Merge 내부 POSIX 스타일 경로 표현 (예: /?wsl.localhost/devtools2/home/eseungsu)
    $wslHomeSlash = "//" + ($wslHomeUnc -replace '^\\', '' -replace '\\', '/')
    $wslHomeSM = "/?" + ($wslHomeUnc -replace '^\\', '' -replace '\\', '/')
    $wslDevtools2SM = "/?" + ($wslDevtools2Unc -replace '^\\', '' -replace '\\', '/')
    $wslUserDevtools2SM = "/?" + ($wslUserDevtools2Unc -replace '^\\', '' -replace '\\', '/')

    foreach ($dataDir in $targetDataDirs) {
        $localDir = Join-Path $dataDir "Local"
        $sessionFile = Join-Path $localDir "Session.sublime_session"

        if (-not (Test-Path $localDir)) {
            New-Item -ItemType Directory -Path $localDir -Force | Out-Null
        }

        $sessionObj = if (Test-Path $sessionFile) {
            try {
                Get-Content $sessionFile -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch {
                [PSCustomObject]@{}
            }
        } else {
            [PSCustomObject]@{}
        }

        if (-not $sessionObj) { $sessionObj = [PSCustomObject]@{} }

        # 1) Open Repository 대화상자 기본 시작 경로 (project_dir) 등록
        $sessionObj | Add-Member -NotePropertyName project_dir -NotePropertyValue $wslHomeSlash -Force

        # 2) recent 배열 항목 병합 (객체 배열 형식 및 folders 문자열 배열 형식 동시 호환)
        $targetPaths = @($wslUserDevtools2SM, $wslDevtools2SM, $wslHomeSM)

        if ($sessionObj.recent -is [System.Array]) {
            $newRecentList = [System.Collections.Generic.List[object]]::new()
            foreach ($tp in $targetPaths) {
                $newRecentList.Add([PSCustomObject]@{
                    path = $tp
                    locations_tab_selected = $false
                    show_untracked_files = $false
                    side_bar_visible = $true
                    table_of_contents_tab_selected = $false
                    table_of_contents_tree_mode = $false
                })
            }
            foreach ($oldItem in $sessionObj.recent) {
                if ($oldItem.path -and -not ($targetPaths -contains $oldItem.path)) {
                    $newRecentList.Add($oldItem)
                }
            }
            $sessionObj.recent = @($newRecentList)
        } else {
            if (-not $sessionObj.recent) {
                $sessionObj | Add-Member -NotePropertyName recent -NotePropertyValue ([PSCustomObject]@{ folders = @() }) -Force
            }
            if (-not $sessionObj.recent.folders) {
                $sessionObj.recent | Add-Member -NotePropertyName folders -NotePropertyValue @() -Force
            }
            $mergedFolders = [System.Collections.Generic.List[string]]::new()
            $folderCandidates = @($wslUserDevtools2Unc, $wslDevtools2Unc, $wslHomeUnc)
            foreach ($cand in $folderCandidates) {
                if (-not [string]::IsNullOrWhiteSpace($cand) -and -not $mergedFolders.Contains($cand)) {
                    $mergedFolders.Add($cand)
                }
            }
            if ($sessionObj.recent.folders) {
                foreach ($oldF in $sessionObj.recent.folders) {
                    if (-not [string]::IsNullOrWhiteSpace($oldF) -and -not $mergedFolders.Contains($oldF)) {
                        $mergedFolders.Add($oldF)
                    }
                }
            }
            $sessionObj.recent.folders = @($mergedFolders)
        }

        $sessionJson = $sessionObj | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($sessionFile, $sessionJson, [System.Text.UTF8Encoding]::new($false))
        $autoSaveSessionFile = Join-Path $localDir "Auto Save Session.sublime_session"
        [System.IO.File]::WriteAllText($autoSaveSessionFile, $sessionJson, [System.Text.UTF8Encoding]::new($false))
        Write-Success "Sublime Merge 세션 및 시작 경로(project_dir) 등록 완료: $dataDir"
    }

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
