# ==============================================================================
# run-all-tests.ps1 — DevTools2 통합 자동화 테스트 러너
#
# [설계 원칙]
# 1. 100% 무의존성(Zero-Dependency): pwsh 미설치 순정 Windows 10/11에서도
#    기본 Windows PowerShell 5.1(powershell.exe) 하나만으로 단독 실행 가능합니다.
# 2. 크로스 플랫폼 검증: Windows(.ps1) 및 Linux/WSL(.sh) 스크립트를 모두 검증합니다.
# 3. 과거 회귀 버그 전수 검증:
#    - 빈 에러 로그에 대한 .Trim() null 참조 예외
#    - Start-Process -PassThru 비동기 ExitCode $null 트랩
#    - WSL python3 인자 큰따옴표 증발 및 SyntaxError
#    - /etc/wsl.conf 자가 치유(Self-Healing) 분기 감지
#    - Linux safe_download_and_extract 아카이브 형식 판별(URL 확장자 대신 파일 헤더)
#    - PS 5.1 비호환 문법(?? 등)·5.1 파서 문법 오류, 셸 스크립트 bash -n
#    - 설치 흐름 결함(timeout 정지, 로컬 공용 파일 로드, WSLg 한글 입력 준비) — Suite 6
#    (run-all-tests.sh 와 같은 항목·기준을 유지합니다)
#
# [실행 방법]
#   PowerShell 5.1 또는 PowerShell 7 어디서든:
#   powershell -ExecutionPolicy Bypass -File .\tests\run-all-tests.ps1
#   (또는 .\tests\run-all-tests.bat)
# ==============================================================================

# --- UTF-8 NoBOM 출력 인코딩 보장
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# PSScriptRoot 무(無)파일/인메모리 런타임 호환 처리 (Rule 5)
# ⚠️ PS 7 에서 UNC 경로(\\wsl.localhost\...)에 Resolve-Path 를 쓰면 ".." 를 정리하지 않아 "...\tests\.." 로 남습니다
#    (실측). 그러면 저장소 기준 상대 경로 계산이 어긋나므로 GetFullPath 로 ".." 를 정리합니다.
$repoRootPath = if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
    [System.IO.Path]::GetFullPath((Resolve-Path (Join-Path $PSScriptRoot "..")).ProviderPath)
} else {
    (Get-Location).ProviderPath
}

$testStats = @{
    total  = 0
    passed = 0
    failed = 0
}

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "===========================================================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "===========================================================================" -ForegroundColor DarkGray
}

# 저장소 기준 상대 경로 (실패 메시지 표시용)
#   WSL 저장소를 Windows 에서 열면 같은 위치가 \\wsl.localhost\<배포판>\... 와 \\wsl$\<배포판>\... 로 섞여 들어와
#   저장소 경로 길이만큼 잘라내면 앞부분이 잘린 경로(예: "vim\init.lua")가 표시됐습니다. 접두어를 맞춘 뒤 비교하고,
#   저장소 밖이면 전체 경로를 그대로 돌려줍니다.
function Get-RepoRelativePath {
    param([string]$FullPath)
    $norm = { param($p) ($p -replace '^\\\\wsl\$\\', '\\wsl.localhost\').TrimEnd('\', '/') }
    $root = & $norm $repoRootPath
    $full = & $norm $FullPath
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).TrimStart('\', '/')
    }
    return $FullPath
}

function Assert-Test {
    param(
        [string]$Description,
        [bool]$Condition,
        [string]$FailureMessage = ""
    )
    $testStats.total++
    if ($Condition) {
        $testStats.passed++
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    } else {
        $testStats.failed++
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        if ($FailureMessage) {
            Write-Host "         -> 오류 상세: $FailureMessage" -ForegroundColor Yellow
        }
    }
}

# ==============================================================================
# [Suite 1] 인코딩 및 BOM 검증 (Windows .ps1, Linux .sh, 설정 파일 전체)
# ==============================================================================
Write-TestHeader "[Suite 1] UTF-8 NoBOM 및 스크립트 헤더 무결성 검증"

# BOM 검사 대상: 모든 텍스트 파일 (AGENTS.md 1번 "저장소의 모든 텍스트 파일은 UTF-8 NoBOM").
#   예전에는 .ps1/.sh/.bash/.json/.toml/.conf 6종만 봐서 .lua·.md·.yml·.bat·.ahk 등이 빠져 있었습니다.
#   앞 8KB 에 NUL 바이트가 있으면 바이너리로 보고 건너뜁니다.
$bomViolations = @()
$paramViolations = @()

# 런타임/캐시/의존성 디렉터리(data, modules 등)를 탐색 단계에서 사전 제외하여 초고속 스캔 보장
$excludedDirs = "^(\.git|\.vscode|\.idea|target|build|node_modules|data|modules)$"
$targetDirs = Get-ChildItem -LiteralPath $repoRootPath -Directory | Where-Object { $_.Name -notmatch $excludedDirs }
$allCandidateFiles = @($targetDirs | Get-ChildItem -Recurse -File | Where-Object { $_.FullName -notmatch "(\.git|\.vscode|\.idea|target|build|node_modules|data|modules)" }) + @(Get-ChildItem -LiteralPath $repoRootPath -File)

foreach ($candidate in $allCandidateFiles) {
    $candidate | ForEach-Object {
        # 1) BOM 검사 (0xEF, 0xBB, 0xBF - PS 5.1 / 7 공용 .NET API 사용, 바이너리 파일은 건너뜀)
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $headLen = [Math]::Min($bytes.Length, 8192)
        $isBinary = ($headLen -gt 0) -and ([Array]::IndexOf($bytes, [byte]0, 0, $headLen) -ge 0)
        if (-not $isBinary -and $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $bomViolations += (Get-RepoRelativePath $_.FullName)
        }

        # 2) .ps1의 스크립트 레벨 param() 위치 검사 (실행문이 param()보다 앞에 오면 안 됨)
        if ($_.Extension -eq ".ps1") {
            $code = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($code, $_.FullName, [ref]$null, [ref]$null)
            if ($ast.ParamBlock) {
                $paramLine = $ast.ParamBlock.Extent.StartLineNumber
                if ($ast.EndBlock -and $ast.EndBlock.Statements) {
                    foreach ($stmt in $ast.EndBlock.Statements) {
                        if ($stmt.Extent.StartLineNumber -lt $paramLine) {
                            $paramViolations += "$($_.Name) (Line $paramLine)"
                            break
                        }
                    }
                }
            }
        }
    }
}

Assert-Test "모든 스크립트 및 설정 파일이 순수 UTF-8 NoBOM 형식인가" ($bomViolations.Count -eq 0) `
    ("BOM 발견 파일: " + ($bomViolations -join ", "))

Assert-Test "모든 .ps1 스크립트의 param() 블록 앞에 실행문이 없는가" ($paramViolations.Count -eq 0) `
    ("잘못된 param() 위치: " + ($paramViolations -join ", "))

# ==============================================================================
# [Suite 2] PowerShell 구문 정적 파싱 검증 (PS 5.1 / 7 파서)
# ==============================================================================
Write-TestHeader "[Suite 2] PowerShell 구문 정적 분석 (PS 5.1 / 7 파서)"

$psFiles = $allCandidateFiles | Where-Object { $_.Extension -eq ".ps1" }

# --- 2-1. 실제 PowerShell 파서로 문법 오류 검사
#     run-all-tests.bat 는 pwsh(7)가 있으면 그걸 먼저 쓰는데, PS 7 파서는 ?? · 삼항 · && 같은 7 전용 문법을 오류로 보지 않습니다.
#     설치 대상은 Windows PowerShell 5.1 이므로, 7 에서 실행 중이고 powershell.exe(5.1)가 있으면 5.1 파서로 따로 검사합니다
#     (run-all-tests.sh 도 WSL 에서는 powershell.exe 를 우선 사용). 5.1 파서 실행 자체가 실패하면 실패로 처리합니다.
$syntaxErrors = @()
$ps51 = Get-Command powershell.exe -ErrorAction SilentlyContinue
if (@($psFiles).Count -eq 0) {
    # 검사할 파일이 0개면 "오류 없음"으로 통과해 버리므로 실패로 처리 (sh 러너에서 REPO_ROOT 가 심볼릭 링크라 0개였던 사례)
    $syntaxErrors += "검사할 .ps1 파일을 찾지 못함 ($repoRootPath)"
} elseif ($PSVersionTable.PSVersion.Major -ge 6 -and $ps51) {
    $quoted = ($psFiles | ForEach-Object { "'" + ($_.FullName -replace "'", "''") + "'" }) -join ","
    $parseScript = "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(`$false); `$errors = @(); " +
        "foreach (`$f in @($quoted)) { `$code = [System.IO.File]::ReadAllText(`$f, [System.Text.Encoding]::UTF8); `$errs = `$null; " +
        "[System.Management.Automation.Language.Parser]::ParseInput(`$code, `$f, [ref]`$null, [ref]`$errs) | Out-Null; " +
        "if (`$errs -and `$errs.Count -gt 0) { `$errors += ([System.IO.Path]::GetFileName(`$f) + ': ' + `$errs[0].Message) } }; " +
        "'DT2_PARSED=' + (`$errors -join ';')"
    $parseOut = @(& $ps51.Source -NoProfile -Command $parseScript 2>$null) | ForEach-Object { [string]$_ }
    $parsedLine = $parseOut | Where-Object { $_ -like 'DT2_PARSED=*' } | Select-Object -Last 1
    if ($null -eq $parsedLine) {
        $syntaxErrors += "powershell.exe 파서 실행 실패"
    } elseif ($parsedLine.Length -gt 'DT2_PARSED='.Length) {
        $syntaxErrors += $parsedLine.Substring('DT2_PARSED='.Length) -split ';'
    }
} else {
    foreach ($file in $psFiles) {
        $code = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($code, $file.FullName, [ref]$null, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            $syntaxErrors += "$($file.Name): $($errors[0].Message)"
        }
    }
}

Assert-Test "모든 .ps1 파일에 문법 오류가 없는가 (PowerShell 파서)" ($syntaxErrors.Count -eq 0) `
    ($syntaxErrors -join "`n         -> ")

# --- 2-3. .ps1 이 부르는 함수·cmdlet 이 모두 정의되어 있는가 (정의 없는 함수 호출)
#     0.setup-wsl.ps1 이 Write-Question 을 부르기만 하고 정의가 없어, 그 줄이 실행되는 경우(.wslconfig 미러링 없음 ·
#     WSL 메모리 상한 질문)에만 멈췄음 — 문법 검사(2-1)는 통과. 검사 본문은 tests\lib\Find-UndefinedPsCommands.ps1 (sh 러너와 공용)
#     ● 내장 cmdlet 목록은 PowerShell 마다 달라, 7 에서 실행 중이고 powershell.exe(5.1)가 있으면 5.1 로 따로 검사(2-1 과 같은 방식)
$undefChecker = Join-Path $repoRootPath "tests\lib\Find-UndefinedPsCommands.ps1"
$undefOut = @()
if ($PSVersionTable.PSVersion.Major -ge 6 -and $ps51) {
    $quotedFiles = ($psFiles | ForEach-Object { "'" + ($_.FullName -replace "'", "''") + "'" }) -join ","
    $undefScript = "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(`$false); " +
        "& ([scriptblock]::Create([System.IO.File]::ReadAllText('" + ($undefChecker -replace "'", "''") + "', [System.Text.Encoding]::UTF8))) -Files @($quotedFiles)"
    $undefOut = @(& $ps51.Source -NoProfile -Command $undefScript 2>$null) | ForEach-Object { [string]$_ }
} else {
    $undefOut = @(& ([scriptblock]::Create([System.IO.File]::ReadAllText($undefChecker, [System.Text.Encoding]::UTF8))) -Files @($psFiles | ForEach-Object { $_.FullName })) | ForEach-Object { [string]$_ }
}
$undefCallsLine = $undefOut | Where-Object { $_ -like 'DT2_CALLS=*' } | Select-Object -Last 1
$undefLine = $undefOut | Where-Object { $_ -like 'DT2_UNDEF=*' } | Select-Object -Last 1
$undefCalls = 0
if ($undefCallsLine) { $undefCalls = [int]$undefCallsLine.Substring('DT2_CALLS='.Length) }
$undefBad = ""
if ($null -eq $undefLine -or $undefCalls -eq 0) {
    $undefBad = "검사 실행 실패 (호출 ${undefCalls}개)"
} elseif ($undefLine.Length -gt 'DT2_UNDEF='.Length) {
    $undefBad = "정의 없음: " + $undefLine.Substring('DT2_UNDEF='.Length)
}
Assert-Test ".ps1 이 부르는 함수·cmdlet 이 모두 정의되어 있는가" ([string]::IsNullOrEmpty($undefBad)) $undefBad

# --- 2-2. PS 5.1 호환 정적 검사 (run-all-tests.sh 의 Python 정밀 검사와 같은 항목·기준)
#     예전에는 이 러너에 없었고 sh 러너도 pwsh 가 없을 때만 실행해서, pwsh 가 있는 PC 에서는 ?? 연산자를 아무도 잡지 못했습니다
#     (AGENTS.md 3번 "널 병합 연산자(??) 사용 금지"). 테스트 러너 자신은 검사 패턴을 문자열로 품고 있어 제외합니다.
#     1) ?? 연산자  2) 빈 해시 리터럴 대입(@{ Key = })  3) 접두사 변수 누락 URL(-Url "/...")
#     4) 좌변 변수 탈락 빈 대입문(= ...)  5) Test-Path 괄호 누락으로 -and/-or 가 매개변수로 오인
$compatErrors = @()
foreach ($file in ($psFiles | Where-Object { $_.Name -ne "run-all-tests.ps1" })) {
    $rel = Get-RepoRelativePath $file.FullName
    $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $lines = $content -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $codePart = ($lines[$i] -split '#', 2)[0]
        if ($codePart.Contains('?' + '?')) { $compatErrors += "${rel}:$($i + 1): PS 5.1 비호환 ?? 연산자" }
        $stripped = $lines[$i].Trim()
        if ($stripped.StartsWith('= ') -or $stripped -eq '=') { $compatErrors += "${rel}:$($i + 1): 좌변 변수 누락 대입문" }
    }
    $noComments = $content -replace '#.*', ''
    foreach ($m in [regex]::Matches($noComments, '@\{[^}]*?\b([a-zA-Z0-9_]+)\s*=\s*(?:\}|;|\n\s*\})')) {
        $compatErrors += "${rel}: 빈 해시테이블 대입문 (@{ ... $($m.Groups[1].Value) = ... })"
    }
    foreach ($m in [regex]::Matches($noComments, '-Url\s+["'']/[a-zA-Z0-9_]')) {
        $compatErrors += "${rel}: 접두사 변수 누락 URL (-Url `"/...`")"
    }
    foreach ($m in [regex]::Matches($noComments, '(?<!\()\bTest-Path\s+[^()\n]+?\s+(-and|-or)\b')) {
        $compatErrors += "${rel}: Test-Path 괄호 누락 매개변수 오인 ($($m.Value.Trim()))"
    }
}
Assert-Test "PS 5.1 호환 정적 검사 (?? 연산자·빈 해시 대입·URL 접두 변수 누락·Test-Path 괄호)" ($compatErrors.Count -eq 0) `
    ($compatErrors -join "`n         -> ")

# ==============================================================================
# [Suite 3] Linux Bash 스크립트 문법 검증 (bash -n)
# ==============================================================================
Write-TestHeader "[Suite 3] Linux Bash 스크립트 구문 검사 (bash -n)"

$bashExe = $null
$possibleBashes = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files\Git\usr\bin\bash.exe",
    (Get-Command bash.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
)
foreach ($b in $possibleBashes) {
    if ($b -and (Test-Path $b)) { $bashExe = $b; break }
}

if ($bashExe) {
    # 대상: scripts\ 아래 모든 셸 스크립트 — .sh/.bash 와, 확장자가 없어도 첫 줄이 bash/sh shebang 인 파일
    #   예전에는 scripts\linux 의 .sh 만 봐서 bw-lib·command-palette·bw-server-manager·git 훅(pre-commit)·
    #   format·jdtls 래퍼가 빠져 있었습니다(이 중 bw-lib 은 설치 스크립트가 직접 불러옴).
    $shFiles = Get-ChildItem -Path (Join-Path $repoRootPath "scripts") -Recurse -File | Where-Object {
        if ($_.Extension -in @(".sh", ".bash")) { return $true }
        if ($_.Extension -ne "") { return $false }
        $firstLine = [string](Get-Content -LiteralPath $_.FullName -TotalCount 1 -ErrorAction SilentlyContinue)
        return ($firstLine -match '^#!.*\b(bash|sh)\b')
    }

    # WSL 의 bash.exe(System32)는 Windows 경로를 이해하지 못하므로 리눅스 경로로 바꿔 넘깁니다.
    #   \\wsl.localhost\<배포판>\var\opt\... → /var/opt/...   C:\Users\... → /mnt/c/Users/...
    # Git Bash 는 슬래시 경로(C:/... 또는 //wsl.localhost/...)를 그대로 이해합니다.
    $isWslBash = ($bashExe -like "*\System32\*")
    $bashErrors = @()
    foreach ($sh in $shFiles) {
        $shPath = $sh.FullName
        if ($isWslBash -and $shPath -match '^\\\\wsl(?:\.localhost|\$)\\[^\\]+\\(.*)$') {
            $shPath = '/' + ($matches[1] -replace '\\', '/')
        } elseif ($isWslBash -and $shPath -match '^([A-Za-z]):\\(.*)$') {
            $shPath = '/mnt/' + $matches[1].ToLower() + '/' + ($matches[2] -replace '\\', '/')
        } else {
            $shPath = $shPath -replace '\\', '/'
        }
        $p = Start-Process $bashExe -ArgumentList "-n `"$shPath`"" -Wait -PassThru -NoNewWindow -RedirectStandardError "$env:TEMP\bash_test_err.txt"
        if ($p.ExitCode -ne 0) {
            $errTxt = [string](Get-Content "$env:TEMP\bash_test_err.txt" -Raw -ErrorAction SilentlyContinue)
            $bashErrors += "$($sh.Name): $($errTxt.Trim())"
        }
        Remove-Item "$env:TEMP\bash_test_err.txt" -Force -ErrorAction SilentlyContinue
    }
    Assert-Test "scripts/ 의 모든 셸 스크립트가 bash -n 검사를 통과하는가" ($bashErrors.Count -eq 0) `
        ($bashErrors -join "`n         -> ")
} else {
    Assert-Test "Bash 환경 감지 (Git Bash / WSL 미설치로 건너뜀)" $true
}

# ==============================================================================
# [Suite 4] 런타임 회귀 버그 전수 검증 (과거 오류 100% 방지)
# ==============================================================================
Write-TestHeader "[Suite 4] 런타임 회귀 버그 전수 검증"

# --- 4-1. Windows 스크립트에 위험한 '(Get-Content ...).Trim()' 직통 호출이 남아있지 않은지 소스 전수 검사
#     빈 파일의 Get-Content -Raw 는 $null 을 돌려주므로 .Trim() 이 바로 크래시합니다(AGENTS.md 3번 .Trim() 널 가드).
#     예전에는 0.setup-wsl.ps1 한 파일만 봤지만 규칙은 모든 .ps1 에 적용되므로 scripts\windows 전체를 봅니다.
#     (예전의 "빈 파일 Get-Content -Raw 가 $null 을 돌려주는가" 검사는 PowerShell 자체 동작 확인이라 저장소와 무관하게
#      항상 통과해 삭제했습니다 — 그 특성은 이 검사와 AGENTS.md 의 근거로 남아 있습니다)
$wslSetupFile = Join-Path $repoRootPath "scripts\windows\dev-env\0.setup-wsl.ps1"
$wslSetupCode = [System.IO.File]::ReadAllText($wslSetupFile, [System.Text.Encoding]::UTF8)
$unsafeTrim = @()
$winScriptFilesForTrim = $psFiles | Where-Object { $_.FullName -like "*\scripts\windows\*" -or $_.FullName -like "*/scripts/windows/*" }
foreach ($file in $winScriptFilesForTrim) {
    $tLines = [System.IO.File]::ReadAllLines($file.FullName, [System.Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $tLines.Count; $i++) {
        if ($tLines[$i] -match '\(Get-Content[^\)]+\)\.Trim\(\)') { $unsafeTrim += "$($file.Name):$($i + 1)" }
    }
}
Assert-Test "Windows 스크립트에 위험한 '(Get-Content).Trim()' 직통 호출이 0건인가" ($unsafeTrim.Count -eq 0) `
    ("위반: " + ($unsafeTrim -join ", "))

# --- 4-2. WSL /etc/wsl.conf 파이썬 코드 인용부호 및 configparser 정상 동작 검증 (Rule 9)
$pyMatch = [regex]::Match($wslSetupCode, '(?s)\$mergeWslConfPy\s*=\s*@''\r?\n(.*?)\r?\n''@')
$pyCodeExtracted = if ($pyMatch.Success) { $pyMatch.Groups[1].Value } else { "" }

$pySyntaxOk = $false
$pyErrMsg = ""
if ($pyCodeExtracted) {
    $testPyFile = Join-Path $env:TEMP "test_wsl_conf_merge.py"
    [System.IO.File]::WriteAllText($testPyFile, $pyCodeExtracted, [System.Text.UTF8Encoding]::new($false))

    $pyRunner = $null
    if (Get-Command python.exe -ErrorAction SilentlyContinue) {
        $testRun = Start-Process python.exe -ArgumentList "--version" -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
        if ($testRun.ExitCode -eq 0) { $pyRunner = "python.exe" }
    }
    if (-not $pyRunner -and (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        $testRun = Start-Process wsl.exe -ArgumentList "-- python3 --version" -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
        if ($testRun.ExitCode -eq 0) { $pyRunner = "wsl-python" }
    }

    if ($pyRunner -eq "python.exe") {
        $checkProc = Start-Process python.exe -ArgumentList "-m py_compile `"$testPyFile`"" -Wait -PassThru -NoNewWindow -RedirectStandardError "$env:TEMP\py_err.txt"
        $pySyntaxOk = ($checkProc.ExitCode -eq 0)
        if (-not $pySyntaxOk) { $pyErrMsg = [string](Get-Content "$env:TEMP\py_err.txt" -Raw) }
    } elseif ($pyRunner -eq "wsl-python") {
        $wslPath = $testPyFile -replace "\\", "/" -replace "C:", "/mnt/c"
        $checkProc = Start-Process wsl.exe -ArgumentList "-- python3 -m py_compile `"$wslPath`"" -Wait -PassThru -NoNewWindow -RedirectStandardError "$env:TEMP\py_err.txt"
        $pySyntaxOk = ($checkProc.ExitCode -eq 0)
        if (-not $pySyntaxOk) { $pyErrMsg = [string](Get-Content "$env:TEMP\py_err.txt" -Raw) }
    } else {
        $pySyntaxOk = ($pyCodeExtracted -match "import configparser" -and $pyCodeExtracted -match "c\.set\('user', 'default', username\)")
    }
    Remove-Item $testPyFile -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\py_err.txt" -Force -ErrorAction SilentlyContinue
}

Assert-Test "0.setup-wsl.ps1 내 /etc/wsl.conf 파이썬 주입 코드가 문법 에러 없이 컴파일되는가" $pySyntaxOk $pyErrMsg

# 명령행 인자(-c) 전달 방식이 아닌 STDIN 파이프라인($mergeWslConfPy | wsl) 방식으로 전달되는지 검증
$usesStdinPipe = ($wslSetupCode -match '\$mergeWslConfPy\s*\|\s*wsl')
$avoidsInlineDashC = ($wslSetupCode -notmatch 'python3\s+-c\s+"\$mergeWslConfPy"')
Assert-Test "0.setup-wsl.ps1 이 따옴표 탈락 방지를 위해 STDIN 파이프라인으로 파이썬을 호출하는가" ($usesStdinPipe -and $avoidsInlineDashC)

# --- 4-3. 배포판 자가 치유 (Self-Healing) 분기 로직 검증
$hasSelfHealingCode = ($wslSetupCode -match '\[user\]' -and $wslSetupCode -match 'default\s*=' -and $wslSetupCode -match 'wsl\.exe\s+--unregister')
Assert-Test "0.setup-wsl.ps1 에 미완성 배포판 자동 감지 및 unregister 자가 치유 로직이 존재하는가" $hasSelfHealingCode

# --- 4-4. Linux safe_download_and_extract 아카이브 포맷 자동 판별 검증
$installUtilsFile = Join-Path $repoRootPath "scripts\linux\dev-env\_install-utils.sh"
$installUtilsCode = [System.IO.File]::ReadAllText($installUtilsFile, [System.Text.Encoding]::UTF8)
$hasUnzipTest = ($installUtilsCode -match 'unzip\s+-tq\s+"\$tmp_archive"')
$hasTarGzTest = ($installUtilsCode -match 'tar\s+-tzf\s+"\$tmp_archive"')
Assert-Test "Linux safe_download_and_extract 가 URL 확장자 대신 파일 헤더 무결성(unzip -tq)으로 아카이브를 판별하는가" ($hasUnzipTest -and $hasTarGzTest)

# ==============================================================================
# [Suite 5] 2026-10 점검에서 찾은 결함 회귀 방지
# ==============================================================================
Write-TestHeader "[Suite 5] 2026-10 점검 결함 회귀 방지"

# --- 5-1. CI 의 Windows PowerShell 5.1 단계(shell: powershell) 본문은 ASCII 전용이어야 함
#     (러너가 BOM 없는 임시 .ps1 로 저장 → PS 5.1 이 cp1252 로 읽어 한글 바이트가 스마트 따옴표로 깨짐)
$ciFile = Join-Path $repoRootPath ".github\workflows\ci.yml"
$ciNonAscii = @()
if (Test-Path $ciFile) {
    $ciLines = [System.IO.File]::ReadAllLines($ciFile, [System.Text.Encoding]::UTF8)
    $inPs51 = $false; $inRun = $false
    for ($i = 0; $i -lt $ciLines.Count; $i++) {
        $l = $ciLines[$i]
        if ($l -match '^\s*-\s+name:') { $inPs51 = $false; $inRun = $false }
        if ($l -match '^\s*shell:\s*powershell\s*$') { $inPs51 = $true }
        if ($inPs51 -and $l -match '^\s*run:\s*\|') { $inRun = $true; continue }
        if ($inPs51 -and $inRun -and $l -match '[^\x00-\x7F]') { $ciNonAscii += "ci.yml:$($i + 1)" }
    }
}
Assert-Test "CI 의 'shell: powershell'(PS 5.1) 단계 본문이 ASCII 전용인가" ($ciNonAscii.Count -eq 0) `
    ("비ASCII 줄: " + ($ciNonAscii -join ", "))

# --- 5-2. Prompt-Confirm 의 기본값은 문자열 "Y"/"N" — $true/$false 를 넘기면 "True" 가 되어 기본값이 N 으로 바뀜
$boolConfirm = @()
foreach ($file in $psFiles) {
    $code = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    if ($code -match 'Prompt-Confirm\s+"[^"]*"\s+\$(true|false)') { $boolConfirm += $file.Name }
}
Assert-Test "Prompt-Confirm 기본값에 `$true/`$false 대신 ""Y""/""N"" 문자열을 쓰는가" ($boolConfirm.Count -eq 0) `
    ("위반 파일: " + ($boolConfirm -join ", "))

# --- 5-3. 설치용 임시 sudo 회수: Windows 는 try/finally, 리눅스는 sudo -n 으로 존재 확인
#     (/etc/sudoers.d 는 0750 root 라 일반 사용자의 [ -f ] 검사는 항상 거짓 → 회수가 실행되지 않던 결함)
$winMaster = [System.IO.File]::ReadAllText((Join-Path $repoRootPath "scripts\windows\setup-devtools2-wsl.ps1"), [System.Text.Encoding]::UTF8)
$linuxMaster = [System.IO.File]::ReadAllText((Join-Path $repoRootPath "scripts\linux\setup-devtools2.sh"), [System.Text.Encoding]::UTF8)
$winFinally = ($winMaster -match '(?s)finally\s*\{[^}]*Revoke-WslTempSudo')
$linuxNoPlainTest = ($linuxMaster -notmatch '\[\s+-[fe]\s+"/etc/sudoers\.d/')
$linuxSudoTest = ($linuxMaster -match 'sudo -n test -e')
Assert-Test "임시 sudo 회수가 Windows(try/finally)·리눅스(sudo -n test) 모두 실제로 동작하는 형태인가" ($winFinally -and $linuxNoPlainTest -and $linuxSudoTest)

# --- 5-4. 포트 해제는 LISTEN 소켓만 대상 (lsof -ti :PORT 는 그 포트로 접속한 클라이언트까지 포함)
#     (팔레트는 command-palette + palette.d\*.sh 로 나뉘어 있어 함께 봄 — 포트 함수는 palette.d\_lib.sh)
$paletteMain = Join-Path $repoRootPath "scripts\fzf\command-palette"
$paletteDir = Join-Path $repoRootPath "scripts\fzf\palette.d"
$paletteCode = [System.IO.File]::ReadAllText($paletteMain, [System.Text.Encoding]::UTF8)
foreach ($pf in @(Get-ChildItem -LiteralPath $paletteDir -Filter "*.sh" -File | Sort-Object Name)) {
    $paletteCode += "`n" + [System.IO.File]::ReadAllText($pf.FullName, [System.Text.Encoding]::UTF8)
}
$noClientKill = ($paletteCode -notmatch '(?m)^[^#\r\n]*lsof\s+-ti\s+:') -and ($paletteCode -match '-sTCP:LISTEN')
Assert-Test "command-palette 포트 해제가 LISTEN 프로세스만 대상으로 하는가" $noClientKill

# --- 5-5. launch.json 병합은 추가할 설정이 없으면 파일을 다시 쓰지 않아야 함 (사용자 주석 보존)
$commonSetupCode = [System.IO.File]::ReadAllText((Join-Path $repoRootPath "scripts\linux\setup-projects\_common\common-setup.sh"), [System.Text.Encoding]::UTF8)
$skipsNoopWrite = ($commonSetupCode -match '(?s)if added_count == 0:\s*\n\s*print\([^\n]*\)\s*\n\s*sys\.exit\(0\)')
Assert-Test "setup_vscode_launch_json 이 변경 없을 때 launch.json 을 다시 쓰지 않는가" $skipsNoopWrite

# --- 5-6. 비밀 정보 유출 방지: "!*"(전부 추적) 폴더마다 차단 목록 + 커밋 차단 훅 + 훅 자동 활성화
#     (루트 .gitignore 의 규칙은 하위 폴더의 "!*" 보다 우선순위가 낮아 각 폴더에 따로 있어야 함)
$trackAllIgnores = Get-ChildItem -Path $repoRootPath -Filter ".gitignore" -Recurse -Force -File |
    Where-Object { $_.FullName -notmatch '[\\/](data|modules|\.git)[\\/]' } |
    Where-Object { [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8) -match '(?m)^!\*\s*$' }
$missingDeny = @()
foreach ($gi in $trackAllIgnores) {
    $giCode = [System.IO.File]::ReadAllText($gi.FullName, [System.Text.Encoding]::UTF8)
    if (($giCode -notmatch '(?m)^\.env\s*$') -or ($giCode -notmatch '(?m)^auth\.json\s*$') -or ($giCode -notmatch '(?m)^\.claude/\s*$')) {
        $missingDeny += (Get-RepoRelativePath $gi.FullName)
    }
}
Assert-Test "전부 추적('!*')하는 폴더의 .gitignore 마다 비밀 정보 차단 목록이 있는가" ($missingDeny.Count -eq 0) `
    ("차단 목록 없는 파일: " + ($missingDeny -join ", "))

$hookFile = Join-Path $repoRootPath "scripts\git-hooks\pre-commit"
$hookOk = $false
if (Test-Path $hookFile) {
    $hookCode = [System.IO.File]::ReadAllText($hookFile, [System.Text.Encoding]::UTF8)
    $hookOk = ($hookCode -match 'sk-ant-') -and ($hookCode -match 'AIza') -and ($hookCode -match 'PRIVATE KEY') -and ($hookCode -match 'exit 1')
}
$setupEnvCode = [System.IO.File]::ReadAllText((Join-Path $repoRootPath "scripts\linux\dev-env\1.setup-env.sh"), [System.Text.Encoding]::UTF8)
$hookWired = ($setupEnvCode -match 'core\.hooksPath scripts/git-hooks') -and ($setupEnvCode -match 'secrets\.env') -and ($setupEnvCode -match 'chmod 600 "\$_SECRETS_ENV"')
Assert-Test "비밀 정보 커밋 차단 훅이 있고 1.setup-env.sh 가 훅·secrets.env(600)를 설정하는가" ($hookOk -and $hookWired)

# --- 5-7. "wsl -- bash -c" 는 리눅스 기본 셸을 한 번 더 거쳐 리눅스 변수($f, $c)가 미리 빈 값으로 확장됨
#     → 리눅스 변수를 쓰는 명령은 wsl -e(--exec)로 넘겨야 함 (Orca 에이전트 감지가 항상 비던 결함)
$wslDollarViolations = @()
foreach ($file in $psFiles) {
    $lines = [System.IO.File]::ReadAllLines($file.FullName, [System.Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match '^\s*#') { continue }
        # 큰따옴표 안의 `$ 든 작은따옴표 안의 $ 든 (PS 가 인자를 큰따옴표로 감싸 넘기므로) 둘 다 미리 확장됨
        if ($l -match 'wsl(\.exe)?\s[^#]*\s--\s+(bash|sh)\s+-l?c\s+("[^"]*`\$|''[^'']*\$)') { $wslDollarViolations += "$($file.Name):$($i + 1)" }
    }
}
Assert-Test "리눅스 변수를 쓰는 wsl 명령이 'wsl -- bash -c' 대신 'wsl -e' 를 쓰는가" ($wslDollarViolations.Count -eq 0) `
    ("위반: " + ($wslDollarViolations -join ", "))

# --- 5-8. RETURN 트랩은 전역이라 스스로 해제하지 않으면 바깥 함수가 끝날 때 다시 실행되어 set -u 로 죽음
$installUtils = [System.IO.File]::ReadAllText((Join-Path $repoRootPath "scripts\linux\dev-env\_install-utils.sh"), [System.Text.Encoding]::UTF8)
$badReturnTrap = ([regex]::Matches($installUtils, "trap '[^']*' RETURN") | Where-Object { $_.Value -notmatch 'trap - RETURN' }).Count
Assert-Test "_install-utils.sh 의 RETURN 트랩이 실행 후 스스로 해제되는가" ($badReturnTrap -eq 0)

# --- 5-9. 설치 로그를 /tmp/_고정이름 에 쓰면 다중 사용자 서버에서 남이 먼저 만든 파일에 쓰지 못해
#     (fs.protected_regular=2) 리다이렉트가 실패하고 apt 설치 같은 명령이 아예 실행되지 않음 → $DT2_TMP 사용
$fixedTmp = @()
foreach ($sh in (Get-ChildItem -Path (Join-Path $repoRootPath "scripts\linux") -Recurse -File -Filter "*.sh")) {
    $shLines = [System.IO.File]::ReadAllLines($sh.FullName, [System.Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $shLines.Count; $i++) {
        if ($shLines[$i] -match '^\s*#') { continue }
        if ($shLines[$i] -match '[>"\s]/tmp/_[A-Za-z]') { $fixedTmp += "$($sh.Name):$($i + 1)" }
    }
}
Assert-Test "리눅스 설치 스크립트가 /tmp 고정 이름 대신 사용자 전용 `$DT2_TMP 를 쓰는가" ($fixedTmp.Count -eq 0) `
    ("위반: " + ($fixedTmp -join ", "))

# --- 5-10. 그룹 공유 nvim 자원: 플러그인·Lua 패키지·Mason·Treesitter 만 공유 폴더, 나머지는 사용자별
#     (~/.local/share/nvim 전체를 공유하면 snacks 기록 등이 섞이고 다른 사용자는 쓰기 오류)
$nvimRoot = Join-Path $repoRootPath ".config\nvim"
$lazyCode = [System.IO.File]::ReadAllText((Join-Path $nvimRoot "lua\config\lazy.lua"), [System.Text.Encoding]::UTF8)
$masonCode = [System.IO.File]::ReadAllText((Join-Path $nvimRoot "lua\plugins\mason.lua"), [System.Text.Encoding]::UTF8)
$tsCode = [System.IO.File]::ReadAllText((Join-Path $nvimRoot "lua\plugins\treesitter.lua"), [System.Text.Encoding]::UTF8)
$setupEnv2 = [System.IO.File]::ReadAllText((Join-Path $repoRootPath "scripts\linux\dev-env\1.setup-env.sh"), [System.Text.Encoding]::UTF8)
$sharedOk = ($lazyCode -match 'root = lazy_root') -and ($lazyCode -match "rocks = \{ root = _G\.NVIM_SHARED_DIR") -and ($lazyCode -match "safe\.directory") `
    -and ($masonCode -match "install_root_dir = _G\.NVIM_SHARED_DIR") -and ($tsCode -match "install_dir = _G\.NVIM_SHARED_DIR") `
    -and ($setupEnv2 -notmatch '_run_symlink "\$DEVTOOLS2/data/nvim"') -and ($setupEnv2 -match 'prune -o -user') -and ($setupEnv2 -match 'setfacl -d -m')
Assert-Test "nvim 공유 자원(플러그인·Mason·파서)만 그룹 공유하고 개인 데이터는 사용자별로 분리하는가" $sharedOk

# --- 5-11. Windows Defender ML 오탐(Trojan:Win32/Commando.A!ml) 유발 방지
#     powershell.exe 에 -EncodedCommand/-enc 로 UAC 승격 스폰을 하면 백신 휴리스틱/머신러닝에 의해 트로이목마로 차단됨
$encodedCommandViolations = @()
foreach ($file in $psFiles) {
    if ($file.Name -eq "run-all-tests.ps1") { continue }
    $lines = [System.IO.File]::ReadAllLines($file.FullName, [System.Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match '^\s*#') { continue }
        if ($l -match '-(EncodedCommand|enc)\b') { $encodedCommandViolations += "$($file.Name):$($i + 1)" }
    }
}
Assert-Test "백신 오탐(Trojan:Win32/Commando.A!ml)을 유발하는 -EncodedCommand/-enc 가 0건인가" ($encodedCommandViolations.Count -eq 0) `
    ("위반: " + ($encodedCommandViolations -join ", "))

# ==============================================================================
# [Suite 6] 2026-11 설치 흐름 점검 결함 회귀 방지 (run-all-tests.sh 의 Suite 6 과 같은 항목·기준)
# ==============================================================================
Write-TestHeader "[Suite 6] 2026-11 설치 흐름 점검 결함 회귀 방지"

# --- 6-1. Start-Process -PassThru(-Wait 없음) 프로세스의 ExitCode 를 읽으면 .Handle 을 미리 여는가
#     Handle 을 미리 열지 않으면 PS 5.1 에서 정상 종료해도 ExitCode 가 $null(실측) → 0.setup-wsl.ps1 이
#     설치된 WSL 을 매번 "미설치"로 판정했음. 대입 문장(백틱 줄 이어짐 포함) 뒤 8줄 안에 .Handle/.WaitForExit 필요
$exitCodeViolations = @()
$winScriptFiles = $psFiles | Where-Object { $_.FullName -like "*\scripts\windows\*" -or $_.FullName -like "*/scripts/windows/*" }
foreach ($file in $winScriptFiles) {
    $lines = [System.IO.File]::ReadAllLines($file.FullName, [System.Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^\s*\$(\w+)\s*=\s*Start-Process\b') { continue }
        $var = $Matches[1]
        $j = $i
        $stmt = $lines[$i]
        while ($stmt.TrimEnd().EndsWith('`') -and ($j + 1) -lt $lines.Count) {
            $j++
            $stmt += ' ' + $lines[$j]
        }
        if ($stmt -notmatch '-PassThru\b' -or $stmt -match '-Wait\b') { continue }
        $varEsc = [regex]::Escape($var)
        $rest = if (($j + 1) -lt $lines.Count) { ($lines[($j + 1)..($lines.Count - 1)] -join "`n") } else { "" }
        if ($rest -notmatch ('\$' + $varEsc + '\.ExitCode\b')) { continue }
        $winEnd = [Math]::Min($j + 8, $lines.Count - 1)
        $window = if (($j + 1) -le $winEnd) { ($lines[($j + 1)..$winEnd] -join "`n") } else { "" }
        if ($window -notmatch ('\$' + $varEsc + '\.(Handle|WaitForExit)\b')) { $exitCodeViolations += "$($file.Name):$($i + 1)(`$$var)" }
    }
}
Assert-Test "Start-Process -PassThru 프로세스의 ExitCode 를 읽을 때 .Handle 을 미리 여는가 (PS 5.1 `$null 트랩)" ($exitCodeViolations.Count -eq 0) `
    ("위반: " + ($exitCodeViolations -join ", "))

# --- 6-2. 리눅스 설치 스크립트의 timeout 이 setsid(터미널 분리)와 함께 쓰이는가
#     timeout 은 명령을 백그라운드 프로세스 그룹에서 실행 → 안에서 터미널을 잡는 명령(대화형 bash, sudo 질문)의
#     SIGTTIN 으로 timeout 까지 정지해 설치가 영원히 멈춤(실측: Orca 권장 스킬 설치). setsid -w timeout 사용,
#     setsid 없는 시스템용 대체 줄은 "# dt2:setsid-fallback" 표시로 예외
$timeoutViolations = @()
$devEnvDir = Join-Path $repoRootPath "scripts\linux\dev-env"
$timeoutTargets = @(Get-ChildItem -Path $devEnvDir -File -Filter "*.sh") + @(Get-Item (Join-Path $repoRootPath "scripts\linux\setup-devtools2.sh") -ErrorAction SilentlyContinue)
foreach ($sh in $timeoutTargets) {
    if ($null -eq $sh) { continue }
    $shLines = [System.IO.File]::ReadAllLines($sh.FullName, [System.Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $shLines.Count; $i++) {
        $l = $shLines[$i]
        if ($l -match '^\s*#') { continue }
        $code = ($l -split ' #', 2)[0]
        if ($code -notmatch '(^|[\s;&|(`$])timeout\s+(-[A-Za-z-]+(\s+\S+)?\s+)*[0-9]') { continue }
        if ($code -match 'setsid' -or $l -match 'dt2:setsid-fallback') { continue }
        $timeoutViolations += "$($sh.Name):$($i + 1)"
    }
}
Assert-Test "리눅스 설치 스크립트의 timeout 이 setsid(터미널 분리)와 함께 쓰이는가 (SIGTTIN 정지 방지)" ($timeoutViolations.Count -eq 0) `
    ("위반: " + ($timeoutViolations -join ", "))

# --- 6-3. 설치 스크립트가 공용 파일(_common.sh·_install-utils.sh·bw-lib)을 $DEVTOOLS2 로컬 저장소에서 불러오지 않는가
#     오래된 로컬 공용 파일을 불러오면 새 공용 함수가 없어 중단 → "스크립트 옆 파일 → 같은 커밋(DT2_REF) 원격" 순서
$localSourceViolations = @()
foreach ($sh in (Get-ChildItem -Path $devEnvDir -File -Filter "*.sh")) {
    $shLines = [System.IO.File]::ReadAllLines($sh.FullName, [System.Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $shLines.Count; $i++) {
        $l = $shLines[$i]
        if ($l -match '^\s*#') { continue }
        $code = ($l -split ' #', 2)[0]
        if ($code -match '\$\{?DEVTOOLS2[^/"]*\}?/scripts/(linux/dev-env/_[A-Za-z-]+\.sh|fzf/bw-lib)') { $localSourceViolations += "$($sh.Name):$($i + 1)" }
    }
}
Assert-Test "설치 스크립트가 공용 파일을 `$DEVTOOLS2 로컬 저장소 대신 스크립트 옆·같은 커밋 원격에서 불러오는가" ($localSourceViolations.Count -eq 0) `
    ("위반: " + ($localSourceViolations -join ", "))

# --- 6-4. WSLg 한글 입력 래퍼(wslg_ime_env_snippet)를 쓰는 GUI 앱 설치 스크립트가 ensure_gui_app_env 를 부르는가
#     래퍼의 입력기 코드는 fcitx5 가 있을 때만 동작 → 앱 설치 스크립트가 입력기·글꼴을 준비해야 함
#     (예전에는 Sublime Merge 만 준비해 Orca 만 설치하면 WSLg 창에서 한글 입력 불가)
$guiViolations = @()
foreach ($sh in (Get-ChildItem -Path $devEnvDir -File -Filter "*.sh")) {
    if ($sh.Name -eq "_install-utils.sh") { continue }
    $shLines = [System.IO.File]::ReadAllLines($sh.FullName, [System.Text.Encoding]::UTF8)
    $code = ($shLines | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    if ($code.Contains('$(wslg_ime_env_snippet)') -and -not $code.Contains('ensure_gui_app_env ')) { $guiViolations += $sh.Name }
}
Assert-Test "WSLg 한글 입력 래퍼를 쓰는 GUI 앱 설치 스크립트가 ensure_gui_app_env 를 부르는가" ($guiViolations.Count -eq 0) `
    ("위반: " + ($guiViolations -join ", "))

# --- 6-5. command-palette 의 그룹 파일 · 메뉴 항목 ID · 실행 함수가 짝이 맞는가 (메뉴 문구 부분 문자열로 분기하지 않는가)
#     예전에는 메뉴 문구의 부분 문자열(*"실행"* 등)로 분기를 골라, 문구가 겹치면 엉뚱한 분기가 실행될 수 있었음
#     → 항목은 "ID<TAB>문구", 실행은 cp_run_<ID> 함수. 팔레트는 1단계 그룹마다 palette.d\<그룹 ID>.sh 파일 하나
#     ● _CP_GROUP_FILES ↔ palette.d 그룹 파일(_lib.sh 제외) 일치, 그룹 파일의 등록 ID = 파일 이름, cp_group_<ID> 존재
#     ● 메뉴 ID(배열 항목 줄 · 조건부 _MENU_X+=("ID<TAB>...") · Gradle quick:<ID>)마다 cp_run_<ID> 가 하나씩 같은 파일에
#     ● palette.d 에서 BASH_SOURCE 금지(함수가 palette.d 파일에 정의돼 그 파일을 가리킴 → 팔레트 위치는 $_CP_SCRIPT_DIR)
#     ● if/elif 분기([ "$CHOICE_ID" = ... ])·문구 부분 문자열 분기 없음
function Get-PaletteCodeOnly([string]$text) {
    (($text -split "`r?`n") | Where-Object { -not $_.TrimStart().StartsWith('#') }) -join "`n"
}
$paletteMenuBad = @()
$paletteMainCode = Get-PaletteCodeOnly ([System.IO.File]::ReadAllText($paletteMain, [System.Text.Encoding]::UTF8))
$paletteGroupFiles = @{}
foreach ($pf in @(Get-ChildItem -LiteralPath $paletteDir -Filter "*.sh" -File | Sort-Object Name)) {
    $paletteGroupFiles[[System.IO.Path]::GetFileNameWithoutExtension($pf.Name)] = Get-PaletteCodeOnly ([System.IO.File]::ReadAllText($pf.FullName, [System.Text.Encoding]::UTF8))
}
$groupNames = @($paletteGroupFiles.Keys | Where-Object { $_ -ne '_lib' } | Sort-Object)
if (-not $paletteGroupFiles.ContainsKey('_lib')) { $paletteMenuBad += "palette.d/_lib.sh 없음" }
$orderMatch = [regex]::Match($paletteMainCode, '(?m)^_CP_GROUP_FILES=\(([^)]*)\)')
$groupOrder = @()
if ($orderMatch.Success) { $groupOrder = @($orderMatch.Groups[1].Value -split '\s+' | Where-Object { $_ }) }
if ($groupOrder.Count -eq 0) {
    $paletteMenuBad += "_CP_GROUP_FILES 없음"
} elseif ((@($groupOrder | Sort-Object -Unique) -join ',') -ne ($groupNames -join ',') -or @($groupOrder | Sort-Object -Unique).Count -ne $groupOrder.Count) {
    $paletteMenuBad += ("불러오는 그룹(" + ($groupOrder -join ',') + ") ≠ palette.d 그룹 파일(" + ($groupNames -join ',') + ")")
}
$runOwner = @{}
foreach ($g in @($paletteGroupFiles.Keys | Sort-Object)) {
    $code = $paletteGroupFiles[$g]
    $regs = @([regex]::Matches($code, 'cp_register_group\s+([a-z0-9_]+)\s') | ForEach-Object { $_.Groups[1].Value })
    if ($g -eq '_lib') {
        if ($regs.Count -gt 0) { $paletteMenuBad += "_lib.sh 가 그룹을 등록함" }
    } else {
        if ((@($regs | Sort-Object -Unique) -join ',') -ne $g) { $paletteMenuBad += ("$g.sh 의 1단계 등록 ID(" + (@($regs) -join ',') + ")가 파일 이름과 다름") }
        if ($code -notmatch ('(?m)^cp_group_' + [regex]::Escape($g) + '\(\)\s*\{')) { $paletteMenuBad += "cp_group_$g 없음" }
    }
    $items = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($code, '(?m)(?:^\s*|\+?=\()"([a-z0-9_]+)\t')) { [void]$items.Add($m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($code, '_GT_RESULT="quick:([a-z0-9_]+)"')) { [void]$items.Add($m.Groups[1].Value) }
    $runs = @([regex]::Matches($code, '(?m)^cp_run_([a-z0-9_]+)\(\)\s*\{') | ForEach-Object { $_.Groups[1].Value })
    foreach ($r in $runs) {
        if ($runOwner.ContainsKey($r)) { $paletteMenuBad += "실행 함수 중복: cp_run_$r ($($runOwner[$r]).sh, $g.sh)" }
        $runOwner[$r] = $g
    }
    $noRun = @($items | Where-Object { $runs -notcontains $_ } | Sort-Object)
    if ($noRun.Count -gt 0) { $paletteMenuBad += ("$g.sh 실행 함수 없는 메뉴: " + ($noRun -join ",")) }
    $noItem = @($runs | Where-Object { -not $items.Contains($_) } | Sort-Object)
    if ($noItem.Count -gt 0) { $paletteMenuBad += ("$g.sh 메뉴 없는 실행 함수: " + ($noItem -join ",")) }
    if ($code.Contains('BASH_SOURCE')) { $paletteMenuBad += "palette.d/$g.sh 에서 BASH_SOURCE 사용 (팔레트 위치는 `$_CP_SCRIPT_DIR)" }
}
if ($runOwner.Count -eq 0) { $paletteMenuBad += "메뉴 ID 없음" }
$paletteAllCode = $paletteMainCode + "`n" + (@($paletteGroupFiles.Values) -join "`n")
if ($paletteAllCode -match '\[ "\$CHOICE_ID" =') { $paletteMenuBad += "if/elif 분기 남음" }
if ($paletteAllCode -match '\[\[ "\$CHOICE" ==') { $paletteMenuBad += "문구 부분 문자열 분기 남음" }
Assert-Test "command-palette 의 그룹 파일 · 메뉴 항목 ID · 실행 함수가 짝이 맞는가" ($paletteMenuBad.Count -eq 0) ($paletteMenuBad -join "; ")

# --- 6-6. 세 편집기(VS Code·Neovim·Zed)의 jdtls 힙이 고정값이 아니라 실행 환경 메모리 기준인가
#     VS Code 가 -Xms8G -Xmx8G 로 고정되어 WSL(기본 PC 메모리의 절반) 안에서 시작부터 8GB 를 잡았음 → 셋 다 메모리의 25% 기준
$jdtlsHeapBad = @()
$vsCode = [System.IO.File]::ReadAllText((Join-Path $repoRootPath ".config\vscode\settings.json"), [System.Text.Encoding]::UTF8)
$vmMatch = [regex]::Match($vsCode, '(?m)^\s*"java\.jdt\.ls\.vmargs"\s*:\s*"([^"]*)"')
if (-not $vmMatch.Success -or $vmMatch.Groups[1].Value -match '-Xmx\d' -or -not $vmMatch.Groups[1].Value.Contains('MaxRAMPercentage')) { $jdtlsHeapBad += "VS Code vmargs" }
$nvJava = [System.IO.File]::ReadAllText((Join-Path $repoRootPath ".config\nvim\lua\plugins\java.lua"), [System.Text.Encoding]::UTF8)
if (-not $nvJava.Contains('MemTotal') -or $nvJava -match '--jvm-arg=-Xmx\d') { $jdtlsHeapBad += "Neovim java.lua" }
$zedLauncher = [System.IO.File]::ReadAllText((Join-Path $repoRootPath "scripts\java\jdtls"), [System.Text.Encoding]::UTF8)
$zedExecs = @(($zedLauncher -split "`r?`n") | Where-Object { $_.Trim().StartsWith('exec "$JDTLS_BIN"') })
if (-not $zedLauncher.Contains('MemTotal') -or $zedExecs.Count -eq 0 -or @($zedExecs | Where-Object { -not $_.Contains('JDTLS_HEAP_ARGS') }).Count -gt 0) { $jdtlsHeapBad += "Zed 런처" }
Assert-Test "VS Code·Neovim·Zed 의 jdtls 힙이 고정값이 아니라 실행 환경 메모리 기준인가" ($jdtlsHeapBad.Count -eq 0) `
    ("위반: " + ($jdtlsHeapBad -join ", "))

# --- 6-7. 0.setup-wsl.ps1 의 .wslconfig(9 · 9-1 메모리) · 배포판 정보 저장(10) 단계가 "배포판 새로 설치" 함수·호출 블록 밖에 있는가
#     예전에는 새 설치 블록이 스크립트 끝까지 이어져 기존 배포판 재설치에서 9 · 9-1 · 10 단계를 통째로 건너뜀
#     (실측: 온라인 설치를 다시 해도 WSL 메모리 상한을 묻지 않음) → 새 설치 단계는 Install-NewDevtools2Distro 함수,
#     호출은 if ($isNewDistroInstall) { . Install-NewDevtools2Distro } — 두 블록 모두 "# 9." 앞에서 닫혀야 함
#     ● PowerShell 구문 트리(AST)로 함수·if 블록의 끝 줄을 구해 각 단계 주석 줄과 비교
#     ● 함수 본문에 최상위 return 이 없어야 함(인라인일 때는 스크립트 종료였지만 함수에서는 함수만 빠져나와 의미가 바뀜)
$wslSetupPath = Join-Path $repoRootPath "scripts\windows\dev-env\0.setup-wsl.ps1"
$wslSetupSrc = [System.IO.File]::ReadAllText($wslSetupPath, [System.Text.Encoding]::UTF8)
$wslSetupLines = $wslSetupSrc -split "`r?`n"
$wslBlockBad = @()
$wslTokens = $null
$wslErrors = $null
$wslAst = [System.Management.Automation.Language.Parser]::ParseInput($wslSetupSrc, [ref]$wslTokens, [ref]$wslErrors)
$newInstallFn = @($wslAst.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Install-NewDevtools2Distro'
    }) | Select-Object -First 1
$newInstallIf = @($wslAst.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.IfStatementAst] -and $_.Clauses[0].Item1.Extent.Text -eq '$isNewDistroInstall'
    }) | Select-Object -First 1
$wslBlocks = @()
if ($null -eq $newInstallFn) { $wslBlockBad += "Install-NewDevtools2Distro 함수 없음" } else { $wslBlocks += , @('Install-NewDevtools2Distro 함수', $newInstallFn.Extent) }
if ($null -eq $newInstallIf) { $wslBlockBad += "새 설치 호출 블록(if (`$isNewDistroInstall)) 없음" } else { $wslBlocks += , @('새 설치 호출 블록', $newInstallIf.Extent) }
# 단계 주석은 들여쓰기와 상관없이 모든 위치를 봅니다(단계를 함수 안으로 옮기면 들여써지므로)
foreach ($stepMark in @('# 9. Windows', '# 9-1.', '# 10.')) {
    $stepLines = @()
    for ($li = 0; $li -lt $wslSetupLines.Count; $li++) {
        if ($wslSetupLines[$li].TrimStart().StartsWith($stepMark)) { $stepLines += ($li + 1) }
    }
    if ($stepLines.Count -eq 0) { $wslBlockBad += "$stepMark 없음"; continue }
    foreach ($blk in $wslBlocks) {
        $inside = @($stepLines | Where-Object { $_ -ge $blk[1].StartLineNumber -and $_ -le $blk[1].EndLineNumber })
        if ($inside.Count -gt 0) { $wslBlockBad += "$stepMark 단계가 $($blk[0]) 안에 있음" }
    }
}
if ($null -ne $newInstallFn) {
    # 함수 본문 바로 아래(중첩 스크립트 블록 { ... } 안이 아닌) return 문
    $fnBody = $newInstallFn.Body
    $topReturns = @($fnBody.FindAll({ param($n) $n -is [System.Management.Automation.Language.ReturnStatementAst] }, $true) | Where-Object {
            $p = $_.Parent
            while ($null -ne $p -and -not ($p -is [System.Management.Automation.Language.ScriptBlockAst])) { $p = $p.Parent }
            $p -eq $fnBody
        })
    foreach ($r in $topReturns) { $wslBlockBad += "함수 본문 최상위 return ($($r.Extent.StartLineNumber)행)" }
}
Assert-Test "0.setup-wsl.ps1 의 .wslconfig·메모리·배포판 정보 단계가 기존 배포판 재설치에서도 실행되는가" ($wslBlockBad.Count -eq 0) `
    ($wslBlockBad -join "; ")

# ==============================================================================
# [최종 요약 결과]
# ==============================================================================
Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Cyan
Write-Host "  테스트 결과 요약: 총 $($testStats.total) 건 | 통과: $($testStats.passed) 건 | 실패: $($testStats.failed) 건" -ForegroundColor $(if ($testStats.failed -eq 0) { "Green" } else { "Red" })
Write-Host "===========================================================================" -ForegroundColor Cyan
Write-Host ""

if ($testStats.failed -gt 0) {
    Write-Host "  $($testStats.failed) 건의 테스트가 실패했습니다. 커밋하기 전에 위의 실패 항목을 반드시 수정하십시오." -ForegroundColor Red
    exit 1
} else {
    Write-Host "  모든 테스트를 완벽하게 통과했습니다! 안전하게 커밋 및 푸시할 수 있습니다." -ForegroundColor Green
    exit 0
}
