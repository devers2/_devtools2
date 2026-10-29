#!/bin/bash
# ==============================================================================
# Sublime Merge 설치 및 Git Diff/Merge 연동 스크립트 (tool.setup-sublime-merge.sh)
#
# 주요 기능:
#   1. Linux 네이티브 환경: 공식 최신 tar.xz 다운로드 및 $DEVTOOLS2/modules/sublime-merge 포터블 스마트 설치 ([y/N], 기본값 N)
#   2. WSL2 환경: Windows 네이티브 smerge.exe 탐색 및 WSL 전용 경로 변환(wslpath) 브릿지 래퍼 생성
#   3. $DEVTOOLS2/.config/sublime-merge 설정 파일 자동 링크/동기화 (다크 Monokai, 11.5pt)
#   4. Git 글로벌 difftool 및 mergetool 로 smerge 자동 등록
#   5. Linux 데스크탑 환경: .desktop 앱 바로가기 및 GNOME 커스텀 키바인딩(Ctrl+Alt+G) 등록
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

print_banner "🔀 Sublime Merge (Git Diff & Merge) 설치 및 연동 (tool.setup-sublime-merge.sh)"

# 사용자 의사 확인 환경변수 (비대화형 실행 지원)
if [ -n "${DT2_SMERGE_CHOICE:-}" ]; then
    [ "${DT2_SMERGE_CHOICE,,}" = "n" ] && { print_skip "Sublime Merge 설치를 건너뜁니다."; exit 0; }
fi

# ==============================================================================
# [Step 1] 환경별 바이너리 설치 및 PATH 연동
# ==============================================================================
SMERGE_MODULE_DIR="$DEVTOOLS2/modules/sublime-merge"
mkdir -p "$SMERGE_MODULE_DIR"

if [ "${IS_WSL2:-false}" = true ]; then
    print_info "[WSL2] Windows 네이티브 Sublime Merge 연동을 구성합니다..."
    
    ensure_wsl_interop
    _win_user=$(get_win_userprofile || true)

    _win_smerge=""
    if command -v cmd.exe >/dev/null 2>&1; then
        _where_out=$(cmd.exe /c "where smerge.exe" 2>/dev/null | tr -d '\r' | head -n 1 || true)
        if [ -n "$_where_out" ] && command -v wslpath >/dev/null 2>&1; then
            _conv=$(wslpath "$_where_out" 2>/dev/null || true)
            [ -f "$_conv" ] && _win_smerge="$_conv"
        fi
    fi

    if [ -z "$_win_smerge" ]; then
        for _p in \
            "/mnt/c/Program Files/Sublime Merge/smerge.exe" \
            "/mnt/c/Program Files (x86)/Sublime Merge/smerge.exe" \
            "$_win_user/AppData/Local/Programs/Sublime Merge/smerge.exe" \
            "/mnt/c/Users/${USER:-}/AppData/Local/Programs/Sublime Merge/smerge.exe" \
            $_win_user/AppData/Local/Microsoft/WinGet/Packages/SublimeHQ.SublimeMerge*/smerge.exe \
            /mnt/c/Users/${USER:-}/AppData/Local/Microsoft/WinGet/Packages/SublimeHQ.SublimeMerge*/smerge.exe; do
            if [ -f "$_p" ]; then
                _win_smerge="$_p"
                break
            fi
        done
    fi

    # Windows 실행 파일이 아직 없더라도 기본 설치 경로로 래퍼를 생성해 둠 (나중에 winget 설치 시 즉시 작동)
    if [ -z "$_win_smerge" ]; then
        _win_smerge="/mnt/c/Program Files/Sublime Merge/smerge.exe"
        print_warn "Windows 호스트에 smerge.exe 가 아직 감지되지 않았습니다."
        print_info "  기본 경로($_win_smerge)를 기준으로 WSL 브릿지 래퍼를 선제 생성합니다."
        print_info "  Windows 설치 스크립트(setup-devtools2-wsl.ps1) 또는 winget으로 설치를 완료하세요:"
        print_info "    winget install --id SublimeHQ.SublimeMerge"
    else
        print_info "감지된 Windows Sublime Merge 실행 파일: $_win_smerge"
    fi

    # WSL2 전용 smerge 브릿지 래퍼 생성
    # - Linux POSIX 경로(/home/...)를 Windows UNC 경로(\\wsl$\...)로 wslpath 변환하여 전달
    # - git mergetool 호출 시 종료 대기(wait)를 위해 백그라운드(&)가 아닌 동기 실행
    mkdir -p "$SMERGE_MODULE_DIR/bin"
    _wrapper_path="$SMERGE_MODULE_DIR/bin/smerge"
    
    cat <<EOF > "$_wrapper_path"
#!/bin/bash
# ==============================================================================
# WSL2 -> Windows Sublime Merge CLI Bridge Wrapper
# Generated by tool.setup-sublime-merge.sh
# ==============================================================================
WIN_SMERGE="$_win_smerge"

if [ ! -f "\$WIN_SMERGE" ]; then
    # 대체 경로 2차 탐색
    _win_user="\${WIN_USERPROFILE:-}"
    if [ -z "\$_win_user" ] && command -v cmd.exe >/dev/null 2>&1; then
        _raw_home=\$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' || true)
        [ -n "\$_raw_home" ] && command -v wslpath >/dev/null 2>&1 && _win_user=\$(wslpath "\$_raw_home" 2>/dev/null || true)
    fi

    if [ -f "/mnt/c/Program Files/Sublime Merge/smerge.exe" ]; then
        WIN_SMERGE="/mnt/c/Program Files/Sublime Merge/smerge.exe"
    elif [ -f "/mnt/c/Program Files (x86)/Sublime Merge/smerge.exe" ]; then
        WIN_SMERGE="/mnt/c/Program Files (x86)/Sublime Merge/smerge.exe"
    elif [ -n "\$_win_user" ] && [ -f "\$_win_user/AppData/Local/Programs/Sublime Merge/smerge.exe" ]; then
        WIN_SMERGE="\$_win_user/AppData/Local/Programs/Sublime Merge/smerge.exe"
    else
        echo "[오류] Windows Sublime Merge (smerge.exe)를 찾을 수 없습니다: \$WIN_SMERGE" >&2
        echo "  Windows PowerShell 에서 winget install --id SublimeHQ.SublimeMerge 로 설치하세요." >&2
        exit 1
    fi
fi

# 인자 변환: 존재하는 Linux 파일/디렉토리 경로는 Windows UNC/절대 경로로 변환
args=()
for arg in "\$@"; do
    if [ -e "\$arg" ]; then
        args+=("\$(wslpath -w "\$arg" 2>/dev/null || echo "\$arg")")
    else
        args+=("\$arg")
    fi
done

# mergetool 대기(wait) 및 CLI 상호작용 지원을 위해 직접 동기 실행
"\$WIN_SMERGE" "\${args[@]}"
EOF
    chmod +x "$_wrapper_path"

    # bashrc PATH 추가
    ensure_path_in_bashrc "$SMERGE_MODULE_DIR/bin"
    print_done "WSL2 Sublime Merge 브릿지 래퍼 생성 완료: $_wrapper_path"

else
    # ── Linux 네이티브 환경: 포터블 tar.xz 다운로드 및 설치 ─────────────────
    print_info "[Linux] 네이티브 포터블 Sublime Merge 설치 확인 중..."

    # 최신 안정 빌드 번호 조회 (SublimeHQ 공식 다운로드 페이지 HTML 크롤링)
    print_info "SublimeHQ 공식 사이트에서 최신 안정 빌드 확인 중..."
    _latest_build=""
    _html_content=$(curl -sSfL --max-time 10 https://www.sublimemerge.com/download 2>/dev/null || true)
    if [ -n "$_html_content" ]; then
        _latest_build=$(echo "$_html_content" | grep -oP 'sublime_merge_build_\K[0-9]+' | head -n 1 || true)
    fi

    if [ -z "$_latest_build" ]; then
        _latest_build="2102"
        print_warn "최신 빌드 번호 조회 실패 → 기본 안정 빌드($_latest_build) 사용"
    else
        print_info "최신 안정 빌드 확인: Build $_latest_build"
    fi

    # 현재 설치된 빌드 번호 확인
    _installed_build=""
    if [ -x "$SMERGE_MODULE_DIR/smerge" ]; then
        _installed_build=$("$SMERGE_MODULE_DIR/smerge" --version 2>/dev/null | grep -oE '[0-9]+' | head -n 1 || true)
    fi

    _do_install=false
    if [ -z "$_installed_build" ]; then
        # 미설치 → 사용자 확인 (기본값 N)
        if prompt_confirm "   👉 Sublime Merge (Git Diff & Merge GUI)를 설치하시겠습니까?" "N"; then
            _do_install=true
        else
            print_skip "Sublime Merge 설치를 건너뜁니다."
            exit 0
        fi
    elif [ "$_installed_build" = "$_latest_build" ]; then
        # 이미 최신 → 건너뜀
        print_skip "Sublime Merge Build $_installed_build 이 이미 최신 버전입니다."
    else
        # 구버전 → 업데이트 안내 후 진행 (기본값 N)
        print_info "현재 설치: Build $_installed_build → 최신: Build $_latest_build"
        if prompt_confirm "   ⚠️  최신 빌드로 업데이트하시겠습니까?" "N"; then
            _do_install=true
        else
            print_skip "Sublime Merge 업데이트를 건너뜁니다. (현재: Build $_installed_build)"
        fi
    fi

    if [ "$_do_install" = true ]; then
        _smerge_arch="x64"
        if [ "${IS_ARM64:-false}" = "true" ] || [ "$(uname -m 2>/dev/null)" = "aarch64" ]; then
            _smerge_arch="arm64"
        fi

        _smerge_url="https://download.sublimetext.com/sublime_merge_build_${_latest_build}_${_smerge_arch}.tar.xz"
        _smerge_tmp="$DT2_TMP/sublime_merge_${_latest_build}_${_smerge_arch}.tar.xz"

        if download_with_progress "$_smerge_url" "$_smerge_tmp" "Sublime Merge Build $_latest_build (${_smerge_arch})"; then
            echo -n "   📦 Sublime Merge 아카이브 압축 해제 중..."
            # 기존 바이너리를 임시 백업 후 설치 (실패 시 롤백)
            if [ -n "$_installed_build" ]; then
                _smerge_old="$SMERGE_MODULE_DIR/.dt2-old-smerge"
                rm -rf "$_smerge_old"
                mkdir -p "$_smerge_old"
                # Data 폴더(설정/포터블 데이터)는 보존, 바이너리만 백업
                find "$SMERGE_MODULE_DIR" -maxdepth 1 -not -name Data -not -name "$(basename "$SMERGE_MODULE_DIR")" -not -name ".dt2-old-smerge" -exec mv {} "$_smerge_old/" \;
            fi

            tar -xJf "$_smerge_tmp" --strip-components=1 -C "$SMERGE_MODULE_DIR"
            rm -f "$_smerge_tmp"
            echo " 완료"

            # 설치 성공 확인 후 백업 정리 또는 롤백
            if [ -x "$SMERGE_MODULE_DIR/smerge" ]; then
                rm -rf "$SMERGE_MODULE_DIR/.dt2-old-smerge" 2>/dev/null || true
                if [ -n "$_installed_build" ]; then
                    print_done "Sublime Merge 업데이트 완료: Build $_installed_build → Build $_latest_build"
                else
                    print_done "Sublime Merge 포터블 설치 완료: Build $_latest_build"
                fi
            elif [ -d "$SMERGE_MODULE_DIR/.dt2-old-smerge" ]; then
                # 설치 실패 → 롤백
                find "$SMERGE_MODULE_DIR/.dt2-old-smerge" -maxdepth 1 -exec mv {} "$SMERGE_MODULE_DIR/" \;
                rm -rf "$SMERGE_MODULE_DIR/.dt2-old-smerge"
                print_warn "설치 실패 → 이전 Build $_installed_build 로 롤백했습니다."
            fi

            # 포터블 모드 디렉터리 준비 (실행 파일 옆 Data 폴더)
            mkdir -p "$SMERGE_MODULE_DIR/Data/Packages"
            chmod +x "$SMERGE_MODULE_DIR/sublime_merge" "$SMERGE_MODULE_DIR/smerge" 2>/dev/null || true
        else
            print_error "Sublime Merge 다운로드에 실패했습니다. 네트워크를 확인하세요: $_smerge_url"
            rm -f "$_smerge_tmp" 2>/dev/null || true
        fi
    fi

    ensure_path_in_bashrc "$SMERGE_MODULE_DIR"
fi

# ==============================================================================
# [Step 2] 설정 파일 심볼릭 링크 연동
# ==============================================================================
print_info "Sublime Merge 설정 파일 링크 구성 중..."
SMERGE_CONFIG_SRC="$DEVTOOLS2/.config/sublime-merge/Packages/User"

if [ -d "$SMERGE_CONFIG_SRC" ]; then
    # 1) Linux/WSL 사용자 전역 설정 경로 심볼릭 링크
    mkdir -p "$HOME/.config/sublime-merge/Packages"
    if [ -d "$HOME/.config/sublime-merge/Packages/User" ] && [ ! -L "$HOME/.config/sublime-merge/Packages/User" ]; then
        # 기존 비심볼릭 User 디렉터리가 있으면 백업
        mv "$HOME/.config/sublime-merge/Packages/User" "$HOME/.config/sublime-merge/Packages/User.bak.$(date +%Y%m%d%H%M%S)"
    fi
    ln -sfn "$SMERGE_CONFIG_SRC" "$HOME/.config/sublime-merge/Packages/User"

    # 2) Linux 네이티브 포터블 경로 Data/Packages/User 심볼릭 링크
    if [ -d "$SMERGE_MODULE_DIR/Data/Packages" ]; then
        ln -sfn "$SMERGE_CONFIG_SRC" "$SMERGE_MODULE_DIR/Data/Packages/User"
    fi
    print_done "설정 파일 심볼릭 링크 완료: $SMERGE_CONFIG_SRC"

    # 3) Sublime Merge 시작 세션에 기본 저장소 경로 등록 (Local Repositories)
    python3 - <<PYEOF 2>/dev/null || true
import json, os

dirs = ["$HOME/.config/sublime-merge/Local", "$SMERGE_MODULE_DIR/Data/Local"]
targets = ["$HOME/_devtools2", "${DEVTOOLS2:-}", "$HOME"]

for d in dirs:
    if not os.path.exists(d):
        try: os.makedirs(d, exist_ok=True)
        except: continue
    sf = os.path.join(d, "Session.sublime_session")
    data = {}
    if os.path.exists(sf):
        try:
            with open(sf, "r", encoding="utf-8") as f:
                data = json.load(f)
        except: data = {}
    recent = data.setdefault("recent", {})
    existing = recent.setdefault("folders", [])
    merged = [t for t in targets if t and os.path.exists(t)]
    for e in existing:
        if e not in merged:
            merged.append(e)
    recent["folders"] = merged
    try:
        with open(sf, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    except: pass
PYEOF
fi

# ==============================================================================
# [Step 3] Git difftool & mergetool 연동
# ==============================================================================
if command -v git >/dev/null 2>&1; then
    print_info "Git difftool 및 mergetool 설정 중..."
    git config --global merge.tool smerge
    git config --global mergetool.smerge.cmd 'smerge mergetool "$BASE" "$LOCAL" "$REMOTE" -o "$MERGED"'
    git config --global mergetool.smerge.trustExitCode true
    git config --global diff.tool smerge
    git config --global difftool.smerge.cmd 'smerge "$LOCAL" "$REMOTE"'
    git config --global difftool.prompt false
    git config core.filemode false 2>/dev/null || true
    print_done "Git 글로벌 smerge 연동 완료 (git diff / git mergetool)"

    # ── WSL2: Windows Git 의 safe.directory 및 filemode 자동 등록 ──
    # Sublime Merge(Windows 네이티브)가 WSL2 파일시스템(\\wsl.localhost\...)의
    # 저장소를 열 때 Git 의 "dubious ownership" 보안 검사에 걸리지 않도록
    # Windows 쪽 git config 에 safe.directory 를 등록합니다.
    # 또한 Windows ↔ WSL2 간 실행 비트(100755 vs 100644) 불일치로 인한
    # 스크립트 대량 Unstaged 오탐을 방지하기 위해 core.filemode false 를 등록합니다.
    if [ "${IS_WSL2:-false}" = true ] && command -v git.exe >/dev/null 2>&1; then
        git.exe config --global core.filemode false 2>/dev/null || true
        _wsl_distro_name=""
        if [ -n "${WSL_DISTRO_NAME:-}" ]; then
            _wsl_distro_name="$WSL_DISTRO_NAME"
        elif [ -f /etc/wsl-distribution-name ]; then
            _wsl_distro_name=$(cat /etc/wsl-distribution-name 2>/dev/null | tr -d '\r\n')
        fi
        _dt2_path="${DEVTOOLS2:-/var/opt/_devtools2}"
        if [ -n "$_wsl_distro_name" ]; then
            _safe_dir="%(prefix)///wsl.localhost/${_wsl_distro_name}${_dt2_path}"
            _existing=$(git.exe config --global --get-all safe.directory 2>/dev/null || true)
            if ! echo "$_existing" | grep -qF "$_safe_dir"; then
                git.exe config --global --add safe.directory "$_safe_dir"
                print_done "Windows Git safe.directory 등록: $_safe_dir"
            fi
        fi
    fi
fi

# ==============================================================================
# [Step 4] Linux 데스크탑 환경 통합 (앱 바로가기 + 전역 단축키)
#   - Sublime Merge .desktop 앱 바로가기 등록
#   - GNOME 커스텀 키바인딩 등록:
#     • Ctrl+Alt+G → Sublime Merge
#     • Ctrl+Alt+T → Ghostty (기존 gnome-terminal 이중 실행 방지를 위해 내장 단축키 해제)
#   - WSL2 / 헤드리스(CLI) 환경에서는 자동 건너뜀
# ==============================================================================
if [ "${IS_WSL2:-false}" = false ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v gsettings >/dev/null 2>&1; then
    print_info "Linux 데스크탑 환경 감지 → 앱 바로가기 및 전역 단축키 등록 중..."

    # ── 4-1. Sublime Merge .desktop 앱 바로가기 ──────────────────────────────
    _desktop_dir="$HOME/.local/share/applications"
    mkdir -p "$_desktop_dir"

    # Sublime Merge 아이콘 경로: tarball에 포함된 Icon 디렉터리 또는 실행 파일 기본 경로
    _smerge_icon=""
    if [ -f "$SMERGE_MODULE_DIR/Icon/128x128/sublime-merge.png" ]; then
        _smerge_icon="$SMERGE_MODULE_DIR/Icon/128x128/sublime-merge.png"
    elif [ -f "$SMERGE_MODULE_DIR/Icon/48x48/sublime-merge.png" ]; then
        _smerge_icon="$SMERGE_MODULE_DIR/Icon/48x48/sublime-merge.png"
    fi

    cat > "$_desktop_dir/sublime_merge.desktop" <<DESKTOP_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Sublime Merge
GenericName=Git Client
Comment=Git Diff & Merge 시각화 도구 (DevTools2)
Exec=$SMERGE_MODULE_DIR/sublime_merge %F
Terminal=false
MimeType=inode/directory;application/x-git-repository;
Icon=$_smerge_icon
Categories=Development;RevisionControl;
StartupNotify=true
DESKTOP_EOF
    chmod +x "$_desktop_dir/sublime_merge.desktop"
    print_done ".desktop 앱 바로가기 등록 완료: $_desktop_dir/sublime_merge.desktop"

    # ── 4-2. GNOME 커스텀 키바인딩 등록 헬퍼 ─────────────────────────────────
    # GNOME custom-keybindings 는 dconf 경로 기반 배열 구조입니다.
    # 이미 같은 이름의 바인딩이 있으면 덮어쓰고(멱등), 없으면 새 슬롯을 추가합니다.
    _GNOME_KB_BASE="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
    _GNOME_KB_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

    # 현재 등록된 커스텀 키바인딩 목록 조회
    _existing_bindings=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "[]")

    # 이름으로 기존 슬롯 검색: 일치하면 해당 customN 반환, 없으면 빈 문자열
    _find_slot_by_name() {
        local _target_name="$1"
        local _idx=0
        while true; do
            local _slot_path="$_GNOME_KB_PATH/custom${_idx}/"
            # 슬롯이 등록 목록에 없으면 탐색 종료
            echo "$_existing_bindings" | grep -q "custom${_idx}" || break
            local _slot_name
            _slot_name=$(gsettings get "${_GNOME_KB_BASE}:${_slot_path}" name 2>/dev/null | tr -d "'" || true)
            if [ "$_slot_name" = "$_target_name" ]; then
                echo "$_idx"
                return
            fi
            _idx=$((_idx + 1))
        done
        echo ""
    }

    # 다음 사용 가능한 빈 슬롯 번호 탐색
    _find_next_slot() {
        local _idx=0
        while echo "$_existing_bindings" | grep -q "custom${_idx}"; do
            _idx=$((_idx + 1))
        done
        echo "$_idx"
    }

    # GNOME 커스텀 키바인딩 등록 (멱등)
    # 사용법: _register_gnome_keybinding "이름" "명령어" "<Primary><Alt>g"
    _register_gnome_keybinding() {
        local _name="$1" _command="$2" _binding="$3"

        # 기존 슬롯 검색 (같은 이름이 있으면 재사용)
        local _slot
        _slot=$(_find_slot_by_name "$_name")
        if [ -z "$_slot" ]; then
            _slot=$(_find_next_slot)
        fi

        local _slot_path="$_GNOME_KB_PATH/custom${_slot}/"

        gsettings set "${_GNOME_KB_BASE}:${_slot_path}" name "$_name"
        gsettings set "${_GNOME_KB_BASE}:${_slot_path}" command "$_command"
        gsettings set "${_GNOME_KB_BASE}:${_slot_path}" binding "$_binding"

        # 등록 목록에 슬롯 추가 (이미 있으면 중복 추가 방지)
        if ! echo "$_existing_bindings" | grep -q "custom${_slot}"; then
            # 기존 목록에서 @as [] 또는 [] 처리
            if [ "$_existing_bindings" = "@as []" ] || [ "$_existing_bindings" = "[]" ]; then
                _existing_bindings="['${_slot_path}']"
            else
                # 기존 목록의 닫는 ] 앞에 새 항목 추가
                _existing_bindings=$(echo "$_existing_bindings" | sed "s|]$|, '${_slot_path}']|")
            fi
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$_existing_bindings"
        fi

        print_done "GNOME 단축키 등록: $_binding → $_name ($_command)"
    }

    # ── 4-3. 기존 GNOME 내장 터미널 단축키 해제 (이중 실행 방지) ─────────────
    # Ubuntu GNOME 기본값: Ctrl+Alt+T → gnome-terminal
    # 이 내장 바인딩을 해제하지 않으면 Ghostty와 gnome-terminal이 동시에 실행됩니다.
    _builtin_terminal=$(gsettings get org.gnome.settings-daemon.plugins.media-keys terminal 2>/dev/null || true)
    if [ -n "$_builtin_terminal" ] && [ "$_builtin_terminal" != "[]" ] && [ "$_builtin_terminal" != "@as []" ]; then
        gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "[]"
        print_done "GNOME 내장 터미널 단축키 해제 완료 (이중 실행 방지)"
    fi

    # ── 4-4. Ctrl+Alt+T → Ghostty 터미널 등록 ────────────────────────────────
    _ghostty_cmd=""
    if [ -x "$DEVTOOLS2/modules/ghostty/ghostty" ]; then
        _ghostty_cmd="$DEVTOOLS2/modules/ghostty/ghostty"
    elif command -v ghostty >/dev/null 2>&1; then
        _ghostty_cmd="ghostty"
    fi

    if [ -n "$_ghostty_cmd" ]; then
        _register_gnome_keybinding "Ghostty Terminal" "$_ghostty_cmd" "<Primary><Alt>t"
    else
        print_warn "Ghostty 가 설치되어 있지 않아 Ctrl+Alt+T 단축키 등록을 건너뜁니다."
        print_info "  Ghostty 설치 후 수동 등록: gsettings → 설정 → 키보드 → 바로 가기"
    fi

    # ── 4-5. Ctrl+Alt+G → Sublime Merge 등록 ─────────────────────────────────
    _smerge_cmd=""
    if [ -x "$SMERGE_MODULE_DIR/sublime_merge" ]; then
        _smerge_cmd="$SMERGE_MODULE_DIR/sublime_merge"
    elif command -v smerge >/dev/null 2>&1; then
        _smerge_cmd="smerge"
    fi

    if [ -n "$_smerge_cmd" ]; then
        _register_gnome_keybinding "Sublime Merge" "$_smerge_cmd" "<Primary><Alt>g"
    fi

else
    if [ "${IS_WSL2:-false}" = true ]; then
        print_info "[WSL2] 데스크탑 단축키는 Windows AutoHotkey(devtools2-hotkey.ahk)에서 관리합니다."
    else
        print_info "GUI 데스크탑 환경이 감지되지 않아 앱 바로가기/단축키 등록을 건너뜁니다."
    fi
fi

print_done "Sublime Merge 전체 연동 단계 완료"
echo ""
