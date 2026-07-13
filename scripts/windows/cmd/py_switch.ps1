<#
:: =================================================================
:: 프로그램명: py_switch.ps1
:: 기능: 상대 경로를 기반으로 PYTHON_HOME 버전을 전환 (314, 312)
::       - set_env.ps1를 호출하여 환경 변수를 실제 변경합니다.
::       - 관리자 권한 실행 시 시스템, 아니면 사용자 환경변수 설정
:: 사용법: .\py_switch.ps1 314  (또는 312)
:: =================================================================
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$PythonVersion
)

# 1. 필수 인자(파이썬 버전) 확인
if ([string]::IsNullOrWhiteSpace($PythonVersion)) {
    Write-Host "[Error] 파이썬 버전을 입력해주세요 (314, 312)." -ForegroundColor Red
    Write-Host "사용법: .\py_switch.ps1 314"
    pause
    exit
}

# 2. 기준 경로 설정 (현재 파일 위치 추출)
$CURRENT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition

# 3. 버전별 폴더명 설정 (python-버전 형식)
$FOLDER_NAME = "python-$PythonVersion"

# 4. 상대 경로를 사용하여 최종 절대 경로 계산
try {
    $RELATIVE_PATH = Join-Path $CURRENT_DIR "..\..\..\modules\python\$FOLDER_NAME"
    if (-not (Test-Path $RELATIVE_PATH)) {
        # 기존 bin 폴더 구조도 호환되도록 확인
        $RELATIVE_PATH = Join-Path $CURRENT_DIR "..\..\..\bin\python\$FOLDER_NAME"
    }

    $TARGET_PATH = (Resolve-Path $RELATIVE_PATH -ErrorAction Stop).Path
}
catch {
    Write-Host "[Error] 해당 파이썬 경로를 찾을 수 없습니다." -ForegroundColor Red
    Write-Host "예상 경로: ..\..\..\modules\python\$FOLDER_NAME"
    pause
    exit
}

# 5. set_env.ps1 호출 (동일 폴더 내 존재 가정)
Write-Host "[정보] Python $PythonVersion (폴더: $FOLDER_NAME) 버전으로 전환을 시도합니다..."
Write-Host "[정보] 경로: $TARGET_PATH"

$SET_ENV_PATH = Join-Path $CURRENT_DIR "set_env.ps1"
if (Test-Path $SET_ENV_PATH) {
    & $SET_ENV_PATH "PYTHON_HOME" "$TARGET_PATH"
} else {
    Write-Host ""
    Write-Host "[오류] 환경 변수 변경에 실패했습니다. (set_env.ps1 확인 필요)" -ForegroundColor Red
    pause
    exit 1
}

# 6. 결과 처리
exit
