param([string[]]$Files)
# ==============================================================================
# [테스트 2-3 공용] .ps1 이 부르는 함수·cmdlet 중 어디에도 정의되지 않은 것 찾기
# ==============================================================================
# run-all-tests.sh · run-all-tests.ps1 이 같은 기준으로 쓰도록 검사 본문을 이 파일 하나에 둡니다.
# 사용: & ([scriptblock]::Create([System.IO.File]::ReadAllText(<이 파일>, [System.Text.Encoding]::UTF8))) -Files <.ps1 경로들>
#   (BOM 없는 UTF-8 파일이라 Windows PowerShell 5.1 의 -File 로 부르면 한글 주석이 깨져 읽히므로 scriptblock 으로 부름)
# 출력: DT2_CALLS=<검사한 호출 수>  /  DT2_UNDEF=<파일:줄 이름;...> (없으면 빈 값)
#
# [설계 원칙 / Rationale]
#   ● 0.setup-wsl.ps1 이 Write-Question 을 부르기만 하고 정의가 없었는데, 그 줄이 실행되는 경우(.wslconfig 에 미러링이
#     없을 때 · 메모리 상한 질문)가 드물어 문법 검사(2-1)로도 못 잡고 실제 재설치에서야 멈췄습니다.
#   ● PowerShell 구문 트리(AST)로 모든 명령 호출을 모으고, Verb-Noun 형태(함수·cmdlet 이름 규칙)만 봅니다
#     (wsl · winget 같은 외부 프로그램은 PC 마다 설치 여부가 달라 제외).
#   ● 정의 = 검사 대상 .ps1 전체의 function 정의(설치 스크립트는 _common.ps1 을 먼저 불러 함께 쓰므로 합쳐서 봄)
#     + 이 PowerShell 에서 Get-Command 로 찾을 수 있는 명령(내장 cmdlet · 모듈). 설치 대상과 같은 Windows PowerShell 5.1 로
#     실행해야 정확합니다(러너가 powershell.exe 를 우선 사용).
$defined = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$calls = @()
foreach ($f in $Files) {
    $code = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($code, $f, [ref]$null, [ref]$null)
    foreach ($d in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        [void]$defined.Add($d.Name)
    }
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $name = $c.GetCommandName()
        if ($name -and $name -match '^[A-Za-z]+-[A-Za-z0-9]+$') {
            $calls += [pscustomobject]@{ N = $name; F = [System.IO.Path]::GetFileName($f); L = $c.Extent.StartLineNumber }
        }
    }
}
$known = @{}
$miss = @()
foreach ($c in $calls) {
    if ($defined.Contains($c.N)) { continue }
    if (-not $known.ContainsKey($c.N)) { $known[$c.N] = [bool](Get-Command -Name $c.N -ErrorAction SilentlyContinue) }
    if (-not $known[$c.N]) { $miss += ($c.F + ':' + $c.L + ' ' + $c.N) }
}
'DT2_CALLS=' + $calls.Count
'DT2_UNDEF=' + ($miss -join ';')
