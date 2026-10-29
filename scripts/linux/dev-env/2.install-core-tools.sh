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

# 공통 모듈 로드 (로컬 우선 탐색 후 원격 스트리밍)
DT2_REF="${DT2_REF:-main}"
_GH_RAW="https://raw.githubusercontent.com/devers2/_devtools2/${DT2_REF}/scripts/linux/dev-env"
_SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
if [ -f "$_SCRIPT_DIR/_common.sh" ]; then
    # shellcheck disable=SC1091
    source "$_SCRIPT_DIR/_common.sh"
elif [ -f "${DEVTOOLS2:-}/scripts/linux/dev-env/_common.sh" ]; then
    # shellcheck disable=SC1091
    source "$DEVTOOLS2/scripts/linux/dev-env/_common.sh"
else
    # shellcheck disable=SC1090
    source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_common.sh") || { echo "[오류] _common.sh 로드 실패 - 네트워크 연결을 확인하세요." >&2; exit 1; }
fi

# 공통 설치 유틸리티 로드
if [ -f "$_SCRIPT_DIR/_install-utils.sh" ]; then
    # shellcheck disable=SC1091
    source "$_SCRIPT_DIR/_install-utils.sh"
elif [ -f "${DEVTOOLS2:-}/scripts/linux/dev-env/_install-utils.sh" ]; then
    # shellcheck disable=SC1091
    source "$DEVTOOLS2/scripts/linux/dev-env/_install-utils.sh"
else
    # shellcheck disable=SC1090
    source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_install-utils.sh") || { print_error "_install-utils.sh 로드 실패 - 네트워크 연결을 확인하세요."; exit 1; }
fi

# DEVTOOLS2 기본 폴더 및 필수 서브 디렉토리 존재/권한 확보
if [ ! -d "$DEVTOOLS2" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        mkdir -p "$DEVTOOLS2"
    else
        sudo mkdir -p "$DEVTOOLS2" 2>/dev/null || mkdir -p "$DEVTOOLS2" 2>/dev/null || true
        sudo chown -R "$USER" "$DEVTOOLS2" 2>/dev/null || true
    fi
fi
# ⚠️ 쓰기 권한이 없다고 "sudo chown -R $USER" 로 저장소 전체 소유자를 바꾸지 않습니다.
#    여러 사용자가 그룹(devers)으로 공유하는 서버에서 두 번째 사용자가 설치를 실행하면
#    공유 저장소를 통째로 가져가 다른 사용자의 접근을 깨뜨리기 때문입니다.
#    (공유 런타임 폴더 data/modules 는 0.init-devtools2.sh 가 그룹 쓰기(2770)로 설정합니다.)
if [ ! -w "$DEVTOOLS2/modules" ] && [ -d "$DEVTOOLS2/modules" ] && [ "$(id -u)" -ne 0 ]; then
    print_error "$DEVTOOLS2/modules 에 쓰기 권한이 없습니다 (소유자: $(stat -c '%U:%G' "$DEVTOOLS2/modules" 2>/dev/null))."
    print_info "  그룹(devers)에 추가된 직후라면 다시 로그인하거나 'newgrp devers' 후 다시 실행하세요."
    print_info "  그룹에 없다면 관리자가 실행: sudo $DEVTOOLS2/scripts/linux/dev-env/add-devtools2-user.sh $USER"
    exit 1
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
# (Node.js 최신 버전 조회는 공용 list_nodejs_lts_versions + [track] nodejs 로 대체)

# 로그 설정: data/logs 폴더에 실행 시점별로 기록
LOG_DIR="$DEVTOOLS2/data/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy_$(date +%Y%m%d_%H%M%S).log"
# 설치 로그는 최근 20개만 남기고 정리합니다 (실행할 때마다 무한히 쌓이지 않도록)
ls -1t "$LOG_DIR"/deploy_*.log 2>/dev/null | tail -n +20 | xargs -r rm -f -- 2>/dev/null || true

# ARCH/IS_ARM64/IS_WSL2/show_spinner/install_tool 은 _install-utils.sh / _common.sh 에서 로드됨

# 모든 표준 출력(stdout)과 표준 에러(stderr)를 터미널과 로그 파일에 동시에 기록
exec > >(tee -i "$LOG_FILE") 2>&1

# ─────────────────────────────────────────────────────────────────
# ⚙️  PRE-FLIGHT: 버전 정책 확인 (tool-versions.toml [track])
# ─────────────────────────────────────────────────────────────────
# 버전 정책은 tool-versions.toml 의 [track] 한 곳에서 관리합니다 (_install-utils.sh 의 resolve_track_version).
# 예전처럼 설치 때마다 "최신/지정/개별" 버전 선택 방식을 묻지 않고, 각 도구의 track 범위 안 최신 버전을 설치합니다.

# [폴더 이름에서 메이저 버전 제거] node-v24 → nodejs/current, gradle-9 → gradle/current
# 메이저가 폴더 이름에 박혀 있으면 [track] 으로 메이저를 올릴 때(예: nodejs = "26") 경로까지 바꿔야 했습니다.
# 기존 설치는 다시 받지 않고 이름만 옮기며, 예전 이름은 새 폴더를 가리키는 링크로 남겨
# env.sh(1.setup-env.sh) 를 다시 만들기 전의 셸·scripts/java/jdtls 등이 깨지지 않게 합니다.
_dt2_migrate_dir() {  # <예전 폴더> <새 폴더>
    local old="$1" new="$2"
    if [ -d "$old" ] && [ ! -L "$old" ] && [ ! -e "$new" ]; then
        mv "$old" "$new"
        echo "   📁 설치 폴더 이름 변경: $(basename "$old") → $(basename "$new")"
    fi
    if [ -e "$new" ] && [ ! -e "$old" ] && [ ! -L "$old" ]; then
        ln -s "$(basename "$new")" "$old"
    fi
}
_dt2_migrate_dir "$DEVTOOLS2/modules/nodejs/node-v24" "$DEVTOOLS2/modules/nodejs/current"
_dt2_migrate_dir "$DEVTOOLS2/modules/gradle/gradle-9" "$DEVTOOLS2/modules/gradle/current"

# 마지막 설치 버전 읽기 (data/state 기록, 없으면 TOML 버전 배열 첫 항목 — 목록 조회 실패 시 폴백)
NODEJS_PINNED=$(get_pinned_version "nodejs")
GHOSTTY_PINNED=$(get_pinned_version "ghostty")

# 설치 상태 확인
NODEJS_INSTALLED=false
[ -d "$DEVTOOLS2/modules/nodejs/current" ] && NODEJS_INSTALLED=true

GHOSTTY_INSTALLED=false
if [ "$IS_WSL2" = false ] && [ -f "$DEVTOOLS2/modules/ghostty/ghostty" ]; then
    GHOSTTY_INSTALLED=true
fi

# 상태 포매팅 헬퍼(_fmts)는 _install-utils.sh 에서 로드됨

echo ""
echo "==========================================================================="
echo "📋 버전 관리 대상 도구 현황 (버전 정책: tool-versions.toml [track])"
echo ""
printf "   %-14s  track: %-10s  %s\n" "Node.js" "$(get_track nodejs 24)" "$(_fmts "$NODEJS_INSTALLED")"
for _jv in $(get_supported_jdk_versions); do
    printf "   %-14s  track: %-10s\n" "JDK $_jv" "$(get_track "jdk${_jv}" "$_jv")"
done
printf "   %-14s  track: %-10s\n" "Gradle" "$(get_track gradle latest)"
printf "   %-14s  track: %-10s\n" "Neovim" "$(get_track neovim 0.12)"
if [ "$IS_WSL2" = false ]; then
    printf "   %-14s  track: %-10s  %s\n" \
        "Ghostty" "$(get_track ghostty latest)" "$(_fmts "$GHOSTTY_INSTALLED")"
else
    printf "   %-14s  %-28s  %s\n" \
        "Ghostty" "(WSL2 - 설치 건너뜀)" "⏭️  해당 없음"
fi
echo ""
for _pm in $(get_supported_python_minors); do
    _pd="$DEVTOOLS2/modules/python/python-${_pm//./}"
    printf "   %-14s  track: %-10s  %s\n" "Python $_pm" "$(get_track "python${_pm//./}" "$_pm")" "$(_fmts "$([ -x "$_pd/bin/python3" ] && echo true || echo false)")"
done
echo ""

# ── 중복 처리 방식 선택 ──────────────────────────────────────────
# 환경변수 DT2_DUPLICATE_MODE(remove|reinstall|keep|skip|individual)가 있으면 질문 없이 그 값을 씁니다.
DUPLICATE_MODE="${DT2_DUPLICATE_MODE:-keep}"
_HAS_INSTALLED=false
[ "$NODEJS_INSTALLED" = true ] && _HAS_INSTALLED=true
[ "$IS_WSL2" = false ] && [ "$GHOSTTY_INSTALLED" = true ] && _HAS_INSTALLED=true
[ -d "$DEVTOOLS2/modules/java" ] && [ -n "$(ls -A "$DEVTOOLS2/modules/java" 2>/dev/null)" ] && _HAS_INSTALLED=true
[ -d "$DEVTOOLS2/modules/gradle/current" ] && _HAS_INSTALLED=true
[ -d "$DEVTOOLS2/modules/neovim/nvim" ] && _HAS_INSTALLED=true

if [ -n "${DT2_DUPLICATE_MODE:-}" ]; then
    print_info "환경변수(DT2_DUPLICATE_MODE) 설정 적용됨: $DUPLICATE_MODE"
elif [ "$_HAS_INSTALLED" = true ]; then
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

# (예전 "버전 설치 방식 선택(최신/지정/개별)" 질문과 최신 일괄 조회는 [track] 정책으로 대체되어 제거했습니다)

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
# ── Adoptium Temurin JDK 설치 공용 헬퍼 함수 ───────────────────────
install_adoptium_jdk() {
    local major="$1"
    local dest_dir="$2"
    local target_path="$DEVTOOLS2/modules/java/$dest_dir"

    # 이미 설치되어 있으면 설치 버전과 대상 버전을 비교합니다. 같으면 건너뛰고, 다르면
    # (track 범위 안에 보안 패치 버전이 새로 나온 경우 등) 업데이트 여부를 묻습니다(decide_app_action).
    local jdk_arch="$([ "$IS_ARM64" = true ] && echo 'aarch64' || echo 'x64')"
    local pinned_ver track
    pinned_ver=$(get_pinned_version "jdk${major}")
    track=$(get_track "jdk${major}" "$major")
    local dl_url=""
    local checksum=""
    local actual_ver=""

    # 1. 버전 결정: [track] jdk<메이저>
    #    - 전체 버전 고정(예: "17.0.18+8", "8u482-b08") → 그 버전을 공식 릴리스 URL 로 설치
    #    - 메이저(예: "17") → Adoptium API 로 같은 메이저의 최신 패치 및 체크섬 동적 조회
    #    (JDK 는 여러 메이저를 나란히 설치하므로 메이저를 올리는 대신 새 jdk<메이저> 항목을 추가합니다)
    if _track_is_exact "$track"; then
        actual_ver="$track"
    else
        echo -n "   🔍 Adoptium API 에서 JDK $major 최신 패치 조회 중... "
        local meta
        meta=$(fetch_adoptium_release "$major" "$jdk_arch")
        if [ -n "$meta" ]; then
            actual_ver=$(echo "$meta" | cut -d'|' -f1)
            dl_url=$(echo "$meta" | cut -d'|' -f2)
            checksum=$(echo "$meta" | cut -d'|' -f3)
            echo "완료 ($actual_ver)"
        else
            echo "실패 → 마지막 설치 버전으로 폴백"
        fi
    fi

    # 2순위: API 미사용 또는 조회 실패 시 tool-versions.toml 고정 버전 및 공식 릴리스 URL로 폴백
    if [ -z "$dl_url" ]; then
        actual_ver="${actual_ver:-${pinned_ver:-default}}"
        if [ "$major" = "8" ]; then
            local ver_nodash="${actual_ver//-/}"
            dl_url="https://github.com/adoptium/temurin8-binaries/releases/download/jdk${actual_ver}/OpenJDK8U-jdk_${jdk_arch}_linux_hotspot_${ver_nodash}.tar.gz"
        else
            local ver_enc="${actual_ver//+/%2B}"
            local ver_us="${actual_ver//[+-]/_}"
            dl_url="https://github.com/adoptium/temurin${major}-binaries/releases/download/jdk-${ver_enc}/OpenJDK${major}U-jdk_${jdk_arch}_linux_hotspot_${ver_us}.tar.gz"
        fi
        checksum="${dl_url}.sha256.txt"
    fi

    # 2. 설치/업데이트/건너뛰기 결정 (필수 도구라 미설치면 묻지 않고 설치)
    local _reinstall=false
    if [ -d "$target_path" ]; then
        local _cur_ver
        _cur_ver=$(_installed_jdk_version "$target_path")
        if [ -n "$_cur_ver" ] && _jdk_version_matches "$_cur_ver" "$actual_ver" "$major"; then
            if [ "$(_resolve_action true "JDK $major")" = "reinstall" ]; then
                _reinstall=true
            else
                echo "   ⏭️ [건너뜀] JDK $major ($dest_dir, $_cur_ver)이 이미 최신 버전입니다."
                return 0
            fi
        else
            decide_app_action "JDK $major" true "$_cur_ver" "$actual_ver" "A" "DT2_JDK${major}"
            if [ "$DT2_APP_ACTION" = "update" ] || [ "$(_resolve_action true "JDK $major")" = "reinstall" ]; then
                _reinstall=true
            else
                return 0
            fi
        fi
    fi

    echo "   📦 JDK $major $actual_ver 다운로드 및 설치..."
    # 재설치는 기존 JDK 를 옆으로 옮겨 두었다가, 새 설치가 실패하면 되돌립니다.
    local _backup=""
    if [ "$_reinstall" = true ]; then
        # 백업 이름은 "jdk-*" 패턴(Gradle 툴체인 목록, 설치 검증)에 걸리지 않도록 점으로 시작합니다.
        _backup="$(dirname "$target_path")/.dt2-old-${dest_dir}"
        rm -rf "$_backup"
        mv "$target_path" "$_backup"
    fi
    if safe_download_and_extract "$dl_url" "$target_path" 1 "$checksum" "JDK $major"; then
        [ -n "$_backup" ] && rm -rf "$_backup"
        echo "   ✅ JDK $major ($dest_dir) 설치 완료"
        if [ -n "$actual_ver" ] && [ "$actual_ver" != "$pinned_ver" ]; then
            update_pinned_version "jdk${major}" "$actual_ver"
        fi
    else
        if [ -n "$_backup" ]; then
            rm -rf "$target_path"
            mv "$_backup" "$target_path"
            echo "   ↩️  기존 JDK $major 를 복원했습니다." >&2
        fi
        echo "   ❌ JDK $major 설치 실패" >&2
        return 1
    fi
}

# 설치된 JDK 의 버전 문자열을 release 파일에서 읽습니다. (예: "21.0.12.1+1", JDK 8 은 "1.8.0_504")
_installed_jdk_version() {
    local rel="$1/release" v=""
    [ -f "$rel" ] || return 0
    v=$(grep -E '^JAVA_RUNTIME_VERSION=' "$rel" | head -1 | cut -d'"' -f2)
    [ -z "$v" ] && v=$(grep -E '^JAVA_VERSION=' "$rel" | head -1 | cut -d'"' -f2)
    echo "${v%-LTS}"
}

# 설치 버전과 지정 버전(tool-versions.toml 형식)이 같은지 비교합니다.
# - JDK 8: 설치 "1.8.0_504" ↔ 지정 "8u504-b01" → 업데이트 번호(504)만 비교
# - 그 외: 설치 "21.0.12.1+1" ↔ 지정 "21.0.12.1+1"
_jdk_version_matches() {
    local cur="$1" want="$2" major="$3"
    if [ "$major" = "8" ]; then
        local cur_u="${cur##*_}" want_u="${want#8u}"
        want_u="${want_u%%-*}"
        [ "$cur_u" = "$want_u" ]
    else
        [ "$cur" = "$want" ]
    fi
}

# 1. JAVA 포터블 설치 (Adoptium Eclipse Temurin JDK — tool-versions.toml 연동)
echo "☕ 1. JAVA 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/java"
cd "$DEVTOOLS2/modules/java"

for _jdk_v in $(get_supported_jdk_versions); do
    _dest_name="jdk-${_jdk_v}"
    [ "$_jdk_v" = "8" ] && _dest_name="jdk-1.8"
    install_adoptium_jdk "$_jdk_v" "$_dest_name"
done

echo "✅ JAVA 설치 완료 ($ARCH)"
echo ""

echo "---------------------------------------------------------------------------"
# 2. Gradle 포터블 설치
echo "🐘 2. Gradle 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/gradle"
cd "$DEVTOOLS2/modules/gradle"

GRADLE_PINNED=$(get_pinned_version "gradle")
# [track] gradle (기본 "latest"): 프로젝트는 각자 Gradle wrapper(gradlew)로 자기 버전을 쓰므로 전역 Gradle 은
# 새 프로젝트·wrapper 생성용으로 최신을 따릅니다. 목록 조회 실패 시 마지막 설치 버전(TOML/data/state)으로 폴백.
GRADLE_VERSION=$(resolve_track_version gradle latest list_gradle_versions)
GRADLE_VERSION="${GRADLE_VERSION:-${GRADLE_PINNED:-9.7.1}}"
_GRADLE_DIR="$DEVTOOLS2/modules/gradle/current"

# 설치된 Gradle 버전(lib/gradle-core-api-<버전>.jar)과 대상 버전을 비교합니다.
_GRADLE_CUR=""
_GRADLE_INSTALLED=false
if [ -d "$_GRADLE_DIR" ]; then
    _GRADLE_INSTALLED=true
    _GRADLE_CUR=$(find "$_GRADLE_DIR/lib" -maxdepth 1 -name 'gradle-core-api-*.jar' 2>/dev/null \
        | head -1 | sed -E 's|.*/gradle-core-api-(.+)\.jar$|\1|')
fi
decide_app_action "Gradle" "$_GRADLE_INSTALLED" "$_GRADLE_CUR" "$GRADLE_VERSION" "A" "DT2_GRADLE"
_GRADLE_ACTION="$DT2_APP_ACTION"
if [ "$_GRADLE_ACTION" = "skip" ] && [ "$_GRADLE_INSTALLED" = true ] && [ "$(_resolve_action true "Gradle")" = "reinstall" ]; then
    _GRADLE_ACTION="update"
fi

if [ "$_GRADLE_ACTION" != "skip" ]; then
    _gradle_url="https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"
    _gradle_sha="${_gradle_url}.sha256"
    if safe_download_and_extract "$_gradle_url" "$DEVTOOLS2/modules/gradle" 0 "$_gradle_sha" "Gradle $GRADLE_VERSION" \
        && [ -d "$DEVTOOLS2/modules/gradle/gradle-${GRADLE_VERSION}" ]; then
        # 재설치: 새 버전 압축 해제에 성공한 뒤에만 기존 current 를 교체합니다.
        # (기존 폴더가 남아 있는 채로 mv 하면 새 폴더가 그 "안으로" 들어갑니다)
        rm -rf "$_GRADLE_DIR"
        mv -f "$DEVTOOLS2/modules/gradle/gradle-${GRADLE_VERSION}" "$_GRADLE_DIR"
        echo "   ✅ Gradle $GRADLE_VERSION 설치 완료"
        if [ "$GRADLE_VERSION" != "$GRADLE_PINNED" ]; then
            update_pinned_version "gradle" "$GRADLE_VERSION"
        fi
    else
        echo "   ❌ Gradle 설치 실패 (기존 설치가 있으면 그대로 유지됩니다)" >&2
    fi
fi
# 예전 이름(gradle-9)으로 참조하던 곳을 위한 호환 링크
_dt2_migrate_dir "$DEVTOOLS2/modules/gradle/gradle-9" "$_GRADLE_DIR"

echo "✅ Gradle 설치 완료"
echo ""

echo "---------------------------------------------------------------------------"
# 3. Python 포터블 설치
echo "🐍 3. Python 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/python"
cd "$DEVTOOLS2/modules/python"

# ── 버전 결정: [track] python314 / python312 (기본 "3.14" / "3.12" = 그 마이너 안의 최신 패치) ──────
# Python 의 3.14 → 3.15 는 매년 나오는 기능 릴리스로 사실상 메이저 업그레이드라, JDK(jdk-21·jdk-25)처럼
# 마이너마다 폴더(python-314·python-312)를 따로 두고 track 은 패치(3.14.x)만 따라갑니다.
#   ● 폴더 경로가 그대로라 패치 업데이트 뒤에도 PYTHON_HOME·VS Code 설정·가상환경(venv)이 그대로 동작합니다.
#   ● 새 마이너(예: 3.16)를 추가하려면 tool-versions.toml 에 [track] python316 = "3.16" 과
#     [core_tools] python316 = [...] 를 추가합니다(설치 대상 목록은 get_supported_python_minors 가 TOML 에서 읽음).
#   ● 예전에는 다운로드 주소(빌드 20260414)가 고정이고 폴더가 있으면 건너뛰어 보안 패치를 받지 못했습니다.
#   ● 다운로드 주소는 프로젝트의 현재 위치(astral-sh)를 씁니다(예전 indygreg 주소는 GitHub 리디렉트에 의존).
_pbs_triple="x86_64-unknown-linux-gnu"
[ "$IS_ARM64" = true ] && _pbs_triple="aarch64-unknown-linux-gnu"
set +e; _PBS_INDEX=$(fetch_python_build_index "$_pbs_triple"); set -e
# 인수로 마이너를 주면 그 마이너의 버전만 출력합니다(가장 높은 마이너가 아니면 "범위 밖 새 버전" 안내를 내지 않기 위함)
_pbs_list_versions() { printf '%s\n' "$_PBS_INDEX" | awk -v m="${1:-}" 'NF && (m == "" || index($1, m ".") == 1) { print $1 }'; }

# 사용법: _install_python_minor <마이너, 예: 3.14> [notice]
#   notice: 범위 밖 새 마이너(예: 3.15) 안내를 표시 — 가장 높은 마이너에만 줍니다
#           (3.12 에도 주면 "python312 값을 3.15 로 바꾸라"는 엉뚱한 안내가 됨)
_install_python_minor() {
    local minor="$1" notice="${2:-}"
    local key="python${minor//./}" dir="python-${minor//./}"
    local pdir="$DEVTOOLS2/modules/python/$dir"
    local pinned ver tag sha="" line track cur="" installed=false
    pinned=$(get_pinned_version "$key")             # 마지막 설치 기록 "3.14.4+20260414"
    track=$(get_track "$key" "$minor")
    if [ "$notice" = "notice" ]; then
        ver=$(resolve_track_version "$key" "$minor" _pbs_list_versions)
    else
        ver=$(resolve_track_version "$key" "$minor" _pbs_list_versions "$minor")
    fi
    # 폴더(python-314)가 마이너에 묶여 있으므로 다른 마이너를 가리키는 track(예: python314 = "3.15")은 받지 않습니다
    # (위 "범위 밖 새 버전" 안내를 보고 값만 바꾸면 3.15 가 python-314 폴더에 설치되는 것을 막기 위함)
    if [ -n "$ver" ] && [[ "$ver" != "${minor}."* ]]; then
        print_warn "  ${key}: track \"${track}\" 은 ${minor}.x 범위가 아니라 무시합니다. 새 마이너는 tool-versions.toml 에 새 키(예: python316 = \"3.16\")로 추가하세요."
        ver=""
    fi
    if [[ "$ver" == *+* ]]; then
        # 정확한 고정("3.14.4+20260414"): 버전과 빌드 날짜를 그대로 사용
        tag="${ver#*+}"; ver="${ver%%+*}"
    elif [ -n "$ver" ]; then
        line=$(printf '%s\n' "$_PBS_INDEX" | awk -v v="$ver" '$1 == v { print; exit }')
        tag=$(awk '{ print $2 }' <<<"$line"); sha=$(awk '{ print $3 }' <<<"$line")
        if [ -z "$tag" ]; then
            # 버전만 고정(빌드 날짜 없음)했는데 최신 릴리스에 그 버전이 없으면 주소를 만들 수 없음
            print_warn "  ${key}: track \"${track}\" 의 빌드를 찾지 못했습니다. 정확히 고정하려면 \"버전+빌드날짜\"(예: ${pinned}) 형식으로 쓰세요."
            ver=""
        fi
    fi
    if [ -z "$ver" ] || [ -z "$tag" ]; then
        # 목록 조회 실패 시 마지막 설치 버전으로 폴백
        ver="${pinned%%+*}"; tag="${pinned#*+}"
    fi
    # 폴백 값도 없거나 "버전+빌드날짜" 형식이 아니면 다운로드 주소를 만들 수 없으므로 이 마이너는 건너뜁니다
    if [ -z "$ver" ] || [ -z "$tag" ] || [ "$ver" = "$tag" ]; then
        print_warn "  ${key}: 설치할 버전을 정하지 못했습니다(목록 조회 실패, TOML 폴백 값 없음 또는 형식 오류). Python ${minor} 설치를 건너뜁니다."
        return 0
    fi
    [ "$sha" = "-" ] && sha=""

    if [ -x "$pdir/bin/python3" ]; then
        installed=true
        cur=$("$pdir/bin/python3" --version 2>/dev/null | awk '{ print $2 }' || true)
    fi

    # ── 설치/업데이트/건너뛰기 결정 (필수 도구라 미설치면 묻지 않고 설치) ──
    decide_app_action "Python ${minor}" "$installed" "$cur" "$ver" "A" "DT2_PYTHON${minor//./}"
    local action="$DT2_APP_ACTION"
    # ── 중복 처리: 업데이트하지 않은 경우 사용자가 고른 중복 처리 방식(재설치 등) 적용 ──
    if [ "$action" = "skip" ] && [ "$installed" = true ] && [ "$(_resolve_action true "Python ${minor}")" = "reinstall" ]; then
        action="update"
    fi
    [ "$action" = "skip" ] && return 0

    local file="cpython-${ver}+${tag}-${_pbs_triple}-install_only.tar.gz"
    local url="https://github.com/astral-sh/python-build-standalone/releases/download/${tag}/${file}"
    [ -n "$sha" ] || sha=$(github_asset_sha256 "astral-sh/python-build-standalone" "$tag" "$file")
    local stage="$DEVTOOLS2/modules/python/.dt2-new-${dir}" old="$DEVTOOLS2/modules/python/.dt2-old-${dir}"
    rm -rf "$stage" "$old"; mkdir -p "$stage"

    echo "   📦 Python ${ver} (빌드 ${tag}) 설치..."
    if ! download_with_progress "$url" "$stage/$file" "Python ${ver}"; then
        print_warn "Python ${ver} 다운로드 실패 ($url) — 기존 설치를 유지합니다."
        rm -rf "$stage"; return 0
    fi
    if [ -n "$sha" ]; then
        if ! verify_sha256 "$stage/$file" "$sha"; then
            print_warn "Python ${ver} SHA256 불일치 — 기존 설치를 유지합니다."
            rm -rf "$stage"; return 0
        fi
    else
        print_warn "Python ${ver} 체크섬을 조회하지 못해 검증 없이 설치합니다."
    fi
    if ! tar -xzf "$stage/$file" -C "$stage" || [ ! -x "$stage/python/bin/python3" ]; then
        print_warn "Python ${ver} 압축 해제 실패 — 기존 설치를 유지합니다."
        rm -rf "$stage"; return 0
    fi

    # 새 버전 준비가 끝난 뒤에만 기존 설치를 교체합니다(실패 시 기존 Python 유지).
    if [ -d "$pdir" ]; then
        mv "$pdir" "$old"
        # 사용자가 이 Python 에 직접 pip 로 설치한 패키지·명령은 새 설치로 옮깁니다.
        # (같은 마이너의 패치 업데이트는 ABI 가 같아 그대로 동작하고, 명령의 #! 경로도 폴더가 같아 유효)
        local sp_old="$old/lib/python${minor}/site-packages" sp_new="$stage/python/lib/python${minor}/site-packages" it
        if [ -d "$sp_old" ] && [ -d "$sp_new" ]; then
            for it in "$sp_old"/* "$sp_old"/.[!.]*; do
                [ -e "$it" ] || continue
                [ -e "$sp_new/$(basename "$it")" ] || mv "$it" "$sp_new/"
            done
        fi
        for it in "$old/bin"/*; do
            [ -e "$it" ] || [ -L "$it" ] || continue
            [ -e "$stage/python/bin/$(basename "$it")" ] || [ -L "$stage/python/bin/$(basename "$it")" ] || mv "$it" "$stage/python/bin/"
        done
    fi
    mv "$stage/python" "$pdir"
    rm -rf "$stage" "$old"
    echo "   ✅ Python ${ver} 설치 완료 ($dir)"
    # 마지막 설치 버전과 다르면 이 PC 의 설치 이력(data/state) 업데이트
    if [ "${ver}+${tag}" != "$pinned" ]; then
        update_pinned_version "$key" "${ver}+${tag}"
    fi
}

# 가장 높은 마이너에만 범위 밖 새 마이너 안내(notice)를 줍니다
_py_first=true
for _pm in $(get_supported_python_minors); do
    if [ "$_py_first" = true ]; then
        _install_python_minor "$_pm" notice
        _py_first=false
    else
        _install_python_minor "$_pm"
    fi
done

echo "✅ Python 설치 완료 ($ARCH)"
echo ""

echo "---------------------------------------------------------------------------"
# 4. Node.js 포터블 설치
echo "🟢 4. Node.js 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/nodejs"
cd "$DEVTOOLS2/modules/nodejs"

# ── 버전 결정: [track] nodejs (기본 "24" = 메이저 24 의 최신 LTS 패치) ─────────
# 메이저를 올리려면 [track] nodejs 값만 바꿉니다(예: "26"). 설치 폴더는 메이저와 무관한 nodejs/current 입니다.
# (메이저를 바꾸면 npm 전역 패키지 중 네이티브 모듈은 다시 설치해야 할 수 있습니다)
NODEJS_VERSION=$(resolve_track_version nodejs 24 list_nodejs_lts_versions)
if [ -n "$NODEJS_VERSION" ]; then
    NODEJS_VERSION="v${NODEJS_VERSION#v}"
else
    NODEJS_VERSION="$NODEJS_PINNED"   # 목록 조회 실패 시 마지막 설치 버전으로 폴백
fi
_nodejs_cur=""
[ -x "$DEVTOOLS2/modules/nodejs/current/bin/node" ] && _nodejs_cur=$("$DEVTOOLS2/modules/nodejs/current/bin/node" --version 2>/dev/null || true)

# ── 설치/업데이트/건너뛰기 결정 (필수 도구라 미설치면 묻지 않고 설치) ──
decide_app_action "Node.js" "$NODEJS_INSTALLED" "$_nodejs_cur" "$NODEJS_VERSION" "A" "DT2_NODEJS"
_nodejs_action="$DT2_APP_ACTION"
# ── 중복 처리: 업데이트하지 않은 경우 사용자가 고른 중복 처리 방식(재설치 등) 적용 ──
if [ "$_nodejs_action" = "skip" ] && [ "$NODEJS_INSTALLED" = true ] && [ "$(_resolve_action true "Node.js")" = "reinstall" ]; then
    _nodejs_action="update"
fi

# ── 설치 실행 ─────────────────────────────────────────────────────
if [ "$_nodejs_action" != "skip" ]; then
    if [ "$_nodejs_action" = "update" ]; then
        echo "   🗑️  기존 Node.js(current) 디렉토리 삭제 중..."
        rm -rf "$DEVTOOLS2/modules/nodejs/current"
    fi
    echo "   📦 Node.js $NODEJS_VERSION 설치..."
    install_tool \
        "https://nodejs.org/dist/${NODEJS_VERSION}/node-${NODEJS_VERSION}-linux-{ARCH}.tar.xz" \
        'x64' 'arm64' 'current'
    # 마지막 설치 버전과 다르면 이 PC 의 설치 이력(data/state) 업데이트
    if [ "$NODEJS_VERSION" != "$NODEJS_PINNED" ]; then
        update_pinned_version "nodejs" "$NODEJS_VERSION"
    fi
fi
# 예전 이름(node-v24)으로 참조하던 곳을 위한 호환 링크
_dt2_migrate_dir "$DEVTOOLS2/modules/nodejs/node-v24" "$DEVTOOLS2/modules/nodejs/current"

# 전역 패키지 저장소 생성 및 복구
mkdir -p "$DEVTOOLS2/data/.npm-packages"
cd "$DEVTOOLS2/data/.npm-packages"

# 임시 PATH 추가 (방금 설치한 Node.js 바이너리를 현재 셸 환경에 즉시 연동)
export PATH="$DEVTOOLS2/modules/nodejs/current/bin:$PATH"
export NPM_CONFIG_GLOBALCONFIG="$DEVTOOLS2/.config/nodejs/.npmrc"
unset NPM_CONFIG_USERCONFIG
# setup_npm_mirror는 npmmirror 불가/폴백 시 return 1을 반환하는 정상 케이스가 있어
# set -e 환경에서 스크립트가 중단되는 버그를 방지한다.
setup_npm_mirror || true

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
        local err_log="$DT2_TMP/_npm_install_err.log"
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
        export NPM_CONFIG_REGISTRY="$target_reg"
        print_done "$done_label (적용 저장소: $target_reg)"
    else
        print_error "글로벌 npm 패키지 설치 실패!"
        if [ -f "$DT2_TMP/_npm_install_err.log" ]; then
            echo "   [에러 상세 로그]"
            grep -E "npm ERR!" "$DT2_TMP/_npm_install_err.log" | head -n 10 | sed 's/^/   /'
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

NEOVIM_PINNED=$(get_pinned_version "neovim")
# [track] neovim (기본 "0.12"): 0.12.x 안에서 최신 패치. 마이너(0.13)는 플러그인 호환을 확인한 뒤 track 을 바꿔 올립니다.
NEOVIM_VERSION=$(resolve_track_version neovim 0.12 list_github_release_versions neovim/neovim)
if [ -n "$NEOVIM_VERSION" ]; then
    NEOVIM_VERSION="v${NEOVIM_VERSION#v}"
else
    NEOVIM_VERSION="${NEOVIM_PINNED:-v0.12.5}"   # 목록 조회 실패 시 마지막 설치 버전으로 폴백
fi
_nvim_arch="$([ "$IS_ARM64" = true ] && echo 'arm64' || echo 'x86_64')"
_nvim_asset="nvim-linux-${_nvim_arch}.tar.gz"
_nvim_url="https://github.com/neovim/neovim/releases/download/${NEOVIM_VERSION}/${_nvim_asset}"

# Neovim 은 체크섬 파일(.sha256sum)을 배포하지 않으므로(404 확인) GitHub API 의 자산 SHA256 으로 검증합니다.
# - 조회되면 반드시 검증하고, 불일치하면 설치하지 않습니다(예전처럼 "검증 없이 재시도"하지 않음).
# - API 호출 한도 초과 등으로 조회하지 못한 경우에만 경고 후 검증 없이 설치합니다.
install_neovim() {
    local _sha
    _sha=$(github_asset_sha256 "neovim/neovim" "$NEOVIM_VERSION" "$_nvim_asset")
    if [ -z "$_sha" ]; then
        print_warn "Neovim SHA256 을 GitHub API 에서 조회하지 못해 체크섬 검증 없이 설치합니다 (API 호출 한도 초과일 수 있음, GITHUB_TOKEN 설정 시 완화)."
    fi
    safe_download_and_extract "$_nvim_url" "$DEVTOOLS2/modules/neovim/nvim" 1 "$_sha" "Neovim $NEOVIM_VERSION"
}

_nvim_dir="$DEVTOOLS2/modules/neovim/nvim"
_nvim_bin="$_nvim_dir/bin/nvim"
_installed_nvim_ver=""
if [ -x "$_nvim_bin" ]; then
    _installed_nvim_ver=$("$_nvim_bin" --version 2>/dev/null | head -n 1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || true)
    if [ -z "$_installed_nvim_ver" ]; then
        _raw_v=$("$_nvim_bin" --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
        [ -n "$_raw_v" ] && _installed_nvim_ver="v$_raw_v"
    fi
fi

_do_nvim_install=false
if [ -n "$_installed_nvim_ver" ]; then
    # 설치/업데이트 판단은 공용 함수 decide_app_action (track 범위 안에 새 버전 → 업데이트 여부 확인, 기본 Y)
    # (예전에는 중복 처리 방식이 "기존 도구 유지"(기본값)이면 새 버전이 있어도 업데이트하지 않았음)
    decide_app_action "Neovim" true "$_installed_nvim_ver" "$NEOVIM_VERSION" "A" "DT2_NEOVIM"
    if [ "$DT2_APP_ACTION" = "update" ]; then
        _do_nvim_install=true
    elif [ "$DUPLICATE_MODE" = "remove" ]; then
        print_info "Neovim $_installed_nvim_ver 재설치 진행 (중복 처리: 삭제 후 재설치 모드)"
        _do_nvim_install=true
    fi
elif [ -d "$_nvim_dir" ]; then
    # 디렉터리는 있으나 바이너리가 없거나 손상된 경우
    print_warn "Neovim 디렉터리가 손상되었거나 바이너리를 찾을 수 없습니다: $_nvim_dir"
    if [ "$DUPLICATE_MODE" = "remove" ] || prompt_confirm "👉 Neovim을 새로 설치하시겠습니까?" "Y"; then
        _do_nvim_install=true
    fi
else
    # 최초 설치
    _do_nvim_install=true
fi

if [ "$_do_nvim_install" = true ]; then
    # 새 버전 설치에 성공했을 때만 기존 설치를 지웁니다(실패 시 기존 Neovim 유지).
    _nvim_old="$DEVTOOLS2/modules/neovim/.dt2-old-nvim"
    rm -rf "$_nvim_old"
    [ -d "$_nvim_dir" ] && mv "$_nvim_dir" "$_nvim_old"
    if install_neovim; then
        rm -rf "$_nvim_old"
        echo "   ✅ Neovim $NEOVIM_VERSION 설치 완료"
        if [ "$NEOVIM_VERSION" != "$NEOVIM_PINNED" ]; then
            update_pinned_version "neovim" "$NEOVIM_VERSION"
        fi
    else
        rm -rf "$_nvim_dir"
        [ -d "$_nvim_old" ] && mv "$_nvim_old" "$_nvim_dir"
        echo "   ❌ Neovim 설치 실패 — 기존 Neovim 을 복원했습니다." >&2
    fi
fi

echo "✅ Neovim 설치 완료 ($ARCH)"
echo ""

echo "---------------------------------------------------------------------------"
# 6. Ghostty 포터블 설치: https://ghostty.org/
echo "💚 6. Ghostty 포터블 설치 단계"
echo ""

if [ "$IS_WSL2" = true ]; then
    echo "   ⚠️  [WSL2 환경 감지] Ghostty는 WSL2에서 지원되지 않으므로 설치를 건너뜁니다."
    echo "   💬 WSL2 에서는 Windows Terminal 을 사용합니다(2.setup-windows-terminal.ps1 이 설정)."
else
    echo "💚 6. Ghostty 포터블 설치 중..."
    mkdir -p "$DEVTOOLS2/modules/ghostty"
    cd "$DEVTOOLS2/modules/ghostty"

    # ── 설치 여부·버전 결정: 앱 규칙 (미설치 → 설치 여부 확인 / 설치됨 → 최신 버전 확인 후 업데이트 여부 확인) ──
    # Ghostty 는 Linux 데스크톱의 기본 터미널 "앱"이라 [track] ghostty = "latest"(항상 최신)이고,
    # 설치 여부를 묻는 앱 규칙(Zed·Orca·VS Code·Sublime Merge 와 동일)을 씁니다.
    # (Java·Node.js 같은 필수 개발 런타임은 같은 track 정책을 따르되 미설치면 묻지 않고 설치)
    #   ● 미설치: 설치 여부 확인 (기본 터미널이라 기본값 Y) → 최신 버전 설치 (조회 실패 시 최종 설치 버전)
    #   ● 설치됨: 최신 버전 조회 → 새 버전이 있으면 업데이트 여부 확인 (기본값 Y), 조회 실패 시 확인 건너뜀
    #   ● GHOSTTY_PINNED 는 마지막으로 설치에 성공한 버전입니다(설치 성공 시 update_pinned_version 으로 기록).
    #   ● 업데이트하지 않은 경우에는 중복 처리 방식(DUPLICATE_MODE: 재설치 등)을 기존처럼 존중합니다.
    #   ● 대상 버전은 [track] ghostty(기본 "latest") 범위 안의 최신 — 다른 도구와 같은 resolve_track_version 사용
    echo -n "   🔍 Ghostty 최신 버전 조회 중... "
    set +e; _gl_latest=$(resolve_track_version ghostty latest list_github_release_versions pkgforge-dev/ghostty-appimage); set -e
    [ -n "$_gl_latest" ] && echo "완료 ($_gl_latest)" || echo "실패 (조회 불가)"

    # 판단은 공용 함수 decide_app_action(_install-utils.sh)에 맡깁니다 (Zed·Orca·VS Code·Sublime Merge 와 동일 규칙)
    # (이미 설치되어 있지만 최신 버전이 감지된 경우 스마트 업데이트 처리 → 결과 update)
    decide_app_action "Ghostty (Linux 기본 터미널)" "$GHOSTTY_INSTALLED" "$GHOSTTY_PINNED" "${_gl_latest:-}" "Y" "DT2_GHOSTTY"
    case "$DT2_APP_ACTION" in
        install) _ghostty_action="install";   GHOSTTY_VERSION="${_gl_latest:-$GHOSTTY_PINNED}" ;;
        update)  _ghostty_action="reinstall"; GHOSTTY_VERSION="$_gl_latest" ;;
        *)       _ghostty_action="skip" ;;
    esac
    if [ "$GHOSTTY_INSTALLED" = true ]; then
        # ── 중복 처리: 업데이트하지 않은 경우 사용자가 고른 중복 처리 방식(재설치 등) 적용 ──
        if [ "$_ghostty_action" = "skip" ] && [ "$(_resolve_action "$GHOSTTY_INSTALLED" "Ghostty")" = "reinstall" ]; then
            _ghostty_action="reinstall"
        fi
    fi

    # ── 설치 실행 ─────────────────────────────────────────────────
    if [ "$_ghostty_action" = "skip" ]; then
        # (미설치 후 설치 거절 / 이미 최신 / 업데이트 거절 — 안내는 위에서 출력)
        if [ "$GHOSTTY_INSTALLED" = true ]; then
            echo "   ⏭️  [건너뜀] ghostty AppImage가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -f '$DEVTOOLS2/modules/ghostty/ghostty'"
        fi
    else
        if [ "$_ghostty_action" = "reinstall" ]; then
            echo "   🗑️  기존 ghostty AppImage 삭제 중..."
            rm -f "$DEVTOOLS2/modules/ghostty/ghostty"
        fi
        echo -n "   📦 Ghostty $GHOSTTY_VERSION AppImage 다운로드 중..."
        _gh_url="https://github.com/pkgforge-dev/ghostty-appimage/releases/download/v${GHOSTTY_VERSION}/Ghostty-${GHOSTTY_VERSION}-${ARCH}.AppImage"
        # 체크섬 파일이 없어 GitHub API 의 자산 SHA256 으로 검증 (조회 실패 시에만 검증 없이 설치)
        _gh_sha=$(github_asset_sha256 "pkgforge-dev/ghostty-appimage" "v${GHOSTTY_VERSION}" "Ghostty-${GHOSTTY_VERSION}-${ARCH}.AppImage")
        [ -z "$_gh_sha" ] && echo "" && print_warn "Ghostty SHA256 을 GitHub API 에서 조회하지 못해 체크섬 검증 없이 설치합니다."
        if safe_download_binary "$_gh_url" "$DEVTOOLS2/modules/ghostty/ghostty" 755 "$_gh_sha"; then
            echo " 완료"

            # 설정 파일 경로 심볼릭 링크 생성
            _ghostty_symlink_script="$DEVTOOLS2/scripts/linux/cmd/create-symbolic-link.sh"
            if [ -f "$_ghostty_symlink_script" ]; then
                "$_ghostty_symlink_script" "$DEVTOOLS2/.config/ghostty" "$HOME/.config/ghostty"
            else
                curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "https://raw.githubusercontent.com/devers2/_devtools2/${DT2_REF:-main}/scripts/linux/cmd/create-symbolic-link.sh" \
                    | bash -s -- "$DEVTOOLS2/.config/ghostty" "$HOME/.config/ghostty"
            fi

            # 최신 버전으로 설치 성공한 경우에만 이력 업데이트
            if [ "$GHOSTTY_VERSION" != "$GHOSTTY_PINNED" ]; then
                update_pinned_version "ghostty" "$GHOSTTY_VERSION"
            fi
        else
            echo " ❌ Ghostty 다운로드 실패" >&2
        fi
    fi

    # 글꼴 크기를 ui-defaults.json 과 동기화 (설치/건너뜀과 무관하게 매번 — GNOME 텍스트 배율 변경도 반영)
    sync_ghostty_font_size "$DEVTOOLS2/.config/ghostty"

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
