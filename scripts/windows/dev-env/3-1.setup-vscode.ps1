param(
    [string]$WslDistro = ""
)

# ==============================================================================
# VSCode 에디터 설치 및 WSL2 설정/확장 연동 스크립트 (3-1.setup-vscode.ps1)
#
# 주요 기능:
#   0. VS Code 설치 의사 확인 ([y/N], 기본값 N) — 단독 실행/마스터 호출 모두 여기서 질문
#   1. winget 을 통해 VS Code 에디터 자동 설치 (이미 설치되어 있으면 건너뜀)
#   2. WSL Remote 필수 확장(ms-vscode-remote.remote-wsl) 설치
#   3. WSL2 의 _devtools2/.config/vscode/ 내 설정 파일을 Windows VS Code 설정 경로로 심볼릭 링크
#   4. extensions.txt 에 정의된 개발 확장 프로그램을 Windows 로컬 및 WSL Remote 에 자동 동기화 설치
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
# ------------------------------------------------------------------------------
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'

$_colorsHeaders = @{ 'Cache-Control' = 'no-cache, no-store, must-revalidate'; 'Pragma' = 'no-cache' }
$_colorsContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/_colors.ps1" -Headers $_colorsHeaders -ErrorAction Stop
. ([scriptblock]::Create($_colorsContent))

# 파일/심볼릭 링크(dangling 포함)를 안전하게 제거하는 헬퍼
function Remove-FileOrSymlink {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -ne $item) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        return $true
    }
    $cmdCheck = cmd.exe /c "if exist `"$Path`" echo exists" 2>$null
    if ($cmdCheck -match 'exists') {
        cmd.exe /c "del /f /q `"$Path`"" 2>$null | Out-Null
        return $true
    }
    return $false
}

function New-SymlinkIdempotent {
    param([string]$LinkPath, [string]$TargetPath, [string]$Description = "")
    $label = if ($Description) { $Description } else { Split-Path $LinkPath -Leaf }
    if (-not (Test-Path $TargetPath)) {
        Write-Warn "$label 대상 경로가 존재하지 않아 심볼릭 링크를 건너뜁니다: $TargetPath"
        return $false
    }
    $removed = Remove-FileOrSymlink -Path $LinkPath
    if ($removed) { Write-Info "$label 기존 항목 제거 완료: $LinkPath" }
    Write-Info "$label 심볼릭 링크 생성 중..."
    $result = cmd.exe /c "mklink `"$LinkPath`" `"$TargetPath`"" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "$label 심볼릭 링크 생성 실패: $result"
        return $false
    }
    Write-Success "$label 심볼릭 링크 생성 완료"
    return $true
}

function Backup-AndLink {
    param([string]$LinkPath, [string]$TargetPath, [string]$Description = "")
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
        Remove-FileOrSymlink -Path $LinkPath | Out-Null
    }
    return New-SymlinkIdempotent -LinkPath $LinkPath -TargetPath $TargetPath -Description $label
}

# ==============================================================================
# [Step 0] 관리자 권한 확인 및 재실행
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "[경고] 심볼릭 링크 생성에는 관리자 권한이 필요합니다." -ForegroundColor Yellow
    Write-Host "       관리자 권한으로 스크립트를 재실행합니다..." -ForegroundColor Yellow
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/3-1.setup-vscode.ps1 | iex`"" -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -WslDistro `"$WslDistro`"" -Verb RunAs
    }
    return
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "💻 VS Code 에디터 설치 및 설정/확장 연동 스크립트 (3-1.setup-vscode.ps1)" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan

# ==============================================================================
# [Step 1] 설치 의사 확인 ([y/N])
# ==============================================================================
Write-Step "[Step 1] VS Code 설치 의사 확인"

Write-Host ""
Write-Host "👉 VS Code (Visual Studio Code)를 설치하시겠습니까? [y/" -ForegroundColor Yellow -NoNewline
Write-Host "N" -ForegroundColor Green -NoNewline
Write-Host "]: " -ForegroundColor Yellow -NoNewline
$installInput = Read-Host
if (-not ($installInput -match '^[Yy]')) {
    Write-Skip "VS Code 설치를 건너뜁니다. 확장 설치도 건너뜁니다."
    Write-Host ""
    exit 0
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
            exit 1
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
    exit 1
}
Write-Host "  _devtools2 경로: $DevTools2Wsl" -ForegroundColor White

# ==============================================================================
# [Step 3] VSCode 설치 확인 및 설치
# ==============================================================================
Write-Step "[Step 3] VSCode 에디터 설치"

$vscodeAlreadyInstalled = $false
try {
    if (Get-Command code -ErrorAction SilentlyContinue) {
        $vscodeAlreadyInstalled = $true
    } elseif (Test-Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe") {
        $vscodeAlreadyInstalled = $true
    } elseif (Test-Path "$env:ProgramFiles\Microsoft VS Code\Code.exe") {
        $vscodeAlreadyInstalled = $true
    }
} catch {}

if ($vscodeAlreadyInstalled) {
    Write-Skip "VSCode(Visual Studio Code)가 이미 설치되어 있습니다."
} else {
    Write-Info "VSCode(Visual Studio Code)를 winget으로 자동 설치합니다..."
    $p = Start-Process winget -ArgumentList "install --id Microsoft.VisualStudioCode --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\vscode_install.log" -RedirectStandardError "$env:TEMP\vscode_install_err.log" -ErrorAction SilentlyContinue
    Wait-WithSpinner -Message "VSCode 패키지 설치 진행" -Condition { $p.HasExited }
    Remove-Item "$env:TEMP\vscode_install.log", "$env:TEMP\vscode_install_err.log" -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) {
        Write-Warn "winget 설치 종료 코드: $($p.ExitCode) (이미 설치되었거나 다른 이유일 수 있습니다)"
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

if (Get-Command code -ErrorAction SilentlyContinue) {
    Write-Info "VSCode WSL Remote 필수 확장(ms-vscode-remote.remote-wsl) 설치/확인 중..."
    code --install-extension ms-vscode-remote.remote-wsl --force 2>&1 | Out-Null
}

# ==============================================================================
# [Step 4] VSCode 설정 파일 심볼릭 링크 연동
# ==============================================================================
Write-Step "[Step 4] VSCode 설정 파일 심볼릭 링크 연동"

$vscodeUserDir = "$env:APPDATA\Code\User"
if (-not (Test-Path $vscodeUserDir)) {
    New-Item -ItemType Directory -Path $vscodeUserDir -Force | Out-Null
}

if (Test-Path $DevTools2Wsl) {
    [Environment]::SetEnvironmentVariable("DEVTOOLS2", $DevTools2Wsl, "User")
    $env:DEVTOOLS2 = $DevTools2Wsl
    Write-Success "Windows 사용자 환경 변수 %DEVTOOLS2% 연동 완료: $DevTools2Wsl"
}

$targetSettings    = "$DevTools2Wsl\.config\vscode\settings.json"
$targetKeybindings = "$DevTools2Wsl\.config\vscode\keybindings.json"
$targetTasks       = "$DevTools2Wsl\.config\vscode\tasks.json"

Backup-AndLink -LinkPath "$vscodeUserDir\settings.json"    -TargetPath $targetSettings    -Description "VSCode settings.json" | Out-Null
Backup-AndLink -LinkPath "$vscodeUserDir\keybindings.json" -TargetPath $targetKeybindings -Description "VSCode keybindings.json" | Out-Null
if (Test-Path $targetTasks) {
    Backup-AndLink -LinkPath "$vscodeUserDir\tasks.json" -TargetPath $targetTasks -Description "VSCode tasks.json" | Out-Null
}

# ==============================================================================
# [Step 5] VSCode 확장 프로그램 동기화 (Windows 로컬 및 WSL Remote)
# ==============================================================================
Write-Step "[Step 5] VSCode 확장 프로그램 동기화 (extensions.txt 기반)"

$targetExtensionsList = "$DevTools2Wsl\.config\vscode\extensions.txt"
if (Test-Path $targetExtensionsList) {
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Write-Info "Windows 로컬: 설치된 확장 목록 조회 중..."
        $installedExts = @()
        for ($i = 0; $i -lt 3; $i++) {
            $installedExts = @((code --list-extensions 2>$null) | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -ne "" })
            if ($installedExts.Count -ge 0 -and $LASTEXITCODE -eq 0) { break }
            Write-Info "VSCode CLI 초기화 대기 중... ($($i+1)/3)"
            Start-Sleep -Seconds 3
        }

        $toInstall = @()
        Get-Content $targetExtensionsList | ForEach-Object {
            $ext = $_.Trim()
            if ($ext -and -not $ext.StartsWith("#") -and ($ext -match '^[a-zA-Z0-9][a-zA-Z0-9_-]*\.[a-zA-Z0-9][a-zA-Z0-9_-]*$')) {
                if (-not ($installedExts -contains $ext.ToLower())) { $toInstall += $ext }
            }
        }

        if ($toInstall.Count -gt 0) {
            Write-Info "Windows 로컬: 신규/미설치 확장 $($toInstall.Count)개 설치 중..."
            $failedExts = @(); $idx = 0
            foreach ($ext in $toInstall) {
                $idx++
                $installed = $false
                for ($retry = 1; $retry -le 3; $retry++) {
                    Write-Host "  [$idx/$($toInstall.Count)] $ext (시도 $retry/3)..." -ForegroundColor DarkGray -NoNewline
                    $result = code --install-extension $ext --force 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host " ✓" -ForegroundColor Green
                        $installed = $true; break
                    } else {
                        Write-Host " 재시도..." -ForegroundColor Yellow
                        Start-Sleep -Seconds 2
                    }
                }
                if (-not $installed) { $failedExts += $ext }
            }
            if ($failedExts.Count -gt 0) {
                Write-Warn "아래 확장 $($failedExts.Count)개는 자동 설치에 실패했습니다 (수동으로 설치해주세요):"
                $failedExts | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
            } else {
                Write-Success "Windows 로컬 확장 $($toInstall.Count)개 설치 완료"
            }
        } else {
            Write-Skip "Windows 로컬: 모든 확장 프로그램이 이미 설치되어 있습니다."
        }

        Write-Info "WSL Remote: VSCode 확장 프로그램 설치 중 (WSL 내부 bash 실행)..."
        $wslExtScript = '[ -z "$DEVTOOLS2" ] && DEVTOOLS2="/var/opt/_devtools2"; VSCODE_BIN=""; command -v code >/dev/null 2>&1 && VSCODE_BIN="code"; [ -z "$VSCODE_BIN" ] && command -v code.cmd >/dev/null 2>&1 && VSCODE_BIN="code.cmd"; [ -z "$VSCODE_BIN" ] && { echo "[WSL-SKIP] code CLI not found"; exit 0; }; EXT_LIST="$DEVTOOLS2/.config/vscode/extensions.txt"; [ ! -f "$EXT_LIST" ] && { echo "[WSL-SKIP] extensions.txt not found"; exit 0; }; _INST=$("$VSCODE_BIN" --list-extensions 2>/dev/null </dev/null | tr [:upper:] [:lower:]); _cnt=0; _fail=0; while IFS= read -r line || [ -n "$line" ]; do ext=$(echo "$line" | tr -d \r | sed "s/#.*//" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//"); [ -z "$ext" ] && continue; ext_lower=$(echo "$ext" | tr [:upper:] [:lower:]); if echo "$_INST" | grep -qF "$ext_lower"; then echo "[SKIP] $ext"; else echo "[Install] $ext"; ok=0; for i in 1 2 3; do "$VSCODE_BIN" --install-extension "$ext" --force </dev/null >/dev/null 2>&1 && ok=1 && break; sleep 2; done; if [ $ok -eq 1 ]; then echo "[OK] $ext"; _cnt=$((_cnt+1)); else echo "[FAIL] $ext"; _fail=$((_fail+1)); fi; fi; done < "$EXT_LIST"; echo "[WSL Done] New: ${_cnt}, Failed: ${_fail}"'
        try {
            wsl -d $WslDistro -- bash -c $wslExtScript 2>$null
        } catch {
            Write-Warn "WSL Remote 확장 설치 중 오류: $_"
        }
    } else {
        Write-Warn "VSCode CLI('code')를 찾을 수 없어서 확장 프로그램 자동 설치를 건너뜁니다."
    }
} else {
    Write-Warn "확장 목록 파일(extensions.txt)을 찾을 수 없습니다: $targetExtensionsList"
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 VSCode 설치 및 설정 연동 완료!" -ForegroundColor Green
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
