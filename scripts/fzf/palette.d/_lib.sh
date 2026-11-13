# shellcheck shell=bash
# ==============================================================================
# [명령 팔레트] 그룹 공통 함수 — 두 그룹 이상이 쓰는 함수·값
# ==============================================================================
# command-palette 가 source 로 불러오는 파일입니다(단독 실행 X). 구조 설명은 command-palette 의
# 이 파일 = 그룹 공통: 포트·프로세스(🐘 Gradle bootRun 충돌 처리 + 🖥️ 시스템), 프로젝트별 저장값, 클립보드,
# Git 저장소 위치·데스크톱 여부, GUI 앱 떼어 실행(🧰 외부 도구 + 🤖 AI), 1단계 메뉴 등록·2단계 선택 공용 함수.
# 한 그룹만 쓰는 함수는 그 그룹 파일에 두고, 다른 그룹도 쓰게 되면 그때 이 파일로 옮깁니다.

# ── 1단계 메뉴 등록 ─────────────────────────────────────────────────────────
# 그룹 파일이 보일 조건이 맞을 때 cp_register_group <그룹 ID> "<1단계 문구>" 를 부르고, cp_group_<그룹 ID> 로 2단계를 엽니다.
# 등록 순서(= command-palette 의 _CP_GROUP_FILES 순서)가 1단계 메뉴 순서입니다.
_CP_GROUP_ORDER=()
declare -A _CP_GROUP_LABEL=()
cp_register_group() {
    _CP_GROUP_ORDER+=("$1")
    _CP_GROUP_LABEL[$1]="$2"
}

# 기존 세이브 데이터 로드용 유틸리티 (properties 기반)
get_state() {
    local label=$1
    local key=$2
    local full_key="${PROJ_KEY}.${label}.${key}"
    if [ -f "$STATE_FILE" ]; then
        grep "^${full_key}=" "$STATE_FILE" | cut -d'=' -f2-
    fi
}

save_state() {
    local label=$1
    local key=$2
    local val=$3
    local full_key="${PROJ_KEY}.${label}.${key}"

    touch "$STATE_FILE"

    local tmp
    tmp=$(mktemp)
    if [ -f "$STATE_FILE" ]; then
        grep -v "^${full_key}=" "$STATE_FILE" >"$tmp"
    fi
    echo "${full_key}=${val}" >>"$tmp"
    mv "$tmp" "$STATE_FILE"
}

# ==============================================================================
# OS 공통 클립보드 유틸리티 함수 (WSL / Linux)
# ==============================================================================

# 표준 입력을 클립보드에 복사 (개행 없이 그대로)
# ⚠️ bw-lib 의 copy_to_clipboard(인자로 문자열을 받음)와 이름이 겹치면 이 정의가 그것을 덮어써서,
#    bw-lib 의 clear_clipboard(copy_to_clipboard "") 같은 호출이 터미널 입력을 기다리며 멈춥니다. 이름을 분리합니다.
# 반환: 0 = 성공, 1 = 사용 가능한 클립보드 도구 없음
cp_copy_stdin_to_clipboard() {
    if $IS_WSL; then
        # WSL interop 으로 Windows 클립보드에 복사
        if command -v clip.exe &>/dev/null; then
            clip.exe
            return 0
        fi
    fi
    # 순수 Linux(WSL 제외): 디스플레이 서버별 클립보드 도구 순차 시도
    if command -v wl-copy &>/dev/null; then
        wl-copy
        return 0
    elif command -v xclip &>/dev/null; then
        xclip -selection clipboard
        return 0
    elif command -v xsel &>/dev/null; then
        xsel --clipboard --input
        return 0
    fi
    return 1
}

# 클립보드 내용을 표준 출력으로 반환 (끝 개행/캐리지리턴 제거)
# 반환: 0 = 성공(클립보드가 비어있어도 성공), 1 = 사용 가능한 클립보드 도구 없음
paste_from_clipboard() {
    if $IS_WSL; then
        if command -v powershell.exe &>/dev/null; then
            powershell.exe -NoProfile -Command "[Console]::Out.Write((Get-Clipboard -Raw))" 2>/dev/null | tr -d '\r\n'
            return 0
        fi
    fi
    if command -v wl-paste &>/dev/null; then
        wl-paste | tr -d '\r\n'
        return 0
    elif command -v xclip &>/dev/null; then
        xclip -selection clipboard -o | tr -d '\r\n'
        return 0
    elif command -v xsel &>/dev/null; then
        xsel --clipboard --output | tr -d '\r\n'
        return 0
    fi
    return 1
}

# ==============================================================================
# OS 공통 포트 유틸리티 함수 (근본적 Non-blocking /proc/net 직접 조회)
# ==============================================================================

# 10진수 포트 번호를 16진수 포트 표현으로 변환 (예: 8080 -> 1F90)
port_to_hex() {
    printf "%04X" "$1" 2>/dev/null
}

# 포트가 현재 열려(LISTEN) 있는지 외부 커맨드 없이 직접 확인
# 반환: 0 = 사용 중, 1 = 비어 있음
is_port_in_use() {
    local port="$1"

    # Linux / WSL2: 커널 /proc/net/tcp 텍스트 직접 조회 (외부 커맨드 0개, 멈춤 0%)
    local hex_port
    hex_port=$(port_to_hex "$port")

    # 로컬 주소(2번째 칸)의 포트와 상태(4번째 칸, 0A = LISTEN)를 정확히 비교합니다.
    # (줄 전체에서 ":포트 ... 0A" 를 찾으면 그 포트로 "접속한" 클라이언트 연결이나 다른 칸의 0A 도 걸림)
    local _f
    for _f in /proc/net/tcp /proc/net/tcp6; do
        if [[ -f "$_f" ]] && awk -v p=":${hex_port}" 'toupper(substr($2, length($2)-4)) == p && $4 == "0A" { found=1; exit } END { exit !found }' "$_f" 2>/dev/null; then
            return 0
        fi
    done

    # /proc 접근 불가 시 Linux 폴백
    if command -v ss &>/dev/null; then
        ss -tln 2>/dev/null | grep -qE ":${port}([[:space:]]|$)" &>/dev/null
    else
        return 1
    fi
}

# 지정한 포트를 사용 중인 PID 목록 반환
get_pids_by_port() {
    local port="$1"
    local pids=""

    # Linux / WSL2: lsof, ss, fuser 순차 시도
    # ⚠️ 반드시 LISTEN 소켓만 봅니다. "lsof -ti :PORT" 는 로컬/원격 포트를 모두 매칭해서
    #    그 포트로 "접속한 클라이언트"(예: 8080 백엔드로 프록시하는 vite 개발 서버)까지 종료합니다.
    if command -v lsof &>/dev/null; then
        pids=$(lsof -nP -ti tcp:"$port" -sTCP:LISTEN 2>/dev/null | sort -u)
    elif command -v ss &>/dev/null; then
        pids=$(ss -ltnp "sport = :$port" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | sort -u)
    elif command -v fuser &>/dev/null; then
        pids=$(fuser "$port/tcp" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | sort -u)
    fi

    echo "$pids"
}

# 지정한 포트를 사용 중인 프로세스 정보를 출력 (PID + 이름 + 명령어)
print_pids_info() {
    local pids="$1"

    for pid in $pids; do
        local pname pcmd
        pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "알 수 없음")
        pcmd=$(ps -p "$pid" -o args= 2>/dev/null | cut -c1-72 || echo "")
        echo "  PID: $pid  |  프로세스: $pname"
        [[ -n "$pcmd" ]] && echo "  명령어: $pcmd"
    done
}

# 지정한 PID 목록을 강제 종료하고 결과를 출력, 종료 건수와 실패 건수를 전역 변수에 저장
# 전역: KILLED, FAILED
kill_pids() {
    local pids="$1"
    KILLED=0
    FAILED=0

    # SIGTERM 으로 먼저 정상 종료(Spring 종료 훅·임시 파일 정리 등)를 기회를 주고,
    # 3초 안에 끝나지 않은 프로세스만 SIGKILL 합니다.
    for pid in $pids; do
        local pname
        pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "알 수 없음")
        kill -TERM "$pid" 2>/dev/null || true
        local _w=0
        while kill -0 "$pid" 2>/dev/null && [[ $_w -lt 30 ]]; do
            sleep 0.1
            ((_w++))
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
            sleep 0.2
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "  ✅ PID $pid ($pname) 종료 완료"
            ((KILLED++))
        else
            echo "  ❌ PID $pid ($pname) 종료 실패"
            ((FAILED++))
        fi
    done
}

# 포트 해제 여부를 재확인하고 결과 메시지 출력 (최대 wait_max 초 대기)
verify_port_released() {
    local port="$1"
    local wait_max="${2:-3}"
    local elapsed=0

    sleep 0.5
    while [[ $elapsed -lt $wait_max ]]; do
        local remaining
        remaining=$(get_pids_by_port "$port")
        [[ -z "$remaining" ]] && break
        sleep 1
        ((elapsed++))
    done

    local remaining
    remaining=$(get_pids_by_port "$port")
    if [[ -z "$remaining" ]]; then
        echo "✅ 포트 $port 가 정상적으로 해제되었습니다."
    else
        echo "⚠️  아직 포트 $port 를 점유하는 프로세스가 남아 있습니다: $remaining"
        echo "   sudo kill -9 $remaining 으로 강제 종료를 시도해 보세요."
    fi
}


# 현재 폴더가 Git 저장소인가 (하위 폴더에서 열어도 저장소 루트 기준)
_GIT_ROOT=""
command -v git >/dev/null 2>&1 && _GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)
# Linux 데스크톱(WSL 제외)에서 창을 띄울 수 있는가 — SSH 로 접속한 서버 등에서는 열기 항목을 숨김
_HAS_DESKTOP=false
[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && _HAS_DESKTOP=true

# GUI 앱을 팔레트와 떼어 놓고 실행 (팔레트가 끝나거나 Ctrl+C 로 중단해도 앱은 계속 실행, 출력은 터미널에 섞이지 않게)
_cp_detach() {
    if command -v setsid >/dev/null 2>&1; then
        setsid -f "$@" >/dev/null 2>&1 </dev/null
    else
        nohup "$@" >/dev/null 2>&1 </dev/null &
        disown 2>/dev/null || true
    fi
}

# 1단계 그룹 문구용 — 실제로 있는 항목 이름을 " · " 로 이어 출력 (예: _cp_join_kw 탐색기 "VS Code" Zed → "탐색기 · VS Code · Zed")
# 설치된 도구에 따라 항목이 달라지는 그룹(🧰 외부 도구 · 🤖 AI)이 씁니다.
_cp_join_kw() {
    local _s
    _s=$(printf ' · %s' "$@")
    printf '%s' "${_s# · }"
}

# 2단계 항목 선택 — 고른 항목의 ID 를 출력 (Esc 면 빈 문자열)
# 사용법: _pick_leaf "<프롬프트>" "ID<TAB>문구" ...
#   항목이 하나뿐인 그룹은 2단계 메뉴를 띄우지 않고 바로 그 항목을 고릅니다.
_pick_leaf() {
    local _prompt="$1" _sel
    shift
    if [ "$#" -eq 1 ]; then
        printf '%s' "${1%%$'\t'*}"
        return 0
    fi
    _sel=$(printf '%s\n' "$@" | fzf --delimiter=$'\t' --with-nth=2 --prompt="$_prompt" --header="Esc: 메뉴로" --height=40% --reverse) || true
    printf '%s' "${_sel%%$'\t'*}"
}
