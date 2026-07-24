#!/bin/bash

# =================================================================
# DevTools2 핵심 포터블 도구 설치 스크립트 (2.install-core-tools.sh)
# 대상: Java(8/17/21/25), Gradle, Python, Node.js, Neovim, Ghostty
# =================================================================

if [ -z "${DEVTOOLS2:-}" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")
fi

# 유효한 DEVTOOLS2 폴더가 아니면 표준 경로를 기본값으로 사용
if [ ! -f "$DEVTOOLS2/scripts/linux/devtools2/2.install-core-tools.sh" ]; then
    DEVTOOLS2="/var/opt/_devtools2"
fi

# 공통 색상/스피너 헬퍼 로드 (원격 실행 및 파일 미존재 시 자동 폴백 보장)
_load_colors() {
    [ -n "${_COLORS_LOADED:-}" ] && return 0

    local script_dir; script_dir=$(dirname "$(readlink -f "$0" 2>/dev/null || echo ".")")
    local colors_file="$script_dir/_colors.sh"

    if [ ! -f "$colors_file" ] && [ -n "${DEVTOOLS2:-}" ] && [ -f "$DEVTOOLS2/scripts/linux/devtools2/_colors.sh" ]; then
        colors_file="$DEVTOOLS2/scripts/linux/devtools2/_colors.sh"
    fi

    if [ -f "$colors_file" ]; then
        # shellcheck disable=SC1090
        source "$colors_file" 2>/dev/null && _COLORS_LOADED=true && return 0
    fi

    if curl -sSfL --max-time 5 "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/devtools2/_colors.sh" -o /tmp/_colors_remote.sh 2>/dev/null; then
        # shellcheck disable=SC1091
        source /tmp/_colors_remote.sh 2>/dev/null && _COLORS_LOADED=true && return 0
    fi

    _C_RESET='' _C_BOLD='' _C_CYAN='' _C_GREEN='' _C_YELLOW='' _C_RED='' _C_MAGENTA='' _C_WHITE='' _C_GRAY=''
    if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
        _C_RESET='\033[0m' _C_BOLD='\033[1m' _C_CYAN='\033[0;36m' _C_GREEN='\033[0;32m'
        _C_YELLOW='\033[0;33m' _C_RED='\033[0;31m' _C_MAGENTA='\033[0;36m' _C_WHITE='\033[1;37m'
    fi

    print_info()    { printf "${_C_CYAN}[정보]${_C_RESET} %s\n"    "$*"; }
    print_success() { printf "${_C_GREEN}[성공]${_C_RESET} %s\n"   "$*"; }
    print_done()    { printf "${_C_GREEN}[완료]${_C_RESET} %s\n"   "$*"; }
    print_warn()    { printf "${_C_YELLOW}[경고]${_C_RESET} %s\n"  "$*"; }
    print_error()   { printf "${_C_RED}[오류]${_C_RESET} %s\n"     "$*" >&2; }
    print_step()    { printf "${_C_MAGENTA}%s${_C_RESET}\n"         "$*"; }
    print_sep()     { printf "${_C_MAGENTA}%s${_C_RESET}\n" "==========================================================================="; }
    print_subsep()  { printf "${_C_MAGENTA}%s${_C_RESET}\n" "---------------------------------------------------------------------------"; }
    print_question(){ printf "${_C_BOLD}${_C_CYAN}%s${_C_RESET}\n" "$*"; }
    print_option()  {
        if [ -n "${3:-}" ]; then
            printf "   ${_C_YELLOW}${_C_BOLD}%s)${_C_RESET} ${_C_WHITE}%s${_C_RESET} ${_C_GREEN}${_C_BOLD}%s${_C_RESET}\n" "$1" "$2" "$3"
        else
            printf "   ${_C_YELLOW}${_C_BOLD}%s)${_C_RESET} ${_C_WHITE}%s${_C_RESET}\n" "$1" "$2"
        fi
    }
    prompt_input()  { printf "${_C_YELLOW}${_C_BOLD}%s${_C_RESET} " "$*"; }
    _COLORS_LOADED=true
}
_load_colors

# DEVTOOLS2 기본 폴더 및 필수 서브 디렉토리 존재/권한 확보
if [ ! -d "$DEVTOOLS2" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        mkdir -p "$DEVTOOLS2"
    else
        sudo mkdir -p "$DEVTOOLS2" 2>/dev/null || mkdir -p "$DEVTOOLS2" 2>/dev/null || true
        sudo chown -R "$USER" "$DEVTOOLS2" 2>/dev/null || true
    fi
fi
if [ ! -w "$DEVTOOLS2" ] && [ "$(id -u)" -ne 0 ]; then
    sudo chown -R "$USER" "$DEVTOOLS2" 2>/dev/null || true
    sudo chmod -R u+w "$DEVTOOLS2" 2>/dev/null || true
fi

# tool-versions.toml 경로
TOOL_VERSIONS_TOML="$DEVTOOLS2/scripts/linux/devtools2/tool-versions.toml"

# ─────────────────────────────────────────────────────────────────
# 📄 TOML 유틸리티 함수 (tool-versions.toml 연동)
# ─────────────────────────────────────────────────────────────────

# 지정한 키의 최종 설치 버전 (배열의 첫 번째 값)을 반환합니다.
get_pinned_version() {
    local key="$1"
    grep -E "^${key} = \[" "$TOOL_VERSIONS_TOML" 2>/dev/null \
        | grep -oE '"[^"]+"' | head -1 | tr -d '"'
}

# 지정한 키의 버전 배열 앞에 새 버전을 추가합니다 (이미 있으면 건너뜀).
update_pinned_version() {
    local key="$1" new_ver="$2"
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

# Node.js 최신 v24.x 버전을 반환합니다 ('v' 포함, 예: v24.16.0).
fetch_latest_nodejs() {
    curl -sf --max-time 10 "https://nodejs.org/dist/index.json" \
        2>/dev/null \
        | grep -o '"version":"v24\.[^"]*"' | head -1 \
        | cut -d'"' -f4 || true
}

# 로그 설정: data/logs 폴더에 실행 시점별로 기록
LOG_DIR="$DEVTOOLS2/data/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy_$(date +%Y%m%d_%H%M%S).log"

# 아키텍처 확인
ARCH=$(uname -m)
IS_ARM64=false
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    IS_ARM64=true
fi

# WSL2 환경 감지: /proc/version에 'microsoft' 문자열이 포함되어 있으면 WSL2로 판단한다.
IS_WSL2=false
if grep -qi 'microsoft' /proc/version 2>/dev/null; then
    IS_WSL2=true
fi

# 아키텍처에 따라 적절한 URL을 선택하여 다운로드 및 압축 해제 함수
show_spinner() {
    local pid=$1
    local delay=0.15
    local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_len=${#spinner[@]}
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf " [%s] " "${spinner[i]}"
        i=$(( (i + 1) % spin_len ))
        sleep $delay
        printf "\b\b\b\b\b"
    done
    printf "     \b\b\b\b\b"
}

install_tool() {
    local URL_TEMPLATE="$1"
    local X64_ARCH="$2"
    local ARM_ARCH="$3"
    local TARGET_DIR="$4"
    local SELECTED_ARCH
    local DOWNLOAD_URL
    local FILE_NAME

    # 아키텍처에 맞는 아키텍처 식별 문자열 선택
    if [ "$IS_ARM64" = true ]; then
        SELECTED_ARCH="$ARM_ARCH"
    else
        SELECTED_ARCH="$X64_ARCH"
    fi

    # URL 템플릿의 {ARCH} 치환
    DOWNLOAD_URL="${URL_TEMPLATE//\{ARCH\}/$SELECTED_ARCH}"
    FILE_NAME=$(basename "$DOWNLOAD_URL")

    # 다운로드 및 압축 해제에 스피너 적용
    echo -n "   📥 $TARGET_DIR 다운로드 중..."
    wget -q "$DOWNLOAD_URL" &
    show_spinner $!
    echo " 완료"

    echo -n "   📦 $TARGET_DIR 압축 해제 중..."
    tar -xf "$FILE_NAME" &
    show_spinner $!
    echo " 완료"

    # 폴더 이름 정리 (패턴 매칭으로 이동 후 정리)
    local EXTRACTED_DIR=$(tar -tf "$FILE_NAME" | head -1 | cut -f1 -d"/")
    mv "$EXTRACTED_DIR" "$TARGET_DIR"

    rm "$FILE_NAME"
    echo "   ✅ $TARGET_DIR ($ARCH) 설치 완료"
}

# 모든 표준 출력(stdout)과 표준 에러(stderr)를 터미널과 로그 파일에 동시에 기록
exec > >(tee -i "$LOG_FILE") 2>&1

# ─────────────────────────────────────────────────────────────────
# ⚙️  PRE-FLIGHT: 설치 방식 선택 (Node.js, Ghostty 대상)
# ─────────────────────────────────────────────────────────────────

# 최종 설치 버전 읽기
NODEJS_PINNED=$(get_pinned_version "nodejs")
GHOSTTY_PINNED=$(get_pinned_version "ghostty")

# 설치 상태 확인
NODEJS_INSTALLED=false
[ -d "$DEVTOOLS2/modules/nodejs/node-v24" ] && NODEJS_INSTALLED=true

GHOSTTY_INSTALLED=false
if [ "$IS_WSL2" = false ] && [ -f "$DEVTOOLS2/modules/ghostty/ghostty" ]; then
    GHOSTTY_INSTALLED=true
fi

# 상태 포매팅 헬퍼
_fmts() { [ "$1" = true ] && echo '✅ 설치됨' || echo '⬜ 미설치'; }

echo ""
echo "==========================================================================="
echo "📋 버전 관리 대상 도구 현황 (Node.js, Ghostty)"
echo ""
printf "   %-14s  최종 설치 버전: %-12s  %s\n" \
    "Node.js" "$NODEJS_PINNED" "$(_fmts "$NODEJS_INSTALLED")"
if [ "$IS_WSL2" = false ]; then
    printf "   %-14s  최종 설치 버전: %-12s  %s\n" \
        "Ghostty" "$GHOSTTY_PINNED" "$(_fmts "$GHOSTTY_INSTALLED")"
else
    printf "   %-14s  %-28s  %s\n" \
        "Ghostty" "(WSL2 - 설치 건너뜀)" "⏭️  해당 없음"
fi
echo ""
echo "   ℹ️  Java, Gradle, Python, Neovim, Zed는 버전 고정 설치입니다."
echo ""

# ── 중복 처리 방식 선택 ──────────────────────────────────────────
DUPLICATE_MODE="keep"
_HAS_INSTALLED=false
[ "$NODEJS_INSTALLED" = true ] && _HAS_INSTALLED=true
[ "$IS_WSL2" = false ] && [ "$GHOSTTY_INSTALLED" = true ] && _HAS_INSTALLED=true

if [ "$_HAS_INSTALLED" = true ]; then
    print_question "⚠️  이미 설치된 도구가 감지되었습니다. 중복 처리 방식을 선택하세요:"
    echo ""
    print_option "1" "기존 도구 삭제 후 재설치 (덮어쓰기)"
    print_option "2" "기존 도구 유지 (건너뛰기)" "[기본값]"
    print_option "3" "도구별 개별 확인 (재설치/건너뛰기 선택)"
    echo ""
    read -rp "$(prompt_input "   선택 (1-3, 기본값: 2): ")" _dup_choice
    echo ""
    case "${_dup_choice:-2}" in
        1) DUPLICATE_MODE="remove"     ; print_info "중복 처리: 묻지 않고 삭제 후 재설치 선택됨" ;;
        3) DUPLICATE_MODE="individual" ; print_info "중복 처리: 도구별 개별 확인 선택됨" ;;
        *) DUPLICATE_MODE="keep"       ; print_info "중복 처리: 기존 도구 유지(건너뛰기) 선택됨" ;;
    esac
    echo ""
fi

# ── 버전 설치 방식 선택 ──────────────────────────────────────────
print_question "❓ 적용할 버전 선택 방식을 선택하세요:"
echo ""
print_option "1" "모든 도구 최신 버전으로 설치 (온라인 최신 릴리스)"
print_option "2" "모든 도구 지정 버전으로 설치 (TOML 고정/최종 설치 버전)" "[기본값]"
print_option "3" "도구별 개별 확인 (최신/지정 버전 선택)"
echo ""
read -rp "$(prompt_input "   선택 (1-3, 기본값: 2): ")" _ver_choice
echo ""
case "${_ver_choice:-2}" in
    1) VERSION_MODE="latest"     ; print_info "버전 선택: 모든 도구 최신 버전 선택됨" ;;
    3) VERSION_MODE="individual" ; print_info "버전 선택: 도구별 개별 확인 선택됨" ;;
    *) VERSION_MODE="pinned"     ; print_info "버전 선택: 모든 도구 지정(TOML) 버전 선택됨" ;;
esac

# 설치에 사용할 실제 버전 초기화 (기본: 최종 설치 버전)
NODEJS_VERSION="$NODEJS_PINNED"
GHOSTTY_VERSION="$GHOSTTY_PINNED"

# 일괄 최신 버전 모드: 미리 최신 버전 조회
if [ "$VERSION_MODE" = "latest" ]; then
    echo ""
    echo "   🔍 최신 버전 조회 중..."
    _nl=$(fetch_latest_nodejs)
    if [ -n "$_nl" ]; then
        NODEJS_VERSION="$_nl"
        echo "   ✓ Node.js:  최신 → $_nl  (최종 설치: $NODEJS_PINNED)"
    else
        echo "   ⚠️  Node.js: 최신 버전 조회 실패 → 최종 설치 버전으로 대체: $NODEJS_PINNED"
    fi
    if [ "$IS_WSL2" = false ]; then
        _gl=$(fetch_latest_github "pkgforge-dev/ghostty-appimage" | sed 's/^v//')
        if [ -n "$_gl" ]; then
            GHOSTTY_VERSION="$_gl"
            echo "   ✓ Ghostty:  최신 → $_gl  (최종 설치: $GHOSTTY_PINNED)"
        else
            echo "   ⚠️  Ghostty: 최신 버전 조회 실패 → 최종 설치 버전으로 대체: $GHOSTTY_PINNED"
        fi
    fi
fi

echo ""
echo "==========================================================================="
echo ""

# 오류 발생 시 즉시 중단 설정
set -e

echo ""
echo "==========================================================================="
echo "🚀 DevTools2 포터블 개발 환경 설치를 시작합니다..."
echo ""
echo "📍 최상위 경로: $DEVTOOLS2"
echo "📝 로그 파일: $LOG_FILE"
echo ""

echo "---------------------------------------------------------------------------"
# 1. JAVA 포터블 설치
echo "☕ 1. JAVA 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/java"
cd "$DEVTOOLS2/modules/java"

# JDK 1.8
if [ -d "$DEVTOOLS2/modules/java/jdk-1.8" ]; then
    echo "   ⏭️ [건너뜀] JDK 1.8 설치 디렉토리 jdk-1.8이 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/java/jdk-1.8'"
else
    echo "   📦 JDK 1.8 다운로드 및 압축 해제..."
    install_tool \
        'https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u482-b08/OpenJDK8U-jdk_{ARCH}_linux_hotspot_8u482b08.tar.gz' \
        'x64' \
        'aarch64' \
        'jdk-1.8'
fi

# JDK 17
if [ -d "$DEVTOOLS2/modules/java/jdk-17" ]; then
    echo "   ⏭️ [건너뜀] JDK 17 설치 디렉토리 jdk-17이 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/java/jdk-17'"
else
    echo "   📦 JDK 17 다운로드 및 압축 해제..."
    install_tool \
        'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.18%2B8/OpenJDK17U-jdk_{ARCH}_linux_hotspot_17.0.18_8.tar.gz' \
        'x64' \
        'aarch64' \
        'jdk-17'
fi

# JDK 21
if [ -d "$DEVTOOLS2/modules/java/jdk-21" ]; then
    echo "   ⏭️ [건너뜀] JDK 21 설치 디렉토리 jdk-21이 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/java/jdk-21'"
else
    echo "   📦 JDK 21 다운로드 및 압축 해제..."
    install_tool \
        'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.10%2B7/OpenJDK21U-jdk_{ARCH}_linux_hotspot_21.0.10_7.tar.gz' \
        'x64' \
        'aarch64' \
        'jdk-21'
fi

# JDK 25
if [ -d "$DEVTOOLS2/modules/java/jdk-25" ]; then
    echo "   ⏭️ [건너뜀] JDK 25 설치 디렉토리 jdk-25이 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/java/jdk-25'"
else
    echo "   📦 JDK 25 다운로드 및 압축 해제..."
    install_tool \
        'https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.2%2B10/OpenJDK25U-jdk_{ARCH}_linux_hotspot_25.0.2_10.tar.gz' \
        'x64' \
        'aarch64' \
        'jdk-25'
fi

echo "✅ JAVA 설치 완료 ($ARCH)"
echo ""

echo "---------------------------------------------------------------------------"
# 2. Gradle 포터블 설치
echo "🐘 2. Gradle 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/gradle"
cd "$DEVTOOLS2/modules/gradle"

if [ -d "$DEVTOOLS2/modules/gradle/gradle-9" ]; then
    echo "   ⏭️ [건너뜀] gradle-9 디렉토리가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/gradle/gradle-9'"
else
    echo -n "   📥 Gradle 다운로드 중..."
    wget -q https://services.gradle.org/distributions/gradle-9.4.1-bin.zip &
    show_spinner $!
    echo " 완료"

    echo -n "   📦 Gradle 압축 해제 중..."
    unzip -q gradle-9.4.1-bin.zip &
    show_spinner $!
    echo " 완료"

    mv gradle-9.4.1 gradle-9
    rm -f gradle-9.4.1-bin.zip
fi

echo "✅ Gradle 설치 완료"
echo ""

echo "---------------------------------------------------------------------------"
# 3. Python 포터블 설치
echo "🐍 3. Python 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/python"
cd "$DEVTOOLS2/modules/python"

if [ -d "$DEVTOOLS2/modules/python/python-314" ]; then
    echo "   ⏭️ [건너뜀] python-314 디렉토리가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/python/python-314'"
else
    install_tool \
        'https://github.com/indygreg/python-build-standalone/releases/download/20260414/cpython-3.14.4+20260414-{ARCH}-unknown-linux-gnu-install_only.tar.gz' \
        'x86_64' \
        'aarch64' \
        'python-314'
fi

if [ -d "$DEVTOOLS2/modules/python/python-312" ]; then
    echo "   ⏭️ [건너뜀] python-312 디렉토리가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/python/python-312'"
else
    install_tool \
        'https://github.com/astral-sh/python-build-standalone/releases/download/20260414/cpython-3.12.13+20260414-{ARCH}-unknown-linux-gnu-install_only.tar.gz' \
        'x86_64' \
        'aarch64' \
        'python-312'
fi

echo "✅ Python 설치 완료 ($ARCH)"
echo ""

echo "---------------------------------------------------------------------------"
# 4. Node.js 포터블 설치
echo "🟢 4. Node.js 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/nodejs"
cd "$DEVTOOLS2/modules/nodejs"

# ── 개별 선택 모드: Node.js 버전 결정 ────────────────────────────
if [ "$VERSION_MODE" = "individual" ]; then
    echo -n "   🔍 Node.js 최신 버전 조회 중... "
    set +e; _nl_ind=$(fetch_latest_nodejs); set -e
    [ -n "$_nl_ind" ] && echo "완료 ($_nl_ind)" || echo "실패 (조회 불가)"
    echo ""
    echo "   Node.js 설치 버전 선택:"
    echo "   1) 최신 버전: ${_nl_ind:-[조회 실패 - 선택 불가]}"
    echo "   2) 최종 설치 버전: $NODEJS_PINNED [기본값]"
    echo ""
    read -rp "   선택 (1-2, 기본값: 2): " _nv_sel
    case "${_nv_sel:-2}" in
        1) [ -n "$_nl_ind" ] && NODEJS_VERSION="$_nl_ind" || NODEJS_VERSION="$NODEJS_PINNED" ;;
        *) NODEJS_VERSION="$NODEJS_PINNED" ;;
    esac
    echo ""
fi

# ── 중복 처리: 설치 여부 결정 ────────────────────────────────────
_nodejs_action="install"
if [ "$NODEJS_INSTALLED" = true ]; then
    case "$DUPLICATE_MODE" in
        remove)
            _nodejs_action="reinstall"
            ;;
        individual)
            echo "   ⚠️  node-v24 디렉토리가 이미 존재합니다."
            read -rp "   삭제 후 재설치하시겠습니까? (y/N): " _nd_dup
            case "${_nd_dup:-N}" in
                y|Y) _nodejs_action="reinstall" ;;
                *)   _nodejs_action="skip" ;;
            esac
            ;;
        *)
            _nodejs_action="skip"
            ;;
    esac
fi

# ── 설치 실행 ─────────────────────────────────────────────────────
if [ "$_nodejs_action" = "skip" ]; then
    echo "   ⏭️  [건너뜀] node-v24 디렉토리가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/nodejs/node-v24'"
else
    if [ "$_nodejs_action" = "reinstall" ]; then
        echo "   🗑️  기존 node-v24 디렉토리 삭제 중..."
        rm -rf "$DEVTOOLS2/modules/nodejs/node-v24"
    fi
    echo "   📦 Node.js $NODEJS_VERSION 설치..."
    install_tool \
        "https://nodejs.org/dist/${NODEJS_VERSION}/node-${NODEJS_VERSION}-linux-{ARCH}.tar.xz" \
        'x64' 'arm64' 'node-v24'
    # 최신 버전으로 설치한 경우 이력 업데이트
    if [ "$NODEJS_VERSION" != "$NODEJS_PINNED" ]; then
        update_pinned_version "nodejs" "$NODEJS_VERSION"
    fi
fi

# 전역 패키지 저장소 생성 및 복구
mkdir -p "$DEVTOOLS2/data/.npm-packages"
cd "$DEVTOOLS2/data/.npm-packages"

# 임시 PATH 추가 (방금 설치한 Node.js 바이너리를 현재 셸 환경에 즉시 연동)
export PATH="$DEVTOOLS2/modules/nodejs/node-v24/bin:$PATH"

if [ -f "package.json" ]; then
    _has_npm_pkgs=false
    if [ -d "lib/node_modules" ] && [ -n "$(ls -A lib/node_modules 2>/dev/null)" ]; then
        _has_npm_pkgs=true
    elif [ -d "node_modules" ] && [ -n "$(ls -A node_modules 2>/dev/null)" ]; then
        _has_npm_pkgs=true
    fi

    _do_npm_install=false
    if [ "$_has_npm_pkgs" = true ]; then
        echo ""
        print_warn "이미 글로벌 npm 패키지가 설치되어 있습니다."
        _npm_choice="n"
        if [ -t 0 ]; then
            read -rp "$(prompt_input "   글로벌 npm 패키지를 다시 복구(npm install)하시겠습니까? [y/N, 기본값: N]: ")" _npm_choice
        fi
        _npm_choice_lower=$(echo "${_npm_choice:-n}" | tr '[:upper:]' '[:lower:]')
        if [ "$_npm_choice_lower" = "y" ]; then
            _do_npm_install=true
        else
            print_info "기존 글로벌 npm 패키지를 유지합니다 (건너뜀)."
        fi
    else
        _do_npm_install=true
    fi

    if [ "$_do_npm_install" = true ]; then
        (npm install -q) >/tmp/_npm_install.log 2>&1 &
        _npm_pid=$!
        run_with_spinner "글로벌 npm 패키지 복구 중 (npm install)..." "$_npm_pid"
        wait "$_npm_pid" 2>/dev/null || true
        rm -f /tmp/_npm_install.log 2>/dev/null
        print_done "글로벌 npm 패키지 복구 완료!"
    fi
fi

# rsync를 사용하여 기존 node_modules 내용을 lib/node_modules로 강제 통합(덮어쓰기) 후 기존 디렉토리 삭제
# Windows 글로벌 패키지 경로: .npm-packages/node_modules
# Linux 글로벌 패키지 경로: .npm-packages/lib/node_modules
echo "   📂 npm 패키지 구조 정리 중..."
mkdir -p lib/node_modules
if [ -d "node_modules" ]; then
    rsync -avq --remove-source-files node_modules/ lib/node_modules/
    find node_modules -type d -empty -delete 2>/dev/null
fi
echo "✅ Node.js 설치 완료 ($ARCH)"
echo ""

echo "---------------------------------------------------------------------------"
# 5. Neovim 포터블 설치
echo "💤 5. Neovim 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/neovim"
cd "$DEVTOOLS2/modules/neovim"

if [ -d "$DEVTOOLS2/modules/neovim/nvim" ]; then
    # 사용자에게 선택 입력 요청
    read -p "   ⚠️  neovim 디렉토리가 이미 존재합니다. 삭제하고 새로 설치하시겠습니까? (y/N): " choice

    case "$choice" in
    y | Y)
        echo "   🗑️  기존 디렉토리 삭제 중..."
        rm -rf "$DEVTOOLS2/modules/neovim/nvim"
        echo "   📦 Neovim stable 다운로드 및 압축 해제..."
        install_tool \
            'https://github.com/neovim/neovim/releases/download/stable/nvim-linux-{ARCH}.tar.gz' \
            'x86_64' \
            'arm64' \
            'nvim'
        ;;
    *)
        echo "   ⏭️ [건너뜀] neovim 디렉토리가 이미 존재합니다."
        ;;
    esac
else
    echo "   📦 Neovim stable 다운로드 및 압축 해제..."
    install_tool \
        'https://github.com/neovim/neovim/releases/download/stable/nvim-linux-{ARCH}.tar.gz' \
        'x86_64' \
        'arm64' \
        'nvim'
fi

echo "✅ Neovim 설치 완료 ($ARCH)"
echo ""

echo "---------------------------------------------------------------------------"
# 6. Zed 설치
if [ "$IS_WSL2" = false ]; then
    echo "⚡ 6. Zed 설치 중..."
    if [ -d "$DEVTOOLS2/modules/zed" ]; then
        echo "   ⏭️ [건너뜀] zed 디렉토리가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/zed'"
    else
        echo "   📦 Zed stable 다운로드 및 압축 해제..."
        mkdir -p "$DEVTOOLS2/modules"
        cd "$DEVTOOLS2/modules"

        install_tool \
            'https://github.com/zed-industries/zed/releases/latest/download/zed-linux-{ARCH}.tar.gz' \
            'x86_64' \
            'aarch64' \
            'zed'
    fi
else
    echo "⚡ 6. Zed 설치 단계"
    echo "   ⚠️  [WSL2 환경 감지] WSL2 환경에서는 Windows 호스트에 Zed를 설치하므로 리눅스 내부 Zed 설치는 건너뜁니다."
fi
echo ""

echo "---------------------------------------------------------------------------"
# 7. Ghostty 포터블 설치: https://ghostty.org/
echo "💚 7. Ghostty 포터블 설치 단계"
echo ""

if [ "$IS_WSL2" = true ]; then
    echo "   ⚠️  [WSL2 환경 감지] Ghostty는 WSL2에서 지원되지 않으므로 설치를 건너뜁니다."
    echo "   💬 Windows 네이티브 환경에서 Ghostty를 설치해주세요: https://ghostty.org/"
else
    echo "💚 7. Ghostty 포터블 설치 중..."
    mkdir -p "$DEVTOOLS2/modules/ghostty"
    cd "$DEVTOOLS2/modules/ghostty"

    # ── 개별 선택 모드: Ghostty 버전 결정 ────────────────────────
    if [ "$VERSION_MODE" = "individual" ]; then
        echo -n "   🔍 Ghostty 최신 버전 조회 중... "
        set +e; _gl_ind=$(fetch_latest_github "pkgforge-dev/ghostty-appimage" | sed 's/^v//'); set -e
        [ -n "$_gl_ind" ] && echo "완료 ($_gl_ind)" || echo "실패 (조회 불가)"
        echo ""
        echo "   Ghostty 설치 버전 선택:"
        echo "   1) 최신 버전: ${_gl_ind:-[조회 실패 - 선택 불가]}"
        echo "   2) 최종 설치 버전: $GHOSTTY_PINNED [기본값]"
        echo ""
        read -rp "   선택 (1-2, 기본값: 2): " _gv_sel
        case "${_gv_sel:-2}" in
            1) [ -n "$_gl_ind" ] && GHOSTTY_VERSION="$_gl_ind" || GHOSTTY_VERSION="$GHOSTTY_PINNED" ;;
            *) GHOSTTY_VERSION="$GHOSTTY_PINNED" ;;
        esac
        echo ""
    fi

    # ── 중복 처리: 설치 여부 결정 ────────────────────────────────
    _ghostty_action="install"
    if [ "$GHOSTTY_INSTALLED" = true ]; then
        case "$DUPLICATE_MODE" in
            remove)
                _ghostty_action="reinstall"
                ;;
            individual)
                echo "   ⚠️  ghostty AppImage가 이미 존재합니다."
                read -rp "   삭제 후 재설치하시겠습니까? (y/N): " _gh_dup
                case "${_gh_dup:-N}" in
                    y|Y) _ghostty_action="reinstall" ;;
                    *)   _ghostty_action="skip" ;;
                esac
                ;;
            *)
                _ghostty_action="skip"
                ;;
        esac
    fi

    # ── 설치 실행 ─────────────────────────────────────────────────
    if [ "$_ghostty_action" = "skip" ]; then
        echo "   ⏭️  [건너뜀] ghostty AppImage가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -f '$DEVTOOLS2/modules/ghostty/ghostty'"
    else
        if [ "$_ghostty_action" = "reinstall" ]; then
            echo "   🗑️  기존 ghostty AppImage 삭제 중..."
            rm -f "$DEVTOOLS2/modules/ghostty/ghostty"
        fi
        echo -n "   📦 Ghostty $GHOSTTY_VERSION AppImage 다운로드 중..."
        curl -Ls \
            "https://github.com/pkgforge-dev/ghostty-appimage/releases/download/v${GHOSTTY_VERSION}/Ghostty-${GHOSTTY_VERSION}-${ARCH}.AppImage" \
            -o ghostty &
        show_spinner $!
        echo " 완료"
        chmod +x ghostty

        # 설정 파일 경로 심볼릭 링크 생성
        "$DEVTOOLS2/scripts/linux/cmd/create-symbolic-link.sh" "$DEVTOOLS2/.config/ghostty" "$HOME/.config/ghostty"

        # 최신 버전으로 설치한 경우 이력 업데이트
        if [ "$GHOSTTY_VERSION" != "$GHOSTTY_PINNED" ]; then
            update_pinned_version "ghostty" "$GHOSTTY_VERSION"
        fi
    fi

    echo "✅ Ghostty 설치 완료"
fi
echo ""

echo "---------------------------------------------------------------------------"
echo "🔍 설치 완료: JDK 설치 검증"
echo ""

# 설치된 JDK 확인
echo "[정보] 실제 설치된 JDK 디렉토리:"
INSTALLED_JDKS=""
for jdk_dir in "$DEVTOOLS2/modules/java/jdk-"*; do
    if [ -d "$jdk_dir" ]; then
        if [ -z "$INSTALLED_JDKS" ]; then
            INSTALLED_JDKS="$jdk_dir"
        else
            INSTALLED_JDKS="$INSTALLED_JDKS,$jdk_dir"
        fi
        echo "  ✓ $(basename "$jdk_dir")"
    fi
done

echo ""
echo "[정보] Gradle용 설정값 (1.setup-dev-env.sh에서 사용됨):"
echo "  org.gradle.java.installations.paths=$INSTALLED_JDKS"
echo ""

echo "---------------------------------------------------------------------------"
echo "🎉 모든 포터블 도구 설치가 완료되었습니다!"
echo ""
echo "==========================================================================="
echo ""
