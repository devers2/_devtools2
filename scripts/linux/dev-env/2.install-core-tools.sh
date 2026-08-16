#!/bin/bash

# =================================================================
# DevTools2 핵심 포터블 도구 설치 스크립트 (2.install-core-tools.sh)
# 대상: Java(8/17/21/25), Gradle, Python, Node.js, Neovim, VSCode, Zed, Ghostty
# =================================================================

if [ -z "${DEVTOOLS2:-}" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")
fi

# 유효한 DEVTOOLS2 폴더가 아니면 표준 경로를 기본값으로 사용
if [ ! -f "$DEVTOOLS2/scripts/linux/dev-env/2.install-core-tools.sh" ]; then
    DEVTOOLS2="/var/opt/_devtools2"
fi

# 공통 색상/스피너 헬퍼 로드 (온라인 전용)
_load_colors() {
    [ -n "${_COLORS_LOADED:-}" ] && return 0

    # 캐시 우회 헤더 포함 (run_remote_script와 동일) — CDN이 방금 푸시 전 구버전을
    # 서빙하면 "진입 스크립트는 최신인데 _colors.sh만 구버전"이 될 수 있으므로 필수.
    # curl의 실제 실패 사유(stderr)를 버리지 않고 그대로 보여줘야 나중에 원인 진단이 가능하다.
    # 고정된 /tmp/_colors_remote.sh 경로를 쓰면, 이 스크립트를 실행하는 사용자가 바뀔 때
    # (예: 0.init은 root로, 1.setup-env는 일반 사용자로) /tmp의 sticky bit 때문에 이전
    # 실행자가 만든 파일을 지금 사용자가 덮어쓰지 못해 curl이 쓰기 실패(exit 23)한다
    # (실측으로 재현 확인). mktemp로 매번 고유한 파일을 만들어 이 충돌을 없앤다.
    local _tmpfile _curl_err _curl_ec=0
    _tmpfile=$(mktemp) || { echo "[오류] 임시 파일 생성에 실패했습니다." >&2; exit 1; }
    _curl_err=$(curl -sSfL --max-time 5 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env/_colors.sh" -o "$_tmpfile" 2>&1) || _curl_ec=$?
    if [ "$_curl_ec" -eq 0 ]; then
        # shellcheck disable=SC1090
        if source "$_tmpfile" 2>/dev/null; then
            rm -f "$_tmpfile"
            _COLORS_LOADED=true
            return 0
        fi
        rm -f "$_tmpfile"
        echo "[오류] _colors.sh를 다운로드했지만 source 실행 중 오류가 발생했습니다." >&2
        exit 1
    fi

    rm -f "$_tmpfile"
    echo "[오류] _colors.sh를 온라인에서 불러오지 못했습니다 (curl 종료 코드: $_curl_ec)." >&2
    [ -n "$_curl_err" ] && echo "  curl: $_curl_err" >&2
    echo "  네트워크 연결을 확인하세요." >&2
    exit 1
}
_load_colors

# 공통 설치 유틸리티 로드 (ARCH/IS_ARM64/IS_WSL2 감지, _ensure_pkg, TOML 버전 관리,
# _resolve_action, _fmts 등 — 3.install-cli-tools.sh 와 공유)
_load_install_utils() {
    [ -n "${_INSTALL_UTILS_LOADED:-}" ] && return 0

    # 온라인 전용, 캐시 우회 헤더 및 mktemp 이유는 _load_colors 주석 참고.
    # TOOL_VERSIONS_TOML 등은 인라인 대체가 불가능해서 실패하면 바로 하드 실패한다.
    local _tmpfile _curl_err _curl_ec=0
    _tmpfile=$(mktemp) || { print_error "임시 파일 생성에 실패했습니다."; exit 1; }
    _curl_err=$(curl -sSfL --max-time 5 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env/_install-utils.sh" -o "$_tmpfile" 2>&1) || _curl_ec=$?
    if [ "$_curl_ec" -eq 0 ]; then
        # shellcheck disable=SC1090
        if source "$_tmpfile" 2>/dev/null; then
            rm -f "$_tmpfile"
            _INSTALL_UTILS_LOADED=true
            return 0
        fi
        rm -f "$_tmpfile"
        print_error "_install-utils.sh를 다운로드했지만 source 실행 중 오류가 발생했습니다."
        exit 1
    fi

    rm -f "$_tmpfile"
    print_error "_install-utils.sh를 온라인에서 불러오지 못했습니다 (curl 종료 코드: $_curl_ec)."
    [ -n "$_curl_err" ] && print_error "  curl: $_curl_err"
    print_error "  네트워크 연결을 확인하세요."
    exit 1
}
_load_install_utils

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

_ensure_pkg unzip
_ensure_pkg tar
_ensure_pkg curl
_ensure_pkg wget

# ─────────────────────────────────────────────────────────────────
# 📄 이 스크립트 전용 TOML 버전 조회 함수 (Node.js는 GitHub API가 아닌
# nodejs.org 자체 인덱스를 써야 해서 _install-utils.sh 공용 함수로 옮기지 않음)
# ─────────────────────────────────────────────────────────────────

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

# ARCH/IS_ARM64/IS_WSL2/show_spinner 는 _install-utils.sh / _colors.sh 에서 로드됨

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

# 상태 포매팅 헬퍼(_fmts)는 _install-utils.sh 에서 로드됨

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
    prompt_input "   선택 [1/${_C_DEFAULT}2${_C_RESET}/3]: "; read -r _dup_choice
    echo ""
    case "${_dup_choice:-2}" in
        1) DUPLICATE_MODE="remove"     ; print_info "중복 처리: 묻지 않고 삭제 후 재설치 선택됨" ;;
        3) DUPLICATE_MODE="individual" ; print_info "중복 처리: 도구별 개별 확인 선택됨" ;;
        *) DUPLICATE_MODE="keep"       ; print_info "중복 처리: 기존 도구 유지(건너뛰기) 선택됨" ;;
    esac
    echo ""
fi

# ── 버전 설치 방식 선택 ──────────────────────────────────────────
# _select_version_mode() 는 _install-utils.sh 에서 로드됨 (3.install-cli-tools.sh 와 공유)
_select_version_mode

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
    prompt_input "   선택 [1/${_C_DEFAULT}2${_C_RESET}]: "; read -r _nv_sel
    case "${_nv_sel:-2}" in
        1) [ -n "$_nl_ind" ] && NODEJS_VERSION="$_nl_ind" || NODEJS_VERSION="$NODEJS_PINNED" ;;
        *) NODEJS_VERSION="$NODEJS_PINNED" ;;
    esac
    echo ""
fi

# ── 중복 처리: 설치 여부 결정 ────────────────────────────────────
_nodejs_action=$(_resolve_action "$NODEJS_INSTALLED" "Node.js")

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
            prompt_input "   글로벌 npm 패키지를 다시 복구(npm install)하시겠습니까? [y/${_C_DEFAULT}N${_C_RESET}]: "
            read -r _npm_choice
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
        show_spinner "$_npm_pid"
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
    prompt_input "   ⚠️  neovim 디렉토리가 이미 존재합니다. 삭제하고 새로 설치하시겠습니까? [y/${_C_DEFAULT}N${_C_RESET}]: "; read -r choice

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
# 6. VSCode 설치 (Linux 네이티브 전용 - WSL은 Windows에서 관리)
echo "💻 6. VSCode 단계"
echo ""

# [6-1] VSCode 바이너리 설치 (Linux 네이티브 전용)
#   WSL은 Windows 호스트에 VSCode가 이미 설치되어 있으므로 리눅스 내부 설치 건너뜀
if [ "$IS_WSL2" = true ]; then
    echo "   ⚠️  [WSL2 환경] VSCode는 Windows 호스트에 설치되므로 Linux 내부 설치를 건너뜁니다."
elif command -v code >/dev/null 2>&1; then
    echo "   ⏭️ [건너뜀] VSCode가 이미 설치되어 있습니다: $(command -v code)"
else
    echo ""
    printf "   👉 VS Code (Visual Studio Code)를 설치하시겠습니까? [y/\\033[1;32mN\\033[0m]: "
    if [ -t 0 ]; then
        read -r _vscode_choice
    else
        _vscode_choice="N"
    fi
    echo ""
    case "${_vscode_choice:-N}" in
        y|Y)
            echo "   📦 VSCode .deb 패키지 다운로드 및 설치 중..."
            _vscode_tmp="/tmp/vscode_install_$$.deb"
            if curl -Ls "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" -o "$_vscode_tmp"; then
                sudo dpkg -i "$_vscode_tmp" 2>/dev/null || sudo apt-get install -f -y 2>/dev/null || true
                rm -f "$_vscode_tmp"
                echo "   ✅ VSCode 설치 완료"
            else
                echo "   ⚠️  VSCode 다운로드 실패. 수동으로 설치하세요: https://code.visualstudio.com/"
                rm -f "$_vscode_tmp"
            fi
            ;;
        *)
            echo "   ⏭️ VSCode 설치를 건너뜁니다. 기존 설정은 유지됩니다."
            ;;
    esac
fi

# [6-2] VSCode 확장 자동 설치 (extensions.txt 기반)
#   WSL / Linux 네이티브 상관없이 code 명령이 존재하면 항상 실행
#   WSL: Windows code CLI 가 interop으로 동작 / Linux 네이티브: /usr/bin/code
VSCODE_EXT_LIST="$DEVTOOLS2/.config/vscode/extensions.txt"
if command -v code >/dev/null 2>&1 && [ -f "$VSCODE_EXT_LIST" ]; then
    echo ""
    echo -n "   📋 VSCode 기존 확장 목록 조회 중..."
    (code --list-extensions 2>/dev/null </dev/null > /tmp/_vscode_installed.tmp) &
    _ext_list_pid=$!
    show_spinner "$_ext_list_pid"
    wait "$_ext_list_pid" 2>/dev/null || true
    echo " 완료"
    _INSTALLED_EXTS=$(tr '[:upper:]' '[:lower:]' < /tmp/_vscode_installed.tmp 2>/dev/null || echo "")
    rm -f /tmp/_vscode_installed.tmp 2>/dev/null

    echo "   📋 VSCode 확장 프로그램 설치 중 (extensions.txt 기반)..."
    _vscode_install_count=0
    _vscode_skip_count=0
    _vscode_fail_count=0
    while IFS= read -r ext_line || [ -n "$ext_line" ]; do
        ext=$(echo "$ext_line" | tr -d '\r' | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$ext" ] && continue
        ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        if echo "$_INSTALLED_EXTS" | grep -qF "$ext_lower"; then
            echo "   ⏭️  [건너뜀] $ext (이미 설치됨)"
            _vscode_skip_count=$((_vscode_skip_count + 1))
        else
            echo -n "   📥 [설치] $ext ..."
            _ok=0
            for _retry in 1 2 3; do
                (code --install-extension "$ext" --force </dev/null >/dev/null 2>&1) &
                _ext_pid=$!
                show_spinner "$_ext_pid"
                _ext_ec=0
                wait "$_ext_pid" 2>/dev/null || _ext_ec=$?
                if [ "$_ext_ec" -eq 0 ]; then
                    _ok=1
                    break
                fi
                sleep 2
            done
            if [ "$_ok" -eq 1 ]; then
                echo " ✅"
                _vscode_install_count=$((_vscode_install_count + 1))
            else
                echo " ⚠️  실패 (3회 시도)"
                _vscode_fail_count=$((_vscode_fail_count + 1))
            fi
        fi
    done < "$VSCODE_EXT_LIST"
    echo ""
    echo "   [요약] 신규 설치: ${_vscode_install_count}개 / 이미 설치: ${_vscode_skip_count}개 / 실패: ${_vscode_fail_count}개"
elif ! command -v code >/dev/null 2>&1; then
    echo "   ⚠️  code 명령을 찾을 수 없어 확장 설치를 건너뜁니다."
else
    echo "   ⚠️  extensions.txt 없음: $VSCODE_EXT_LIST"
fi
echo "✅ VSCode 단계 완료"
echo ""

echo "---------------------------------------------------------------------------"
# 7. Zed 설치
echo "⚡ 7. Zed 설치 단계"
echo ""

if [ "$IS_WSL2" = true ]; then
    echo "   ⚠️  [WSL2 환경 감지] WSL2 환경에서는 Windows 호스트에 Zed를 설치하므로 리눅스 내부 Zed 설치는 건너뜁니다."
elif [ -d "$DEVTOOLS2/modules/zed" ]; then
    echo "   ⏭️ [건너뜀] zed 디렉토리가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/zed'"
else
    echo ""
    printf "   👉 Zed 에디터를 설치하시겠습니까? [y/\033[1;32mN\033[0m]: "
    if [ -t 0 ]; then
        read -r _zed_choice
    else
        _zed_choice="N"
    fi
    echo ""
    case "${_zed_choice:-N}" in
        y|Y)
            echo "   📦 Zed stable 다운로드 및 압축 해제..."
            mkdir -p "$DEVTOOLS2/modules"
            cd "$DEVTOOLS2/modules"
            install_tool \
                'https://github.com/zed-industries/zed/releases/latest/download/zed-linux-{ARCH}.tar.gz' \
                'x86_64' \
                'aarch64' \
                'zed'
            ;;
        *)
            echo "   ⏭️ Zed 에디터 설치를 건너뜁니다. 기존 설정은 유지됩니다."
            ;;
    esac
fi
echo ""

echo "---------------------------------------------------------------------------"
# 8. Ghostty 포터블 설치: https://ghostty.org/
echo "💚 8. Ghostty 포터블 설치 단계"
echo ""

if [ "$IS_WSL2" = true ]; then
    echo "   ⚠️  [WSL2 환경 감지] Ghostty는 WSL2에서 지원되지 않으므로 설치를 건너뜁니다."
    echo "   💬 Windows 네이티브 환경에서 Ghostty를 설치해주세요: https://ghostty.org/"
else
    echo "💚 8. Ghostty 포터블 설치 중..."
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
    _ghostty_action=$(_resolve_action "$GHOSTTY_INSTALLED" "Ghostty")

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
        # (로컬에 create-symbolic-link.sh가 없으면 GitHub에서 직접 스트리밍 실행 —
        #  다른 심볼릭 링크 호출들과 동일하게 온라인 전용 실행에서도 항상 동작하도록 보장)
        _ghostty_symlink_script="$DEVTOOLS2/scripts/linux/cmd/create-symbolic-link.sh"
        if [ -f "$_ghostty_symlink_script" ]; then
            "$_ghostty_symlink_script" "$DEVTOOLS2/.config/ghostty" "$HOME/.config/ghostty"
        else
            curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/cmd/create-symbolic-link.sh" \
                | bash -s -- "$DEVTOOLS2/.config/ghostty" "$HOME/.config/ghostty"
        fi

        # 최신 버전으로 설치한 경우 이력 업데이트
        if [ "$GHOSTTY_VERSION" != "$GHOSTTY_PINNED" ]; then
            update_pinned_version "ghostty" "$GHOSTTY_VERSION"
        fi
    fi

    echo "✅ Ghostty 설치 완료"
fi
echo ""

echo "---------------------------------------------------------------------------"
# 9. Orca 설치 (멀티 에이전트 오케스트레이션 ADE): https://github.com/stablyai/orca
#    전체 설치 과정의 마지막 단계 — Zed 설치 여부를 물은 바로 다음에 위치.
#
#    ⚠️ Zed/Ghostty와 달리 WSL2에서도 "건너뛰지 않고" 여기(리눅스 내부)에 설치합니다.
#    이유: Orca는 Claude Code/Codex/Gemini 같은 CLI 에이전트를 직접 실행(spawn)해야 하는데,
#    그 CLI들은 (npm i -g @anthropic-ai/claude-code 등으로) 전부 이 WSL2 내부에 설치되어
#    있습니다. Orca를 Windows 네이티브로만 설치하면 WSL2 안의 그 바이너리를 실행할 방법이
#    없습니다(공식 문서에 WSL 브릿지 기능 없음). 대신 Orca 공식 "Remote Orca Servers" 모드를
#    사용합니다: 에이전트 실행부(orca serve)는 CLI가 실제로 있는 WSL2에 헤드리스로 두고,
#    Windows에는 거기 페어링만 하는 가벼운 GUI 클라이언트를 설치합니다(4.setup-orca.ps1).
echo "🐋 9. Orca 설치 단계"
echo ""

ORCA_DIR="$DEVTOOLS2/modules/orca"
if [ "$IS_ARM64" = true ]; then
    ORCA_APPIMAGE_NAME="orca-linux-arm64.AppImage"
else
    ORCA_APPIMAGE_NAME="orca-linux.AppImage"
fi
ORCA_APPIMAGE="$ORCA_DIR/$ORCA_APPIMAGE_NAME"

_orca_proceed=false

if [ -f "$ORCA_APPIMAGE" ]; then
    echo "   ⏭️ [건너뜀] orca AppImage가 이미 존재합니다. (재설치하려면 삭제: sudo rm -rf '$ORCA_DIR')"
    if [ "${DT2_ORCA_CHOICE:-}" = "N" ] || [ "${DT2_ORCA_CHOICE:-}" = "n" ]; then
        # Windows 쪽에서 이번 실행은 명시적으로 N을 선택한 경우 — systemd/페어링 재점검도
        # 이번엔 건너뜁니다(4.setup-orca.ps1도 이번엔 안 돌기 때문에 재점검해봐야 그 결과를
        # 받아줄 곳이 없어 불필요한 작업이 됨).
        echo "   ℹ️  이번 실행은 Windows 쪽에서 'N'을 선택하셔서 systemd/페어링 재점검도 건너뜁니다."
    else
        echo "   ℹ️  이미 설치되어 있어도 아래 systemd/페어링 상태는 매번 다시 점검합니다"
        echo "      (예: systemd 활성화를 위해 WSL을 재시작하고 이 스크립트를 다시 실행한 경우)."
        _orca_proceed=true
    fi
else
    echo "   ℹ️  Orca는 여러 코딩 에이전트를 Git worktree로 격리해 병렬로 실행/조율하는"
    echo "      에이전트 오케스트레이션 도구입니다 (Claude Code, Codex, Gemini 등 지원)."
    echo ""
    if [ -n "${DT2_ORCA_CHOICE:-}" ]; then
        # setup-devtools2-wsl.ps1(Windows)에서 Zed 질문 직후 이미 물어본 답을 그대로 사용합니다.
        # WSL2 조합에서 여기서 또 물으면 같은 질문을 두 번 하게 되므로 건너뜁니다.
        _orca_choice="$DT2_ORCA_CHOICE"
        echo "   ℹ️  Windows 쪽에서 이미 선택하신 값을 사용합니다: ${_orca_choice}"
    else
        printf "   👉 Orca를 설치하시겠습니까? [y/\033[1;32mN\033[0m]: "
        if [ -t 0 ]; then
            read -r _orca_choice
        else
            _orca_choice="N"
        fi
    fi
    echo ""
    case "${_orca_choice:-N}" in
        y|Y)
            if [ "$IS_WSL2" = true ]; then
                echo "   ⚠️  [WSL2 환경 감지] Orca 실행부(orca serve)는 CLI 에이전트가 실제로 설치된"
                echo "      이 WSL2 내부에 헤드리스로 설치합니다. Windows 쪽에는 여기 페어링만 하는"
                echo "      GUI 클라이언트가 별도로 설치됩니다(setup-devtools2-wsl.ps1 마지막 단계)."
                echo ""
            fi

            mkdir -p "$ORCA_DIR"
            echo -n "   📥 orca 다운로드 중..."
            curl -Ls "https://github.com/stablyai/orca/releases/latest/download/${ORCA_APPIMAGE_NAME}" -o "$ORCA_APPIMAGE" &
            show_spinner $!
            echo " 완료"
            chmod +x "$ORCA_APPIMAGE"
            echo "   ✅ orca ($ARCH) 설치 완료 → $ORCA_APPIMAGE"
            _orca_proceed=true
            ;;
        *)
            echo "   ⏭️ Orca 설치를 건너뜁니다."
            ;;
    esac
fi

if [ "$_orca_proceed" = true ]; then
    # orca AppImage 실행에 필요한 의존성 (공식 헤드리스 서버 가이드 기준:
    # curl file jq xvfb zlib1g-dev). curl은 이미 이 저장소 전체가 의존하므로 생략.
    # 이미 설치된 상태로 재실행돼도 전부 존재 여부부터 확인하고 스킵하므로 안전합니다.
    _ensure_pkg file file
    _ensure_pkg jq jq
    _ensure_pkg Xvfb xvfb
    if ! dpkg -s libfuse2 >/dev/null 2>&1 && ! dpkg -s libfuse2t64 >/dev/null 2>&1; then
        echo -n "   📦 필수 패키지 (libfuse2) 자동 설치 중..."
        sudo apt-get update -qq >/dev/null 2>&1 || true
        sudo apt-get install -y libfuse2t64 >/dev/null 2>&1 || sudo apt-get install -y libfuse2 >/dev/null 2>&1 || true
        echo " 완료"
    fi
    if ! dpkg -s zlib1g-dev >/dev/null 2>&1; then
        echo -n "   📦 필수 패키지 (zlib1g-dev) 자동 설치 중..."
        sudo apt-get update -qq >/dev/null 2>&1 || true
        sudo apt-get install -y zlib1g-dev >/dev/null 2>&1 || true
        echo " 완료"
    fi

    # PATH에서 'orca'라는 짧은 이름으로 바로 실행할 수 있도록 심볼릭 링크 생성
    # (상대 경로 링크라 $DEVTOOLS2가 통째로 이동해도 깨지지 않음). ln -sf라 재실행해도 안전.
    ln -sf "$ORCA_APPIMAGE_NAME" "$ORCA_DIR/orca"

    # 설정/상태 디렉터리 심볼릭 링크. Orca는 아래 세 곳을 모두 씁니다(공식 문서 확인):
    # 소문자 ~/.config/orca, Electron GUI용 대문자 ~/.config/Orca, 그리고 keybindings.json
    # 등 CLI 전역 설정용 ~/.orca. 안 쓰는 게 있어도 빈 심볼릭 링크라 해될 게 없어 셋 다 둡니다.
    _orca_symlink_script="$DEVTOOLS2/scripts/linux/cmd/create-symbolic-link.sh"
    _orca_link() {
        if [ -f "$_orca_symlink_script" ]; then
            "$_orca_symlink_script" "$1" "$2"
        else
            curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/cmd/create-symbolic-link.sh" \
                | bash -s -- "$1" "$2"
        fi
    }
    _orca_link "$DEVTOOLS2/.config/orca" "$HOME/.config/orca"
    _orca_link "$DEVTOOLS2/.config/Orca" "$HOME/.config/Orca"
    _orca_link "$DEVTOOLS2/.config/orca-home" "$HOME/.orca"

    # ── 권장 스킬 전역 설치 (베스트 에포트) ──
            # orca-cli/orchestration은 공식 문서가 일반적인 기본 조합으로 예시하는 스킬입니다.
            # CLI 에이전트(claude/codex 등)가 아직 없으면 그냥 아무것도 안 하고 넘어갑니다
            # (에이전트 설치 후 'orca skills install --all' 로 나중에 다시 돌리면 됩니다).
            # orca serve 데몬을 아직 띄우기 전에 실행합니다 — 같은 AppImage를 동시에 두 번
            # 띄웠을 때 생길 수 있는 Electron 단일 인스턴스 락 충돌 가능성을 애초에 피하기 위함.
            # timeout으로 감싸는 이유: 실패해도 무해해야 할 이 단계가 혹시라도 응답 없이 멈추면
            # (예: 디스플레이 요구) 전체 devtools2 설치가 그 자리에서 무한 대기하게 되기 때문.
            # 공식 문서(onorca.dev/docs/cli/skills)가 헤드리스 호스트(SSH/컨테이너/CI/orca serve)용으로
            # 정확히 명시한 명령입니다: "orca skills install --skill orca-cli --skill orchestration"
            # (--global 플래그는 문서 예시에 없어 임의로 추가하지 않음 — 헤드리스 CLI 래퍼는 애초에
            # 전역 스코프만 의미가 있어 기본값이 global인 것으로 보입니다).
            echo ""
            echo "   🧩 권장 스킬(orca-cli, orchestration) 설치 시도 중..."
            timeout 20 "$ORCA_DIR/orca" skills install --skill orca-cli --skill orchestration >/dev/null 2>&1 \
                && echo "   ✅ 스킬 설치 완료 (감지된 에이전트가 없었다면 지금은 조용히 아무 일도 안 했을 수 있음)" \
                || echo "   ⚠️  스킬 설치를 건너뜁니다(타임아웃 또는 미감지 — 에이전트 CLI 설치 후 'orca skills install --all'로 다시 시도 가능)"

            # ── WSL2: orca serve 헤드리스 자동 실행 등록 + 페어링 링크 자동 확보 ──
            # systemd가 이미 활성화돼 있으면 바로 등록하고, 아직이면 common-setup.sh의
            # setup_rclone_sftp_mount와 동일하게 wsl.conf 자동 설정 + 재시작 안내로 처리합니다.
            if [ "$IS_WSL2" = true ]; then
                echo ""

                # ⚠️ 127.0.0.1은 Orca 공식 문서가 "원격 클라이언트 페어링에 쓰지 말라"고 명시적으로
                # 경고하는 주소라 쓰지 않습니다. 대신 WSL2 자체 IP(Windows에서 직접 라우팅 가능)를
                # 매번 기동 시점에 새로 조회하는 래퍼 스크립트를 둡니다 — WSL2 IP는 재부팅마다
                # 바뀔 수 있어 systemd 유닛 파일에 고정 IP를 박아두면 재부팅 후 깨지기 때문입니다.
                # LIBGL_ALWAYS_SOFTWARE=1도 여기 직접 넣어둡니다 — systemd의 Environment= 줄에만
                # 있으면 "systemctl 없음" 폴백으로 이 파일을 수동 실행할 때는 안 먹기 때문입니다.
                cat > "$ORCA_DIR/orca-serve-wrapper.sh" <<EOF
#!/bin/bash
export LIBGL_ALWAYS_SOFTWARE=1
exec "$ORCA_APPIMAGE" serve --port 6768 --pairing-address "\$(hostname -I | awk '{print \$1}')"
EOF
                chmod +x "$ORCA_DIR/orca-serve-wrapper.sh"

                # ⚠️ command -v systemctl 만으로는 부족합니다 — Ubuntu는 systemd 패키지가
                # 기본 설치돼 있어 WSL2에서 systemd가 실제로 PID 1로 안 떠 있어도 systemctl
                # 바이너리 자체는 존재합니다. 실제 동작 여부는 'systemctl --user status'의
                # 종료 코드로 확인해야 합니다(common-setup.sh의 setup_rclone_sftp_mount와
                # 동일한 검증 방식 — 이 저장소에서 이미 검증된 패턴을 그대로 재사용).
                if systemctl --user status >/dev/null 2>&1; then
                    echo "   ⚙️  systemd 사용자 서비스로 'orca serve' 자동 실행을 등록합니다..."
                    mkdir -p "$HOME/.config/systemd/user"
                    # 공식 헤드리스 가이드(docs/reference/headless-linux-server.md)의 systemd
                    # 예시를 그대로 따릅니다: StartLimitIntervalSec/Burst로 재시작 폭주 방지,
                    # RestartPreventExitStatus=3(= "이미 같은 userData 프로필을 쓰는 다른 인스턴스가
                    # 떠 있음" — 재시작해봐야 성공할 수 없는 경우라 그냥 멈춤), KillMode=mixed로
                    # 내부 Xvfb가 깨끗이 종료되도록 함.
                    cat > "$HOME/.config/systemd/user/orca-serve.service" <<EOF
[Unit]
Description=Orca headless agent orchestration server
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
WorkingDirectory=%h
ExecStart=$ORCA_DIR/orca-serve-wrapper.sh
KillMode=mixed
Restart=on-failure
RestartPreventExitStatus=3
RestartSec=5

[Install]
WantedBy=default.target
EOF
                    systemctl --user daemon-reload 2>/dev/null || true
                    if systemctl --user enable --now orca-serve.service 2>/dev/null; then
                        echo "   ✅ orca-serve.service 등록 및 실행 완료 (포트 6768)"

                        # 페어링 링크 자동 확보 시도(베스트 에포트, 최대 20초 폴링). 헤드리스
                        # 리눅스에서는 pairing 코드가 아예 출력되지 않는 알려진 미해결 버그가
                        # 있어(stablyai/orca#9759) 안 나와도 정상입니다 — 그 경우 대체 안내를 출력합니다.
                        _orca_pair_link=""
                        for _i in 1 2 3 4 5 6 7 8 9 10; do
                            sleep 2
                            _orca_pair_link=$(journalctl --user -u orca-serve.service --no-pager -n 80 2>/dev/null | grep -oE 'orca://pair[^[:space:]]*' | tail -1)
                            [ -n "$_orca_pair_link" ] && break
                        done
                        mkdir -p "$DEVTOOLS2/data"
                        if [ -n "$_orca_pair_link" ]; then
                            echo "$_orca_pair_link" > "$DEVTOOLS2/data/orca-pairing-link.txt"
                            echo "   🔗 페어링 링크 확보: $_orca_pair_link"
                            echo "      (Windows 쪽 4.setup-orca.ps1 이 이 링크를 자동으로 읽어갑니다)"
                        else
                            rm -f "$DEVTOOLS2/data/orca-pairing-link.txt"
                            echo "   ⚠️  페어링 링크를 자동으로 찾지 못했습니다(알려진 업스트림 버그일 수 있음:"
                            echo "      https://github.com/stablyai/orca/issues/9759 )."
                            echo "      필요하면 직접 확인: journalctl --user -u orca-serve.service --no-pager | grep orca://"
                        fi
                    else
                        echo "   ⚠️  systemd --user 서비스 활성화 실패. 수동 실행: $ORCA_DIR/orca-serve-wrapper.sh &"
                        echo "   💬 반복 실패로 재시작 제한(StartLimitBurst)에 걸린 경우:"
                        echo "      systemctl --user reset-failed orca-serve.service 후 다시 시도하세요."
                    fi
                else
                    # common-setup.sh의 setup_rclone_sftp_mount와 동일한 절차: wsl.conf에
                    # systemd=true를 자동으로 추가하고, WSL 재시작이 필요하다는 걸 명확히 안내합니다.
                    echo "   ⚠️  WSL2에서 systemd가 활성화되어 있지 않습니다."
                    echo "      orca serve 자동 실행은 systemd user 서비스로 동작하므로 systemd가 필요합니다."
                    echo ""

                    _WSL_CONF="/etc/wsl.conf"
                    _NEEDS_SYSTEMD=true
                    if grep -q 'systemd\s*=\s*true' "$_WSL_CONF" 2>/dev/null; then
                        _NEEDS_SYSTEMD=false
                    fi

                    if [ "$_NEEDS_SYSTEMD" = true ]; then
                        echo "   ⏳ /etc/wsl.conf 에 systemd 활성화 설정을 추가합니다... (sudo 필요)"
                        if grep -q '\[boot\]' "$_WSL_CONF" 2>/dev/null; then
                            sudo sed -i '/^\[boot\]/a systemd=true' "$_WSL_CONF"
                        else
                            printf '\n[boot]\nsystemd=true\n' | sudo tee -a "$_WSL_CONF" > /dev/null
                        fi
                        echo "   ✅ /etc/wsl.conf 에 systemd=true 추가 완료!"
                    else
                        echo "   ℹ️  /etc/wsl.conf 에는 이미 systemd=true 가 설정되어 있습니다."
                        echo "      WSL 인스턴스가 아직 재시작되지 않아 systemd가 비활성 상태입니다."
                    fi

                    echo ""
                    echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "   🔄  WSL 인스턴스를 재시작해야 systemd가 활성화됩니다."
                    echo ""
                    echo "      PowerShell 에서 아래 명령어를 실행하세요:"
                    echo ""
                    echo "        wsl --shutdown"
                    echo ""
                    echo "      재시작 후 이 설치 스크립트를 다시 실행하면 orca-serve.service 자동 등록이"
                    echo "      이어서 완료됩니다(orca AppImage는 이미 설치돼 있어 다운로드는 다시 안 함)."
                    echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo ""
                    echo "   💬 지금 당장 쓰려면 수동으로도 실행 가능합니다: $ORCA_DIR/orca-serve-wrapper.sh &"
                fi
                echo ""
                echo "   💬 Windows Orca 앱과의 페어링 안내는 4.setup-orca.ps1 완료 화면에서 보여드립니다."
            else
                echo "   💬 일반 데스크톱 GUI 앱으로 바로 실행할 수 있습니다: $ORCA_APPIMAGE"
            fi

            # ── 실제로 쓰려면 필요한 다음 단계 안내 ──
            # Orca는 오케스트레이터일 뿐, claude/codex/gemini 등 실제 에이전트 CLI 바이너리는
            # 별도로 설치/로그인해야 함(Orca가 PATH에서 찾아 그대로 실행). codecompanion.lua에
            # 정리된 것과 동일한 CLI라서 이미 그쪽을 설정했다면 이 단계는 생략 가능.
            echo ""
            echo "   ---------------------------------------------------------------------"
            echo "   📋 실제로 사용하려면 (에이전트 CLI 설치 + 로그인, 1회만):"
            echo "   ---------------------------------------------------------------------"
            echo "   Orca는 오케스트레이터일 뿐이라, 아래 CLI들을 PATH에서 찾아 그대로 실행합니다."
            echo "   설치 + 로그인은 각 CLI 자체 방식으로 1회만 하면 됩니다:"
            echo ""
            echo "     • Claude Code : npm i -g @anthropic-ai/claude-code  →  claude  (최초 실행 시 로그인)"
            echo "     • Codex       : npm i -g @openai/codex             →  codex   (최초 실행 시 로그인)"
            echo "     • Gemini CLI  : npm i -g @google/gemini-cli        →  gemini  (최초 실행 시 로그인)"
            echo "     • OpenCode    : opencode.ai 설치 스크립트 →  opencode auth login"
            echo "     • Goose       : Block의 Goose CLI 설치    →  goose configure"
            echo ""
            echo "   ⚠️  ANTHROPIC_API_KEY 등을 .bashrc에 export해두신 게 있어도, orca serve가"
            echo "      systemd(또는 데스크톱 런처)로 뜬 경우엔 .bashrc를 거치지 않아 그 값을 못 봅니다"
            echo "      (WSL2 터미널에서 직접 치는 orca account add 같은 명령은 대화형 셸이라 문제없음)."
            echo "      orca serve 데몬에서도 보이게 하려면 아래처럼 등록해주세요(로그인마다 자동 반영):"
            echo "        mkdir -p ~/.config/environment.d"
            echo "        printf 'ANTHROPIC_API_KEY=%s\\n' \"\$ANTHROPIC_API_KEY\" >> ~/.config/environment.d/orca.conf"
            echo "      등록 후에는 'systemctl --user restart orca-serve.service'로 반영하거나 WSL2를"
            echo "      재시작하면 적용됩니다."
            echo ""
            echo "   Claude/Codex는 Orca 자체 계정 전환/사용량 추적 기능도 지원합니다(선택 사항):"
            echo "     orca account add --agent claude"
            echo "     orca account add --agent codex"
            echo "     orca account list"
            echo ""
            echo "   에이전트 CLI를 새로 설치했다면 스킬 인식을 갱신해주세요(위에서 자동 설치는 이미 됨):"
            echo "     orca skills install --all"
            echo ""
    echo "   설치 확인 후에는 Orca에서 바로 에이전트를 지정해 워크트리를 만들 수 있습니다:"
    echo "     orca worktree create --agent claude --prompt \"할 일\""
    echo "   ---------------------------------------------------------------------"
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
