param(
    # WSL2 배포판 이름 (기본값: 첫 번째로 찾은 기본 배포판 자동 감지) — 지금은 사용하지 않지만
    # 마스터 스크립트(setup-devtools2-wsl.ps1)가 다른 하위 스크립트와 동일한 방식으로
    # Invoke-RemotePsScript -Arguments 를 넘기므로 시그니처를 맞춰둡니다.
    [string]$WslDistro = ""
)

# ==============================================================================
# Windows Terminal 폰트/테마/단축키 설정 스크립트 (2.setup-windows-terminal.ps1)
#
# 주요 기능:
#   1. Windows Terminal 설치 확인 (winget 폴백)
#   2. Nerd Font 설치 (기본값: D2KodingLigature Nerd Font Mono, 대안: JetBrainsMono NFM)
#      — 둘 다 한글을 지원하지만, D2Koding은 한글 자체 글리프가 있어 Windows Terminal이
#        폰트 폴백을 지원하지 않는 한계를 우회할 수 있습니다(JetBrainsMono는 영문 전용이라
#        한글은 OS가 자동 대체하는 다른 폰트로 렌더링되어 정렬이 어긋날 수 있음).
#   3. Windows Terminal settings.json에 Kanagawa 색 배열 추가, 기본 폰트/투명도(97) 적용
#   4. ALT+c(command-palette) / ALT+h(bw-server-manager) fzf 스크립트 실행 단축키 등록
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
#
# ⚠️ Windows Terminal settings.json의 defaultProfile(콜드 실행 시 첫 탭)은 이 스크립트가
#   건드리지 않습니다. WSL 배포판을 재설치/재등록할 때마다 Windows Terminal이 새 GUID로
#   프로필을 다시 만들어서(이 PC에서 실측: "devtools2"라는 이름의 중복 프로필이 수십 개
#   쌓여있었음) 어떤 GUID가 "현재 살아있는" 배포판인지 안전하게 특정할 방법이 없기
#   때문입니다. Ctrl+Alt+T(devtools2-hotkey.ahk)는 GUID가 아니라 wsl.exe를 직접 실행해서
#   이 문제를 우회합니다. 콜드 실행 시 기본 프로필도 WSL로 바꾸고 싶다면, Windows
#   Terminal 설정 UI에서 원하는 devtools2 프로필을 직접 "시작 > 기본 프로필"로 지정하세요.
# ------------------------------------------------------------------------------
# ==============================================================================

# --- 한글 깨짐 방지: 출력 인코딩을 UTF-8 로 설정
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- 윈도우 PowerShell 기본 파란색 프로그레스바 팝업 끄기 (텍스트 깨짐 및 커서 겹침 방지)
$ProgressPreference = 'SilentlyContinue'

# ==============================================================================
# 헬퍼 함수
# ==============================================================================

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

function Write-Warn {
    param([string]$Message)
    Write-Host "[경고] $Message" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🚀 Windows Terminal 폰트/테마/단축키 설정" -ForegroundColor DarkCyan
Write-Host "===========================================================================" -ForegroundColor DarkCyan

# ==============================================================================
# [Step 1] Windows Terminal 설치 확인
# ==============================================================================
Write-Step "[Step 1] Windows Terminal 설치 확인"

$wtInstalled = [bool](Get-Command wt.exe -ErrorAction SilentlyContinue)
if ($wtInstalled) {
    Write-Skip "Windows Terminal이 이미 설치되어 있습니다."
} else {
    Write-Info "Windows Terminal을 winget으로 설치합니다..."
    $p = Start-Process winget -ArgumentList "install --id Microsoft.WindowsTerminal --silent --accept-source-agreements --accept-package-agreements" -WindowStyle Hidden -PassThru -Wait
    $successCodes = @(0, 3010, -1978335189, -1978335212)
    if ($successCodes -contains $p.ExitCode -or (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
        Write-Success "Windows Terminal 설치/확인 완료"
    } else {
        Write-Fail "Windows Terminal 설치 실패 (종료 코드: $($p.ExitCode))"
        Write-Host "  수동 설치: https://aka.ms/terminal" -ForegroundColor Yellow
    }
}

# ==============================================================================
# [Step 2] Nerd Font 설치 (기본값: D2KodingLigature Nerd Font Mono)
# ==============================================================================
Write-Step "[Step 2] Nerd Font 설치"

Write-Host ""
Write-Host "  터미널 폰트를 선택하세요:" -ForegroundColor Cyan
Write-Host "    [Y] D2KodingLigature Nerd Font Mono - 한글 자체 지원, 리거처 포함 (권장, 기본값)" -ForegroundColor Green
Write-Host "    [N] JetBrainsMono NFM               - 영문 전용, 한글은 OS 대체 폰트로 렌더링" -ForegroundColor Gray
Write-Host "👉 D2KodingLigature로 설치할까요? [" -ForegroundColor Yellow -NoNewline
Write-Host "Y" -ForegroundColor Green -NoNewline
Write-Host "/n]: " -ForegroundColor Yellow -NoNewline
$fontChoice = Read-Host

if ($fontChoice -match '^[Nn]') {
    $fontFiles = @("JetBrainsMonoNerdFontMono-Regular.ttf", "JetBrainsMonoNerdFontMono-Bold.ttf")
    $fontFace  = "JetBrainsMono NFM"
} else {
    $fontFiles = @("D2KodingLigatureNerdFontMono-Regular.ttf", "D2KodingLigatureNerdFontMono-Bold.ttf")
    $fontFace  = "D2KodingLigature Nerd Font Mono"
}
Write-Host "  선택된 폰트: $fontFace" -ForegroundColor White

# WSL2 배포판 자동 감지 (폰트 원본을 WSL2 저장소에서 우선 복사하기 위함)
$WslDistroDetected = $WslDistro
if ($WslDistroDetected -eq "") {
    $distroList = (wsl --list --quiet 2>$null) | Where-Object { $_ -ne "" }
    if ($distroList.Count -gt 0) {
        $WslDistroDetected = ($distroList[0] -replace "`0", "").Trim()
    }
}
$WslRoot = if ($WslDistroDetected -ne "") { "\\wsl.localhost\$WslDistroDetected" } else { "" }
$DevTools2Wsl = if ($env:DEVTOOLS2 -and (Test-Path $env:DEVTOOLS2)) { $env:DEVTOOLS2 } elseif ($WslRoot -ne "") { "$WslRoot\var\opt\_devtools2" } else { "" }

$UserFontsDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$FontRegPath  = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

if (-not (Test-Path $UserFontsDir)) {
    New-Item -ItemType Directory -Path $UserFontsDir -Force | Out-Null
}
if (-not (Test-Path $FontRegPath)) {
    New-Item -Path $FontRegPath -Force | Out-Null
}

# 폰트 레지스트리 등록 이름 매핑 (파일명 -> "표시 폰트명 (TrueType)")
# TTF 내부 실제 family name과 파일명이 다를 수 있어 레지스트리 이름은 family name 기준으로 고정합니다.
$fontDisplayNames = @{
    "D2KodingLigatureNerdFontMono-Regular.ttf" = "D2KodingLigature Nerd Font Mono"
    "D2KodingLigatureNerdFontMono-Bold.ttf"    = "D2KodingLigature Nerd Font Mono Bold"
    "JetBrainsMonoNerdFontMono-Regular.ttf"    = "JetBrainsMono NFM"
    "JetBrainsMonoNerdFontMono-Bold.ttf"       = "JetBrainsMono NFM Bold"
}

function Install-DevtoolsFont {
    param([string]$FontFileName, [string]$SourcePath)
    $destPath = "$UserFontsDir\$FontFileName"
    if (Test-Path $destPath) {
        Write-Skip "폰트 이미 설치됨: $FontFileName"
        return
    }
    if (-not (Test-Path $SourcePath)) {
        Write-Warn "폰트 원본을 찾을 수 없습니다: $SourcePath"
        return
    }
    try {
        Copy-Item -Path $SourcePath -Destination $destPath -Force
        $regName = $fontDisplayNames[$FontFileName]
        if (-not $regName) { $regName = [System.IO.Path]::GetFileNameWithoutExtension($FontFileName) + ' (TrueType)' } else { $regName = "$regName (TrueType)" }
        Set-ItemProperty -Path $FontRegPath -Name $regName -Value $destPath -Force
        Write-Success "폰트 설치: $FontFileName"
    } catch {
        Write-Warn "폰트 설치 실패: $FontFileName - $($_.Exception.Message)"
    }
}

$hasWslFonts = ($DevTools2Wsl -ne "") -and (Test-Path "$DevTools2Wsl\assets\fonts")

if ($hasWslFonts) {
    Write-Host "  WSL2 저장소에서 폰트를 복사합니다: $DevTools2Wsl\assets\fonts" -ForegroundColor White
    foreach ($f in $fontFiles) {
        Install-DevtoolsFont -FontFileName $f -SourcePath "$DevTools2Wsl\assets\fonts\$f"
    }
} else {
    Write-Host "  WSL2 저장소를 찾을 수 없어 GitHub 원격 저장소에서 직접 다운로드합니다..." -ForegroundColor Yellow
    $tempDownloadDir = Join-Path $env:TEMP "devtools2_fonts_tmp"
    if (-not (Test-Path $tempDownloadDir)) {
        New-Item -ItemType Directory -Path $tempDownloadDir -Force | Out-Null
    }
    $gitHubFontBaseUrl = "https://raw.githubusercontent.com/devers2/_devtools2/main/assets/fonts"
    foreach ($f in $fontFiles) {
        $destPath = "$UserFontsDir\$f"
        if (Test-Path $destPath) {
            Write-Skip "폰트 이미 설치됨: $f"
            continue
        }
        $tempFile = Join-Path $tempDownloadDir $f
        try {
            Write-Host "  다운로드 중: $f..." -ForegroundColor White
            Invoke-WebRequest -Uri "$gitHubFontBaseUrl/$f" -OutFile $tempFile -ErrorAction Stop
            Install-DevtoolsFont -FontFileName $f -SourcePath $tempFile
        } catch {
            Write-Warn "원격 폰트 다운로드 실패: $f - $($_.Exception.Message)"
        }
    }
    Remove-Item -Path $tempDownloadDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ==============================================================================
# [Step 3] settings.json 갱신 (Kanagawa 테마, 폰트/투명도, ALT+c/h 단축키)
# ==============================================================================
Write-Step "[Step 3] Windows Terminal settings.json 갱신"

# ── Windows Terminal 실행 중이면 종료 여부 확인 (state.json 덮어쓰기 방지) ──────
# 살아있는 Windows Terminal 프로세스는 종료될 때 자기 메모리 상태(state.json)를 다시
# 디스크에 저장하므로, 이 스크립트가 state.json을 정리해도 곧바로 덮어써질 수 있습니다
# (실측 확인: WT가 떠 있는 채로 정리해도 재확인해보면 원상복구돼 있었음).
#
# $env:WT_SESSION 은 "지금 이 스크립트 자신이 Windows Terminal 안에서 실행 중인지"를
# 알려주는 값입니다 — 관리자 권한 승격(-Verb RunAs)으로 새 프로세스가 뜨더라도, Windows
# 11 기본 터미널 설정이 Windows Terminal이면 그 새 프로세스도 다시 Windows Terminal
# 안에서 열리므로 이 값이 그대로 설정돼 있을 수 있습니다. 이 경우 모든 Windows Terminal을
# 강제 종료하면 지금 실행 중인 이 설치 스크립트 자신도 같이 끊겨버리므로, 절대 자동
# 종료하지 않고 state.json 정리만 건너뜁니다.
$skipStateCleanup = $false
$wtProcesses = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue
if ($wtProcesses) {
    if ($env:WT_SESSION) {
        Write-Warn "이 스크립트 자체가 Windows Terminal 안에서 실행 중이라 자동으로 닫을 수 없습니다(설치가 끊깁니다)."
        Write-Warn "settings.json은 정상 갱신되지만, WSL 중복 프로필의 state.json 정리는 이번엔 건너뛰게 됩니다."
        Write-Warn "완전히 정리하려면 지금 중단한 뒤 Windows Terminal이 아닌 곳(시작 메뉴에서 'Windows PowerShell' 검색)에서 이 스크립트를 다시 실행해주세요."
        Write-Host ""
        # 중요한 갈림길이라 기본값(Enter로 통과) 없이, y/n 둘 중 하나를 명시적으로 입력할 때까지 재질문
        $wtSessionChoice = ""
        while ($wtSessionChoice -notmatch '^[YyNn]') {
            Write-Host "👉 state.json 정리 없이 이대로 진행할까요? (y/n): " -ForegroundColor Yellow -NoNewline
            $wtSessionChoice = Read-Host
        }
        if ($wtSessionChoice -match '^[Yy]') {
            $skipStateCleanup = $true
        } else {
            Write-Fail "설치를 중단합니다."
            exit 1
        }
    } else {
        Write-Host ""
        Write-Host "  Windows Terminal이 실행 중입니다(지금 이 설치 스크립트와는 다른 창)." -ForegroundColor Yellow
        Write-Host "  WSL 중복 프로필을 완전히 정리하려면 지금 전부 닫아야 합니다." -ForegroundColor Yellow
        Write-Host "👉 Windows Terminal을 지금 닫고 계속할까요? [y/" -ForegroundColor Yellow -NoNewline
        Write-Host "N" -ForegroundColor Green -NoNewline
        Write-Host "]: " -ForegroundColor Yellow -NoNewline
        $closeChoice = Read-Host
        if ($closeChoice -match '^[Yy]') {
            $wtProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            Write-Success "Windows Terminal을 종료했습니다."
        } else {
            Write-Fail "설치를 중단합니다."
            exit 1
        }
    }
}

# MSIX 패키지 폴더는 설치마다 조금씩 다를 수 있어 동적으로 찾습니다 (Store/Preview 겸용)
$wtPackageDir = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.WindowsTerminal*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
$settingsPath = if ($wtPackageDir) {
    Join-Path $wtPackageDir.FullName "LocalState\settings.json"
} else {
    # 언패키지(portable) 빌드 폴백 경로
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
}

if (-not (Test-Path $settingsPath)) {
    Write-Warn "settings.json을 찾을 수 없습니다: $settingsPath"
    Write-Warn "Windows Terminal을 한 번 실행해 기본 설정 파일을 생성한 뒤 이 스크립트를 다시 실행해주세요."
} else {
    Write-Host "  대상 파일: $settingsPath" -ForegroundColor DarkGray

    # 원본 백업 (덮어쓰기 실패/사용자 커스텀 설정 유실 방지)
    Copy-Item -Path $settingsPath -Destination "$settingsPath.bak" -Force -ErrorAction SilentlyContinue

    try {
        $raw = Get-Content -Path $settingsPath -Raw -Encoding UTF8
        $settings = $raw | ConvertFrom-Json

        # ── Kanagawa 색 배열 추가 (이미 있으면 건너뜀) ──────────────────────────
        $kanagawaScheme = [PSCustomObject]@{
            name                = "Kanagawa"
            background          = "#0D0C0C"
            selectionBackground = "#282727"
            black               = "#0D0C0C"
            brightBlack         = "#625e5a"
            red                 = "#C34043"
            brightRed           = "#c4746e"
            green               = "#76946A"
            brightGreen         = "#87a987"
            yellow              = "#DCA561"
            brightYellow        = "#c4b28a"
            blue                = "#2D4F67"
            brightBlue          = "#658594"
            purple              = "#766b90"
            brightPurple        = "#938AA9"
            cyan                = "#597b75"
            brightCyan          = "#8ea4a2"
            foreground          = "#a6a69c"
            cursorColor         = "#625e5a"
            white               = "#7a8382"
            brightWhite         = "#a6a69c"
        }
        if (-not $settings.schemes) {
            $settings | Add-Member -NotePropertyName schemes -NotePropertyValue @() -Force
        }
        $schemesList = @($settings.schemes | Where-Object { $_.name -ne "Kanagawa" })
        $schemesList += $kanagawaScheme
        $settings.schemes = $schemesList
        Write-Success "Kanagawa 색 배열 등록 완료 (schemes)"

        # ── WSL 동적 프로필 중복 정리 (멱등성 보장) ─────────────────────────────
        # Windows Terminal은 WSL 배포판을 재등록할 때마다 새 GUID로 동적 프로필을 자동
        # 생성하고, 예전 GUID는 스스로 지우지 않습니다(실측: 이 PC에 "devtools2"/"Ubuntu"
        # 중복 프로필이 80개 넘게 쌓여있었음). 같은 이름의 항목이 여러 개면, WT가 새
        # 프로필을 항상 목록 끝에 추가하는 특성을 이용해 "마지막 것 = 가장 최근에 생성된
        # 것"으로 보고 그것만 남기고 나머지를 지웁니다(정확히 어떤 GUID가 지금 살아있는
        # 배포판인지는 알 수 없지만, 유효한 게 최소 1개는 남도록 보수적으로 정리).
        $wslProfiles = @($settings.profiles.list | Where-Object { $_.source -eq "Microsoft.WSL" })
        $dupNameGroups = $wslProfiles | Group-Object -Property name | Where-Object { $_.Count -gt 1 }
        $staleWslGuids = @()
        if ($dupNameGroups) {
            foreach ($grp in $dupNameGroups) {
                $items = @($grp.Group)
                # PS5.1 호환을 위해 -SkipLast 대신 배열 슬라이싱으로 "마지막 하나만 제외한 나머지"를 구함
                $toRemove = $items[0..($items.Count - 2)]
                $staleWslGuids += @($toRemove | ForEach-Object { $_.guid })
            }
            $settings.profiles.list = @($settings.profiles.list | Where-Object { $staleWslGuids -notcontains $_.guid })
            Write-Success "WSL 동적 프로필 중복 $($staleWslGuids.Count)개 정리 (이름별 최신 1개만 유지)"

            # settings.json에서만 지우면 state.json의 generatedProfiles가 "이미 생성함"으로
            # 기억하고 있어서 Windows Terminal이 재생성을 건너뛰는 버그가 있음
            # (microsoft/terminal#11510) — 지운 GUID를 state.json에서도 같이 제거해야 함.
            # 단, 이 스크립트 자신이 Windows Terminal 안에서 실행 중이라 종료를 건너뛴
            # 경우($skipStateCleanup)는 살아있는 프로세스가 곧바로 덮어쓸 것이 확실하므로
            # 시도 자체를 생략합니다.
            $statePath = Join-Path (Split-Path $settingsPath -Parent) "state.json"
            if ($skipStateCleanup) {
                Write-Warn "state.json 정리를 건너뜁니다 (위 안내 참고)."
            } elseif (Test-Path $statePath) {
                try {
                    Copy-Item -Path $statePath -Destination "$statePath.bak" -Force -ErrorAction SilentlyContinue
                    $state = (Get-Content -Path $statePath -Raw -Encoding UTF8) | ConvertFrom-Json
                    if ($state.generatedProfiles) {
                        $state.generatedProfiles = @($state.generatedProfiles | Where-Object { $staleWslGuids -notcontains $_ })
                        $stateJson = $state | ConvertTo-Json -Depth 100
                        [System.IO.File]::WriteAllText($statePath, $stateJson, (New-Object System.Text.UTF8Encoding($false)))
                        Write-Success "state.json의 generatedProfiles 동기화 완료 (재생성 차단 버그 우회)"
                    }
                } catch {
                    Write-Warn "state.json 정리 실패: $($_.Exception.Message)"
                }
            }
        }

        # ── 프로필 공통 기본값: 폰트 / 투명도 / 색 배열 ─────────────────────────
        if (-not $settings.profiles) {
            $settings | Add-Member -NotePropertyName profiles -NotePropertyValue ([PSCustomObject]@{ defaults = [PSCustomObject]@{}; list = @() }) -Force
        }
        if (-not $settings.profiles.defaults) {
            $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        # size: 폰트 사이즈 (WT 공식 스키마 기본값 12)
        # cellHeight: CSS line-height와 유사하게 셀(줄) 높이를 조정합니다(WT 공식 스키마 확인, release-1.24 기준, 기본값 1.2)
        $settings.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([PSCustomObject]@{ face = $fontFace; size = 11.5; cellHeight = '1.5' }) -Force
        $settings.profiles.defaults | Add-Member -NotePropertyName opacity -NotePropertyValue 97 -Force
        $settings.profiles.defaults | Add-Member -NotePropertyName colorScheme -NotePropertyValue "Kanagawa" -Force
        Write-Success "기본 폰트($fontFace, 11.5pt) / 투명도(97) / Kanagawa 테마 적용 완료 (profiles.defaults)"

        # ── ALT+c / ALT+h fzf 스크립트 실행 단축키 (sendInput, 이미 있으면 교체) ─
        if (-not $settings.actions) {
            $settings | Add-Member -NotePropertyName actions -NotePropertyValue @() -Force
        }
        $actionsList = @($settings.actions | Where-Object { $_.keys -notin @("alt+c", "alt+h") })
        $actionsList += [PSCustomObject]@{
            command = [PSCustomObject]@{ action = "sendInput"; input = '$DEVTOOLS2/scripts/fzf/command-palette' + "`n" }
            keys    = "alt+c"
        }
        $actionsList += [PSCustomObject]@{
            command = [PSCustomObject]@{ action = "sendInput"; input = '$DEVTOOLS2/scripts/fzf/bw-server-manager' + "`n" }
            keys    = "alt+h"
        }
        $settings.actions = $actionsList
        Write-Success "ALT+c(command-palette) / ALT+h(bw-server-manager) 단축키 등록 완료"

        # UTF-8 NoBOM으로 저장 (프로젝트 전역 인코딩 원칙과 동일)
        $json = $settings | ConvertTo-Json -Depth 100
        [System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Success "settings.json 저장 완료 (백업: $settingsPath.bak)"
    } catch {
        Write-Fail "settings.json 갱신 실패: $($_.Exception.Message)"
        Write-Warn "백업 파일($settingsPath.bak)에서 복원할 수 있습니다."
    }
}

# ==============================================================================
# 완료
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host "🎉 Windows Terminal 설정 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  [적용된 설정]" -ForegroundColor Cyan
Write-Host "  · 폰트     : $fontFace, 11.5pt" -ForegroundColor White
Write-Host "  · 테마     : Kanagawa" -ForegroundColor White
Write-Host "  · 투명도   : 97%" -ForegroundColor White
Write-Host "  · ALT+c    : 명령어 팔레트 (command-palette)" -ForegroundColor White
Write-Host "  · ALT+h    : SSH/Bitwarden 매니저 (bw-server-manager)" -ForegroundColor White
Write-Host ""
Write-Host "  Windows Terminal을 재시작하면 설정이 적용됩니다." -ForegroundColor Yellow
Write-Host "  Ctrl+Alt+T로 WSL을 여는 단축키는 devtools2-hotkey.ahk(1.setup-autohotkey.ps1)가 담당합니다." -ForegroundColor DarkGray
Write-Host "===========================================================================" -ForegroundColor DarkCyan
Write-Host ""
