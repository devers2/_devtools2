#!/usr/bin/env bash
# ==============================================================================
# DEVTOOLS2 setup-projects 공통 모듈 (common-setup.sh)
# ==============================================================================
# 개요:
#   프로젝트 설정(setup-projects) 스크립트에서 공통으로 재사용 가능한 모듈 함수들을 제공합니다.
#
# 사용 방법 (다른 스크립트에서 호출 시):
#   1. 모듈 불러오기:
#      if [ -f "$SCRIPT_DIR/common-setup.sh" ]; then
#          source "$SCRIPT_DIR/common-setup.sh"
#      fi
#
#   2. GitHub Packages 의존성 설정 함수 호출:
#      setup_gpr_gradle_properties "$TARGET_DIR" [BW_ITEM_NAME]
#      - $1: 대상 프로젝트 루트 경로 (필수, 기본값: $PWD)
#      - $2: Bitwarden 아이템 이름 (선택, 기본값: github.com-main)
# ==============================================================================

# ── GitHub Packages 의존성 관리 설정 (gpr.user / gpr.key) ───────────────────
# 기능:
#   - 대상 디렉토리에 Gradle 설정 파일(build.gradle, settings.gradle, build.gradle.kts, settings.gradle.kts) 존재 여부 확인
#   - ~/.gradle/gradle.properties 파일의 gpr.user 와 gpr.key 설정 상태 검증
#   - 누락되거나 불일치 시 대소문자 구분 없이 (y/n) 대화형 입력을 받아 gpr.user 및 gpr.key 자동 생성/수정
# 인수:
#   $1 = 대상 프로젝트 디렉토리 (기본값: 현재 디렉토리)
#   $2 = Bitwarden 아이템 이름 (선택, 기본값: github.com-main)
setup_gpr_gradle_properties() {
    local TARGET_DIR="${1:-$PWD}"
    local BW_ITEM="${2:-github.com-main}"

    if [ ! -d "$TARGET_DIR" ]; then
        return 0
    fi

    # 1. Gradle 빌드/설정 파일 존재 여부 확인
    local HAS_GRADLE=false
    for gfile in "build.gradle" "settings.gradle" "build.gradle.kts" "settings.gradle.kts"; do
        if [ -f "$TARGET_DIR/$gfile" ]; then
            HAS_GRADLE=true
            break
        fi
    done

    if [ "$HAS_GRADLE" = "false" ]; then
        return 0
    fi

    # 2. expected user.name 및 PAT 추출
    local EXPECTED_USER=""
    EXPECTED_USER=$(git config user.name 2>/dev/null || git config --global user.name 2>/dev/null || echo "")

    local EXPECTED_PAT=""
    local _EMAIL=""
    if [ -n "${BW_SESSION:-}" ] && command -v bw_find_item_by_name &>/dev/null; then
        local _ALL_ITEMS_RAW _PARSED
        _ALL_ITEMS_RAW=$(bw list items --search "$BW_ITEM" --session "$BW_SESSION" </dev/null 2>&1)
        _PARSED=$(bw_find_item_by_name "${_ALL_ITEMS_RAW}"$'\n---ITEM_SPLIT---\n' "$BW_ITEM" 2>/dev/null || true)
        if [ -n "$_PARSED" ]; then
            _EMAIL=$(printf "%s" "$_PARSED" | cut -f1)
            EXPECTED_PAT=$(printf "%s" "$_PARSED" | cut -f3) # totp 필드 = PAT
        fi
    fi

    if [ -z "$EXPECTED_USER" ] && [ -n "$_EMAIL" ]; then
        EXPECTED_USER=$(printf "%s" "$_EMAIL" | cut -d'@' -f1)
    fi

    # 3. ~/.gradle/gradle.properties 확인
    local GRADLE_PROPS_DIR="$HOME/.gradle"
    local GRADLE_PROPS_FILE="$GRADLE_PROPS_DIR/gradle.properties"

    local CURRENT_USER=""
    local CURRENT_KEY=""
    local FILE_EXISTS=false

    if [ -f "$GRADLE_PROPS_FILE" ]; then
        FILE_EXISTS=true
        CURRENT_USER=$(grep -E '^\s*gpr\.user\s*=' "$GRADLE_PROPS_FILE" 2>/dev/null | head -n 1 | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        CURRENT_KEY=$(grep -E '^\s*gpr\.key\s*=' "$GRADLE_PROPS_FILE" 2>/dev/null | head -n 1 | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    fi

    # 4. 검증 및 수정 필요 여부 판단
    local NEEDS_UPDATE=false

    if [ "$FILE_EXISTS" = "false" ]; then
        NEEDS_UPDATE=true
    elif [ -z "$CURRENT_USER" ] || [ "$CURRENT_USER" != "$EXPECTED_USER" ]; then
        NEEDS_UPDATE=true
    elif [ -z "$CURRENT_KEY" ] || [ "$CURRENT_KEY" != "$EXPECTED_PAT" ]; then
        NEEDS_UPDATE=true
    fi

    if [ "$NEEDS_UPDATE" = "false" ]; then
        echo "ℹ️  ~/.gradle/gradle.properties 의 gpr.user 및 gpr.key 설정이 최신 상태입니다."
        return 0
    fi

    # 5. 사용자 입력 요청 (기본값 없음, y/n 대소문자 구분 없이 재요청)
    echo ""
    echo "⚠️  Gradle 프로젝트가 감지되었으나, ~/.gradle/gradle.properties 에 gpr.user / gpr.key 설정이 없거나 일치하지 않습니다."
    if [ "$FILE_EXISTS" = "true" ]; then
        local MASKED_CUR_KEY=""
        if [ -n "$CURRENT_KEY" ]; then
            MASKED_CUR_KEY="${CURRENT_KEY:0:4}****"
        fi
        echo "   [현재 설정] gpr.user='${CURRENT_USER}', gpr.key='${MASKED_CUR_KEY}'"
    else
        echo "   [현재 설정] ~/.gradle/gradle.properties 파일 없음"
    fi
    local MASKED_EXP_KEY=""
    if [ -n "$EXPECTED_PAT" ]; then
        MASKED_EXP_KEY="${EXPECTED_PAT:0:4}****"
    fi
    echo "   [권장 설정] gpr.user='${EXPECTED_USER}', gpr.key='${MASKED_EXP_KEY}'"
    echo ""

    local USER_CHOICE=""
    while true; do
        read -rp "❓ GitHub Packages 의존성 관리를 위해 ~/.gradle/gradle.properties 에 gpr.user 및 gpr.key 를 설정하시겠습니까? (y/n): " USER_CHOICE
        USER_CHOICE=$(echo "$USER_CHOICE" | tr '[:upper:]' '[:lower:]' | xargs)
        if [ "$USER_CHOICE" = "y" ] || [ "$USER_CHOICE" = "n" ]; then
            break
        fi
        echo "❌ 잘못된 입력입니다. 'y' 또는 'n' (대소문자 구분 없음)을 반드시 입력해주세요."
    done

    if [ "$USER_CHOICE" = "n" ]; then
        echo "ℹ️  gpr.user 및 gpr.key 설정을 추가/수정하지 않고 다음 단계로 진행합니다."
        return 0
    fi

    # 6. 'y' 입력 시 파일 생성 및 gpr.user, gpr.key 추가/수정
    mkdir -p "$GRADLE_PROPS_DIR"
    touch "$GRADLE_PROPS_FILE"

    if [ -z "$EXPECTED_USER" ]; then
        read -rp "🔑 gpr.user 에 설정할 GitHub 계정명(user.name)을 입력하세요: " EXPECTED_USER
    fi
    if [ -z "$EXPECTED_PAT" ]; then
        read -rp "🔑 gpr.key 에 설정할 GitHub PAT(Personal Access Token)을 입력하세요: " EXPECTED_PAT
    fi

    python3 -c "
import sys, re

filepath = sys.argv[1]
user_val = sys.argv[2]
key_val = sys.argv[3]

try:
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
except Exception:
    lines = []

def update_or_append(lines, key, val):
    pattern = re.compile(r'^\s*' + re.escape(key) + r'\s*=')
    updated = False
    new_lines = []
    for line in lines:
        if pattern.match(line):
            new_lines.append(f'{key}={val}\n')
            updated = True
        else:
            new_lines.append(line)
    if not updated:
        if new_lines and not new_lines[-1].endswith('\n'):
            new_lines.append('\n')
        new_lines.append(f'{key}={val}\n')
    return new_lines

lines = update_or_append(lines, 'gpr.user', user_val)
lines = update_or_append(lines, 'gpr.key', key_val)

with open(filepath, 'w', encoding='utf-8') as f:
    f.writelines(lines)
" "$GRADLE_PROPS_FILE" "$EXPECTED_USER" "$EXPECTED_PAT"

    echo "✅ ~/.gradle/gradle.properties 에 gpr.user=${EXPECTED_USER} 및 gpr.key 설정 완료!"
}
