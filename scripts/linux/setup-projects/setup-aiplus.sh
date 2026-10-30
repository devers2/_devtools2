#!/usr/bin/env bash
# ==============================================================================
# aiplus 프로젝트 설정 스크립트
# ==============================================================================

set -e

# 공통 프로젝트 설정 모듈 로드 (Java·Python 설정 함수 포함. Bitwarden 인증 라이브러리(bw-lib)는 저장소 클론 등
# 필요한 시점에 공통 모듈이 알아서 불러옴 — ensure_project_repo)
DEVTOOLS2="${DEVTOOLS2:-$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")}"
# shellcheck disable=SC1091
source "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh" || { echo "❌ 공통 모듈을 찾을 수 없습니다: $DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"; exit 1; }

# Python FastAPI 프로젝트 표준 설정 실행
# (SFTP 마운트는 방식 C 개별 옵션 지정 방식을 사용하여 향후 프로젝트 작성 시 참고할 수 있도록 구성)
setup_python_fastapi_project \
    --target-dir "$HOME/workspaces/aiplus" \
    --repo-url "https://github.com/Placelink-HUB/aiplus.git" \
    --python-version "312" \
    --venv-name "venv_math" \
    --module "main:app" \
    --port 8095 \
    --worker-script "handwriting_matching_worker.py" \
    --sftp-user "namupia" \
    --sftp-host "aiplus.im" \
    --sftp-port 222 \
    --sftp-remote-path "~/mount/aiplus" \
    --sftp-local-path "$HOME/mount/aiplus"
