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

# 공통 모듈 로드 (로컬 우선 탐색 후 원격 스트리밍)
DT2_REF="${DT2_REF:-main}"
_GH_RAW="https://raw.githubusercontent.com/devers2/_devtools2/${DT2_REF}/scripts/linux/dev-env"
_SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
if [ -f "$_SCRIPT_DIR/_common.sh" ]; then
    # shellcheck disable=SC1091
    source "$_SCRIPT_DIR/_common.sh"
elif [ -f "${DEVTOOLS2:-}/scripts/linux/dev-env/_common.sh" ]; then
    # shellcheck disable=SC1091
    source "$DEVTOOLS2/scripts/linux/dev-env/_common.sh"
else
    # shellcheck disable=SC1090
    source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_common.sh") || { echo "[오류] _common.sh 로드 실패 - 네트워크 연결을 확인하세요." >&2; exit 1; }
fi

# 공통 설치 유틸리티 로드
if [ -f "$_SCRIPT_DIR/_install-utils.sh" ]; then
    # shellcheck disable=SC1091
    source "$_SCRIPT_DIR/_install-utils.sh"
elif [ -f "${DEVTOOLS2:-}/scripts/linux/dev-env/_install-utils.sh" ]; then
    # shellcheck disable=SC1091
    source "$DEVTOOLS2/scripts/linux/dev-env/_install-utils.sh"
else
    # shellcheck disable=SC1090
    source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_install-utils.sh") || { print_error "_install-utils.sh 로드 실패 - 네트워크 연결을 확인하세요."; exit 1; }
fi

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
chmod 700 "$MODULES_DIR/rclone/.config"
if [ -d "$DEVTOOLS2/.config/rclone" ]; then
    if [ -f "$DEVTOOLS2/.config/rclone/rclone.conf" ]; then
        mv -f "$DEVTOOLS2/.config/rclone/rclone.conf" "$MODULES_DIR/rclone/.config/rclone.conf" 2>/dev/null || true
        chmod 600 "$MODULES_DIR/rclone/.config/rclone.conf" 2>/dev/null || true
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

# show_spinner 는 _common.sh 에서 로드됨

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
    prompt_read _dup_choice "   선택 [1/${_C_DEFAULT}2${_C_RESET}/3]: "
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
# 도구 다운로드 URL 생성 헬퍼
# ─────────────────────────────────────────────────────────────────
get_cli_tool_url() {
    local tool="$1"
    local ver="$2"
    case "$tool" in
        fzf)
            if [ "$IS_ARM64" = true ]; then
                echo "https://github.com/junegunn/fzf/releases/download/v${ver}/fzf-${ver}-linux_arm64.tar.gz"
            else
                echo "https://github.com/junegunn/fzf/releases/download/v${ver}/fzf-${ver}-linux_amd64.tar.gz"
            fi
            ;;
        lazygit)
            if [ "$IS_ARM64" = true ]; then
                echo "https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_arm64.tar.gz"
            else
                echo "https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_x86_64.tar.gz"
            fi
            ;;
        ripgrep)
            if [ "$IS_ARM64" = true ]; then
                echo "https://github.com/BurntSushi/ripgrep/releases/download/${ver}/ripgrep-${ver}-aarch64-unknown-linux-gnu.tar.gz"
            else
                echo "https://github.com/BurntSushi/ripgrep/releases/download/${ver}/ripgrep-${ver}-x86_64-unknown-linux-musl.tar.gz"
            fi
            ;;
        fd)
            if [ "$IS_ARM64" = true ]; then
                echo "https://github.com/sharkdp/fd/releases/download/v${ver}/fd-v${ver}-aarch64-unknown-linux-musl.tar.gz"
            else
                echo "https://github.com/sharkdp/fd/releases/download/v${ver}/fd-v${ver}-x86_64-unknown-linux-musl.tar.gz"
            fi
            ;;
        ast-grep)
            if [ "$IS_ARM64" = true ]; then
                echo "https://github.com/ast-grep/ast-grep/releases/download/${ver}/app-aarch64-unknown-linux-gnu.zip"
            else
                echo "https://github.com/ast-grep/ast-grep/releases/download/${ver}/app-x86_64-unknown-linux-gnu.zip"
            fi
            ;;
        bitwarden)
            if [ "$IS_ARM64" = true ]; then
                echo "https://github.com/bitwarden/clients/releases/download/cli-v${ver}/bw-linux-arm64-${ver}.zip"
            else
                echo "https://vault.bitwarden.com/download/?app=cli&platform=linux"
            fi
            ;;
        rclone)
            if [ "$IS_ARM64" = true ]; then
                echo "https://github.com/rclone/rclone/releases/download/v${ver}/rclone-v${ver}-linux-arm64.zip"
            else
                echo "https://github.com/rclone/rclone/releases/download/v${ver}/rclone-v${ver}-linux-amd64.zip"
            fi
            ;;
        win32yank)
            echo "https://github.com/equalsraf/win32yank/releases/download/v${ver}/win32yank-x64.zip"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────
# 도구 다운로드 SHA256 체크섬 URL 생성 헬퍼
# ─────────────────────────────────────────────────────────────────
get_cli_tool_checksum_url() {
    local tool="$1"
    local ver="$2"
    case "$tool" in
        fzf)
            echo "https://github.com/junegunn/fzf/releases/download/v${ver}/fzf_${ver}_checksums.txt"
            ;;
        lazygit)
            echo "https://github.com/jesseduffield/lazygit/releases/download/v${ver}/checksums.txt"
            ;;
        ripgrep)
            if [ "$IS_ARM64" = true ]; then
                echo "https://github.com/BurntSushi/ripgrep/releases/download/${ver}/ripgrep-${ver}-aarch64-unknown-linux-gnu.tar.gz.sha256"
            else
                echo "https://github.com/BurntSushi/ripgrep/releases/download/${ver}/ripgrep-${ver}-x86_64-unknown-linux-musl.tar.gz.sha256"
            fi
            ;;
        rclone)
            echo "https://github.com/rclone/rclone/releases/download/v${ver}/SHA256SUMS"
            ;;
        *)
            echo ""
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────
# 도구별 버전 확인 및 다운로드/설치 공용 함수
# ─────────────────────────────────────────────────────────────────
install_cli_tool() {
    local id="$1"             # fzf
    local label="$2"          # "fzf - 터미널용 퍼지 파인더"
    local repo="$3"           # junegunn/fzf
    local pinned_ver="$4"     # $FZF_PINNED
    local current_ver="$5"    # $FZF_VERSION
    local installed="$6"      # $FZF_INSTALLED
    local bin_rel_path="$7"   # fzf/fzf
    local strip_num="${8:-0}" # 0 or 1
    local toml_key="$9"       # fzf

    # 1. 버전 결정 (개별 선택 모드)
    local selected_ver="$current_ver"
    if [ "$VERSION_MODE" = "individual" ]; then
        if [ "$id" = "bitwarden" ] && [ "$IS_ARM64" != true ]; then
            selected_ver="(최신)"
        else
            echo -n "   🔍 $id 최신 버전 조회 중... "
            local _latest=""
            if [ "$id" = "bitwarden" ]; then
                _latest=$(fetch_latest_bitwarden_cli)
            elif [ "$id" = "ripgrep" ]; then
                _latest=$(fetch_latest_github "$repo")
            else
                _latest=$(fetch_latest_github "$repo" | sed 's/^v//')
            fi
            [ -n "$_latest" ] && echo "완료 ($_latest)" || echo "실패"
            echo ""
            echo "   $id 설치 버전 선택:"
            echo "   1) 최신 버전: ${_latest:-[조회 실패 - 선택 불가]}"
            echo "   2) 최종 설치 버전: $pinned_ver [기본값]"
            echo ""
            local _vs=""
            prompt_read _vs "   선택 [1/${_C_DEFAULT}2${_C_RESET}]: "
            case "${_vs:-2}" in
                1) [ -n "$_latest" ] && selected_ver="$_latest" || selected_ver="$pinned_ver" ;;
                *) selected_ver="$pinned_ver" ;;
            esac
            echo ""
        fi
    fi

    # 2. 설치/재설치/건너뛰기 결정
    local action
    action=$(_resolve_action "$installed" "$id")

    echo "📦 $id $selected_ver 설치..."
    if [ "$action" = "skip" ]; then
        echo "   ⏭️  [건너뜀] 이미 설치되어 있습니다."
        return 0
    fi

    # 3. 재설치 시 기존 바이너리 삭제
    if [ "$action" = "reinstall" ]; then
        rm -f "$MODULES_DIR/$bin_rel_path"
    fi

    local target_dir="$MODULES_DIR/$(dirname "$bin_rel_path")"
    mkdir -p "$target_dir"

    # 4. 다운로드 URL 및 무결성 검증용 체크섬 URL 생성
    local dl_url dl_checksum
    dl_url=$(get_cli_tool_url "$id" "$selected_ver")
    dl_checksum=$(get_cli_tool_checksum_url "$id" "$selected_ver")

    # 5. 다운로드 및 설치
    local install_ok=false
    if [ "$id" = "rclone" ]; then
        if download_with_progress "$dl_url" "/tmp/rclone.zip" "rclone $selected_ver"; then
            if [ -n "$dl_checksum" ]; then
                if ! verify_sha256 "/tmp/rclone.zip" "$dl_checksum" "$(basename "$dl_url")"; then
                    rm -f /tmp/rclone.zip
                    echo " ❌ rclone 체크섬 검증 실패" >&2
                    return 1
                fi
            fi
            echo -n "   📦 rclone $selected_ver 압축 해제 중..."
            (unzip -qo /tmp/rclone.zip -d /tmp/rclone_tmp && \
             mv -f /tmp/rclone_tmp/rclone-*/rclone "$MODULES_DIR/rclone/rclone" && \
             rm -rf /tmp/rclone.zip /tmp/rclone_tmp) &
            local _rc_pid=$!
            show_spinner $_rc_pid
            if wait $_rc_pid 2>/dev/null; then
                echo " 완료"
                install_ok=true
            else
                echo " ❌ 압축 해제 실패" >&2
            fi
        fi
    elif [ "$strip_num" -gt 0 ]; then
        if safe_download_and_extract "$dl_url" "$target_dir" "$strip_num" "$dl_checksum" "$id $selected_ver"; then
            install_ok=true
        fi
    else
        if safe_download_and_extract "$dl_url" "$target_dir" 0 "$dl_checksum" "$id $selected_ver"; then
            install_ok=true
        fi
    fi

    if [ "$install_ok" = true ]; then
        if [ "$id" = "ast-grep" ]; then
            (cd "$target_dir" && ([ -f ast-grep ] && [ ! -f sg ] && ln -sf ast-grep sg || true) && ([ -f sg ] && [ ! -f ast-grep ] && ln -sf sg ast-grep || true))
        elif [ "$id" = "bitwarden" ]; then
            chmod +x "$target_dir/bw" 2>/dev/null || true
        elif [ "$id" = "win32yank" ]; then
            chmod +x "$target_dir/win32yank.exe" 2>/dev/null || true
        fi
        echo "   ✅ $id $selected_ver 설치 완료"

        if [ -n "$toml_key" ] && [ "$selected_ver" != "$pinned_ver" ] && [ "$selected_ver" != "(최신)" ]; then
            update_pinned_version "$toml_key" "$selected_ver"
        fi
    else
        echo " ❌ $id 다운로드/설치 실패" >&2
    fi
}

# ─────────────────────────────────────────────────────────────────
# 각 CLI 도구 순차 설치 실행
# ─────────────────────────────────────────────────────────────────
install_cli_tool "fzf" "fzf - 터미널용 퍼지 파인더" "junegunn/fzf" "$FZF_PINNED" "$FZF_VERSION" "$FZF_INSTALLED" "fzf/fzf" 0 "fzf"
install_cli_tool "lazygit" "lazygit - 터미널 UI Git 도구" "jesseduffield/lazygit" "$LAZYGIT_PINNED" "$LAZYGIT_VERSION" "$LAZYGIT_INSTALLED" "lazygit/lazygit" 0 "lazygit"
install_cli_tool "ripgrep" "ripgrep (rg) - 코드 검색 도구" "BurntSushi/ripgrep" "$RIPGREP_PINNED" "$RIPGREP_VERSION" "$RIPGREP_INSTALLED" "ripgrep/rg" 1 "ripgrep"
install_cli_tool "fd" "fd-find (fd) - 파일 검색 도구" "sharkdp/fd" "$FD_PINNED" "$FD_VERSION" "$FD_INSTALLED" "fd/fd" 1 "fd"
install_cli_tool "ast-grep" "ast-grep (sg) - 구조적 코드 검색 도구" "ast-grep/ast-grep" "$ASTGREP_PINNED" "$ASTGREP_VERSION" "$ASTGREP_INSTALLED" "ast-grep/ast-grep" 0 "ast_grep"
install_cli_tool "bitwarden" "Bitwarden CLI (bw)" "bitwarden/clients" "$BITWARDEN_ARM_PINNED" "$BITWARDEN_ARM_VERSION" "$BITWARDEN_INSTALLED" "bitwarden/bw" 0 "bitwarden_arm"
install_cli_tool "rclone" "rclone - 클라우드 동기화 도구" "rclone/rclone" "$RCLONE_PINNED" "$RCLONE_VERSION" "$RCLONE_INSTALLED" "rclone/rclone" 0 "rclone"

# rclone 구성 파일 디렉터리 보장 ($DEVTOOLS2/modules/rclone/.config — git 미추적 영역)
mkdir -p "$MODULES_DIR/rclone/.config"

if [ "$IS_WSL2" = true ]; then
    install_cli_tool "win32yank" "win32yank - 클립보드 공유 도구" "equalsraf/win32yank" "$WIN32YANK_PINNED" "$WIN32YANK_VERSION" "$WIN32YANK_INSTALLED" "win32yank/win32yank.exe" 0 "win32yank"
    if [ -d "$MODULES_DIR/win32yank" ]; then
        ensure_path_in_bashrc "$MODULES_DIR/win32yank"
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

# ==============================================================================
# 8. Gradle DAP (디버거 Attach) 전역 설정
# (구현부: scripts/linux/dev-env/_install-utils.sh configure_gradle_dap)
# ==============================================================================
configure_gradle_dap

# ==============================================================================
# 9. Gradle Spotless (Java 포매터) 전역 설정
# (구현부: scripts/linux/dev-env/_install-utils.sh configure_gradle_spotless)
# ==============================================================================
configure_gradle_spotless

print_sep
print_step "🎉 모든 도구 설치가 완료되었습니다!"
echo ""
echo "설정 확인 명령어:"
echo "    hererocks --version"
echo "    ls -F \"$DEVTOOLS2/data/nvim/lazy-rocks/hererocks/bin/\""
print_sep
echo ""
