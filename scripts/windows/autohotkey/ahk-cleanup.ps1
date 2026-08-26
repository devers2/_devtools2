# ==============================================================================
# ahk-cleanup.ps1 — AutoHotkey 설치 현황 진단 및 정리 스크립트
#
# [기능]
#   1. 실행 중인 AHK 프로세스 / Task Scheduler 작업 / Startup 바로가기 /
#      레지스트리 Run 키 / 로컬 .ahk 파일을 전수 스캔
#   2. 각 항목에 대해
#      - dotfiles 설치본인지 여부 표시 (원본 / 수정본 / 구버전 / 관계 없음)
#      - 기능 추정 설명 표시
#   3. 번호 선택으로 원하는 항목만 삭제
#
# [실행 방법]
#   PowerShell(관리자) 에서:
#   irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/autohotkey/ahk-cleanup.ps1 | iex
#   또는 로컬 실행:
#   powershell -ExecutionPolicy Bypass -File .\ahk-cleanup.ps1
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'

# ── dotfiles 식별 패턴 ──────────────────────────────────────────────────────
$DOTFILES_PATTERNS = @(
    [regex]::Escape("_devtools2"),
    [regex]::Escape("wsl.localhost"),
    "devtools2-hotkey",
    "DevTools2"
)

# dotfiles가 설치한 AHK 파일의 특징 키워드
$DOTFILES_AHK_SIGNATURES = @(
    "devtools2-hotkey.ahk",
    "DevTools2",
    "_SetImeToEnglish",
    "_IsDevWindow"
)
# 구버전(WezTerm 시절) 식별 키워드
$WEZTERM_SIGNATURES = @(
    "wezterm",
    "_GetWeztermExe",
    "WezTermGroup",
    "wezterm-gui.exe"
)

function Is-DotfilesItem($text) {
    foreach ($p in $DOTFILES_PATTERNS) {
        if ($text -imatch $p) { return $true }
    }
    return $false
}

function Get-AhkFileStatus($filePath) {
    if (-not (Test-Path $filePath)) { return "파일없음" }
    $content = Get-Content $filePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $content) { return "읽기실패" }

    # 구버전(WezTerm) 판별 — 최우선
    foreach ($sig in $WEZTERM_SIGNATURES) {
        if ($content -imatch [regex]::Escape($sig)) {
            return "구버전(WezTerm 코드 포함 — 삭제 권장)"
        }
    }

    # dotfiles 원본 판별
    $matchCount = 0
    foreach ($sig in $DOTFILES_AHK_SIGNATURES) {
        if ($content -imatch [regex]::Escape($sig)) { $matchCount++ }
    }
    if ($matchCount -ge 3) { return "원본(dotfiles 최신)" }
    if ($matchCount -ge 1) { return "수정본 또는 유사 파일" }
    return "관계 없음(dotfiles 무관)"
}

function Guess-AhkPurpose($name, $path, $args) {
    $combined = "$name $path $args".ToLower()
    if ($combined -match "capslock|keyboard|remap|ime|devtools2-hotkey") { return "CapsLock 리매핑 / IME 자동 영문 전환 (devtools2)" }
    if ($combined -match "wezterm") { return "WezTerm 터미널 단축키 [구버전 devtools2 — 삭제 권장]" }
    if ($combined -match "terminal|wt\.exe") { return "Windows Terminal 단축키" }
    if ($combined -match "kanata") { return "kanata 키보드 리매퍼 (AHK와 저수준 후킹 충돌 — 동시 실행 금지)" }
    if ($combined -match "mouse|click|scroll") { return "마우스 자동화" }
    if ($combined -match "game|macro") { return "게임/매크로 자동화" }
    if ($combined -match "autohotkey") { return "AutoHotkey 스크립트 (기능 미상)" }
    return "기능 미상"
}

# ══════════════════════════════════════════════════════════════════════════════
# 스캔
# ══════════════════════════════════════════════════════════════════════════════
$items = [System.Collections.Generic.List[hashtable]]::new()

Write-Host ""
Write-Host "=================================================================" -ForegroundColor DarkCyan
Write-Host " AutoHotkey 설치 현황 스캔 중..." -ForegroundColor DarkCyan
Write-Host "=================================================================" -ForegroundColor DarkCyan

# ── [1] 실행 중인 AHK 프로세스 ───────────────────────────────────────────────
Write-Host ""
Write-Host "  [스캔 1/5] 실행 중인 프로세스..." -ForegroundColor DarkGray
try {
    Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" -ErrorAction SilentlyContinue |
    ForEach-Object {
        $cmd  = $_.CommandLine ?? ""
        $ahkFile = if ($cmd -match '"([^"]+\.ahk)"') { $Matches[1] }
                   elseif ($cmd -match '(\S+\.ahk)') { $Matches[1] }
                   else { "" }
        $items.Add(@{
            Type       = "프로세스"
            Name       = $_.Name
            Detail     = $cmd
            FilePath   = $ahkFile
            FileStatus = if ($ahkFile) { Get-AhkFileStatus $ahkFile } else { "파일경로 불명" }
            IsDotfiles = Is-DotfilesItem $cmd
            Purpose    = Guess-AhkPurpose $_.Name $ahkFile $cmd
            Pid        = $_.ProcessId
        })
    }
} catch {}

# ── [2] Task Scheduler ────────────────────────────────────────────────────────
Write-Host "  [스캔 2/5] Task Scheduler 작업..." -ForegroundColor DarkGray
try {
    $ts = New-Object -ComObject Schedule.Service
    $ts.Connect()
    $ts.GetFolder("\").GetTasks(0) | ForEach-Object {
        $taskXml = $_.Xml
        $exePath = if ($taskXml -match '<Command>(.*?)</Command>') { $Matches[1] } else { "" }
        $argsVal = if ($taskXml -match '<Arguments>(.*?)</Arguments>') { $Matches[1] } else { "" }
        $combined = "$exePath $argsVal"
        if ($combined -imatch "autohotkey|\.ahk") {
            $ahkFile = if ($argsVal -match '"([^"]+\.ahk)"') { $Matches[1] }
                       elseif ($argsVal -match '(\S+\.ahk)') { $Matches[1] }
                       else { "" }
            $items.Add(@{
                Type       = "Task Scheduler"
                Name       = $_.Name
                Detail     = "$exePath $argsVal"
                FilePath   = $ahkFile
                FileStatus = if ($ahkFile) { Get-AhkFileStatus $ahkFile } else { "파일경로 불명" }
                IsDotfiles = Is-DotfilesItem $combined
                Purpose    = Guess-AhkPurpose $_.Name $exePath $argsVal
                TaskName   = $_.Name
            })
        }
    }
} catch {}

# ── [3] Startup 폴더 바로가기 ─────────────────────────────────────────────────
Write-Host "  [스캔 3/5] Startup 폴더 바로가기..." -ForegroundColor DarkGray
$startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$wshShell = New-Object -ComObject WScript.Shell
Get-ChildItem -Path $startupDir -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $sc = $wshShell.CreateShortcut($_.FullName)
        $combined = "$($sc.TargetPath) $($sc.Arguments)"
        if ($combined -imatch "autohotkey|\.ahk") {
            $ahkFile = if ($sc.Arguments -match '"([^"]+\.ahk)"') { $Matches[1] }
                       elseif ($sc.Arguments -match '(\S+\.ahk)') { $Matches[1] }
                       else { "" }
            $items.Add(@{
                Type       = "Startup 바로가기"
                Name       = $_.Name
                Detail     = $combined
                FilePath   = $ahkFile
                FileStatus = if ($ahkFile) { Get-AhkFileStatus $ahkFile } else { "파일경로 불명" }
                IsDotfiles = Is-DotfilesItem $combined
                Purpose    = Guess-AhkPurpose $_.Name $sc.TargetPath $sc.Arguments
                LnkPath    = $_.FullName
            })
        }
    } catch {}
}

# ── [4] 레지스트리 Run 키 ─────────────────────────────────────────────────────
Write-Host "  [스캔 4/5] 레지스트리 Run 키..." -ForegroundColor DarkGray
@(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
) | ForEach-Object {
    $regPath = $_
    if (Test-Path $regPath) {
        (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).psobject.Properties |
        Where-Object { $_.Name -notmatch "^PS" -and $_.Value -imatch "autohotkey|\.ahk" } |
        ForEach-Object {
            $val = $_.Value
            $ahkFile = if ($val -match '"([^"]+\.ahk)"') { $Matches[1] }
                       elseif ($val -match '(\S+\.ahk)') { $Matches[1] }
                       else { "" }
            $items.Add(@{
                Type       = "레지스트리 Run"
                Name       = $_.Name
                Detail     = $val
                FilePath   = $ahkFile
                FileStatus = if ($ahkFile) { Get-AhkFileStatus $ahkFile } else { "파일경로 불명" }
                IsDotfiles = Is-DotfilesItem $val
                Purpose    = Guess-AhkPurpose $_.Name "" $val
                RegPath    = $regPath
                RegName    = $_.Name
            })
        }
    }
}

# ── [5] 로컬 .ahk 파일 (알려진 경로) ─────────────────────────────────────────
Write-Host "  [스캔 5/5] 로컬 AHK 파일..." -ForegroundColor DarkGray
@(
    "$env:LOCALAPPDATA\_devtools2\modules\autohotkey",
    $startupDir,
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Desktop"
) | ForEach-Object {
    if (Test-Path $_) {
        Get-ChildItem -Path $_ -Filter "*.ahk" -ErrorAction SilentlyContinue | ForEach-Object {
            $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
            $items.Add(@{
                Type       = "로컬 AHK 파일"
                Name       = $_.Name
                Detail     = $_.FullName
                FilePath   = $_.FullName
                FileStatus = Get-AhkFileStatus $_.FullName
                IsDotfiles = Is-DotfilesItem $_.FullName
                Purpose    = Guess-AhkPurpose $_.Name $_.FullName ($content ?? "")
                AhkPath    = $_.FullName
            })
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# 목록 출력
# ══════════════════════════════════════════════════════════════════════════════
if ($items.Count -eq 0) {
    Write-Host ""
    Write-Host "  AutoHotkey 관련 항목이 발견되지 않았습니다." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor DarkCyan
Write-Host " 발견된 AutoHotkey 관련 항목" -ForegroundColor DarkCyan
Write-Host "=================================================================" -ForegroundColor DarkCyan
Write-Host ""

for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items[$i]
    $num  = "[$($i + 1)]"

    # 출처 배지 및 색상
    if ($item.IsDotfiles) {
        if ($item.FileStatus -match "구버전")  { $badge = "[dotfiles 구버전]"; $badgeColor = "Red"    }
        elseif ($item.FileStatus -match "원본") { $badge = "[dotfiles 원본]  "; $badgeColor = "Green"  }
        elseif ($item.FileStatus -match "수정") { $badge = "[dotfiles 수정본]"; $badgeColor = "Yellow" }
        else                                    { $badge = "[dotfiles 관련]  "; $badgeColor = "Yellow" }
    } else {
        $badge = "[관계 없음]      "; $badgeColor = "DarkGray"
    }

    $typeColor = switch ($item.Type) {
        "프로세스"         { "Magenta"    }
        "Task Scheduler"   { "Cyan"       }
        "Startup 바로가기" { "Blue"       }
        "레지스트리 Run"   { "DarkYellow" }
        "로컬 AHK 파일"    { "White"      }
        default            { "White"      }
    }

    $statusColor = if ($item.FileStatus -match "구버전") { "Red" }
                   elseif ($item.FileStatus -match "원본") { "Green" }
                   else { "DarkGray" }

    Write-Host "  $num " -NoNewline -ForegroundColor White
    Write-Host $badge -NoNewline -ForegroundColor $badgeColor
    Write-Host " $($item.Type)" -NoNewline -ForegroundColor $typeColor
    Write-Host " — $($item.Name)" -ForegroundColor White
    Write-Host "       기능: $($item.Purpose)" -ForegroundColor DarkGray
    if ($item.FilePath) {
        Write-Host "       파일: $($item.FilePath)" -ForegroundColor DarkGray
        Write-Host "       상태: $($item.FileStatus)" -ForegroundColor $statusColor
    }
    Write-Host "       경로: $($item.Detail)" -ForegroundColor DarkGray
    Write-Host ""
}

# ══════════════════════════════════════════════════════════════════════════════
# 삭제 선택
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "=================================================================" -ForegroundColor DarkCyan
Write-Host " 삭제할 항목 번호를 입력하세요." -ForegroundColor Yellow
Write-Host " 예: 1,3,5   all = 전체 삭제   Enter = 종료" -ForegroundColor DarkGray
Write-Host "=================================================================" -ForegroundColor DarkCyan
$userInput = Read-Host "번호 입력"

if ([string]::IsNullOrWhiteSpace($userInput)) {
    Write-Host "  취소되었습니다." -ForegroundColor DarkGray
    exit 0
}

$selected = if ($userInput.Trim() -ieq "all") {
    1..$items.Count
} else {
    $userInput -split "[,\s]+" | Where-Object { $_ -match "^\d+$" } | ForEach-Object { [int]$_ }
}

Write-Host ""
Write-Host "  선택한 항목 삭제를 진행합니다..." -ForegroundColor Yellow
Write-Host ""

foreach ($num in $selected) {
    if ($num -lt 1 -or $num -gt $items.Count) {
        Write-Host "  [$num] 건너뜀 — 잘못된 번호" -ForegroundColor DarkGray
        continue
    }
    $item = $items[$num - 1]
    Write-Host "  [$num] $($item.Type) — $($item.Name)" -ForegroundColor Cyan

    try {
        switch ($item.Type) {
            "프로세스" {
                Stop-Process -Id $item.Pid -Force -ErrorAction Stop
                Write-Host "       ✅ 프로세스 종료 완료 (PID: $($item.Pid))" -ForegroundColor Green
            }
            "Task Scheduler" {
                $ts2 = New-Object -ComObject Schedule.Service
                $ts2.Connect()
                $ts2.GetFolder("\").DeleteTask($item.TaskName, 0)
                Write-Host "       ✅ Task Scheduler 작업 삭제 완료" -ForegroundColor Green
            }
            "Startup 바로가기" {
                Remove-Item $item.LnkPath -Force -ErrorAction Stop
                Write-Host "       ✅ 바로가기 삭제 완료" -ForegroundColor Green
            }
            "레지스트리 Run" {
                Remove-ItemProperty -Path $item.RegPath -Name $item.RegName -Force -ErrorAction Stop
                Write-Host "       ✅ 레지스트리 값 삭제 완료" -ForegroundColor Green
            }
            "로컬 AHK 파일" {
                Remove-Item $item.AhkPath -Force -ErrorAction Stop
                Write-Host "       ✅ 파일 삭제 완료" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "       ❌ 실패: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "          관리자 권한으로 재실행해보세요." -ForegroundColor DarkGray
    }
    Write-Host ""
}

Write-Host "=================================================================" -ForegroundColor DarkCyan
Write-Host "  완료! 변경사항 반영을 위해 로그아웃 후 재로그인을 권장합니다." -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor DarkCyan
Write-Host ""
