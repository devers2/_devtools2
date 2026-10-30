#!/bin/bash
# ==============================================================================
# Linux용 VS Code 설치 및 확장 동기화 스크립트 (tool.setup-vscode.sh)
#
# 주요 기능:
#   1. VS Code 설치 의사 확인 ([y/N], 기본값 N)
#   2. Linux 네이티브 환경에서 .deb 패키지 다운로드 및 설치 (이미 설치 시 최신 버전 확인 후 업데이트 여부 확인, 기본값 Y)
#   3. extensions.txt 에 정의된 개발 확장 프로그램 자동 동기화 설치
#   4. WSL2 환경 감지 시 Windows 호스트 전담 안내 및 안전 스킵
#
# ------------------------------------------------------------------------------
# ⚠️ [AI / 개발자 필독 - 설계 절대 원칙]
# 100% 온라인 전용 스트리밍: 서브스크립트는 무조건 GitHub main 원격 raw URL에서
# 직접 스트리밍으로 실행됩니다. 순수 UTF-8 NoBOM으로 유지되어야 합니다.
# ------------------------------------------------------------------------------
# ==============================================================================

set -euo pipefail

if [ -z "${DEVTOOLS2:-}" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")
fi

if [ ! -d "$DEVTOOLS2" ]; then
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

if [ -f "$_SCRIPT_DIR/_install-utils.sh" ]; then
    # shellcheck disable=SC1091
    source "$_SCRIPT_DIR/_install-utils.sh"
else
    # shellcheck disable=SC1090
    source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_install-utils.sh") || { print_error "_install-utils.sh 로드 실패 - 네트워크 연결을 확인하세요."; exit 1; }
fi

print_banner "💻 VS Code 에디터 설치 및 확장 연동 (tool.setup-vscode.sh)"

# ── Linux 네이티브: 공식 최신 .deb 다운로드 및 설치 (신규 설치·업데이트 공용) ──
_vscode_install_deb() {
    _vscode_tmp="$DT2_TMP/vscode_install_$$.deb"
    _deb_os="linux-deb-x64"
    if [ "${IS_ARM64:-false}" = "true" ] || [ "$(uname -m 2>/dev/null)" = "aarch64" ]; then
        _deb_os="linux-deb-arm64"
    fi
    if download_with_progress "https://code.visualstudio.com/sha/download?build=stable&os=${_deb_os}" "$_vscode_tmp" "VSCode .deb 패키지"; then
        dt2_sudo_auth || true   # 비밀번호 질문이 스피너에 가려지지 않도록 먼저 인증
        echo -n "   📦 VSCode 패키지 설치 중..."
        (sudo dpkg -i "$_vscode_tmp" >/dev/null 2>&1 || sudo apt-get install -f -y >/dev/null 2>&1 || true) &
        show_spinner $!
        wait $! 2>/dev/null || true
        rm -f "$_vscode_tmp"
        if command -v code >/dev/null 2>&1; then
            echo " 완료"
            print_done "VSCode 설치 완료"
        else
            echo " 실패"
            print_warn "VSCode 패키지 설치에 실패했습니다. 수동으로 설치하세요: https://code.visualstudio.com/"
        fi
    else
        print_warn "VSCode 다운로드 실패. 수동으로 설치하세요: https://code.visualstudio.com/"
        rm -f "$_vscode_tmp"
    fi
}

# ── 1. 기존 설치 여부 사전 감지 ──────────────────────────────────────────────
_vscode_installed=false

if [ "${IS_WSL2:-false}" = true ]; then
    ensure_wsl_interop
    _win_user=$(get_win_userprofile || true)
    for _p in \
        "$_win_user/AppData/Local/Programs/Microsoft VS Code/bin" \
        "/mnt/c/Users/${USER:-}/AppData/Local/Programs/Microsoft VS Code/bin" \
        "/mnt/c/Program Files/Microsoft VS Code/bin"; do
        if [ -d "$_p" ]; then
            ensure_path_in_bashrc "$_p"
            break
        fi
    done
    if command -v code >/dev/null 2>&1; then
        _vscode_installed=true
        print_info "[WSL2] Windows VS Code 감지됨: $(command -v code)"
    fi
else
    if command -v code >/dev/null 2>&1; then
        _vscode_installed=true
        # 이미 설치됨: 최신 버전과 비교해 새 버전이 있으면 업데이트 여부를 묻습니다 (기본값 Y)
        # (Zed·Orca·Ghostty·Sublime Merge 와 같은 "설치되어 있으면 최신 버전 확인" 규칙. 최신 버전 조회는 공식 업데이트 API 사용)
        _vscode_cur=$(code --version 2>/dev/null | head -n 1 || true)
        _vscode_latest=$(curl -sSfL --max-time 10 "https://update.code.visualstudio.com/api/releases/stable" 2>/dev/null \
            | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | head -n 1 | tr -d '"' || true)
        # 판단은 공용 함수 decide_app_action(_install-utils.sh, 앱 규칙)에 맡깁니다 (DT2_VSCODE_UPDATE=y|n 로 강제 가능)
        decide_app_action "VS Code" true "$_vscode_cur" "$_vscode_latest" "N" "DT2_VSCODE"
        [ "$DT2_APP_ACTION" = "update" ] && _vscode_install_deb
    fi
fi

# ── 2. 미설치 상태일 때만 설치 의사 확인 ──────────────────────────────────────
_do_vscode=false
if [ "$_vscode_installed" = true ]; then
    _do_vscode=true
else
    # 설치 여부 확인은 공용 함수 decide_app_action 사용 (DT2_VSCODE_CHOICE=y|n 로 강제 가능, 기본값 N)
    decide_app_action "VS Code (Visual Studio Code)" false "" "" "N" "DT2_VSCODE"
    [ "$DT2_APP_ACTION" = "install" ] && _do_vscode=true

    if [ "$_do_vscode" = true ]; then
        if [ "${IS_WSL2:-false}" = true ]; then
            print_warn "[WSL2] Windows 호스트에 VS Code가 설치되어 있지 않습니다."
            print_info "  Windows에서 tool.setup-vscode.ps1 을 실행하거나 winget으로 설치하세요:"
            print_info "    winget install --id Microsoft.VisualStudioCode"
            print_skip "VSCode 설치 및 확장 연동 단계 건너뜀"
            exit 0
        else
            _vscode_install_deb
        fi
    else
        # (건너뜀 안내는 decide_app_action 이 출력)
        print_info "기존 설정은 유지됩니다."
    fi
fi

        # [3] VSCode 확장 자동 설치 (extensions.txt 기반)
        #   WSL / Linux 네이티브 상관없이 사용자가 y를 선택하고 code 명령이 존재하면 실행
        #   WSL: Windows code CLI 가 interop으로 동작 / Linux 네이티브: /usr/bin/code
        VSCODE_EXT_LIST="$DEVTOOLS2/.config/vscode/extensions.txt"
        if command -v code >/dev/null 2>&1 && [ -f "$VSCODE_EXT_LIST" ]; then
            echo ""
            # [VS Code 서버 다운로드 진행률 표시 — WSL2]
            #   WSL 의 code 는 Windows VS Code 를 부르는 래퍼라, Windows VS Code 가 업데이트된 뒤 처음 실행하면
            #   VS Code WSL 확장(wslCode.sh → wslDownload.sh)이 그 버전의 VS Code 서버(약 220MB)를
            #   ~/.vscode-server/bin 에 먼저 내려받습니다. 몇 분 걸리는데 스피너만 돌면 멈춘 것처럼 보입니다
            #   (실측: 약 0.8MB/s 에서 5분 가까이 "확장 목록 조회 중..." 에 머묾).
            #   ● wslDownload.sh 가 표준출력으로 내보내는 진행률("97% 98% ...")이 아래 임시 파일에 쌓이므로
            #     마지막 퍼센트 값과, 받는 중인 *.tar.gz 크기를 스피너 옆에 함께 보여 줍니다.
            #   ● 받는 중인 파일은 최근 1분 안에 바뀐 것만 봅니다(예전에 끊긴 다운로드의 잔여 파일 제외).
            #   ● 진행률이 오래 그대로면 네트워크 문제이므로 Ctrl+C 후 다시 실행하면 됩니다(서버는 처음부터 다시 받음).
            #   ● 받은 서버는 남아 있어 VS Code 가 다시 업데이트되기 전까지는 이 대기가 없습니다.
            _vscode_wait_ext_list() {
                local _pid="$1" _label="$2" _out="$3" _i=0 _extra _f _pct _mb
                local _spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
                while kill -0 "$_pid" 2>/dev/null; do
                    _extra=""
                    if [ "${IS_WSL2:-false}" = true ]; then
                        _f=$(find "$HOME/.vscode-server/bin" -maxdepth 1 -name '*.tar.gz' -mmin -1 2>/dev/null | head -n 1)
                        if [ -n "$_f" ]; then
                            _mb=$(( $(stat -c %s "$_f" 2>/dev/null || echo 0) / 1048576 ))
                            _pct=$(tail -c 32 "$_out" 2>/dev/null | grep -oE '[0-9]+%' | tail -n 1 || true)
                            # (한 줄이 터미널 폭을 넘으면 \r 덮어쓰기가 깨져 줄이 쌓이므로 짧게 유지)
                            _extra=" VS Code 서버 다운로드 중 ${_pct:+${_pct} }(${_mb}MB)"
                        fi
                    fi
                    printf "\r%s [%s]%s\033[K" "$_label" "${_spin[_i]}" "$_extra"
                    _i=$(( (_i + 1) % ${#_spin[@]} ))
                    sleep 0.15
                done
                printf "\r%s\033[K" "$_label"
            }
            (code --list-extensions 2>/dev/null </dev/null > $DT2_TMP/_vscode_installed.tmp) &
            _ext_list_pid=$!
            _vscode_wait_ext_list "$_ext_list_pid" "   📋 VSCode 기존 확장 목록 조회 중..." "$DT2_TMP/_vscode_installed.tmp"
            wait "$_ext_list_pid" 2>/dev/null || true
            echo " 완료"
            _INSTALLED_EXTS=$(tr '[:upper:]' '[:lower:]' < $DT2_TMP/_vscode_installed.tmp 2>/dev/null || echo "")
            rm -f $DT2_TMP/_vscode_installed.tmp 2>/dev/null

            _ext_total=$(grep -v '^[[:space:]]*#' "$VSCODE_EXT_LIST" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
            print_info "VSCode 확장 프로그램 설치 중 (extensions.txt 기반, 총 ${_ext_total}개)..."
            _vscode_install_count=0
            _vscode_skip_count=0
            _vscode_fail_count=0
            _ext_idx=0
            while IFS= read -r ext_line || [ -n "$ext_line" ]; do
                ext=$(echo "$ext_line" | tr -d '\r' | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [ -z "$ext" ] && continue
                _ext_idx=$((_ext_idx + 1))
                ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
                if echo "$_INSTALLED_EXTS" | grep -qxF "$ext_lower"; then
                    echo "   ⏭️  [${_ext_idx}/${_ext_total}] [건너뜀] $ext (이미 설치됨)"
                    _vscode_skip_count=$((_vscode_skip_count + 1))
                else
                    echo -n "   📥 [${_ext_idx}/${_ext_total}] [설치] $ext ..."
                    _ok=0
                    _ext_err_file="$DT2_TMP/_vscode_ext_err_$$.log"
                    for _retry in 1 2 3; do
                        if [ "$_retry" -gt 1 ]; then
                            echo -n " (재시도 ${_retry}/3)..."
                        fi
                        (code --install-extension "$ext" --force </dev/null >"$_ext_err_file" 2>&1) &
                        _ext_pid=$!
                        show_spinner "$_ext_pid"
                        _ext_ec=0
                        wait "$_ext_pid" 2>/dev/null || _ext_ec=$?
                        if [ "$_ext_ec" -eq 0 ]; then
                            _ok=1
                            break
                        fi
                        sleep 2
                    done
                    if [ "$_ok" -eq 1 ]; then
                        echo " ✅"
                        _vscode_install_count=$((_vscode_install_count + 1))
                    else
                        _err_line=$(grep -v 'DEP0169\|DeprecationWarning' "$_ext_err_file" 2>/dev/null | grep -E 'Error|error|실패|failed' | head -n 1 | tr -d '\r\n' || true)
                        [ -z "$_err_line" ] && _err_line=$(head -n 1 "$_ext_err_file" 2>/dev/null | tr -d '\r\n' || echo "")
                        if [ -n "$_err_line" ]; then
                            echo " ⚠️  실패: $_err_line"
                        else
                            echo " ⚠️  실패 (3회 시도)"
                        fi
                        _vscode_fail_count=$((_vscode_fail_count + 1))
                    fi
                    rm -f "$_ext_err_file" 2>/dev/null
                fi
            done < "$VSCODE_EXT_LIST"
            echo ""
            print_info "[요약] 신규 설치: ${_vscode_install_count}개 / 이미 설치: ${_vscode_skip_count}개 / 실패: ${_vscode_fail_count}개"
        elif ! command -v code >/dev/null 2>&1; then
            print_warn "code 명령을 찾을 수 없어 확장 설치를 건너뜁니다."
        else
            print_warn "extensions.txt 없음: $VSCODE_EXT_LIST"
        fi

print_done "VSCode 단계 완료"
echo ""
