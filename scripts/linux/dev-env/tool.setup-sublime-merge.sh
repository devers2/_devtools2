#!/bin/bash
# ==============================================================================
# Sublime Merge 설치 및 Git Diff/Merge 연동 스크립트 (tool.setup-sublime-merge.sh)
#
# 주요 기능:
#   1. Linux 데스크톱 / WSL2(WSLg) 공통: 공식 최신 tar.xz 다운로드 및 $DEVTOOLS2/modules/sublime-merge
#      스마트 설치 ([y/N], 기본값 N). GUI 가 없는 서버(헤드리스) 환경에서는 설치를 건너뜁니다.
#   2. WSL2 환경: WSLg(WSL GUI 앱 지원) 활성화 확인 — Linux 앱을 Windows 창으로 실행
#   3. 한글 입력기 확인 및 설치 (없을 때만, _install-utils.sh 의 ensure_korean_ime 공용 함수)
#   4. smerge 실행 래퍼 생성 (WSL2 에서는 fcitx5 입력기 환경변수·데몬을 실행 시점에 준비)
#   5. $DEVTOOLS2/.config/sublime-merge 설정 파일 자동 링크/동기화 (다크 Monokai, 11.5pt)
#   6. Git 글로벌 difftool 및 mergetool 로 smerge 자동 등록
#   7. 앱 바로가기(.desktop) 등록 (WSL2 는 WSLg 가 Windows 시작 메뉴에 자동 노출)
#      및 Linux GNOME 커스텀 키바인딩(Ctrl+Alt+G) 등록 (WSL2 는 Windows AutoHotkey 가 담당)
#
# [WSL2 에서 Windows 판 대신 Linux 판(WSLg)을 쓰는 이유]
#   Windows 판 Sublime Merge 는 번들 git.exe 로 \\wsl.localhost(9P) 경로의 저장소를 다뤄야 해서
#   ● 실행 비트(100755) 오탐 ● Linux 심볼릭 링크 lstat 실패("Function not implemented") 오탐
#   ● 양쪽 git 이 같은 .git/index 를 번갈아 재작성하는 전체 재해시(대형 저장소 수십 초)
#   ● index.lock 잔존 ● autocrlf=true 로 Discard 시 CRLF 기록 ● safe.directory 등록
#   같은 문제가 계속 발생했습니다. Linux 판은 WSL 의 git 과 ext4 파일시스템을 직접 쓰므로
#   이 문제들이 구조적으로 생기지 않습니다.
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
#   DT2_SMERGE_CHOICE=n → 전체 건너뜀 / DT2_SMERGE_CHOICE=y → 설치·업데이트 확인 프롬프트를 자동 승인
_smerge_auto_yes=false
if [ -n "${DT2_SMERGE_CHOICE:-}" ]; then
    [ "${DT2_SMERGE_CHOICE,,}" = "n" ] && { print_skip "Sublime Merge 설치를 건너뜁니다."; exit 0; }
    [ "${DT2_SMERGE_CHOICE,,}" = "y" ] && _smerge_auto_yes=true
fi

# ==============================================================================
# [Step 0] GUI 환경 확인 (Sublime Merge 는 GUI 전용 앱)
#   - WSL2: WSLg 가 꺼져 있으면 .wslconfig 에 활성화 설정을 기록하고 계속 설치합니다
#           (WSL 재시작 후 바로 실행 가능하도록 바이너리·설정을 미리 준비).
#   - Linux: 현재 GUI 세션(DISPLAY/WAYLAND_DISPLAY)이 있거나, SSH 로 접속했더라도
#            데스크톱 세션(xsessions/wayland-sessions)이 설치된 머신이면 데스크톱 환경으로 판단합니다.
#            둘 다 아니면 헤드리스 서버이므로 설치를 건너뜁니다 (터미널에서는 lazygit 사용).
# ==============================================================================
if [ "${IS_WSL2:-false}" = true ]; then
    if ensure_wslg; then
        print_info "[WSL2] WSLg 활성화 확인 완료 → Linux 판 Sublime Merge 를 Windows 창으로 실행합니다."
    fi
else
    if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] \
        && ! ls /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop >/dev/null 2>&1; then
        print_skip "GUI 데스크톱 환경이 없는 서버로 감지되어 Sublime Merge 설치를 건너뜁니다. (터미널에서는 lazygit 을 사용하세요)"
        exit 0
    fi
fi

# ==============================================================================
# [Step 1] 바이너리 설치 (Linux 데스크톱 / WSL2 공통: 포터블 tar.xz)
#   ⚠️ 공식 tar.xz 에는 'smerge' 실행 파일이 없고 'sublime_merge' 만 들어 있습니다.
#      (deb 패키지는 /usr/bin/smerge 심볼릭 링크를 따로 만들어 줌)
#      따라서 설치 여부/버전은 sublime_merge 로 확인하고, smerge 명령은 bin/smerge 래퍼가 제공합니다.
# ==============================================================================
SMERGE_MODULE_DIR="$DEVTOOLS2/modules/sublime-merge"
mkdir -p "$SMERGE_MODULE_DIR"

print_info "포터블 Sublime Merge 설치 확인 중..."

# 최신 안정 빌드 번호 조회 (SublimeHQ 공식 다운로드 페이지 HTML 크롤링)
print_info "SublimeHQ 공식 사이트에서 최신 안정 빌드 확인 중..."
_latest_build=""
_html_content=$(curl -sSfL --max-time 10 https://www.sublimemerge.com/download 2>/dev/null || true)
if [ -n "$_html_content" ]; then
    _latest_build=$(echo "$_html_content" | grep -oP 'sublime_merge_build_\K[0-9]+' | head -n 1 || true)
fi

# 현재 설치된 빌드 번호 확인 (출력 예: "Sublime Merge Build 2132")
_installed_build=""
if [ -x "$SMERGE_MODULE_DIR/sublime_merge" ]; then
    _installed_build=$("$SMERGE_MODULE_DIR/sublime_merge" --version 2>/dev/null | grep -oE '[0-9]+' | head -n 1 || true)
fi

if [ -z "$_latest_build" ]; then
    if [ -n "$_installed_build" ]; then
        # 조회 실패 시 기본값과 비교하면 더 오래된 빌드로 "업데이트"하자고 묻게 되므로 업데이트 확인 자체를 건너뜀
        print_warn "최신 빌드 번호 조회 실패 → 업데이트 확인을 건너뜁니다. (현재: Build $_installed_build)"
        _latest_build="$_installed_build"
    else
        _latest_build="2132"
        print_warn "최신 빌드 번호 조회 실패 → 기본 안정 빌드($_latest_build) 사용"
    fi
else
    print_info "최신 안정 빌드 확인: Build $_latest_build"
fi

# 미설치 → 사용자 확인 (기본값 N) / 이미 최신 → 건너뜀 / 구버전 → 업데이트 안내 후 진행 (기본값 Y)
# → 판단은 공용 함수 decide_app_action(_install-utils.sh, 앱 규칙: Zed·Orca·VS Code·Ghostty 와 동일)에 맡깁니다.
#   ● 빌드 번호는 크기로 비교합니다: 설치된 빌드가 최신 이상이면 최신으로 간주(함수는 같음/다름만 비교하므로 미리 정규화)
#   ● DT2_SMERGE_CHOICE=y 는 설치와 업데이트를 모두 자동 승인합니다 → DT2_SMERGE_UPDATE 기본값을 y 로 연결
_smerge_installed=false
[ -n "$_installed_build" ] && _smerge_installed=true
_cmp_latest="$_latest_build"
if [ -n "$_installed_build" ] && [ "$_installed_build" -ge "$_latest_build" ] 2>/dev/null; then
    _cmp_latest="$_installed_build"
fi
[ "$_smerge_auto_yes" = true ] && DT2_SMERGE_UPDATE="${DT2_SMERGE_UPDATE:-y}"
decide_app_action "Sublime Merge (Git Diff & Merge GUI)" "$_smerge_installed" \
    "${_installed_build:+Build $_installed_build}" "Build $_cmp_latest" "N" "DT2_SMERGE"
_do_install=false
case "$DT2_APP_ACTION" in
    install|update) _do_install=true ;;
    *) if [ "$_smerge_installed" = false ]; then exit 0; fi ;;   # 미설치 + 설치 거절 → 연동 단계도 건너뜀
esac

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
            # bin 폴더(DevTools2 실행 래퍼)는 보존, 바이너리만 백업
            find "$SMERGE_MODULE_DIR" -mindepth 1 -maxdepth 1 -not -name bin -not -name ".dt2-old-smerge" -exec mv {} "$_smerge_old/" \;
        fi

        tar -xJf "$_smerge_tmp" --strip-components=1 -C "$SMERGE_MODULE_DIR"
        rm -f "$_smerge_tmp"
        echo " 완료"

        # 설치 성공 확인 후 백업 정리 또는 롤백
        if [ -x "$SMERGE_MODULE_DIR/sublime_merge" ]; then
            rm -rf "$SMERGE_MODULE_DIR/.dt2-old-smerge" 2>/dev/null || true
            if [ -n "$_installed_build" ]; then
                print_done "Sublime Merge 업데이트 완료: Build $_installed_build → Build $_latest_build"
            else
                print_done "Sublime Merge 포터블 설치 완료: Build $_latest_build"
            fi
        elif [ -d "$SMERGE_MODULE_DIR/.dt2-old-smerge" ]; then
            # 설치 실패 → 롤백
            find "$SMERGE_MODULE_DIR/.dt2-old-smerge" -mindepth 1 -maxdepth 1 -exec mv {} "$SMERGE_MODULE_DIR/" \;
            rm -rf "$SMERGE_MODULE_DIR/.dt2-old-smerge"
            print_warn "설치 실패 → 이전 Build $_installed_build 로 롤백했습니다."
        fi
        chmod +x "$SMERGE_MODULE_DIR/sublime_merge" 2>/dev/null || true
    else
        print_error "Sublime Merge 다운로드에 실패했습니다. 네트워크를 확인하세요: $_smerge_url"
        rm -f "$_smerge_tmp" 2>/dev/null || true
    fi
fi

if [ ! -x "$SMERGE_MODULE_DIR/sublime_merge" ]; then
    print_error "Sublime Merge 실행 파일이 없어 연동 단계를 진행할 수 없습니다: $SMERGE_MODULE_DIR/sublime_merge"
    exit 1
fi

# 과거 버전이 만든 포터블 Data 폴더 정리
# - 실행 파일 옆에 Data 폴더가 있으면 Sublime Merge 가 포터블 모드로 동작해 세션·캐시·라이선스 같은
#   개인 데이터를 그룹 공유 디렉터리(modules, 2770)에 기록합니다. 개인 데이터는 사용자별
#   ~/.config/sublime-merge 에 두어야 하므로, 라이선스 파일이 없는(=DevTools2 가 만든 세션뿐인) 경우에만 제거합니다.
if [ -d "$SMERGE_MODULE_DIR/Data" ]; then
    if [ -z "$(find "$SMERGE_MODULE_DIR/Data" -name '*.sublime_license' -print -quit 2>/dev/null)" ]; then
        rm -rf "$SMERGE_MODULE_DIR/Data"
        print_info "포터블 Data 폴더를 정리했습니다. (설정은 사용자별 ~/.config/sublime-merge 를 사용)"
    else
        print_warn "$SMERGE_MODULE_DIR/Data 에 라이선스 파일이 있어 포터블 모드를 유지합니다."
    fi
fi

# ==============================================================================
# [Step 2] 한글 입력기 및 한글 UI 글꼴 확인·설치 (없을 때만)
#   - WSL2 는 기본적으로 입력기가 없고, WSLg 창에는 Windows IME 가 적용되지 않으므로
#     fcitx5-hangul 이 있어야 커밋 메시지에 한글을 입력할 수 있습니다.
#   - Linux 데스크톱은 대부분 ibus/fcitx5 가 이미 있어 그대로 건너뜁니다.
#   - 가변폭 한글 UI 글꼴(Noto Sans CJK KR)도 없을 때만 함께 설치합니다 (WSL2 는 기본 UI 글꼴·GTK 글꼴 크기 보정 포함).
# ==============================================================================
ensure_korean_ime || print_warn "한글 입력기 준비에 실패했습니다. 나중에 install_hangle.sh 로 다시 시도할 수 있습니다."

# 한글 UI 글꼴 (없을 때만) — 커밋 목록 한글 겹침, 과도하게 큰 제목/메뉴 글꼴 방지 (상세: ensure_korean_gui_font 주석)
ensure_korean_gui_font || true

# ==============================================================================
# [Step 3] smerge 실행 래퍼 생성 ($SMERGE_MODULE_DIR/bin/smerge)
#   - nvim(<leader>gu), git mergetool, .desktop 바로가기, Windows AutoHotkey(Ctrl+Alt+G)가
#     모두 이 래퍼를 통해 실행됩니다. (1.setup-env.sh 의 PATH 목록에서 bin 이 모듈 루트보다 앞섬)
#   - WSL2: WSLg 에는 데스크톱 세션(im-config/autostart)이 없으므로 실행 시점에
#     ● fcitx5 입력기 환경변수(GTK_IM_MODULE 등) 지정
#     ● 세션 DBus 주소 보정 (fcitx GTK 입력 모듈은 DBus 로 fcitx5 와 통신; wsl.exe -e 실행 시 비어 있을 수 있음)
#     ● fcitx5 데몬이 없으면 기동 (WSLg 컴포지터는 Wayland 입력기 프로토콜을 지원하지 않아 wayland 애드온은 끔)
#   - 공통: 날짜 형식만 LC_TIME=C.UTF-8 로 고정 (ko_KR 로캘의 오전/오후가 잘려 날짜가 깨지는 문제 방지)
#   - 공통: 제목 표시줄·메뉴 바만 GTK 다크(GTK_THEME=Adwaita:dark) 적용 (눈부심 감소, 나머지 UI 는 라이트)
#   - mergetool 은 종료 대기가 필요하므로 백그라운드(&)가 아닌 exec 로 직접 실행합니다.
#     (sublime_merge 는 일반 실행 시 스스로 백그라운드로 분리되어 즉시 반환됩니다)
#   - 과거 WSL2 용 Windows smerge.exe 브릿지 래퍼도 이 단계에서 덮어써집니다.
# ==============================================================================
mkdir -p "$SMERGE_MODULE_DIR/bin"
_wrapper_path="$SMERGE_MODULE_DIR/bin/smerge"
cat <<EOF > "$_wrapper_path"
#!/bin/bash
# ==============================================================================
# Sublime Merge 실행 래퍼 (Generated by tool.setup-sublime-merge.sh)
# ==============================================================================
SMERGE_BIN="$SMERGE_MODULE_DIR/sublime_merge"
if [ ! -x "\$SMERGE_BIN" ]; then
    echo "[오류] Sublime Merge 실행 파일을 찾을 수 없습니다: \$SMERGE_BIN" >&2
    echo "  tool.setup-sublime-merge.sh 를 다시 실행하세요." >&2
    exit 1
fi

if grep -qi microsoft /proc/version 2>/dev/null && command -v fcitx5 >/dev/null 2>&1; then
    export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx SDL_IM_MODULE=fcitx
    if [ -z "\${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "/run/user/\$(id -u)/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/\$(id -u)/bus"
    fi
    if ! pgrep -u "\$(id -u)" -x fcitx5 >/dev/null 2>&1; then
        fcitx5 -d --replace --disable=wayland,waylandim >/dev/null 2>&1 || true
    fi
fi

# 날짜 표시는 시스템 로캘(glib)을 따르는데, ko_KR 로캘의 '오전/오후' 를 Sublime Merge 가 중간에서 잘라
# "수 28 10월 2026, 12:25 오" / "화 5:33 오" 처럼 깨져 보이므로 날짜 형식만 영어로 고정합니다.
# (Windows 판과 동일한 "Wed, Oct 28, 2026, 12:21 AM" / "Tue, 5:33 PM" 형식. UI 언어·한글 입력에는 영향 없음)
export LC_TIME=C.UTF-8

# 제목 표시줄(창 드래그 영역)과 메뉴 바(File, Edit…)는 Sublime Merge 테마가 아니라 GTK 가 그리므로
# GTK 다크 테마를 지정해 눈부심을 줄입니다. (나머지 UI 는 평가판 라이트 테마 그대로)
# - gsettings 의 color-scheme/gtk-theme 로는 적용되지 않음을 실측했습니다. Sublime Merge 가 자기 UI 테마(라이트)에 맞춰
#   GTK 다크 선호를 스스로 끄기 때문이며, 앱이 덮어쓸 수 없는 GTK_THEME 환경변수로만 적용됩니다.
# - 사용자가 이미 GTK_THEME 를 지정했다면 그 값을 존중합니다.
export GTK_THEME="\${GTK_THEME:-Adwaita:dark}"

exec "\$SMERGE_BIN" "\$@"
EOF
chmod +x "$_wrapper_path"
print_done "smerge 실행 래퍼 생성 완료: $_wrapper_path"

# ==============================================================================
# [Step 4] 설정 파일 심볼릭 링크 연동
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
    print_done "설정 파일 심볼릭 링크 완료: $SMERGE_CONFIG_SRC"

    # 2) 중앙 UI 기본값(.config/devtools2/ui-defaults.json)을 Preferences 에 반영 — diff 코드 글꼴·크기·줄 간격
    # - Neovim(Windows Terminal/Ghostty)과 같은 글꼴 크기·줄 높이를 쓰도록 단일 파일에서 관리합니다.
    #   (예전에는 Windows 판 설치 PS1 이 복사하면서 반영했으나, Linux 판으로 전환하며 이 단계로 옮김)
    # - Sublime Merge 는 사용자 폴더의 플랫폼별 설정(Preferences (Linux).sublime-settings)을 읽지 않음을 실측했으므로
    #   저장소의 Preferences 파일 값을 직접 갱신합니다. 값이 이미 같으면 파일을 건드리지 않습니다(멱등, git 변경 없음).
    # - 줄 간격 환산: nvim/WT 는 줄 높이 "비율"(line_height, 예 1.5), Sublime 은 위·아래 여백 px 입니다.
    #   D2Coding 의 기본 줄 높이는 글자 크기(px)의 약 1.17배(WSLg 1:1 캡처 실측)이므로
    #   여백 합계 = round((line_height - 1.17) × 글자 px), 글자 px = pt × 96/72, 위쪽에 1px 더 배분합니다.
    #   (11.5pt / 1.5 → 15.3px, 여백 5px → 위 3 / 아래 2)
    python3 - "$DEVTOOLS2/.config/devtools2/ui-defaults.json" "$SMERGE_CONFIG_SRC/Preferences.sublime-settings" <<'PYEOF' || print_warn "ui-defaults.json 값을 Sublime Merge Preferences 에 반영하지 못했습니다."
import json, re, sys

ui_path, pref_path = sys.argv[1], sys.argv[2]
font = json.load(open(ui_path, encoding="utf-8")).get("font", {})
size = float(font.get("size", 11.5))
face = font.get("gui_face", "D2Coding ligature")
line_height = float(font.get("line_height", 1.5))

px = size * 96 / 72
total = max(0, round((line_height - 1.17) * px))
top, bottom = (total + 1) // 2, total // 2
size_str = ("%g" % size)

text = open(pref_path, encoding="utf-8").read()
new = text
new = re.sub(r'("font_face"\s*:\s*)"[^"]*"', lambda m: m.group(1) + json.dumps(face, ensure_ascii=False), new, count=1)
new = re.sub(r'("font_size"\s*:\s*)[0-9.]+', lambda m: m.group(1) + size_str, new, count=1)
new = re.sub(r'("line_padding_top"\s*:\s*)[0-9]+', lambda m: m.group(1) + str(top), new, count=1)
new = re.sub(r'("line_padding_bottom"\s*:\s*)[0-9]+', lambda m: m.group(1) + str(bottom), new, count=1)
if new != text:
    with open(pref_path, "w", encoding="utf-8") as f:
        f.write(new)
    print(f"[완료] ui-defaults.json 반영: font_face={face}, font_size={size_str}, line_padding={top}/{bottom}")
else:
    print(f"[건너뜀] Preferences 가 이미 ui-defaults.json 과 같습니다 (font_size={size_str}, line_padding={top}/{bottom})")
PYEOF

    # 3) Sublime Merge 시작 세션에 기본 저장소 경로 등록 (Local Repositories)
    python3 - <<PYEOF 2>/dev/null || true
import json, os

dirs = ["$HOME/.config/sublime-merge/Local"]
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
# [Step 5] Git difftool & mergetool 연동
#   (WSL2 도 이제 WSL 의 git 을 직접 쓰므로 Windows git.exe 의 safe.directory/filemode 보정은 필요 없습니다)
# ==============================================================================
if command -v git >/dev/null 2>&1; then
    print_info "Git difftool 및 mergetool 설정 중..."
    git config --global merge.tool smerge
    git config --global mergetool.smerge.cmd 'smerge mergetool "$BASE" "$LOCAL" "$REMOTE" -o "$MERGED"'
    git config --global mergetool.smerge.trustExitCode true
    git config --global diff.tool smerge
    git config --global difftool.smerge.cmd 'smerge "$LOCAL" "$REMOTE"'
    git config --global difftool.prompt false
    print_done "Git 글로벌 smerge 연동 완료 (git diff / git mergetool)"
fi

# ==============================================================================
# [Step 6] 데스크탑 환경 통합 (앱 바로가기 + 전역 단축키)
#   - Sublime Merge .desktop 앱 바로가기 등록 (Linux 앱 메뉴 / WSL2 는 WSLg 가 Windows 시작 메뉴에 노출)
#   - GNOME 커스텀 키바인딩 등록 (Linux 데스크톱 전용):
#     • Ctrl+Alt+G → Sublime Merge
#     • Ctrl+Alt+T → Ghostty (기존 gnome-terminal 이중 실행 방지를 위해 내장 단축키 해제)
#   - GNOME 단축키 등록은 WSL2 / 헤드리스(CLI) 환경에서는 자동 건너뜀
#   - WSL2 의 Ctrl+Alt+G 는 Windows AutoHotkey(devtools2-hotkey.ahk)가 담당합니다.
# ==============================================================================

# ── 6-1. Sublime Merge .desktop 앱 바로가기 ──────────────────────────────
_desktop_dir="$HOME/.local/share/applications"
mkdir -p "$_desktop_dir"

# Sublime Merge 아이콘 경로: tarball에 포함된 Icon 디렉터리 또는 실행 파일 기본 경로
_smerge_icon=""
if [ -f "$SMERGE_MODULE_DIR/Icon/128x128/sublime-merge.png" ]; then
    _smerge_icon="$SMERGE_MODULE_DIR/Icon/128x128/sublime-merge.png"
elif [ -f "$SMERGE_MODULE_DIR/Icon/48x48/sublime-merge.png" ]; then
    _smerge_icon="$SMERGE_MODULE_DIR/Icon/48x48/sublime-merge.png"
fi

# Exec 는 입력기 환경을 준비하는 bin/smerge 래퍼를 가리킵니다.
cat > "$_desktop_dir/sublime_merge.desktop" <<DESKTOP_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Sublime Merge
GenericName=Git Client
Comment=Git Diff & Merge 시각화 도구 (DevTools2)
Exec=$_wrapper_path %F
Terminal=false
MimeType=inode/directory;application/x-git-repository;
Icon=$_smerge_icon
Categories=Development;RevisionControl;
StartupNotify=true
DESKTOP_EOF
chmod +x "$_desktop_dir/sublime_merge.desktop"
print_done ".desktop 앱 바로가기 등록 완료: $_desktop_dir/sublime_merge.desktop"

if [ "${IS_WSL2:-false}" = false ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v gsettings >/dev/null 2>&1; then
    print_info "Linux 데스크탑 환경 감지 → 전역 단축키 등록 중..."

    # ── 6-2. GNOME 커스텀 키바인딩 등록 헬퍼 ─────────────────────────────────
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

    # ── 6-3. 기존 GNOME 내장 터미널 단축키 해제 (이중 실행 방지) ─────────────
    # Ubuntu GNOME 기본값: Ctrl+Alt+T → gnome-terminal
    # 이 내장 바인딩을 해제하지 않으면 Ghostty와 gnome-terminal이 동시에 실행됩니다.
    _builtin_terminal=$(gsettings get org.gnome.settings-daemon.plugins.media-keys terminal 2>/dev/null || true)
    if [ -n "$_builtin_terminal" ] && [ "$_builtin_terminal" != "[]" ] && [ "$_builtin_terminal" != "@as []" ]; then
        gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "[]"
        print_done "GNOME 내장 터미널 단축키 해제 완료 (이중 실행 방지)"
    fi

    # ── 6-4. Ctrl+Alt+T → Ghostty 터미널 등록 ────────────────────────────────
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


    # ── 6-5. Ctrl+Alt+G → Sublime Merge 등록 ─────────────────────────────────
    _register_gnome_keybinding "Sublime Merge" "$_wrapper_path" "<Primary><Alt>g"

else
    if [ "${IS_WSL2:-false}" = true ]; then
        print_info "[WSL2] 전역 단축키(Ctrl+Alt+G)는 Windows AutoHotkey(devtools2-hotkey.ahk)에서 관리합니다."
    else
        print_info "현재 GUI 세션이 감지되지 않아 GNOME 전역 단축키 등록을 건너뜁니다. (데스크톱 로그인 후 다시 실행하세요)"
    fi
fi

print_done "Sublime Merge 전체 연동 단계 완료"
if [ "${IS_WSL2:-false}" = true ]; then
    print_info "  실행: WSL 터미널에서 'smerge .' / nvim <leader>gu / Windows Ctrl+Alt+G"
    print_info "  한/영 전환: 한/영 키(오른쪽 Alt) — Windows IME 는 WSLg 창에 적용되지 않아 AutoHotkey 가 WSL fcitx5 로 전달합니다."
    print_info "  Esc / CapsLock 탭 / Ctrl+[ 를 누르면 WSLg 창에서도 fcitx5 가 영문으로 전환됩니다."
fi
echo ""
