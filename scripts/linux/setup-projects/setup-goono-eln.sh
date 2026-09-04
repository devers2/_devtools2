#!/usr/bin/env bash
# ==============================================================================
# Goono-ELN 프로젝트 설정 스크립트
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

# 공통 프로젝트 설정 모듈 로드 (setup_gradle_spring_project 포함)
if [ -f "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh" ]; then
    # shellcheck disable=SC1091
    source "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"
else
    echo "❌ common-setup.sh 를 찾을 수 없습니다: $DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"
    exit 1
fi

# Gradle Spring Boot 프로젝트 표준 설정 실행
setup_gradle_spring_project \
    --target-dir "$HOME/workspaces/goono/Goono-ELN" \
    --repo-url "https://github.com/redwit-dev/Goono-ELN.git" \
    --jdk-version 21 \
    --main-class "so.goono.GoonoELNApplication" \
    --spring-profile "0_DEVELOP,0_LOCAL,s2"
