#!/bin/bash
# ==============================================================================
# DevTools2 전체 환경 자동 설치 마스터 스크립트 (setup-devtools2.sh)
#
# 목적:
#   scripts/linux/dev-env/ 하위의 0~4번 스크립트를 GitHub main 브랜치에서
#   직접 스트리밍으로 순서대로 자동 실행하여 DevTools2 포터블 개발 환경을 구축합니다.
#
# ------------------------------------------------------------------------------
# ⚠️ [AI / 개발자 필독 - 설계 절대 원칙]
# 100% 온라인 전용 스트리밍: 서브스크립트는 bash <(curl -sSfL ...) 방식으로
# 무조건 GitHub main 원격 raw URL에서 직접 스트리밍 실행합니다.
# 로컬 파일 실행 분기(IS_LOCAL 등)를 추가하지 마십시오.
# ------------------------------------------------------------------------------
#
# 사용 방법:
#   bash /path/to/scripts/linux/setup-devtools2.sh
# ==============================================================================

set -euo pipefail

# 컬러 출력 헬퍼
print_banner() {
    echo ""
    echo "==========================================================================="
    echo "  $1"
    echo "==========================================================================="
    echo ""
}

print_step() {
    echo ""
    echo "---------------------------------------------------------------------------"
    echo "  $1"
    echo "---------------------------------------------------------------------------"
}

print_info()  { echo "[정보] $*"; }
print_warn()  { echo "[경고] $*" >&2; }
print_error() { echo "[오류] $*" >&2; }
print_done()  { echo "[완료] $*"; }

# GitHub raw URL에서 스크립트를 스트리밍으로 직접 실행하는 헬퍼
# - bash <(curl ...) 방식: temp 파일 미사용, NoBOM, BOM 이슈 없음
# - Cache-Control 헤더: CDN·프록시 캐시 강제 우회 → 항상 최신 스크립트 실행
run_remote_script() {
    local url="$1"
    shift
    bash <(curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$url") "$@"
}

# sudo 가 필요한 스크립트용 (curl | sudo bash 패턴)
run_remote_script_sudo() {
    local url="$1"
    shift
    curl -sSfL \
        -H 'Cache-Control: no-cache, no-store, must-revalidate' \
        -H 'Pragma: no-cache' \
        "$url" | sudo bash "$@"
}

RAW_BASE="https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env"

print_info "서브스크립트는 항상 GitHub main 브랜치 최신 버전으로 실행됩니다. (캐시 우회)"

# ==============================================================================
# [Step 0] Git 인증 설정 + 저장소 클론 + 그룹/권한 초기화
# ==============================================================================
print_step "▶ [0/4] DevTools2 초기화 (sudo 권한 필요)"

run_remote_script_sudo "$RAW_BASE/0.init-devtools2.sh"
print_done "[Step 0] 초기화 완료."

# ==============================================================================
# [Step 1] 환경 변수 주입 (~/.bashrc)
# ==============================================================================
print_step "▶ [1/4] 환경 변수 설정 (~/.bashrc)"

DEVTOOLS2=/var/opt/_devtools2 run_remote_script "$RAW_BASE/1.setup-env.sh"
print_done "[Step 1] 환경 변수 설정 완료."

# source ~/.bashrc 를 마스터 스크립트 프로세스 내에서 실행하면,
# 이후 호출되는 2, 3번 스크립트(자식 프로세스)가 환경 변수를 상속받습니다.
print_info "source ~/.bashrc 실행 중..."
# 멱등성 보장: bashrc 내부의 미정의 변수, pipefail, errexit 오류를 모두 억제하고 source 진행
set +euo pipefail
# shellcheck source=/dev/null
source "$HOME/.bashrc" 2>/dev/null || true
set -euo pipefail
print_done "환경 변수가 현재 세션에 적용되었습니다."

# ==============================================================================
# [Step 2] 핵심 포터블 도구 설치 (Java, Node.js, Python, Neovim, Zed, Ghostty 등)
# ==============================================================================
print_step "▶ [2/4] 핵심 포터블 도구 설치"

DEVTOOLS2=/var/opt/_devtools2 run_remote_script "$RAW_BASE/2.install-core-tools.sh"
print_done "[Step 2] 핵심 도구 설치 완료."

# ==============================================================================
# [Step 3] CLI 유틸리티 도구 설치 (fzf, lazygit, ripgrep, fd, ast-grep, hererocks 등)
# ==============================================================================
print_step "▶ [3/4] CLI 유틸리티 도구 설치"

DEVTOOLS2=/var/opt/_devtools2 run_remote_script "$RAW_BASE/3.install-cli-tools.sh"
print_done "[Step 3] CLI 유틸리티 설치 완료."

# ==============================================================================
# [Step 4] 키보드 리매핑 설정 (keyd — WSL 환경이면 자동 건너뜀, 비치명적)
# ==============================================================================
print_step "▶ [4/4] 키보드 리매핑 설정 (keyd)"

# set -e 를 일시 중단: Step 4는 실패해도 전체 설치를 중단하지 않음
set +e
run_remote_script_sudo "$RAW_BASE/4.setup-keyboard.sh"
_kb_exit=$?
set -e

if [ "$_kb_exit" -ne 0 ]; then
    print_warn "[Step 4] 키보드 설정 실패 (비치명적, 계속 진행합니다). 종료 코드: $_kb_exit"
else
    print_done "[Step 4] 키보드 설정 완료."
fi

# ==============================================================================
# 완료
# ==============================================================================
print_banner "🎉 DevTools2 전체 환경 구축 완료!"
echo "  이제 새 터미널을 열거나 아래 명령어를 실행하면 모든 도구를 바로 사용할 수 있습니다."
echo ""
echo "    source ~/.bashrc"
echo ""
echo "  설치 확인 명령어:"
echo "    echo \$DEVTOOLS2"
echo "    echo \$PATH"
echo "    node --version"
echo "    java --version"
echo "    nvim --version"
echo ""
echo "  키보드 리매핑 (리눅스 네이티브):"
echo "    CapsLock 단독 탭      → ESC"
echo "    CapsLock + 다른 키    → Ctrl 조합"
echo "    Shift + CapsLock      → 대문자 고정 ON"
echo "    (고정ON) CapsLock/ESC → 대문자 고정 OFF"
echo "==========================================================================="
echo ""
