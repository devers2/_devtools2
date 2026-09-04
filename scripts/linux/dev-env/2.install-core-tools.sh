#!/bin/bash

# =================================================================
# DevTools2 핵심 포터블 도구 설치 스크립트 (2.install-core-tools.sh)
# 대상: Java(8/17/21/25), Gradle, Python, Node.js, Neovim, Ghostty
# (선택적 에디터 VSCode, Zed, Orca는 5-1, 5-2, 5-3 스크립트로 분리됨)
# =================================================================

if [ -z "${DEVTOOLS2:-}" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")
fi

# 유효한 DEVTOOLS2 폴더가 아니면 표준 경로를 기본값으로 사용
if [ ! -f "$DEVTOOLS2/scripts/linux/dev-env/2.install-core-tools.sh" ]; then
    DEVTOOLS2="/var/opt/_devtools2"
fi

# 공통 모듈 로드 - GitHub raw URL에서 스트리밍 source (캐시 우회 헤더 포함)
_GH_RAW="https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env"
# shellcheck disable=SC1090
source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_common.sh") || { echo "[오류] _common.sh 로드 실패 - 네트워크 연결을 확인하세요." >&2; exit 1; }

# 공통 설치 유틸리티 로드
# shellcheck disable=SC1090
source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_install-utils.sh") || { print_error "_install-utils.sh 로드 실패 - 네트워크 연결을 확인하세요."; exit 1; }

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

# ARCH/IS_ARM64/IS_WSL2/show_spinner 는 _install-utils.sh / _common.sh 에서 로드됨

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

    download_with_progress "$DOWNLOAD_URL" "$FILE_NAME" "$TARGET_DIR"

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
echo "   ℹ️  Java, Gradle, Python, Neovim은 버전 고정 설치입니다."
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
    prompt_read _dup_choice "   선택 [1/${_C_DEFAULT}2${_C_RESET}/3]: "
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
    prompt_read _nv_sel "   선택 [1/${_C_DEFAULT}2${_C_RESET}]: "
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
export NPM_CONFIG_USERCONFIG="$DEVTOOLS2/.config/nodejs/.npmrc"
setup_npm_mirror

# ── 글로벌 npm 패키지 실시간 프로그래스 바 및 미러 서버 폴백 설치 헬퍼 ──────
install_npm_packages_with_progress() {
    local cmd="$1"             # "install" 또는 "update"
    local done_label="$2"
    local total_pkgs=243

    if [ -f "package-lock.json" ]; then
        local detected
        detected=$(node -e "
        try {
            const p = require('./package-lock.json');
            const count = Object.keys(p.packages || {}).filter(k => k.startsWith('node_modules/')).length;
            if (count > 0) console.log(count);
        } catch(e) {}
        " 2>/dev/null || true)
        [ -n "$detected" ] && total_pkgs="$detected"
    fi

    local mirror_reg="${NPM_MIRROR_REGISTRY:-https://registry.npmmirror.com/}"
    local official_reg="${NPM_OFFICIAL_REGISTRY:-https://registry.npmjs.org/}"
    local target_reg="$official_reg"
    local is_mirror=false

    if check_mirror_available "registry.npmmirror.com" 443; then
        target_reg="$mirror_reg"
        is_mirror=true
        print_info "한국/아시아 초고속 미러 서버(registry.npmmirror.com)를 우선 적용합니다."
    else
        print_info "미러 서버에 연결할 수 없어 공식 npmjs 레지스트리(registry.npmjs.org)를 사용합니다."
    fi

    _exec_npm_stream() {
        local reg="$1"
        local err_log="/tmp/_npm_install_err.log"
        rm -f "$err_log"

        local bar_len=25
        local count=0
        local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local spin_idx=0

        # npm 실행 및 timing 스트림을 파이프로 연결하여 실시간 게이지 렌더링
        npm "$cmd" --registry="$reg" --no-audit --no-fund --timing 2>&1 | tee "$err_log" | while IFS= read -r line; do
            if [[ "$line" =~ reifyNode:node_modules/([^[:space:]]+) ]]; then
                local pkg="${BASH_REMATCH[1]}"
                count=$((count + 1))
                local pct=$(( count * 100 / total_pkgs ))
                [ "$pct" -gt 100 ] && pct=100
                local filled=$(( bar_len * count / total_pkgs ))
                [ "$filled" -gt "$bar_len" ] && filled=$bar_len
                local empty=$(( bar_len - filled ))

                local bar=$(printf "%${filled}s" "" | tr ' ' '=')
                local spaces=$(printf "%${empty}s" "" | tr ' ' ' ')

                local pkg_disp="$pkg"
                if [ ${#pkg_disp} -gt 28 ]; then
                    pkg_disp="${pkg_disp:0:25}..."
                fi

                printf "\r   \033[36m[%s%s]\033[0m %3d%% (%d/%d) %-28s\033[K" "$bar" "$spaces" "$pct" "$count" "$total_pkgs" "$pkg_disp"
            elif [ "$count" -eq 0 ]; then
                local spin_char="${spinner[spin_idx]}"
                spin_idx=$(( (spin_idx + 1) % 10 ))
                printf "\r   \033[36m[%s]\033[0m 패키지 메타데이터 확인 및 다운로드 준비 중...\033[K" "$spin_char"
            fi
        done
        local _stream_ec=${PIPESTATUS[0]}
        printf "\r\033[K"
        return $_stream_ec
    }

    local success=false
    if _exec_npm_stream "$target_reg"; then
        success=true
    elif [ "$is_mirror" = true ]; then
        print_warn "미러 서버($target_reg) 설치 실패. 공식 레지스트리($official_reg)로 자동 폴백합니다..."
        restore_npm_mirror
        if _exec_npm_stream "$official_reg"; then
            success=true
            target_reg="$official_reg"
        fi
    fi

    if [ "$success" = true ]; then
        local cur_reg
        cur_reg=$(npm config get registry 2>/dev/null | sed 's#/$##')
        if [ "$cur_reg" != "${target_reg%/}" ]; then
            npm config set registry "$target_reg" 2>/dev/null || true
        fi
        print_done "$done_label (적용 저장소: $target_reg)"
    else
        print_error "글로벌 npm 패키지 설치 실패!"
        if [ -f "/tmp/_npm_install_err.log" ]; then
            echo "   [에러 상세 로그]"
            grep -E "npm ERR!" "/tmp/_npm_install_err.log" | head -n 10 | sed 's/^/   /'
        fi
        return 1
    fi
}

if [ -f "package.json" ]; then
    # ── package.json devDependencies 기준 설치 상태 상세 확인 ──────────────────
    # 단순 디렉터리 존재 여부가 아닌, 선언된 패키지 각각의 설치 여부를 확인합니다.
    # (설치 도중 강제 종료된 경우 일부만 설치된 상태를 정확히 감지하기 위함)
    _npm_total=0
    _npm_installed=0
    _npm_missing=""

    _pkg_list=$(node -e "
const p = require('./package.json');
const deps = {...(p.dependencies||{}), ...(p.devDependencies||{})};
Object.keys(deps).forEach(k => console.log(k));
" 2>/dev/null)

    if [ -n "$_pkg_list" ]; then
        while IFS= read -r _pkg; do
            [ -z "$_pkg" ] && continue
            _npm_total=$((_npm_total + 1))
            # Linux는 lib/node_modules, Windows(WSL 경유 설치)는 node_modules 에 위치
            if [ -d "lib/node_modules/$_pkg" ] || [ -d "node_modules/$_pkg" ]; then
                _npm_installed=$((_npm_installed + 1))
            else
                _npm_missing="${_npm_missing:+${_npm_missing}, }${_pkg}"
            fi
        done <<< "$_pkg_list"
    fi

    _npm_action=""
    echo ""

    if [ "$_npm_total" -gt 0 ] && [ "$_npm_installed" -eq "$_npm_total" ]; then
        # ── 전체 설치됨 ────────────────────────────────────────────────────────
        print_question "📦 글로벌 npm 패키지 (${_npm_installed}/${_npm_total}개) 모두 설치되어 있습니다. 처리 방식을 선택하세요:"
        echo ""
        print_option "1" "기존 패키지 유지 (건너뛰기)" "[기본값]"
        print_option "2" "package-lock.json 기준 다시 설치 (버전 고정 재설치)"
        print_option "3" "최신 버전으로 업데이트 (package-lock.json 갱신)"
        echo ""
        prompt_read _npm_choice "   선택 [${_C_DEFAULT}1${_C_RESET}/2/3]: "
        echo ""
        case "${_npm_choice:-1}" in
            2) _npm_action="install" ; print_info "package-lock.json 기준 재설치 선택됨" ;;
            3) _npm_action="update"  ; print_info "최신 버전으로 업데이트 선택됨" ;;
            *) _npm_action="skip"    ; print_info "기존 글로벌 npm 패키지를 유지합니다 (건너뜀)." ;;
        esac

    elif [ "$_npm_total" -gt 0 ] && [ "$_npm_installed" -gt 0 ]; then
        # ── 일부만 설치됨 (설치 중단 등) ─────────────────────────────────────
        print_warn "📦 글로벌 npm 패키지 일부 미설치: ${_npm_installed}/${_npm_total}개 설치됨"
        echo "   미설치 패키지: ${_npm_missing}"
        echo ""
        print_option "1" "package-lock.json 기준 재설치 (버전 고정 설치)" "[기본값]"
        print_option "2" "최신 버전으로 설치 (package-lock.json 갱신)"
        echo ""
        prompt_read _npm_choice "   선택 [${_C_DEFAULT}1${_C_RESET}/2]: "
        echo ""
        case "${_npm_choice:-1}" in
            2) _npm_action="update"  ; print_info "최신 버전으로 설치 선택됨" ;;
            *) _npm_action="install" ; print_info "package-lock.json 기준 재설치 선택됨" ;;
        esac

    else
        # ── 미설치 ────────────────────────────────────────────────────────────
        print_question "📦 글로벌 npm 패키지 설치 방식을 선택하세요:"
        echo ""
        print_option "1" "package-lock.json 기준 설치 (버전 고정 설치)" "[기본값]"
        print_option "2" "최신 버전으로 설치 (package-lock.json 갱신)"
        echo ""
        prompt_read _npm_choice "   선택 [${_C_DEFAULT}1${_C_RESET}/2]: "
        echo ""
        case "${_npm_choice:-1}" in
            2) _npm_action="update"  ; print_info "최신 버전으로 설치 선택됨" ;;
            *) _npm_action="install" ; print_info "package-lock.json 기준 설치 선택됨" ;;
        esac
    fi

    if [ "$_npm_action" = "install" ] || [ "$_npm_action" = "update" ]; then
        _npm_cmd="install"
        _npm_done_label="글로벌 npm 패키지 설치 완료!"
        if [ "$_npm_action" = "update" ]; then
            _npm_cmd="update"
            _npm_done_label="글로벌 npm 패키지 최신 업데이트 완료!"
        fi

        install_npm_packages_with_progress "$_npm_cmd" "$_npm_done_label"
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
# PATH 연동을 위한 bin 디렉터리 심볼릭 링크 연결
if [ -d "lib/node_modules/.bin" ]; then
    ln -sfn lib/node_modules/.bin bin
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
    if prompt_confirm "   ⚠️  neovim 디렉토리가 이미 존재합니다. 삭제하고 새로 설치하시겠습니까?" "N"; then
        echo "   🗑️  기존 디렉토리 삭제 중..."
        rm -rf "$DEVTOOLS2/modules/neovim/nvim"
        echo "   📦 Neovim stable 다운로드 및 압축 해제..."
        install_tool \
            'https://github.com/neovim/neovim/releases/download/stable/nvim-linux-{ARCH}.tar.gz' \
            'x86_64' \
            'arm64' \
            'nvim'
    else
        echo "   ⏭️ [건너뜀] neovim 디렉토리가 이미 존재합니다."
    fi
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
# 6. Ghostty 포터블 설치: https://ghostty.org/
echo "💚 6. Ghostty 포터블 설치 단계"
echo ""

if [ "$IS_WSL2" = true ]; then
    echo "   ⚠️  [WSL2 환경 감지] Ghostty는 WSL2에서 지원되지 않으므로 설치를 건너뜁니다."
    echo "   💬 Windows 네이티브 환경에서 Ghostty를 설치해주세요: https://ghostty.org/"
else
    echo "💚 6. Ghostty 포터블 설치 중..."
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
        prompt_read _gv_sel "   선택 (1-2, 기본값: 2): "
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

    # 네이티브 리눅스: Ghostty PATH 동적 등록
    if [ -d "$DEVTOOLS2/modules/ghostty" ]; then
        ensure_path_in_bashrc "$DEVTOOLS2/modules/ghostty"
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
