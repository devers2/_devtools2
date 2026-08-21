#!/bin/bash
# ==============================================================================
# Linux용 VS Code 설치 및 확장 동기화 스크립트 (tool.setup-vscode.sh)
#
# 주요 기능:
#   1. VS Code 설치 의사 확인 ([y/N], 기본값 N)
#   2. Linux 네이티브 환경에서 .deb 패키지 다운로드 및 설치 (이미 설치 시 건너뜀)
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

# 공통 모듈 로드 - GitHub raw URL에서 스트리밍 source (캐시 우회 헤더 포함)
_GH_RAW="https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env"
# shellcheck disable=SC1090
source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_common.sh") || { echo "[오류] _common.sh 로드 실패 - 네트워크 연결을 확인하세요." >&2; exit 1; }
# shellcheck disable=SC1090
source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_install-utils.sh") || { print_error "_install-utils.sh 로드 실패 - 네트워크 연결을 확인하세요."; exit 1; }

print_banner "💻 VS Code 에디터 설치 및 확장 연동 (tool.setup-vscode.sh)"

_do_vscode=false
if [ -n "${DT2_VSCODE_CHOICE:-}" ]; then
    [ "${DT2_VSCODE_CHOICE,,}" = "y" ] && _do_vscode=true
elif prompt_confirm "👉 VS Code (Visual Studio Code)를 설치하시겠습니까?" "N"; then
    _do_vscode=true
fi

if [ "$_do_vscode" = true ]; then
        if [ "${IS_WSL2:-false}" = true ]; then
            # binfmt_misc WSLInterop 복구 (Exec format error 예방)
            if [ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ] && [ -w /proc/sys/fs/binfmt_misc/register ]; then
                echo ':WSLInterop:M::MZ::/init:PF' > /proc/sys/fs/binfmt_misc/register 2>/dev/null || echo ':WSLInterop:M::MZ::/init:' > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
            fi
            _win_user="${WIN_USERPROFILE:-}"
            if [ -z "$_win_user" ] && command -v cmd.exe >/dev/null 2>&1; then
                _raw_home=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' || true)
                [ -n "$_raw_home" ] && command -v wslpath >/dev/null 2>&1 && _win_user=$(wslpath "$_raw_home" 2>/dev/null || true)
            fi
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
                print_info "[WSL2] Windows VS Code CLI가 감지되어 WSL Remote 확장 동기화를 진행합니다: $(command -v code)"
            else
                print_warn "[WSL2] Windows 호스트에 VS Code가 설치되어 있지 않아 확장 설치를 건너뜁니다."
                print_skip "VSCode 설치 및 확장 연동 단계 건너뜀"
                exit 0
            fi
        else
            if command -v code >/dev/null 2>&1; then
                print_skip "VSCode(Visual Studio Code)가 이미 설치되어 있습니다: $(command -v code)"
            else
                _vscode_tmp="/tmp/vscode_install_$$.deb"
                if download_with_progress "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" "$_vscode_tmp" "VSCode .deb 패키지"; then
                    echo -n "   📦 VSCode 패키지 설치 중..."
                    (sudo dpkg -i "$_vscode_tmp" 2>/dev/null || sudo apt-get install -f -y 2>/dev/null || true) &
                    show_spinner $!
                    echo " 완료"
                    rm -f "$_vscode_tmp"
                    print_done "VSCode 설치 완료"
                else
                    print_warn "VSCode 다운로드 실패. 수동으로 설치하세요: https://code.visualstudio.com/"
                    rm -f "$_vscode_tmp"
                fi
            fi
        fi

        # [3] VSCode 확장 자동 설치 (extensions.txt 기반)
        #   WSL / Linux 네이티브 상관없이 사용자가 y를 선택하고 code 명령이 존재하면 실행
        #   WSL: Windows code CLI 가 interop으로 동작 / Linux 네이티브: /usr/bin/code
        VSCODE_EXT_LIST="$DEVTOOLS2/.config/vscode/extensions.txt"
        if command -v code >/dev/null 2>&1 && [ -f "$VSCODE_EXT_LIST" ]; then
            echo ""
            echo -n "   📋 VSCode 기존 확장 목록 조회 중..."
            (code --list-extensions 2>/dev/null </dev/null > /tmp/_vscode_installed.tmp) &
            _ext_list_pid=$!
            show_spinner "$_ext_list_pid"
            wait "$_ext_list_pid" 2>/dev/null || true
            echo " 완료"
            _INSTALLED_EXTS=$(tr '[:upper:]' '[:lower:]' < /tmp/_vscode_installed.tmp 2>/dev/null || echo "")
            rm -f /tmp/_vscode_installed.tmp 2>/dev/null

            print_info "VSCode 확장 프로그램 설치 중 (extensions.txt 기반)..."
            _vscode_install_count=0
            _vscode_skip_count=0
            _vscode_fail_count=0
            while IFS= read -r ext_line || [ -n "$ext_line" ]; do
                ext=$(echo "$ext_line" | tr -d '\r' | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [ -z "$ext" ] && continue
                ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
                if echo "$_INSTALLED_EXTS" | grep -qF "$ext_lower"; then
                    echo "   ⏭️  [건너뜀] $ext (이미 설치됨)"
                    _vscode_skip_count=$((_vscode_skip_count + 1))
                else
                    echo -n "   📥 [설치] $ext ..."
                    _ok=0
                    _ext_err_file="/tmp/_vscode_ext_err_$$.log"
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
                        _err_line=$(head -n 1 "$_ext_err_file" 2>/dev/null | tr -d '\r\n' || echo "")
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
    else
        print_skip "VSCode 설치를 건너뜁니다. 기존 설정은 유지됩니다."
    fi

print_done "VSCode 단계 완료"
echo ""
