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
        # 설치는 백그라운드로 돌리고 스피너로 진행 중임을 표시합니다.
        # (sudo 비밀번호 질문이 스피너에 가려지지 않도록 인증을 먼저 받아 둠)
        dt2_sudo_auth || true
        echo -n "   📦 필수 패키지 ($pkg) 자동 설치 중..."
        if command -v sudo >/dev/null 2>&1; then
            ( sudo apt-get update -qq >/dev/null 2>&1 || true
              sudo apt-get install -y "$pkg" >/dev/null 2>&1 || true ) &
            show_spinner $!; wait $! 2>/dev/null || true
        elif [ "$(id -u)" -eq 0 ]; then
            ( apt-get update -qq >/dev/null 2>&1 || true
              apt-get install -y "$pkg" >/dev/null 2>&1 || true ) &
            show_spinner $!; wait $! 2>/dev/null || true
        fi
        if command -v "$cmd" >/dev/null 2>&1; then
            echo " 완료"
        else
            echo " 실패"
        fi
    fi
}

# ── 버전 범위(track) 정책: tool-versions.toml 의 [track] 한 곳에서 모든 도구의 버전 정책을 관리 ──────
# 예전에는 도구마다 버전을 정하는 방법이 달랐습니다(설치 때 "최신/지정/개별" 선택, TOML 직접 수정,
# 코드에 메이저 고정(node-v24·gradle-9), 항상 최신). 이제 모든 도구가 같은 규칙을 따릅니다.
#   track 값:  "latest" → 항상 최신(메이저 포함) / "24" → 메이저 24 안에서 최신 /
#              "0.12" → 0.12.x 안에서 최신 / "0.74.1" 처럼 전체 버전 → 정확히 그 버전으로 고정
#   ● 설치 스크립트가 track 범위 안의 최신 버전을 찾고, 설치된 버전과 다르면 업데이트 여부를 묻습니다
#     (판단은 decide_app_action). 범위 밖에 더 새 버전이 있으면 안내만 합니다(메이저 업그레이드는 track 한 줄 변경).
#   ● 버전 목록 조회에 실패하면 TOML 버전 배열의 첫 항목(마지막 공유 기본 버전)으로 폴백합니다.

# [track] 섹션에서 도구의 track 값 읽기 (없으면 두 번째 인수 기본값)
get_track() {
    local key="$1" def="${2:-}" v
    v=$(_read_toml | awk -v k="$key" '
        /^\[/ { in_t = ($0 ~ /^\[track\]/) ; next }
        in_t && $0 ~ "^"k"[[:space:]]*=" { sub(/^[^=]*=[[:space:]]*/, ""); gsub(/"/, ""); sub(/[[:space:]]*#.*/, ""); print; exit }')
    echo "${v:-$def}"
}

# track 이 "정확한 버전 고정"인지 (숫자 구간 3개 이상, 또는 8u504-b01·17.0.18+8 처럼 숫자·점 외 문자 포함)
_track_is_exact() {
    local t="$1"
    [ "$t" != "latest" ] || return 1
    [[ "$t" =~ [^0-9.] ]] && return 0
    [ "$(tr -cd '.' <<<"$t" | wc -c)" -ge 2 ]
}

# 표준입력의 버전 목록(한 줄에 하나, 'v' 없음) 중 track 범위 안의 최신 버전
_pick_in_track() {
    local t="$1"
    if [ "$t" = "latest" ]; then
        sort -V | tail -n 1
    else
        grep -E "^${t//./\\.}(\.|$)" | sort -V | tail -n 1
    fi
}

# GitHub 릴리스 목록에서 정식 버전만 추출 (draft·prerelease 제외, 태그 접두어·'v' 제거, 숫자 버전만)
# 사용법: list_github_release_versions <owner/repo> [태그 접두어(예: cli-v)]
# GITHUB_TOKEN 이 있으면 인증 헤더를 붙여 API 호출 한도(시간당 60회)를 완화합니다.
list_github_release_versions() {
    local repo="$1" prefix="${2:-}"
    local _auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && _auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    curl -sf --max-time 15 "${_auth[@]}" "https://api.github.com/repos/${repo}/releases?per_page=100" 2>/dev/null \
        | python3 -c '
import json, re, sys
prefix = sys.argv[1]
try:
    rels = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in rels if isinstance(rels, list) else []:
    if r.get("draft") or r.get("prerelease"):
        continue
    tag = r.get("tag_name", "")
    if prefix and tag.startswith(prefix):
        tag = tag[len(prefix):]
    tag = tag[1:] if tag[:1] in "vV" else tag
    if re.fullmatch(r"\d+(\.\d+)+", tag):
        print(tag)
' "$prefix" 2>/dev/null || true
}

# Node.js LTS 버전 목록 ('v' 없음) — track "latest" 도 Current 가 아닌 최신 LTS 를 고르도록 LTS 만 출력
list_nodejs_lts_versions() {
    curl -sf --max-time 15 "https://nodejs.org/dist/index.json" 2>/dev/null \
        | python3 -c '
import json, sys
try:
    for v in json.load(sys.stdin):
        if v.get("lts"):
            print(v["version"].lstrip("v"))
except Exception:
    pass
' 2>/dev/null || true
}

# Gradle 정식 버전 목록 (스냅샷·나이틀리·RC·마일스톤·broken 제외)
list_gradle_versions() {
    curl -sf --max-time 15 "https://services.gradle.org/versions/all" 2>/dev/null \
        | python3 -c '
import json, sys
try:
    for v in json.load(sys.stdin):
        if v.get("snapshot") or v.get("nightly") or v.get("releaseNightly") or v.get("rcFor") or v.get("milestoneFor") or v.get("broken"):
            continue
        print(v["version"])
except Exception:
    pass
' 2>/dev/null || true
}

# Python 포터블 빌드(astral-sh/python-build-standalone) 최신 릴리스의 버전·태그·SHA256 목록
# 이 프로젝트는 릴리스 태그가 버전이 아니라 빌드 날짜(예: 20261026)이고, 실제 CPython 버전은 파일 이름
# (cpython-3.14.10+20261026-x86_64-unknown-linux-gnu-install_only.tar.gz)에 들어 있습니다.
# 릴리스마다 지원 중인 모든 마이너(3.11~3.15 등)의 최신 패치를 함께 빌드하므로 최신 릴리스 하나만 보면
# 각 마이너의 최신 패치를 알 수 있습니다(릴리스 JSON 약 2MB — 전체 목록은 너무 커서 보지 않음).
# 사용법: fetch_python_build_index <아키텍처 triple, 예: x86_64-unknown-linux-gnu>
# 출력: "버전 태그 sha256" 줄 목록 (조회 실패 시 빈 출력, sha256 은 GitHub digest 미제공 시 "-")
fetch_python_build_index() {
    local triple="$1"
    local -a auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    curl -sf --max-time 30 "${auth[@]}" "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest" 2>/dev/null \
        | python3 -c '
import json, re, sys
triple = sys.argv[1]
try:
    rel = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for a in rel.get("assets", []):
    m = re.fullmatch(r"cpython-(\d+\.\d+\.\d+)\+(\d+)-" + re.escape(triple) + r"-install_only\.tar\.gz", a.get("name", ""))
    if m:
        d = a.get("digest") or ""
        print(m.group(1), m.group(2), d[7:] if d.startswith("sha256:") and len(d) == 71 else "-")
' "$triple" 2>/dev/null || true
}

# track 범위 안의 설치 대상 버전 결정
# 사용법: resolve_track_version <toml 키> <기본 track> <버전 목록 명령...>
# 출력: 대상 버전('v' 없음). 정확한 버전 고정이면 그대로, 목록 조회 실패 시 빈 값(호출부가 TOML 배열로 폴백)
# 범위 밖에 더 새 버전이 있으면 표준에러로 안내합니다(메이저 업그레이드 = [track] 값 변경).
resolve_track_version() {
    local key="$1" def_track="$2"; shift 2
    local track list best top
    track=$(get_track "$key" "$def_track")
    if _track_is_exact "$track"; then
        echo "${track#v}"
        return 0
    fi
    list=$("$@")
    [ -n "$list" ] || return 0
    best=$(printf '%s\n' "$list" | _pick_in_track "$track")
    top=$(printf '%s\n' "$list" | sort -V | tail -n 1)
    if [ -n "$top" ] && [ -n "$best" ] && [ "$top" != "$best" ]; then
        print_info "  ${key}: track \"${track}\" 범위 밖에 새 버전 ${top} 이 있습니다. 올리려면 tool-versions.toml 의 [track] ${key} 값을 바꾸세요." >&2
    fi
    echo "$best"
}

# ── 설치된 도구의 새 버전 확인 방식 (DT2_UPDATE_CHECK) ───────────────────────────
# 3.install-cli-tools.sh 는 시작할 때 이미 설치된 도구가 있으면 한 번만 묻습니다.
# (2.install-core-tools.sh 는 track 이 대부분 패치·마이너 범위라 묻지 않고 check — 도구별 확인으로 동작)
#   keep  : 기존 버전 유지 (기본값) — 설치된 도구는 새 버전 조회조차 하지 않습니다(네트워크 호출·질문 없음).
#           미설치 도구만 track 범위 안의 최신 버전으로 설치합니다.
#   check : 도구별 새 버전 확인 — 도구마다 track 범위 안의 최신 버전을 조회해, 새 버전이 있으면 업데이트 여부를 묻습니다.
# 환경변수 DT2_UPDATE_CHECK 가 있으면 묻지 않고 그 값을 씁니다(무인 실행 기본값은 keep).
# 값이 비어 있으면(이 질문이 없는 앱 설치 스크립트: Zed·VS Code·Orca·Sublime Merge) 예전처럼 check 로 동작합니다.
# 사용법: dt2_select_update_check <설치된 도구가 있음 true|false> <대상 이름(예: "핵심 개발 도구")>
dt2_select_update_check() {
    local any="$1" label="$2" _uc=""
    if [ -n "${DT2_UPDATE_CHECK:-}" ]; then
        print_info "환경변수(DT2_UPDATE_CHECK) 설정 적용됨: $DT2_UPDATE_CHECK"
        export DT2_UPDATE_CHECK
        return 0
    fi
    DT2_UPDATE_CHECK="keep"
    export DT2_UPDATE_CHECK
    [ "$any" = true ] || return 0          # 설치된 도구가 없으면 물을 필요 없음(전부 새로 설치)
    dt2_is_noninteractive && return 0      # 무인 실행: 기존 버전 유지
    print_question "📦 이미 설치된 도구가 있습니다 (${label}). 새 버전을 확인할까요?"
    echo ""
    print_option "1" "기존 버전 유지 (새 버전 확인 안 함 — 미설치 도구만 설치)" "[기본값]"
    print_option "2" "도구별 새 버전 확인 (새 버전이 있으면 도구마다 업데이트 여부 질문)"
    echo ""
    prompt_read _uc "   선택 [${_C_DEFAULT}1${_C_RESET}/2]: "
    echo ""
    case "${_uc:-1}" in
        2) DT2_UPDATE_CHECK="check"; print_info "도구별 새 버전 확인을 선택했습니다." ;;
        *) print_info "기존 버전을 유지합니다 (설치된 도구는 새 버전을 확인하지 않음)." ;;
    esac
    echo ""
}

# 이 도구의 새 버전을 조회·확인해야 하는지 (0 = 확인 / 1 = 기존 버전 유지)
# 미설치, check 모드, 도구별 강제(<접두사>_UPDATE=y|n), 재설치 모드(DT2_DUPLICATE_MODE=reinstall 등)이면 확인합니다.
# 사용법: dt2_should_check_update <설치여부 true|false> <환경변수 접두사, 예: DT2_JDK21>
dt2_should_check_update() {
    local installed="$1" prefix="$2" _uv
    [ "$installed" = true ] || return 0
    _uv="${prefix}_UPDATE"
    [ -n "${!_uv:-}" ] && return 0
    case "${DUPLICATE_MODE:-${DT2_DUPLICATE_MODE:-}}" in remove|reinstall|individual) return 0 ;; esac
    [ "${DT2_UPDATE_CHECK:-check}" = "check" ]
}

# ── 앱 설치·업데이트 여부 결정 공용 함수 (앱 규칙) ─────────────────────────────
# Zed · Orca · VS Code · Sublime Merge · Ghostty 처럼 "버전 고정(TOML)"이 아닌 사용자 앱이 모두 같은 규칙으로
# 동작하도록 판단을 한 곳에 모았습니다. 새 앱을 추가할 때도 이 함수를 쓰면 동일하게 동작합니다.
# (Java·Node.js·Python·Neovim·CLI 도구 같은 개발 런타임/도구는 재현성을 위해 TOML 버전 고정 방식을 그대로 씁니다)
#
#   ● 미설치: 설치 여부 확인 (기본값은 앱별 지정, 보통 N / 기본 터미널처럼 꼭 필요한 앱은 Y)
#             설치 기본값 "A"(auto)는 묻지 않고 바로 설치합니다 — Java·Node.js·CLI 도구처럼 개발 환경에 필수인 도구용
#   ● 설치됨: 최신 버전 조회 → 새 버전이 있으면 업데이트 여부 확인 (기본값 Y)
#             최신 버전 조회 실패 또는 이미 최신이면 건너뜀. 설치는 됐지만 현재 버전을 모르면 업데이트를 제안
#   ● 무인 실행(DT2_NONINTERACTIVE=1 또는 tty 없음): 업데이트하지 않고 기존 설치 유지 (기존 Orca 규칙을 공통화)
#   ● 환경변수 강제: <접두사>_CHOICE=y|n (설치 여부), <접두사>_UPDATE=y|n (업데이트 여부)
#   ● 기존 버전 유지 모드(DT2_UPDATE_CHECK=keep, dt2_should_check_update): 설치됨이면 새 버전을 확인하지 않고 건너뜀
#
# 사용법: decide_app_action <표시 이름> <설치여부 true|false> <현재 버전> <최신 버전> <설치 기본값 Y|N|A> <환경변수 접두사> [업데이트 안내문]
# 결과: 전역 변수 DT2_APP_ACTION = install | update | skip  (함수 반환값은 항상 0)
decide_app_action() {
    local _name="$1" _installed="$2" _cur="$3" _latest="$4" _install_def="${5:-N}" _prefix="$6" _update_note="${7:-}"
    local _choice_var="${_prefix}_CHOICE" _update_var="${_prefix}_UPDATE"
    local _choice="${!_choice_var:-}" _update="${!_update_var:-}"
    DT2_APP_ACTION="skip"

    if [ "$_installed" != true ]; then
        if [ "$_install_def" = "A" ] && [ -z "$_choice" ]; then
            DT2_APP_ACTION="install"
            return 0
        elif [ -n "$_choice" ]; then
            [ "${_choice,,}" = "y" ] && DT2_APP_ACTION="install"
        elif prompt_confirm "   👉 ${_name}을(를) 설치하시겠습니까?" "$_install_def"; then
            DT2_APP_ACTION="install"
        fi
        [ "$DT2_APP_ACTION" = "skip" ] && print_skip "${_name} 설치를 건너뜁니다."
        return 0
    fi
    if ! dt2_should_check_update true "$_prefix"; then
        print_skip "${_name}${_cur:+ ${_cur}} — 기존 버전 유지 (새 버전 확인 안 함)"
        return 0
    fi

    if [ -z "$_latest" ]; then
        print_info "${_name} 이(가) 설치되어 있습니다(${_cur:-버전 기록 없음}). 최신 버전 확인에 실패해 업데이트 확인은 건너뜁니다."
        return 0
    fi
    if [ "$_cur" = "$_latest" ]; then
        print_skip "${_name} ${_cur} 이(가) 이미 최신 버전입니다."
        return 0
    fi

    print_info "${_name} 새 버전이 있습니다: ${_cur:-알 수 없음(버전 기록 없음)} → ${_latest}"
    if [ -n "$_update" ]; then
        [ "${_update,,}" = "y" ] && DT2_APP_ACTION="update"
    elif dt2_is_noninteractive; then
        print_skip "비대화형 실행이라 ${_name} 업데이트를 건너뜁니다 (${_update_var}=y 로 강제 가능)."
        return 0
    elif prompt_confirm "   👉 ${_name}을(를) ${_latest} 로 업데이트하시겠습니까?${_update_note:+ $_update_note}" "Y"; then
        DT2_APP_ACTION="update"
    fi
    [ "$DT2_APP_ACTION" = "skip" ] && print_skip "${_name} 업데이트를 건너뜁니다. (현재: ${_cur:-알 수 없음} 유지)"
    return 0
}

# ── WSLg GUI 앱 실행 래퍼용 한글 입력기 환경 코드 조각 (Sublime Merge · Orca 등 공용) ──────
# WSLg 에는 데스크톱 세션(im-config/autostart)이 없으므로, GUI 앱을 띄우는 래퍼가 실행 시점에 직접
#   ● fcitx5 입력기 환경변수(GTK_IM_MODULE 등) 지정
#   ● 세션 DBus 주소 보정 (fcitx GTK 입력 모듈은 DBus 로 fcitx5 와 통신; wsl.exe -e 실행 시 비어 있을 수 있음)
#   ● fcitx5 데몬이 없으면 기동 (WSLg 컴포지터는 Wayland 입력기 프로토콜을 지원하지 않아 wayland 애드온은 끔)
# 을 해야 합니다. 앱마다 같은 코드를 복사하지 않도록 이 함수가 래퍼에 넣을 셸 코드를 출력합니다.
# Linux 데스크톱(WSL 아님)이나 fcitx5 가 없으면 아무 것도 하지 않는 코드라 공통으로 넣어도 안전합니다.
# 사용법: cat <<EOF > 래퍼 ... $(wslg_ime_env_snippet) ... EOF
wslg_ime_env_snippet() {
    cat <<'SNIPPET'
if grep -qi microsoft /proc/version 2>/dev/null && command -v fcitx5 >/dev/null 2>&1; then
    export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx SDL_IM_MODULE=fcitx
    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "/run/user/$(id -u)/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    fi
    if ! pgrep -u "$(id -u)" -x fcitx5 >/dev/null 2>&1; then
        fcitx5 -d --replace --disable=wayland,waylandim >/dev/null 2>&1 || true
    fi
fi
SNIPPET
}

# ── 한글 입력기(IME) 확인 및 설치 (WSL2 WSLg · Linux 데스크톱 공용) ──────────
# GUI 앱(Sublime Merge 등)에서 한글을 입력하려면 디스플레이 서버에 등록되는 입력기가 필요합니다.
# ⚠️ 포터블 원칙의 예외: 입력기는 시스템 서비스라 apt 로 직접 설치해야 합니다(0.init-devtools2.sh 상단 메모 참고).
#   ● 이미 한글 엔진(fcitx5-hangul / ibus-hangul / kime / nimf / fcitx-hangul)이 있으면 설치를 건너뜁니다.
#   ● Linux GNOME + ibus 환경: GNOME 은 ibus 와 통합되어 있으므로 fcitx5 를 새로 넣지 않고
#     ibus-hangul 만 추가한 뒤 GNOME 입력 소스에 한국어(Hangul)를 등록합니다(충돌 방지).
#   ● 그 외(WSL2 포함): fcitx5 + fcitx5-hangul 을 설치합니다.
#     - Linux 데스크톱: im-config 로 기본 입력기를 fcitx5 로 지정합니다(다음 로그인부터 적용).
#     - WSL2: 데스크톱 세션(im-config/autostart)이 없으므로 환경변수 지정과 데몬 기동은
#       앱 실행 래퍼(예: modules/sublime-merge/bin/smerge)가 실행 시점에 담당합니다.
#   ● fcitx5 사용자 설정(~/.config/fcitx5/profile, config)이 없을 때만 한글 기본 프로필과
#     한/영 전환 키(Hangul, 오른쪽 Alt)를 생성합니다(기존 사용자 설정 보존).
#     config 가 이미 있으면 기존 키는 그대로 두고, Windows AutoHotkey 가 WSLg 창에 보내는 전용 키
#     (한/영: Control+Alt+Shift+F12, 영문: Control+Alt+Shift+F11) 중 빠진 것만 보충합니다.
#     (예전 보조 전환 키 Shift+Space 는 fcitx5 가 없을 때 공백이 입력되는 부작용이 있어 더 이상 넣지 않음)
# 반환: 0 = 한글 입력기 준비됨(또는 비 apt 배포판이라 건너뜀), 1 = 설치 실패
ensure_korean_ime() {
    if ! command -v dpkg-query >/dev/null 2>&1 || ! command -v apt-get >/dev/null 2>&1; then
        print_warn "apt 기반 배포판이 아니어서 한글 입력기 자동 설치를 건너뜁니다. (fcitx5-hangul 또는 ibus-hangul 을 직접 설치하세요)"
        return 0
    fi
    _dt2_pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"; }

    local _p _engine=""
    for _p in fcitx5-hangul ibus-hangul kime nimf fcitx-hangul; do
        if _dt2_pkg_installed "$_p"; then
            _engine="$_p"
            break
        fi
    done

    if [ -n "$_engine" ]; then
        print_skip "한글 입력기가 이미 설치되어 있습니다: $_engine"
    else
        local _use_ibus=false _pkgs=()
        if [ "${IS_WSL2:-false}" != true ] && _dt2_pkg_installed ibus \
            && { echo "${XDG_CURRENT_DESKTOP:-}" | grep -qi gnome || command -v gnome-shell >/dev/null 2>&1; }; then
            _use_ibus=true
            _pkgs=(ibus-hangul)
        else
            _pkgs=(fcitx5 fcitx5-hangul fcitx5-frontend-gtk3 fcitx5-frontend-qt5)
            [ "${IS_WSL2:-false}" != true ] && _pkgs+=(im-config)
        fi

        print_info "한글 입력기가 없어 설치합니다: ${_pkgs[*]}"
        local _sudo=()
        if [ "$(id -u)" -ne 0 ]; then
            command -v sudo >/dev/null 2>&1 || { print_error "sudo 가 없어 한글 입력기를 설치할 수 없습니다."; return 1; }
            _sudo=(sudo)
            # 출력은 로그로 보내므로 비밀번호 프롬프트가 묻히지 않도록 먼저 인증을 받아 둡니다.
            normalize_tty
            sudo -v || { print_error "sudo 인증에 실패해 한글 입력기 설치를 건너뜁니다."; return 1; }
        fi
        # ⚠️ 종료코드를 확인하지 않으면 설치가 실패해도 아래에서 "설치 완료"가
        # 그대로 출력됩니다(3.install-cli-tools.sh의 apt install 오류 처리 관례와 동일하게 맞춤).
        # 설치는 백그라운드로 돌리고 스피너로 진행 중임을 표시합니다(위에서 sudo 인증을 이미 받아 둠).
        _dt2_ime_apt() {
            { "${_sudo[@]}" apt-get update -qq && "${_sudo[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${_pkgs[@]}"; } >"$DT2_TMP/_ime_apt.log" 2>&1
        }
        if ! run_with_spinner_cmd "한글 입력기 설치 중... (${_pkgs[*]})" _dt2_ime_apt; then
            print_error "한글 입력기 설치에 실패했습니다. (로그: $DT2_TMP/_ime_apt.log)"
            return 1
        fi

        if [ "$_use_ibus" = true ]; then
            _engine="ibus-hangul"
            # GNOME 입력 소스에 ('ibus', 'hangul') 이 없을 때만 추가 (GUI 세션 밖에서 실행되면 조용히 건너뜀)
            if command -v gsettings >/dev/null 2>&1; then
                local _src
                _src=$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || true)
                if [ -n "$_src" ] && ! echo "$_src" | grep -q "'hangul'"; then
                    if [ "$_src" = "@a(ss) []" ] || [ "$_src" = "[]" ]; then
                        _src="[('xkb', 'us'), ('ibus', 'hangul')]"
                    else
                        _src="${_src%]}, ('ibus', 'hangul')]"
                    fi
                    gsettings set org.gnome.desktop.input-sources sources "$_src" 2>/dev/null || true
                fi
            fi
        else
            _engine="fcitx5-hangul"
            # im-config를 비대화형 모드로 실행하여 fcitx5 지정 (Linux 데스크톱 전용)
            if [ "${IS_WSL2:-false}" != true ] && command -v im-config >/dev/null 2>&1; then
                im-config -n fcitx5 >/dev/null 2>&1 || print_warn "im-config 로 기본 입력기를 fcitx5 로 지정하지 못했습니다."
            fi
        fi
        print_done "한글 입력기 설치 완료: $_engine"
        [ "${IS_WSL2:-false}" != true ] && print_info "  다음 로그인(또는 재부팅)부터 한글 입력기가 활성화됩니다."
        # keyd 가 fcitx5 설치 전에 배포되었다면 전역 ESC → 영문 전환(C-A-S-f11)이 꺼진 채로 배포되어 있으므로 재배포 안내
        # (4.setup-keyboard.sh 는 fcitx5 설치 여부를 보고 .config/keyd/default.conf 의 영문 전환 매크로를 켜고 끕니다)
        if [ "$_engine" = "fcitx5-hangul" ] && [ -f /etc/keyd/default.conf ] && ! grep -q "C-A-S-f11" /etc/keyd/default.conf 2>/dev/null; then
            print_info "  전역 ESC → 영문 전환을 켜려면 keyd 설정을 다시 배포하세요: sudo bash ${DEVTOOLS2:-/var/opt/_devtools2}/scripts/linux/dev-env/4.setup-keyboard.sh"
        fi
    fi

    # fcitx5 기본 프로필(영문 + 한글) 및 한/영 전환 키 — 파일이 없을 때만 생성
    # (단, 전환 키 config 는 AHK 연동 전용 키가 꼭 있어야 하므로 기존 파일에도 빠진 키만 보충합니다)
    if [ "$_engine" = "fcitx5-hangul" ]; then
        local _fdir="${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5"
        mkdir -p "$_fdir"
        if [ ! -f "$_fdir/profile" ]; then
            cat >"$_fdir/profile" <<'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=hangul

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=hangul
Layout=

[GroupOrder]
0=Default
EOF
        fi
        # 한/영 전환 키(TriggerKeys)와 영문 전환 키(DeactivateKeys)
        # - 한/영 키는 키보드·WSLg 키 매핑에 따라 Hangul 또는 Alt_R 로 들어오므로 둘 다 등록합니다
        #   (Linux 데스크톱에서 물리 한/영 키·오른쪽 Alt 를 그대로 쓰는 경우).
        # - Control+Alt+Shift+F12 / F11 은 Windows AutoHotkey(devtools2-hotkey.ahk Part 5)가
        #   WSLg 창에서 한/영 키와 Esc·CapsLock 탭·Ctrl+[ 를 대신해 보내는 "안전한 전용 키"입니다.
        #   어떤 앱(Sublime Merge/Text 기본 키맵 포함)에서도 쓰지 않는 조합이라, fcitx5 가 없거나 꺼져 있어도
        #   공백 입력 같은 부작용이 생기지 않습니다. (예전 보조 전환 키 Shift+Space 는 이 부작용 때문에 제외)
        #   AHK 쪽 조합과 반드시 함께 바꿔야 합니다.
        # - 파일이 없으면 새로 만들고, 사용자 설정 파일이 이미 있으면 기존 키는 그대로 두고
        #   위 키들 중 빠진 것만 해당 섹션 끝에 추가합니다(기존 사용자 설정 보존, 멱등).
        python3 - "$_fdir/config" <<'PYEOF' || print_warn "fcitx5 전환 키 설정을 기록하지 못했습니다: $_fdir/config"
import os, re, sys

path = sys.argv[1]
wanted = {
    "Hotkey/TriggerKeys": ["Hangul", "Alt_R", "Control+Alt+Shift+F12"],
    "Hotkey/DeactivateKeys": ["Control+Alt+Shift+F11"],
}
lines = open(path, encoding="utf-8").read().splitlines() if os.path.exists(path) else []

for section, keys in wanted.items():
    header = f"[{section}]"
    if header not in [l.strip() for l in lines]:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append(header)
    start = [l.strip() for l in lines].index(header) + 1
    end = start
    while end < len(lines) and not lines[end].strip().startswith("["):
        end += 1
    entries = {}
    for l in lines[start:end]:
        m = re.match(r"\s*(\d+)\s*=\s*(.*)$", l)
        if m:
            entries[int(m.group(1))] = m.group(2).strip()
    insert_at = end
    while insert_at > start and not lines[insert_at - 1].strip():
        insert_at -= 1
    next_idx = max(entries) + 1 if entries else 0
    for k in keys:
        if k not in entries.values():
            lines.insert(insert_at, f"{next_idx}={k}")
            insert_at += 1
            next_idx += 1

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PYEOF
        # 실행 중인 fcitx5 는 종료 시 메모리의 설정으로 파일을 덮어쓰므로, 바뀐 파일을 즉시 다시 읽게 합니다.
        if pgrep -u "$(id -u)" -x fcitx5 >/dev/null 2>&1 && command -v fcitx5-remote >/dev/null 2>&1; then
            fcitx5-remote -r >/dev/null 2>&1 || true
        fi
    fi
    return 0
}

# ── GUI 한글 폰트 확인 및 설치 (WSL2 WSLg · Linux 데스크톱 공용) ──────────────
# GUI 앱(Sublime Merge 등)의 메뉴·목록 같은 UI 글꼴은 fontconfig 의 기본 sans-serif 를 따릅니다.
#   ● WSL2 에는 데스크톱 글꼴이 없어 sans-serif 가 터미널용 'D2Coding Nerd Font Mono' 로 잡히는데,
#     Mono 계열 Nerd Font 는 모든 글자를 한 칸 폭으로 취급해 두 칸 폭인 한글이 서로 겹쳐 보입니다
#     (실측: Sublime Merge 커밋 목록 한글 겹침). 또 GTK 기본 글꼴 'Cantarell 11' 이 없어 같은 글꼴이
#     11pt 로 대체되어 제목 표시줄·메뉴 글자가 앱 본문보다 비정상적으로 크게 보였습니다.
#   ● 가변폭(proportional) 한글 글꼴이 하나도 없을 때만 Ubuntu 데스크톱 기본 한글 글꼴인
#     fonts-noto-cjk(Noto Sans CJK KR)를 설치합니다 → WSL 과 Linux 데스크톱의 UI 글꼴이 같아집니다.
#     (Linux 데스크톱은 대부분 이미 있어 건너뜀)
#   ● WSL2 전용 보정 (데스크톱 환경이 없어 기본값을 정해 줄 주체가 없으므로):
#     - ~/.config/fontconfig/conf.d/60-devtools2-sans.conf: sans-serif 선호 순서를
#       Noto Sans CJK KR → D2Coding ligature(가변폭 글꼴 설치 실패 시에도 겹침만은 방지) 로 지정
#       (사용자 fonts.conf 는 건드리지 않는 별도 파일, 멱등)
#     - GTK 글꼴이 기본값 'Cantarell 11'(미설치 글꼴)일 때만 'Sans 9' 로 변경 (사용자가 바꾼 값은 보존)
#   ⚠️ 포터블 원칙의 예외: 시스템 fontconfig 가 읽는 글꼴 패키지라 apt 로 설치합니다.
# 반환: 0 = 준비됨(또는 비 apt 배포판이라 설치 건너뜀), 1 = 글꼴 설치 실패
ensure_korean_gui_font() {
    local _rc=0
    # fc-list 의 spacing 출력: 고정폭은 spacing=90/100 이 붙고 가변폭은 붙지 않음
    if command -v fc-list >/dev/null 2>&1 && fc-list ':lang=ko' spacing 2>/dev/null | grep -qv 'spacing='; then
        print_skip "가변폭 한글 UI 글꼴이 이미 설치되어 있습니다."
    elif ! command -v apt-get >/dev/null 2>&1; then
        print_warn "apt 기반 배포판이 아니어서 한글 UI 글꼴 자동 설치를 건너뜁니다. (Noto Sans CJK 등을 직접 설치하세요)"
    else
        print_info "가변폭 한글 UI 글꼴이 없어 설치합니다: fonts-noto-cjk (Noto Sans CJK KR)"
        local _sudo=()
        if [ "$(id -u)" -ne 0 ]; then
            if command -v sudo >/dev/null 2>&1; then
                _sudo=(sudo)
                # 출력은 로그로 보내므로 비밀번호 프롬프트가 묻히지 않도록 먼저 인증을 받아 둡니다.
                normalize_tty
                sudo -v || _sudo=(false)
            else
                _sudo=(false)
            fi
        fi
        # 패키지 목록이 오래되어 실패하면 목록을 갱신한 뒤 한 번 더 시도합니다.
        # 설치는 백그라운드로 돌리고 스피너로 진행 중임을 표시합니다(위에서 sudo 인증을 이미 받아 둠).
        _dt2_font_apt() {
            { "${_sudo[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fonts-noto-cjk \
                || { "${_sudo[@]}" apt-get update -qq && "${_sudo[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fonts-noto-cjk; }; } >"$DT2_TMP/_font_apt.log" 2>&1
        }
        if run_with_spinner_cmd "한글 UI 글꼴 설치 중... (fonts-noto-cjk)" _dt2_font_apt; then
            print_done "한글 UI 글꼴 설치 완료: Noto Sans CJK KR"
        else
            print_warn "한글 UI 글꼴 설치에 실패했습니다. (로그: $DT2_TMP/_font_apt.log) — D2Coding 으로 대체합니다."
            _rc=1
        fi
    fi

    if [ "${IS_WSL2:-false}" = true ]; then
        local _fc_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d"
        mkdir -p "$_fc_dir"
        cat >"$_fc_dir/60-devtools2-sans.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<!-- DevTools2 (WSL2 전용, _install-utils.sh 의 ensure_korean_gui_font 가 생성):
     WSLg GUI 앱의 기본 UI 글꼴이 Mono Nerd Font 로 잡혀 한글이 겹치는 문제를 막기 위해
     sans-serif 선호 순서를 지정합니다. -->
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans CJK KR</family>
      <family>D2Coding ligature</family>
    </prefer>
  </alias>
</fontconfig>
EOF
        if command -v gsettings >/dev/null 2>&1 \
            && [ "$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null || true)" = "'Cantarell 11'" ]; then
            gsettings set org.gnome.desktop.interface font-name 'Sans 9' 2>/dev/null || true
        fi
        command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1 || true
    fi
    return $_rc
}

# ── Ghostty 글꼴 크기를 중앙 UI 기본값(ui-defaults.json)과 동기화 (Linux 데스크톱) ──────
# Neovim 을 띄우는 터미널(Windows: Windows Terminal, Linux: Ghostty)의 글꼴 크기를 한 곳에서 관리합니다.
#   ● Linux(GTK) 판 Ghostty 는 font-size 에 데스크톱의 "텍스트 크기 배율"(GNOME text-scaling-factor)을
#     추가로 곱해 그립니다(Ghostty src/config/Config.zig font-size 주석). 그래서 json 값을 그대로 쓰면
#     배율만큼 커지므로, 화면에서 json 의 크기(예: 11.5pt)로 보이도록 "json 크기 ÷ 텍스트 배율"로 역산합니다.
#     (예: 배율 1.125 → 11.5 ÷ 1.125 ≈ 10.2 — 예전 config.ghostty 에 직접 적어 두었던 값과 같음)
#   ● 화면 배율(200% 등 정수 배율)은 Windows 의 DPI 배율과 같은 개념이라 보정하지 않습니다.
#   ● 결과는 ~/.config/ghostty(= $DEVTOOLS2/.config/ghostty 심볼릭 링크)의 font.local.ghostty 에 기록하고,
#     config.ghostty 가 config-file = ?font.local.ghostty 로 불러와 덮어씁니다(PC 별 값이라 git 추적 제외).
#   ● 텍스트 배율은 설치 시점 값으로 계산합니다. GNOME 텍스트 크기를 바꾼 뒤에는 이 함수를 다시 실행하세요
#     (2.install-core-tools.sh 재실행 시 자동 호출). gsettings 를 읽을 수 없으면 배율 1.0 으로 계산합니다.
# 사용법: sync_ghostty_font_size [ghostty 설정 디렉터리, 기본: $DEVTOOLS2/.config/ghostty]
sync_ghostty_font_size() {
    local _gdir="${1:-$DEVTOOLS2/.config/ghostty}"
    local _ui="$DEVTOOLS2/.config/devtools2/ui-defaults.json"
    [ -d "$_gdir" ] && [ -f "$_ui" ] || return 0

    local _scale="1.0"
    if command -v gsettings >/dev/null 2>&1; then
        _scale=$(gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null || echo "1.0")
    fi

    python3 - "$_ui" "$_gdir/font.local.ghostty" "$_scale" <<'PYEOF' || print_warn "Ghostty 글꼴 크기 동기화에 실패했습니다."
import json, sys
ui_path, out_path, scale_raw = sys.argv[1], sys.argv[2], sys.argv[3]
size = float(json.load(open(ui_path, encoding="utf-8")).get("font", {}).get("size", 11.5))
try:
    scale = float(scale_raw)
    if scale <= 0:
        scale = 1.0
except ValueError:
    scale = 1.0
ghostty_size = round(size / scale, 1)
content = (
    "# DevTools2 자동 생성 파일 — 직접 수정하지 마세요 (git 추적 제외)\n"
    "# 원본: .config/devtools2/ui-defaults.json (font.size)\n"
    "# 생성: _install-utils.sh 의 sync_ghostty_font_size (2.install-core-tools.sh 가 호출)\n"
    f"# 계산: {size:g}pt ÷ GNOME 텍스트 크기 배율 {scale:g} = {ghostty_size:g}\n"
    "#       (Linux GTK 판 Ghostty 는 텍스트 배율을 곱해 그리므로, 화면에서 json 크기로 보이도록 역산)\n"
    f"font-size = {ghostty_size:g}\n"
)
try:
    old = open(out_path, encoding="utf-8").read()
except FileNotFoundError:
    old = None
if old != content:
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(content)
print(f"[완료] Ghostty 글꼴 크기: {size:g}pt ÷ 텍스트 배율 {scale:g} → font-size = {ghostty_size:g}")
PYEOF
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
    # "|| true": head 가 첫 줄만 읽고 닫으면 tar 가 SIGPIPE(141)로 끝나, 호출한 스크립트가
    # "set -o pipefail + set -e" 이면 여기서 즉시 종료됩니다(큰 아카이브에서 재현). 값은 그대로 얻어집니다.
    EXTRACTED_DIR=$(tar -tf "$FILE_NAME" 2>/dev/null | head -1 | cut -f1 -d"/") || true
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

# tool-versions.toml 의 기본 고정 버전(배열 첫 항목)을 반환합니다.
_get_toml_version() {
    _read_toml \
        | grep -E "^${1} = \[" 2>/dev/null \
        | grep -oE '"[^"]+"' | head -1 | tr -d '"'
}

# 지정한 키의 "지정 버전"을 반환합니다.
# - 이 PC 에서 TOML 과 다른 버전(최신 등)을 설치했다면 data/state 에 기록된 그 버전을 우선합니다.
# - 단, 기록 당시의 TOML 기준값(<key>@toml)과 현재 TOML 값이 다르면(누군가 TOML 을 새 버전으로
#   올렸다면) TOML 값을 따릅니다. 그렇지 않으면 TOML 의 보안 패치 갱신이 이미 설치한 PC 에는
#   영원히 반영되지 않습니다. (기준값이 없는 예전 상태 파일도 TOML 을 따름)
get_pinned_version() {
    local key="$1"
    local toml_ver
    toml_ver=$(_get_toml_version "$key")
    if [ -f "$STATE_FILE" ]; then
        local local_ver
        local_ver=$(python3 - "$STATE_FILE" "$key" "$toml_ver" <<'PY' 2>/dev/null || true
import json, sys
path, key, toml_ver = sys.argv[1:4]
try:
    d = json.load(open(path, encoding='utf-8'))
except Exception:
    d = {}
ver = d.get(key, '')
base = d.get(key + '@toml', None)
if ver and (not toml_ver or base == toml_ver):
    print(ver)
PY
)
        if [ -n "$local_ver" ]; then
            echo "$local_ver"
            return 0
        fi
    fi
    echo "$toml_ver"
}

# 머신별 설치 버전 상태를 data/state/installed-tools.json 에 격리 기록합니다.
# (Git 형상관리 대상인 tool-versions.toml 은 건드리지 않아 작업 트리 무결성을 보장합니다)
# 기록 당시의 TOML 기준값도 함께 남겨, 이후 TOML 이 갱신되면 TOML 을 따르게 합니다.
# 값은 인자(argv)로 넘겨 파이썬 코드에 직접 이어 붙이지 않습니다(태그 문자열에 따옴표가 있어도 안전).
update_pinned_version() {
    local key="$1" new_ver="$2"
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    python3 - "$STATE_FILE" "$key" "$new_ver" "$(_get_toml_version "$key")" <<'PY' 2>/dev/null || true
import json, os, sys
path, key, ver, toml_ver = sys.argv[1:5]
data = {}
if os.path.exists(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception:
        data = {}
data[key] = ver
data[key + '@toml'] = toml_ver
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
    echo "   📝 [머신 상태: data/state] ${key} 버전 기록: \"${new_ver}\""
}

# tool-versions.toml 에서 지원하는 Adoptium JDK 메이저 버전 목록을 내림차순(예: "25 21 17 8")으로 반환합니다.
# TOML 의 python3NN 키(예: python315)에서 설치 대상 Python 마이너 목록을 높은 순으로 반환 ("3.15 3.14 3.12")
# JDK 처럼 TOML 에 키를 추가하면 설치 스크립트·명령 팔레트(Python 전환)에 자동으로 반영됩니다.
get_supported_python_minors() {
    local m
    m=$(_read_toml | grep -E '^python3[0-9]+ = \[' 2>/dev/null | grep -oE '^python3[0-9]+' | sed -E 's/^python3/3./' | sort -t. -k2,2nr | tr '\n' ' ' | sed 's/ *$//' || true)
    echo "${m:-3.14 3.12}"
}

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

# GitHub 릴리스 자산의 SHA256 을 GitHub API(assets[].digest)에서 조회합니다.
# 체크섬 파일을 따로 배포하지 않는 저장소(Neovim, fd, ast-grep, Ghostty 등)도 이 값으로 검증할 수 있습니다.
# 사용법: github_asset_sha256 <owner/repo> <tag | latest> <자산 파일명>
# 출력: 64자리 16진수 SHA256 (조회 실패·digest 미제공이면 빈 문자열)
# ⚠️ 비인증 API 는 시간당 60회 제한이 있으므로, GITHUB_TOKEN 이 있으면 인증 헤더로 사용합니다.
github_asset_sha256() {
    local repo="$1" tag="$2" asset="$3"
    local api="https://api.github.com/repos/${repo}/releases/tags/${tag}"
    [ "$tag" = "latest" ] && api="https://api.github.com/repos/${repo}/releases/latest"
    local -a auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    curl -fsSL --max-time 10 "${auth[@]}" "$api" 2>/dev/null \
        | python3 -c '
import json, sys
asset = sys.argv[1]
try:
    for a in json.load(sys.stdin).get("assets", []):
        if a.get("name") == asset:
            d = a.get("digest") or ""
            if d.startswith("sha256:") and len(d) == 71:
                print(d[7:])
            break
except Exception:
    pass
' "$asset" 2>/dev/null || true
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
            if dt2_is_noninteractive; then
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

# (예전 _select_version_mode: 설치 때 "최신/지정/개별" 버전 선택 방식을 묻던 함수 — tool-versions.toml [track] 정책으로 대체되어 제거)

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
# 인수: $1 = 대상 파일 경로, $2 = 64자리 16진수 SHA256 또는 체크섬 파일 URL, $3 = 원본 파일명 힌트(선택)
verify_sha256() {
    local target_file="$1"
    local checksum_spec="$2"
    local filename_hint="${3:-$(basename "$target_file")}"

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
        if [ -n "$raw_cs" ]; then
            if [ -n "$filename_hint" ]; then
                local matched_line
                matched_line=$(echo "$raw_cs" | grep -iF "$filename_hint" | head -1 || true)
                if [ -n "$matched_line" ]; then
                    expected_hash=$(echo "$matched_line" | grep -oE '[0-9a-fA-F]{64}' | head -1 || true)
                fi
            fi
            if [ -z "$expected_hash" ]; then
                expected_hash=$(echo "$raw_cs" | grep -oE '[0-9a-fA-F]{64}' | head -1 || true)
            fi
        fi
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
#    성공 시 0, 실패 시 1 반환 (스테이징 디렉터리에 먼저 풀어, 실패 시 대상 디렉터리 오염 방지)
#    인수: $1 = URL, $2 = 대상 디렉터리, $3 = strip_count(기본 0),
#          $4 = sha256_or_url(선택), $5 = label(선택, 프로그레스 바 표시용)
#    다운로드 시 download_with_progress 프로그레스 바를 표시하고,
#    압축 해제 시 show_spinner 회전 애니메이션을 표시합니다.
safe_download_and_extract() {
    local url="$1"
    local target_dir="$2"
    local strip_count="${3:-0}"
    local checksum_spec="${4:-}"
    local label="${5:-$(basename "$url")}"

    if [ -z "$url" ] || [ -z "$target_dir" ]; then
        echo "❌ safe_download_and_extract 오류: URL과 대상 디렉터리는 필수입니다." >&2
        return 1
    fi

    local tmp_archive
    tmp_archive=$(mktemp "/tmp/dt2_dl_XXXXXX")
    # ⚠️ RETURN 트랩은 전역이라 지우지 않으면 이 함수를 부른 "바깥 함수"가 끝날 때도 다시 실행되고,
    #   그때는 local 변수가 없어 set -u 에서 "바인딩 해제한 변수"로 스크립트가 죽습니다(실측: Orca 설치).
    #   그래서 한 번 실행되면 스스로 트랩을 해제합니다.
    trap 'rm -f "${tmp_archive:-}"; trap - RETURN' RETURN

    # 프로그레스 바와 함께 다운로드 (download_with_progress 는 _common.sh 에서 로드됨)
    if ! download_with_progress "$url" "$tmp_archive" "$label"; then
        echo "   ❌ 다운로드 실패 (HTTP 에러 또는 연결 오류): $url" >&2
        return 1
    fi

    if [ ! -s "$tmp_archive" ]; then
        echo "   ❌ 다운로드 실패 (빈 파일): $url" >&2
        return 1
    fi

    if [ -n "$checksum_spec" ]; then
        if ! verify_sha256 "$tmp_archive" "$checksum_spec" "$(basename "$url")"; then
            return 1
        fi
    fi

    # ⚠️ 대상 디렉터리에 바로 풀지 않고, 같은 파일시스템의 임시 스테이징 디렉터리에 먼저 풉니다.
    #    압축 해제가 중간에 실패하면 대상에는 아무것도 남지 않아, 다음 실행이 "반쯤 풀린 폴더"를
    #    "이미 설치됨"으로 오판해 건너뛰는 일을 막습니다. 성공했을 때만 대상에 합칩니다.
    local parent_dir
    parent_dir=$(dirname "$target_dir")
    mkdir -p "$parent_dir"
    local stage_dir
    stage_dir=$(mktemp -d "$parent_dir/.dt2_stage_XXXXXX")
    local strip_opt=""
    [ "$strip_count" -gt 0 ] && strip_opt="--strip-components=$strip_count"

    # 스피너와 함께 압축 해제 (URL 확장자 의존 탈피 - 파일 헤더 무결성 검사 기반 자동 판별)
    echo -n "   📦 $label 압축 해제 중..."
    if unzip -tq "$tmp_archive" >/dev/null 2>&1; then
        unzip -q -o "$tmp_archive" -d "$stage_dir" &
    elif [[ "$url" == *.zip ]]; then
        unzip -q -o "$tmp_archive" -d "$stage_dir" &
    elif tar -tzf "$tmp_archive" >/dev/null 2>&1; then
        tar -xzf "$tmp_archive" -C "$stage_dir" $strip_opt &
    elif tar -tf "$tmp_archive" >/dev/null 2>&1; then
        tar -xf "$tmp_archive" -C "$stage_dir" $strip_opt &
    else
        tar -xzf "$tmp_archive" -C "$stage_dir" $strip_opt &
    fi
    local _ext_pid=$!
    show_spinner $_ext_pid
    if ! wait $_ext_pid 2>/dev/null; then
        echo " ❌ 압축 해제 실패" >&2
        rm -rf "$stage_dir"
        return 1
    fi

    # 대상 디렉터리에 합치기 (대상에 이미 있는 다른 파일은 보존, 같은 이름은 덮어씀)
    # ⚠️ "cp -a stage/. target/" 은 mktemp -d 의 700 권한을 대상 디렉터리 자체에 덮어써
    #    공유 디렉터리(2770)의 그룹 접근을 막으므로, 스테이징 "안의 항목"만 복사합니다.
    mkdir -p "$target_dir"
    local -a _entries
    _entries=( "$stage_dir"/* "$stage_dir"/.[!.]* "$stage_dir"/..?* )
    local _e _copy_ok=true
    for _e in "${_entries[@]}"; do
        [ -e "$_e" ] || [ -L "$_e" ] || continue
        cp -a "$_e" "$target_dir/" || { _copy_ok=false; break; }
    done
    if [ "$_copy_ok" != true ]; then
        echo " ❌ 설치 위치로 복사 실패: $target_dir" >&2
        rm -rf "$stage_dir"
        return 1
    fi
    rm -rf "$stage_dir"
    echo " 완료"

    return 0
}

# 2) 단일 바이너리/스크립트 파일 안전 다운로드
#    성공 시 0, 실패 시 1 반환 (원자적 교체 및 체크섬 검증 지원)
#    인수: $1 = URL, $2 = 대상 파일, $3 = 권한모드(기본 755),
#          $4 = sha256_or_url(선택), $5 = label(선택, 프로그레스 바 표시용)
safe_download_binary() {
    local url="$1"
    local target_file="$2"
    local chmod_mode="${3:-755}"
    local checksum_spec="${4:-}"
    local label="${5:-$(basename "$target_file")}"

    if [ -z "$url" ] || [ -z "$target_file" ]; then
        echo "❌ safe_download_binary 오류: URL과 대상 파일 경로는 필수입니다." >&2
        return 1
    fi

    local target_dir
    target_dir=$(dirname "$target_file")
    mkdir -p "$target_dir"

    local tmp_file
    tmp_file=$(mktemp "/tmp/dt2_bin_XXXXXX")
    # ⚠️ RETURN 트랩은 전역이라 지우지 않으면 이 함수를 부른 "바깥 함수"가 끝날 때도 다시 실행되고,
    #   그때는 local 변수가 없어 set -u 에서 "바인딩 해제한 변수"로 스크립트가 죽습니다(실측: Orca 설치).
    #   그래서 한 번 실행되면 스스로 트랩을 해제합니다.
    trap 'rm -f "${tmp_file:-}"; trap - RETURN' RETURN

    # 프로그레스 바와 함께 다운로드
    if ! download_with_progress "$url" "$tmp_file" "$label"; then
        echo "   ❌ $label 바이너리 다운로드 실패 (HTTP 에러 또는 연결 오류): $url" >&2
        return 1
    fi

    if [ ! -s "$tmp_file" ]; then
        echo "   ❌ $label 다운로드 실패 (빈 파일): $url" >&2
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

# Adoptium 이 제공하는 가장 최근 LTS Java 메이저 번호 (예: 25) — 조회 실패 시 빈 출력
# 사용처: 2.install-core-tools.sh 의 "새 LTS 안내" (tool-versions.toml 에 없는 새 LTS 가 나오면 안내만 함)
fetch_adoptium_latest_lts() {
    curl -sf --max-time 10 "https://api.adoptium.net/v3/info/available_releases" 2>/dev/null \
        | python3 -c 'import json, sys
try:
    print(int(json.load(sys.stdin).get("most_recent_lts")))
except Exception:
    pass' 2>/dev/null || true
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
            clean_rel = rel[4:] if rel.startswith("jdk-") else (rel[3:] if rel.startswith("jdk") else rel)
            if clean_rel and link:
                print(f"{clean_rel}|{link}|{chk}")
except Exception:
    pass
'
    python3 -c "$py_script" "$feature_ver" "$arch" 2>/dev/null || true
}
