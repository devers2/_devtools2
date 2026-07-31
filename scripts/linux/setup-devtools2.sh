#!/bin/bash
# ==============================================================================
# DevTools2 전체 환경 자동 설치 마스터 스크립트 (setup-devtools2.sh)
#
# 목적:
#   scripts/linux/dev-env/ 하위의 0~3번 스크립트를 순서대로 자동 실행하여
#   DevTools2 포터블 개발 환경을 한 번에 완전히 구축합니다.
#
# 실행 순서:
#   0. init-devtools2     : Git 인증 설정 + 저장소 클론 + 그룹/권한 초기화 (sudo)
#   1. setup-env          : ~/.bashrc 환경 변수 주입
#      └─ source ~/.bashrc: 이후 스크립트가 환경 변수를 상속받을 수 있도록 로드
#   2. install-core-tools : Java, Gradle, Python, Node.js, Neovim, Zed, Ghostty 설치
#   3. install-cli-tools  : fzf, lazygit, ripgrep, fd, ast-grep, apt 패키지, hererocks 설치
#   4. setup-keyboard     : keyd 설치 + CapsLock 리매핑 설정 (WSL 환경이면 자동 건너뜀)
#
# 사용 방법:
#   bash /path/to/scripts/linux/setup-devtools2.sh
#   (스크립트 실행 중 sudo 비밀번호 및 Git 인증 정보 입력이 요청될 수 있습니다.)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
SUB_DIR="$SCRIPT_DIR/dev-env"

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

# 온라인 모드에서 서브스크립트를 안전하게 실행하는 헬퍼
# process substitution <(curl ...) 은 일부 환경에서 동작하지 않으므로 임시 파일 방식 사용
run_remote_script() {
    local url="$1"
    shift
    local tmp_script
    tmp_script=$(mktemp /tmp/_devtools2_script_XXXXXX.sh)
    # 스크립트 종료 시 임시 파일 자동 삭제
    trap "rm -f '$tmp_script'" RETURN
    if ! curl -sSfL "$url" -o "$tmp_script"; then
        print_error "원격 스크립트 다운로드 실패: $url"
        return 1
    fi
    chmod +x "$tmp_script"
    bash "$tmp_script" "$@"
}

# 로컬 실행 모드 여부 판정
IS_LOCAL=false
if [ -f "$SUB_DIR/0.init-devtools2.sh" ]; then
    IS_LOCAL=true
fi

RAW_BASE="https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env"

# ==============================================================================
# [Step 0] Git 인증 설정 + 저장소 클론 + 그룹/권한 초기화
# ==============================================================================
print_step "▶ [0/3] DevTools2 초기화 (sudo 권한 필요)"

if [ "$IS_LOCAL" = true ]; then
    print_info "로컬 초기화 스크립트 실행 중..."
    chmod +x "$SUB_DIR/0.init-devtools2.sh"
    sudo "$SUB_DIR/0.init-devtools2.sh"
else
    print_info "온라인 원격 초기화 스크립트 다운로드 및 실행 중..."
    curl -sSfL "$RAW_BASE/0.init-devtools2.sh" -o /tmp/0.init-devtools2.sh
    chmod +x /tmp/0.init-devtools2.sh
    sudo bash /tmp/0.init-devtools2.sh
    rm -f /tmp/0.init-devtools2.sh
fi

if [ $? -ne 0 ]; then
    print_error "[Step 0] 초기화 스크립트 실행 실패."
    exit 1
fi

# ==============================================================================
# [Step 1] 환경 변수 주입 (~/.bashrc)
# ==============================================================================
print_step "▶ [1/3] 환경 변수 설정 (~/.bashrc)"

if [ "$IS_LOCAL" = true ]; then
    chmod +x "$SUB_DIR/1.setup-env.sh"
    DEVTOOLS2=/var/opt/_devtools2 "$SUB_DIR/1.setup-env.sh"
else
    DEVTOOLS2=/var/opt/_devtools2 run_remote_script "$RAW_BASE/1.setup-env.sh"
fi

if [ $? -ne 0 ]; then
    print_error "[Step 1] 환경 변수 설정 실패."
    exit 1
fi

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
print_step "▶ [2/3] 핵심 포터블 도구 설치"

if [ "$IS_LOCAL" = true ]; then
    chmod +x "$SUB_DIR/2.install-core-tools.sh"
    DEVTOOLS2=/var/opt/_devtools2 "$SUB_DIR/2.install-core-tools.sh"
else
    DEVTOOLS2=/var/opt/_devtools2 run_remote_script "$RAW_BASE/2.install-core-tools.sh"
fi

if [ $? -ne 0 ]; then
    print_error "[Step 2] 핵심 도구 설치 실패."
    exit 1
fi

# ==============================================================================
# [Step 3] CLI 유틸리티 도구 설치 (fzf, lazygit, ripgrep, fd, ast-grep, hererocks 등)
# ==============================================================================
print_step "▶ [3/4] CLI 유틸리티 도구 설치"

if [ "$IS_LOCAL" = true ]; then
    chmod +x "$SUB_DIR/3.install-cli-tools.sh"
    DEVTOOLS2=/var/opt/_devtools2 "$SUB_DIR/3.install-cli-tools.sh"
else
    DEVTOOLS2=/var/opt/_devtools2 run_remote_script "$RAW_BASE/3.install-cli-tools.sh"
fi

if [ $? -ne 0 ]; then
    print_error "[Step 3] CLI 유틸리티 설치 실패."
    exit 1
fi

# ==============================================================================
# [Step 4] 키보드 리매핑 설정 (keyd — WSL 환경이면 자동 건너뜀)
# ==============================================================================
print_step "▶ [4/4] 키보드 리매핑 설정 (keyd)"

if [ "$IS_LOCAL" = true ]; then
    chmod +x "$SUB_DIR/4.setup-keyboard.sh"
    DEVTOOLS2=/var/opt/_devtools2 sudo "$SUB_DIR/4.setup-keyboard.sh"
else
    # 온라인 모드: 임시 파일로 저장 후 sudo로 실행 (process substitution은 sudo와 함께 동작 안 함)
    _kb_tmp=$(mktemp /tmp/_devtools2_keyboard_XXXXXX.sh)
    if curl -sSfL "$RAW_BASE/4.setup-keyboard.sh" -o "$_kb_tmp"; then
        chmod +x "$_kb_tmp"
        DEVTOOLS2=/var/opt/_devtools2 sudo bash "$_kb_tmp"
        _kb_exit=$?
    else
        print_warn "[Step 4] 키보드 스크립트 다운로드 실패 — 건너뜁니다."
        _kb_exit=0
    fi
    rm -f "$_kb_tmp"
    if [ "$_kb_exit" -ne 0 ]; then
        print_warn "[Step 4] 키보드 설정 실패 (비치명적, 계속 진행합니다)."
    fi
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
