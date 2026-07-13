<#
:: =================================================================
:: 프로그램명: set_env.ps1
:: 기능: 실행 권한에 따라 환경 변수를 사용자(User) 또는 시스템(Machine)에 설정/변경
::       - 일반 권한 실행 시: 사용자(User) 환경 변수에 등록 및 변경
::       - 관리자 권한 실행 시: 시스템(Machine) 환경 변수에 등록 및 변경
::       - 이미 동일한 이름의 환경 변수가 존재하면 입력한 새 경로로 덮어씁니다.
:: 사용법: .\set_env.ps1 "환경변수명" "C:\추가할\경로"
:: =================================================================
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$VarName,

    [Parameter(Mandatory=$false)]
    [string]$VarValue
)

# 1. 필수 인자(환경 변수명, 경로) 확인
if ([string]::IsNullOrWhiteSpace($VarName)) {
    Write-Host "[Error] 환경 변수명을 입력해주세요." -ForegroundColor Red
    Write-Host "사용법: .\set_env.ps1 `"변수명`" `"C:\경로`""
    pause
    exit
}

if ([string]::IsNullOrWhiteSpace($VarValue)) {
    Write-Host "[Error] 설정할 경로를 입력해주세요." -ForegroundColor Red
    Write-Host "사용법: .\set_env.ps1 `"변수명`" `"C:\경로`""
    pause
    exit
}

set-variable -name "VAR_NAME" -value $VarName
set-variable -name "VAR_VALUE" -value $VarValue

# 2. PowerShell 실행 (환경 변수 설정 및 덮어쓰기 로직)
# (배치 파일 내부의 PowerShell 로직을 기본 스크립트 로직으로 전환)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    $target = [EnvironmentVariableTarget]::Machine
    $perm = '관리자'
} else {
    $target = [EnvironmentVariableTarget]::User
    $perm = '일반'
}

Write-Host "[정보] 권한: $perm - 대상: $($target.ToString())"

try {
    # 환경 변수 설정
    [Environment]::SetEnvironmentVariable($VAR_NAME, $VAR_VALUE, $target)

    Write-Host "성공: 환경 변수 [$VAR_NAME]가 [$VAR_VALUE]로 정상적으로 설정되었습니다." -ForegroundColor Green
} catch {
    Write-Host "오류: $($_.Exception.Message)" -ForegroundColor Red

    # 3. 에러 발생 시 처리
    Write-Host ""
    Write-Host "[오류] 환경 변수 등록에 실패했습니다."
    pause
    exit 1
}

# 4. 성공 메시지 및 안내
Write-Host ""
Write-Host "변경 사항을 적용하려면 현재 열려 있는 터미널 창을 닫고 다시 열어주세요."

pause
