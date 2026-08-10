#!/bin/bash
# ==============================================================================
# _install-utils.sh — 도구 설치 스크립트 공용 유틸리티
# (2.install-core-tools.sh, 3.install-cli-tools.sh 에서 공용으로 사용)
#
# 전제 조건: 이 파일을 source 하기 전에 아래가 이미 준비되어 있어야 합니다.
#   - $DEVTOOLS2 (설치 루트 경로)
#   - _colors.sh 의 print_*, prompt_input, _C_* 색상 변수 (_load_colors 로 로드됨)
#
# 사용법:
#   source "$(dirname "$(readlink -f "$0")")/_install-utils.sh"
# ==============================================================================

# ── 아키텍처 감지 ──────────────────────────────────────────────────────────
ARCH=$(uname -m)
IS_ARM64=false
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    IS_ARM64=true
fi

# ── WSL2 환경 감지: /proc/version에 'microsoft' 문자열이 포함되어 있으면 WSL2로 판단 ──
IS_WSL2=false
if grep -qi 'microsoft' /proc/version 2>/dev/null; then
    IS_WSL2=true
fi

# ── 필수 패키지 자동 설치 (없으면 apt로 설치 시도) ──────────────────────────
_ensure_pkg() {
    local cmd="$1" pkg="${2:-$1}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -n "   📦 필수 패키지 ($pkg) 자동 설치 중..."
        if command -v sudo >/dev/null 2>&1; then
            sudo apt-get update -qq >/dev/null 2>&1 || true
            sudo apt-get install -y "$pkg" >/dev/null 2>&1 || true
        elif [ "$(id -u)" -eq 0 ]; then
            apt-get update -qq >/dev/null 2>&1 || true
            apt-get install -y "$pkg" >/dev/null 2>&1 || true
        fi
        if command -v "$cmd" >/dev/null 2>&1; then
            echo " 완료"
        else
            echo " 실패"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────
# 📄 TOML 유틸리티 함수 (tool-versions.toml 연동)
# ─────────────────────────────────────────────────────────────────
TOOL_VERSIONS_TOML="$DEVTOOLS2/scripts/linux/dev-env/tool-versions.toml"
_TOML_RAW_URL="https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env/tool-versions.toml"

# 로컬에 없으면 GitHub에서 직접 스트리밍하여 TOML 콘텐츠를 읽는 함수
_read_toml() {
    if [ -f "$TOOL_VERSIONS_TOML" ]; then
        cat "$TOOL_VERSIONS_TOML"
    else
        curl -sSfL --max-time 10 "$_TOML_RAW_URL" 2>/dev/null || true
    fi
}

# 지정한 키의 최종 설치 버전 (배열의 첫 번째 값)을 반환합니다.
get_pinned_version() {
    local key="$1"
    _read_toml \
        | grep -E "^${key} = \[" 2>/dev/null \
        | grep -oE '"[^"]+"' | head -1 | tr -d '"'
}

# 지정한 키의 버전 배열 앞에 새 버전을 추가합니다 (이미 있으면 건너뜀).
update_pinned_version() {
    local key="$1" new_ver="$2"
    # 로컬 TOML이 없으면 업데이트 불가
    if [ ! -f "$TOOL_VERSIONS_TOML" ]; then
        echo "   ⚠️  [tool-versions.toml] 로컬 파일이 없어 버전 이력 업데이트를 건너뜁니다."
        return 0
    fi
    if grep -E "^${key} = \[" "$TOOL_VERSIONS_TOML" 2>/dev/null | grep -qF "\"${new_ver}\""; then
        return 0
    fi
    sed -i "s|^\(${key} = \[\)\(.*\)\]\$|\1\"${new_ver}\", \2]|" "$TOOL_VERSIONS_TOML"
    echo "   📝 [tool-versions.toml] ${key} 버전 이력 추가: \"${new_ver}\""
}

# GitHub 최신 릴리즈 태그를 반환합니다. 실패 시 빈 문자열 반환.
fetch_latest_github() {
    local repo="$1"
    curl -sf --max-time 10 \
        "https://api.github.com/repos/${repo}/releases/latest" \
        2>/dev/null \
        | grep '"tag_name"' | head -1 \
        | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' || true
}

# ─────────────────────────────────────────────────────────────────
# 도구별 설치 액션(install/reinstall/skip) 결정 헬퍼
# 사용법: _resolve_action <IS_INSTALLED> <TOOL_DISPLAY_NAME>
# 결과: echo "install" | "reinstall" | "skip"  (전역 변수 DUPLICATE_MODE 참조)
# ─────────────────────────────────────────────────────────────────
_resolve_action() {
    local is_installed="$1"
    local tool_name="$2"
    if [ "$is_installed" = false ]; then
        echo "install"; return
    fi
    case "$DUPLICATE_MODE" in
        remove)
            echo "reinstall"
            ;;
        individual)
            echo ""
            echo "   ⚠️  ${tool_name}이(가) 이미 설치되어 있습니다."
            prompt_input "   삭제 후 재설치하시겠습니까? [y/${_C_DEFAULT}N${_C_RESET}]: "; read -r _dup_sel
            case "${_dup_sel:-N}" in
                y|Y) echo "reinstall" ;;
                *)   echo "skip" ;;
            esac
            ;;
        *)
            echo "skip"
            ;;
    esac
}

# 설치 상태를 사람이 읽기 좋은 문자열로 표시 (true/false → 이모지+문구)
_fmts() { [ "$1" = true ] && echo '✅ 설치됨' || echo '⬜ 미설치'; }
