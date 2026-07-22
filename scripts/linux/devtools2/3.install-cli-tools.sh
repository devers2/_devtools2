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

# 아키텍처 확인
ARCH=$(uname -m)
IS_ARM64=false
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    IS_ARM64=true
fi

# WSL2 환경 감지: /proc/version에 'microsoft' 문자열이 포함되어 있으면 WSL2로 판단한다.
IS_WSL2=false
if grep -qi 'microsoft' /proc/version 2>/dev/null; then
    IS_WSL2=true
fi

if [ -z "${DEVTOOLS2:-}" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")
fi

# 유효한 DEVTOOLS2 폴더가 아니면 표준 경로를 기본값으로 사용
if [ ! -f "$DEVTOOLS2/scripts/linux/devtools2/3.install-cli-tools.sh" ]; then
    DEVTOOLS2="/var/opt/_devtools2"
fi

# 공통 색상/스피너 헬퍼 로드 (원격 실행 및 파일 미존재 시 자동 폴백 보장)
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

    _C_RESET='' _C_BOLD='' _C_CYAN='' _C_GREEN='' _C_YELLOW='' _C_RED='' _C_MAGENTA='' _C_WHITE='' _C_GRAY=''
    if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
        _C_RESET='\033[0m' _C_BOLD='\033[1m' _C_CYAN='\033[0;36m' _C_GREEN='\033[0;32m'
        _C_YELLOW='\033[0;33m' _C_RED='\033[0;31m' _C_MAGENTA='\033[0;35m' _C_WHITE='\033[1;37m'
    fi

    print_info()    { printf "${_C_CYAN}[정보]${_C_RESET} %s\n"    "$*"; }
    print_success() { printf "${_C_GREEN}[성공]${_C_RESET} %s\n"   "$*"; }
    print_done()    { printf "${_C_GREEN}[완료]${_C_RESET} %s\n"   "$*"; }
    print_warn()    { printf "${_C_YELLOW}[경고]${_C_RESET} %s\n"  "$*"; }
    print_error()   { printf "${_C_RED}[오류]${_C_RESET} %s\n"     "$*" >&2; }
    print_step()    { printf "${_C_MAGENTA}%s${_C_RESET}\n"         "$*"; }
    print_sep()     { printf "${_C_MAGENTA}%s${_C_RESET}\n" "==========================================================================="; }
    print_subsep()  { printf "${_C_MAGENTA}%s${_C_RESET}\n" "---------------------------------------------------------------------------"; }
    print_question(){ printf "${_C_BOLD}${_C_CYAN}%s${_C_RESET}\n" "$*"; }
    print_option()  {
        if [ -n "${3:-}" ]; then
            printf "   ${_C_YELLOW}${_C_BOLD}%s)${_C_RESET} ${_C_WHITE}%s${_C_RESET} ${_C_GREEN}${_C_BOLD}%s${_C_RESET}\n" "$1" "$2" "$3"
        else
            printf "   ${_C_YELLOW}${_C_BOLD}%s)${_C_RESET} ${_C_WHITE}%s${_C_RESET}\n" "$1" "$2"
        fi
    }
    prompt_input()  { printf "${_C_YELLOW}${_C_BOLD}%s${_C_RESET} " "$*"; }
    _COLORS_LOADED=true
}
_load_colors

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

# 바이너리가 설치될 modules 디렉토리 경로 설정
MODULES_DIR="$DEVTOOLS2/modules"

# 경로 생성
# 각 도구별로 독립된 폴더를 생성하여 관리를 용이하게 합니다.
mkdir -p "$MODULES_DIR/fzf" "$MODULES_DIR/lazygit" "$MODULES_DIR/ripgrep" "$MODULES_DIR/fd" "$MODULES_DIR/ast-grep" "$MODULES_DIR/bitwarden"

# tool-versions.toml 경로
TOOL_VERSIONS_TOML="$DEVTOOLS2/scripts/linux/devtools2/tool-versions.toml"

# ─────────────────────────────────────────────────────────────────
# 📄 TOML 유틸리티 함수 (tool-versions.toml 연동)
# ─────────────────────────────────────────────────────────────────

# 지정한 키의 최종 설치 버전 (배열의 첫 번째 값)을 반환합니다.
get_pinned_version() {
    local key="$1"
    grep -E "^${key} = \[" "$TOOL_VERSIONS_TOML" 2>/dev/null \
        | grep -oE '"[^"]+"' | head -1 | tr -d '"'
}

# 지정한 키의 버전 배열 앞에 새 버전을 추가합니다 (이미 있으면 건너뜀).
update_pinned_version() {
    local key="$1" new_ver="$2"
    if grep -E "^${key} = \[" "$TOOL_VERSIONS_TOML" 2>/dev/null | grep -qF "\"${new_ver}\""; then
        return 0
    fi
    sed -i "s|^\(${key} = \[\)\(.*\)\]\$|\1\"${new_ver}\", \2]|" "$TOOL_VERSIONS_TOML"
    echo "   📝 [tool-versions.toml] ${key} 버전 이력 추가: \"${new_ver}\""
}

# GitHub 최신 릴리즈 태그를 반환합니다. 실패 시 빈 문자열 반환.
fetch_latest_github() {
    local repo="$1"
    curl -sf --max-time 10 \
        "https://api.github.com/repos/${repo}/releases/latest" \
        2>/dev/null \
        | grep '"tag_name"' | head -1 \
        | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' || true
}

# Bitwarden CLI 최신 릴리즈 버전을 반환합니다 (cli-v 태그만 필터링).
fetch_latest_bitwarden_cli() {
    curl -sf --max-time 10 \
        "https://api.github.com/repos/bitwarden/clients/releases" \
        2>/dev/null \
        | grep '"tag_name"' | grep 'cli-v' | head -1 \
        | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
        | sed 's/^cli-v//' || true
}

show_spinner() {
    local pid=$1
    local delay=0.15
    local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_len=${#spinner[@]}
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf " [%s] " "${spinner[i]}"
        i=$(( (i + 1) % spin_len ))
        sleep $delay
        printf "\b\b\b\b\b"
    done
    printf "     \b\b\b\b\b"
}

# ─────────────────────────────────────────────────────────────────
# ⚙️  PRE-FLIGHT: 설치 방식 선택 (CLI 도구 7종)
# ─────────────────────────────────────────────────────────────────

# 최종 설치 버전 읽기
FZF_PINNED=$(get_pinned_version "fzf")
LAZYGIT_PINNED=$(get_pinned_version "lazygit")
RIPGREP_PINNED=$(get_pinned_version "ripgrep")
FD_PINNED=$(get_pinned_version "fd")
ASTGREP_PINNED=$(get_pinned_version "ast_grep")
BITWARDEN_ARM_PINNED=$(get_pinned_version "bitwarden_arm")
WIN32YANK_PINNED=$(get_pinned_version "win32yank")

# 설치 상태 확인
FZF_INSTALLED=false;      [ -f "$MODULES_DIR/fzf/fzf" ]           && FZF_INSTALLED=true
LAZYGIT_INSTALLED=false;  [ -f "$MODULES_DIR/lazygit/lazygit" ]    && LAZYGIT_INSTALLED=true
RIPGREP_INSTALLED=false;  [ -f "$MODULES_DIR/ripgrep/rg" ]         && RIPGREP_INSTALLED=true
FD_INSTALLED=false;       [ -f "$MODULES_DIR/fd/fd" ]              && FD_INSTALLED=true
ASTGREP_INSTALLED=false;  [ -f "$MODULES_DIR/ast-grep/sg" ]        && ASTGREP_INSTALLED=true
BITWARDEN_INSTALLED=false;[ -f "$MODULES_DIR/bitwarden/bw" ]       && BITWARDEN_INSTALLED=true
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

# 상태 포매팅 헬퍼
_fmts() { [ "$1" = true ] && echo '✅ 설치됨' || echo '⬜ 미설치'; }

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
           "$FD_INSTALLED" "$ASTGREP_INSTALLED" "$BITWARDEN_INSTALLED" "$WIN32YANK_INSTALLED"; do
    [ "$_b" = true ] && _HAS_INSTALLED=true && break
done

if [ "$_HAS_INSTALLED" = true ]; then
    print_question "⚠️  이미 설치된 도구가 감지되었습니다. 중복 처리 방식을 선택하세요:"
    echo ""
    print_option "1" "기존 도구 삭제 후 재설치 (덮어쓰기)"
    print_option "2" "기존 도구 유지 (건너뛰기)" "[기본값]"
    print_option "3" "도구별 개별 확인 (재설치/건너뛰기 선택)"
    echo ""
    read -rp "$(prompt_input "   선택 (1-3, 기본값: 2): ")" _dup_choice
    echo ""
    case "${_dup_choice:-2}" in
        1) DUPLICATE_MODE="remove"     ; print_info "중복 처리: 묻지 않고 삭제 후 재설치 선택됨" ;;
        3) DUPLICATE_MODE="individual" ; print_info "중복 처리: 도구별 개별 확인 선택됨" ;;
        *) DUPLICATE_MODE="keep"       ; print_info "중복 처리: 기존 도구 유지(건너뛰기) 선택됨" ;;
    esac
    echo ""
fi

# ── 버전 설치 방식 선택 ──────────────────────────────────────────
print_question "❓ 적용할 버전 선택 방식을 선택하세요:"
echo ""
print_option "1" "모든 도구 최신 버전으로 설치 (온라인 최신 릴리스)"
print_option "2" "모든 도구 지정 버전으로 설치 (TOML 고정/최종 설치 버전)" "[기본값]"
print_option "3" "도구별 개별 확인 (최신/지정 버전 선택)"
echo ""
read -rp "$(prompt_input "   선택 (1-3, 기본값: 2): ")" _ver_choice
echo ""
case "${_ver_choice:-2}" in
    1) VERSION_MODE="latest"     ; print_info "버전 선택: 모든 도구 최신 버전 선택됨" ;;
    3) VERSION_MODE="individual" ; print_info "버전 선택: 도구별 개별 확인 선택됨" ;;
    *) VERSION_MODE="pinned"     ; print_info "버전 선택: 모든 도구 지정(TOML) 버전 선택됨" ;;
esac

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

# ─────────────────────────────────────────────────────────────────
# 공통: 도구별 설치 액션(install/reinstall/skip) 결정 헬퍼
# ─────────────────────────────────────────────────────────────────
# 사용법: _resolve_action <IS_INSTALLED> <TOOL_DISPLAY_NAME>
# 결과: echo "install" | "reinstall" | "skip"
_resolve_action() {
    local is_installed="$1"
    local tool_name="$2"
    if [ "$is_installed" = false ]; then
        echo "install"; return
    fi
    case "$DUPLICATE_MODE" in
        remove)
            echo "reinstall"
            ;;
        individual)
            echo ""
            echo "   ⚠️  ${tool_name}이(가) 이미 설치되어 있습니다."
            read -rp "   삭제 후 재설치하시겠습니까? (y/N): " _dup_sel
            case "${_dup_sel:-N}" in
                y|Y) echo "reinstall" ;;
                *)   echo "skip" ;;
            esac
            ;;
        *)
            echo "skip"
            ;;
    esac
}

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
    read -rp "   선택 (1-2, 기본값: 2): " _fzf_vs
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
    read -rp "   선택 (1-2, 기본값: 2): " _lg_vs
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
    read -rp "   선택 (1-2, 기본값: 2): " _rg_vs
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
    read -rp "   선택 (1-2, 기본값: 2): " _fd_vs
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
    read -rp "   선택 (1-2, 기본값: 2): " _sg_vs
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
        rm -f "$MODULES_DIR/ast-grep/sg"
    fi
    # ast-grep은 버전별 다운로드와 /latest/ 다운로드 모두 지원
    if [ "$ASTGREP_VERSION" = "$ASTGREP_PINNED" ] && [ "$VERSION_MODE" = "pinned" ]; then
        # 최종 설치 버전이 최신과 같을 수 있으므로 버전 명시 URL 사용
        if [ "$IS_ARM64" = true ]; then
            _sg_url="https://github.com/ast-grep/ast-grep/releases/download/v${ASTGREP_VERSION}/app-aarch64-unknown-linux-gnu.zip"
        else
            _sg_url="https://github.com/ast-grep/ast-grep/releases/download/v${ASTGREP_VERSION}/app-x86_64-unknown-linux-gnu.zip"
        fi
    else
        if [ "$IS_ARM64" = true ]; then
            _sg_url="https://github.com/ast-grep/ast-grep/releases/download/v${ASTGREP_VERSION}/app-aarch64-unknown-linux-gnu.zip"
        else
            _sg_url="https://github.com/ast-grep/ast-grep/releases/download/v${ASTGREP_VERSION}/app-x86_64-unknown-linux-gnu.zip"
        fi
    fi
    (curl -sL "$_sg_url" -o /tmp/ast-grep.zip && unzip -qo /tmp/ast-grep.zip -d "$MODULES_DIR/ast-grep" && rm -f /tmp/ast-grep.zip) &
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
    read -rp "   선택 (1-2, 기본값: 2): " _bw_vs
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
# 7. (WSL2 전용) win32yank 설치 (Neovim의 Windows 클립보드 공유 용도)
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
        read -rp "   선택 (1-2, 기본값: 2): " _wy_vs
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
           "$MODULES_DIR/lazygit/lazygit" "$MODULES_DIR/ast-grep/sg" "$MODULES_DIR/bitwarden/bw"; do
    if [ -s "$cmd" ]; then
        chmod +x "$cmd"
    else
        echo "⚠️  경고: $cmd 파일이 비어있거나 다운로드에 실패했습니다."
    fi
done

print_done "모든 바이너리 도구($ARCH) 설치가 완료되었습니다!"
echo ""

echo "---------------------------------------------------------------------------"
# apt 락 강제 해제
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null
sudo dpkg --configure -a 2>/dev/null

echo -n "   - apt 패키지 인덱스 업데이트 중..."
sudo apt-get update -qq &
show_spinner $!
echo " 완료"

echo -n "   - apt 패키지(build-essential, libreadline-dev, git, trash-cli, xclip, wl-clipboard) 설치 중..."
sudo apt-get install -y build-essential libreadline-dev git trash-cli xclip wl-clipboard -qq &
show_spinner $!
echo " 완료"
print_done "apt 패키지 설치 완료"
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
hererocks . -l 5.1 -r latest &
show_spinner $!
echo " 완료"
print_done "hererocks / Lua 환경 구성 완료"
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
print_question "❓ Gradle bootRun DAP Attach 모드 전역 설정을 추가할까요? [Y/n]"
read -rp "$(prompt_input "   선택 [Y/n, 기본값: Y]: ")" dap_answer

# 기본값 y: 아무것도 입력 안 하거나 Y/y 입력 시 설치
dap_answer_lower=$(echo "${dap_answer:-y}" | tr '[:upper:]' '[:lower:]')

if [ "$dap_answer_lower" = "y" ]; then
    GRADLE_INIT_DIR="$HOME/.gradle/init.d"
    GRADLE_DEBUG_FILE="$GRADLE_INIT_DIR/debug.gradle"

    mkdir -p "$GRADLE_INIT_DIR"

    # 파일이 이미 존재하는 경우 교체 여부 확인 (기본값 n: 덮어쓰지 않음)
    do_write=true
    if [ -f "$GRADLE_DEBUG_FILE" ]; then
        echo ""
        print_warn "파일이 이미 존재합니다: $GRADLE_DEBUG_FILE"
        read -rp "$(prompt_input "   기존 파일을 새 설정으로 교체할까요? [y/N, 기본값: N]: ")" overwrite_answer
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
    echo "   ⏭️  건너뜀: Gradle DAP Attach 전역 설정을 나중에 추가하려면"
    echo "      $HOME/.gradle/init.d/debug.gradle 파일을 직접 생성하세요."
fi
echo ""




print_sep
print_step "🎉 모든 도구 설치가 완료되었습니다!"
echo ""
echo "설정 확인 명령어:"
echo "    hererocks --version"
echo "    ls -F \"$DEVTOOLS2/data/nvim/lazy-rocks/hererocks/bin/\""
print_sep
echo ""
