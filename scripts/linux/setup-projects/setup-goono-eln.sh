#!/usr/bin/env bash
# ==============================================================================
# Goono-ELN 프로젝트 설정 스크립트
# ==============================================================================

set -e

# 공통 프로젝트 설정 모듈 로드 (Java·Python 설정 함수 포함. Bitwarden 인증 라이브러리(bw-lib)는 저장소 클론 등
# 필요한 시점에 공통 모듈이 알아서 불러옴 — ensure_project_repo)
DEVTOOLS2="${DEVTOOLS2:-$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../..")}"
# shellcheck disable=SC1091
source "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh" || { echo "❌ 공통 모듈을 찾을 수 없습니다: $DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"; exit 1; }

# Gradle Spring Boot 프로젝트 표준 설정 실행
setup_gradle_spring_project \
    --target-dir "$HOME/workspaces/goono/Goono-ELN" \
    --repo-url "https://github.com/redwit-dev/Goono-ELN.git" \
    --jdk-version 8 \
    --gradle-jdk-version 17 \
    --main-class "so.goono.GoonoELNApplication" \
    --spring-profile "0_DEVELOP,0_LOCAL,s2"
