#!/bin/bash
# ==============================================================================
# Gittyup & Meld 설치 및 Git Diff/Merge 연동 스크립트 (tool.setup-gittyup.sh)
#
# 주요 기능:
#   1. Linux 네이티브 환경: 공식 최신 AppImage 다운로드 및 $DEVTOOLS2/modules/gittyup 포터블 설치
#      Meld 네이티브 apt 패키지 설치
#   2. WSL2 환경: Windows 네이티브 gittyup.exe 및 meld.exe 탐색, WSL 전용 경로 변환(wslpath) 브릿지 래퍼 생성
#   3. 설정 심볼릭 링크: $DEVTOOLS2/.config/gittyup -> ~/.config/Gittyup 심볼릭 링크 연동
#   4. Git 글로벌 difftool 및 mergetool 로 meld 자동 등록 (Gittyup 내 3-Way 병합 도구 원클릭 연동)
#   5. Gittyup & Meld 다크 테마(Dark.lua, meld-dark) 및 폰트(D2Coding ligature, 11.5pt) 동기화
#
# ------------------------------------------------------------------------------
# ⚠️ [AI / 개발자 필독 - 설계 절대 원칙]
# 100% 온라인 전용 스트리밍: 서브스크립트는 무조건 GitHub main 원격 raw URL에서
# 직접 스트리밍으로 실행됩니다. 순수 UTF-8 NoBOM으로 유지되어야 합니다.
# ------------------------------------------------------------------------------
# ==============================================================================

set -euo pipefail

if [ -z "${DEVTOOLS2:-}" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
    DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../.." 2>/dev/null || echo "/var/opt/_devtools2")
fi

if [ ! -d "$DEVTOOLS2" ]; then
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

print_banner "🔀 Gittyup & Meld (Git GUI & 3-Way Merge) 설치 및 연동 (tool.setup-gittyup.sh)"

# ==============================================================================
# [Step 1] 환경별 바이너리 설치 및 PATH 연동
# ==============================================================================
GITTYUP_MODULE_DIR="$DEVTOOLS2/modules/gittyup"
mkdir -p "$GITTYUP_MODULE_DIR/bin"

if [ "${IS_WSL2:-false}" = true ]; then
    print_info "[WSL2] Windows 네이티브 Gittyup & Meld 연동을 구성합니다..."

    ensure_wsl_interop
    _win_user=$(get_win_userprofile || true)

    # 1) Windows gittyup.exe 탐색
    _win_gittyup=""
    for _p in \
        "/mnt/c/Program Files/Gittyup/bin/gittyup.exe" \
        "/mnt/c/Program Files/Gittyup/gittyup.exe" \
        "/mnt/c/Program Files (x86)/Gittyup/bin/gittyup.exe" \
        "/mnt/c/Program Files (x86)/Gittyup/gittyup.exe" \
        "$_win_user/AppData/Local/Programs/Gittyup/bin/gittyup.exe" \
        "$_win_user/AppData/Local/Programs/Gittyup/gittyup.exe" \
        "/mnt/c/Users/${USER:-}/AppData/Local/Programs/Gittyup/bin/gittyup.exe" \
        "/mnt/c/Users/${USER:-}/AppData/Local/Programs/Gittyup/gittyup.exe"; do
        if [ -f "$_p" ]; then
            _win_gittyup="$_p"
            break
        fi
    done

    if [ -z "$_win_gittyup" ]; then
        _win_gittyup="/mnt/c/Program Files/Gittyup/bin/gittyup.exe"
        print_warn "Windows 호스트에 gittyup.exe 가 아직 감지되지 않았습니다."
        print_info "  기본 경로($_win_gittyup)를 기준으로 WSL 브릿지 래퍼를 선제 생성합니다."
        print_info "  Windows 설치 스크립트(tool.setup-gittyup.ps1) 또는 winget으로 설치를 완료하세요:"
        print_info "    winget install --id Murmele.Gittyup"
    else
        print_info "감지된 Windows Gittyup 실행 파일: $_win_gittyup"
    fi

    # WSL2 전용 gittyup 브릿지 래퍼 생성
    _gittyup_wrapper="$GITTYUP_MODULE_DIR/bin/gittyup"
    cat <<EOF > "$_gittyup_wrapper"
#!/bin/bash
# ==============================================================================
# WSL2 -> Windows Gittyup CLI Bridge Wrapper
# ==============================================================================
WIN_GITTYUP="$_win_gittyup"

if [ ! -f "\$WIN_GITTYUP" ]; then
    _win_user="\${WIN_USERPROFILE:-}"
    if [ -z "\$_win_user" ] && command -v cmd.exe >/dev/null 2>&1; then
        _raw_home=\$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' || true)
        [ -n "\$_raw_home" ] && command -v wslpath >/dev/null 2>&1 && _win_user=\$(wslpath "\$_raw_home" 2>/dev/null || true)
    fi

    if [ -f "/mnt/c/Program Files/Gittyup/bin/gittyup.exe" ]; then
        WIN_GITTYUP="/mnt/c/Program Files/Gittyup/bin/gittyup.exe"
    elif [ -f "/mnt/c/Program Files/Gittyup/gittyup.exe" ]; then
        WIN_GITTYUP="/mnt/c/Program Files/Gittyup/gittyup.exe"
    elif [ -f "/mnt/c/Program Files (x86)/Gittyup/bin/gittyup.exe" ]; then
        WIN_GITTYUP="/mnt/c/Program Files (x86)/Gittyup/bin/gittyup.exe"
    elif [ -n "\$_win_user" ] && [ -f "\$_win_user/AppData/Local/Programs/Gittyup/bin/gittyup.exe" ]; then
        WIN_GITTYUP="\$_win_user/AppData/Local/Programs/Gittyup/bin/gittyup.exe"
    else
        echo "[오류] Windows Gittyup (gittyup.exe)을 찾을 수 없습니다: \$WIN_GITTYUP" >&2
        echo "  winget install --id Murmele.Gittyup 으로 설치하세요." >&2
        exit 1
    fi
fi

args=()
for arg in "\$@"; do
    if [ -e "\$arg" ]; then
        args+=("\$(wslpath -w "\$arg" 2>/dev/null || echo "\$arg")")
    else
        args+=("\$arg")
    fi
done

"\$WIN_GITTYUP" "\${args[@]}" &
EOF
    chmod +x "$_gittyup_wrapper"

    # 2) Windows meld.exe 탐색 및 래퍼 생성
    _win_meld=""
    for _mp in \
        "/mnt/c/Program Files/Meld/Meld.exe" \
        "/mnt/c/Program Files/Meld/meld.exe" \
        "/mnt/c/Program Files (x86)/Meld/Meld.exe" \
        "/mnt/c/Program Files (x86)/Meld/meld.exe" \
        "$_win_user/AppData/Local/Programs/Meld/Meld.exe" \
        "$_win_user/AppData/Local/Programs/Meld/meld.exe" \
        "/mnt/c/Users/${USER:-}/AppData/Local/Programs/Meld/Meld.exe" \
        "/mnt/c/Users/${USER:-}/AppData/Local/Programs/Meld/meld.exe"; do
        if [ -f "$_mp" ]; then
            _win_meld="$_mp"
            break
        fi
    done

    if [ -n "$_win_meld" ]; then
        _meld_wrapper="$GITTYUP_MODULE_DIR/bin/meld"
        cat <<EOF > "$_meld_wrapper"
#!/bin/bash
# ==============================================================================
# WSL2 -> Windows Meld CLI Bridge Wrapper
# ==============================================================================
WIN_MELD="$_win_meld"

args=()
for arg in "\$@"; do
    if [ -e "\$arg" ]; then
        args+=("\$(wslpath -w "\$arg" 2>/dev/null || echo "\$arg")")
    else
        args+=("\$arg")
    fi
done

"\$WIN_MELD" "\${args[@]}"
EOF
        chmod +x "$_meld_wrapper"
    fi

    ensure_path_in_bashrc "$GITTYUP_MODULE_DIR/bin"
    print_done "WSL2 Gittyup & Meld 브릿지 래퍼 생성 완료: $GITTYUP_MODULE_DIR/bin"

else
    # Linux 네이티브 환경: $DEVTOOLS2/modules/gittyup 에 포터블 AppImage 설치
    print_info "Gittyup 최신 릴리스 확인 중..."
    _gittyup_ver=$(curl -sSfL --max-time 10 https://api.github.com/repos/Murmele/Gittyup/releases/latest 2>/dev/null | grep -oP '"tag_name":\s*"v?\K[0-9.]+' | head -n 1 || true)
    if [ -z "$_gittyup_ver" ]; then
        _gittyup_ver="1.4.0"
    fi
    print_info "최신 안정 릴리스: v$_gittyup_ver"

    _installed_ver=""
    if [ -x "$GITTYUP_MODULE_DIR/bin/gittyup" ]; then
        _installed_ver=$("$GITTYUP_MODULE_DIR/bin/gittyup" --version 2>/dev/null | grep -oE '[0-9.]+' | head -n 1 || true)
    fi

    if [ -z "$_installed_ver" ] || [ "$_installed_ver" != "$_gittyup_ver" ]; then
        _appimage_url="https://github.com/Murmele/Gittyup/releases/download/gittyup_v${_gittyup_ver}/Gittyup-x86_64.AppImage"
        _appimage_tmp="$DT2_TMP/Gittyup.AppImage"

        if download_with_progress "$_appimage_url" "$_appimage_tmp" "Gittyup v${_gittyup_ver} AppImage"; then
            mv "$_appimage_tmp" "$GITTYUP_MODULE_DIR/bin/gittyup"
            chmod +x "$GITTYUP_MODULE_DIR/bin/gittyup"
            print_done "Gittyup AppImage 포터블 설치 완료: $GITTYUP_MODULE_DIR/bin/gittyup"
        else
            print_warn "Gittyup AppImage 다운로드 실패 - 수동 설치를 권장합니다."
        fi
    else
        print_skip "Gittyup v$_installed_ver 이 이미 최신 버전입니다."
    fi

    # Meld 네이티브 패키지 설치
    if ! command -v meld >/dev/null 2>&1; then
        print_info "Meld 3-Way 머지 도구를 apt로 설치합니다..."
        sudo_exec apt-get update -qq && sudo_exec apt-get install -y -qq meld || print_warn "Meld 설치 실패 (나중에 수동 설치: sudo apt install meld)"
    else
        print_skip "Meld 가 이미 설치되어 있습니다."
    fi

    ensure_path_in_bashrc "$GITTYUP_MODULE_DIR/bin"
fi

# ==============================================================================
# [Step 2] 설정 파일 심볼릭 링크 연동 ($DEVTOOLS2/.config/gittyup -> ~/.config/Gittyup)
# ==============================================================================
print_info "Gittyup 설정 파일 심볼릭 링크 연동 중..."
GITTYUP_CONFIG_SRC="$DEVTOOLS2/.config/gittyup"

if [ -d "$GITTYUP_CONFIG_SRC" ]; then
    mkdir -p "$HOME/.config"
    if [ -d "$HOME/.config/Gittyup" ] && [ ! -L "$HOME/.config/Gittyup" ]; then
        mv "$HOME/.config/Gittyup" "$HOME/.config/Gittyup.bak.$(date +%Y%m%d%H%M%S)"
    fi
    ln -sfn "$GITTYUP_CONFIG_SRC" "$HOME/.config/Gittyup"
    print_done "설정 파일 심볼릭 링크 완료: $HOME/.config/Gittyup -> $GITTYUP_CONFIG_SRC"
fi

# Meld 다크 테마 및 폰트 설정 (gsettings/dconf 지원 환경인 경우)
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.meld style-scheme 'meld-dark' 2>/dev/null || true
    gsettings set org.gnome.meld use-custom-font true 2>/dev/null || true
    gsettings set org.gnome.meld custom-font 'D2Coding ligature 11.5' 2>/dev/null || true
fi

# ==============================================================================
# [Step 3] Git 전역 diff.tool 및 merge.tool 로 Meld 등록
# ==============================================================================
print_info "Git 글로벌 mergetool 및 difftool 로 Meld 등록 중..."
git config --global merge.tool meld
git config --global diff.tool meld
git config --global mergetool.prompt false
git config --global difftool.prompt false
print_done "Git 글로벌 설정 완료: merge.tool=meld, diff.tool=meld"

print_success "Gittyup & Meld 설치, 설정 심볼릭 링크 및 연동 완료!"
