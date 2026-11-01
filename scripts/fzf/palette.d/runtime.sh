# shellcheck shell=bash
# ==============================================================================
# [명령 팔레트] ☕ 런타임 · SDK — JDK · Python 버전 전환, JDTLS 캐시 초기화
# ==============================================================================
# command-palette 가 source 로 불러오는 파일입니다(단독 실행 X). 구조 설명은 command-palette 의
# "그룹 파일 불러오기" 주석을 보세요. 이 파일 = 1단계 메뉴 그룹 "☕ 런타임 · SDK" (그룹 ID: runtime)

# 지원하는 JDK 및 파이썬 버전 목록 (tool-versions.toml 단일 원천 연동)
SUPPORTED_JDK_VERSIONS=()
_tv_toml="${DEVTOOLS2:-/var/opt/_devtools2}/scripts/linux/dev-env/tool-versions.toml"
if [ -f "$_tv_toml" ]; then
    while IFS= read -r _ver; do
        [ -n "$_ver" ] && SUPPORTED_JDK_VERSIONS+=("$_ver")
    done < <(grep -E '^jdk[0-9]+ = \[' "$_tv_toml" 2>/dev/null | grep -oE 'jdk[0-9]+' | sed 's/^jdk//' | sort -rn || true)
fi
if [ ${#SUPPORTED_JDK_VERSIONS[@]} -eq 0 ]; then
    SUPPORTED_JDK_VERSIONS=("25" "21" "17" "8")
fi
# Python 도 JDK 와 같이 tool-versions.toml 의 python3NN 키(예: python315)에서 지원 버전 목록을 읽습니다 (높은 순)
SUPPORTED_PY_VERSIONS=()
if [ -f "$_tv_toml" ]; then
    while IFS= read -r _ver; do
        [ -n "$_ver" ] && SUPPORTED_PY_VERSIONS+=("$_ver")
    done < <(grep -E '^python3[0-9]+ = \[' "$_tv_toml" 2>/dev/null | grep -oE '^python3[0-9]+' | sed 's/^python//' | sort -rn || true)
fi
if [ ${#SUPPORTED_PY_VERSIONS[@]} -eq 0 ]; then
    SUPPORTED_PY_VERSIONS=("314" "312")
fi

_MENU_RUNTIME=(
    "jdk_switch	JDK 버전 변경 (JDK Switch)"
    "python_switch	Python 버전 변경 (Python Switch)"
    "jdtls_reset	JDTLS 캐시 초기화"
)

# ── 1단계 메뉴 등록 · 2단계 선택 ─────────────────────────────────────────────
cp_register_group runtime "☕ 런타임 · SDK ▸ JDK · Python · JDTLS 캐시"
cp_group_runtime() {
    CHOICE_ID=$(_pick_leaf "☕ 런타임 · SDK > " "${_MENU_RUNTIME[@]}")
}

# ── [JDTLS] 캐시 초기화 ──────────────────────────────────────────────────────
cp_run_jdtls_reset() {
    PROJ_NAME=$(basename "$CWD")

    # OS별 캐시 디렉토리 판단
    XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME_DIR/.cache}"
    JDTLS_CACHE="$XDG_CACHE_HOME/nvim/jdtls/$PROJ_NAME"

    if [ -d "$JDTLS_CACHE" ]; then
        if prompt_confirm "🗑️ JDTLS 캐시를 삭제하시겠습니까? (경로: $JDTLS_CACHE)" "N"; then
            rm -rf "$JDTLS_CACHE"
            echo "✅ JDTLS 캐시 제거 완료: $PROJ_NAME"
        else
            echo "❌ 취소되었습니다."
        fi
    else
        echo "ℹ️ 삭제할 JDTLS 캐시 디렉토리가 존재하지 않습니다: $JDTLS_CACHE"
    fi
}

# ── JDK 버전 변경 (JDK Switch) ───────────────────────────────────────────────
cp_run_jdk_switch() {
    # 기준 경로 설정 (DEVTOOLS2 환경변수 백업)
    DEV_ROOT="${DEVTOOLS2}"
    if [[ -z "$DEV_ROOT" ]]; then
        SCRIPT_PATH="$_CP_SCRIPT_DIR"   # 팔레트 위치 (이 함수는 palette.d 파일에 정의돼 있어 이 파일 기준 경로가 아니라 팔레트 경로를 씀)
        DEV_ROOT="$(cd "$SCRIPT_PATH/../.." && pwd)"
    fi

    echo "🔍 현재 JDK 설정 정보:"
    if [[ -n "$JAVA_HOME" ]]; then
        echo "  - JAVA_HOME: $JAVA_HOME"
    else
        echo "  - JAVA_HOME: 설정되지 않음"
    fi
    if command -v java &>/dev/null; then
        echo "  - java 위치: $(which java)"
        echo "  - java 버전:"
        java -version 2>&1 | sed 's/^/    /'
    else
        echo "  - java 명령어를 찾을 수 없습니다."
    fi
    echo ""

    JDK_CHOICE=$(printf "%s\n" "${SUPPORTED_JDK_VERSIONS[@]}" | fzf --prompt="☕ 변경할 JDK 버전 선택 > " --height=30% --reverse)
    if [[ -z "$JDK_CHOICE" ]]; then
        echo "❌ 취소되었습니다."
        exit 0
    fi

    if [[ "$JDK_CHOICE" == "8" ]]; then
        echo ""
        echo "⚠️  [호환성 주의] Gradle 9 실행 불가 (JVM 17+ 필요)"
        echo "   JDK 8은 레거시 컴파일 호환용입니다. Gradle 9.x 빌드는 JVM 17 이상이 필수이므로,"
        echo "   Java 8 프로젝트 빌드는 Gradle 툴체인(org.gradle.java.installations.paths) 설정을 권장합니다."
        echo ""
    fi

    # Linux (WSL 포함) / macOS 공통
    JDK_SWITCH_SCRIPT="$DEV_ROOT/scripts/linux/cmd/jdk_switch.sh"
    if [[ -f "$JDK_SWITCH_SCRIPT" ]]; then
        source "$JDK_SWITCH_SCRIPT" "$JDK_CHOICE"
    else
        echo "❌ 스위치 스크립트를 찾을 수 없습니다: $JDK_SWITCH_SCRIPT"
    fi

    echo ""
    echo "📢 안내:"
    echo "  - 환경 변수 영구 설정이 변경되었습니다."
    echo "  - 현재 터미널 세션에 즉시 적용하려면 다음 명령을 실행하십시오:"
    if [[ "$SHELL" == *"zsh"* ]]; then
        echo "    source ~/.zshrc"
    else
        echo "    source ~/.bashrc"
    fi
    echo "  - 또는 터미널을 다시 시작(새 창/새 탭)하십시오."
}

# ── Python 버전 변경 (Python Switch) ─────────────────────────────────────────
cp_run_python_switch() {
    # 기준 경로 설정 (DEVTOOLS2 환경변수 백업)
    DEV_ROOT="${DEVTOOLS2}"
    if [[ -z "$DEV_ROOT" ]]; then
        SCRIPT_PATH="$_CP_SCRIPT_DIR"   # 팔레트 위치 (이 함수는 palette.d 파일에 정의돼 있어 이 파일 기준 경로가 아니라 팔레트 경로를 씀)
        DEV_ROOT="$(cd "$SCRIPT_PATH/../.." && pwd)"
    fi

    echo "🔍 현재 Python 설정 정보:"
    if [[ -n "$PYTHON_HOME" ]]; then
        echo "  - PYTHON_HOME: $PYTHON_HOME"
    else
        echo "  - PYTHON_HOME: 설정되지 않음"
    fi
    if command -v python3 &>/dev/null; then
        echo "  - python3 위치: $(which python3)"
        echo "  - python3 버전: $(python3 --version 2>&1)"
    elif command -v python &>/dev/null; then
        echo "  - python 위치: $(which python)"
        echo "  - python 버전: $(python --version 2>&1)"
    else
        echo "  - python 명령어를 찾을 수 없습니다."
    fi
    echo ""

    PY_CHOICE=$(printf "%s\n" "${SUPPORTED_PY_VERSIONS[@]}" | fzf --prompt="🐍 변경할 Python 버전 선택 > " --height=30% --reverse)
    if [[ -z "$PY_CHOICE" ]]; then
        echo "❌ 취소되었습니다."
        exit 0
    fi

    # Linux (WSL 포함) / macOS 공통
    PY_SWITCH_SCRIPT="$DEV_ROOT/scripts/linux/cmd/py_switch.sh"
    if [[ -f "$PY_SWITCH_SCRIPT" ]]; then
        source "$PY_SWITCH_SCRIPT" "$PY_CHOICE"
    else
        echo "❌ 스위치 스크립트를 찾을 수 없습니다: $PY_SWITCH_SCRIPT"
    fi

    echo ""
    echo "📢 안내:"
    echo "  - 환경 변수 영구 설정이 변경되었습니다."
    echo "  - 현재 터미널 세션에 즉시 적용하려면 다음 명령을 실행하십시오:"
    if [[ "$SHELL" == *"zsh"* ]]; then
        echo "    source ~/.zshrc"
    else
        echo "    source ~/.bashrc"
    fi
    echo "  - 또는 터미널을 다시 시작(새 창/새 탭)하십시오."
}
