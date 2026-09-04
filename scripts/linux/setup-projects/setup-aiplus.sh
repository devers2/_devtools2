#!/usr/bin/env bash
# ==============================================================================
# aiplus 프로젝트 설정 스크립트
# ==============================================================================

set -e

# DEVTOOLS2 경로 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVTOOLS2="${DEVTOOLS2:-$(readlink -f "$SCRIPT_DIR/../../..")}"

# bw-lib 로드 (Bitwarden 인증 라이브러리)
if [ -f "$DEVTOOLS2/scripts/fzf/bw-lib" ]; then
    # shellcheck disable=SC1091
    source "$DEVTOOLS2/scripts/fzf/bw-lib"
else
    echo "❌ bw-lib 라이브러리를 찾을 수 없습니다: $DEVTOOLS2/scripts/fzf/bw-lib"
    exit 1
fi

# 공통 프로젝트 설정 모듈 로드 (setup_python_fastapi_project 포함)
if [ -f "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh" ]; then
    # shellcheck disable=SC1091
    source "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"
else
    echo "❌ common-setup.sh 를 찾을 수 없습니다: $DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"
    exit 1
fi

# Python FastAPI 프로젝트 표준 설정 실행
# (SFTP 마운트는 방식 C 개별 옵션 지정 방식을 사용하여 향후 프로젝트 작성 시 참고할 수 있도록 구성)
setup_python_fastapi_project \
    --target-dir "$HOME/workspaces/aiplus" \
    --repo-url "https://github.com/Placelink-HUB/aiplus.git" \
    --python-version "312" \
    --venv-name "venv_math" \
    --port 8095 \
    --sftp-user "namupia" \
    --sftp-host "aiplus.im" \
    --sftp-port 222 \
    --sftp-remote-path "~/mount/aiplus" \
    --sftp-local-path "$HOME/mount/aiplus"
