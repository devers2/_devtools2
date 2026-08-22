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

# 공통 모듈 로드 - GitHub raw URL에서 스트리밍 source (캐시 우회 헤더 포함)
_GH_RAW="https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env"
# shellcheck disable=SC1090
source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_common.sh") || { echo "[오류] _common.sh 로드 실패 - 네트워크 연결을 확인하세요." >&2; exit 1; }
# shellcheck disable=SC1090
source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_install-utils.sh") || { print_error "_install-utils.sh 로드 실패 - 네트워크 연결을 확인하세요."; exit 1; }

print_banner "⚡ Zed 에디터 설치 (tool.setup-zed.sh)"

if [ -d "$DEVTOOLS2/modules/zed" ]; then
    print_skip "zed 디렉토리가 이미 존재합니다: $DEVTOOLS2/modules/zed"
    print_info "  새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/zed'"
    exit 0
fi

_do_zed=false
if [ -n "${DT2_ZED_CHOICE:-}" ]; then
    [ "${DT2_ZED_CHOICE,,}" = "y" ] && _do_zed=true
elif prompt_confirm "Zed 에디터를 설치하시겠습니까?" "N"; then
    _do_zed=true
fi

if [ "$_do_zed" = true ]; then
    if [ "${IS_WSL2:-false}" = true ]; then
        _win_user="${WIN_USERPROFILE:-}"
        if [ -z "$_win_user" ] && command -v cmd.exe >/dev/null 2>&1; then
            _raw_home=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' || true)
            [ -n "$_raw_home" ] && command -v wslpath >/dev/null 2>&1 && _win_user=$(wslpath "$_raw_home" 2>/dev/null || true)
        fi
        for _p in \
            "$_win_user/AppData/Local/Programs/Zed/bin" \
            "/mnt/c/Users/${USER:-}/AppData/Local/Programs/Zed/bin" \
            "/mnt/c/Program Files/Zed/bin"; do
            if [ -d "$_p" ]; then
                ensure_path_in_bashrc "$_p"
                break
            fi
        done
        print_done "Zed Windows 연동 완료"
    else
        print_info "Zed stable 다운로드 및 압축 해제..."
        mkdir -p "$DEVTOOLS2/modules"
        cd "$DEVTOOLS2/modules"
        install_tool \
            'https://github.com/zed-industries/zed/releases/latest/download/zed-linux-{ARCH}.tar.gz' \
            'x86_64' \
            'aarch64' \
            'zed'
        ensure_path_in_bashrc "$DEVTOOLS2/modules/zed"
        print_done "Zed 설치 완료"
    fi
else
    print_skip "Zed 에디터 설치를 건너뜁니다. 기존 설정은 유지됩니다."
fi

echo ""
