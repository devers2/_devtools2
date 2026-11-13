# shellcheck shell=bash
# ==============================================================================
# [명령 팔레트] 🐘 Gradle — 실행·빌드·배포, 작업(Tasks) 트리, 테스트 하나만 실행, 데몬 정리 (Gradle 프로젝트에서만 표시)
# ==============================================================================
# command-palette 가 source 로 불러오는 파일입니다(단독 실행 X). 구조 설명은 command-palette 의
# "그룹 파일 불러오기" 주석을 보세요. 이 파일 = 1단계 메뉴 그룹 "🐘 Gradle" (그룹 ID: gradle)

# ==============================================================================
# Gradle 프로젝트 속성 감지 유틸리티
# ==============================================================================

# 루트 gradle.properties → build.gradle(.kts) 순으로 지정한 속성 값을 감지
# (Maven 중앙 저장소 배포 시 group/version 감지에 재사용 — 동일 패턴 중복 방지)
# 인수: $1 = 프로젝트 디렉토리, $2 = 속성 키 (예: group, version)
# 출력: 감지된 값 (없으면 빈 문자열)
detect_gradle_property() {
    local _dir="$1"
    local _key="$2"
    local _val=""

    if [ -f "$_dir/gradle.properties" ]; then
        _val=$(grep -E "^[[:space:]]*${_key}[[:space:]]*=" "$_dir/gradle.properties" 2>/dev/null \
            | head -1 | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    fi
    if [ -z "$_val" ]; then
        # Groovy DSL은 "key = 'x'"와 "key 'x'"(등호 생략) 둘 다 유효하므로 등호를 선택적으로 처리
        local _bf
        for _bf in "$_dir/build.gradle.kts" "$_dir/build.gradle"; do
            if [ -f "$_bf" ]; then
                _val=$(grep -E "^[[:space:]]*${_key}[[:space:]]*=?[[:space:]]*[\"']" "$_bf" 2>/dev/null \
                    | head -1 | sed -E "s/^[[:space:]]*${_key}[[:space:]]*=?[[:space:]]*[\"']([^\"']*)[\"'].*/\1/")
                [ -n "$_val" ] && break
            fi
        done
    fi
    printf "%s" "$_val"
}

# bootRun 실행 전 포트 충돌 사전 확인 및 해소
# 인수: $1 = 모듈명 (없으면 루트 기준)
check_and_resolve_port_conflict() {
    local mod="$1"
    local detected_port=""

    # 핀포인트 설정 파일 검색 (디렉토리 무분별 grep -r 전체 스캔 제거)
    local target_files=()
    local search_base="$CWD/src/main/resources"
    [[ -n "$mod" ]] && search_base="$CWD/$mod/src/main/resources"

    if [[ -d "$search_base" ]]; then
        for f in "$search_base"/application*.yml "$search_base"/application*.yaml "$search_base"/application*.properties; do
            [[ -f "$f" ]] && target_files+=("$f")
        done
    fi

    if [[ ${#target_files[@]} -gt 0 ]]; then
        # server.port 또는 port: 빠른 핀포인트 추출
        detected_port=$(grep -Eh '^[[:space:]]*server\.port[[:space:]]*=[[:space:]]*[0-9]+|^[[:space:]]*port:[[:space:]]*[0-9]+' "${target_files[@]}" 2>/dev/null \
            | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/; s/.*=[[:space:]]*([0-9]+).*/\1/' \
            | head -1)
    fi

    # 감지 실패 시 Spring Boot 기본값 8080 사용
    [[ -z "$detected_port" ]] && detected_port="8080"

    # 1단계: 포트 열림 여부 비블로킹 즉시 확인 (/proc/net/tcp 직접 조회)
    if ! is_port_in_use "$detected_port"; then
        return 0  # 충돌 없음 — 즉시 bootRun 진행
    fi

    # 2단계: 충돌 안내 및 사용자 질문
    echo ""
    echo "⚠️  [포트 충돌 경고] 포트 ${detected_port} 가 이미 다른 프로세스에서 사용 중입니다."
    echo "─────────────────────────────────────────"
    echo ""

    # 대소문자 구분 없는 y/n 입력 판별
    prompt_confirm "❓ 기존 프로세스를 중지하고 bootRun을 시작하시겠습니까?" "N" && CONFLICT_ANS="y" || CONFLICT_ANS="n"

    if [[ "$CONFLICT_ANS" != "y" ]]; then
        echo "❌ bootRun을 중지합니다."
        exit 0
    fi

    # 3단계: 기존 프로세스 중지 (해당 포트를 점유한 PID만 정확히 타겟팅하여 종료)
    echo ""
    echo "🔪 포트 $detected_port 점유 프로세스 중지 시도 중..."
    local target_pids
    target_pids=$(get_pids_by_port "$detected_port")
    if [[ -n "$target_pids" ]]; then
        kill_pids "$target_pids"
    else
        # PID를 직접 찾지 못한 경우의 폴백
        if command -v fuser &>/dev/null; then
            fuser -k -9 "$detected_port/tcp" &>/dev/null || true
        fi
    fi

    # 포트 해제 대기 및 확인
    echo ""
    verify_port_released "$detected_port" 3
    echo ""
    echo "🚀 bootRun을 시작합니다."
    echo ""
}

# ==============================================================================
# 2. 프로젝트 디렉토리 내 그레이들 래퍼 확인
# ==============================================================================
GRADLEW_EXISTS=false
GW_NAME="./gradlew"
if [ -f "$CWD/gradlew" ] || [ -f "$CWD/build.gradle" ] || [ -f "$CWD/build.gradle.kts" ] || [ -f "$CWD/settings.gradle" ] || [ -f "$CWD/settings.gradle.kts" ]; then
    GRADLEW_EXISTS=true
fi

# CentralPortal 설정 여부 확인 (build.gradle 또는 build.gradle.kts 확인)
# 단순 부분 문자열 검색이라 아래 두 형태를 모두 자동으로 잡아낸다 (의도된 동작, 우연이 아님):
#   1) 리포지토리를 직접 선언하는 구식: maven { name = "CentralPortal" ... }
#   2) s2-build-support 플러그인의 공용 헬퍼 호출: S2BuildUtils.configureCentralPortalRepository(project)
#      → 메서드 이름 자체가 "CentralPortal"을 부분 문자열로 포함하므로 별도 패턴 추가 없이 감지됨.
#      (메서드 이름을 바꾸면 이 감지가 깨지니, 이름을 바꿀 경우 이 주석과 함께 패턴도 갱신할 것)
CENTRAL_PORTAL_EXISTS=false
if $GRADLEW_EXISTS; then
    if grep -q "CentralPortal" "$CWD/build.gradle" 2>/dev/null || grep -q "CentralPortal" "$CWD/build.gradle.kts" 2>/dev/null; then
        CENTRAL_PORTAL_EXISTS=true
    fi
fi

# ── [Gradle] 메뉴 — 빠른 실행(bootRun·빌드·배포) + 모듈 › 그룹 › 작업 계층형 메뉴 ──────────
# 1단계 그룹 메뉴의 "🐘 Gradle" 에서 들어옵니다. 첫 단계 맨 위에 기존 전용 흐름(⭐ 실행·빌드·배포 — 포트 충돌 확인,
# launch.json·프로필, clean·제외 옵션 기억, 배포 사전 검증)을 두고, 그 아래에 최근 작업과 전체 작업 트리를 둡니다.
# VS Code Gradle 확장의 Tasks 트리(프로젝트 › 모듈 › 그룹 › 작업)와 같은 구조로, 프로젝트에 실제로 있는 작업을
# 동적으로 보여 줍니다(build·publishing·verification 등 플러그인이 만든 작업 포함).
#   ● 작업 목록: ./gradlew tasks --all 출력을 파싱합니다(모듈 작업은 "s2-core:publish" 형태로 나옴).
#     빌드 설정 파일(settings·build.gradle(.kts)·gradle.properties·*.versions.toml·wrapper)이 바뀌었을 때만 다시 읽고
#     나머지는 캐시(~/.devtools2/gradle-tasks/<프로젝트 키>.tsv)를 씁니다. 플러그인 버전만 바뀐 경우 등은 "🔄 새로 읽기".
#   ● 단계: 모듈(여러 모듈일 때만) → 그룹 → 작업. Esc 는 한 단계 위로, 첫 단계에서는 닫기. fzf 라 글자 입력으로 바로 걸러짐.
#   ● 실행 의미: 루트에서 고른 작업은 이름만 넘겨 모든 모듈에서 실행(./gradlew publish — VS Code·위 build/배포 항목과 같음),
#     하위 모듈에서 고른 작업은 그 모듈만 실행(./gradlew :s2-core:publish).
#   ● 최근 실행한 작업 5개를 첫 단계 맨 위에 보여 줍니다(프로젝트별). "🧪 테스트 하나만 실행" 도 기록됩니다.
#   ● 🧪 테스트 하나만 실행: src/test 아래 테스트 파일에서 클래스를 고르고(메서드는 선택), 그 모듈만 test --tests 로 실행.
#   ● 🧹 Gradle 데몬 정리: 작업이 끝나도 데몬(JVM)이 메모리를 잡고 3시간까지 남아 있어, 상태를 보고 바로 중지합니다.
#   ● JDK: [Gradle] 빌드에서 저장한 Java Home 이 있으면 같은 값을 씁니다(목록 읽기·실행 모두).
_GT_DIR="$STATE_DIR/gradle-tasks"
mkdir -p "$_GT_DIR"
_GT_CACHE="$_GT_DIR/$PROJ_KEY.tsv"
_GT_SIG="$_GT_DIR/$PROJ_KEY.sig"
_GT_RECENT="$_GT_DIR/$PROJ_KEY.recent"

# gradlew 가 없고 build.gradle 만 있는 프로젝트는 설치된 gradle 사용
_GT_GW="$GW_NAME"
if [ ! -x "$CWD/gradlew" ] && command -v gradle >/dev/null 2>&1; then
    _GT_GW="gradle"
fi
_GT_JAVA_ARGS=()
_gt_java_home=$(get_state "gradle_build" "java_home")
[ -n "$_gt_java_home" ] && _GT_JAVA_ARGS=("-Dorg.gradle.java.home=$_gt_java_home")

# 빌드 설정 파일들의 경로·수정 시각·크기로 만든 서명 (macOS 도 지원하도록 find -printf 대신 Python)
_gt_signature() {
    python3 - "$CWD" <<'PYSIG'
import hashlib, os, re, sys
root = sys.argv[1]
skip = {'build', '.gradle', '.git', 'node_modules', 'out', 'bin', '.idea', '.vscode'}
pat = re.compile(r'(settings|build)\.gradle(\.kts)?$|gradle\.properties$|\.versions\.toml$|gradle-wrapper\.properties$')
rows = []
for d, dirs, files in os.walk(root):
    dirs[:] = [x for x in dirs if x not in skip]
    if d[len(root):].count(os.sep) >= 3:
        dirs[:] = []
    for f in files:
        if pat.search(f):
            p = os.path.join(d, f)
            st = os.stat(p)
            rows.append(f"{os.path.relpath(p, root)} {st.st_mtime_ns} {st.st_size}")
print(hashlib.md5('\n'.join(sorted(rows)).encode()).hexdigest())
PYSIG
}

# ./gradlew tasks --all 출력 → "모듈<TAB>그룹<TAB>작업<TAB>설명" (루트 모듈은 빈 문자열, 첫 줄은 "@root<TAB>루트 이름")
# [설명 한글화] Gradle·Spring Boot 표준 작업의 영어 설명을 한글로 바꿉니다(문장 패턴 사전).
#   ● 설명 속 프로젝트 이름('goono-eln', ':s2-core')·퍼블리케이션 이름('mavenJava')·저장소 이름(CentralPortal)은 그대로 살립니다.
#   ● 사전에 없는 설명(프로젝트가 직접 만든 작업 등)은 영어 그대로 둡니다.
#   ● 번역은 목록을 읽을 때 캐시에 저장되므로, 사전을 고치면 _GT_PARSER_VER 를 올려 캐시를 한 번 다시 읽게 합니다.
# (파이썬 코드에 작은따옴표가 많아 python3 -c '...' 대신 heredoc 으로 변수에 담아 넘깁니다 — 표준입력은 Gradle 출력용)
_GT_PARSER_VER=2
read -r -d '' _GT_PARSER_PY <<'PYPARSE'
import re, sys

PROJ = "§P§"  # 설명 속 "root project 'x'" / "project ':x'" 자리 표시
KO = [
    (r"Assembles the outputs of this project\.", "이 프로젝트의 산출물을 만듭니다."),
    (r"Assembles and tests this project\.", "이 프로젝트를 빌드하고 테스트합니다."),
    (r"Assembles and tests this project and all projects that depend on it\.", "이 프로젝트와, 이 프로젝트에 의존하는 모든 프로젝트를 빌드하고 테스트합니다."),
    (r"Assembles and tests this project and all projects it depends on\.", "이 프로젝트와, 이 프로젝트가 의존하는 모든 프로젝트를 빌드하고 테스트합니다."),
    (r"Assembles main classes\.", "main 클래스를 컴파일합니다."),
    (r"Assembles test classes\.", "test 클래스를 컴파일합니다."),
    (r"Assembles a jar archive containing the classes of the '([^']+)' feature\.", r"'\1' 기능의 클래스를 담은 jar 를 만듭니다."),
    (r"Assembles a jar archive containing the main classes\.", "main 클래스를 담은 jar 를 만듭니다."),
    (r"Assembles a jar archive containing the main javadoc\.", "main Javadoc 을 담은 jar 를 만듭니다."),
    (r"Assembles a jar archive containing the main sources\.", "main 소스를 담은 jar 를 만듭니다."),
    (r"Assembles an executable jar archive containing the main classes and their dependencies\.", "main 클래스와 의존성을 모두 담은 실행 가능한 jar 를 만듭니다."),
    (r"Assembles an executable war archive containing webapp content, and the main classes and their dependencies\.", "웹앱 콘텐츠·main 클래스·의존성을 모두 담은 실행 가능한 war 를 만듭니다."),
    (r"Generates a war archive with all the compiled classes, the web-app content and the libraries\.", "컴파일된 클래스·웹앱 콘텐츠·라이브러리를 담은 war 를 만듭니다."),
    (r"Builds an OCI image of the application using the output of the bootJar task", "bootJar 결과물로 애플리케이션 OCI(컨테이너) 이미지를 만듭니다."),
    (r"Resolves the name of the application's main class for the (\w+) task\.", r"\1 작업에 쓸 애플리케이션 main 클래스 이름을 찾습니다."),
    (r"Runs this project as a Spring Boot application\.", "이 프로젝트를 Spring Boot 애플리케이션으로 실행합니다."),
    (r"Runs this project as a JVM application", "이 프로젝트를 JVM 애플리케이션으로 실행합니다."),
    (r"Generates Spring Boot build profile for local development", "로컬 개발용 Spring Boot 빌드 프로필을 만듭니다."),
    (r"Copies license files of bundled dependencies for the Fat JAR\.", "Fat JAR 에 포함된 의존성의 라이선스 파일을 복사합니다."),
    (r"Deletes the build directory\.", "build 디렉터리를 삭제합니다."),
    (r"Compiles main Java source\.", "main Java 소스를 컴파일합니다."),
    (r"Compiles test Java source\.", "test Java 소스를 컴파일합니다."),
    (r"Compiles main Kotlin source\.", "main Kotlin 소스를 컴파일합니다."),
    (r"Compiles test Kotlin source\.", "test Kotlin 소스를 컴파일합니다."),
    (r"Processes main resources\.", "main 리소스를 처리(복사)합니다."),
    (r"Processes test resources\.", "test 리소스를 처리(복사)합니다."),
    (r"Runs all checks\.", "모든 검사(테스트 포함)를 실행합니다."),
    (r"Runs the test suite\.", "테스트를 실행합니다."),
    (r"Runs the unit tests\.", "단위 테스트를 실행합니다."),
    (r"Generates Javadoc API documentation for the '([^']+)' feature\.", r"'\1' 기능의 Javadoc API 문서를 만듭니다."),
    (r"Generates Javadoc API documentation for the main source code\.", "main 소스의 Javadoc API 문서를 만듭니다."),
    (r"Displays a help message\.", "도움말을 표시합니다."),
    (r"Displays the detected java toolchains\.", "감지된 Java 툴체인을 표시합니다."),
    (r"Prints the Kotlin code for accessing the currently available project extensions\.", "현재 프로젝트 확장에 접근하는 Kotlin 코드를 출력합니다."),
    (r"Displays all buildscript dependencies declared in §P§\.", "§P§의 빌드 스크립트(buildscript) 의존성을 모두 표시합니다."),
    (r"Displays all dependencies declared in §P§\.", "§P§에 선언된 모든 의존성을 표시합니다."),
    (r"Displays the insight into a specific dependency in §P§\.", "§P§에서 특정 의존성이 어떻게 결정됐는지 자세히 표시합니다."),
    (r"Displays the dependency management declared in §P§\.", "§P§에 선언된 의존성 관리(BOM 등)를 표시합니다."),
    (r"Displays the components produced by §P§\.", "§P§에서 만드는 컴포넌트를 표시합니다."),
    (r"Displays the dependent components of components in §P§\.", "§P§의 컴포넌트에 의존하는 컴포넌트를 표시합니다."),
    (r"Displays the Artifact Transforms that can be executed in §P§\.", "§P§에서 실행할 수 있는 아티팩트 변환을 표시합니다."),
    (r"Displays the configuration model of §P§\.", "§P§의 구성 모델을 표시합니다."),
    (r"Displays the outgoing variants of §P§\.", "§P§에서 내보내는 변형(variant)을 표시합니다."),
    (r"Displays the sub-projects of §P§\.", "§P§의 하위 프로젝트를 표시합니다."),
    (r"Displays the properties of §P§\.", "§P§의 속성을 표시합니다."),
    (r"Displays the configurations that can be resolved in §P§\.", "§P§에서 의존성을 결정할 수 있는 구성(configuration)을 표시합니다."),
    (r"Displays the tasks runnable from §P§\.", "§P§에서 실행할 수 있는 작업을 표시합니다."),
    (r"Displays the tasks runnable from §P§ and its subprojects\.", "§P§와 하위 프로젝트에서 실행할 수 있는 작업을 표시합니다."),
    (r"Displays the tasks runnable from §P§ \(some of the displayed tasks may belong to subprojects\)\.", "§P§에서 실행할 수 있는 작업을 표시합니다(일부는 하위 프로젝트 작업)."),
    (r"Initializes a new Gradle build\.", "새 Gradle 빌드를 초기화합니다."),
    (r"Generates Gradle wrapper files\.", "Gradle 래퍼(gradlew) 파일을 만듭니다."),
    (r"Generates or updates the Gradle Daemon JVM criteria\.", "Gradle 데몬 JVM 조건을 만들거나 갱신합니다."),
    (r"Publishes all publications produced by this project\.", "이 프로젝트의 모든 퍼블리케이션을 배포합니다."),
    (r"Publishes all Maven publications produced by this project to the local Maven cache\.", "이 프로젝트의 모든 Maven 퍼블리케이션을 로컬 Maven 저장소(~/.m2)에 배포합니다."),
    (r"Publishes all Maven publications produced by this project to the (\S+) repository\.", r"이 프로젝트의 모든 Maven 퍼블리케이션을 \1 저장소에 배포합니다."),
    (r"Publishes Maven publication '([^']+)' to the local Maven repository\.", r"Maven 퍼블리케이션 '\1'을(를) 로컬 Maven 저장소(~/.m2)에 배포합니다."),
    (r"Publishes Maven publication '([^']+)' to Maven repository '([^']+)'\.", r"Maven 퍼블리케이션 '\1'을(를) Maven 저장소 '\2'에 배포합니다."),
    (r"Generates the Gradle metadata file for publication '([^']+)'\.", r"퍼블리케이션 '\1'의 Gradle 메타데이터 파일을 만듭니다."),
    (r"Generates the Maven POM file for publication '([^']+)'\.", r"퍼블리케이션 '\1'의 Maven POM 파일을 만듭니다."),
    (r"Signs all artifacts in the '([^']+)' publication\.", r"퍼블리케이션 '\1'의 모든 아티팩트에 서명합니다."),
]
KO = [(re.compile(p), r) for p, r in KO]


def to_korean(desc):
    if not desc:
        return desc
    deprecated = desc.endswith("[deprecated]")
    text = desc[: -len("[deprecated]")].strip() if deprecated else desc
    proj = None
    m = re.search(r"(?:root )?project '(:?[^']+)'", text)
    if m:
        proj = m.group(1).lstrip(":")
        text = text.replace(m.group(0), PROJ)
    for pat, rep in KO:
        if pat.fullmatch(text):
            out = pat.sub(rep, text)
            if proj is not None:
                out = out.replace(PROJ, "프로젝트 '" + proj + "'")
            return out + (" (사용 중단 예정)" if deprecated else "")
    return desc


lines = sys.stdin.read().splitlines()
root, group, rows = "", None, []
for i, line in enumerate(lines):
    m = re.match(r"Tasks runnable from (?:root )?project '([^']+)'", line)
    if m:
        root = m.group(1)
        continue
    nxt = lines[i + 1] if i + 1 < len(lines) else ""
    if line and re.fullmatch(r"-+", nxt) and not re.fullmatch(r"-+", line):
        group = re.sub(r"\s+tasks$", "", line.strip(), flags=re.I).lower()
        continue
    if group is None or not line.strip() or re.fullmatch(r"-+", line) or line.startswith((" ", "To see", "Pattern:")):
        continue
    name, _, desc = line.partition(" - ")
    name = name.strip()
    if not re.fullmatch(r"[A-Za-z0-9_.:-]+", name):
        continue
    module, _, task = name.rpartition(":")
    rows.append("\t".join([module, group, task, to_korean(desc.strip())]))
print("@root\t" + (root or "root"))
print("\n".join(rows))
PYPARSE
_gt_parse() {
    python3 -c "$_GT_PARSER_PY"
}

_gt_load() {
    local _force="${1:-false}" _sig _raw _pid _rc=0
    _sig=$(_gt_signature 2>/dev/null)
    [ -n "$_sig" ] && _sig="v${_GT_PARSER_VER}:$_sig"
    if [ "$_force" != true ] && [ -s "$_GT_CACHE" ] && [ -n "$_sig" ] && [ "$(cat "$_GT_SIG" 2>/dev/null)" = "$_sig" ]; then
        return 0
    fi
    _raw=$(mktemp)
    ("$_GT_GW" tasks --all --console=plain -q "${_GT_JAVA_ARGS[@]}" </dev/null >"$_raw" 2>&1) &
    _pid=$!
    if command -v show_spinner_status >/dev/null 2>&1; then
        show_spinner_status "$_pid" "   📋 Gradle 작업 목록 읽는 중... (빌드 설정이 바뀌었을 때만)"
    else
        echo "   📋 Gradle 작업 목록 읽는 중... (빌드 설정이 바뀌었을 때만)"
    fi
    wait "$_pid" || _rc=$?
    echo ""
    if [ "$_rc" -ne 0 ]; then
        echo "❌ Gradle 작업 목록을 읽지 못했습니다 (종료 코드: $_rc). 마지막 출력:"
        tail -n 15 "$_raw" | sed 's/^/   │ /'
        rm -f "$_raw"
        return 1
    fi
    if ! _gt_parse <"$_raw" >"$_GT_CACHE.tmp" || [ "$(wc -l <"$_GT_CACHE.tmp")" -le 1 ]; then
        echo "❌ Gradle 작업 목록을 해석하지 못했습니다."
        rm -f "$_raw" "$_GT_CACHE.tmp"
        return 1
    fi
    mv "$_GT_CACHE.tmp" "$_GT_CACHE"
    echo "$_sig" >"$_GT_SIG"
    rm -f "$_raw"
}

# 사용법: _gt_run <작업> [추가 인자...]   예) _gt_run :s2-core:test --tests com.example.FooTest
#   최근 실행 기록에는 "작업 인자..." 한 줄로 남기고, 다시 실행할 때 공백으로 나눠 그대로 넘깁니다
#   (작업 이름·테스트 클래스 이름에는 공백이 없으므로 안전).
_gt_run() {
    local _line="$*" _tmp
    # 최근 실행 기록 (중복 제거, 최신 5개)
    _tmp=$(mktemp)
    { echo "$_line"; grep -vxF "$_line" "$_GT_RECENT" 2>/dev/null; } | head -n 5 >"$_tmp"
    mv "$_tmp" "$_GT_RECENT"
    local _cmd=("$_GT_GW" "$@" "${_GT_JAVA_ARGS[@]}")
    echo "▶️ 실행 명령어: ${_cmd[*]}"
    echo "   ⏹ 중단: Ctrl+C"
    "${_cmd[@]}"
}


# Gradle 메뉴 탐색. 결과는 _GT_RESULT 로 돌려줍니다:
#   back        첫 단계에서 Esc → 1단계 그룹 메뉴로
#   ran         작업을 실행함(종료 코드 _GT_RC)
#   quick:<ID>  ⭐ 빠른 실행 항목을 고름 → 아래 실행 분기(ID)로 넘어감
# 작업 목록을 읽지 못해도(빌드 스크립트 오류 등) ⭐ 빠른 실행 항목은 쓸 수 있게 합니다.
_gt_menu() {
    _GT_RESULT="back"
    _GT_RC=0
    local _quick=("⭐ 실행 (bootRun)" "⭐ 빌드 (build)")
    $CENTRAL_PORTAL_EXISTS && _quick+=("⭐ Maven 중앙 저장소 배포 (publishAllPublicationsToCentralPortalRepository)")
    _quick+=("🧪 테스트 하나만 실행 (클래스 · 메서드 고르기)" "🧹 Gradle 데몬 상태 · 정리 (메모리 반환)")
    local _load_ok=true
    _gt_load || _load_ok=false
    _GT_ROOT=""
    _GT_MODULES=()
    if $_load_ok; then
        _GT_ROOT=$(awk -F'\t' '$1=="@root"{print $2; exit}' "$_GT_CACHE")
        # 모듈 목록: 루트 먼저, 나머지는 이름순
        mapfile -t _GT_MODULES < <(awk -F'\t' '$1!="@root" && $1!=""{print $1}' "$_GT_CACHE" | sort -u)
    fi
    [ -n "$_GT_ROOT" ] || _GT_ROOT=$(basename "$CWD")
    _GT_MULTI=false
    [ "${#_GT_MODULES[@]}" -gt 0 ] && _GT_MULTI=true

    _GT_LEVEL="module"
    $_GT_MULTI || _GT_LEVEL="group"
    _GT_MOD=""
    _GT_GROUP=""
    _GT_FZF=(fzf --height=60% --reverse --no-sort)
    local _items _prompt _header _sel _first _task _r _m _g _n
    while true; do
        case "$_GT_LEVEL" in
        module | group)
            _items=()
            # 첫 단계: ⭐ 빠른 실행 · 🕘 최근 실행 · (모듈 또는 그룹 목록) · 🔄 새로 읽기
            _first=false
            if [ "$_GT_LEVEL" = "module" ] || ! $_GT_MULTI; then _first=true; fi
            if $_first; then
                _items+=("${_quick[@]}")
                while IFS= read -r _r; do
                    [ -n "$_r" ] && _items+=("🕘 최근  $_r")
                done 2>/dev/null <"$_GT_RECENT"   # 2>/dev/null 을 앞에 둬야 파일이 없을 때(처음 쓰는 프로젝트)의 오류도 숨겨짐
            fi
            if ! $_load_ok; then
                _items+=("⚠️  작업 목록을 읽지 못했습니다 (위 오류 확인 후 🔄 다시 읽기)")
            elif [ "$_GT_LEVEL" = "module" ]; then
                _items+=("📦 ${_GT_ROOT} (루트 · 전체 모듈)")
                for _m in "${_GT_MODULES[@]}"; do _items+=("📦 $_m"); done
            else
                while IFS=$'\t' read -r _g _n; do
                    _items+=("📂 $_g ($_n)")
                done < <(awk -F'\t' -v m="$_GT_MOD" '$1!="@root" && $1==m{c[$2]++; if(!($2 in o)){o[$2]=++n; g[n]=$2}} END{for(i=1;i<=n;i++) print g[i] "\t" c[g[i]]}' "$_GT_CACHE")
            fi
            if $_first; then
                _items+=("🔄 작업 목록 새로 읽기")
                _prompt="🐘 Gradle (${_GT_ROOT}) > "
                _header="Esc: 메뉴로 · ⭐ 빠른 실행 / 📦 모듈 · 📂 그룹 › 🔧 작업 (루트에서 고른 작업은 모든 모듈에서 실행)"
            elif [ -n "$_GT_MOD" ]; then
                _prompt="📂 그룹 선택 (${_GT_MOD}) > "
                _header="Esc: 모듈 선택으로"
            else
                _prompt="📂 그룹 선택 (${_GT_ROOT} · 전체 모듈) > "
                _header="Esc: 모듈 선택으로"
            fi
            _sel=$(printf '%s\n' "${_items[@]}" | "${_GT_FZF[@]}" --prompt="$_prompt" --header="$_header")
            if [ -z "$_sel" ]; then
                if ! $_first; then
                    _GT_LEVEL="module"
                    continue
                fi
                _GT_RESULT="back"
                return 0
            fi
            case "$_sel" in
            "⭐ 실행 (bootRun)")
                _GT_RESULT="quick:gradle_bootrun"
                return 0
                ;;
            "⭐ 빌드 (build)")
                _GT_RESULT="quick:gradle_build"
                return 0
                ;;
            "⭐ Maven 중앙 저장소 배포"*)
                _GT_RESULT="quick:gradle_publish_central"
                return 0
                ;;
            "🧪 테스트 하나만 실행"*)
                _GT_RESULT="quick:gradle_test_one"
                return 0
                ;;
            "🧹 Gradle 데몬"*)
                _GT_RESULT="quick:gradle_daemon"
                return 0
                ;;
            "🕘 최근  "*)
                local _args
                read -r -a _args <<<"${_sel#🕘 최근  }"
                _gt_run "${_args[@]}"
                _GT_RC=$?
                _GT_RESULT="ran"
                return 0
                ;;
            "🔄 작업 목록 새로 읽기")
                if _gt_load true; then
                    _load_ok=true
                    _GT_ROOT=$(awk -F'\t' '$1=="@root"{print $2; exit}' "$_GT_CACHE")
                    mapfile -t _GT_MODULES < <(awk -F'\t' '$1!="@root" && $1!=""{print $1}' "$_GT_CACHE" | sort -u)
                    _GT_MULTI=false
                    [ "${#_GT_MODULES[@]}" -gt 0 ] && _GT_MULTI=true
                    _GT_LEVEL="module"
                    $_GT_MULTI || _GT_LEVEL="group"
                fi
                ;;
            "📦 "*)
                if [ "$_sel" = "📦 ${_GT_ROOT} (루트 · 전체 모듈)" ]; then _GT_MOD=""; else _GT_MOD="${_sel#📦 }"; fi
                _GT_LEVEL="group"
                ;;
            "📂 "*)
                _GT_GROUP="${_sel#📂 }"
                _GT_GROUP="${_GT_GROUP% (*}"
                _GT_LEVEL="task"
                ;;
            esac
            ;;
        task)
            _sel=$(awk -F'\t' -v m="$_GT_MOD" -v g="$_GT_GROUP" '$1!="@root" && $1==m && $2==g{printf "🔧 %-48s  %s\n", $3, $4}' "$_GT_CACHE" |
                "${_GT_FZF[@]}" --prompt="🔧 작업 선택 (${_GT_MOD:-${_GT_ROOT}} › ${_GT_GROUP}) > " --header="Esc: 그룹 선택으로")
            if [ -z "$_sel" ]; then
                _GT_LEVEL="group"
                continue
            fi
            _task=$(echo "${_sel#🔧 }" | awk '{print $1}')
            if [ -n "$_GT_MOD" ]; then
                _gt_run ":${_GT_MOD}:${_task}"
            else
                _gt_run "$_task"
            fi
            _GT_RC=$?
            _GT_RESULT="ran"
            return 0
            ;;
        esac
    done
}



# ==============================================================================
# 2-1. .vscode/launch.json 기반 bootRun 설정 감지 및 스캐폴딩 헬퍼
# ==============================================================================

# JSONC 파싱 및 Java launch 구성 탐색 함수
# 성공 시: TARGET_LAUNCH_NAME, TARGET_MAIN_CLASS, TARGET_MOD, TARGET_PROF, TARGET_VM_EXTRA 설정 후 0 반환
# 복수 구성 선택 중 사용자 취소(Esc) 시: 2 반환
# 파일 없거나 Java launch 구성 없을 시: 1 반환
parse_vscode_launch_for_bootrun() {
    local launch_file="$CWD/.vscode/launch.json"
    if [[ ! -f "$launch_file" ]]; then
        return 1
    fi

    local parsed_output
    parsed_output=$(python3 - "$launch_file" "$CWD" 2>/dev/null << 'PYEOF'
import json, os, re, sys

launch_file = sys.argv[1]
cwd = sys.argv[2]

def parse_jsonc(text):
    pattern = re.compile(r'(/\*.*?\*/|//[^\r\n]*)|("(?:\\.|[^"\\])*")', re.DOTALL)
    no_comments = pattern.sub(lambda m: '' if m.group(1) else m.group(2), text)
    clean_text = re.sub(r',\s*([\]}])', r'\1', no_comments)
    return json.loads(clean_text)

try:
    with open(launch_file, 'r', encoding='utf-8') as f:
        data = parse_jsonc(f.read())
except Exception:
    sys.exit(1)

configs = data.get('configurations', [])
if not isinstance(configs, list):
    sys.exit(1)

java_configs = []
for c in configs:
    if isinstance(c, dict) and c.get('type') == 'java' and c.get('request', 'launch') == 'launch':
        java_configs.append(c)

if not java_configs:
    sys.exit(1)

# rootProject.name 판별 (루트 프로젝트와 모듈명이 같으면 단일 모듈로 처리)
root_project_name = ''
for sf in [os.path.join(cwd, 'settings.gradle'), os.path.join(cwd, 'settings.gradle.kts')]:
    if os.path.isfile(sf):
        try:
            with open(sf, 'r', encoding='utf-8') as f:
                m = re.search(r"rootProject\.name\s*=\s*['\"]([^'\"]+)['\"]", f.read())
                if m:
                    root_project_name = m.group(1)
                    break
        except Exception:
            pass

results = []
for idx, c in enumerate(java_configs):
    name = c.get('name', f'Config {idx + 1}')
    main_class = c.get('mainClass', '')
    proj_name = c.get('projectName', '')
    vm_args = c.get('vmArgs', '')
    if isinstance(vm_args, list):
        vm_args = ' '.join(vm_args)
    args = c.get('args', '')
    if isinstance(args, list):
        args = ' '.join(args)

    # 1. 프로필 추출
    profile = ''
    m_prof = re.search(r'-Dspring\.profiles\.active=([^\s]+)', vm_args)
    if m_prof:
        profile = m_prof.group(1)
    else:
        m_args_prof = re.search(r'--spring\.profiles\.active=([^\s]+)', args)
        if m_args_prof:
            profile = m_args_prof.group(1)

    # 2. 추가 시스템 프로퍼티 (-D... 중 spring.profiles.active 제외)
    extra_vm_parts = []
    for token in vm_args.split():
        if token.startswith('-D') and not token.startswith('-Dspring.profiles.active='):
            extra_vm_parts.append(token)
    extra_vm = ' '.join(extra_vm_parts)

    # 3. 모듈명 결정: rootProject.name과 일치 시 단일 모듈(빈 문자열)
    mod = proj_name
    if mod and root_project_name and mod == root_project_name:
        mod = ''

    results.append({
        'name': name,
        'mainClass': main_class,
        'module': mod,
        'profile': profile,
        'extraVm': extra_vm
    })

print(json.dumps(results, ensure_ascii=False))
PYEOF
    )

    if [[ -z "$parsed_output" ]]; then
        return 1
    fi

    local count
    count=$(python3 -c "import json, sys; print(len(json.loads(sys.argv[1])))" "$parsed_output" 2>/dev/null || echo "0")
    if [[ "$count" -eq 0 ]]; then
        return 1
    fi

    local selected_idx=0
    if [[ "$count" -gt 1 ]]; then
        local config_menu=()
        while IFS=$'\t' read -r idx c_name c_prof c_mod; do
            local label="$c_name"
            [[ -n "$c_mod" ]] && label="$label [모듈: $c_mod]"
            [[ -n "$c_prof" ]] && label="$label [프로필: $c_prof]"
            config_menu+=("${idx}\t${label}")
        done < <(python3 -c "
import json, sys
data = json.loads(sys.argv[1])
for i, d in enumerate(data):
    print(f'{i}\t{d.get(\"name\", \"\")}\t{d.get(\"profile\", \"\")}\t{d.get(\"module\", \"\")}')
" "$parsed_output")

        local fzf_choice
        fzf_choice=$(printf '%s\n' "${config_menu[@]}" | fzf --with-nth=2 --prompt="🎯 실행할 launch.json 구성을 선택하세요 > " --height=40% --reverse)
        if [[ -z "$fzf_choice" ]]; then
            echo "❌ bootRun 구성 선택이 취소되었습니다."
            return 2
        fi
        selected_idx=$(echo "$fzf_choice" | cut -f1)
    fi

    eval "$(python3 - "$parsed_output" "$selected_idx" << 'PYEOF'
import json, sys, shlex
data = json.loads(sys.argv[1])
idx = int(sys.argv[2])
target = data[idx]
print(f"TARGET_LAUNCH_NAME={shlex.quote(target.get('name', ''))}")
print(f"TARGET_MAIN_CLASS={shlex.quote(target.get('mainClass', ''))}")
print(f"TARGET_MOD={shlex.quote(target.get('module', ''))}")
print(f"TARGET_PROF={shlex.quote(target.get('profile', ''))}")
print(f"TARGET_VM_EXTRA={shlex.quote(target.get('extraVm', ''))}")
PYEOF
    )"

    return 0
}

# .vscode/launch.json 미감지 시 스마트 기본값 추론 및 생성 함수
scaffold_launch_json_for_bootrun() {
    echo ""
    echo "💡 [.vscode/launch.json] 표준 디버그/실행 설정이 감지되지 않았습니다."
    echo "   Spring Boot 표준 실행 구성을 생성합니다."
    echo "──────────────────────────────────────────────────────────────────────────────"

    # 1. 메인 클래스 스마트 추론
    local default_main=""
    if [[ -f "$CWD/.vscode/launch.json" ]]; then
        default_main=$(python3 -c "
import json, re, sys
try:
    text = re.sub(r'//.*', '', open(sys.argv[1]).read())
    data = json.loads(text)
    for c in data.get('configurations', []):
        if c.get('mainClass'):
            print(c['mainClass']); break
except Exception:
    pass
" "$CWD/.vscode/launch.json" 2>/dev/null)
    fi
    if [[ -z "$default_main" ]] && [[ -d "$CWD/src/main/java" ]]; then
        local found_file
        found_file=$(grep -rl '@SpringBootApplication' "$CWD/src/main/java" 2>/dev/null | head -1)
        if [[ -n "$found_file" ]]; then
            local pkg cls
            pkg=$(grep -E '^\s*package\s+' "$found_file" | head -1 | sed -E 's/^\s*package\s+([^;]+);.*/\1/')
            cls=$(basename "$found_file" .java)
            if [[ -n "$pkg" && -n "$cls" ]]; then
                default_main="${pkg}.${cls}"
            fi
        fi
    fi

    # 2. 모듈/프로젝트명 스마트 추론
    local default_proj=""
    if [[ -f "$CWD/settings.gradle" ]]; then
        default_proj=$(grep -oE "rootProject\.name\s*=\s*['\"][^'\"]+['\"]" "$CWD/settings.gradle" 2>/dev/null | head -1 | sed -E "s/rootProject\.name\s*=\s*['\"]([^'\"]+)['\"]/\1/")
    elif [[ -f "$CWD/settings.gradle.kts" ]]; then
        default_proj=$(grep -oE "rootProject\.name\s*=\s*['\"][^'\"]+['\"]" "$CWD/settings.gradle.kts" 2>/dev/null | head -1 | sed -E "s/rootProject\.name\s*=\s*['\"]([^'\"]+)['\"]/\1/")
    fi
    [[ -z "$default_proj" ]] && default_proj="$(basename "$CWD")"

    # 3. 프로필 스마트 추론 (@profiles-*.yml 또는 application-*.yml 스캔)
    local default_prof=""
    local res_dir="$CWD/src/main/resources"
    if [[ -d "$res_dir" ]]; then
        local prof_candidates=()
        for pf in "$res_dir"/config/@profiles-*.yml "$res_dir"/config/@profiles-*.yaml; do
            if [[ -f "$pf" ]]; then
                local p_name
                p_name=$(basename "$pf" | sed -E 's/^@profiles-([^\.]+)\.ya?ml$/\1/')
                prof_candidates+=("$p_name")
            fi
        done
        if [[ ${#prof_candidates[@]} -eq 0 ]]; then
            for pf in "$res_dir"/application-*.yml "$res_dir"/application-*.yaml; do
                if [[ -f "$pf" ]]; then
                    local p_name
                    p_name=$(basename "$pf" | sed -E 's/^application-([^\.]+)\.ya?ml$/\1/')
                    prof_candidates+=("$p_name")
                fi
            done
        fi
        if [[ ${#prof_candidates[@]} -gt 0 ]]; then
            default_prof=$(IFS=','; echo "${prof_candidates[*]}")
        fi
    fi
    [[ -z "$default_prof" ]] && default_prof="local"

    # 사용자 1회성 입력 받기 (친절한 가이드 및 힌트 제공)
    echo ""
    echo "📌 1. 메인 클래스 (Spring Boot 진입 클래스 FQCN)"
    echo "   • 자동 분석 결과: ${default_main:-(감지 실패 - 직접 입력 필요)}"
    prompt_text IN_MAIN "   👉 메인 클래스" "$default_main"
    IN_MAIN=${IN_MAIN:-$default_main}

    echo ""
    echo "📌 2. 모듈 / 프로젝트명 (Gradle 실행 대상 모듈)"
    echo "   • 싱글 프로젝트: 기본값 그대로 Enter / 멀티모듈: 서브모듈명(예: api, core) 입력"
    prompt_text IN_PROJ "   👉 모듈/프로젝트명" "$default_proj"
    IN_PROJ=${IN_PROJ:-$default_proj}

    echo ""
    echo "📌 3. 실행 프로필 (Spring Boot Active Profiles / 쉼표 구분)"
    echo "   • 자동 분석 결과: ${default_prof:-(없음)}"
    prompt_text IN_PROF "   👉 실행 프로필" "$default_prof"
    IN_PROF=${IN_PROF:-$default_prof}
    echo "──────────────────────────────────────────────────────────────────────────────"

    if [[ -z "$IN_MAIN" ]]; then
        echo "❌ 메인 클래스가 지정되지 않아 launch.json 생성을 중단합니다."
        return 1
    fi

    local app_name="${IN_MAIN##*.}"
    [[ -z "$app_name" ]] && app_name="$IN_PROJ"

    local vm_args="-Dfile.encoding=UTF-8"
    [[ -n "$IN_PROF" ]] && vm_args="-Dfile.encoding=UTF-8 -Dspring.profiles.active=${IN_PROF}"

    mkdir -p "$CWD/.vscode"
    python3 - "$CWD/.vscode/launch.json" "$app_name" "$IN_MAIN" "$IN_PROJ" "$vm_args" << 'PYEOF'
import json, sys

path, name, main_class, proj_name, vm_args = sys.argv[1:6]
config = {
    'version': '0.2.0',
    'configurations': [
        {
            'type': 'java',
            'name': name,
            'request': 'launch',
            'mainClass': main_class,
            'projectName': proj_name,
            'vmArgs': vm_args
        }
    ]
}
with open(path, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
    f.write('\n')
PYEOF

    echo "✅ .vscode/launch.json 생성이 완료되었습니다!"
    echo "   (이제 Neovim, VSCode, fzf 어디서든 동일한 설정으로 실행됩니다)"
    echo ""

    TARGET_LAUNCH_NAME="$app_name"
    TARGET_MAIN_CLASS="$IN_MAIN"
    TARGET_MOD=""
    if [[ -n "$IN_PROJ" && "$IN_PROJ" != "$default_proj" ]]; then
        TARGET_MOD="$IN_PROJ"
    fi
    TARGET_PROF="$IN_PROF"
    TARGET_VM_EXTRA="-Dfile.encoding=UTF-8"

    return 0
}

# ── 1단계 메뉴 등록 · 2단계 선택 (Gradle 프로젝트에서만) ─────────────────────────────
# 2단계는 _gt_menu(⭐ 빠른 실행 · 🕘 최근 · 📦 모듈 › 📂 그룹 › 🔧 작업). 작업을 바로 실행했으면 그 종료 코드로 끝내고,
# ⭐ 빠른 실행 항목을 골랐으면 그 항목 ID 의 실행 함수(cp_run_<ID>)로 넘어갑니다.
# 1단계 키워드는 실제로 보이는 빠른 실행 항목에 맞춤(배포는 Maven 중앙 저장소 배포 설정이 있을 때만 — _gt_menu 와 같은 조건)
_GRADLE_KW=("실행" "빌드")
$CENTRAL_PORTAL_EXISTS && _GRADLE_KW+=("배포")
_GRADLE_KW+=("테스트" "데몬 정리" "작업(Tasks)")
$GRADLEW_EXISTS && cp_register_group gradle "🐘 Gradle ▸ $(_cp_join_kw "${_GRADLE_KW[@]}")"
cp_group_gradle() {
    _gt_menu
    case "$_GT_RESULT" in
    ran) exit "$_GT_RC" ;;
    quick:*) CHOICE_ID="${_GT_RESULT#quick:}" ;;
    esac
}

# ── [Gradle] 실행 (bootRun) ──────────────────────────────────────────────────
cp_run_gradle_bootrun() {
    TARGET_LAUNCH_NAME=""
    TARGET_MAIN_CLASS=""
    TARGET_MOD=""
    TARGET_PROF=""
    TARGET_VM_EXTRA=""

    # 1. .vscode/launch.json 파싱 시도 (단일 원천)
    parse_vscode_launch_for_bootrun
    _parse_code=$?

    if [[ "$_parse_code" -eq 2 ]]; then
        exit 0
    elif [[ "$_parse_code" -ne 0 ]]; then
        scaffold_launch_json_for_bootrun || exit 1
        parse_vscode_launch_for_bootrun || exit 1
    fi

    # 2. 감지/생성된 launch.json 정보 표시 및 실행 확인
    echo "📋 [.vscode/launch.json] 실행 구성: ${TARGET_LAUNCH_NAME}"
    [[ -n "$TARGET_MAIN_CLASS" ]] && echo "   메인 클래스 : ${TARGET_MAIN_CLASS}"
    echo "   모듈 / 대상 : ${TARGET_MOD:-(루트 프로젝트)}"
    echo "   실행 프로필 : ${TARGET_PROF:-(없음)}"
    [[ -n "$TARGET_VM_EXTRA" ]] && echo "   추가 VM 인자: ${TARGET_VM_EXTRA}"
    echo ""
    prompt_confirm "▶️  이 설정으로 바로 실행하시겠습니까?" "Y" && REUSE="y" || REUSE="n"

    if [[ "${REUSE,,}" != "y" ]]; then
        prompt_text IN_MOD "📦 모듈명 (루트면 엔터)" "$TARGET_MOD"
        TARGET_MOD=${IN_MOD:-$TARGET_MOD}

        prompt_text IN_PROF "🔑 프로필" "$TARGET_PROF"
        TARGET_PROF=${IN_PROF:-$TARGET_PROF}
    fi

    # 3. 안전하게 배열로 인수 조립 (eval 대신 직접 실행)
    CMD_ARGS=()
    CMD_ARGS+=("$GW_NAME")

    if [[ -n "$TARGET_MOD" ]]; then
        CMD_ARGS+=(":$TARGET_MOD:bootRun")
    else
        CMD_ARGS+=("bootRun")
    fi

    if [[ -n "$TARGET_PROF" ]]; then
        CMD_ARGS+=("--args=--spring.profiles.active=$TARGET_PROF")
    fi

    # launch.json 의 vmArgs(-D...)는 "실행되는 앱 JVM" 에 넣어야 합니다.
    # ⚠️ "./gradlew bootRun -Dkey=val" 처럼 Gradle 명령 인자로 주면 Gradle 자체 JVM 에만 적용되고
    #    bootRun 이 띄우는 앱에는 전달되지 않습니다(build.gradle 이 직접 넘기지 않는 한).
    #    그래서 작은 init 스크립트로 bootRun 태스크의 jvmArgs 에만 추가합니다(Neovim/VSCode 디버그 실행과 동일).
    BOOTRUN_ENV=()
    if [[ -n "$TARGET_VM_EXTRA" ]]; then
        BOOTRUN_INIT="$STATE_DIR/bootrun-jvm-args.init.gradle"
        cat > "$BOOTRUN_INIT" <<'GRADLE_INIT'
// command-palette 가 생성: DT2_BOOTRUN_JVM_ARGS 환경 변수의 JVM 인자를 bootRun 앱 JVM 에 추가
allprojects {
    tasks.matching { it.name == 'bootRun' }.configureEach { task ->
        def extra = System.getenv('DT2_BOOTRUN_JVM_ARGS')
        if (extra) {
            task.jvmArgs(extra.trim().split(/\s+/) as List)
        }
    }
}
GRADLE_INIT
        CMD_ARGS+=("--init-script" "$BOOTRUN_INIT")
        BOOTRUN_ENV=(env "DT2_BOOTRUN_JVM_ARGS=$TARGET_VM_EXTRA")
    fi

    # 기본 백그라운드 컴파일 감시(-t), 병렬 빌드, 빌드 캐시 활성화
    CMD_ARGS+=("-t" "--parallel" "--build-cache")

    echo ""
    prompt_confirm "📁 로그를 파일로 저장하시겠습니까?" "N" && SAVE_LOG="y" || SAVE_LOG="n"

    # bootRun 실행 전 포트 충돌 사전 확인
    check_and_resolve_port_conflict "$TARGET_MOD"

    echo "▶️ 실행 명령어: ${CMD_ARGS[*]}"
    echo "   ⏹ 종료: Ctrl+C (실행 중인 앱과 Gradle 변경 감시가 함께 종료됩니다)"
    if [[ "${SAVE_LOG,,}" == "y" ]]; then
        LOG_DIR="$CWD/logs"
        mkdir -p "$LOG_DIR"
        LOG_FILE="$LOG_DIR/gradle-$(date +%Y%m%d-%H%M%S).log"
        echo "📁 로그 저장 경로: $LOG_FILE"
        "${BOOTRUN_ENV[@]}" "${CMD_ARGS[@]}" 2>&1 | tee "$LOG_FILE"
    else
        "${BOOTRUN_ENV[@]}" "${CMD_ARGS[@]}"
    fi
}

# ── [Gradle] 빌드 (build) ────────────────────────────────────────────────────
cp_run_gradle_build() {
    PREV_CLEAN=$(get_state "gradle_build" "clean")
    PREV_EX=$(get_state "gradle_build" "exclude")
    PREV_PARALLEL=$(get_state "gradle_build" "parallel")
    PREV_CACHE=$(get_state "gradle_build" "build_cache")
    PREV_REFRESH=$(get_state "gradle_build" "refresh")
    PREV_DEBUG=$(get_state "gradle_build" "debug")
    PREV_JAVA_HOME=$(get_state "gradle_build" "java_home")

    PREV_CLEAN=${PREV_CLEAN:-"N"}
    PREV_EX=${PREV_EX:-""}
    PREV_PARALLEL=${PREV_PARALLEL:-"Y"}
    PREV_CACHE=${PREV_CACHE:-"Y"}
    PREV_REFRESH=${PREV_REFRESH:-"N"}
    PREV_DEBUG=${PREV_DEBUG:-""}
    PREV_JAVA_HOME=${PREV_JAVA_HOME:-""}

    echo "📋 이전 빌드 설정:"
    echo "   클린 여부  : $PREV_CLEAN"
    echo "   태스크 제외: ${PREV_EX:-(없음)}"
    echo "   병렬 빌드  : $PREV_PARALLEL"
    echo "   빌드 캐시  : $PREV_CACHE"
    echo "   의존성 갱신: $PREV_REFRESH"
    echo "   디버그 옵션: ${PREV_DEBUG:-(없음)}"
    echo "   Java Home  : ${PREV_JAVA_HOME:-(기본값)}"
    echo ""
    prompt_confirm "▶️  이 설정으로 바로 빌드하시겠습니까?" "Y" && REUSE="y" || REUSE="n"

    if [[ "${REUSE,,}" != "y" ]]; then
        # Y/N 옵션은 지난번 값을 기본값으로 묻습니다(공용 prompt_confirm — 기본값 초록색 표시)
        prompt_confirm "🧹 클린 여부" "${PREV_CLEAN^^}" && CLEAN="Y" || CLEAN="N"

        prompt_text EXCLUDE "🚫 태스크 제외 (test 등 제외할 태스크 명, 공백/콤마 구분)" "$PREV_EX"
        EXCLUDE=${EXCLUDE:-$PREV_EX}

        prompt_confirm "🚀 병렬 빌드" "${PREV_PARALLEL^^}" && PARALLEL="Y" || PARALLEL="N"

        prompt_confirm "📦 빌드 캐시" "${PREV_CACHE^^}" && CACHE="Y" || CACHE="N"

        prompt_confirm "🔄 의존성 갱신" "${PREV_REFRESH^^}" && REFRESH="Y" || REFRESH="N"

        prompt_text DEBUG_OPT "🐛 디버깅 옵션 (공백/info/debug)" "$PREV_DEBUG"
        DEBUG_OPT=${DEBUG_OPT:-$PREV_DEBUG}

        prompt_text JAVA_HOME_PATH "☕ Java Home 경로 (공백이면 기본값)" "$PREV_JAVA_HOME"
        JAVA_HOME_PATH=${JAVA_HOME_PATH:-$PREV_JAVA_HOME}

        save_state "gradle_build" "clean" "$CLEAN"
        save_state "gradle_build" "exclude" "$EXCLUDE"
        save_state "gradle_build" "parallel" "$PARALLEL"
        save_state "gradle_build" "build_cache" "$CACHE"
        save_state "gradle_build" "refresh" "$REFRESH"
        save_state "gradle_build" "debug" "$DEBUG_OPT"
        save_state "gradle_build" "java_home" "$JAVA_HOME_PATH"
    else
        CLEAN="$PREV_CLEAN"
        EXCLUDE="$PREV_EX"
        PARALLEL="$PREV_PARALLEL"
        CACHE="$PREV_CACHE"
        REFRESH="$PREV_REFRESH"
        DEBUG_OPT="$PREV_DEBUG"
        JAVA_HOME_PATH="$PREV_JAVA_HOME"
    fi

    CMD_ARGS=()
    CMD_ARGS+=("$GW_NAME")

    if [[ "${CLEAN,,}" == "y" ]]; then
        CMD_ARGS+=("clean")
    fi
    CMD_ARGS+=("build")

    # 태스크 제외 처리 (공백 또는 쉼표 기준 토큰 분할하여 각각 -x 추가)
    if [[ -n "$EXCLUDE" ]]; then
        IFS=' ,/' read -r -a exc_tasks <<<"$EXCLUDE"
        for task in "${exc_tasks[@]}"; do
            if [[ -n "$task" ]]; then
                CMD_ARGS+=("-x" "$task")
            fi
        done
    fi

    if [[ "${PARALLEL,,}" == "y" ]]; then
        CMD_ARGS+=("--parallel")
    fi
    if [[ "${CACHE,,}" == "y" ]]; then
        CMD_ARGS+=("--build-cache")
    fi
    if [[ "${REFRESH,,}" == "y" ]]; then
        CMD_ARGS+=("--refresh-dependencies")
    fi

    if [[ "${DEBUG_OPT,,}" == "info" ]]; then
        CMD_ARGS+=("--info" "--stacktrace")
    elif [[ "${DEBUG_OPT,,}" == "debug" ]]; then
        CMD_ARGS+=("--debug" "--stacktrace")
    fi

    if [[ -n "$JAVA_HOME_PATH" ]]; then
        CMD_ARGS+=("-Dorg.gradle.java.home=$JAVA_HOME_PATH")
    fi

    echo "▶️ 실행 명령어: ${CMD_ARGS[*]}"
    echo "   ⏹ 중단: Ctrl+C"
    "${CMD_ARGS[@]}"
}

# ── [Gradle] Maven 중앙 저장소 배포 ──────────────────────────────────────────
cp_run_gradle_publish_central() {
    # ── 0. 배포 필수 환경(GPG 서명키 + Central Portal 인증) 사전 검증 ────────
    # ~/.gradle/gradle.properties 에 signing.keyId 와 centralUsername 이 모두
    # 설정되어 있어야 Gradle 서명/배포 태스크가 정상 실행됩니다. 하나라도 없으면
    # Bitwarden 에서 가져와 자동 설정하도록 maven-central-setup.sh 를 호출합니다.
    _CP_GRADLE_PROPS="$HOME/.gradle/gradle.properties"
    _CP_HAS_SIGNING=false
    _CP_HAS_CENTRAL=false
    if [ -f "$_CP_GRADLE_PROPS" ]; then
        grep -qE '^\s*signing\.keyId\s*=' "$_CP_GRADLE_PROPS" 2>/dev/null && _CP_HAS_SIGNING=true
        grep -qE '^\s*centralUsername\s*=' "$_CP_GRADLE_PROPS" 2>/dev/null && _CP_HAS_CENTRAL=true
    fi

    if [ "$_CP_HAS_SIGNING" = "false" ] || [ "$_CP_HAS_CENTRAL" = "false" ]; then
        echo ""
        echo "⚠️  Maven Central 배포에 필요한 설정이 ~/.gradle/gradle.properties 에 없습니다."
        [ "$_CP_HAS_SIGNING" = "false" ] && echo "   ❌ GPG 서명 키 (signing.keyId / signing.password / signing.secretKeyRingFile)"
        [ "$_CP_HAS_CENTRAL" = "false" ] && echo "   ❌ Central Portal 인증 정보 (centralUsername / centralPassword)"
        echo ""
        prompt_confirm "❓ Bitwarden 에서 자동으로 설정하시겠습니까?" "N" && _CP_AUTO_SETUP="y" || _CP_AUTO_SETUP="n"

        if [ "$_CP_AUTO_SETUP" = "y" ]; then
            # common-setup.sh + maven-central-setup.sh 로드
            _CP_DT2="${DEVTOOLS2:-$(readlink -f "$_CP_SCRIPT_DIR/../..")}"   # 팔레트 위치 기준 (palette.d 파일 기준 경로가 아니라 팔레트 경로)
            if [ -f "$_CP_DT2/scripts/linux/setup-projects/_common/common-setup.sh" ]; then
                # shellcheck disable=SC1090
                source "$_CP_DT2/scripts/linux/setup-projects/_common/common-setup.sh"
            fi
            if ! command -v setup_maven_central_publishing &>/dev/null; then
                if [ -f "$_CP_DT2/scripts/linux/setup-projects/_common/maven-central-setup.sh" ]; then
                    # shellcheck disable=SC1090
                    source "$_CP_DT2/scripts/linux/setup-projects/_common/maven-central-setup.sh"
                fi
            fi
            if command -v setup_maven_central_publishing &>/dev/null; then
                setup_maven_central_publishing "$CWD" "--yes" || {
                    echo ""
                    echo "❌ 배포 환경 자동 설정에 실패했습니다. 배포를 중단합니다."
                    exit 1
                }
            else
                echo "❌ setup_maven_central_publishing 함수를 로드할 수 없습니다."
                echo "   $DEVTOOLS2/scripts/linux/setup-projects/_common/maven-central-setup.sh 파일을 확인해주세요."
                exit 1
            fi

            # 설정 후 재검증
            _CP_HAS_SIGNING=false
            _CP_HAS_CENTRAL=false
            if [ -f "$_CP_GRADLE_PROPS" ]; then
                grep -qE '^\s*signing\.keyId\s*=' "$_CP_GRADLE_PROPS" 2>/dev/null && _CP_HAS_SIGNING=true
                grep -qE '^\s*centralUsername\s*=' "$_CP_GRADLE_PROPS" 2>/dev/null && _CP_HAS_CENTRAL=true
            fi
            if [ "$_CP_HAS_SIGNING" = "false" ] || [ "$_CP_HAS_CENTRAL" = "false" ]; then
                echo ""
                echo "❌ 자동 설정 후에도 필수 설정이 완전하지 않습니다. 배포를 중단합니다."
                exit 1
            fi
            echo ""
            echo "✅ 배포 환경 설정이 완료되었습니다. 배포를 계속 진행합니다."
            echo ""
        else
            echo ""
            echo "ℹ️  배포 환경 설정을 건너뛰었습니다."
            echo "   수동으로 설정하려면 다음 명령어를 실행하세요:"
            echo '   source "$DEVTOOLS2/scripts/fzf/bw-lib"'
            echo '   source "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"'
            echo '   source "$DEVTOOLS2/scripts/linux/setup-projects/_common/maven-central-setup.sh"'
            echo '   bw_ensure_session && setup_maven_central_publishing "$PWD"'
            exit 0
        fi
    fi

    # ── 1. settings.gradle(.kts)에서 서브모듈/루트 이름 탐색 ────────────────────
    _CP_SETTINGS_FILE=""
    if [ -f "$CWD/settings.gradle.kts" ]; then
        _CP_SETTINGS_FILE="$CWD/settings.gradle.kts"
    elif [ -f "$CWD/settings.gradle" ]; then
        _CP_SETTINGS_FILE="$CWD/settings.gradle"
    fi

    _CP_ROOT_NAME=$(basename "$CWD")
    if [ -n "$_CP_SETTINGS_FILE" ]; then
        _CP_ROOT_NAME_FOUND=$(grep -oE "rootProject\.name[[:space:]]*=[[:space:]]*[\"'][^\"']+[\"']" "$_CP_SETTINGS_FILE" \
            | sed -E "s/.*[\"']([^\"']+)[\"'].*/\1/" | head -1)
        [ -n "$_CP_ROOT_NAME_FOUND" ] && _CP_ROOT_NAME="$_CP_ROOT_NAME_FOUND"
    fi

    # include(":a"), include(":a", ":b"), include ':a', ':a:b' 등 표기를 모두 포괄
    _CP_MODULES=()
    if [ -n "$_CP_SETTINGS_FILE" ]; then
        while IFS= read -r _mod; do
            [ -n "$_mod" ] && _CP_MODULES+=("$_mod")
        done < <(grep -oE "[\"']:[A-Za-z0-9_.:-]+[\"']" "$_CP_SETTINGS_FILE" | tr -d "\"'" | sed 's/^://' | sort -u)
    fi

    # ── 2. 배포할 패키지(모듈) 선택 ───────────────────────────────────────────
    _CP_TARGET_MODULE=""
    if [ "${#_CP_MODULES[@]}" -eq 0 ]; then
        echo "ℹ️  서브모듈이 감지되지 않아 루트 프로젝트(${_CP_ROOT_NAME}) 전체를 배포 대상으로 진행합니다."
    else
        _CP_PKG_OPTIONS=("전체 (루트 프로젝트: ${_CP_ROOT_NAME})")
        _CP_PKG_OPTIONS+=("${_CP_MODULES[@]}")
        _CP_PKG_CHOICE=$(printf "%s\n" "${_CP_PKG_OPTIONS[@]}" | fzf --prompt="📦 배포할 패키지 선택 > " --height=40% --reverse)
        if [ -z "$_CP_PKG_CHOICE" ]; then
            exit 0
        fi
        if [[ "$_CP_PKG_CHOICE" != "전체"* ]]; then
            _CP_TARGET_MODULE="$_CP_PKG_CHOICE"
        fi
    fi
    # 이후 요약/완료 메시지에서 반복 사용할 표시용 문자열
    _CP_DISPLAY_TARGET="${_CP_TARGET_MODULE:-전체 (${_CP_ROOT_NAME})}"

    # ── 3. group 감지 + Maven Central에 마지막으로 배포된 버전 조회 ────────────
    # 중복 배포는 Maven Central 자체가 거부해주니 별 문제가 아니지만, "존재하지
    # 않는 엉뚱한 버전"(예: 최종 1.10인데 0.10이나 10.10으로 오타)은 그대로
    # 통과해서 영구히 남는 게 훨씬 위험합니다. 그래서 실제 마지막 배포 버전을
    # 미리 보여줘서 입력할 값과 비교할 수 있게 합니다.
    _CP_GROUP=$(detect_gradle_property "$CWD" "group")
    # 중첩 모듈 경로(:a:b)를 골랐으면 마지막 세그먼트를 아티팩트ID로 간주(관례, 커스텀 설정 시 다를 수 있음)
    _CP_ARTIFACT_ID="${_CP_TARGET_MODULE:-$_CP_ROOT_NAME}"
    _CP_ARTIFACT_ID="${_CP_ARTIFACT_ID##*:}"

    # search.maven.org의 solrsearch API는 Central Publisher Portal로 새로 배포되는
    # 그룹(예: io.github.* 네임스페이스)을 색인하지 않는 경우가 있어(실제로 존재하는
    # 배포 이력도 0건으로 나옴), 대신 실제 CDN인 repo1.maven.org의 maven-metadata.xml을
    # 직접 조회합니다 — 이게 진짜 배포 여부를 반영하는 소스입니다.
    _CP_LATEST_PUBLISHED=""
    if [ -n "$_CP_GROUP" ] && command -v curl &>/dev/null; then
        echo "⏳ Maven Central에서 마지막 배포 버전 확인 중... (${_CP_GROUP}:${_CP_ARTIFACT_ID})"
        _CP_GROUP_PATH="${_CP_GROUP//./\/}"
        _CP_METADATA_XML=$(curl -s -f -m 8 "https://repo1.maven.org/maven2/${_CP_GROUP_PATH}/${_CP_ARTIFACT_ID}/maven-metadata.xml" 2>/dev/null)
        _CP_LATEST_PUBLISHED=$(printf "%s" "$_CP_METADATA_XML" | python3 -c "import sys, xml.etree.ElementTree as ET
try:
    versioning = ET.fromstring(sys.stdin.read()).find('versioning')
    print(versioning.findtext('release') or versioning.findtext('latest') or '')
except Exception:
    print('')" 2>/dev/null)
        if [ -n "$_CP_LATEST_PUBLISHED" ]; then
            echo "ℹ️  Maven Central에 마지막으로 배포된 버전: $_CP_LATEST_PUBLISHED"
        else
            echo "ℹ️  Maven Central 배포 이력을 찾지 못했습니다 (최초 배포이거나 group/artifact 추정이 다를 수 있음)."
        fi
    else
        echo "⚠️  group 정보를 찾지 못했거나 curl이 없어 Maven Central 배포 이력 조회를 건너뜁니다."
    fi

    # ── 4. 배포 버전 입력 (프로젝트에 설정된 값을 기본값으로 제안) ─────────────
    # 입력 프롬프트의 기본값으로 보여줍니다(그냥 Enter만 치면 이 값 그대로 사용).
    _CP_DETECTED_VERSION=$(detect_gradle_property "$CWD" "version")

    PREV_CP_VERSION=$(get_state "central_portal" "version")
    _CP_VERSION_DEFAULT="${_CP_DETECTED_VERSION:-$PREV_CP_VERSION}"
    if [ -n "$_CP_DETECTED_VERSION" ]; then
        echo "ℹ️  프로젝트에 설정된 현재 버전: $_CP_DETECTED_VERSION (gradle.properties/build.gradle에서 감지)"
    fi

    prompt_text CP_VERSION "🏷️  배포할 버전 입력 (예: 1.2.3)" "$_CP_VERSION_DEFAULT"
    CP_VERSION=${CP_VERSION:-$_CP_VERSION_DEFAULT}
    if [ -z "$CP_VERSION" ]; then
        echo "❌ 버전이 입력되지 않았습니다. 취소합니다."
        exit 1
    fi
    save_state "central_portal" "version" "$CP_VERSION"

    if command -v git &>/dev/null && [ -d "$CWD/.git" ]; then
        _CP_GIT_DIRTY=$(git -C "$CWD" status --porcelain 2>/dev/null)
        if [ -n "$_CP_GIT_DIRTY" ]; then
            echo "⚠️  커밋되지 않은 변경 사항이 있습니다. 이 상태로 배포하면 나중에 정확히 어떤 코드가 배포됐는지 추적하기 어렵습니다."
        fi
    fi

    # ── 5. 최종 확인 (대소문자 구분 없이 y, 기본값 N) ─────────────────────────
    echo ""
    echo "📋 배포 정보 확인:"
    echo "   패키지 : $_CP_DISPLAY_TARGET"
    echo "   버전   : $CP_VERSION"
    if [ -n "$_CP_LATEST_PUBLISHED" ]; then
        echo "   (Maven Central 마지막 배포 버전: $_CP_LATEST_PUBLISHED — 방금 입력한 버전과 비교해보세요)"
    fi
    echo ""
    echo "⚠️  Maven Central은 한 번 배포하면 취소·수정·삭제가 불가능합니다(불변 저장소)."
    prompt_confirm "🚀 정말 이 설정으로 배포하시겠습니까?" "N" && CP_CONFIRM="y" || CP_CONFIRM="n"
    if [ "$CP_CONFIRM" != "y" ]; then
        echo "❌ 배포를 취소했습니다."
        exit 0
    fi

    # ── 6. 실행 ────────────────────────────────────────────────────────────
    # -Pversion=... : build.gradle(.kts)이 project.version을 이 프로퍼티로부터
    # 읽도록 구성돼 있어야 실제로 적용됩니다(흔한 관례지만 프로젝트마다 다를 수
    # 있으니, 배포 후 실제 게시된 버전이 의도한 값인지 한 번 확인해주세요).
    CMD_ARGS=()
    CMD_ARGS+=("$GW_NAME")
    CMD_ARGS+=("clean")
    if [ -n "$_CP_TARGET_MODULE" ]; then
        CMD_ARGS+=(":${_CP_TARGET_MODULE}:publishAllPublicationsToCentralPortalRepository")
    else
        CMD_ARGS+=("publishAllPublicationsToCentralPortalRepository")
    fi
    CMD_ARGS+=("-Pversion=${CP_VERSION}" "-x" "test" "--build-cache")

    echo "▶️ 실행 명령어: ${CMD_ARGS[*]}"
    echo "   ⏹ 중단: Ctrl+C (배포 도중 중단하면 Central Portal 에 일부만 올라갈 수 있으니 확인하세요)"
    if "${CMD_ARGS[@]}"; then
        echo ""
        echo "✅ Maven 중앙 저장소 배포 완료! (패키지: $_CP_DISPLAY_TARGET, 버전: $CP_VERSION)"
    else
        _CP_RC=$?
        echo ""
        echo "❌ Maven 중앙 저장소 배포 실패 (종료 코드: $_CP_RC)"
        echo "   위 Gradle 출력에서 'BUILD FAILED' 아래 원인(Caused by: 등)을 확인해주세요."
        echo "   원인이 더 자세히 필요하면 --stacktrace 를 붙여 다시 실행해보세요:"
        echo "   ${CMD_ARGS[*]} --stacktrace"
    fi
}

# ── [Gradle] 테스트 하나만 실행 (클래스 · 메서드) ───────────────────────────────
# 전체 test 는 오래 걸려, 고치는 중인 테스트 하나만 돌릴 때 씁니다(VS Code 테스트 탐색기의 ▶ 와 같은 용도).
#   ● src/<test 소스셋>/(java|kotlin|groovy) 아래에서 이름이 Test·Tests·IT·Spec 으로 끝나는 파일을 클래스로 봅니다.
#     소스셋 이름이 곧 작업 이름입니다(test → test, integrationTest → integrationTest).
#   ● 모듈: 파일 위치(core/src/test → :core:test, 루트 src/test → :test)로 정하고, 폴더 이름과 모듈 이름이 다르면
#     Gradle 작업 목록(캐시)의 모듈 중 마지막 이름이 같은 것으로 맞춥니다. 루트도 ":test" 로 넘겨 그 모듈만 실행합니다
#     (이름만 넘기면 모든 모듈에서 실행되고, 해당 테스트가 없는 모듈은 "No tests found" 로 실패).
#   ● 메서드: 비우면 클래스 전체. * 사용 가능, 공백(Kotlin 백틱 이름)은 * 로 바꿔 넘깁니다.
cp_run_gradle_test_one() {
    echo "🔍 테스트 클래스 찾는 중..."
    _TO_LIST=$(python3 - "$CWD" "$_GT_CACHE" <<'PYTEST'
import os, re, sys
root, cache = sys.argv[1], sys.argv[2]
mods = set()
try:
    for line in open(cache, encoding="utf-8"):
        m = line.split("\t", 1)[0]
        if m and m != "@root":
            mods.add(m)
except OSError:
    pass
skip = {"build", "out", "bin", "node_modules"}
src_re = re.compile(r"^(?:(.*)/)?src/([A-Za-z0-9_]*[Tt]est)/(?:java|kotlin|groovy)(?:/|$)")
cls_re = re.compile(r"(Test|Tests|IT|Spec)$")
pkg_re = re.compile(r"^\s*package\s+([\w.]+)", re.M)
rows = []
for d, dirs, files in os.walk(root):
    dirs[:] = sorted(x for x in dirs if x not in skip and not x.startswith("."))
    rel = os.path.relpath(d, root).replace(os.sep, "/")
    m = src_re.match(rel + "/" if rel != "." else "")
    if not m:
        continue
    moddir, sset = m.group(1) or "", m.group(2)
    for f in sorted(files):
        name, ext = os.path.splitext(f)
        if ext not in (".java", ".kt", ".groovy") or not cls_re.search(name):
            continue
        try:
            head = open(os.path.join(d, f), encoding="utf-8", errors="replace").read(8192)
        except OSError:
            continue
        pm = pkg_re.search(head)
        pkg = pm.group(1) if pm else ""
        mod = moddir.replace("/", ":")
        if mod and mods and mod not in mods:
            same = [x for x in mods if x.split(":")[-1] == moddir.split("/")[-1]]
            if len(same) == 1:
                mod = same[0]
        task = (":" + mod if mod else "") + ":" + sset
        fqn = (pkg + "." if pkg else "") + name
        label = "{}  ({})  · {}".format(name, pkg or "기본 패키지", (mod or "루트") + " › " + sset)
        rows.append("\t".join([task, fqn, label]))
print("\n".join(rows))
PYTEST
)
    if [ -z "$_TO_LIST" ]; then
        echo "ℹ️  src/test 아래에서 테스트 클래스(이름이 Test·Tests·IT·Spec 으로 끝나는 파일)를 찾지 못했습니다."
        exit 0
    fi
    _TO_SEL=$(printf '%s\n' "$_TO_LIST" | fzf --delimiter=$'\t' --with-nth=3 --prompt="🧪 실행할 테스트 클래스 > " --header="Esc: 취소 · 글자를 입력해 걸러 보세요 (클래스 · 패키지 · 모듈)" --height=60% --reverse) || true
    [ -z "$_TO_SEL" ] && exit 0
    IFS=$'\t' read -r _TO_TASK _TO_CLASS _ <<<"$_TO_SEL"
    prompt_text _TO_METHOD "🎯 메서드 이름 (비우면 클래스 전체, * 사용 가능 — 예: should*)"
    _TO_METHOD="${_TO_METHOD// /*}"
    _TO_FILTER="$_TO_CLASS"
    [ -n "$_TO_METHOD" ] && _TO_FILTER="${_TO_CLASS}.${_TO_METHOD}"
    echo ""
    _gt_run "$_TO_TASK" --tests "$_TO_FILTER"
    exit $?
}

# ── [Gradle] 데몬 상태 · 정리 ─────────────────────────────────────────────────
# Gradle·Kotlin 데몬은 다음 빌드를 빠르게 하려고 작업이 끝나도 JVM 을 띄워 둡니다(유휴 3시간 뒤 스스로 종료).
# 프로젝트·Gradle 버전·JDK 마다 따로 떠서 몇 GB 를 잡고 있을 수 있어, 상태를 보고 바로 중지할 수 있게 합니다.
#   ● gradlew --stop 은 그 Gradle 버전의 데몬만 멈추므로, 남은 데몬(다른 버전·Kotlin)은 TERM 으로 종료합니다.
#   ● 이 사용자의 프로세스만 대상으로 합니다. 중지해도 다음 빌드가 처음에 조금 느릴 뿐 문제는 없습니다.
cp_run_gradle_daemon() {
    # 출력: PID<TAB>종류<TAB>버전<TAB>MB
    _gd_list() {
        local _ps
        _ps=$(ps -u "$(id -u)" -o pid=,rss=,args= 2>/dev/null)   # awk 자신이 목록에 섞이지 않도록 먼저 받아 둠
        printf '%s\n' "$_ps" | awk '{
            kind = ""
            if ($0 ~ /org\.gradle\.launcher\.daemon\.bootstrap\.GradleDaemon/) kind = "Gradle 데몬"
            else if ($0 ~ /KotlinCompileDaemon/) kind = "Kotlin 컴파일 데몬"
            if (kind == "") next
            ver = "-"
            if (match($0, /gradle-[0-9]+(\.[0-9]+)+/)) ver = substr($0, RSTART + 7, RLENGTH - 7)
            else if (match($0, /kotlin-compiler-embeddable-[0-9]+(\.[0-9]+)+/)) ver = substr($0, RSTART + 27, RLENGTH - 27)
            printf "%s\t%s\t%s\t%d\n", $1, kind, ver, $2 / 1024
        }'
    }
    _gd_print() {
        awk -F'\t' '{ printf "  PID %-8s %-20s 버전 %-10s %6d MB\n", $1, $2, $3, $4; t += $4 } END { printf "  ─ 합계 %d MB\n", t }'
    }
    _GD_NOW=$(_gd_list)
    echo "🐘 실행 중인 Gradle · Kotlin 데몬"
    echo "─────────────────────────────────────────"
    if [ -z "$_GD_NOW" ]; then
        echo "  (실행 중인 데몬 없음)"
        echo "─────────────────────────────────────────"
        exit 0
    fi
    printf '%s\n' "$_GD_NOW" | _gd_print
    echo "─────────────────────────────────────────"
    echo "ℹ️  데몬은 다음 빌드를 빠르게 하려고 남아 있는 JVM 입니다. 중지해도 다음 빌드가 처음에 조금 느릴 뿐입니다."
    prompt_confirm "🧹 데몬을 모두 중지해 메모리를 돌려받을까요?" "Y" || exit 0
    echo ""
    echo "▶️ 실행 명령어: $_GT_GW --stop"
    "$_GT_GW" --stop || true
    # --stop 은 같은 Gradle 버전 데몬만 멈춤 → 남은 데몬(다른 버전·Kotlin)은 TERM, 최대 5초 기다림
    _GD_LEFT=$(_gd_list)
    if [ -n "$_GD_LEFT" ]; then
        echo "   남은 데몬(다른 Gradle 버전 · Kotlin)을 종료합니다."
        printf '%s\n' "$_GD_LEFT" | cut -f1 | xargs kill -TERM 2>/dev/null || true
        for _i in 1 2 3 4 5; do
            _GD_LEFT=$(_gd_list)
            [ -z "$_GD_LEFT" ] && break
            sleep 1
        done
    fi
    if [ -z "$_GD_LEFT" ]; then
        echo "✅ 데몬을 모두 중지했습니다."
    else
        echo "⚠️  아직 종료되지 않은 데몬이 있습니다 (🖥️ 시스템 ▸ 프로세스 종료 로 PID 를 직접 종료할 수 있습니다):"
        printf '%s\n' "$_GD_LEFT" | _gd_print
    fi
}
