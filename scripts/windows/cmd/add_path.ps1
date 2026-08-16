<#
:: =================================================================
:: 프로그램명: add_path.ps1
:: 기능: 실행 권한에 따라 경로를 사용자(User) 또는 시스템(Machine) 환경 변수에 자동 추가
::       - 일반 권한 실행 시: 사용자(User) 환경 변수에 등록
::       - 관리자 권한 실행 시: 시스템(Machine) 환경 변수에 등록
:: 사용법: .\add_path.ps1 "C:\추가할\경로"
:: =================================================================
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$NewPath
)

# 1. 필수 인자(경로) 확인
# (PowerShell의 param 처리로 대체되지만 기존 로직 흐름 유지)
if ([string]::IsNullOrWhiteSpace($NewPath)) {
    Write-Host "[Error] 추가할 경로를 입력해주세요." -ForegroundColor Red
    Write-Host "사용법: .\add_path.ps1 'C:\경로'"
    pause
    exit
}

set-variable -name "NEW_PATH" -value $NewPath

# 2. PowerShell 실행 권한 및 대상 결정 (기존 배치의 PS 로직 반영)
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
    # 3. 환경 변수 읽기
    $current = [Environment]::GetEnvironmentVariable('Path', $target)
    if ($null -eq $current) { $current = '' }

    # 4. 경로 정리 및 리스트화
    $current = $current.TrimEnd(';')
    $list = $current.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)

    # 5. 중복 확인 및 등록
    if ($list -notcontains $NEW_PATH) {
        $new = if ($current -eq '') { $NEW_PATH } else { $current + ';' + $NEW_PATH }

        [Environment]::SetEnvironmentVariable('Path', $new, $target)

        Write-Host '성공: 환경 변수가 정상적으로 등록되었습니다.' -ForegroundColor Green
    } else {
        Write-Host '알림: 이미 등록된 경로입니다.' -ForegroundColor Yellow
    }
} catch {
    Write-Host "오류: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 6. 성공 메시지 및 안내
Write-Host ""
Write-Host "변경 사항을 적용하려면 현재 열려 있는 터미널 창을 닫고 다시 열어주세요."

# ⚠️ 이 스크립트는 외부 실행 파일을 전혀 호출하지 않으므로 $LASTEXITCODE는 항상
# "이 세션에서 이전에 실행됐던 다른 네이티브 명령"의 잔여값일 뿐입니다(cmdlet/.NET
# 호출은 $LASTEXITCODE를 갱신하지 않음 — PowerShell의 잘 알려진 동작). 실제 실패는
# 이미 위 catch 블록에서 exit 1로 처리되므로, 이 죽은 코드는 오히려 이전 세션의
# 무관한 실패값 때문에 정상 성공 시에도 거짓 오류를 띄울 수 있어 제거합니다.

pause
