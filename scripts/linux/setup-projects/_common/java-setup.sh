#!/usr/bin/env bash
# ==============================================================================
# DEVTOOLS2 setup-projects Java / Gradle Spring Boot 공통 모듈 (java-setup.sh)
# ==============================================================================
# [목적]
#   Gradle 기반 Java / Spring Boot 프로젝트의 초기 개발 환경 구성을 표준화합니다.
#   신규 프로젝트 스크립트 작성 시 단 한 번의 함수 호출(setup_gradle_spring_project)로
#   Bitwarden 세션 확인, Git 저장소 클론, GitHub Packages(GPR) 토큰 설정,
#   .nvim.lua 및 .vscode(settings.json, launch.json) 설정, command-palette 실행 프로필 저장,
#   VSCode 필수 Java 확장 프로그램 설치까지의 모든 과정을 자동화합니다.
#
# [사용 방법]
#   source "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"
#
#   setup_gradle_spring_project \
#       --target-dir "$HOME/workspaces/my-org/my-app" \
#       --repo-url "https://github.com/my-org/my-app.git" \
#       [선택 옵션들...]
#
# [옵션 상세 안내]
#   ■ 필수 옵션:
#     --target-dir <경로>        : 프로젝트를 클론하고 설정할 로컬 작업 디렉토리 경로
#     --repo-url <URL>           : 대상 Git 저장소 주소 (Bitwarden PAT 자동 인증 클론)
#
#   ■ 일반 선택 옵션:
#     --jdk-version <버전>       : 사용할 Java 버전 (기본값: 21, 예: 17, 21, 25)
#     --main-class <FQCN>        : Spring Boot 메인 클래스 전체 패키지 경로 (선택, 예: com.example.DemoApplication)
#                                  (미지정 시 launch.json 및 .nvim.lua의 MAIN_CLASS 생략)
#     --spring-profile <프로필>  : 기본 Spring Active Profile (선택, 예: local,dev 또는 0_DEVELOP,0_LOCAL,s2)
#                                  (미지정 시 기본 프로필 저장을 건너뛰고 기본 인코딩 인자만 적용)
#     --vm-args <인자문자열>     : launch.json에 지정할 JVM 인자 (단일 문자열)
#                                  (미지정 시 -Dfile.encoding=UTF-8 및 --spring-profile 기반 자동 조립)
#     --app-name <이름>          : VSCode/DAP 런치 설정 및 콘솔 안내용 앱 명칭
#                                  (기본값: main-class의 클래스명 또는 대상 폴더명)
#     --project-root <경로>      : .nvim.lua 파일에 설정할 PROJECT_ROOT 상대/절대 경로 (기본값: ./)
#
#   ■ SFTP 마운트 선택 옵션 (원격 디렉토리 마운트가 필요 없는 프로젝트는 전부 생략 가능):
#     Q. --sftp 한 줄로 쓰나요, 아니면 --sftp- 로 시작하는 개별 옵션을 쓰나요?
#     A. 둘 중 편한 방식을 선택하여 사용하시면 됩니다 (상호 대체 및 조합 가능):
#
#     [방식 A: 권장 - 단축 옵션 1개만 사용]
#       --sftp <user@host[:port]>: 접속 정보 1줄만 지정하면 포트 및 마운트 경로가 자동 결정됩니다.
#                                  - 포트 생략 시 기본 22번 포트 사용
#                                  - 원격 마운트 경로 자동 기본값: ~/mount/<app-name>
#                                  - 로컬 마운트 경로 자동 기본값: $HOME/mount/<app-name>
#                                  (예: --sftp "namupia@aiplus.im:222" 또는 --sftp "user@example.com")
#
#     [방식 B: 단축 옵션 + 특정 경로만 커스텀 지정]
#       --sftp <user@host[:port]> 사용 시 마운트 경로만 기본값(~/mount/<app-name>)과 다르게 바꾸고 싶다면
#       아래 경로 옵션만 선택적으로 함께 추가하면 해당 경로로 덮어씁니다:
#       --sftp-remote-path <경로>: 서버 측 원격 마운트 경로 (예: ~/mount/custom 또는 /var/log/app)
#       --sftp-local-path <경로> : 로컬 측 마운트 대상 경로 (예: $HOME/mount/custom)
#
#     [방식 C: 기존 호환용 - 개별 옵션 분할 지정]
#       --sftp 단축 형식을 쓰지 않고 아래 개별 옵션들을 직접 분할 지정해도 100% 동일하게 동작합니다:
#       --sftp-user <계정>       : SFTP 접속 계정명 (필수)
#       --sftp-host <호스트>     : SFTP 접속 호스트 주소 (필수)
#       --sftp-port <포트>       : SFTP 포트 (선택, 기본값: 22)
#       --sftp-remote-path <경로>: 서버 측 원격 마운트 경로 (선택, 기본값: ~/mount/<app-name>)
#       --sftp-local-path <경로> : 로컬 측 마운트 대상 경로 (선택, 기본값: $HOME/mount/<app-name>)
# ==============================================================================

# VSCode Java 개발 필수 익스텐션 목록
VSCODE_JAVA_EXTENSIONS=(
    "redhat.java"
    "vscjava.vscode-java-debug"
    "vscjava.vscode-java-dependency"
)

# ── 1. .nvim.lua 파일 생성 ────────────────────────────────────────────────────
# 인수:
#   $1 = TARGET_DIR   (필수)
#   $2 = JDK_VERSION  (선택, 기본값: 21)
#   $3 = MAIN_CLASS   (선택, 없을 경우 생략)
#   $4 = PROJECT_ROOT (선택, 기본값: ./)
setup_nvim_lua_java() {
    local TARGET_DIR="$1"
    local JDK_VERSION="${2:-21}"
    local MAIN_CLASS="${3:-}"
    local PROJECT_ROOT="${4:-./}"

    if [ -z "$TARGET_DIR" ]; then
        echo "❌ setup_nvim_lua_java: TARGET_DIR가 지정되지 않았습니다."
        return 1
    fi

    echo "⚙️  .nvim.lua 설정 파일 생성 중..."
    if [ -f "$TARGET_DIR/.nvim.lua" ]; then
        echo "ℹ️  .nvim.lua 이 이미 존재합니다. 덮어쓰지 않습니다 (직접 수정했을 수 있으므로)."
        return 0
    fi

    local TMP_LUA
    TMP_LUA=$(mktemp)
    cat > "$TMP_LUA" <<EOF
PROJECT_ROOT = "${PROJECT_ROOT}"
JDK_VERSION = ${JDK_VERSION}
EOF
    if [ -n "$MAIN_CLASS" ]; then
        echo "MAIN_CLASS = \"${MAIN_CLASS}\"" >> "$TMP_LUA"
    fi
    mv "$TMP_LUA" "$TARGET_DIR/.nvim.lua"
    echo "✅ .nvim.lua 생성 완료!"
}

# ── 2. .vscode/settings.json 생성 (Java 런타임 및 Gradle JDK 설정) ───────────
# 인수:
#   $1 = TARGET_DIR  (필수)
#   $2 = JDK_VERSION (선택, 기본값: 21)
setup_vscode_java_settings() {
    local TARGET_DIR="$1"
    local JDK_VERSION="${2:-21}"
    local DEVTOOLS2_PATH="${DEVTOOLS2:-$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../../..")}"

    local VSCODE_DIR="$TARGET_DIR/.vscode"
    mkdir -p "$VSCODE_DIR"

    if [ -f "$VSCODE_DIR/settings.json" ]; then
        echo "ℹ️  .vscode/settings.json 이 이미 존재합니다. 덮어쓰지 않습니다."
        return 0
    fi

    local JDK_PATH="${DEVTOOLS2_PATH}/modules/java/jdk-${JDK_VERSION}"
    cat > "$VSCODE_DIR/settings.json" <<EOF
{
  "java.configuration.runtimes": [
    {
      "name": "JavaSE-${JDK_VERSION}",
      "path": "${JDK_PATH}",
      "default": true
    }
  ],
  "java.import.gradle.java.home": "${JDK_PATH}"
}
EOF
    echo "✅ .vscode/settings.json 생성 완료"
}

# ── 3. .vscode/launch.json 생성 (DAP 및 VSCode 디버깅 런치 설정) ─────────────
# 인수:
#   $1 = TARGET_DIR  (필수)
#   $2 = APP_NAME    (필수, 예: GoonoELNApplication)
#   $3 = MAIN_CLASS  (필수, 예: so.goono.GoonoELNApplication)
#   $4 = VM_ARGS     (선택, 기본값: -Dfile.encoding=UTF-8)
setup_vscode_java_launch() {
    local TARGET_DIR="$1"
    local APP_NAME="$2"
    local MAIN_CLASS="$3"
    local VM_ARGS="${4:--Dfile.encoding=UTF-8}"

    local VSCODE_DIR="$TARGET_DIR/.vscode"
    mkdir -p "$VSCODE_DIR"

    if [ -f "$VSCODE_DIR/launch.json" ]; then
        echo "ℹ️  .vscode/launch.json 이 이미 존재합니다. 덮어쓰지 않습니다."
        return 0
    fi

    # ⚠️ 주의사항:
    # 1. projectName은 일부러 지정하지 않습니다.
    #    VSCode Java 확장이 실제로 등록하는 프로젝트 이름은 settings.gradle의 rootProject.name과
    #    다를 수 있어, 생략 시 vscode-java-debug가 mainClass만으로 워크스페이스를 탐색해
    #    정확한 프로젝트를 찾으므로 임포터 종류에 구애받지 않고 안전합니다.
    # 2. vmArgs는 반드시 단일 공백 구분 문자열(String)이어야 합니다!
    #    배열(["-D..."])로 선언할 경우 Neovim DAP 및 JDTLS Debug Server에서
    #    JsonSyntaxException: Expected STRING but was BEGIN_ARRAY at path $.vmArgs 크래시가 발생합니다.
    cat > "$VSCODE_DIR/launch.json" <<EOF
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "java",
      "name": "${APP_NAME}",
      "request": "launch",
      "mainClass": "${MAIN_CLASS}",
      "vmArgs": "${VM_ARGS}"
    }
  ]
}
EOF
    echo "✅ .vscode/launch.json 생성 완료!"
}

# ── 4. .vscode 통합 설정 (settings.json + launch.json) ────────────────────────
setup_vscode_java() {
    local TARGET_DIR="$1"
    local JDK_VERSION="${2:-21}"
    local APP_NAME="$3"
    local MAIN_CLASS="$4"
    local VM_ARGS="$5"

    echo "⚙️  .vscode 설정 파일 생성 중..."
    setup_vscode_java_settings "$TARGET_DIR" "$JDK_VERSION"
    if [ -n "$MAIN_CLASS" ]; then
        setup_vscode_java_launch "$TARGET_DIR" "$APP_NAME" "$MAIN_CLASS" "$VM_ARGS"
    fi
}

# ── 5. Gradle Spring Boot 프로젝트 원클릭 표준 설정 함수 ────────────────────
# 사용 가능한 명명 옵션:
#   --target-dir      : 프로젝트 로컬 경로 (필수)
#   --repo-url        : Git 저장소 주소 (필수)
#   --jdk-version     : Java 버전 (선택, 기본값: 21)
#   --main-class      : 스프링 부트 Application 메인 클래스 FQCN (선택)
#   --spring-profile  : 기본 Spring Active Profile (선택, 예: 0_DEVELOP,0_LOCAL,s2)
#   --vm-args         : 추가 JVM 인자 (선택, 미지정 시 인코딩 및 프로필 자동 구성)
#   --app-name        : 런치 구성 이름 (선택, 기본값: mainClass 클래스명 또는 폴더명)
#   --project-root    : .nvim.lua 상의 PROJECT_ROOT (선택, 기본값: ./)
setup_gradle_spring_project() {
    local TARGET_DIR=""
    local REPO_URL=""
    local JDK_VERSION=21
    local MAIN_CLASS=""
    local SPRING_PROFILE=""
    local VM_ARGS=""
    local APP_NAME=""
    local PROJECT_ROOT="./"
    local SFTP_SPEC=""
    local SFTP_USER=""
    local SFTP_HOST=""
    local SFTP_PORT="22"
    local SFTP_REMOTE_PATH=""
    local SFTP_LOCAL_PATH=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --target-dir)        TARGET_DIR="$2"; shift 2 ;;
            --repo-url)          REPO_URL="$2"; shift 2 ;;
            --jdk-version)       JDK_VERSION="$2"; shift 2 ;;
            --main-class)        MAIN_CLASS="$2"; shift 2 ;;
            --spring-profile)    SPRING_PROFILE="$2"; shift 2 ;;
            --vm-args)           VM_ARGS="$2"; shift 2 ;;
            --app-name)          APP_NAME="$2"; shift 2 ;;
            --project-root)      PROJECT_ROOT="$2"; shift 2 ;;
            --sftp)              SFTP_SPEC="$2"; shift 2 ;;
            --sftp-user)         SFTP_USER="$2"; shift 2 ;;
            --sftp-host)         SFTP_HOST="$2"; shift 2 ;;
            --sftp-port)         SFTP_PORT="$2"; shift 2 ;;
            --sftp-remote-path)  SFTP_REMOTE_PATH="$2"; shift 2 ;;
            --sftp-local-path)   SFTP_LOCAL_PATH="$2"; shift 2 ;;
            *) echo "⚠️  알 수 없는 옵션 무시: $1"; shift ;;
        esac
    done

    if [ -z "$TARGET_DIR" ] || [ -z "$REPO_URL" ]; then
        echo "❌ setup_gradle_spring_project: --target-dir 및 --repo-url 은 필수 인자입니다."
        return 1
    fi

    # APP_NAME 자동 결정 (지정되지 않은 경우 MAIN_CLASS의 마지막 클래스명 또는 폴더명)
    if [ -z "$APP_NAME" ]; then
        if [ -n "$MAIN_CLASS" ]; then
            APP_NAME="${MAIN_CLASS##*.}"
        else
            APP_NAME="$(basename "$TARGET_DIR")"
        fi
    fi

    # VM_ARGS 자동 조립 (단일 문자열 보장)
    if [ -z "$VM_ARGS" ]; then
        if [ -n "$SPRING_PROFILE" ]; then
            VM_ARGS="-Dfile.encoding=UTF-8 -Dspring.profiles.active=${SPRING_PROFILE}"
        else
            VM_ARGS="-Dfile.encoding=UTF-8"
        fi
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 [$APP_NAME] Gradle Spring Boot 프로젝트 설정을 시작합니다."
    echo "   대상 경로 : $TARGET_DIR"
    echo "   저장소 URL: $REPO_URL"
    echo "   Java 버전 : JDK $JDK_VERSION"
    [ -n "$MAIN_CLASS" ] && echo "   메인 클래스: $MAIN_CLASS"
    [ -n "$SPRING_PROFILE" ] && echo "   기본 프로필: $SPRING_PROFILE"
    [ -n "$SFTP_SPEC" ] && echo "   SFTP 마운트: $SFTP_SPEC"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 1. Bitwarden 세션 확인 및 Git Clone
    ensure_project_repo "$REPO_URL" "$TARGET_DIR" || return 1

    # 1-1. SFTP 마운트 설정 (선택, SFTP 옵션 지정 시)
    if [ -n "$SFTP_SPEC" ] || [ -n "$SFTP_USER" ]; then
        handle_sftp_mount_options "$SFTP_SPEC" "$SFTP_USER" "$SFTP_HOST" "$SFTP_PORT" "$SFTP_REMOTE_PATH" "$SFTP_LOCAL_PATH" "$APP_NAME" || {
            local _exit_code=$?
            if [ "$_exit_code" -eq 2 ]; then
                return 0
            fi
        }
    fi

    # 2. GitHub Packages 의존성 설정 (gpr.user / gpr.key)
    if command -v setup_gpr_gradle_properties &>/dev/null; then
        setup_gpr_gradle_properties "$TARGET_DIR"
    fi

    # 3. .nvim.lua 파일 생성
    setup_nvim_lua_java "$TARGET_DIR" "$JDK_VERSION" "$MAIN_CLASS" "$PROJECT_ROOT"

    # 4. command-palette 실행 프로필 저장 (~/.devtools2/state.properties)
    if [ -n "$SPRING_PROFILE" ]; then
        save_devtools2_project_state "$TARGET_DIR" "gradle_run.profile" "$SPRING_PROFILE"
    fi

    # 5. .vscode 설정 생성 (settings.json, launch.json)
    setup_vscode_java "$TARGET_DIR" "$JDK_VERSION" "$APP_NAME" "$MAIN_CLASS" "$VM_ARGS"

    # 6. VSCode 필수 확장 프로그램 검사/설치
    install_vscode_extensions "${VSCODE_JAVA_EXTENSIONS[@]}"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉 [$APP_NAME] Gradle Spring Boot 프로젝트 설정이 성공적으로 완료되었습니다!"
    echo "📁 프로젝트 위치: $TARGET_DIR"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
