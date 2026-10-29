#!/bin/bash
# ==============================================================================
# Linux용 Zed 에디터 설치 스크립트 (tool.setup-zed.sh)
#
# 주요 기능:
#   1. Zed 에디터 설치 의사 확인 ([y/N], 기본값 N)
#   2. Linux 네이티브 환경에서 포터블 tar.gz 다운로드 및 $DEVTOOLS2/modules/zed 설치
#   3. WSL2 환경 감지 시 Windows 호스트 전담 안내 및 안전 스킵
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

print_banner "⚡ Zed 에디터 설치 및 연동 (tool.setup-zed.sh)"

ZED_MODULE_DIR="$DEVTOOLS2/modules/zed"

if [ "${IS_WSL2:-false}" = true ]; then
    ensure_wsl_interop
    _win_user=$(get_win_userprofile || true)

    _win_zed=""
    for _p in \
        "$_win_user/AppData/Local/Programs/Zed/bin" \
        "/mnt/c/Users/${USER:-}/AppData/Local/Programs/Zed/bin" \
        "/mnt/c/Program Files/Zed/bin"; do
        if [ -d "$_p" ]; then
            _win_zed="$_p"
            break
        fi
    done

    if [ -n "$_win_zed" ]; then
        print_info "[WSL2] Windows Zed 감지됨: $_win_zed"
        ensure_path_in_bashrc "$_win_zed"
        print_done "Zed Windows 연동 완료"
    else
        _do_zed=false
        if [ -n "${DT2_ZED_CHOICE:-}" ]; then
            [ "${DT2_ZED_CHOICE,,}" = "y" ] && _do_zed=true
        elif prompt_confirm "👉 Zed 에디터를 설치하시겠습니까?" "N"; then
            _do_zed=true
        fi

        if [ "$_do_zed" = true ]; then
            print_info "Windows 호스트에서 tool.setup-zed.ps1 을 실행하거나 winget으로 설치하세요:"
            print_info "  winget install --id ZedIndustries.Zed"
        else
            print_skip "Zed 에디터 설치를 건너뜁니다."
        fi
    fi
else
    # Linux 네이티브 환경
    _installed_ver=""
    if [ -x "$ZED_MODULE_DIR/bin/zed" ]; then
        _installed_ver=$("$ZED_MODULE_DIR/bin/zed" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
    fi

    _latest_ver=$(fetch_latest_github "zed-industries/zed" 2>/dev/null | sed 's/^v//' || true)

    # 이미 설치됨: 최신 버전과 비교 / 미설치 상태: 사용자 설치 의사 확인
    # → 판단은 공용 함수 decide_app_action(_install-utils.sh, 앱 규칙)에 맡깁니다 (환경변수 DT2_ZED_CHOICE / DT2_ZED_UPDATE 지원)
    _zed_installed=false
    [ -x "$ZED_MODULE_DIR/bin/zed" ] && _zed_installed=true
    decide_app_action "Zed 에디터" "$_zed_installed" "$_installed_ver" "$_latest_ver" "N" "DT2_ZED"
    _do_install=false
    [ "$DT2_APP_ACTION" != "skip" ] && _do_install=true

    if [ "$_do_install" = true ]; then
        print_info "Zed 다운로드 및 압축 해제..."
        mkdir -p "$DEVTOOLS2/modules"
        cd "$DEVTOOLS2/modules"
        install_tool \
            'https://github.com/zed-industries/zed/releases/latest/download/zed-linux-{ARCH}.tar.gz' \
            'x86_64' \
            'aarch64' \
            'zed'
        ensure_path_in_bashrc "$ZED_MODULE_DIR/bin"
        print_done "Zed 설치/업데이트 완료"
    fi
    # (설치·업데이트를 건너뛴 경우의 안내는 decide_app_action 이 출력)
fi

echo ""
