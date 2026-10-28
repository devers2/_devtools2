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

if ($smergeInstalled) {
    # 이미 설치되어 있으면 winget upgrade 로 최신 버전 업데이트 시도
    Write-Host "  Sublime Merge 가 이미 설치되어 있습니다. 최신 버전 확인 중..." -ForegroundColor White
    $upgradeNeeded = $false
    try {
        $wgUpgradeCheck = winget upgrade --id SublimeHQ.SublimeMerge 2>$null
        $upgradeOutput = $wgUpgradeCheck -join ""
        # winget upgrade 출력에 "SublimeHQ.SublimeMerge" 가 포함되면 업데이트 가능
        if ($LASTEXITCODE -eq 0 -and $upgradeOutput -match "SublimeHQ.SublimeMerge") {
            $upgradeNeeded = $true
        }
    } catch {}

    if ($upgradeNeeded) {
        Write-Info "Sublime Merge 최신 버전이 있습니다. 업데이트를 진행합니다..."
        $p = Start-Process winget -ArgumentList "upgrade --id SublimeHQ.SublimeMerge --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\smerge_upgrade.log" -RedirectStandardError "$env:TEMP\smerge_upgrade_err.log"
        # PS 5.1: -Wait 없이 띄운 프로세스는 핸들을 미리 열어 두지 않으면 종료 후 .ExitCode 가 $null 입니다(Rule 8).
        $null = $p.Handle
        Wait-ProcessWithSpinner -Process $p -Message "Sublime Merge 업데이트 진행 중"
        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq -1978335189) {
            Write-Success "Sublime Merge 업데이트 완료"
        } else {
            Write-Skip "Sublime Merge 업데이트를 건너뛰었습니다. (이미 최신이거나 수동 확인 필요)"
        }
        Remove-Item "$env:TEMP\smerge_upgrade.log", "$env:TEMP\smerge_upgrade_err.log" -Force -ErrorAction SilentlyContinue
    } else {
        Write-Skip "Sublime Merge 가 이미 최신 버전입니다."
    }
} else {
    Write-Host "  Sublime Merge 를 winget으로 설치합니다..." -ForegroundColor White
    $smergeIds = @("SublimeHQ.SublimeMerge")
    $smergeInstallSuccess = $false
    foreach ($smergeId in $smergeIds) {
        $p = Start-Process winget -ArgumentList "install --id $smergeId --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\smerge_install.log" -RedirectStandardError "$env:TEMP\smerge_install_err.log"
        # PS 5.1: -Wait 없이 띄운 프로세스는 핸들을 미리 열어 두지 않으면 종료 후 .ExitCode 가 $null 입니다(Rule 8).
        $null = $p.Handle
        Wait-ProcessWithSpinner -Process $p -Message "Sublime Merge 설치 진행 중 ($smergeId)"
        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq -1978335189) {
            Write-Success "Sublime Merge 설치 완료 ($smergeId)"
            $smergeInstallSuccess = $true
            Remove-Item "$env:TEMP\smerge_install.log", "$env:TEMP\smerge_install_err.log" -Force -ErrorAction SilentlyContinue
            break
        }
        Remove-Item "$env:TEMP\smerge_install.log", "$env:TEMP\smerge_install_err.log" -Force -ErrorAction SilentlyContinue
    }
    if (-not $smergeInstallSuccess) {
        Write-Warn "Sublime Merge winget 설치 실패. 수동 설치: https://www.sublimemerge.com/download"
    }
}

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
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 Sublime Merge 설정 완료!" -ForegroundColor Green
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
