#!/bin/bash

# =================================================================
# DevTools2 CLI 유틸리티 도구 설치 스크립트 (3.install-cli-tools.sh)
# 대상: fzf, lazygit, ripgrep, fd, ast-grep, gh(GitHub CLI, Bitwarden PAT 자동 로그인 포함),
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

# 공통 설치 유틸리티 로드
if [ -f "$_SCRIPT_DIR/_install-utils.sh" ]; then
    # shellcheck disable=SC1091
    source "$_SCRIPT_DIR/_install-utils.sh"
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
mkdir -p "$MODULES_DIR/fzf" "$MODULES_DIR/lazygit" "$MODULES_DIR/ripgrep" "$MODULES_DIR/fd" "$MODULES_DIR/ast-grep" "$MODULES_DIR/bitwarden" "$MODULES_DIR/rclone" "$MODULES_DIR/gh"

# rclone 구성 파일 디렉터리 사전 확보 (사용자 홈 ~/.config/rclone — 사용자별 격리, 700)
# (공유 트리 modules/rclone/.config 에 있던 예전 설정은 1.setup-env.sh 가 사용자 홈으로 옮깁니다)
mkdir -p "$HOME/.config/rclone"
chmod 700 "$HOME/.config/rclone"
if [ -f "$DEVTOOLS2/.config/rclone/rclone.conf" ] && [ ! -e "$HOME/.config/rclone/rclone.conf" ]; then
    mv -f "$DEVTOOLS2/.config/rclone/rclone.conf" "$HOME/.config/rclone/rclone.conf" 2>/dev/null || true
    chmod 600 "$HOME/.config/rclone/rclone.conf" 2>/dev/null || true
    rmdir "$DEVTOOLS2/.config/rclone" 2>/dev/null || true
fi

# TOOL_VERSIONS_TOML/_read_toml/get_pinned_version/update_pinned_version/fetch_latest_github 는
# _install-utils.sh 에서 로드됨 (2.install-core-tools.sh 와 공유)

# (Bitwarden CLI 최신 버전 조회는 공용 list_github_release_versions "bitwarden/clients" "cli-v" 로 대체)

# show_spinner 는 _common.sh 에서 로드됨

# ─────────────────────────────────────────────────────────────────
# ⚙️  PRE-FLIGHT: 설치 방식 선택 (CLI 도구 9종)
# ─────────────────────────────────────────────────────────────────

# 버전 정책은 tool-versions.toml 의 [track] 한 곳에서 관리합니다 (_install-utils.sh 의 resolve_track_version).
# 예전처럼 설치 때마다 "최신/지정/개별" 버전 선택 방식을 묻지 않고, 각 도구의 track 범위 안 최신 버전을 설치합니다.

# 설치 상태 확인
FZF_INSTALLED=false;      [ -f "$MODULES_DIR/fzf/fzf" ]           && FZF_INSTALLED=true
LAZYGIT_INSTALLED=false;  [ -f "$MODULES_DIR/lazygit/lazygit" ]    && LAZYGIT_INSTALLED=true
RIPGREP_INSTALLED=false;  [ -f "$MODULES_DIR/ripgrep/rg" ]         && RIPGREP_INSTALLED=true
FD_INSTALLED=false;       [ -f "$MODULES_DIR/fd/fd" ]              && FD_INSTALLED=true
ASTGREP_INSTALLED=false;  { [ -f "$MODULES_DIR/ast-grep/sg" ] || [ -f "$MODULES_DIR/ast-grep/ast-grep" ]; } && ASTGREP_INSTALLED=true
BITWARDEN_INSTALLED=false;[ -f "$MODULES_DIR/bitwarden/bw" ]       && BITWARDEN_INSTALLED=true
RCLONE_INSTALLED=false;   [ -f "$MODULES_DIR/rclone/rclone" ]      && RCLONE_INSTALLED=true
GH_INSTALLED=false;       [ -f "$MODULES_DIR/gh/gh" ]              && GH_INSTALLED=true
DELTA_INSTALLED=false;    [ -f "$MODULES_DIR/delta/delta" ]        && DELTA_INSTALLED=true
DIFFT_INSTALLED=false;    [ -f "$MODULES_DIR/difftastic/difft" ]   && DIFFT_INSTALLED=true
WIN32YANK_INSTALLED=false
[ "$IS_WSL2" = true ] && [ -f "$MODULES_DIR/win32yank/win32yank.exe" ] && WIN32YANK_INSTALLED=true

# 상태 포매팅 헬퍼(_fmts)는 _install-utils.sh 에서 로드됨

echo ""
print_sep
print_step "🚀 도구 설치를 시작합니다..."
print_info "📍 최상위 경로: $DEVTOOLS2"
print_info "📍 설치 폴더: $MODULES_DIR"
if [ "$IS_WSL2" = true ]; then print_info "📍 환경: WSL2 감지됨"; fi
echo ""
echo "📋 버전 관리 대상 도구 현황 (버전 정책: tool-versions.toml [track])"
echo ""
_cli_status() {  # <표시 이름> <toml 키> <설치 여부>
    printf "   %-16s  track: %-10s  %s\n" "$1" "$(get_track "$2" latest)" "$(_fmts "$3")"
}
_cli_status "fzf"             fzf       "$FZF_INSTALLED"
_cli_status "lazygit"         lazygit   "$LAZYGIT_INSTALLED"
_cli_status "ripgrep"         ripgrep   "$RIPGREP_INSTALLED"
_cli_status "fd-find"         fd        "$FD_INSTALLED"
_cli_status "ast-grep"        ast_grep  "$ASTGREP_INSTALLED"
_cli_status "rclone"          rclone    "$RCLONE_INSTALLED"
_cli_status "bitwarden-cli"   bitwarden "$BITWARDEN_INSTALLED"
_cli_status "gh (GitHub CLI)" gh        "$GH_INSTALLED"
_cli_status "delta"           delta     "$DELTA_INSTALLED"
_cli_status "difftastic"      difftastic "$DIFFT_INSTALLED"
if [ "$IS_WSL2" = true ]; then
    _cli_status "win32yank"   win32yank "$WIN32YANK_INSTALLED"
fi
echo ""

# ── 중복 처리 방식 (같은 버전 재설치) ─────────────────────────────
# 예전에는 이미 설치된 도구가 있으면 "삭제 후 재설치 / 유지 / 도구별 개별 확인"을 매번 물었습니다.
# 이제 새 버전 확인 여부는 아래 "새 버전 확인 방식" 질문 하나로 정하고(기존 버전 유지 / 도구별 확인), 업데이트 여부는
# 도구마다 decide_app_action 이 묻기 때문에, 이 질문에 남은 역할은 "같은 버전 다시 설치(깨진 설치 복구)"뿐이라
# 묻지 않고 기본값 keep(유지)으로 둡니다.
#   ● 복구가 필요할 때: DT2_DUPLICATE_MODE=reinstall (전체 재설치) 또는 individual (도구마다 재설치 여부 질문)
#   ● 환경변수 DT2_DUPLICATE_MODE(remove|reinstall|keep|skip|individual)는 CI·무인 실행용으로 그대로 지원합니다.
DUPLICATE_MODE="${DT2_DUPLICATE_MODE:-keep}"
if [ -n "${DT2_DUPLICATE_MODE:-}" ]; then
    print_info "환경변수(DT2_DUPLICATE_MODE) 설정 적용됨: $DUPLICATE_MODE"
fi

# ── 설치된 도구의 새 버전 확인 방식 (한 번만 질문) ──────────────────────
# 기본은 "기존 버전 유지"(설치된 도구는 새 버전 조회도 하지 않음), "도구별 새 버전 확인"을 고를 때만
# 도구마다 track 범위 안의 새 버전을 조회해 업데이트 여부를 묻습니다 (dt2_select_update_check, _install-utils.sh).
_HAS_INSTALLED=false
for _b in "$FZF_INSTALLED" "$LAZYGIT_INSTALLED" "$RIPGREP_INSTALLED" \
           "$FD_INSTALLED" "$ASTGREP_INSTALLED" "$BITWARDEN_INSTALLED" "$RCLONE_INSTALLED" "$WIN32YANK_INSTALLED" "$GH_INSTALLED" \
           "$DELTA_INSTALLED" "$DIFFT_INSTALLED"; do
    [ "$_b" = true ] && _HAS_INSTALLED=true && break
done
dt2_select_update_check "$_HAS_INSTALLED" "CLI 도구"
echo "   ℹ️  같은 버전을 다시 설치(복구)하려면 DT2_DUPLICATE_MODE=reinstall 로 실행하세요."

# (예전 "버전 설치 방식 선택(최신/지정/개별)" 질문과 일괄 최신 조회는 [track] 정책으로 대체되어 제거했습니다)

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
        gh)
            # 압축 구조: gh_<ver>_linux_<arch>/bin/gh → strip 2 로 $MODULES_DIR/gh/gh 에 설치
            if [ "$IS_ARM64" = true ]; then
                echo "https://github.com/cli/cli/releases/download/v${ver}/gh_${ver}_linux_arm64.tar.gz"
            else
                echo "https://github.com/cli/cli/releases/download/v${ver}/gh_${ver}_linux_amd64.tar.gz"
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
            # x86_64 도 ARM64 처럼 GitHub 릴리스의 버전별 파일을 씁니다 — 예전 공식 "항상 최신" 직접 다운로드 URL 은
            # 버전을 고정·비교할 수 없어 [track] 정책(고정·되돌리기)을 적용할 수 없었기 때문입니다.
            if [ "$IS_ARM64" = true ]; then
                echo "https://github.com/bitwarden/clients/releases/download/cli-v${ver}/bw-linux-arm64-${ver}.zip"
            else
                echo "https://github.com/bitwarden/clients/releases/download/cli-v${ver}/bw-linux-${ver}.zip"
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
        delta)
            # 압축 구조: delta-<ver>-<triple>/delta → strip 1 로 $MODULES_DIR/delta/delta 에 설치 (태그에 'v' 없음)
            if [ "$IS_ARM64" = true ]; then
                echo "https://github.com/dandavison/delta/releases/download/${ver}/delta-${ver}-aarch64-unknown-linux-gnu.tar.gz"
            else
                echo "https://github.com/dandavison/delta/releases/download/${ver}/delta-${ver}-x86_64-unknown-linux-musl.tar.gz"
            fi
            ;;
        difftastic)
            # 압축 구조: difft 단일 파일 → strip 0 (태그에 'v' 없음)
            if [ "$IS_ARM64" = true ]; then
                echo "https://github.com/Wilfred/difftastic/releases/download/${ver}/difft-${ver}-aarch64-unknown-linux-gnu.tar.gz"
            else
                echo "https://github.com/Wilfred/difftastic/releases/download/${ver}/difft-${ver}-x86_64-unknown-linux-musl.tar.gz"
            fi
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
        gh)
            echo "https://github.com/cli/cli/releases/download/v${ver}/gh_${ver}_checksums.txt"
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
    local toml_key="$4"       # fzf  ([track] 키 = TOML 버전 배열 키 = data/state 기록 키)
    local bin_rel_path="$5"   # fzf/fzf
    local strip_num="${6:-0}" # 0 or 1
    local installed="$7"      # $FZF_INSTALLED
    local tag_prefix="${8:-}" # GitHub 태그 접두어 (예: Bitwarden 의 "cli-v")
    local cur_ver="${9:-}"    # 실제 설치 버전(--version 등으로 알 수 있을 때), 없으면 data/state 기록 버전

    # 1. 버전 결정: [track] 범위 안의 최신 버전 (GitHub 릴리스 목록 조회 실패 시 TOML 배열 첫 항목으로 폴백)
    local pinned_ver selected_ver
    pinned_ver=$(get_pinned_version "$toml_key")   # 이 PC 에 마지막으로 설치한 버전(data/state) 또는 TOML 첫 항목
    [ -z "$cur_ver" ] && cur_ver="$pinned_ver"
    local prefix="DT2_$(echo "$id" | tr 'a-z-' 'A-Z_')"
    selected_ver=""
    # 기존 버전 유지 모드면 설치된 도구는 버전 목록 조회(네트워크)도 하지 않습니다 (dt2_should_check_update)
    if dt2_should_check_update "$installed" "$prefix"; then
        selected_ver=$(resolve_track_version "$toml_key" latest list_github_release_versions "$repo" "$tag_prefix")
    fi
    [ -z "$selected_ver" ] && selected_ver=$(_get_toml_version "$toml_key")

    # 2. 설치/업데이트/건너뛰기 결정 — 공용 함수 decide_app_action (필수 도구라 미설치면 묻지 않고 설치,
    #    설치됨 + track 범위 안에 새 버전 → 업데이트 여부 확인(기본 Y), 무인 실행은 기존 유지)
    #    업데이트하지 않은 경우에는 중복 처리 방식(재설치 등)을 기존처럼 존중합니다.
    local action
    decide_app_action "$id" "$installed" "$cur_ver" "$selected_ver" "A" "$prefix"
    action="$DT2_APP_ACTION"
    if [ "$action" = "skip" ] && [ "$installed" = true ] && [ "$(_resolve_action true "$id")" = "reinstall" ]; then
        action="reinstall"
    fi

    # (건너뛰는 경우의 안내는 decide_app_action 이 출력)
    [ "$action" = "skip" ] && return 0
    echo "📦 $id $selected_ver 설치..."

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
    # 체크섬 파일을 배포하지 않는 도구(fd, ast-grep, Bitwarden ARM64, win32yank)는
    # GitHub API 의 자산 SHA256 으로 검증합니다(조회 실패 시에만 경고 후 검증 없이 설치).
    if [ -z "$dl_checksum" ] && [[ "$dl_url" == https://github.com/* ]]; then
        local _gh_tag
        _gh_tag=$(echo "$dl_url" | sed -E 's#^https://github.com/[^/]+/[^/]+/releases/download/([^/]+)/.*#\1#')
        dl_checksum=$(github_asset_sha256 "$repo" "$_gh_tag" "$(basename "$dl_url")")
        if [ -z "$dl_checksum" ]; then
            print_warn "$id SHA256 을 GitHub API 에서 조회하지 못해 체크섬 검증 없이 설치합니다."
        fi
    fi

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
        _CLI_FAILED+=("$id")
    fi
}

# ─────────────────────────────────────────────────────────────────
# 각 CLI 도구 순차 설치 실행
# ─────────────────────────────────────────────────────────────────
# 설치에 실패한 도구 목록 (마지막에 요약 출력)
# 도구 하나가 실패해도 나머지 설치는 계속하므로 종료 코드는 바꾸지 않고, 실패 내역을 눈에 띄게 알립니다.
_CLI_FAILED=()
install_cli_tool "fzf" "fzf - 터미널용 퍼지 파인더" "junegunn/fzf" "fzf" "fzf/fzf" 0 "$FZF_INSTALLED"
install_cli_tool "lazygit" "lazygit - 터미널 UI Git 도구" "jesseduffield/lazygit" "lazygit" "lazygit/lazygit" 0 "$LAZYGIT_INSTALLED"
install_cli_tool "ripgrep" "ripgrep (rg) - 코드 검색 도구" "BurntSushi/ripgrep" "ripgrep" "ripgrep/rg" 1 "$RIPGREP_INSTALLED"
install_cli_tool "fd" "fd-find (fd) - 파일 검색 도구" "sharkdp/fd" "fd" "fd/fd" 1 "$FD_INSTALLED"
install_cli_tool "ast-grep" "ast-grep (sg) - 구조적 코드 검색 도구" "ast-grep/ast-grep" "ast_grep" "ast-grep/ast-grep" 0 "$ASTGREP_INSTALLED"
# Bitwarden: 실제 설치 버전을 bw --version 으로 비교 (x86_64 는 예전 "항상 최신" 설치라 data/state 기록이 없음)
_bw_cur=""; [ "$BITWARDEN_INSTALLED" = true ] && _bw_cur=$("$MODULES_DIR/bitwarden/bw" --version 2>/dev/null | head -n 1 | tr -d '[:space:]' || true)
install_cli_tool "bitwarden" "Bitwarden CLI (bw)" "bitwarden/clients" "bitwarden" "bitwarden/bw" 0 "$BITWARDEN_INSTALLED" "cli-v" "$_bw_cur"
install_cli_tool "rclone" "rclone - 클라우드 동기화 도구" "rclone/rclone" "rclone" "rclone/rclone" 0 "$RCLONE_INSTALLED"
# gh (GitHub CLI): 하위 호환이 좋고 에이전트가 최신 기능을 가정하므로 track "latest" (실제 설치 버전은 gh --version)
_gh_cur=""; [ "$GH_INSTALLED" = true ] && _gh_cur=$("$MODULES_DIR/gh/gh" --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
install_cli_tool "gh" "gh - GitHub CLI (PR·이슈·Actions, 모든 에이전트 공용)" "cli/cli" "gh" "gh/gh" 2 "$GH_INSTALLED" "" "$_gh_cur"
# delta / difftastic: lazygit·git diff 표시 도구 (실제 설치 버전은 --version 으로 비교)
#   ● delta: 문법 색상·줄 안 단어 강조·좌우 비교 — lazygit 기본 pager 와 git 의 core.pager
#   ● difftastic(difft): 문법 트리 기준 구조 비교 — lazygit 의 '|' 전환 목록과 git dft 별칭
#   ● 둘 다 없거나 실행에 실패해도 lazygit·git 은 예전 일반 diff 로 자동 폴백합니다(.config/lazygit/config.yml, 1.setup-env.sh)
_delta_cur=""; [ "$DELTA_INSTALLED" = true ] && _delta_cur=$("$MODULES_DIR/delta/delta" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
install_cli_tool "delta" "delta - git diff 표시 도구 (문법 색상·좌우 비교)" "dandavison/delta" "delta" "delta/delta" 1 "$DELTA_INSTALLED" "" "$_delta_cur"
_difft_cur=""; [ "$DIFFT_INSTALLED" = true ] && _difft_cur=$("$MODULES_DIR/difftastic/difft" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
install_cli_tool "difftastic" "difftastic (difft) - 구조 기준 diff 도구" "Wilfred/difftastic" "difftastic" "difftastic/difft" 0 "$DIFFT_INSTALLED" "" "$_difft_cur"

if [ "$IS_WSL2" = true ]; then
    install_cli_tool "win32yank" "win32yank - 클립보드 공유 도구" "equalsraf/win32yank" "win32yank" "win32yank/win32yank.exe" 0 "$WIN32YANK_INSTALLED"
    if [ -d "$MODULES_DIR/win32yank" ]; then
        ensure_path_in_bashrc "$MODULES_DIR/win32yank"
    fi
fi

# ─────────────────────────────────────────────────────────────────
# 실행 권한 부여 및 검증
# ─────────────────────────────────────────────────────────────────
echo "🔐 실행 권한 부여 및 검증 중..."
for cmd in "$MODULES_DIR/ripgrep/rg" "$MODULES_DIR/fd/fd" "$MODULES_DIR/fzf/fzf" \
           "$MODULES_DIR/lazygit/lazygit" "$MODULES_DIR/ast-grep/sg" "$MODULES_DIR/ast-grep/ast-grep" "$MODULES_DIR/bitwarden/bw" "$MODULES_DIR/rclone/rclone" \
           "$MODULES_DIR/gh/gh"; do
    if [ -s "$cmd" ]; then
        chmod +x "$cmd"
    else
        echo "⚠️  경고: $cmd 파일이 비어있거나 다운로드에 실패했습니다."
    fi
done

if [ ${#_CLI_FAILED[@]} -gt 0 ]; then
    print_warn "설치에 실패한 도구 ${#_CLI_FAILED[@]}개: ${_CLI_FAILED[*]}"
    print_info "  네트워크 확인 후 이 스크립트를 다시 실행하면 실패한 도구만 다시 설치합니다."
else
    print_done "모든 바이너리 도구($ARCH) 설치가 완료되었습니다!"
fi
echo ""

# ─────────────────────────────────────────────────────────────────
# GitHub 로그인 연결 (Bitwarden PAT → git 자격 증명 + gh CLI)
# ─────────────────────────────────────────────────────────────────
# - 예전에는 프로젝트 설정 스크립트(setup-goono-eln.sh 등)가 저장소를 clone 할 때만 GitHub 로그인을 설정했습니다.
#   이제 gh 설치와 함께 여기서 한 번 설정하고, 프로젝트 스크립트는 로그인이 없거나 실패할 때만 폴백합니다
#   (bw-lib 의 bw_git_clone_with_fallback).
# - 구현은 프로젝트 설정 스크립트와 같은 bw-lib(scripts/fzf/bw-lib)의 bw_setup_github_auth 를 그대로 씁니다.
#   (폴더 이름은 fzf 지만 Bitwarden 세션·항목 조회·git 설정 함수만 쓰므로 fzf 없이 동작)
#   ● git user.name/email + ~/.git-credentials(PAT, WSL 이면 Windows 쪽 동기화 포함) + gh CLI 로그인
#   ● 이미 로그인되어 있으면 Bitwarden 잠금 해제 없이 건너뜀 / Bitwarden 미로그인이면 그 자리에서 bw login
# - DT2_GITHUB_AUTH=y|n 로 묻지 않고 지정 가능. 무인 실행에서는 건너뜁니다(DT2_GITHUB_AUTH=y 로 강제).
# - Bitwarden 항목 이름: BW_DEFAULT_PAT_ITEM (기본값 github.com-main, 사용자 지정 필드 "PAT" 에 GitHub PAT)
echo "---------------------------------------------------------------------------"
echo "🔑 GitHub 로그인 연결 (Bitwarden PAT → git push/pull · gh CLI)"
# 방금 설치한 gh·bw 를 이 셸에서 바로 쓸 수 있도록 PATH 앞에 둡니다(env.sh 반영은 새 셸부터).
export PATH="$MODULES_DIR/gh:$MODULES_DIR/bitwarden:$PATH"
_dt2_gh_auth_choice="${DT2_GITHUB_AUTH:-}"
if [ "${_dt2_gh_auth_choice,,}" = "n" ]; then
    print_skip "DT2_GITHUB_AUTH=n → GitHub 로그인 연결을 건너뜁니다."
else
    # 공통 모듈과 같은 규칙: 로컬 저장소에서 직접 실행했을 때만(스크립트 옆에 _common.sh 가 있음) 같은 체크아웃의
    # bw-lib 을 쓰고, 스트리밍 실행은 같은 커밋(DT2_REF)의 원격 파일을 씁니다.
    # (예전에는 $DEVTOOLS2 로컬 저장소를 먼저 봐서, 로컬이 오래되어 있으면 옛 로그인 흐름이 실행될 수 있었음)
    _bw_lib="$_SCRIPT_DIR/../../fzf/bw-lib"
    _bw_lib_ok=false
    if [ -f "$_SCRIPT_DIR/_common.sh" ] && [ -f "$_bw_lib" ]; then
        # shellcheck disable=SC1090
        source "$_bw_lib" && _bw_lib_ok=true
    else
        # shellcheck disable=SC1090
        source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' \
            "https://raw.githubusercontent.com/devers2/_devtools2/${DT2_REF:-main}/scripts/fzf/bw-lib") && _bw_lib_ok=true
    fi
    if [ "$_bw_lib_ok" != true ]; then
        print_warn "bw-lib 을 불러오지 못해 GitHub 로그인 연결을 건너뜁니다. (나중에 프로젝트 설정 스크립트가 폴백으로 설정)"
    elif bw_git_credentials_exist "github.com" && bw_gh_auth_ok "github.com"; then
        print_skip "GitHub 로그인이 이미 설정되어 있습니다. (git 자격 증명 + gh CLI)"
    elif [ "${_dt2_gh_auth_choice,,}" != "y" ] && dt2_is_noninteractive; then
        print_skip "비대화형 실행이라 GitHub 로그인 연결을 건너뜁니다 (DT2_GITHUB_AUTH=y 로 강제 가능)."
    elif [ "${_dt2_gh_auth_choice,,}" = "y" ] || prompt_confirm "   👉 Bitwarden PAT 로 GitHub 로그인(git push/pull · gh CLI)을 설정하시겠습니까?" "Y"; then
        if ! bw_setup_github_auth; then
            print_warn "GitHub 로그인 연결에 실패했습니다. 나중에 프로젝트 설정 스크립트가 폴백으로 설정하거나, 직접 'gh auth login' 하세요."
        fi
    else
        print_skip "GitHub 로그인 연결을 건너뜁니다. (프로젝트 설정 스크립트가 clone 할 때 폴백으로 설정)"
    fi
fi
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
(sudo apt-get update -qq >$DT2_TMP/_apt_update.log 2>&1) &
_apt_upd_pid=$!
show_spinner "$_apt_upd_pid"
wait "$_apt_upd_pid" 2>/dev/null || true
rm -f $DT2_TMP/_apt_update.log 2>/dev/null
echo " 완료"

dt2_sudo_auth || true   # 비밀번호 질문이 스피너에 가려지지 않도록 먼저 인증
echo -n "   - apt 패키지(build-essential, libreadline-dev, git, trash-cli, xclip, wl-clipboard, sqlite3) 설치 중..."
# ⚠️ 이 줄은 포터블 원칙의 예외입니다(전체 목록/이유는 0.init-devtools2.sh 상단 메모 참고).
# - build-essential/libreadline-dev: hererocks(아래 7번) 및 nvim-treesitter :TSInstall이
#   C 소스를 직접 컴파일하는 데 필요 — 컴파일러라 포터블 바이너리로 대체 불가능.
# - xclip/wl-clipboard: 사실 WSL2에서는 안 씀(options.lua가 win32yank/PowerShell clip.exe를
#   우선 사용) — 네이티브 리눅스 전용 폴백이라 WSL2 한정이면 빼도 되는 항목.
# - sqlite3/libsqlite3-dev: Neovim Snacks.picker의 frecency(최근·자주 쓴 파일 우선순위)/히스토리 저장용.
#   없어도 파일 기반으로 폴백되어 동작은 하지만, 세션이 쌓일수록 느려지고 :checkhealth snacks에
#   경고가 뜸. lazy.nvim/Mason 대상이 아닌 OS 공유 라이브러리라 여기 apt 등급에 포함(버전 고정 없음).
(sudo apt-get install -y build-essential libreadline-dev git trash-cli xclip wl-clipboard sqlite3 libsqlite3-dev -qq >$DT2_TMP/_apt_install.log 2>&1) &
_apt_inst_pid=$!
show_spinner "$_apt_inst_pid"
_apt_inst_ec=0
wait "$_apt_inst_pid" 2>/dev/null || _apt_inst_ec=$?
if [ "$_apt_inst_ec" -eq 0 ]; then
    rm -f $DT2_TMP/_apt_install.log 2>/dev/null
    echo " 완료"
    print_done "apt 패키지 설치 완료"
else
    echo " ⚠️  실패"
    print_error "apt 패키지 설치 중 오류가 발생했습니다. 상세 로그:"
    cat $DT2_TMP/_apt_install.log 2>/dev/null || true
    rm -f $DT2_TMP/_apt_install.log 2>/dev/null
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

# 이미 구성되어 있으면(lua·luarocks 실행 파일 존재) Lua 를 다시 컴파일하지 않습니다.
# 다시 만들려면 중복 처리 방식에서 '삭제 후 재설치'를 고르거나 DT2_DUPLICATE_MODE=reinstall 로 실행하세요.
_hero_ec=0
if [ -x "$HEREROCKS_DIR/bin/lua" ] && [ -x "$HEREROCKS_DIR/bin/luarocks" ] \
    && [ "$DUPLICATE_MODE" != "remove" ] && [ "$DUPLICATE_MODE" != "reinstall" ]; then
    echo "   ⏭️  [건너뜀] hererocks(Lua 5.1 / Luarocks)가 이미 구성되어 있습니다."
    _hero_ec=skip
else
    echo -n "   ⚙️ hererocks 구성 중 (Lua 5.1 / Luarocks 최신)..."
    (hererocks . -l 5.1 -r latest >$DT2_TMP/_hererocks_install.log 2>&1) &
    _hero_pid=$!
    show_spinner "$_hero_pid"
    wait "$_hero_pid" 2>/dev/null || _hero_ec=$?
fi
if [ "$_hero_ec" = "skip" ]; then
    :
elif [ "$_hero_ec" -eq 0 ]; then
    rm -f $DT2_TMP/_hererocks_install.log 2>/dev/null
    echo " 완료"
    print_done "hererocks / Lua 환경 구성 완료"
else
    echo " ⚠️  실패"
    print_error "hererocks 구성 중 오류가 발생했습니다. 상세 로그:"
    cat $DT2_TMP/_hererocks_install.log 2>/dev/null || true
    rm -f $DT2_TMP/_hererocks_install.log 2>/dev/null
fi
echo ""

# ==============================================================================
# 7-1. Neovim Python provider (pynvim 전용 가상환경)
# ==============================================================================
# Neovim 의 Python provider 는 Python 으로 작성된 Neovim 플러그인(remote plugin)을 실행하는 연결 고리입니다.
# Python 개발 자체(LSP basedpyright·ruff, 디버거 debugpy, 테스트 neotest-python)와는 별개이며, 지금은 쓰는
# 플러그인이 없지만 나중에 쓸 수 있도록 미리 준비합니다(:checkhealth vim.provider 경고도 사라짐).
#   ● 시스템·프로젝트 Python 에 pynvim 을 섞지 않도록 전용 가상환경($DEVTOOLS2/data/nvim/python-provider)에 설치
#   ● 기준 Python 은 DevTools2 Python 3.14 (패치 업데이트는 같은 폴더에서 교체되어 가상환경이 그대로 동작)
#   ● Neovim 은 config/options.lua 의 vim.g.python3_host_prog 로 이 가상환경을 씁니다
#   ● Node provider(neovim npm 패키지)는 2.install-core-tools.sh 의 npm 전역 패키지(data/.npm-packages)에 포함
_NVIM_PYPROV="$DEVTOOLS2/data/nvim/python-provider"
_NVIM_PYBASE="$DEVTOOLS2/modules/python/python-314/bin/python3"
echo "🐍 7-1. Neovim Python provider(pynvim) 구성 중..."
if [ -x "$_NVIM_PYPROV/bin/python" ] && "$_NVIM_PYPROV/bin/python" -c "import pynvim" >/dev/null 2>&1; then
    echo "   ⏭️  [건너뜀] pynvim 가상환경이 이미 구성되어 있습니다: $_NVIM_PYPROV"
elif [ -x "$_NVIM_PYBASE" ]; then
    echo -n "   ⚙️ pynvim 가상환경 만드는 중..."
    ( "$_NVIM_PYBASE" -m venv "$_NVIM_PYPROV" && "$_NVIM_PYPROV/bin/python" -m pip install -q --upgrade pip pynvim ) \
        >"$DT2_TMP/_pynvim.log" 2>&1 &
    show_spinner $!
    if wait $! && "$_NVIM_PYPROV/bin/python" -c "import pynvim" >/dev/null 2>&1; then
        echo " 완료"
    else
        echo " ⚠️  실패 (로그: $DT2_TMP/_pynvim.log) — Python 플러그인을 쓰지 않으면 영향 없음"
    fi
else
    echo "   ⏭️  [건너뜀] DevTools2 Python 3.14 가 없어 pynvim 가상환경을 만들지 않습니다 (2.install-core-tools.sh 먼저 실행)."
fi
echo ""

# ==============================================================================
# 8. Gradle DAP (디버거 Attach) 전역 설정
# (구현부: scripts/linux/dev-env/_install-utils.sh configure_gradle_dap)
# ==============================================================================
configure_gradle_dap

print_sep
print_step "🎉 모든 도구 설치가 완료되었습니다!"
echo ""
echo "설정 확인 명령어:"
echo "    hererocks --version"
echo "    ls -F \"$DEVTOOLS2/data/nvim/lazy-rocks/hererocks/bin/\""
print_sep
echo ""
