#!/usr/bin/env bash
# ==============================================================================
# s2-support 프로젝트 설정 스크립트 (common-setup.sh 래퍼)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVTOOLS2="${DEVTOOLS2:-$(readlink -f "$SCRIPT_DIR/../../../..")}"

# 공통 프로젝트 설정 모듈 로드
if [ -f "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh" ]; then
    source "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"
else
    echo "❌ 공통 모듈을 찾을 수 없습니다: $DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"
    exit 1
fi

setup_s2_library_project "s2-support"
