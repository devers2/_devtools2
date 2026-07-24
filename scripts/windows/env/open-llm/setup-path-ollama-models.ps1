# ============================================================
# OLLAMA_MODELS을 Z:\llm-models로 설정하는 스크립트
#
# 주요 기능:
# 1. Z:\llm-models 폴더 생성 (없을 경우 자동 생성)
# 2. OLLAMA_MODELS 시스템 환경 변수 등록 ($envScope 옵션으로 적용)
# 3. 실행 시 자동으로 관리자 권한을 확인하고 필요 시 요청
#
# 사용 방법:
# - 관리자 권한으로 실행 시 시스템 변수에 등록되며,
#   완료 후 모든 터미널과 IDE(VSCode 등)를 재시작해야 적용됨
# ============================================================

# --- 한글 깨짐 방지: 출력 인코딩을 UTF-8로 설정
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- [설정]
$newPath = "Z:\llm-models"

# --- [관리자 권한 확인 및 재실행 로직]
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[알림] 관리자 권한이 필요합니다. 권한 승격을 시도합니다." -ForegroundColor Yellow

    # PowerShell을 관리자 권한으로 재실행 (기존 배치의 VBS 방식 대신 직접 승격 호출)
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# --- 작업 시작
Write-Host "====================================================="
Write-Host "   OLLAMA_MODELS 설정 작업을 시작합니다." -ForegroundColor Cyan
Write-Host "====================================================="
Write-Host ""

# 1. 폴더 생성
if (-not (Test-Path $newPath)) {
    Write-Host "[진행] 폴더를 생성합니다: $newPath"
    New-Item -Path $newPath -ItemType Directory | Out-Null
} else {
    Write-Host "[확인] 이미 폴더가 존재합니다: $newPath" -ForegroundColor Gray
}

# 2. 환경 변수 등록
try {
    # [System.Environment]::SetEnvironmentVariable를 사용하여 시스템 전역(Machine)에 등록
    [System.Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $newPath, "Machine")

    Write-Host ""
    Write-Host "[성공] 시스템 환경 변수에 OLLAMA_MODELS이 반영되었습니다." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "[실패] 환경 변수 저장 중 오류가 발생했습니다." -ForegroundColor Red
    Write-Host "상세 오류: $($_.Exception.Message)" -ForegroundColor Red
}

# --- 작업 완료
Write-Host ""
Write-Host "====================================================="
Write-Host "    모든 작업이 완료되었습니다." -ForegroundColor DarkCyan
Write-Host "    적용을 위해 모든 터미널과 VSCode를 다시 실행하십시오."
Write-Host "====================================================="
Write-Host ""

# pause 구현
Read-Host "계속하려면 엔터 키를 누르십시오..."
