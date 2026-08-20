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

# 공통 색상/스피너 헬퍼 로드 (온라인 전용)
_load_colors() {
    [ -n "${_COLORS_LOADED:-}" ] && return 0
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
    exit 1
}
_load_colors

# 공통 설치 유틸리티 로드 (IS_WSL2, ARCH 등)
_load_install_utils() {
    [ -n "${_INSTALL_UTILS_LOADED:-}" ] && return 0
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
    exit 1
}
_load_install_utils

print_banner "💻 VS Code 에디터 설치 및 확장 연동 (tool.setup-vscode.sh)"

# WSL2 환경 감지 시: Windows 호스트 전담 안내
if [ "$IS_WSL2" = true ]; then
    print_warn "[WSL2 환경 감지] VSCode 설치 및 확장 설정은 Windows 호스트(tool.setup-vscode.ps1)에서 전담합니다."
    print_info "  Windows 측 설치 스크립트를 통해 설치 및 WSL Remote 연동을 진행해주세요."
    exit 0
fi

# [1] 설치 의사 확인
echo ""
printf "👉 VS Code (Visual Studio Code)를 설치하시겠습니까? [y/\033[1;32mN\033[0m]: "
if [ -t 0 ]; then
    read -r _vscode_choice
else
    _vscode_choice="N"
fi
echo ""

case "${_vscode_choice:-N}" in
    y|Y)
        # [2] 바이너리 설치 (.deb)
        if command -v code >/dev/null 2>&1; then
            print_skip "VSCode(Visual Studio Code)가 이미 설치되어 있습니다: $(command -v code)"
        else
            print_info "VSCode .deb 패키지 다운로드 및 설치 중..."
            _vscode_tmp="/tmp/vscode_install_$$.deb"
            if curl -Ls "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" -o "$_vscode_tmp"; then
                sudo dpkg -i "$_vscode_tmp" 2>/dev/null || sudo apt-get install -f -y 2>/dev/null || true
                rm -f "$_vscode_tmp"
                print_done "VSCode 설치 완료"
            else
                print_warn "VSCode 다운로드 실패. 수동으로 설치하세요: https://code.visualstudio.com/"
                rm -f "$_vscode_tmp"
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
                    for _retry in 1 2 3; do
                        (code --install-extension "$ext" --force </dev/null >/dev/null 2>&1) &
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
                        echo " ⚠️  실패 (3회 시도)"
                        _vscode_fail_count=$((_vscode_fail_count + 1))
                    fi
                fi
            done < "$VSCODE_EXT_LIST"
            echo ""
            print_info "[요약] 신규 설치: ${_vscode_install_count}개 / 이미 설치: ${_vscode_skip_count}개 / 실패: ${_vscode_fail_count}개"
        elif ! command -v code >/dev/null 2>&1; then
            print_warn "code 명령을 찾을 수 없어 확장 설치를 건너뜁니다."
        else
            print_warn "extensions.txt 없음: $VSCODE_EXT_LIST"
        fi
        ;;
    *)
        print_skip "VSCode 설치를 건너뜁니다. 기존 설정은 유지됩니다."
        ;;
esac

print_done "VSCode 단계 완료"
echo ""
