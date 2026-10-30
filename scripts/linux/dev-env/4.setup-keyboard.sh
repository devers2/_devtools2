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
#
# 전역 ESC → 영문 전환 (Windows AutoHotkey 의 _SetImeToEnglish 와 동일한 경험):
#   - Esc / CapsLock 탭 / Ctrl+[ 입력 직후 fcitx5 영문 전환 전용 키(Ctrl+Alt+Shift+F11)를 이어서 전송
#   - fcitx5 를 실제 입력기로 쓰는 경우에만 활성화 (아니면 터미널에 이상한 문자가 찍히지 않도록 순수 키로 배포)
# ==============================================================================

set -euo pipefail

# ── DEVTOOLS2 경로 결정 ────────────────────────────────────────────────────────
if [ -z "${DEVTOOLS2:-}" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")
fi

if [ ! -f "$DEVTOOLS2/scripts/linux/dev-env/4.setup-keyboard.sh" ]; then
    DEVTOOLS2="/var/opt/_devtools2"
fi

# ── 색상 헬퍼 로드 (온라인 전용) ──────────────────────────────────────────────────
# 공통 모듈 로드 (스크립트 옆 파일 → 없으면 같은 커밋(DT2_REF)의 원격 스트리밍)
#   ● 로컬 저장소에서 직접 실행하면 스크립트 옆 파일을 씁니다(같은 체크아웃이라 버전이 항상 맞음).
#   ● 스트리밍 실행(마스터가 받은 /tmp/_dt2_*.sh, bash <(curl ...))은 스크립트와 같은 커밋의 원격 파일을 씁니다.
#     예전에는 그 사이에 $DEVTOOLS2 로컬 저장소를 먼저 봤는데, 로컬이 커밋 동기화를 건너뛴 채(미커밋 변경·갈라짐)
#     오래되어 있으면 새 스크립트가 옛 공용 파일을 불러와 새 함수가 없어 중단될 수 있어 제외했습니다.
DT2_REF="${DT2_REF:-main}"
_GH_RAW="https://raw.githubusercontent.com/devers2/_devtools2/${DT2_REF}/scripts/linux/dev-env"
_SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
if [ -f "$_SCRIPT_DIR/_common.sh" ]; then
    # shellcheck disable=SC1091
    source "$_SCRIPT_DIR/_common.sh"
else
    # shellcheck disable=SC1090
    source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_common.sh") || { echo "[오류] _common.sh 로드 실패 - 네트워크 연결을 확인하세요." >&2; exit 1; }
fi

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
    print_info "Windows 설치 스크립트 (1.setup-autohotkey.ps1) 를 참조하세요."
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
# ⚠️ 포터블 원칙의 예외입니다(전체 목록/이유는 0.init-devtools2.sh 상단 메모 참고).
# keyd는 커널 input 레벨(/dev/input, uinput)에 systemd 서비스로 등록되어 동작하는 데몬이라
# 바이너리만 복사해서는 개념적으로 동작할 수 없습니다(항상 대상 OS에 직접 설치 필요).
if command -v keyd &>/dev/null; then
    KEYD_VER=$(keyd --version 2>/dev/null || echo "unknown")
    print_info "keyd 이미 설치되어 있음: $KEYD_VER"
else
    # ── (1-A) apt 패키지로 설치 시도 ──────────────────────────────────────────
    print_info "apt 로 keyd 설치 시도 중..."

    # 이전 apt 작업이 락을 쥐고 중단된 경우를 대비해 먼저 락을 강제 해제 — 단, fuser로
    # 실제로 쥐고 있는 프로세스가 없을 때만 지웁니다(진짜 실행 중인 apt/dpkg와 경합해
    # 데이터베이스가 손상되는 걸 방지; fuser가 없으면 기존처럼 무조건 삭제로 폴백).
    for _lockfile in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock; do
        if [ -e "$_lockfile" ]; then
            if command -v fuser &>/dev/null; then
                fuser "$_lockfile" >/dev/null 2>&1 || rm -f "$_lockfile"
            else
                rm -f "$_lockfile"
            fi
        fi
    done
    dpkg --configure -a 2>/dev/null || true

    # apt 목록 갱신·설치는 백그라운드로 돌리고 스피너로 진행 중임을 표시합니다
    _dt2_keyd_apt() {
        apt-get update -qq >$DT2_TMP/_keyd_apt_update.log 2>&1 || true
        apt-get install -y keyd >$DT2_TMP/_keyd_apt.log 2>&1
    }
    if run_with_spinner_cmd "keyd 설치 중 (apt)..." _dt2_keyd_apt; then
        print_success "apt 로 keyd 설치 완료."
    else
        # ── (1-B) 소스 빌드 설치 ──────────────────────────────────────────────
        print_warn "apt 설치 실패. 소스에서 빌드합니다: $KEYD_MODULE_DIR"

        # 빌드 의존성 설치
        print_info "빌드 의존성 설치 중 (make, gcc)..."
        _dt2_keyd_deps() { apt-get install -y make gcc git >$DT2_TMP/_keyd_deps.log 2>&1; }
        run_with_spinner_cmd "빌드 의존성 설치 중 (make, gcc, git)..." _dt2_keyd_deps || {
            print_error "빌드 의존성 설치 실패. 로그: $DT2_TMP/_keyd_deps.log"
            exit 1
        }

        # 소스 클론 또는 업데이트 (스피너 표시)
        if [ -d "$KEYD_MODULE_DIR/.git" ]; then
            (cd "$KEYD_MODULE_DIR" && git pull --ff-only) >$DT2_TMP/_keyd_git.log 2>&1 &
            _pull_pid=$!
            run_with_spinner "keyd 소스 업데이트 진행 중..." "$_pull_pid"
            wait "$_pull_pid" 2>/dev/null || print_warn "git pull 실패. 기존 소스 그대로 사용합니다."
            rm -f $DT2_TMP/_keyd_git.log
        else
            mkdir -p "$(dirname "$KEYD_MODULE_DIR")"
            git clone https://github.com/rvaiya/keyd "$KEYD_MODULE_DIR" >$DT2_TMP/_keyd_git.log 2>&1 &
            _clone_pid=$!
            run_with_spinner "keyd 소스 클론 진행 중..." "$_clone_pid"
            if ! wait "$_clone_pid" 2>/dev/null; then
                print_error "keyd 소스 클론 실패. 로그: $DT2_TMP/_keyd_git.log"
                exit 1
            fi
            rm -f $DT2_TMP/_keyd_git.log
        fi

        # 빌드 및 설치 (스피너 표시)
        (cd "$KEYD_MODULE_DIR" && make >$DT2_TMP/_keyd_make.log 2>&1) &
        _make_pid=$!
        run_with_spinner "keyd 컴파일 및 빌드 중 (make)..." "$_make_pid"
        if ! wait "$_make_pid" 2>/dev/null; then
            print_error "keyd 빌드 실패. 로그: $DT2_TMP/_keyd_make.log"
            exit 1
        fi
        rm -f $DT2_TMP/_keyd_make.log

        (cd "$KEYD_MODULE_DIR" && make install >$DT2_TMP/_keyd_install.log 2>&1) &
        _inst_pid=$!
        run_with_spinner "keyd 시스템 설치 중 (make install)..." "$_inst_pid"
        if ! wait "$_inst_pid" 2>/dev/null; then
            print_error "keyd 설치 실패. 로그: $DT2_TMP/_keyd_install.log"
            exit 1
        fi
        rm -f $DT2_TMP/_keyd_install.log

        print_success "keyd 소스 빌드 및 설치 완료: $(command -v keyd)"
    fi
fi

# ── Step 2: 설정 파일 배포 ────────────────────────────────────────────────────
print_subsep
print_step "[Step 2] keyd 설정 파일 배포"
print_subsep

# /etc/keyd 디렉토리 생성
mkdir -p /etc/keyd

# 배포할 최종 설정을 먼저 임시 파일로 만든 뒤(소스 선택 → fcitx5 유무에 따른 변환) 기존 파일과 비교합니다.
# (변환 전 소스와 비교하면 fcitx5 미설치 환경에서 실행할 때마다 불필요한 백업이 쌓이므로 최종 결과로 비교)
_keyd_tmp=$(mktemp)
trap 'rm -f "$_keyd_tmp"' EXIT

if [ -f "$KEYD_CONF_SRC" ]; then
    print_info "로컬 설정 파일 사용: $KEYD_CONF_SRC"
    cp -f "$KEYD_CONF_SRC" "$_keyd_tmp"
elif curl -sSfL --max-time 5 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "https://raw.githubusercontent.com/devers2/_devtools2/${DT2_REF:-main}/.config/keyd/default.conf" -o "$_keyd_tmp" 2>/dev/null; then
    print_info "GitHub 원격에서 최신 default.conf 다운로드 완료"
else
    # 네트워크 연결 원격 다운로드 및 로컬 소스 모두 없을 때 인라인으로 생성
    # (.config/keyd/default.conf 와 동일한 내용을 유지해야 합니다)
    print_warn "설정 소스를 찾을 수 없어 기본 설정을 인라인으로 생성합니다."
    cat > "$_keyd_tmp" <<'EOF'
[ids]
*

# ------------------------------------------------------------------------------
# [전역 ESC → 영문 전환] Windows AutoHotkey(devtools2-hotkey.ahk)의 _SetImeToEnglish 와 동일한 경험
# - Esc / CapsLock 탭 / Ctrl+[ 를 누르면 원래 키를 보낸 직후 fcitx5 '입력기 비활성화(=영문)' 전용 키
#   Ctrl+Alt+Shift+F11 (keyd 표기 C-A-S-f11) 을 이어서 보냅니다. Neovim 뿐 아니라 Sublime Merge,
#   터미널 등 fcitx5 를 쓰는 모든 앱에서 한글 상태가 영문으로 돌아옵니다.
# - 이 키는 fcitx5 설정(~/.config/fcitx5/config 의 [Hotkey/DeactivateKeys])에 등록되어 있어
#   fcitx5 가 가로채므로 앱에는 전달되지 않습니다(_install-utils.sh 의 ensure_korean_ime 가 기록).
#   Windows(WSLg) 쪽 AHK 와 같은 조합이므로 바꿀 때는 세 곳(keyd, AHK, fcitx5 config)을 함께 바꿔야 합니다.
# - ⚠️ fcitx5 가 없는 환경(ibus 등)에서는 이 키가 앱에 그대로 전달되어 터미널에 이상한 문자가 찍힐 수 있으므로,
#   4.setup-keyboard.sh 가 fcitx5 를 실제 입력기로 쓰지 않으면(미설치, 또는 ibus-hangul 사용) macro(<키> C-A-S-f11) 를 <키> 로 되돌려 배포합니다.
# - keyd 매크로는 길게 눌러도 자동 반복되지 않습니다(Esc 연타 용도에는 영향 없음).
# ------------------------------------------------------------------------------

[main]
# 짧게 누르면 esc, 다른 키와 조합하면 control (keyd overload)
# (탭 시 esc 직후 fcitx5 영문 전환 키도 함께 전송)
capslock = overload(control, macro(esc C-A-S-f11))

# Esc 키 → esc 입력 + fcitx5 영문 전환
esc = macro(esc C-A-S-f11)

# 오른쪽 컨트롤 키를 명시적으로 지정하여 keyd 에서 정확하게 인식할 수 있도록 함
rightcontrol = rightcontrol

[control]
# Vim 표준 Esc 대체키 Ctrl+[ → Ctrl+[ 입력 + fcitx5 영문 전환 (AHK Part 3 과 동일)
# keyd 는 [control] 레이어의 바인딩을 실행할 때 Ctrl 을 잠시 떼고 보내므로 매크로 안에서 C- 를 명시합니다.
leftbrace = macro(C-leftbrace C-A-S-f11)

[shift]
# Shift 키를 누른 상태에서 CapsLock → 대문자 고정 ON (caps 레이어 진입)
# keyd 공식 권장: chord(shift+capslock) 대신 [shift] 레이어로 정의하여 50ms 타이밍 한계 해결
capslock = toggle(caps)

[caps:S]
# 대문자 고정 ON 상태에서:
# CapsLock 또는 ESC 키 → ESC 입력 + 대문자 고정 OFF (AHK(devtools2-hotkey.ahk)의
# CapsLock/ESC 처리와 동일하게 맞춤). toggle(caps)만 쓰면 레이어만 해제되고 실제
# ESC 키 입력은 전송되지 않으므로, 매크로를 먼저 실행한 뒤 토글하는 togglem을 사용합니다.
# (ESC 직후 fcitx5 영문 전환 키도 함께 전송)
capslock = togglem(caps, macro(esc C-A-S-f11))
esc = togglem(caps, macro(esc C-A-S-f11))
EOF
fi

# fcitx5 가 없는 환경(ibus 등)에서는 ESC 계열 키 뒤에 붙는 fcitx5 영문 전환 키(C-A-S-f11)가
# 앱에 그대로 전달되어 터미널에 이상한 문자가 찍힐 수 있으므로 순수 키로 되돌립니다.
#   macro(esc C-A-S-f11) → esc,  macro(C-leftbrace C-A-S-f11) → C-leftbrace
# (나중에 fcitx5 를 설치했다면 이 스크립트를 다시 실행하면 영문 전환 동작이 켜집니다)
# 판단 기준: fcitx5 가 "설치"가 아니라 "실제 사용 중인 입력기"인지 확인합니다.
#   Ubuntu 한국어 설치는 기본으로 ibus-hangul 이 들어 있어, fcitx5 가 설치만 되어 있고 ibus 를 쓰는 경우
#   C-A-S-f11 을 받아 줄 입력기가 없어 터미널에 문자가 찍힐 수 있기 때문입니다.
#   ● fcitx5 설치 + ibus-hangul 미설치 → fcitx5 사용으로 판단
#   ● 둘 다 설치 → im-config 선택(사용자 ~/.xinputrc 또는 시스템 /etc/X11/xinit/xinputrc)이 fcitx5 일 때만
#   (이 스크립트는 sudo 로 실행되므로 사용자 홈은 SUDO_USER 로 찾습니다)
_dt2_pkg_ok() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"; }
_fcitx5_active=false
if _dt2_pkg_ok fcitx5; then
    if ! _dt2_pkg_ok ibus-hangul; then
        _fcitx5_active=true
    else
        _target_home=$(getent passwd "${SUDO_USER:-$(id -un)}" 2>/dev/null | cut -d: -f6)
        for _xinputrc in "${_target_home:-/nonexistent}/.xinputrc" /etc/X11/xinit/xinputrc; do
            if [ -f "$_xinputrc" ]; then
                grep -qE '^[[:space:]]*run_im[[:space:]]+fcitx5' "$_xinputrc" && _fcitx5_active=true
                break
            fi
        done
    fi
fi
if [ "$_fcitx5_active" = true ]; then
    print_info "fcitx5 감지 → Esc / CapsLock 탭 / Ctrl+[ 입력 시 한글 입력기를 영문으로 전환합니다."
else
    sed -i -E 's/macro\(([^ )]+) C-A-S-f11\)/\1/g' "$_keyd_tmp"
    print_info "fcitx5 를 사용하지 않는 환경 → 전역 ESC 영문 전환 없이 기본 키 리매핑만 배포합니다."
fi

# 직접 수정한 기존 설정을 잃지 않도록, 내용이 다른 기존 파일은 덮어쓰기 전에 한 번 백업합니다.
if [ -f "$KEYD_CONF_DEST" ] && ! cmp -s "$_keyd_tmp" "$KEYD_CONF_DEST"; then
    _keyd_bak="${KEYD_CONF_DEST}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$KEYD_CONF_DEST" "$_keyd_bak"
    print_info "기존 keyd 설정을 백업했습니다: $_keyd_bak"
fi

install -m 644 "$_keyd_tmp" "$KEYD_CONF_DEST"
print_success "keyd 설정 파일 배포 완료: $KEYD_CONF_DEST"

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
