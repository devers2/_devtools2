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
        curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_TOML_RAW_URL" 2>/dev/null || true
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
            # ⚠️ 이 함수의 결과는 모든 호출부에서 $(_resolve_action ...)로 캡처됩니다.
            # 안내 메시지/프롬프트를 stdout에 그대로 출력하면 최종 반환값("reinstall"/
            # "skip")에 섞여 들어가 호출부의 case 분기가 깨지고, 동시에 프롬프트 문구도
            # 화면에 안 보인 채 read만 기다리는 상태가 됩니다. stderr로 분리합니다.
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
            rm -f "$GRADLE_DEBUG_FILE"
            print_info "이전에 설치된 Attach 모드 설정을 삭제했습니다: $GRADLE_DEBUG_FILE"
        else
            print_skip "Gradle DAP Attach 전역 설정을 나중에 추가하려면"
            echo "      $GRADLE_DEBUG_FILE 파일을 직접 생성하세요."
        fi
    fi
    echo ""
}
