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

# 공통 설치 유틸리티 로드 (IS_WSL2, install_tool 등)
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

print_banner "⚡ Zed 에디터 설치 (tool.setup-zed.sh)"

# WSL2 환경 감지 시: Windows 호스트 전담 안내
if [ "$IS_WSL2" = true ]; then
    print_warn "[WSL2 환경 감지] WSL2 환경에서는 Windows 호스트(tool.setup-zed.ps1)에 Zed를 설치하므로 리눅스 내부 Zed 설치는 건너뜁니다."
    exit 0
fi

if [ -d "$DEVTOOLS2/modules/zed" ]; then
    print_skip "zed 디렉토리가 이미 존재합니다: $DEVTOOLS2/modules/zed"
    print_info "  새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/zed'"
    exit 0
fi

echo ""
printf "👉 Zed 에디터를 설치하시겠습니까? [y/\033[1;32mN\033[0m]: "
if [ -t 0 ]; then
    read -r _zed_choice
else
    _zed_choice="N"
fi
echo ""

case "${_zed_choice:-N}" in
    y|Y)
        print_info "Zed stable 다운로드 및 압축 해제..."
        mkdir -p "$DEVTOOLS2/modules"
        cd "$DEVTOOLS2/modules"
        install_tool \
            'https://github.com/zed-industries/zed/releases/latest/download/zed-linux-{ARCH}.tar.gz' \
            'x86_64' \
            'aarch64' \
            'zed'
        print_done "Zed 설치 완료"
        ;;
    *)
        print_skip "Zed 에디터 설치를 건너뜁니다. 기존 설정은 유지됩니다."
        ;;
esac

echo ""
