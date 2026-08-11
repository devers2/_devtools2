#!/usr/bin/env bash
# ==============================================================================
# Goono-ELN 프로젝트 설정 스크립트
# ==============================================================================

set -e

# DEVTOOLS2 경로 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVTOOLS2="${DEVTOOLS2:-$(readlink -f "$SCRIPT_DIR/../..")}"

# bw-lib 로드 (bw_ensure_session / bw_git_clone / bw_find_item_by_name 포함)
if [ -f "$DEVTOOLS2/scripts/fzf/bw-lib" ]; then
    source "$DEVTOOLS2/scripts/fzf/bw-lib"
else
    echo "❌ bw-lib 라이브러리를 찾을 수 없습니다: $DEVTOOLS2/scripts/fzf/bw-lib"
    exit 1
fi

# 공통 프로젝트 설정 모듈 로드 (setup_gpr_gradle_properties 포함)
if [ -f "$SCRIPT_DIR/common-setup.sh" ]; then
    source "$SCRIPT_DIR/common-setup.sh"
fi

TARGET_DIR="$HOME/workspaces/goono/Goono-ELN"
REPO_URL="https://github.com/redwit-dev/Goono-ELN.git"

echo "🚀 [Goono-ELN] 프로젝트 설정을 시작합니다."
echo "   대상 경로: $TARGET_DIR"

# ==============================================================================
# 1. Bitwarden 세션 확보 (bw-lib: bw_ensure_session)
# ==============================================================================
echo "⏳ Bitwarden 상태 확인 중..."
bw_ensure_session || exit 1

# ==============================================================================
# 2. 깃 클론 (bw-lib: bw_git_clone — Bitwarden PAT 인증 자동)
# ==============================================================================
if [ -d "$TARGET_DIR/.git" ]; then
    echo "ℹ️  이미 깃 저장소가 존재합니다. 클론 단계를 건너뜁니다."
else
    bw_git_clone "$REPO_URL" "$TARGET_DIR" || exit 1
fi

# ==============================================================================
# 2-1. GitHub Packages 의존성 설정 (gpr.user / gpr.key)
# ==============================================================================
if command -v setup_gpr_gradle_properties &>/dev/null; then
    setup_gpr_gradle_properties "$TARGET_DIR"
fi

# ==============================================================================
# 3. .nvim.lua 파일 생성
# ==============================================================================
echo "⚙️  .nvim.lua 설정 파일 생성 중..."
cat > "$TARGET_DIR/.nvim.lua" <<'EOF'
PROJECT_ROOT = "./"
JDK_VERSION = 21
MAIN_CLASS = "so.goono.GoonoELNApplication"
EOF
echo "✅ .nvim.lua 생성 완료!"

# ==============================================================================
# 4. command-palette 이전 실행 프로필 저장 (~/.devtools2/state.properties)
#    command-palette 의 save_state() 와 동일한 방식으로 직접 기록
#    (command-palette 는 인터랙티브 스크립트라 함수 재사용 불가)
# ==============================================================================
echo "⚙️  command-palette 이전 실행 프로필 저장 중..."
DEVTOOLS2_USER_DIR="$HOME/.devtools2"
mkdir -p "$DEVTOOLS2_USER_DIR"
STATE_FILE="$DEVTOOLS2_USER_DIR/state.properties"

NORM_CWD=$(echo "$TARGET_DIR" | tr '\\' '/' | sed 's/\/$//')
PROJ_KEY=$(echo -n "$NORM_CWD" | md5sum | awk '{print $1}')
FULL_KEY="${PROJ_KEY}.gradle_run.profile"
TARGET_VAL="0_DEVELOP,0_LOCAL,s2"

touch "$STATE_FILE"
TMP_STATE=$(mktemp)
grep -v "^${FULL_KEY}=" "$STATE_FILE" > "$TMP_STATE" 2>/dev/null || true
echo "${FULL_KEY}=${TARGET_VAL}" >> "$TMP_STATE"
mv "$TMP_STATE" "$STATE_FILE"
echo "✅ 실행 프로필 저장 완료 ($STATE_FILE)"
echo "   Key  : $FULL_KEY"
echo "   Value: $TARGET_VAL"

# ==============================================================================
# 5. .vscode 설정 생성 (settings.json, launch.json) - 멱등성 보장
# ==============================================================================
echo "⚙️  .vscode 설정 파일 생성 중..."
VSCODE_DIR="$TARGET_DIR/.vscode"
mkdir -p "$VSCODE_DIR"

JDK21_PATH="${DEVTOOLS2}/modules/java/jdk-21"

if [ -f "$VSCODE_DIR/settings.json" ]; then
    echo "ℹ️  .vscode/settings.json 이 이미 존재합니다. 덮어쓰지 않습니다."
else
    cat > "$VSCODE_DIR/settings.json" <<EOF
{
  "java.configuration.runtimes": [
    {
      "name": "JavaSE-21",
      "path": "${JDK21_PATH}",
      "default": true
    }
  ],
  "java.import.gradle.java.home": "${JDK21_PATH}"
}
EOF
    echo "✅ .vscode/settings.json 생성 완료"
fi

# projectName은 일부러 지정하지 않는다. VSCode Java 확장이 실제로 등록하는 프로젝트 이름은
# settings.gradle의 rootProject.name과 다를 수 있고(임포터 종류에 따라 워크스페이스
# 폴더명을 쓰기도 함 — 실측으로 확인됨), 이 스크립트가 미리 알 방법이 없다. projectName을
# 생략하면 vscode-java-debug가 mainClass만으로 워크스페이스를 탐색해 프로젝트를 찾으므로
# 임포터가 어떤 이름을 쓰든 항상 정상 동작한다 (동일 mainClass가 여러 프로젝트에 있는
# 경우가 아니면 모호함이 없음 — 이 저장소는 단일 루트 프로젝트, 서브프로젝트 없음).
if [ -f "$VSCODE_DIR/launch.json" ]; then
    echo "ℹ️  .vscode/launch.json 이 이미 존재합니다. 덮어쓰지 않습니다."
else
    cat > "$VSCODE_DIR/launch.json" <<'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "java",
      "name": "GoonoELNApplication",
      "request": "launch",
      "mainClass": "so.goono.GoonoELNApplication",
      "vmArgs": ["-Dfile.encoding=UTF-8", "-Dspring.profiles.active=0_DEVELOP,0_LOCAL,s2"]
    }
  ]
}
EOF
    echo "✅ .vscode/launch.json 생성 완료!"
fi

# ==============================================================================
# 6. VSCode 필수 확장 프로그램 검사/설치 (Java 개발용)
# ==============================================================================
echo ""
echo "⏳ [Step 6] VSCode Java 확장 프로그램을 확인/설치합니다..."

VSCODE_BIN=""
for _bin in code code-insiders; do
    if command -v "$_bin" &>/dev/null; then
        VSCODE_BIN="$_bin"
        break
    fi
done

_REQUIRED_EXTENSIONS=(
    "redhat.java"
    "vscjava.vscode-java-debug"
    "vscjava.vscode-java-dependency"
)

if [ -z "$VSCODE_BIN" ]; then
    echo "⚠️  VSCode(code) 명령어를 찾을 수 없습니다. 확장 설치를 건너뜁니다."
else
    _INSTALLED_EXTS=$("$VSCODE_BIN" --list-extensions 2>/dev/null || echo "")
    for _ext in "${_REQUIRED_EXTENSIONS[@]}"; do
        if echo "$_INSTALLED_EXTS" | grep -qi "^${_ext}$"; then
            echo "   ✅ 이미 설치됨: $_ext"
        else
            echo "   📦 설치 중: $_ext ..."
            "$VSCODE_BIN" --install-extension "$_ext" --force 2>/dev/null && \
                echo "   ✅ 설치 완료: $_ext" || \
                echo "   ⚠️  설치 실패: $_ext"
        fi
    done
fi

echo ""
echo "🎉 [Goono-ELN] 프로젝트 설정이 성공적으로 완료되었습니다!"
echo "    프로젝트 위치: ~/workspaces/goono/Goono-ELN"
