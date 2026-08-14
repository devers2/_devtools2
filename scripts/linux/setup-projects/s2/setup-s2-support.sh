#!/usr/bin/env bash
# ==============================================================================
# s2-support 프로젝트 설정 스크립트
# ==============================================================================
# 실행형 애플리케이션이 아니라 라이브러리(플러그인/의존성 jar) 프로젝트이므로
# bootRun 관련 설정(MAIN_CLASS, launch.json, command-palette 실행 프로필)은
# 만들지 않습니다. 클론 + 편집기 설정 + (선택) Maven Central 배포 설정만 합니다.

set -e

# DEVTOOLS2 경로 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/linux/setup-projects/s2 에서 저장소 루트까지는 4단계 상위
DEVTOOLS2="${DEVTOOLS2:-$(readlink -f "$SCRIPT_DIR/../../../..")}"

# bw-lib 로드 (bw_ensure_session / bw_git_clone / bw_get_fields 포함)
if [ -f "$DEVTOOLS2/scripts/fzf/bw-lib" ]; then
    source "$DEVTOOLS2/scripts/fzf/bw-lib"
else
    echo "❌ bw-lib 라이브러리를 찾을 수 없습니다: $DEVTOOLS2/scripts/fzf/bw-lib"
    exit 1
fi

# 공통 프로젝트 설정 모듈 로드 ($DEVTOOLS2 기준 절대경로 — 하위 디렉토리로 옮겨져도 안전)
if [ -f "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh" ]; then
    source "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"
fi
if [ -f "$DEVTOOLS2/scripts/linux/setup-projects/_common/maven-central-setup.sh" ]; then
    source "$DEVTOOLS2/scripts/linux/setup-projects/_common/maven-central-setup.sh"
fi

TARGET_DIR="$HOME/workspaces/s2/s2-support"
REPO_URL="https://github.com/devers2/s2-support.git"

echo "🚀 [s2-support] 프로젝트 설정을 시작합니다."
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
    bw_git_clone_interactive "$REPO_URL" "$TARGET_DIR" || exit 1
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
# JDK_VERSION = 17: Java 17 문법 호환성을 편집기(JDTLS) 기준 타깃으로 고정합니다.
# (java.lua의 configuration.runtimes 목록에는 17/21/25가 모두 등록되므로, 실제
#  빌드에서 JDK 25 툴체인으로 컴파일하면서 --release 17 등으로 타깃을 낮추는
#  방식도 그대로 지원됩니다 — JDTLS 서버 자체는 항상 JDK 21 이상에서 구동됨)
echo "⚙️  .nvim.lua 설정 파일 생성 중..."
if [ -f "$TARGET_DIR/.nvim.lua" ]; then
    echo "ℹ️  .nvim.lua 이 이미 존재합니다. 덮어쓰지 않습니다 (직접 수정했을 수 있으므로)."
else
    cat > "$TARGET_DIR/.nvim.lua" <<'EOF'
PROJECT_ROOT = "./"
JDK_VERSION = 17
EOF
    echo "✅ .nvim.lua 생성 완료!"
fi

# ==============================================================================
# 4. .vscode/settings.json 생성 - 멱등성 보장
# ==============================================================================
echo "⚙️  .vscode 설정 파일 생성 중..."
VSCODE_DIR="$TARGET_DIR/.vscode"
mkdir -p "$VSCODE_DIR"

JDK17_PATH="${DEVTOOLS2}/modules/java/jdk-17"
JDK25_PATH="${DEVTOOLS2}/modules/java/jdk-25"

if [ -f "$VSCODE_DIR/settings.json" ]; then
    echo "ℹ️  .vscode/settings.json 이 이미 존재합니다. 덮어쓰지 않습니다."
else
    cat > "$VSCODE_DIR/settings.json" <<EOF
{
  "java.configuration.runtimes": [
    {
      "name": "JavaSE-17",
      "path": "${JDK17_PATH}",
      "default": true
    },
    {
      "name": "JavaSE-25",
      "path": "${JDK25_PATH}"
    }
  ],
  "java.import.gradle.java.home": "${JDK25_PATH}"
}
EOF
    echo "✅ .vscode/settings.json 생성 완료"
fi

# ==============================================================================
# 5. Maven Central 배포용 설정 (선택, common-setup.sh/_common: setup_maven_central_publishing)
# ==============================================================================
if command -v setup_maven_central_publishing &>/dev/null; then
    setup_maven_central_publishing "$TARGET_DIR"
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
echo "🎉 [s2-support] 프로젝트 설정이 성공적으로 완료되었습니다!"
echo "📁 프로젝트 위치: $TARGET_DIR"
