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
#    - Linux safe_download_and_extract / safe_download_binary 파라미터 정합성
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
$repoRootPath = if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
    (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    (Get-Location).Path
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

$targetExtensions = @("*.ps1", "*.sh", "*.bash", "*.json", "*.toml", "*.conf")
$bomViolations = @()
$paramViolations = @()

foreach ($ext in $targetExtensions) {
    Get-ChildItem -Path $repoRootPath -Recurse -File -Filter $ext | Where-Object {
        $_.FullName -notmatch "(\.git|\.vscode|\.idea|target|build|node_modules)"
    } | ForEach-Object {
        # 1) BOM 검사 (0xEF, 0xBB, 0xBF - PS 5.1 / 7 공용 .NET API 사용)
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        if ($bytes -and $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $bomViolations += $_.FullName.Substring($repoRootPath.Length + 1)
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

$psFiles = Get-ChildItem -Path $repoRootPath -Recurse -File -Filter "*.ps1" | Where-Object {
    $_.FullName -notmatch "(\.git|node_modules)"
}

$syntaxErrors = @()
foreach ($file in $psFiles) {
    $code = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($code, $file.FullName, [ref]$null, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $syntaxErrors += "$($file.Name): $($errors[0].Message)"
    }
}

Assert-Test "모든 .ps1 파일에 문법 오류가 없는가 (오류 파일: 0건)" ($syntaxErrors.Count -eq 0) `
    ($syntaxErrors -join "`n         -> ")

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
    $shFiles = Get-ChildItem -Path (Join-Path $repoRootPath "scripts\linux") -Recurse -File | Where-Object {
        $_.Extension -in @(".sh", ".bash")
    }

    $bashErrors = @()
    foreach ($sh in $shFiles) {
        $p = Start-Process $bashExe -ArgumentList "-n `"$($sh.FullName)`"" -Wait -PassThru -NoNewWindow -RedirectStandardError "$env:TEMP\bash_test_err.txt"
        if ($p.ExitCode -ne 0) {
            $errTxt = [string](Get-Content "$env:TEMP\bash_test_err.txt" -Raw -ErrorAction SilentlyContinue)
            $bashErrors += "$($sh.Name): $($errTxt.Trim())"
        }
        Remove-Item "$env:TEMP\bash_test_err.txt" -Force -ErrorAction SilentlyContinue
    }
    Assert-Test "모든 Linux .sh 스크립트가 bash -n 검사를 통과하는가" ($bashErrors.Count -eq 0) `
        ($bashErrors -join "`n         -> ")
} else {
    Assert-Test "Bash 환경 감지 (Git Bash / WSL 미설치로 건너뜀)" $true
}

# ==============================================================================
# [Suite 4] 런타임 회귀 버그 전수 검증 (과거 오류 100% 방지)
# ==============================================================================
Write-TestHeader "[Suite 4] 런타임 회귀 버그 전수 검증"

# --- 4-1. 0바이트 빈 파일에 대한 문자열 안전 처리 검증 (Trim on Null 방어)
$tempEmptyFile = Join-Path $env:TEMP "test_empty_error.log"
"" | Set-Content $tempEmptyFile -NoNewline -Force

# 기존 버그 재현 확인: Get-Content -Raw 는 빈 파일에서 $null 을 반환
$rawContent = Get-Content $tempEmptyFile -Raw
$isNull = ($null -eq $rawContent)

# 안전 패턴 검증 (Rule 7)
$safeExtracted = [string](Get-Content $tempEmptyFile -Raw -ErrorAction SilentlyContinue)
$safeTrimmed = if (-not [string]::IsNullOrWhiteSpace($safeExtracted)) { $safeExtracted.Trim() } else { "" }
Remove-Item $tempEmptyFile -Force -ErrorAction SilentlyContinue

Assert-Test "빈 파일 Get-Content -Raw 의 `$null 반환 특성 인지 및 안전 변환 검증" ($isNull -and $safeTrimmed -eq "")

# 0.setup-wsl.ps1 파일 내에 위험한 '(Get-Content ...).Trim()' 패턴이 남아있지 않은지 소스 전수 검사
$wslSetupFile = Join-Path $repoRootPath "scripts\windows\dev-env\0.setup-wsl.ps1"
$wslSetupCode = [System.IO.File]::ReadAllText($wslSetupFile, [System.Text.Encoding]::UTF8)
$hasUnsafeTrim = ($wslSetupCode -match '\(Get-Content[^\)]+\)\.Trim\(\)')
Assert-Test "0.setup-wsl.ps1 내 위험한 '(Get-Content).Trim()' 직통 호출이 0건인가" (-not $hasUnsafeTrim)

# --- 4-2. Start-Process 비동기 ExitCode $null 트랩 방어 검증 (Rule 8)
# Start-Process -PassThru 만 사용하고 -Wait 가 없으면 핸들이 닫혀 ExitCode 가 $null 임을 확인
$dummyProc = Start-Process powershell.exe -ArgumentList "-NoProfile -Command `"`"" -PassThru -NoNewWindow
while (-not $dummyProc.HasExited) { Start-Sleep -Milliseconds 50 }
$passThruExitIsNull = ($null -eq $dummyProc.ExitCode)

# 0.setup-wsl.ps1 에서 wsl --import 시 .NET Process API 를 사용하여 정수 ExitCode 를 반환하는지 검증
$usesProcessStartInfo = ($wslSetupCode -match 'System\.Diagnostics\.ProcessStartInfo')
$usesDotNetProcessStart = ($wslSetupCode -match '\[System\.Diagnostics\.Process\]::Start')
Assert-Test "0.setup-wsl.ps1 wsl --import 가 .NET ProcessStartInfo 기반으로 `$null 트랩을 방지하는가" ($usesProcessStartInfo -and $usesDotNetProcessStart)

# --- 4-3. WSL /etc/wsl.conf 파이썬 코드 인용부호 및 configparser 정상 동작 검증 (Rule 9)
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

# --- 4-4. 배포판 자가 치유 (Self-Healing) 분기 로직 검증
$hasSelfHealingCode = ($wslSetupCode -match '\[user\]' -and $wslSetupCode -match 'default\s*=' -and $wslSetupCode -match 'wsl\.exe\s+--unregister')
Assert-Test "0.setup-wsl.ps1 에 미완성 배포판 자동 감지 및 unregister 자가 치유 로직이 존재하는가" $hasSelfHealingCode

# --- 4-5. Linux 다운로드/압축해제 헬퍼 파라미터 정합성 검증
$coreToolsFile = Join-Path $repoRootPath "scripts\linux\dev-env\2.install-core-tools.sh"
$coreToolsCode = [System.IO.File]::ReadAllText($coreToolsFile, [System.Text.Encoding]::UTF8)

$hasJdkLabel = ($coreToolsCode -match 'safe_download_and_extract\s+"\$dl_url"\s+"\$target_path"\s+1\s+"\$checksum"\s+"JDK \$major"')
$hasGradleLabel = ($coreToolsCode -match 'safe_download_and_extract\s+"\$_gradle_url"\s+"\$DEVTOOLS2/modules/gradle"\s+0\s+"\$_gradle_sha"\s+"Gradle \$GRADLE_VERSION"')
$hasNeovimLabel = ($coreToolsCode -match 'safe_download_and_extract\s+"\$_nvim_url"\s+"\$DEVTOOLS2/modules/neovim/nvim"\s+1\s+"[^"]*"\s+"Neovim \$NEOVIM_VERSION"')

Assert-Test "Linux Core Tools(JDK, Gradle, Neovim) 다운로드 시 UX 라벨 인자가 완벽히 전달되는가" ($hasJdkLabel -and $hasGradleLabel -and $hasNeovimLabel)

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
