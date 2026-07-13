<#
:: =================================================================
:: 프로그램명: jdk_switch.ps1
:: 기능: 상대 경로를 기반으로 JAVA_HOME 버전을 전환 (25, 21, 17, 8)
::       - set_env.ps1를 호출하여 환경 변수를 실제 변경합니다.
::       - 관리자 권한 실행 시 시스템, 아니면 사용자 환경변수 설정
:: 사용법: .\jdk_switch.ps1 25  (또는 21, 17, 8)
:: =================================================================
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$JavaVersion
)

# 1. 필수 인자(자바 버전) 확인
if ([string]::IsNullOrWhiteSpace($JavaVersion)) {
    Write-Host "[Error] 자바 버전을 입력해주세요 (25, 21, 17, 8)." -ForegroundColor Red
    Write-Host "사용법: .\jdk_switch.ps1 25"
    pause
    exit
}

# 2. 기준 경로 설정 (현재 파일 위치 추출)
$CURRENT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition

# 3. 버전별 폴더명 설정 (8버전은 jdk-1.8 사용, 그 외는 jdk-버전 형식)
$FOLDER_NAME = ""
if ($JavaVersion -eq "8") {
    $FOLDER_NAME = "jdk-1.8"
} else {
    $FOLDER_NAME = "jdk-$JavaVersion"
}

# 4. 상대 경로를 사용하여 최종 절대 경로 계산
# 기존 구조를 유지하여 ..\..\..\modules\java\ 경로로 계산 (bin에서 modules로 변경된 이름 반영)
try {
    $RELATIVE_PATH = Join-Path $CURRENT_DIR "..\..\..\modules\java\$FOLDER_NAME"
    if (-not (Test-Path $RELATIVE_PATH)) {
        # 기존 bin 폴더 구조도 호환되도록 확인
        $RELATIVE_PATH = Join-Path $CURRENT_DIR "..\..\..\bin\java\$FOLDER_NAME"
    }

    $TARGET_PATH = (Resolve-Path $RELATIVE_PATH -ErrorAction Stop).Path
}
catch {
    Write-Host "[Error] 해당 JDK 경로를 찾을 수 없습니다." -ForegroundColor Red
    Write-Host "예상 경로: ..\..\..\modules\java\$FOLDER_NAME"
    pause
    exit
}

# 5. set_env.ps1 호출 (동일 폴더 내 존재 가정)
Write-Host "[정보] Java $JavaVersion (폴더: $FOLDER_NAME) 버전으로 전환을 시도합니다..."
Write-Host "[정보] 경로: $TARGET_PATH"

# 호출되는 set_env.ps1 내부에서 이미 메시지를 출력하므로, 여기서는 호출만 합니다.
$SET_ENV_PATH = Join-Path $CURRENT_DIR "set_env.ps1"
if (Test-Path $SET_ENV_PATH) {
    & $SET_ENV_PATH "JAVA_HOME" "$TARGET_PATH"
} else {
    Write-Host ""
    Write-Host "[오류] 환경 변수 변경에 실패했습니다. (set_env.ps1 확인 필요)" -ForegroundColor Red
    pause
    exit 1
}

# 6. 결과 처리 (이미 set_env에서 안내를 했으므로 바로 종료)
exit
