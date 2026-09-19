#!/bin/bash
# ==============================================================================
# _install-utils.sh — 도구 설치 스크립트 공용 유틸리티
# (2.install-core-tools.sh, 3.install-cli-tools.sh 에서 공용으로 사용)
#
# 전제 조건: 이 파일을 source 하기 전에 아래가 이미 준비되어 있어야 합니다.
#   - $DEVTOOLS2 (설치 루트 경로)
#   - _common.sh 의 print_*, prompt_input, _C_* 색상 변수 (_load_common 로 로드됨)
#
# 사용법:
#   source "$(dirname "$(readlink -f "$0")")/_install-utils.sh"
#
# [로딩 순서: 온라인 전용]
# 이 파일을 로드하는 스크립트는 GitHub main 최신 버전을 curl로 시도하고, 실패하면 바로
# 하드 실패합니다 — TOOL_VERSIONS_TOML 등은 인라인 대체가 불가능하고, 이 설치 스크립트들은
# 어차피 네트워크 없이는 동작할 수 없기 때문입니다. 이 curl 호출에는 반드시 Cache-Control/
# Pragma 캐시 우회 헤더를 포함해야 합니다 — 없으면 GitHub raw CDN이 방금 푸시하기 전
# 구버전을 서빙할 수 있습니다.
# scripts/windows/*.ps1 에는 로컬 파일을 아예 읽으면 안 됩니다 — 각 ps1 헤더 4번 항목 참고.
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

# ── 아키텍처별 tar.gz 아카이브 다운로드 및 폴더 정리 설치 공용 함수 ─────────
# 사용법: install_tool <URL_TEMPLATE> <X64_ARCH> <ARM_ARCH> <TARGET_DIR>
# URL_TEMPLATE 내 '{ARCH}' 문자열이 현재 아키텍처 식별자로 치환됩니다.
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

    if ! download_with_progress "$DOWNLOAD_URL" "$FILE_NAME" "$TARGET_DIR"; then
        echo "   ❌ $TARGET_DIR 다운로드 실패 ($DOWNLOAD_URL)" >&2
        rm -f "$FILE_NAME"
        return 1
    fi

    echo -n "   📦 $TARGET_DIR 압축 해제 중..."
    tar -xf "$FILE_NAME" &
    local _tar_pid=$!
    show_spinner $_tar_pid
    if ! wait $_tar_pid 2>/dev/null; then
        echo " ❌ 압축 해제 실패" >&2
        rm -f "$FILE_NAME"
        return 1
    fi
    echo " 완료"

    # 폴더 이름 정리 (패턴 매칭으로 이동 후 정리)
    local EXTRACTED_DIR
    EXTRACTED_DIR=$(tar -tf "$FILE_NAME" 2>/dev/null | head -1 | cut -f1 -d"/")
    if [ -n "$EXTRACTED_DIR" ] && [ "$EXTRACTED_DIR" != "$TARGET_DIR" ] && [ -e "$EXTRACTED_DIR" ]; then
        rm -rf "$TARGET_DIR"
        mv "$EXTRACTED_DIR" "$TARGET_DIR"
    fi

    rm -f "$FILE_NAME"
    echo "   ✅ $TARGET_DIR ($ARCH) 설치 완료"
}

# ─────────────────────────────────────────────────────────────────
# 📄 TOML 및 머신 상태(data/state) 유틸리티 함수
# ─────────────────────────────────────────────────────────────────
TOOL_VERSIONS_TOML="$DEVTOOLS2/scripts/linux/dev-env/tool-versions.toml"
_TOML_RAW_URL="https://raw.githubusercontent.com/devers2/_devtools2/${DT2_REF:-main}/scripts/linux/dev-env/tool-versions.toml"
STATE_DIR="$DEVTOOLS2/data/state"
STATE_FILE="$STATE_DIR/installed-tools.json"

# 로컬에 없으면 GitHub에서 직접 스트리밍하여 TOML 콘텐츠를 읽는 함수
_read_toml() {
    if [ -f "$TOOL_VERSIONS_TOML" ]; then
        cat "$TOOL_VERSIONS_TOML"
    else
        curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_TOML_RAW_URL" 2>/dev/null || true
    fi
}

# 지정한 키의 설치된 버전(로컬 머신 상태 우선 → 없으면 tool-versions.toml 기본값)을 반환합니다.
get_pinned_version() {
    local key="$1"
    # 1순위: 머신별 로컬 상태 파일 (data/state/installed-tools.json)
    if [ -f "$STATE_FILE" ]; then
        local local_ver
        local_ver=$(python3 -c "import json, sys; d=json.load(open('$STATE_FILE')); print(d.get('$key', ''))" 2>/dev/null || true)
        if [ -n "$local_ver" ]; then
            echo "$local_ver"
            return 0
        fi
    fi

    # 2순위: tool-versions.toml 기본 고정 버전
    _read_toml \
        | grep -E "^${key} = \[" 2>/dev/null \
        | grep -oE '"[^"]+"' | head -1 | tr -d '"'
}

# 머신별 설치 버전 상태를 data/state/installed-tools.json 에 격리 기록합니다.
# (Git 형상관리 대상인 tool-versions.toml 은 건드리지 않아 작업 트리 무결성을 보장합니다)
update_pinned_version() {
    local key="$1" new_ver="$2"
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    python3 -c "
import json, os
path = '$STATE_FILE'
data = {}
if os.path.exists(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception:
        data = {}
data['$key'] = '$new_ver'
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
" 2>/dev/null || true
    echo "   📝 [머신 상태: data/state] ${key} 버전 기록: \"${new_ver}\""
}

# tool-versions.toml 에서 지원하는 Adoptium JDK 메이저 버전 목록을 내림차순(예: "25 21 17 8")으로 반환합니다.
get_supported_jdk_versions() {
    local jdks
    jdks=$(_read_toml | grep -E '^jdk[0-9]+ = \[' 2>/dev/null | grep -oE 'jdk[0-9]+' | sed 's/^jdk//' | sort -rn | tr '\n' ' ' | sed 's/ *$//' || true)
    if [ -n "$jdks" ]; then
        echo "$jdks"
    else
        echo "25 21 17 8"
    fi
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
    local mode="${DUPLICATE_MODE:-${DT2_DUPLICATE_MODE:-skip}}"
    case "$mode" in
        remove|reinstall)
            echo "reinstall"
            ;;
        individual)
            if [ "${DT2_NONINTERACTIVE:-0}" = "1" ] || [ ! -t 0 ] && [ ! -c /dev/tty ]; then
                echo "skip"
                return
            fi
            echo "" >&2
            echo "   ⚠️  ${tool_name}이(가) 이미 설치되어 있습니다." >&2
            printf "${_C_YELLOW}${_C_BOLD}%s${_C_RESET} " "   삭제 후 재설치하시겠습니까? [y/${_C_DEFAULT}N${_C_RESET}]: " >&2
            IFS= read -r _dup_sel </dev/tty || true
            echo "" >&2
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

# ─────────────────────────────────────────────────────────────────
# 버전 설치 방식 선택 프롬프트 (1=최신 / 2=TOML 고정 / 3=도구별 개별) — 공용
# 결과: 전역 변수 VERSION_MODE 에 "latest" | "pinned" | "individual" 설정
# (2.install-core-tools.sh / 3.install-cli-tools.sh 공용)
# ─────────────────────────────────────────────────────────────────
_select_version_mode() {
    if [ -n "${DT2_VERSION_MODE:-}" ]; then
        VERSION_MODE="$DT2_VERSION_MODE"
        print_info "환경변수(DT2_VERSION_MODE) 설정 적용됨: $VERSION_MODE"
        return 0
    fi
    if [ "${DT2_NONINTERACTIVE:-0}" = "1" ] || [ ! -t 0 ] && [ ! -c /dev/tty ]; then
        VERSION_MODE="pinned"
        print_info "비대화형 모드: 기본 고정(TOML) 버전으로 자동 진행됩니다."
        return 0
    fi

    print_question "❓ 적용할 버전 선택 방식을 선택하세요:"
    echo ""
    print_option "1" "모든 도구 최신 버전으로 설치 (온라인 최신 릴리스)"
    print_option "2" "모든 도구 지정 버전으로 설치 (TOML 고정/최종 설치 버전)" "[기본값]"
    print_option "3" "도구별 개별 확인 (최신/지정 버전 선택)"
    echo ""
    prompt_read _ver_choice "   선택 [1/${_C_DEFAULT}2${_C_RESET}/3]: "
    echo ""
    case "${_ver_choice:-2}" in
        1) VERSION_MODE="latest"     ; print_info "버전 선택: 모든 도구 최신 버전 선택됨" ;;
        3) VERSION_MODE="individual" ; print_info "버전 선택: 도구별 개별 확인 선택됨" ;;
        *) VERSION_MODE="pinned"     ; print_info "버전 선택: 모든 도구 지정(TOML) 버전 선택됨" ;;
    esac

    # TOML 고정 버전이 아닌 다른 버전을 설치할 수 있는 경우, 문제가 생겼을 때
    # 되돌리는 방법을 미리 안내합니다 (tool-versions.toml 상단 규칙과 동일한 절차).
    if [ "$VERSION_MODE" != "pinned" ]; then
        echo ""
        print_info "💡 참고: 선택하신 방식은 TOML에 고정된 기본 버전과 다른 버전을 설치할 수 있습니다."
        print_info "   설치한 버전이 호환되지 않는 문제가 발생하면, 아래 파일을 열어 배열 맨 앞에"
        print_info "   새로 추가된 버전 항목을 지워 이전 버전으로 되돌린 뒤, 이 스크립트를 다시"
        print_info "   실행해 '2) 지정 버전으로 설치'를 선택하면 이전 고정 버전으로 재설치됩니다."
        print_info "   TOML 파일 위치: $TOOL_VERSIONS_TOML"
    fi
}

# ─────────────────────────────────────────────────────────────────
# 🐛 Gradle DAP (디버거 Attach) 전역 설정 공용 함수
# ─────────────────────────────────────────────────────────────────
configure_gradle_dap() {
    echo "---------------------------------------------------------------------------"
    print_step "🐛 8. Gradle DAP (디버거 Attach) 전역 설정"
    echo ""
    echo "   Gradle bootRun 실행 시 JDWP(Java Debug Wire Protocol)를 자동으로 활성화하여"
    echo "   DAP 클라이언트(Neovim DAP 등)를 포트 5005 로 Attach 할 수 있게 됩니다."
    echo ""
    echo "   대상 파일: ~/.gradle/init.d/debug.gradle"
    echo ""
    print_info "💡 Neovim 사용 안내:"
    echo "      - <leader> + d + a 단축키로 실행 중인 JVM에 attach 합니다."
    echo "      - (참고) Mason 에서 java-debug-adapter 가 설치되어 있어야 함."
    echo ""

    local GRADLE_INIT_DIR="$HOME/.gradle/init.d"
    local GRADLE_DEBUG_FILE="$GRADLE_INIT_DIR/debug.gradle"

    # 기본값 n: 이 프로젝트의 기본 디버그 흐름은 launch 모드(dap.lua)라서, attach용 전역
    # JDWP 설정을 기본으로 깔 필요가 없습니다 — 필요한 사람만 명시적으로 y를 입력하세요.
    if prompt_confirm "👉 Gradle bootRun DAP Attach 모드 전역 설정을 추가할까요?" "N"; then
        mkdir -p "$GRADLE_INIT_DIR"

        local do_write=true
        if [ -f "$GRADLE_DEBUG_FILE" ]; then
            echo ""
            print_warn "파일이 이미 존재합니다: $GRADLE_DEBUG_FILE"
            if ! prompt_confirm "   기존 파일을 새 설정으로 교체할까요?" "N"; then
                do_write=false
                print_info "기존 파일을 유지합니다."
            fi
        fi

        if [ "$do_write" = "true" ]; then
            cat > "$GRADLE_DEBUG_FILE" << 'EOF'
allprojects {
  tasks.withType(JavaExec).configureEach {
    if (name == "bootRun") {
      // jvmArgs 리스트에 "-agentlib:jdwp"로 시작하는 설정이 있는지 확인
      def hasJDWP = jvmArgs.any { it.toString().contains("-agentlib:jdwp") }

      if (hasJDWP) {
        // 로컬(-I 옵션 등)에서 이미 설정했다면 전역 설정(5005)은 하지 않음
        println ">>> [Global] Custom debug config detected. Prioritizing your custom port."
      } else {
        def javaVersion = org.gradle.api.JavaVersion.current()
        def debugAddress = "127.0.0.1:5005"

        // suspend=y 로 변경하면 디버거가 연결(Attach)되기 전까지 대기한다.
        jvmArgs("-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=${debugAddress}")
        println ">>> [Global] Default JDWP Address assigned: ${debugAddress} (Java Version: ${javaVersion})"
      }
    }
  }
}
EOF
            print_done "Gradle DAP Attach 전역 설정 완료"
            echo "      파일: $GRADLE_DEBUG_FILE"
            echo "      포트: 127.0.0.1:5005 (suspend=n, Attach 모드)"
        fi
    else
        if [ -f "$GRADLE_DEBUG_FILE" ]; then
            print_info "기존 Gradle DAP Attach 설정을 유지합니다 (변경 없음): $GRADLE_DEBUG_FILE"
        else
            print_skip "Gradle DAP Attach 전역 설정을 건너뜁니다."
            echo "      나중에 추가하려면 $GRADLE_DEBUG_FILE 파일을 직접 생성하세요."
        fi
    fi
    echo ""
}


# ─────────────────────────────────────────────────────────────────
# 🔒 SHA256 체크섬 검증 유틸리티
# ─────────────────────────────────────────────────────────────────
# 인수: $1 = 대상 파일 경로, $2 = 64자리 16진수 SHA256 또는 .sha256 파일 URL
verify_sha256() {
    local target_file="$1"
    local checksum_spec="$2"

    [ -z "$checksum_spec" ] && return 0

    if [ ! -f "$target_file" ]; then
        echo "❌ verify_sha256 오류: 검증 대상 파일이 존재하지 않습니다: $target_file" >&2
        return 1
    fi

    local expected_hash=""
    if [[ "$checksum_spec" =~ ^[0-9a-fA-F]{64}$ ]]; then
        expected_hash="$checksum_spec"
    elif [[ "$checksum_spec" =~ ^https?:// ]]; then
        local raw_cs
        raw_cs=$(curl -fsSL --max-time 15 "$checksum_spec" 2>/dev/null || true)
        expected_hash=$(echo "$raw_cs" | grep -oE '[0-9a-fA-F]{64}' | head -1 || true)
        if [ -z "$expected_hash" ]; then
            echo "⚠️  체크섬 URL에서 유효한 SHA256 해시를 찾을 수 없습니다: $checksum_spec" >&2
            return 1
        fi
    fi

    if [ -n "$expected_hash" ]; then
        local actual_hash
        actual_hash=$(sha256sum "$target_file" 2>/dev/null | awk '{print $1}')
        if [ "${expected_hash,,}" != "${actual_hash,,}" ]; then
            echo "❌ SHA256 체크섬 불일치! (예상: $expected_hash, 실제: $actual_hash)" >&2
            return 1
        fi
        echo "   🔒 SHA256 무결성 검증 성공 ($actual_hash)"
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────────
# 📥 안전한 공용 다운로드 유틸리티 (HTTP 에러 검출, 체크섬 검증 및 원자적 처리)
# ─────────────────────────────────────────────────────────────────
# 1) 압축 아카이브(tar.gz, zip) 안전 다운로드 및 압축 해제
#    성공 시 0, 실패 시 1 반환 (실패 시 대상 디렉터리 오염 방지)
#    인수: $1 = URL, $2 = 대상 디렉터리, $3 = strip_count(기본 0), $4 = sha256_or_url(선택)
safe_download_and_extract() {
    local url="$1"
    local target_dir="$2"
    local strip_count="${3:-0}"
    local checksum_spec="${4:-}"

    if [ -z "$url" ] || [ -z "$target_dir" ]; then
        echo "❌ safe_download_and_extract 오류: URL과 대상 디렉터리는 필수입니다." >&2
        return 1
    fi

    local tmp_archive
    tmp_archive=$(mktemp "/tmp/dt2_dl_XXXXXX")
    trap 'rm -f "$tmp_archive"' RETURN

    if ! curl -fsSL "$url" -o "$tmp_archive"; then
        echo "❌ 다운로드 실패 (HTTP 에러 또는 연결 오류): $url" >&2
        return 1
    fi

    if [ ! -s "$tmp_archive" ]; then
        echo "❌ 다운로드 실패 (빈 파일): $url" >&2
        return 1
    fi

    if [ -n "$checksum_spec" ]; then
        if ! verify_sha256 "$tmp_archive" "$checksum_spec"; then
            return 1
        fi
    fi

    mkdir -p "$target_dir"
    local strip_opt=""
    [ "$strip_count" -gt 0 ] && strip_opt="--strip-components=$strip_count"

    if [[ "$url" == *.zip ]]; then
        if ! unzip -q -o "$tmp_archive" -d "$target_dir"; then
            echo "❌ zip 압축 해제 실패: $url" >&2
            return 1
        fi
    else
        if ! tar -xzf "$tmp_archive" -C "$target_dir" $strip_opt; then
            echo "❌ tar.gz 압축 해제 실패: $url" >&2
            return 1
        fi
    fi

    return 0
}

# 2) 단일 바이너리/스크립트 파일 안전 다운로드
#    성공 시 0, 실패 시 1 반환 (원자적 교체 및 체크섬 검증 지원)
#    인수: $1 = URL, $2 = 대상 파일, $3 = 권한모드(기본 755), $4 = sha256_or_url(선택)
safe_download_binary() {
    local url="$1"
    local target_file="$2"
    local chmod_mode="${3:-755}"
    local checksum_spec="${4:-}"

    if [ -z "$url" ] || [ -z "$target_file" ]; then
        echo "❌ safe_download_binary 오류: URL과 대상 파일 경로는 필수입니다." >&2
        return 1
    fi

    local target_dir
    target_dir=$(dirname "$target_file")
    mkdir -p "$target_dir"

    local tmp_file
    tmp_file=$(mktemp "/tmp/dt2_bin_XXXXXX")
    trap 'rm -f "$tmp_file"' RETURN

    if ! curl -fsSL "$url" -o "$tmp_file"; then
        echo "❌ 바이너리 다운로드 실패 (HTTP 에러 또는 연결 오류): $url" >&2
        return 1
    fi

    if [ ! -s "$tmp_file" ]; then
        echo "❌ 다운로드 실패 (빈 파일): $url" >&2
        return 1
    fi

    if [ -n "$checksum_spec" ]; then
        if ! verify_sha256 "$tmp_file" "$checksum_spec"; then
            return 1
        fi
    fi

    chmod "$chmod_mode" "$tmp_file"
    mv -f "$tmp_file" "$target_file"
    return 0
}

# ─────────────────────────────────────────────────────────────────
# ☕ Adoptium Eclipse Temurin JDK 릴리즈 메타데이터 조회 헬퍼
# 인수: $1 = 메이저 버전 (8, 17, 21, 25), $2 = 아키텍처 ("x64" 또는 "aarch64")
# 출력: release_name|download_url|checksum (파이프 구분)
fetch_adoptium_release() {
    local feature_ver="$1"
    local arch="$2"
    local py_script='
import sys, urllib.request, json
ver, arch = sys.argv[1:3]
url = f"https://api.adoptium.net/v3/assets/latest/{ver}/hotspot?os=linux&architecture={arch}&image_type=jdk"
req = urllib.request.Request(url, headers={"User-Agent": "curl/7.81.0"})
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode())
        if isinstance(data, list) and len(data) > 0:
            rel = data[0].get("release_name", "")
            pkg = data[0].get("binary", {}).get("package", {})
            link = pkg.get("link", "")
            chk = pkg.get("checksum", "")
            if rel and link:
                print(f"{rel}|{link}|{chk}")
except Exception:
    pass
'
    python3 -c "$py_script" "$feature_ver" "$arch" 2>/dev/null || true
}
