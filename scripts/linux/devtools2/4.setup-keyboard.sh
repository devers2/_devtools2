#!/bin/bash
# ==============================================================================
# keyd 설치 및 CapsLock 키보드 리매핑 설정 스크립트 (4.setup-keyboard.sh)
#
# 기능:
#   - WSL 환경이면 자동으로 건너뜀 (WSL에서는 AutoHotKey로 동일 기능 제공)
#   - apt install keyd 가 가능하면 패키지 설치 사용
#   - 불가능하면 소스를 /var/opt/_devtools2/modules/keyd 에 클론 후 빌드/설치
#   - /etc/keyd/default.conf 에 설정 파일 복사
#   - keyd systemd 서비스 활성화
#
# CapsLock 리매핑:
#   - 짧게 탭     → ESC
#   - 다른 키와   → Ctrl (overload)
#   - Shift + CapsLock → 대문자 고정 ON
#   - 대문자 고정 ON 상태에서 CapsLock 또는 ESC → 대문자 고정 OFF
# ==============================================================================

set -euo pipefail

# ── DEVTOOLS2 경로 결정 ────────────────────────────────────────────────────────
if [ -z "${DEVTOOLS2:-}" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")
fi

if [ ! -f "$DEVTOOLS2/scripts/linux/devtools2/4.setup-keyboard.sh" ]; then
    DEVTOOLS2="/var/opt/_devtools2"
fi

# ── 색상 헬퍼 로드 ─────────────────────────────────────────────────────────────
_load_colors() {
    [ -n "${_COLORS_LOADED:-}" ] && return 0

    local script_dir; script_dir=$(dirname "$(readlink -f "$0" 2>/dev/null || echo ".")")
    local colors_file="$script_dir/_colors.sh"

    if [ ! -f "$colors_file" ] && [ -n "${DEVTOOLS2:-}" ] && [ -f "$DEVTOOLS2/scripts/linux/devtools2/_colors.sh" ]; then
        colors_file="$DEVTOOLS2/scripts/linux/devtools2/_colors.sh"
    fi

    if [ -f "$colors_file" ]; then
        # shellcheck disable=SC1090
        source "$colors_file" 2>/dev/null && _COLORS_LOADED=true && return 0
    fi

    if curl -sSfL --max-time 5 "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/devtools2/_colors.sh" -o /tmp/_colors_remote.sh 2>/dev/null; then
        # shellcheck disable=SC1091
        source /tmp/_colors_remote.sh 2>/dev/null && _COLORS_LOADED=true && return 0
    fi

    _C_RESET='' _C_BOLD='' _C_CYAN='' _C_GREEN='' _C_YELLOW='' _C_RED='' _C_WHITE='' _C_GRAY=''
    if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
        _C_RESET='\033[0m' _C_BOLD='\033[1m' _C_CYAN='\033[0;36m' _C_GREEN='\033[0;32m'
        _C_YELLOW='\033[0;33m' _C_RED='\033[0;31m' _C_WHITE='\033[1;37m'
    fi

    print_info()    { printf "${_C_CYAN}[정보]${_C_RESET} %s\n"    "$*"; }
    print_success() { printf "${_C_GREEN}[성공]${_C_RESET} %s\n"   "$*"; }
    print_done()    { printf "${_C_GREEN}[완료]${_C_RESET} %s\n"   "$*"; }
    print_warn()    { printf "${_C_YELLOW}[경고]${_C_RESET} %s\n"  "$*"; }
    print_error()   { printf "${_C_RED}[오류]${_C_RESET} %s\n"     "$*" >&2; }
    print_step()    { printf "${_C_CYAN}%s${_C_RESET}\n"           "$*"; }
    print_sep()     { printf "${_C_CYAN}%s${_C_RESET}\n" "==========================================================================="; }
    print_subsep()  { printf "${_C_CYAN}%s${_C_RESET}\n" "---------------------------------------------------------------------------"; }
    _COLORS_LOADED=true
}
_load_colors

# ── 루트 권한 체크 ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    print_error "이 스크립트는 관리자(root) 권한으로 실행해야 합니다. sudo 로 실행하세요."
    exit 1
fi

print_sep
print_step "[keyd] CapsLock 키보드 리매핑 설정"
print_sep

# ── WSL 환경 감지 → 건너뜀 ────────────────────────────────────────────────────
print_subsep
print_step "[Step 0] 실행 환경 확인"
print_subsep

if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
    print_warn "WSL 환경이 감지되었습니다. keyd는 리눅스 네이티브 전용입니다."
    print_info "WSL/Windows 환경에서는 AutoHotKey 를 통해 동일한 키보드 리매핑이 제공됩니다."
    print_info "Windows 설치 스크립트 (1.setup-wezterm.ps1) 를 참조하세요."
    exit 0
fi

print_success "리눅스 네이티브 환경 확인 → keyd 설치를 진행합니다."

# ── 경로 설정 ──────────────────────────────────────────────────────────────────
KEYD_MODULE_DIR="$DEVTOOLS2/modules/keyd"
KEYD_CONF_SRC="$DEVTOOLS2/.config/keyd/default.conf"
KEYD_CONF_DEST="/etc/keyd/default.conf"

# ── Step 1: keyd 설치 ─────────────────────────────────────────────────────────
print_subsep
print_step "[Step 1] keyd 설치"
print_subsep

# 이미 설치되어 있는지 확인
if command -v keyd &>/dev/null; then
    KEYD_VER=$(keyd --version 2>/dev/null || echo "unknown")
    print_info "keyd 이미 설치되어 있음: $KEYD_VER"
else
    # ── (1-A) apt 패키지로 설치 시도 ──────────────────────────────────────────
    print_info "apt 로 keyd 설치 시도 중..."

    apt-get update -qq >/tmp/_keyd_apt_update.log 2>&1 || true
    if apt-get install -y keyd >/tmp/_keyd_apt.log 2>&1; then
        print_success "apt 로 keyd 설치 완료."
    else
        # ── (1-B) 소스 빌드 설치 ──────────────────────────────────────────────
        print_warn "apt 설치 실패. 소스에서 빌드합니다: $KEYD_MODULE_DIR"

        # 빌드 의존성 설치
        print_info "빌드 의존성 설치 중 (make, gcc)..."
        apt-get install -y make gcc git >/tmp/_keyd_deps.log 2>&1 || {
            print_error "빌드 의존성 설치 실패. 로그: /tmp/_keyd_deps.log"
            exit 1
        }

        # 소스 클론 또는 업데이트
        if [ -d "$KEYD_MODULE_DIR/.git" ]; then
            print_info "keyd 소스 업데이트 중: $KEYD_MODULE_DIR"
            (cd "$KEYD_MODULE_DIR" && git pull --ff-only) >/tmp/_keyd_git.log 2>&1 || {
                print_warn "git pull 실패. 기존 소스 그대로 사용합니다."
            }
        else
            print_info "keyd 소스 클론 중: $KEYD_MODULE_DIR"
            mkdir -p "$(dirname "$KEYD_MODULE_DIR")"
            git clone https://github.com/rvaiya/keyd "$KEYD_MODULE_DIR" >/tmp/_keyd_git.log 2>&1 || {
                print_error "keyd 소스 클론 실패. 로그: /tmp/_keyd_git.log"
                exit 1
            }
        fi

        # 빌드 및 설치
        print_info "keyd 빌드 중..."
        (
            cd "$KEYD_MODULE_DIR"
            make >/tmp/_keyd_make.log 2>&1
        ) || {
            print_error "keyd 빌드 실패. 로그: /tmp/_keyd_make.log"
            exit 1
        }

        print_info "keyd 설치 중 (make install)..."
        (
            cd "$KEYD_MODULE_DIR"
            make install >/tmp/_keyd_install.log 2>&1
        ) || {
            print_error "keyd 설치 실패. 로그: /tmp/_keyd_install.log"
            exit 1
        }

        print_success "keyd 소스 빌드 및 설치 완료: $(command -v keyd)"
    fi
fi

# ── Step 2: 설정 파일 배포 ────────────────────────────────────────────────────
print_subsep
print_step "[Step 2] keyd 설정 파일 배포"
print_subsep

# /etc/keyd 디렉토리 생성
mkdir -p /etc/keyd

if [ -f "$KEYD_CONF_SRC" ]; then
    print_info "로컬 설정 파일 복사: $KEYD_CONF_SRC → $KEYD_CONF_DEST"
    cp -f "$KEYD_CONF_SRC" "$KEYD_CONF_DEST"
    print_success "keyd 설정 파일 배포 완료."
elif curl -sSfL --max-time 5 "https://raw.githubusercontent.com/devers2/_devtools2/main/.config/keyd/default.conf" -o "$KEYD_CONF_DEST" 2>/dev/null; then
    print_info "GitHub 원격에서 최신 default.conf 다운로드 완료 → $KEYD_CONF_DEST"
    print_success "keyd 설정 파일 원격 배포 완료."
else
    # 네트워크 연결 원격 다운로드 및 로컬 소스 모두 없을 때 인라인으로 생성
    print_warn "설정 소스를 찾을 수 없어 기본 설정을 인라인으로 생성합니다."
    cat > "$KEYD_CONF_DEST" <<'EOF'
[ids]
*

[main]
# 짧게 누르면 esc, 다른 키와 조합하면 control (keyd overload)
capslock = overload(control, esc)

# Shift + CapsLock → 대문자 고정 ON (caps 레이어 진입)
shift+capslock = toggle(caps)

# 오른쪽 컨트롤 키를 명시적으로 지정하여 keyd 에서 정확하게 인식할 수 있도록 함
rightcontrol = rightcontrol

[caps:toggle+shift]
# 대문자 고정 ON 상태에서:
# CapsLock 또는 ESC 키 → 대문자 고정 OFF (레이어 해제)
capslock = toggle(caps)
esc = toggle(caps)
EOF
    print_success "기본 설정 파일 생성 완료: $KEYD_CONF_DEST"
fi

print_info "적용된 설정 내용:"
cat "$KEYD_CONF_DEST" | sed 's/^/    /'

# ── Step 3: systemd 서비스 활성화 ─────────────────────────────────────────────
print_subsep
print_step "[Step 3] keyd systemd 서비스 활성화"
print_subsep

# systemd 사용 가능 여부 확인
if ! command -v systemctl &>/dev/null; then
    print_warn "systemctl 을 찾을 수 없습니다. 서비스 활성화를 건너뜁니다."
    print_info "keyd 를 수동으로 실행하려면: sudo keyd"
else
    systemctl daemon-reload 2>/dev/null || true

    # 기존 서비스 재시작 (설정 변경 반영)
    if systemctl is-active --quiet keyd 2>/dev/null; then
        print_info "keyd 서비스 재시작 중 (설정 변경 반영)..."
        systemctl restart keyd
        print_success "keyd 서비스 재시작 완료."
    else
        print_info "keyd 서비스 시작 및 부팅 자동 실행 등록 중..."
        systemctl enable --now keyd
        print_success "keyd 서비스 활성화 완료."
    fi

    # 서비스 상태 확인
    if systemctl is-active --quiet keyd; then
        print_success "keyd 서비스 정상 실행 중."
    else
        print_error "keyd 서비스 실행에 실패했습니다."
        systemctl status keyd --no-pager 2>&1 | head -20 >&2
        exit 1
    fi
fi

# ── 완료 ──────────────────────────────────────────────────────────────────────
print_sep
print_done "keyd CapsLock 리매핑 설정 완료!"
print_sep
printf "\n"
printf "${_C_WHITE}  적용된 키 동작:${_C_RESET}\n"
printf "${_C_GRAY}  ┌──────────────────────────────────────────────────────┐${_C_RESET}\n"
printf "${_C_GRAY}  │${_C_RESET}  CapsLock 단독 탭          → ESC                  ${_C_GRAY}│${_C_RESET}\n"
printf "${_C_GRAY}  │${_C_RESET}  CapsLock + 다른 키        → Ctrl 조합           ${_C_GRAY}│${_C_RESET}\n"
printf "${_C_GRAY}  │${_C_RESET}  Shift + CapsLock          → 대문자 고정 ON      ${_C_GRAY}│${_C_RESET}\n"
printf "${_C_GRAY}  │${_C_RESET}  (고정 ON) CapsLock / ESC  → 대문자 고정 OFF     ${_C_GRAY}│${_C_RESET}\n"
printf "${_C_GRAY}  └──────────────────────────────────────────────────────┘${_C_RESET}\n"
printf "\n"
