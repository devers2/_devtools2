#!/bin/bash
# [주의] 이 스크립트는 한글 입력기(Fcitx5 또는 GNOME ibus-hangul)를 설치하고 설정합니다.
#
# ⚠️ 포터블 원칙의 예외입니다(전체 목록/이유는 0.init-devtools2.sh 상단 메모 참고).
# fcitx5는 디스플레이 서버(X11/Wayland)의 입력기 프레임워크에 직접 등록되는 시스템 서비스라
# 바이너리 복사로는 개념적으로 동작할 수 없습니다(항상 대상 OS에 직접 설치 필요).
#
# 실제 설치 로직은 _install-utils.sh 의 ensure_korean_ime 공용 함수에 있습니다
# (tool.setup-sublime-merge.sh 등 GUI 도구 설치 스크립트와 동일한 로직을 공유).
#   ● 이미 한글 엔진이 있으면 건너뜀 / GNOME+ibus 는 ibus-hangul / 그 외(WSL2 포함)는 fcitx5-hangul
#   ● 예전 버전처럼 ~/.bashrc 에 GTK_IM_MODULE 등을 직접 쓰지 않습니다:
#     Linux 데스크톱은 im-config 가 로그인 세션 환경변수를 설정하고,
#     WSL2 는 앱 실행 래퍼가 실행 시점에 환경변수와 fcitx5 데몬을 준비합니다.

set -euo pipefail

# 공통 모듈 로드 (스크립트 옆 파일 → 없으면 같은 커밋(DT2_REF)의 원격 스트리밍)
#   ● 로컬 저장소에서 직접 실행하면 스크립트 옆 파일을 씁니다(같은 체크아웃이라 버전이 항상 맞음).
#   ● 스트리밍 실행(마스터가 받은 /tmp/_dt2_*.sh, bash <(curl ...))은 스크립트와 같은 커밋의 원격 파일을 씁니다.
#     예전에는 그 사이에 $DEVTOOLS2 로컬 저장소를 먼저 봤는데, 로컬이 커밋 동기화를 건너뛴 채(미커밋 변경·갈라짐)
#     오래되어 있으면 새 스크립트가 옛 공용 파일을 불러와 새 함수가 없어 중단될 수 있어 제외했습니다.
DT2_REF="${DT2_REF:-main}"
_GH_RAW="https://raw.githubusercontent.com/devers2/_devtools2/${DT2_REF}/scripts/linux/dev-env"
_SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
for _lib in _common.sh _install-utils.sh; do
    if [ -f "$_SCRIPT_DIR/$_lib" ]; then
        # shellcheck disable=SC1090
        source "$_SCRIPT_DIR/$_lib"
        else
        # shellcheck disable=SC1090
        source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/$_lib") || { echo "[오류] $_lib 로드 실패 - 네트워크 연결을 확인하세요." >&2; exit 1; }
    fi
done

print_banner "⌨️  한글 입력기 설치 및 설정 (install_hangle.sh)"
ensure_korean_ime
