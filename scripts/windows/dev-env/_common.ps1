# ==============================================================================
# _common.ps1 — Windows dev-env 스크립트 공용 콘솔 출력/대기 헬퍼
# (scripts/linux/dev-env/_common.sh 의 PowerShell 대응 버전)
#
# [사용법 — 항상 온라인에서 받아 dot-source]
#   $headers = @{ 'Cache-Control' = 'no-cache, no-store, must-revalidate'; 'Pragma' = 'no-cache' }
#   $colorsContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/dev-env/_common.ps1" -Headers $headers -ErrorAction Stop
#   . ([scriptblock]::Create($colorsContent))
#
# [배경]
# Write-Step/Write-Success/Pause-Script/Wait-WithSpinner 등이 0.setup-wsl.ps1,
# 1.setup-autohotkey.ps1, 2.setup-windows-terminal.ps1, 3-1.setup-vscode.ps1,
# 3-2.setup-zed.ps1, 3-3.setup-orca.ps1 파일에 거의 동일하게 복붙되어 있었습니다. bash 쪽은
# _common.sh 라는 공용 라이브러리로 이미 이 문제를 해결했는데(온라인 source),
# PowerShell 쪽엔 대응 파일이 없어서 한쪽에서 고친 버그(Pause-Script 문구 등)가
# 다른 사본에는 전파되지 않는 드리프트가 실제로 발생했습니다(실측 확인).
# 이 파일이 그 공용 버전입니다 — ps1 원칙(항상 온라인 최신본, NoBOM, param()은
# 없음 — 이 파일은 함수 정의만 있어 param 블록이 필요 없음)을 그대로 따릅니다.
# ==============================================================================

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "===========================================================================" -ForegroundColor DarkGray
    Write-Host " $Message" -ForegroundColor Cyan
    Write-Host "===========================================================================" -ForegroundColor DarkGray
}

function Write-SubStep {
    param([string]$Message)
    Write-Host ""
    Write-Host "---------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[성공] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "[건너뜀] $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "[정보] $Message" -ForegroundColor White
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[경고] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[오류] $Message" -ForegroundColor Red
}

function Pause-Script {
    # 기본 메시지: 이 함수를 부르는 호출부는 대부분 곧이어 exit 하는 상황이라
    # "계속하려면"이 아니라 "종료합니다"가 정확합니다(0.setup-wsl.ps1에서 실측 확인 —
    # 8곳 호출부 전부 Pause-Script 바로 다음 줄이 exit였음). 정말로 스크립트를 계속
    # 진행해야 하는 드문 호출부가 있다면 그때만 -Message 로 다른 문구를 넘기면 됩니다.
    param([string]$Message = "엔터(Enter) 키를 누르면 종료합니다")
    Write-Host ""
    Write-Host "👉 ${Message}: " -ForegroundColor Yellow -NoNewline
    [void][System.Console]::ReadLine()
}

# Yes/No 대화형 확인 프롬프트 공용 헬퍼 (bash _common.sh 의 prompt_confirm 대응)
# 사용법: if (Prompt-Confirm "👉 AutoHotKey를 설치하시겠습니까?" "Y") { ... }
function Prompt-Confirm {
    param(
        [string]$Message,
        [string]$Default = "N"
    )
    Write-Host ""
    if ($Default -eq "Y" -or $Default -eq "y") {
        Write-Host "$Message [" -ForegroundColor Yellow -NoNewline
        Write-Host "Y" -ForegroundColor Green -NoNewline
        Write-Host "/n]: " -ForegroundColor Yellow -NoNewline
        $ans = Read-Host
        if ([string]::IsNullOrWhiteSpace($ans)) { return $true }
        return ($ans -match '^[Yy]')
    } else {
        Write-Host "$Message [y/" -ForegroundColor Yellow -NoNewline
        Write-Host "N" -ForegroundColor Green -NoNewline
        Write-Host "]: " -ForegroundColor Yellow -NoNewline
        $ans = Read-Host
        if ([string]::IsNullOrWhiteSpace($ans)) { return $false }
        return ($ans -match '^[Yy]')
    }
}

# 번호 선택 대화형 프롬프트 공용 헬퍼 (Prompt-Confirm 의 숫자형 버전)
# - 기본값 번호는 Green, 나머지 번호와 구분자는 Yellow (Prompt-Confirm [Y/n] 패턴과 동일)
# - 유효하지 않은 번호 입력 시 재입력 요구 (빈 입력은 Default 로 처리)
# - 반환값: 선택된 1-based 인덱스 (int)
#
# 사용법:
#   $idx = Prompt-Choice "👉 버전을 선택하세요" @("Ubuntu (최신 LTS)", "Ubuntu-24.04", "Ubuntu-22.04") 1
#   switch ($idx) {
#       1 { $distroId = "Ubuntu" }
#       2 { $distroId = "Ubuntu-24.04" }
#       3 { $distroId = "Ubuntu-22.04" }
#   }
function Prompt-Choice {
    param(
        [string]  $Message,
        [string[]]$Options,
        [int]     $Default = 1   # 1-based 기본 선택 번호
    )
    $result = 0
    do {
        Write-Host ""
        Write-Host "$Message [" -ForegroundColor Yellow -NoNewline
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $num = $i + 1
            if ($num -eq $Default) {
                Write-Host "$num" -ForegroundColor Green -NoNewline
            } else {
                Write-Host "$num" -ForegroundColor Yellow -NoNewline
            }
            if ($i -lt $Options.Count - 1) {
                Write-Host "/" -ForegroundColor Yellow -NoNewline
            }
        }
        Write-Host "]: " -ForegroundColor Yellow -NoNewline
        $ans = Read-Host
        $ans = $ans.Trim()
        if ($ans -eq "") { $ans = "$Default" }
        [int]::TryParse($ans, [ref]$result) | Out-Null
    } while ($result -lt 1 -or $result -gt $Options.Count)
    return $result
}

# ==============================================================================
# 한글 키보드(IME) 감지 및 비밀번호 입력 공용 헬퍼
# ==============================================================================
# Windows Win32 IME API (ImmGetDefaultIMEWnd / IMC_GETCONVERSIONMODE) 를 통해
# 현재 포그라운드 콘솔 창의 키보드가 한글 입력 모드인지 실시간으로 검사합니다.
if (-not ([System.Management.Automation.PSTypeName]'DevTools2.ImeHelper').Type) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace DevTools2 {
    public class ImeHelper {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("imm32.dll")]
        public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        private const uint WM_IME_CONTROL = 0x0283;
        private const uint IMC_GETCONVERSIONMODE = 0x0001;
        private const int IME_CMODE_HANGUL = 0x0001;

        public static bool IsHangulMode() {
            try {
                IntPtr hwnd = GetForegroundWindow();
                if (hwnd == IntPtr.Zero) return false;
                IntPtr imeWnd = ImmGetDefaultIMEWnd(hwnd);
                if (imeWnd == IntPtr.Zero) return false;
                IntPtr mode = SendMessage(imeWnd, WM_IME_CONTROL, (IntPtr)IMC_GETCONVERSIONMODE, IntPtr.Zero);
                return ((mode.ToInt32() & IME_CMODE_HANGUL) != 0);
            } catch {
                return false;
            }
        }
    }
}
"@ -ErrorAction SilentlyContinue
    } catch {}
}

# 현재 활성 창의 키보드가 한글 입력 상태인지 여부 반환 ($true / $false)
function Test-IsHangulIme {
    try {
        if ([System.Management.Automation.PSTypeName]'DevTools2.ImeHelper'.Type) {
            return [DevTools2.ImeHelper]::IsHangulMode()
        }
    } catch {}
    return $false
}

# 비밀번호 입력 대화형 프롬프트 공용 헬퍼 (한글/다국어 IME 상태 감지 + 비영문 문자 입력 시 경고 및 재입력 유도)
# - 입력 전: 키보드가 한글/다국어 모드이면 주황색 경고 메시지 출력
# - 입력 후: 마스킹으로 인해 비영문(한글, 일어, 중문, 전각문자 등)이 들어간 경우 에러 경고 후 재입력
# - 반환값: SecureString
#
# 사용법:
#   $securePw = Prompt-Password "👉 비밀번호(password) 입력: "
function Prompt-Password {
    param(
        [string]$Message = "👉 비밀번호(password) 입력: "
    )
    while ($true) {
        # 1. 입력 직전 실시간 한글 IME 상태 확인 및 경고
        if (Test-IsHangulIme) {
            Write-Host ""
            Write-Host "  ⚠️  [주의] 현재 키보드가 '한글/다국어' 입력 모드입니다! [한/영] 키를 눌러 영문으로 전환해 주세요." -ForegroundColor Yellow
        }

        Write-Host $Message -ForegroundColor Yellow -NoNewline
        $securePw = Read-Host -AsSecureString

        # 평문으로 변환하여 유효성 및 비영문(Non-ASCII) 포함 여부 검증
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePw)
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        if ([string]::IsNullOrEmpty($plain)) {
            Write-Warn "비밀번호가 입력되지 않았습니다. 다시 입력해 주세요."
            Write-Host ""
            continue
        }

        # 비영문/비ASCII 문자(한글, 일어, 중문, 전각 기호 등: ASCII 32~126 범위를 벗어나는 모든 유니코드) 검사
        if ($plain -match '[^\u0020-\u007E]') {
            Write-Host ""
            Write-Host "  ❌ [오류] 입력된 비밀번호에 '비영문(한글/다국어/전각)' 문자가 포함되어 있습니다." -ForegroundColor Red
            Write-Host "      키보드를 영문 입력 상태로 전환한 뒤 다시 입력해 주세요." -ForegroundColor Yellow
            Write-Host ""
            continue
        }

        return $securePw
    }
}

# 프로세스 종료 시까지 스피너를 표시해 대기 (타임아웃 없음 — 프로세스가 끝날 때까지 무조건 대기)
function Wait-ProcessWithSpinner {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Message
    )
    $spinner = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $spinIdx = 0
    while (-not $Process.HasExited) {
        $char = $spinner[$spinIdx]
        Write-Host -NoNewline "`r  [$char] $Message...   " -ForegroundColor Cyan
        $spinIdx = ($spinIdx + 1) % $spinner.Count
        Start-Sleep -Milliseconds 150
    }
    Write-Host "`r  [완료] $Message 완료!   " -ForegroundColor Green
}

# 조건(scriptblock)이 참이 될 때까지 스피너를 표시해 대기 (타임아웃 지원, 초과 시 $false 반환)
# ⚠️ 호출부는 반드시 반환값을 확인해야 합니다 — 확인하지 않으면 타임아웃 후에도 마치
# 정상 완료된 것처럼 다음 단계로 조용히 넘어갈 수 있습니다(0.setup-wsl.ps1에서 실측 확인:
# PowerShell은 아직 안 끝난 프로세스의 .ExitCode를 읽어도 예외 없이 빈 값만 반환하므로
# "-eq 3010" 등의 비교가 조용히 false가 되어버림).
function Wait-WithSpinner {
    param(
        [string]$Message,
        [scriptblock]$Condition,
        [int]$MaxTimeoutSeconds = 300
    )
    $spinner = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $spinIdx = 0
    $startTime = Get-Date
    while ($true) {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -gt $MaxTimeoutSeconds) {
            Write-Host "`r  [시간 초과] $Message (제한 시간 초과)   " -ForegroundColor Red
            return $false
        }
        $done = [bool](& $Condition)
        if ($done) {
            Write-Host "`r  [완료] $Message 완료!   " -ForegroundColor Green
            return $true
        }
        $char = $spinner[$spinIdx % $spinner.Count]
        Write-Host -NoNewline "`r  [$char] $Message...   " -ForegroundColor Cyan
        Start-Sleep -Milliseconds 150
        $spinIdx++
    }
}

# ==============================================================================
# WSL 디스트로 상태 확인 / 안전 종료 대기 공용 헬퍼
# ==============================================================================
# wsl -l -v 출력에서 null 바이트를 제거한 뒤 파싱하는 방식으로 구현한다.
# (wsl.exe는 UTF-16LE로 출력하므로 PowerShell이 null 바이트를 포함하는 경우가 있음)

# 지정한 WSL 디스트로가 현재 Running 상태인지 여부를 반환한다.
# 사용법: $isRunning = Test-WslDistroRunning "devtools2"
function Test-WslDistroRunning {
    param([string]$Distro)
    $raw   = wsl.exe -l -v 2>$null
    $lines = $raw -split "`r?`n" | ForEach-Object { $_ -replace "`0", "" }
    return [bool]($lines | Where-Object { $_ -match $Distro -and $_ -match 'Running' })
}

# wsl --shutdown 을 실행한 뒤 지정한 디스트로가 완전히 Stopped 될 때까지 스피너로 대기한다.
# - 타임아웃(기본 60초) 초과 시 오류 메시지 출력 후 $false 반환
# - 성공 시 $true 반환
#
# 사용법:
#   if (-not (Invoke-WslShutdown -Distro "devtools2")) {
#       Write-Fail "WSL 종료 실패"
#       Pause-Script; exit 1
#   }
function Invoke-WslShutdown {
    param(
        [string]$Distro          = "devtools2",
        [int]   $TimeoutSeconds  = 60,
        [string]$ShutdownMessage = "WSL 가상 머신 완전 종료 대기 중"
    )

    Write-Info "wsl --shutdown 실행 중..."
    wsl --shutdown 2>$null

    # 디스트로가 이미 Stopped 상태이면 즉시 성공 반환
    if (-not (Test-WslDistroRunning -Distro $Distro)) {
        Write-Host "  [완료] $Distro 이미 종료됨 — 즉시 계속합니다." -ForegroundColor Green
        return $true
    }

    $spinner   = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')
    $spinIdx   = 0
    $startTime = Get-Date

    while ($true) {
        $elapsed = (Get-Date) - $startTime

        # 타임아웃 초과 시 실패
        if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
            Write-Host ""
            Write-Fail "WSL 종료 대기 시간 초과 (${TimeoutSeconds}초 초과)"
            Write-Info "  → PC를 재부팅한 후 다시 실행해 주세요."
            return $false
        }

        # 디스트로가 멈췄으면 성공
        if (-not (Test-WslDistroRunning -Distro $Distro)) {
            $sec = [int]$elapsed.TotalSeconds
            Write-Host "`r  [완료] $ShutdownMessage 완료! (${sec}초 소요)   " -ForegroundColor Green
            return $true
        }

        $remaining = [int]($TimeoutSeconds - $elapsed.TotalSeconds)
        $char      = $spinner[$spinIdx % $spinner.Count]
        Write-Host -NoNewline "`r  [$char] $ShutdownMessage... (제한 ${TimeoutSeconds}초 / 남은 ${remaining}초)   " -ForegroundColor Cyan
        Start-Sleep -Milliseconds 500
        $spinIdx++
    }
}

# ==============================================================================
# 다운로드 게이지 프로그레스 바 공용 헬퍼 (스트림 기반 실시간 프로그레스 바)
# ==============================================================================
# Bash 환경(_common.sh 의 download_with_progress)과 100% 동일한 게이지 바로 렌더링합니다.
# 사용법:
#   # 단일 URL:
#   $ok = Download-WithProgress -Url "https://example.com/file.zip" -DestinationPath "$env:TEMP\file.zip" -Description "AutoHotkey v2"
#   # 다중 URL 폴백:
#   $ok = Download-WithProgress -Urls @("http://mirror1/f.zip", "http://mirror2/f.zip") -DestinationPath "$env:TEMP\file.zip"
function Download-WithProgress {
    param(
        [string]  $Url,
        [string[]]$Urls,
        [string]  $DestinationPath,
        [string]  $Description = "파일"
    )

    $targetUrls = @()
    if ($Urls -and $Urls.Count -gt 0) {
        $targetUrls = $Urls
    } elseif ($Url) {
        $targetUrls = @($Url)
    }

    if ($targetUrls.Count -eq 0) {
        return $false
    }

    $destDir = Split-Path $DestinationPath -Parent
    if (-not [string]::IsNullOrEmpty($destDir) -and -not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $finalSuccess = $false

    for ($i = 0; $i -lt $targetUrls.Count; $i++) {
        $currentUrl = $targetUrls[$i]
        $domain = $currentUrl
        try {
            $domain = ([System.Uri]$currentUrl).Host
        } catch {}

        if ($targetUrls.Count -gt 1) {
            Write-Host "   📥 $Description 다운로드 시도 [$($i + 1)/$($targetUrls.Count)] ($domain)..." -ForegroundColor Cyan
        } else {
            Write-Host "   📥 $Description 다운로드 중..." -ForegroundColor Cyan
        }

        Remove-Item $DestinationPath -Force -ErrorAction SilentlyContinue

        $downloadSuccess = $false
        $getResp = $null
        $inStream = $null
        $outStream = $null

        try {
            $getReq = [System.Net.HttpWebRequest]::Create($currentUrl)
            $getReq.Timeout = 10000
            $getReq.ReadWriteTimeout = 60000
            $getReq.AllowAutoRedirect = $true
            $getReq.Headers.Add('Cache-Control', 'no-cache, no-store, must-revalidate')
            $getReq.Headers.Add('Pragma', 'no-cache')

            $getResp = $getReq.GetResponse()
            $totalBytes = $getResp.ContentLength
            $inStream = $getResp.GetResponseStream()

            $outStream = [System.IO.File]::Create($DestinationPath)
            $buffer = New-Object byte[] 65536
            $downloadedBytes = 0
            $barLen = 50
            $lastUpdate = [DateTime]::MinValue

            while (($bytesRead = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $outStream.Write($buffer, 0, $bytesRead)
                $downloadedBytes += $bytesRead

                $now = [DateTime]::UtcNow
                if (($now - $lastUpdate).TotalMilliseconds -ge 80 -or ($totalBytes -gt 0 -and $downloadedBytes -eq $totalBytes)) {
                    $lastUpdate = $now
                    if ($totalBytes -gt 0) {
                        $pct = ($downloadedBytes / $totalBytes) * 100
                        $filled = [int]($barLen * ($pct / 100))
                        $pctStr = (" {0:N1}% " -f $pct)
                        $leftLen = [int](($barLen - $pctStr.Length) / 2)

                        $barChars = New-Object char[] $barLen
                        for ($k = 0; $k -lt $barLen; $k++) {
                            if ($k -ge $leftLen -and $k -lt ($leftLen + $pctStr.Length)) {
                                $barChars[$k] = $pctStr[$k - $leftLen]
                            } elseif ($k -lt $filled) {
                                $barChars[$k] = '='
                            } else {
                                $barChars[$k] = ' '
                            }
                        }
                        $bar = -join $barChars
                        Write-Host -NoNewline "`r   [$bar]"
                    } else {
                        $mb = [math]::Round($downloadedBytes / 1MB, 1)
                        Write-Host -NoNewline "`r   [ 다운로드 중... ${mb} MB ]"
                    }
                }
            }

            # 다운로드 완료 후 게이지 바 라인 지우기
            Write-Host -NoNewline ("`r   " + (" " * ($barLen + 4)) + "`r")
            $downloadSuccess = $true
        } catch {
            $downloadSuccess = $false
        } finally {
            if ($outStream) { try { $outStream.Close() } catch {} }
            if ($inStream) { try { $inStream.Close() } catch {} }
            if ($getResp) { try { $getResp.Close() } catch {} }
        }

        if ($downloadSuccess -and (Test-Path $DestinationPath) -and (Get-Item $DestinationPath).Length -gt 0) {
            $finalSuccess = $true
            break
        } else {
            if ($targetUrls.Count -gt 1) {
                Write-Warn "   → 미러 [$($i + 1)] ($domain) 다운로드 실패. 다음 미러로 전환합니다..."
            }
            Remove-Item $DestinationPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $finalSuccess
}

# ==============================================================================
# 콘솔 빠른 편집(QuickEdit) 모드 세션 한정 안전 제어 헬퍼
# ==============================================================================
# Windows 터미널에서 마우스 클릭 시 콘솔 출력이 일시 중단(프리징)되는 현상을 방지합니다.
# - Windows 전체/레지스트리 설정을 건드리지 않고 '현재 PowerShell 세션 핸들'에만 메모리 상에서 적용
# - 스크립트 정상 종료, 예외 발생, Ctrl+C 중단(Console.CancelKeyPress) 시 원래 모드로 100% 자동 복원
# ==============================================================================
if (-not ([System.Management.Automation.PSTypeName]'DevTools2.ConsoleHelper').Type) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace DevTools2 {
    public static class ConsoleHelper {
        private const int STD_INPUT_HANDLE = -10;
        private const uint ENABLE_QUICK_EDIT_MODE = 0x0040;
        private const uint ENABLE_EXTENDED_FLAGS = 0x0080;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetStdHandle(int nStdHandle);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

        private static uint originalMode = 0;
        private static bool isModified = false;
        private static ConsoleCancelEventHandler cancelHandler = null;

        public static bool DisableQuickEdit() {
            try {
                IntPtr hStdin = GetStdHandle(STD_INPUT_HANDLE);
                if (hStdin == IntPtr.Zero || hStdin == (IntPtr)(-1)) return false;

                if (!GetConsoleMode(hStdin, out originalMode)) return false;

                // 이미 수정된 상태라면 중복 등록 방지
                if (!isModified) {
                    // Ctrl+C 이벤트 발생 시 안전 복원 핸들러 등록
                    cancelHandler = new ConsoleCancelEventHandler((sender, args) => {
                        RestoreQuickEdit();
                    });
                    Console.CancelKeyPress += cancelHandler;
                }

                uint newMode = (originalMode & ~ENABLE_QUICK_EDIT_MODE) | ENABLE_EXTENDED_FLAGS;
                bool result = SetConsoleMode(hStdin, newMode);
                if (result) isModified = true;
                return result;
            } catch {
                return false;
            }
        }

        public static bool RestoreQuickEdit() {
            try {
                if (!isModified) return true;

                IntPtr hStdin = GetStdHandle(STD_INPUT_HANDLE);
                if (hStdin == IntPtr.Zero || hStdin == (IntPtr)(-1)) return false;

                bool result = SetConsoleMode(hStdin, originalMode | ENABLE_EXTENDED_FLAGS);
                if (result) {
                    isModified = false;
                    if (cancelHandler != null) {
                        try { Console.CancelKeyPress -= cancelHandler; } catch {}
                        cancelHandler = null;
                    }
                }
                return result;
            } catch {
                return false;
            }
        }
    }
}
"@ -ErrorAction SilentlyContinue
    } catch {}
}

function Disable-ConsoleQuickEdit {
    try {
        if ([System.Management.Automation.PSTypeName]'DevTools2.ConsoleHelper'.Type) {
            return [DevTools2.ConsoleHelper]::DisableQuickEdit()
        }
    } catch {}
    return $false
}

function Restore-ConsoleQuickEdit {
    try {
        if ([System.Management.Automation.PSTypeName]'DevTools2.ConsoleHelper'.Type) {
            return [DevTools2.ConsoleHelper]::RestoreQuickEdit()
        }
    } catch {}
    return $false
}

