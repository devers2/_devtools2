#!/bin/bash

# =================================================================
# DevTools2 CLI 유틸리티 도구 설치 스크립트 (3.install-cli-tools.sh)
# 대상: fzf, lazygit, ripgrep, fd, ast-grep,
#       apt 패키지(build-essential, libreadline-dev, git, trash-cli),
#       hererocks (Lua/Neovim 플러그인 관리용)
# 참고: 바자이트(불변 OS) 환경에서 distrobox 컨테이너를 통해 설치하던
#       apt 패키지 및 hererocks 설치를 이 스크립트로 통합하였습니다.
#       우분투 / WSL2 환경에서는 직접 apt 를 사용하므로 컨테이너가 불필요합니다.
# =================================================================

# ARCH/IS_ARM64/IS_WSL2 는 _install-utils.sh 에서 로드됨 (아래 _load_install_utils 참고)

if [ -z "${DEVTOOLS2:-}" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")
fi

# 유효한 DEVTOOLS2 폴더가 아니면 표준 경로를 기본값으로 사용
if [ ! -f "$DEVTOOLS2/scripts/linux/dev-env/3.install-cli-tools.sh" ]; then
    DEVTOOLS2="/var/opt/_devtools2"
fi

# 공통 색상/스피너 헬퍼 로드 (온라인 전용)
_load_colors() {
    [ -n "${_COLORS_LOADED:-}" ] && return 0

    # 캐시 우회 헤더 포함 (run_remote_script와 동일) — CDN이 방금 푸시 전 구버전을
    # 서빙하면 "진입 스크립트는 최신인데 _colors.sh만 구버전"이 될 수 있으므로 필수.
    # curl의 실제 실패 사유(stderr)를 버리지 않고 그대로 보여줘야 나중에 원인 진단이 가능하다.
    # 고정된 /tmp/_colors_remote.sh 경로를 쓰면, 이 스크립트를 실행하는 사용자가 바뀔 때
    # (예: 0.init은 root로, 1.setup-env는 일반 사용자로) /tmp의 sticky bit 때문에 이전
    # 실행자가 만든 파일을 지금 사용자가 덮어쓰지 못해 curl이 쓰기 실패(exit 23)한다
    # (실측으로 재현 확인). mktemp로 매번 고유한 파일을 만들어 이 충돌을 없앤다.
    local _tmpfile _curl_err _curl_ec=0
    _tmpfile=$(mktemp) || { echo "[오류] 임시 파일 생성에 실패했습니다." >&2; exit 1; }
    _curl_err=$(curl -sSfL --max-time 5 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env/_colors.sh" -o "$_tmpfile" 2>&1) || _curl_ec=$?
    if [ "$_curl_ec" -eq 0 ]; then
        # shellcheck disable=SC1090
        if source "$_tmpfile" 2>/dev/null; then
            rm -f "$_tmpfile"
            _COLORS_LOADED=true
            return 0
        fi
        rm -f "$_tmpfile"
        echo "[오류] _colors.sh를 다운로드했지만 source 실행 중 오류가 발생했습니다." >&2
        exit 1
    fi

    rm -f "$_tmpfile"
    echo "[오류] _colors.sh를 온라인에서 불러오지 못했습니다 (curl 종료 코드: $_curl_ec)." >&2
    [ -n "$_curl_err" ] && echo "  curl: $_curl_err" >&2
    echo "  네트워크 연결을 확인하세요." >&2
    exit 1
}
_load_colors

# 공통 설치 유틸리티 로드 (ARCH/IS_ARM64/IS_WSL2 감지, _ensure_pkg, TOML 버전 관리,
# _resolve_action, _fmts 등 — 2.install-core-tools.sh 와 공유)
_load_install_utils() {
    [ -n "${_INSTALL_UTILS_LOADED:-}" ] && return 0

    # 온라인 전용, 캐시 우회 헤더 및 mktemp 이유는 _load_colors 주석 참고.
    # TOOL_VERSIONS_TOML 등은 인라인 대체가 불가능해서 실패하면 바로 하드 실패한다.
    local _tmpfile _curl_err _curl_ec=0
    _tmpfile=$(mktemp) || { print_error "임시 파일 생성에 실패했습니다."; exit 1; }
    _curl_err=$(curl -sSfL --max-time 5 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env/_install-utils.sh" -o "$_tmpfile" 2>&1) || _curl_ec=$?
    if [ "$_curl_ec" -eq 0 ]; then
        # shellcheck disable=SC1090
        if source "$_tmpfile" 2>/dev/null; then
            rm -f "$_tmpfile"
            _INSTALL_UTILS_LOADED=true
            return 0
        fi
        rm -f "$_tmpfile"
        print_error "_install-utils.sh를 다운로드했지만 source 실행 중 오류가 발생했습니다."
        exit 1
    fi

    rm -f "$_tmpfile"
    print_error "_install-utils.sh를 온라인에서 불러오지 못했습니다 (curl 종료 코드: $_curl_ec)."
    [ -n "$_curl_err" ] && print_error "  curl: $_curl_err"
    print_error "  네트워크 연결을 확인하세요."
    exit 1
}
_load_install_utils

# DEVTOOLS2 기본 폴더 및 필수 서브 디렉토리 존재/권한 확보
if [ ! -d "$DEVTOOLS2" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        mkdir -p "$DEVTOOLS2"
    else
        sudo mkdir -p "$DEVTOOLS2" 2>/dev/null || mkdir -p "$DEVTOOLS2" 2>/dev/null || true
        sudo chown -R "$USER" "$DEVTOOLS2" 2>/dev/null || true
    fi
fi
if [ ! -w "$DEVTOOLS2" ] && [ "$(id -u)" -ne 0 ]; then
    sudo chown -R "$USER" "$DEVTOOLS2" 2>/dev/null || true
    sudo chmod -R u+w "$DEVTOOLS2" 2>/dev/null || true
fi

# _ensure_pkg() 는 _install-utils.sh 에서 로드됨 (2.install-core-tools.sh 와 공유)
_ensure_pkg unzip
_ensure_pkg tar
_ensure_pkg curl
_ensure_pkg wget

# 바이너리가 설치될 modules 디렉토리 경로 설정
MODULES_DIR="$DEVTOOLS2/modules"

# 경로 생성
# 각 도구별로 독립된 폴더를 생성하여 관리를 용이하게 합니다.
mkdir -p "$MODULES_DIR/fzf" "$MODULES_DIR/lazygit" "$MODULES_DIR/ripgrep" "$MODULES_DIR/fd" "$MODULES_DIR/ast-grep" "$MODULES_DIR/bitwarden" "$MODULES_DIR/rclone"

# rclone 구성 파일 디렉터리 사전 확보 ($DEVTOOLS2/modules/rclone/.config — git 미추적 영역)
mkdir -p "$MODULES_DIR/rclone/.config"
if [ -d "$DEVTOOLS2/.config/rclone" ]; then
    if [ -f "$DEVTOOLS2/.config/rclone/rclone.conf" ]; then
        mv -f "$DEVTOOLS2/.config/rclone/rclone.conf" "$MODULES_DIR/rclone/.config/rclone.conf" 2>/dev/null || true
    fi
    rm -rf "$DEVTOOLS2/.config/rclone" 2>/dev/null || true
fi

# TOOL_VERSIONS_TOML/_read_toml/get_pinned_version/update_pinned_version/fetch_latest_github 는
# _install-utils.sh 에서 로드됨 (2.install-core-tools.sh 와 공유)

# Bitwarden CLI 최신 릴리즈 버전을 반환합니다 (cli-v 태그만 필터링). 이 스크립트 전용이라 공유 안 함.
fetch_latest_bitwarden_cli() {
    curl -sf --max-time 10 \
        "https://api.github.com/repos/bitwarden/clients/releases" \
        2>/dev/null \
        | grep '"tag_name"' | grep 'cli-v' | head -1 \
        | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
        | sed 's/^cli-v//' || true
}

# show_spinner 는 _colors.sh 에서 로드됨

# ─────────────────────────────────────────────────────────────────
# ⚙️  PRE-FLIGHT: 설치 방식 선택 (CLI 도구 8종)
# ─────────────────────────────────────────────────────────────────

# 최종 설치 버전 읽기
FZF_PINNED=$(get_pinned_version "fzf")
LAZYGIT_PINNED=$(get_pinned_version "lazygit")
RIPGREP_PINNED=$(get_pinned_version "ripgrep")
FD_PINNED=$(get_pinned_version "fd")
ASTGREP_PINNED=$(get_pinned_version "ast_grep")
BITWARDEN_ARM_PINNED=$(get_pinned_version "bitwarden_arm")
WIN32YANK_PINNED=$(get_pinned_version "win32yank")
RCLONE_PINNED=$(get_pinned_version "rclone")

# 설치 상태 확인
FZF_INSTALLED=false;      [ -f "$MODULES_DIR/fzf/fzf" ]           && FZF_INSTALLED=true
LAZYGIT_INSTALLED=false;  [ -f "$MODULES_DIR/lazygit/lazygit" ]    && LAZYGIT_INSTALLED=true
RIPGREP_INSTALLED=false;  [ -f "$MODULES_DIR/ripgrep/rg" ]         && RIPGREP_INSTALLED=true
FD_INSTALLED=false;       [ -f "$MODULES_DIR/fd/fd" ]              && FD_INSTALLED=true
ASTGREP_INSTALLED=false;  { [ -f "$MODULES_DIR/ast-grep/sg" ] || [ -f "$MODULES_DIR/ast-grep/ast-grep" ]; } && ASTGREP_INSTALLED=true
BITWARDEN_INSTALLED=false;[ -f "$MODULES_DIR/bitwarden/bw" ]       && BITWARDEN_INSTALLED=true
RCLONE_INSTALLED=false;   [ -f "$MODULES_DIR/rclone/rclone" ]      && RCLONE_INSTALLED=true
WIN32YANK_INSTALLED=false
[ "$IS_WSL2" = true ] && [ -f "$MODULES_DIR/win32yank/win32yank.exe" ] && WIN32YANK_INSTALLED=true

# 설치에 사용할 실제 버전 초기화 (기본: 최종 설치 버전)
FZF_VERSION="$FZF_PINNED"
LAZYGIT_VERSION="$LAZYGIT_PINNED"
RIPGREP_VERSION="$RIPGREP_PINNED"
FD_VERSION="$FD_PINNED"
ASTGREP_VERSION="$ASTGREP_PINNED"
BITWARDEN_ARM_VERSION="$BITWARDEN_ARM_PINNED"
WIN32YANK_VERSION="$WIN32YANK_PINNED"
RCLONE_VERSION="$RCLONE_PINNED"

# 상태 포매팅 헬퍼(_fmts)는 _install-utils.sh 에서 로드됨

echo ""
print_sep
print_step "🚀 도구 설치를 시작합니다..."
print_info "📍 최상위 경로: $DEVTOOLS2"
print_info "📍 설치 폴더: $MODULES_DIR"
if [ "$IS_WSL2" = true ]; then print_info "📍 환경: WSL2 감지됨"; fi
echo ""
echo "📋 버전 관리 대상 도구 현황"
echo ""
printf "   %-16s  최종 설치 버전: %-12s  %s\n" "fzf"           "$FZF_PINNED"     "$(_fmts "$FZF_INSTALLED")"
printf "   %-16s  최종 설치 버전: %-12s  %s\n" "lazygit"        "$LAZYGIT_PINNED" "$(_fmts "$LAZYGIT_INSTALLED")"
printf "   %-16s  최종 설치 버전: %-12s  %s\n" "ripgrep"        "$RIPGREP_PINNED" "$(_fmts "$RIPGREP_INSTALLED")"
printf "   %-16s  최종 설치 버전: %-12s  %s\n" "fd-find"        "$FD_PINNED"      "$(_fmts "$FD_INSTALLED")"
printf "   %-16s  최종 설치 버전: %-12s  %s\n" "ast-grep"       "$ASTGREP_PINNED" "$(_fmts "$ASTGREP_INSTALLED")"
printf "   %-16s  최종 설치 버전: %-12s  %s\n" "rclone"         "$RCLONE_PINNED"  "$(_fmts "$RCLONE_INSTALLED")"
if [ "$IS_ARM64" = true ]; then
    printf "   %-16s  최종 설치 버전: %-12s  %s\n" "bitwarden-cli" "$BITWARDEN_ARM_PINNED" "$(_fmts "$BITWARDEN_INSTALLED")"
else
    printf "   %-16s  %-28s  %s\n" "bitwarden-cli" "(직접 다운로드 - 항상 최신)" "$(_fmts "$BITWARDEN_INSTALLED")"
fi
if [ "$IS_WSL2" = true ]; then
    printf "   %-16s  최종 설치 버전: %-12s  %s\n" "win32yank" "$WIN32YANK_PINNED" "$(_fmts "$WIN32YANK_INSTALLED")"
fi
echo ""

# ── 중복 처리 방식 선택 ──────────────────────────────────────────
DUPLICATE_MODE="keep"
_HAS_INSTALLED=false
for _b in "$FZF_INSTALLED" "$LAZYGIT_INSTALLED" "$RIPGREP_INSTALLED" \
           "$FD_INSTALLED" "$ASTGREP_INSTALLED" "$BITWARDEN_INSTALLED" "$RCLONE_INSTALLED" "$WIN32YANK_INSTALLED"; do
    [ "$_b" = true ] && _HAS_INSTALLED=true && break
done

if [ "$_HAS_INSTALLED" = true ]; then
    print_question "⚠️  이미 설치된 도구가 감지되었습니다. 중복 처리 방식을 선택하세요:"
    echo ""
    print_option "1" "기존 도구 삭제 후 재설치 (덮어쓰기)"
    print_option "2" "기존 도구 유지 (건너뛰기)" "[기본값]"
    print_option "3" "도구별 개별 확인 (재설치/건너뛰기 선택)"
    echo ""
    prompt_input "   선택 [1/${_C_DEFAULT}2${_C_RESET}/3]: "; read -r _dup_choice
    echo ""
    case "${_dup_choice:-2}" in
        1) DUPLICATE_MODE="remove"     ; print_info "중복 처리: 묻지 않고 삭제 후 재설치 선택됨" ;;
        3) DUPLICATE_MODE="individual" ; print_info "중복 처리: 도구별 개별 확인 선택됨" ;;
        *) DUPLICATE_MODE="keep"       ; print_info "중복 처리: 기존 도구 유지(건너뛰기) 선택됨" ;;
    esac
    echo ""
fi

# ── 버전 설치 방식 선택 ──────────────────────────────────────────
# _select_version_mode() 는 _install-utils.sh 에서 로드됨 (2.install-core-tools.sh 와 공유)
_select_version_mode

# 일괄 최신 버전 모드: 미리 모든 최신 버전 일괄 조회
if [ "$VERSION_MODE" = "latest" ]; then
    echo ""
    echo "   🔍 최신 버전 조회 중 (GitHub API)..."

    _v=$(fetch_latest_github "junegunn/fzf" | sed 's/^v//')
    if [ -n "$_v" ]; then
        FZF_VERSION="$_v"
        echo "   ✓ fzf:          최신 → $_v  (최종 설치: $FZF_PINNED)"
    else
        echo "   ⚠️  fzf:         조회 실패 → 최종 설치 버전 사용: $FZF_PINNED"
    fi

    _v=$(fetch_latest_github "jesseduffield/lazygit" | sed 's/^v//')
    if [ -n "$_v" ]; then
        LAZYGIT_VERSION="$_v"
        echo "   ✓ lazygit:      최신 → $_v  (최종 설치: $LAZYGIT_PINNED)"
    else
        echo "   ⚠️  lazygit:     조회 실패 → 최종 설치 버전 사용: $LAZYGIT_PINNED"
    fi

    _v=$(fetch_latest_github "BurntSushi/ripgrep")
    if [ -n "$_v" ]; then
        RIPGREP_VERSION="$_v"
        echo "   ✓ ripgrep:      최신 → $_v  (최종 설치: $RIPGREP_PINNED)"
    else
        echo "   ⚠️  ripgrep:     조회 실패 → 최종 설치 버전 사용: $RIPGREP_PINNED"
    fi

    _v=$(fetch_latest_github "sharkdp/fd" | sed 's/^v//')
    if [ -n "$_v" ]; then
        FD_VERSION="$_v"
        echo "   ✓ fd-find:      최신 → $_v  (최종 설치: $FD_PINNED)"
    else
        echo "   ⚠️  fd-find:     조회 실패 → 최종 설치 버전 사용: $FD_PINNED"
    fi

    _v=$(fetch_latest_github "ast-grep/ast-grep" | sed 's/^v//')
    if [ -n "$_v" ]; then
        ASTGREP_VERSION="$_v"
        echo "   ✓ ast-grep:     최신 → $_v  (최종 설치: $ASTGREP_PINNED)"
    else
        echo "   ⚠️  ast-grep:    조회 실패 → 최종 설치 버전 사용: $ASTGREP_PINNED"
    fi

    _v=$(fetch_latest_github "rclone/rclone" | sed 's/^v//')
    if [ -n "$_v" ]; then
        RCLONE_VERSION="$_v"
        echo "   ✓ rclone:       최신 → $_v  (최종 설치: $RCLONE_PINNED)"
    else
        echo "   ⚠️  rclone:      조회 실패 → 최종 설치 버전 사용: $RCLONE_PINNED"
    fi

    # bitwarden: ARM64만 버전 관리 (x86_64는 항상 최신 직접 다운로드)
    if [ "$IS_ARM64" = true ]; then
        _v=$(fetch_latest_bitwarden_cli)
        if [ -n "$_v" ]; then
            BITWARDEN_ARM_VERSION="$_v"
            echo "   ✓ bitwarden-cli (ARM64): 최신 → $_v  (최종 설치: $BITWARDEN_ARM_PINNED)"
        else
            echo "   ⚠️  bitwarden-cli: 조회 실패 → 최종 설치 버전 사용: $BITWARDEN_ARM_PINNED"
        fi
    fi

    if [ "$IS_WSL2" = true ]; then
        _v=$(fetch_latest_github "equalsraf/win32yank" | sed 's/^v//')
        if [ -n "$_v" ]; then
            WIN32YANK_VERSION="$_v"
            echo "   ✓ win32yank:    최신 → $_v  (최종 설치: $WIN32YANK_PINNED)"
        else
            echo "   ⚠️  win32yank:   조회 실패 → 최종 설치 버전 사용: $WIN32YANK_PINNED"
        fi
    fi

    echo ""
fi

print_sep
echo ""

# _resolve_action() 은 _install-utils.sh 에서 로드됨 (2.install-core-tools.sh 와 공유)

# ─────────────────────────────────────────────────────────────────
# 1. fzf 설치 - 터미널용 퍼지 파인더 (목록 검색 도구)
# ─────────────────────────────────────────────────────────────────

# 개별 선택 모드: fzf 버전 결정
if [ "$VERSION_MODE" = "individual" ]; then
    echo -n "   🔍 fzf 최신 버전 조회 중... "
    _fzf_latest=$(fetch_latest_github "junegunn/fzf" | sed 's/^v//')
    [ -n "$_fzf_latest" ] && echo "완료 ($_fzf_latest)" || echo "실패"
    echo ""
    echo "   fzf 설치 버전 선택:"
    echo "   1) 최신 버전: ${_fzf_latest:-[조회 실패 - 선택 불가]}"
    echo "   2) 최종 설치 버전: $FZF_PINNED [기본값]"
    echo ""
    prompt_input "   선택 [1/${_C_DEFAULT}2${_C_RESET}]: "; read -r _fzf_vs
    case "${_fzf_vs:-2}" in
        1) [ -n "$_fzf_latest" ] && FZF_VERSION="$_fzf_latest" || FZF_VERSION="$FZF_PINNED" ;;
        *) FZF_VERSION="$FZF_PINNED" ;;
    esac
    echo ""
fi

_fzf_action=$(_resolve_action "$FZF_INSTALLED" "fzf")

echo -n "📦 fzf $FZF_VERSION 설치 중..."
if [ "$_fzf_action" = "skip" ]; then
    echo " ⏭️  [건너뜀] 이미 설치되어 있습니다."
else
    if [ "$_fzf_action" = "reinstall" ]; then
        rm -f "$MODULES_DIR/fzf/fzf"
    fi
    if [ "$IS_ARM64" = true ]; then
        _fzf_url="https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_arm64.tar.gz"
    else
        _fzf_url="https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_amd64.tar.gz"
    fi
    curl -sL "$_fzf_url" | tar xz -C "$MODULES_DIR/fzf" &
    show_spinner $!
    echo " 완료"
    if [ "$FZF_VERSION" != "$FZF_PINNED" ]; then
        update_pinned_version "fzf" "$FZF_VERSION"
    fi
fi

# ─────────────────────────────────────────────────────────────────
# 2. lazygit 설치 - 터미널 UI 기반 Git 관리 도구
# ─────────────────────────────────────────────────────────────────

# 개별 선택 모드: lazygit 버전 결정
if [ "$VERSION_MODE" = "individual" ]; then
    echo -n "   🔍 lazygit 최신 버전 조회 중... "
    _lg_latest=$(fetch_latest_github "jesseduffield/lazygit" | sed 's/^v//')
    [ -n "$_lg_latest" ] && echo "완료 ($_lg_latest)" || echo "실패"
    echo ""
    echo "   lazygit 설치 버전 선택:"
    echo "   1) 최신 버전: ${_lg_latest:-[조회 실패 - 선택 불가]}"
    echo "   2) 최종 설치 버전: $LAZYGIT_PINNED [기본값]"
    echo ""
    prompt_input "   선택 [1/${_C_DEFAULT}2${_C_RESET}]: "; read -r _lg_vs
    case "${_lg_vs:-2}" in
        1) [ -n "$_lg_latest" ] && LAZYGIT_VERSION="$_lg_latest" || LAZYGIT_VERSION="$LAZYGIT_PINNED" ;;
        *) LAZYGIT_VERSION="$LAZYGIT_PINNED" ;;
    esac
    echo ""
fi

_lg_action=$(_resolve_action "$LAZYGIT_INSTALLED" "lazygit")

echo -n "📦 lazygit $LAZYGIT_VERSION 설치 중..."
if [ "$_lg_action" = "skip" ]; then
    echo " ⏭️  [건너뜀] 이미 설치되어 있습니다."
else
    if [ "$_lg_action" = "reinstall" ]; then
        rm -f "$MODULES_DIR/lazygit/lazygit"
    fi
    if [ "$IS_ARM64" = true ]; then
        _lg_url="https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_arm64.tar.gz"
    else
        _lg_url="https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    fi
    curl -sL "$_lg_url" | tar xz -C "$MODULES_DIR/lazygit" &
    show_spinner $!
    echo " 완료"
    if [ "$LAZYGIT_VERSION" != "$LAZYGIT_PINNED" ]; then
        update_pinned_version "lazygit" "$LAZYGIT_VERSION"
    fi
fi

# ─────────────────────────────────────────────────────────────────
# 3. ripgrep (rg) 설치 - 코드 내 문자열 초고속 검색 도구
# ─────────────────────────────────────────────────────────────────

# 개별 선택 모드: ripgrep 버전 결정
if [ "$VERSION_MODE" = "individual" ]; then
    echo -n "   🔍 ripgrep 최신 버전 조회 중... "
    _rg_latest=$(fetch_latest_github "BurntSushi/ripgrep")
    [ -n "$_rg_latest" ] && echo "완료 ($_rg_latest)" || echo "실패"
    echo ""
    echo "   ripgrep 설치 버전 선택:"
    echo "   1) 최신 버전: ${_rg_latest:-[조회 실패 - 선택 불가]}"
    echo "   2) 최종 설치 버전: $RIPGREP_PINNED [기본값]"
    echo ""
    prompt_input "   선택 [1/${_C_DEFAULT}2${_C_RESET}]: "; read -r _rg_vs
    case "${_rg_vs:-2}" in
        1) [ -n "$_rg_latest" ] && RIPGREP_VERSION="$_rg_latest" || RIPGREP_VERSION="$RIPGREP_PINNED" ;;
        *) RIPGREP_VERSION="$RIPGREP_PINNED" ;;
    esac
    echo ""
fi

_rg_action=$(_resolve_action "$RIPGREP_INSTALLED" "ripgrep")

echo -n "📦 ripgrep $RIPGREP_VERSION 설치 중..."
if [ "$_rg_action" = "skip" ]; then
    echo " ⏭️  [건너뜀] 이미 설치되어 있습니다."
else
    if [ "$_rg_action" = "reinstall" ]; then
        rm -f "$MODULES_DIR/ripgrep/rg"
    fi
    if [ "$IS_ARM64" = true ]; then
        _rg_url="https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-aarch64-unknown-linux-gnu.tar.gz"
    else
        _rg_url="https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl.tar.gz"
    fi
    curl -sL "$_rg_url" | tar xz -C "$MODULES_DIR/ripgrep" --strip-components=1 &
    show_spinner $!
    echo " 완료"
    if [ "$RIPGREP_VERSION" != "$RIPGREP_PINNED" ]; then
        update_pinned_version "ripgrep" "$RIPGREP_VERSION"
    fi
fi

# ─────────────────────────────────────────────────────────────────
# 4. fd-find (fd) 설치 - 파일 이름 초고속 검색 도구 (find 대용)
# ─────────────────────────────────────────────────────────────────

# 개별 선택 모드: fd 버전 결정
if [ "$VERSION_MODE" = "individual" ]; then
    echo -n "   🔍 fd-find 최신 버전 조회 중... "
    _fd_latest=$(fetch_latest_github "sharkdp/fd" | sed 's/^v//')
    [ -n "$_fd_latest" ] && echo "완료 ($_fd_latest)" || echo "실패"
    echo ""
    echo "   fd-find 설치 버전 선택:"
    echo "   1) 최신 버전: ${_fd_latest:-[조회 실패 - 선택 불가]}"
    echo "   2) 최종 설치 버전: $FD_PINNED [기본값]"
    echo ""
    prompt_input "   선택 [1/${_C_DEFAULT}2${_C_RESET}]: "; read -r _fd_vs
    case "${_fd_vs:-2}" in
        1) [ -n "$_fd_latest" ] && FD_VERSION="$_fd_latest" || FD_VERSION="$FD_PINNED" ;;
        *) FD_VERSION="$FD_PINNED" ;;
    esac
    echo ""
fi

_fd_action=$(_resolve_action "$FD_INSTALLED" "fd-find")

echo -n "📦 fd-find $FD_VERSION 설치 중..."
if [ "$_fd_action" = "skip" ]; then
    echo " ⏭️  [건너뜀] 이미 설치되어 있습니다."
else
    if [ "$_fd_action" = "reinstall" ]; then
        rm -f "$MODULES_DIR/fd/fd"
    fi
    if [ "$IS_ARM64" = true ]; then
        _fd_url="https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-v${FD_VERSION}-aarch64-unknown-linux-musl.tar.gz"
    else
        _fd_url="https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-v${FD_VERSION}-x86_64-unknown-linux-musl.tar.gz"
    fi
    curl -sL "$_fd_url" | tar xz -C "$MODULES_DIR/fd" --strip-components=1 &
    show_spinner $!
    echo " 완료"
    if [ "$FD_VERSION" != "$FD_PINNED" ]; then
        update_pinned_version "fd" "$FD_VERSION"
    fi
fi

# ─────────────────────────────────────────────────────────────────
# 5. ast-grep (sg) 설치 - 추상 구문 트리(AST) 기반의 구조적 코드 검색 도구
# ─────────────────────────────────────────────────────────────────

# 개별 선택 모드: ast-grep 버전 결정
if [ "$VERSION_MODE" = "individual" ]; then
    echo -n "   🔍 ast-grep 최신 버전 조회 중... "
    _sg_latest=$(fetch_latest_github "ast-grep/ast-grep" | sed 's/^v//')
    [ -n "$_sg_latest" ] && echo "완료 ($_sg_latest)" || echo "실패"
    echo ""
    echo "   ast-grep 설치 버전 선택:"
    echo "   1) 최신 버전: ${_sg_latest:-[조회 실패 - 선택 불가]}"
    echo "   2) 최종 설치 버전: $ASTGREP_PINNED [기본값]"
    echo ""
    prompt_input "   선택 [1/${_C_DEFAULT}2${_C_RESET}]: "; read -r _sg_vs
    case "${_sg_vs:-2}" in
        1) [ -n "$_sg_latest" ] && ASTGREP_VERSION="$_sg_latest" || ASTGREP_VERSION="$ASTGREP_PINNED" ;;
        *) ASTGREP_VERSION="$ASTGREP_PINNED" ;;
    esac
    echo ""
fi

_sg_action=$(_resolve_action "$ASTGREP_INSTALLED" "ast-grep")

echo -n "📦 ast-grep $ASTGREP_VERSION 설치 중..."
if [ "$_sg_action" = "skip" ]; then
    echo " ⏭️  [건너뜀] 이미 설치되어 있습니다."
else
    if [ "$_sg_action" = "reinstall" ]; then
        rm -f "$MODULES_DIR/ast-grep/sg" "$MODULES_DIR/ast-grep/ast-grep"
    fi
    # ast-grep 태그 형식: ${ASTGREP_VERSION} (v 없음), 에셋 파일명: app-{arch}-unknown-linux-gnu.zip
    if [ "$IS_ARM64" = true ]; then
        _sg_url="https://github.com/ast-grep/ast-grep/releases/download/${ASTGREP_VERSION}/app-aarch64-unknown-linux-gnu.zip"
    else
        _sg_url="https://github.com/ast-grep/ast-grep/releases/download/${ASTGREP_VERSION}/app-x86_64-unknown-linux-gnu.zip"
    fi
    (curl -sLf "$_sg_url" -o /tmp/ast-grep.zip && unzip -qo /tmp/ast-grep.zip -d "$MODULES_DIR/ast-grep" && (cd "$MODULES_DIR/ast-grep" && ([ -f ast-grep ] && [ ! -f sg ] && ln -sf ast-grep sg || true) && ([ -f sg ] && [ ! -f ast-grep ] && ln -sf sg ast-grep || true)) && rm -f /tmp/ast-grep.zip) &
    show_spinner $!
    echo " 완료"
    if [ "$ASTGREP_VERSION" != "$ASTGREP_PINNED" ]; then
        update_pinned_version "ast_grep" "$ASTGREP_VERSION"
    fi
fi

# ─────────────────────────────────────────────────────────────────
# 6. Bitwarden CLI (bw) 설치 - 안전한 서버 로그인 연동 및 패스워드 매니저 CLI
# ─────────────────────────────────────────────────────────────────

# 개별 선택 모드: bitwarden 버전 결정 (ARM64만 해당)
if [ "$VERSION_MODE" = "individual" ] && [ "$IS_ARM64" = true ]; then
    echo -n "   🔍 Bitwarden CLI 최신 버전 조회 중... "
    _bw_latest=$(fetch_latest_bitwarden_cli)
    [ -n "$_bw_latest" ] && echo "완료 ($_bw_latest)" || echo "실패"
    echo ""
    echo "   Bitwarden CLI 설치 버전 선택 (ARM64):"
    echo "   1) 최신 버전: ${_bw_latest:-[조회 실패 - 선택 불가]}"
    echo "   2) 최종 설치 버전: $BITWARDEN_ARM_PINNED [기본값]"
    echo ""
    prompt_input "   선택 [1/${_C_DEFAULT}2${_C_RESET}]: "; read -r _bw_vs
    case "${_bw_vs:-2}" in
        1) [ -n "$_bw_latest" ] && BITWARDEN_ARM_VERSION="$_bw_latest" || BITWARDEN_ARM_VERSION="$BITWARDEN_ARM_PINNED" ;;
        *) BITWARDEN_ARM_VERSION="$BITWARDEN_ARM_PINNED" ;;
    esac
    echo ""
fi

_bw_action=$(_resolve_action "$BITWARDEN_INSTALLED" "Bitwarden CLI")

echo -n "📦 Bitwarden CLI 설치 중..."
if [ "$_bw_action" = "skip" ]; then
    echo " ⏭️  [건너뜀] 이미 설치되어 있습니다."
else
    if [ "$_bw_action" = "reinstall" ]; then
        rm -f "$MODULES_DIR/bitwarden/bw"
    fi
    if [ "$IS_ARM64" = true ]; then
        # ARM64용은 GitHub 클라이언트 릴리즈 주소를 직접 이용
        _bw_url="https://github.com/bitwarden/clients/releases/download/cli-v${BITWARDEN_ARM_VERSION}/bw-linux-${BITWARDEN_ARM_VERSION}.zip"
        if [ "$BITWARDEN_ARM_VERSION" != "$BITWARDEN_ARM_PINNED" ]; then
            update_pinned_version "bitwarden_arm" "$BITWARDEN_ARM_VERSION"
        fi
    else
        # x86_64용 공식 다이렉트 다운로드 주소 (항상 최신)
        _bw_url="https://vault.bitwarden.com/download/?app=cli&platform=linux"
    fi
    (curl -sL "$_bw_url" -o /tmp/bw.zip && unzip -qo /tmp/bw.zip -d "$MODULES_DIR/bitwarden" && rm -f /tmp/bw.zip) &
    show_spinner $!
    echo " 완료"
fi

# ─────────────────────────────────────────────────────────────────
# 7. rclone 설치 - 클라우드 스토리지 동기화 도구
# ─────────────────────────────────────────────────────────────────

# 개별 선택 모드: rclone 버전 결정
if [ "$VERSION_MODE" = "individual" ]; then
    echo -n "   🔍 rclone 최신 버전 조회 중... "
    _rc_latest=$(fetch_latest_github "rclone/rclone" | sed 's/^v//')
    [ -n "$_rc_latest" ] && echo "완료 ($_rc_latest)" || echo "실패"
    echo ""
    echo "   rclone 설치 버전 선택:"
    echo "   1) 최신 버전: ${_rc_latest:-[조회 실패 - 선택 불가]}"
    echo "   2) 최종 설치 버전: $RCLONE_PINNED [기본값]"
    echo ""
    prompt_input "   선택 [1/${_C_DEFAULT}2${_C_RESET}]: "; read -r _rc_vs
    case "${_rc_vs:-2}" in
        1) [ -n "$_rc_latest" ] && RCLONE_VERSION="$_rc_latest" || RCLONE_VERSION="$RCLONE_PINNED" ;;
        *) RCLONE_VERSION="$RCLONE_PINNED" ;;
    esac
    echo ""
fi

_rc_action=$(_resolve_action "$RCLONE_INSTALLED" "rclone")

echo -n "📦 rclone $RCLONE_VERSION 설치 중..."
if [ "$_rc_action" = "skip" ]; then
    echo " ⏭️  [건너뜀] 이미 설치되어 있습니다."
else
    if [ "$_rc_action" = "reinstall" ]; then
        rm -f "$MODULES_DIR/rclone/rclone"
    fi
    mkdir -p "$MODULES_DIR/rclone"
    if [ "$IS_ARM64" = true ]; then
        _rc_url="https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-arm64.zip"
    else
        _rc_url="https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-amd64.zip"
    fi
    (curl -sL "$_rc_url" -o /tmp/rclone.zip && \
     unzip -qo /tmp/rclone.zip -d /tmp/rclone_tmp && \
     mv -f /tmp/rclone_tmp/rclone-*/rclone "$MODULES_DIR/rclone/rclone" && \
     rm -rf /tmp/rclone.zip /tmp/rclone_tmp) &
    show_spinner $!
    echo " 완료"
    if [ "$RCLONE_VERSION" != "$RCLONE_PINNED" ]; then
        update_pinned_version "rclone" "$RCLONE_VERSION"
    fi
fi

# rclone 구성 파일 디렉터리 보장 ($DEVTOOLS2/modules/rclone/.config — git 미추적 영역)
mkdir -p "$MODULES_DIR/rclone/.config"

# ─────────────────────────────────────────────────────────────────
# 8. (WSL2 전용) win32yank 설치 (Neovim의 Windows 클립보드 공유 용도)
# ─────────────────────────────────────────────────────────────────
if [ "$IS_WSL2" = true ]; then
    # 개별 선택 모드: win32yank 버전 결정
    if [ "$VERSION_MODE" = "individual" ]; then
        echo -n "   🔍 win32yank 최신 버전 조회 중... "
        _wy_latest=$(fetch_latest_github "equalsraf/win32yank" | sed 's/^v//')
        [ -n "$_wy_latest" ] && echo "완료 ($_wy_latest)" || echo "실패"
        echo ""
        echo "   win32yank 설치 버전 선택:"
        echo "   1) 최신 버전: ${_wy_latest:-[조회 실패 - 선택 불가]}"
        echo "   2) 최종 설치 버전: $WIN32YANK_PINNED [기본값]"
        echo ""
        prompt_input "   선택 [1/${_C_DEFAULT}2${_C_RESET}]: "; read -r _wy_vs
        case "${_wy_vs:-2}" in
            1) [ -n "$_wy_latest" ] && WIN32YANK_VERSION="$_wy_latest" || WIN32YANK_VERSION="$WIN32YANK_PINNED" ;;
            *) WIN32YANK_VERSION="$WIN32YANK_PINNED" ;;
        esac
        echo ""
    fi

    _wy_action=$(_resolve_action "$WIN32YANK_INSTALLED" "win32yank")

    echo -n "📦 (WSL2) win32yank $WIN32YANK_VERSION 설치 중..."
    if [ "$_wy_action" = "skip" ]; then
        echo " ⏭️  [건너뜀] 이미 설치되어 있습니다."
    else
        if [ "$_wy_action" = "reinstall" ]; then
            rm -f "$MODULES_DIR/win32yank/win32yank.exe"
        fi
        mkdir -p "$MODULES_DIR/win32yank"
        (curl -sL "https://github.com/equalsraf/win32yank/releases/download/v${WIN32YANK_VERSION}/win32yank-x64.zip" -o /tmp/win32yank.zip && \
         unzip -qo /tmp/win32yank.zip -d /tmp/win32yank_tmp && \
         mv -f /tmp/win32yank_tmp/win32yank.exe "$MODULES_DIR/win32yank/win32yank.exe" && \
         chmod +x "$MODULES_DIR/win32yank/win32yank.exe" && \
         rm -rf /tmp/win32yank.zip /tmp/win32yank_tmp) &
        show_spinner $!
        echo " 완료"
        if [ "$WIN32YANK_VERSION" != "$WIN32YANK_PINNED" ]; then
            update_pinned_version "win32yank" "$WIN32YANK_VERSION"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────
# 실행 권한 부여 및 검증
# ─────────────────────────────────────────────────────────────────
echo "🔐 실행 권한 부여 및 검증 중..."
for cmd in "$MODULES_DIR/ripgrep/rg" "$MODULES_DIR/fd/fd" "$MODULES_DIR/fzf/fzf" \
           "$MODULES_DIR/lazygit/lazygit" "$MODULES_DIR/ast-grep/sg" "$MODULES_DIR/ast-grep/ast-grep" "$MODULES_DIR/bitwarden/bw" "$MODULES_DIR/rclone/rclone"; do
    if [ -s "$cmd" ]; then
        chmod +x "$cmd"
    else
        echo "⚠️  경고: $cmd 파일이 비어있거나 다운로드에 실패했습니다."
    fi
done

print_done "모든 바이너리 도구($ARCH) 설치가 완료되었습니다!"
echo ""

echo "---------------------------------------------------------------------------"
# apt 락 강제 해제 — 단, fuser로 실제로 쥐고 있는 프로세스가 없을 때만 지웁니다.
# unattended-upgrades 같은 진짜 실행 중인 apt/dpkg 프로세스와 경합해 dpkg 데이터베이스가
# 손상되는 걸 방지하기 위함(fuser가 없는 극단적 환경이면 기존처럼 무조건 삭제로 폴백).
for _lockfile in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock; do
    if [ -e "$_lockfile" ]; then
        if command -v fuser &>/dev/null; then
            sudo fuser "$_lockfile" >/dev/null 2>&1 || sudo rm -f "$_lockfile"
        else
            sudo rm -f "$_lockfile"
        fi
    fi
done
sudo dpkg --configure -a 2>/dev/null

echo -n "   - apt 패키지 인덱스 업데이트 중..."
(sudo apt-get update -qq >/tmp/_apt_update.log 2>&1) &
_apt_upd_pid=$!
show_spinner "$_apt_upd_pid"
wait "$_apt_upd_pid" 2>/dev/null || true
rm -f /tmp/_apt_update.log 2>/dev/null
echo " 완료"

echo -n "   - apt 패키지(build-essential, libreadline-dev, git, trash-cli, xclip, wl-clipboard, sqlite3) 설치 중..."
# ⚠️ 이 줄은 포터블 원칙의 예외입니다(전체 목록/이유는 0.init-devtools2.sh 상단 메모 참고).
# - build-essential/libreadline-dev: hererocks(아래 7번) 및 nvim-treesitter :TSInstall이
#   C 소스를 직접 컴파일하는 데 필요 — 컴파일러라 포터블 바이너리로 대체 불가능.
# - xclip/wl-clipboard: 사실 WSL2에서는 안 씀(options.lua가 win32yank/PowerShell clip.exe를
#   우선 사용) — 네이티브 리눅스 전용 폴백이라 WSL2 한정이면 빼도 되는 항목.
# - sqlite3/libsqlite3-dev: Neovim Snacks.picker의 frecency(최근·자주 쓴 파일 우선순위)/히스토리 저장용.
#   없어도 파일 기반으로 폴백되어 동작은 하지만, 세션이 쌓일수록 느려지고 :checkhealth snacks에
#   경고가 뜸. lazy.nvim/Mason 대상이 아닌 OS 공유 라이브러리라 여기 apt 등급에 포함(버전 고정 없음).
(sudo apt-get install -y build-essential libreadline-dev git trash-cli xclip wl-clipboard sqlite3 libsqlite3-dev -qq >/tmp/_apt_install.log 2>&1) &
_apt_inst_pid=$!
show_spinner "$_apt_inst_pid"
_apt_inst_ec=0
wait "$_apt_inst_pid" 2>/dev/null || _apt_inst_ec=$?
if [ "$_apt_inst_ec" -eq 0 ]; then
    rm -f /tmp/_apt_install.log 2>/dev/null
    echo " 완료"
    print_done "apt 패키지 설치 완료"
else
    echo " ⚠️  실패"
    print_error "apt 패키지 설치 중 오류가 발생했습니다. 상세 로그:"
    cat /tmp/_apt_install.log 2>/dev/null || true
    rm -f /tmp/_apt_install.log 2>/dev/null
fi
echo ""

echo "---------------------------------------------------------------------------"
echo "💎 7. hererocks 설치 및 Lua 환경 구성 중... (Neovim 플러그인 관리용)"
echo ""
pip install --user --break-system-packages hererocks 2>/dev/null || pip install --user hererocks

HEREROCKS_DIR="$DEVTOOLS2/data/nvim/lazy-rocks/hererocks"
mkdir -p "$HEREROCKS_DIR"
cd "$HEREROCKS_DIR"

# 임시 PATH 추가 (pip로 설치된 hererocks 바이너리를 현재 셸 환경에 즉시 연동)
export PATH="$HOME/.local/bin:$PATH"

echo -n "   ⚙️ hererocks 구성 중 (Lua 5.1 / Luarocks 최신)..."
(hererocks . -l 5.1 -r latest >/tmp/_hererocks_install.log 2>&1) &
_hero_pid=$!
show_spinner "$_hero_pid"
_hero_ec=0
wait "$_hero_pid" 2>/dev/null || _hero_ec=$?
if [ "$_hero_ec" -eq 0 ]; then
    rm -f /tmp/_hererocks_install.log 2>/dev/null
    echo " 완료"
    print_done "hererocks / Lua 환경 구성 완료"
else
    echo " ⚠️  실패"
    print_error "hererocks 구성 중 오류가 발생했습니다. 상세 로그:"
    cat /tmp/_hererocks_install.log 2>/dev/null || true
    rm -f /tmp/_hererocks_install.log 2>/dev/null
fi
echo ""

echo "---------------------------------------------------------------------------"
echo "🐛 8. Gradle DAP (디버거 Attach) 전역 설정"
echo ""
echo "   Gradle bootRun 실행 시 JDWP(Java Debug Wire Protocol)를 자동으로 활성화하여"
echo "   DAP 클라이언트(Neovim DAP 등)를 포트 5005 로 Attach 할 수 있게 됩니다."
echo ""
echo "   대상 파일: ~/.gradle/init.d/debug.gradle"
echo ""
print_info "💡 Neovim 사용 안내:"
echo "      - <leader> + d + a 단축키로 실행 중인 JVM에 attach 합니다."
echo "      - ※ :Mason 에서 java-debug-adapter 가 설치되어 있어야 함."
echo ""
prompt_input "❓ Gradle bootRun DAP Attach 모드 전역 설정을 추가할까요? [y/${_C_DEFAULT}N${_C_RESET}]: "; read -r dap_answer

# 기본값 n: 이 프로젝트의 기본 디버그 흐름은 launch 모드(dap.lua)라서, attach용 전역
# JDWP 설정을 기본으로 깔 필요가 없습니다 — 필요한 사람만 명시적으로 y를 입력하세요.
dap_answer_lower=$(echo "${dap_answer:-n}" | tr '[:upper:]' '[:lower:]')

if [ "$dap_answer_lower" = "y" ]; then
    GRADLE_INIT_DIR="$HOME/.gradle/init.d"
    GRADLE_DEBUG_FILE="$GRADLE_INIT_DIR/debug.gradle"

    mkdir -p "$GRADLE_INIT_DIR"

    # 파일이 이미 존재하는 경우 교체 여부 확인 (기본값 n: 덮어쓰지 않음)
    do_write=true
    if [ -f "$GRADLE_DEBUG_FILE" ]; then
        echo ""
        print_warn "파일이 이미 존재합니다: $GRADLE_DEBUG_FILE"
        prompt_input "   기존 파일을 새 설정으로 교체할까요? [y/${_C_DEFAULT}N${_C_RESET}]: "; read -r overwrite_answer
        overwrite_lower=$(echo "${overwrite_answer:-n}" | tr '[:upper:]' '[:lower:]')
        if [ "$overwrite_lower" != "y" ]; then
            do_write=false
            print_info "기존 파일을 유지합니다."
        fi
    fi

    if [ "$do_write" = "true" ]; then
        cat > "$GRADLE_DEBUG_FILE" << 'EOF'
allprojects {
  tasks.withType(JavaExec).configureEach {
    if (name == "bootRun") {
      // jvmArgs 리스트에 "-agentlib:jdwp"로 시작하는 설정이 있는지 확인
      def hasJDWP = jvmArgs.any { it.toString().contains("-agentlib:jdwp") }

      if (hasJDWP) {
        // 로컬(-I 옵션 등)에서 이미 설정했다면 전역 설정(5005)은 하지 않음
        println ">>> [Global] Custom debug config detected. Prioritizing your custom port."
      } else {
        def javaVersion = org.gradle.api.JavaVersion.current()
        def debugAddress = "127.0.0.1:5005"

        // suspend=y 로 변경하면 디버거가 연결(Attach)되기 전까지 대기한다.
        jvmArgs("-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=${debugAddress}")
        println ">>> [Global] Default JDWP Address assigned: ${debugAddress} (Java Version: ${javaVersion})"
      }
    }
  }
}
EOF

        echo "   ✅ Gradle DAP Attach 전역 설정 완료"
        echo "      파일: $GRADLE_DEBUG_FILE"
        echo "      포트: 127.0.0.1:5005 (suspend=n, Attach 모드)"
    fi
else
    GRADLE_DEBUG_FILE="$HOME/.gradle/init.d/debug.gradle"
    if [ -f "$GRADLE_DEBUG_FILE" ]; then
        rm -f "$GRADLE_DEBUG_FILE"
        echo "   🗑️  이전에 설치된 Attach 모드 설정을 삭제했습니다: $GRADLE_DEBUG_FILE"
    else
        echo "   ⏭️  건너뜀: Gradle DAP Attach 전역 설정을 나중에 추가하려면"
        echo "      $GRADLE_DEBUG_FILE 파일을 직접 생성하세요."
    fi
fi
echo ""

# ==============================================================================
# 9. Neovim 플러그인 & 개발 환경 최종 동기화 (Lazy + Treesitter + Mason)
#
# 📌 [이 위치에 있어야 하는 이유 (설계 원칙)]
#  Neovim 플러그인 생태계는 단순 에디터 바이너리 외에 여러 런타임/컴파일러 의존성을 갖습니다:
#   1) Node.js, Python, Neovim 바이너리: 2.install-core-tools.sh 에서 설치 완료
#   2) C 컴파일러(build-essential gcc): 3번 스크립트 6단계에서 설치 완료
#      - nvim-treesitter 구문 강조 파서 및 C 확장 모듈(fzf-native 등) 컴파일에 필수
#   3) SQLite3 라이브러리: 3번 스크립트 6단계에서 설치 완료
#      - snacks.nvim (picker)의 최근/빈도 히스토리 DB 연동에 필수
#   4) Lua/LuaRocks 환경: 3번 스크립트 7단계 hererocks 에서 구성 완료
#   5) CLI 검색 유틸(ripgrep, fd, fzf): 3번 스크립트 1~3단계에서 설치 완료
#
#  따라서 이 모든 의존성이 100% 충족된 '3번 스크립트의 맨 마지막'에 한 번만 실행하여:
#   - Lazy! restore : lazy-lock.json 기반 플러그인 무결성 복원
#   - TSUpdateSync  : gcc를 활용한 언어별 Treesitter 파서 사전 컴파일
#   - MasonUpdate   : LSP/DAP/포맷터 패키지 레지스트리 갱신
#  을 완료하면, 사용자가 최초로 nvim을 실행할 때 다운로드 렉/오류 없는 Zero-Touch 환경이 완성됩니다.
# ==============================================================================
NVIM_BIN="$DEVTOOLS2/modules/neovim/nvim/bin/nvim"
if [ -x "$NVIM_BIN" ] && [ -f "$DEVTOOLS2/.config/nvim/lazy-lock.json" ]; then
    echo "---------------------------------------------------------------------------"
    echo "💤 9. Neovim 플러그인 및 개발 환경 최종 동기화 (Zero-Touch 사전 빌드)"
    echo ""
    # Neovim, Node, Python, hererocks, cli 툴들을 모두 포함한 임시 PATH 주입
    export PATH="$DEVTOOLS2/modules/neovim/nvim/bin:$DEVTOOLS2/modules/nodejs/node-v24/bin:$DEVTOOLS2/modules/python/python-314/bin:$DEVTOOLS2/data/nvim/lazy-rocks/hererocks/bin:$DEVTOOLS2/modules/ripgrep:$DEVTOOLS2/modules/fd:$DEVTOOLS2/modules/fzf:$PATH"

    echo -n "   📦 Lazy 플러그인 복원, Treesitter 파서 컴파일 및 Mason 레지스트리 갱신 중..."
    ("$NVIM_BIN" --headless "+Lazy! restore" "+TSUpdateSync" "+MasonUpdate" +qa >/tmp/_nvim_sync.log 2>&1) &
    show_spinner $!
    rm -f /tmp/_nvim_sync.log 2>/dev/null
    echo " 완료"
    print_done "Neovim 통합 환경 동기화 완료!"
    echo ""
fi

print_sep
print_step "🎉 모든 도구 설치가 완료되었습니다!"
echo ""
echo "설정 확인 명령어:"
echo "    hererocks --version"
echo "    ls -F \"$DEVTOOLS2/data/nvim/lazy-rocks/hererocks/bin/\""
print_sep
echo ""
