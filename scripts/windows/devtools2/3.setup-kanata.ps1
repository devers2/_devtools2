# ==============================================================================
# kanata 설치 및 CapsLock (ESC/Ctrl) 전역 매핑 설정 스크립트 (3.setup-kanata.ps1)
#
# 주요 기능:
#   1. kanata (Windows 전역 키 매핑 도구) 다운로드 및 설치
#   2. CapsLock 키 재매핑 (단독 탭: ESC / 다른 키와 조합: Ctrl)
#   3. Windows 작업 스케줄러 등록 (로그인 시 관리자 권한 자동 실행)
# ==============================================================================

param(
    [string]$WslDistro = ""
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "---------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[성공] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "[건너뜀] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[오류] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "[정보] $Message" -ForegroundColor White
}

# ==============================================================================
# [Step 0] 관리자 권한 확인
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host "[경고] kanata 설치 및 키보드 후킹 등록을 위해 관리자 권한이 필요합니다." -ForegroundColor Yellow
    if ($PSCommandPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -WslDistro `"$WslDistro`"" -Verb RunAs
    }
    return
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host "kanata 설치 및 CapsLock (ESC/Ctrl) Windows 전역 키 매핑" -ForegroundColor Magenta
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "   ※ kanata 를 설치하면 Windows 및 WSL2(WezTerm/Zed 포함) 전체에 아래 매핑이 적용됩니다." -ForegroundColor White
Write-Host "      - CapsLock 단독 탭  -> ESC" -ForegroundColor Green
Write-Host "      - CapsLock + 조합키 -> Ctrl" -ForegroundColor Green
Write-Host "      - Neovim / 터미널 환경에서 CapsLock 대문자 고정 문제 해결" -ForegroundColor Gray
Write-Host ""

$kanataAnswer = Read-Host "  kanata (CapsLock -> ESC/Ctrl 전역 매핑)를 설치하시겠습니까? (Y/n)"
if ($kanataAnswer -match '^[Nn]') {
    Write-Skip "kanata 설치를 건너뜁니다."
    return
}

# ==============================================================================
# [Step 1] 디렉터리 및 다운로드 준비
# ==============================================================================
Write-Step "[Step 1] kanata 바이너리 및 설정 경로 준비"

$kanataDir = "$env:APPDATA\kanata"
$kanataExe = "$kanataDir\kanata.exe"
$kanataKbd = "$kanataDir\kanata.kbd"

if (-not (Test-Path $kanataDir)) {
    New-Item -ItemType Directory -Path $kanataDir -Force | Out-Null
}

$doDownload = $true
if (Test-Path $kanataExe) {
    Write-Host "  ⚠️ kanata 바이너리가 이미 존재합니다: $kanataExe" -ForegroundColor Yellow
    $reinstall = Read-Host "  kanata 바이너리를 다시 다운로드하시겠습니까? (y/N)"
    if ($reinstall -notmatch '^[Yy]') {
        $doDownload = $false
        Write-Skip "기존 kanata 바이너리를 사용합니다."
    }
}

# TLS 1.2 보안 프로토콜 활성화 (GitHub HTTPS 연결 필수)
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

if ($doDownload) {
    Write-Host "  📦 GitHub 최신 릴리스에서 kanata 패키지 다운로드 중..." -ForegroundColor White
    
    # 프로세스 실행 중이면 임시 종료
    Get-Process kanata* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    $zipPath = Join-Path $env:TEMP "kanata_windows_binaries.zip"
    $extractPath = Join-Path $env:TEMP "kanata_extracted"

    try {
        # GitHub Release API에서 latest windows-binaries-x64.zip URL 조회
        $downloadUrl = ""
        try {
            $relApi = Invoke-RestMethod -Uri "https://api.github.com/repos/jtroo/kanata/releases/latest" -UseBasicParsing -ErrorAction Stop
            $zipAsset = $relApi.assets | Where-Object { $_.name -like "*windows-binaries-x64.zip*" } | Select-Object -First 1
            if ($zipAsset) {
                $downloadUrl = $zipAsset.browser_download_url
            }
        } catch {}

        if (-not $downloadUrl) {
            $downloadUrl = "https://github.com/jtroo/kanata/releases/download/v1.12.0/windows-binaries-x64.zip"
        }

        Write-Host "  다운로드 URL: $downloadUrl" -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop

        if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        # winIOv2 / wintercept 바이너리 탐색
        $exeFile = Get-ChildItem -Path $extractPath -Filter "kanata_windows_gui_winIOv2_x64.exe" -Recurse | Select-Object -First 1
        if (-not $exeFile) {
            $exeFile = Get-ChildItem -Path $extractPath -Filter "kanata_windows_tty_winIOv2_x64.exe" -Recurse | Select-Object -First 1
        }
        if (-not $exeFile) {
            $exeFile = Get-ChildItem -Path $extractPath -Filter "kanata_windows_gui_wintercept_x64.exe" -Recurse | Select-Object -First 1
        }
        if (-not $exeFile) {
            $exeFile = Get-ChildItem -Path $extractPath -Filter "*.exe" -Recurse | Select-Object -First 1
        }

        if (-not $exeFile) {
            throw "압축 파일 내에서 kanata 실행 파일(.exe)을 찾을 수 없습니다."
        }

        $exeName = $exeFile.Name
        Copy-Item -Path $exeFile.FullName -Destination $kanataExe -Force
        Write-Success "kanata 바이너리 저장 완료 ($exeName)"

        # 임시 정리
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Fail "kanata 다운로드 실패: $($_.Exception.Message)"
        Write-Host "  수동 다운로드 링크: https://github.com/jtroo/kanata/releases/latest" -ForegroundColor Yellow
        return
    }
}

# ==============================================================================
# [Step 2] kanata.kbd 설정 파일 생성
# ==============================================================================
Write-Step "[Step 2] kanata.kbd 키 매핑 설정 파일 생성"

$kbdContent = @'
;; kanata configuration for CapsLock overload (tap -> ESC, hold -> Ctrl)
(defsrc
  caps rctl
)

(defalias
  cap (tap-hold-press 200 200 esc lctl)
)

(deflayer default
  @cap rctl
)
'@

$doWriteKbd = $true
if (Test-Path $kanataKbd) {
    Write-Host "  ⚠️ kanata.kbd 설정 파일이 이미 존재합니다: $kanataKbd" -ForegroundColor Yellow
    $overwriteKbd = Read-Host "  설정 파일을 새 매핑(CapsLock -> ESC/Ctrl)으로 교체하시겠습니까? (y/N)"
    if ($overwriteKbd -notmatch '^[Yy]') {
        $doWriteKbd = $false
        Write-Skip "기존 kanata.kbd 설정을 유지합니다."
    }
}

if ($doWriteKbd) {
    $kbdContent | Out-File -FilePath $kanataKbd -Encoding utf8 -Force
    Write-Success "kanata.kbd 설정 파일 작성 완료"
}

# ==============================================================================
# [Step 3] Windows 작업 스케줄러(자동 실행) 등록
# ==============================================================================
Write-Step "[Step 3] Windows 작업 스케줄러 자동 실행 등록"

$taskName = "DevTools2_Kanata"

# 기존 작업 스케줄러 삭제 후 재등록
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

try {
    $action = New-ScheduledTaskAction -Execute $kanataExe -Argument "-c `"$kanataKbd`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Success "Windows 작업 스케줄러 등록 완료 ($taskName)"
} catch {
    # SYSTEM 계정 실패 시 현재 관리자 사용자 권한으로 등록 fallback
    try {
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Write-Success "Windows 작업 스케줄러 등록 완료 ($taskName)"
    } catch {
        Write-Fail "작업 스케줄러 등록 실패: $($_.Exception.Message)"
    }
}

# ==============================================================================
# [Step 4] kanata 실행 테스트 및 서비스 시작
# ==============================================================================
Write-Step "[Step 4] kanata 실행 및 백그라운드 적용"

# 기존 진행 프로세스 종료
Get-Process kanata -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

try {
    Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Start-Sleep -Seconds 1
    Write-Success "kanata 스케줄러 작업 시작 완료"
} catch {
    # 스케줄러 실행 실패 시 직접 백그라운드 프로세스로 띄움
    Start-Process -FilePath $kanataExe -ArgumentList "-c `"$kanataKbd`"" -WindowStyle Hidden
    Write-Success "kanata 백그라운드 프로세스 직접 실행 완료"
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host "kanata CapsLock (ESC/Ctrl) 전역 매핑 설정 완료!" -ForegroundColor Green
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host "  매핑 설정:" -ForegroundColor White
Write-Host "    - CapsLock 탭(짧게 누름)  -> ESC" -ForegroundColor DarkGray
Write-Host "    - CapsLock 홀드(조합키)   -> Ctrl" -ForegroundColor DarkGray
Write-Host "  적용 범위: Windows OS 전역 (WezTerm, WSL2, Zed 및 모든 앱)" -ForegroundColor White
Write-Host "===========================================================================" -ForegroundColor Magenta
Write-Host ""
