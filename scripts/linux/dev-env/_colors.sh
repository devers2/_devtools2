#!/bin/bash
# ==============================================================================
# _colors.sh — 공통 ANSI 색상/스피너 헬퍼 함수
# PowerShell 스크립트와 동일한 색상 체계를 bash 스크립트에서 사용합니다.
#
# 사용법:
#   source "$(dirname "$(readlink -f "$0")")/_colors.sh"
# ==============================================================================

# ANSI 색상 코드 (터미널 미지원 환경에서 비활성화)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
    _C_RESET=$'\033[0m'
    _C_BOLD=$'\033[1m'
    _C_CYAN=$'\033[0;36m'       # [정보] / 구분선 / Step 헤더
    _C_GREEN=$'\033[0;32m'      # [성공] [완료]
    _C_YELLOW=$'\033[0;33m'     # [경고]
    _C_RED=$'\033[0;31m'        # [오류]
    _C_WHITE=$'\033[1;37m'      # 일반 강조
    _C_GRAY=$'\033[0;90m'       # 보조 설명
    _C_DEFAULT=$'\033[1;32m'    # 기본값 강조 (초록+볼드) — [기본값] 태그 및 선택 프롬프트 기본값 문자에 사용
else
    _C_RESET='' _C_BOLD='' _C_CYAN='' _C_GREEN='' _C_YELLOW=''
    _C_RED='' _C_WHITE='' _C_GRAY='' _C_DEFAULT=''
fi

# ── 출력 헬퍼 ──────────────────────────────────────────────────────────────
print_info()    { printf "${_C_CYAN}[정보]${_C_RESET} %s\n"    "$*"; }
print_success() { printf "${_C_GREEN}[성공]${_C_RESET} %s\n"   "$*"; }
print_done()    { printf "${_C_GREEN}[완료]${_C_RESET} %s\n"   "$*"; }
print_warn()    { printf "${_C_YELLOW}[경고]${_C_RESET} %s\n"  "$*"; }
print_error()   { printf "${_C_RED}[오류]${_C_RESET} %s\n"     "$*" >&2; }
print_step()    { printf "${_C_CYAN}%s${_C_RESET}\n"         "$*"; }
print_sep()     { printf "${_C_CYAN}%s${_C_RESET}\n" "==========================================================================="; }
print_subsep()  { printf "${_C_CYAN}%s${_C_RESET}\n" "---------------------------------------------------------------------------"; }

# ── 프롬프트 / 질문 헬퍼 ──────────────────────────────────────────────
print_question() { printf "${_C_BOLD}${_C_CYAN}%s${_C_RESET}\n" "$*"; }
print_option() {
    local num="$1" text="$2" default_tag="${3:-}"
    if [ -n "$default_tag" ]; then
        printf "   ${_C_YELLOW}${_C_BOLD}%s)${_C_RESET} ${_C_WHITE}%s${_C_RESET} ${_C_DEFAULT}%s${_C_RESET}\n" "$num" "$text" "$default_tag"
    else
        printf "   ${_C_YELLOW}${_C_BOLD}%s)${_C_RESET} ${_C_WHITE}%s${_C_RESET}\n" "$num" "$text"
    fi
}
prompt_input() { printf "${_C_YELLOW}${_C_BOLD}%s${_C_RESET} " "$*"; }

# ── 스피너 ─────────────────────────────────────────────────────────────────
# 사용법: run_with_spinner <label> <pid>
#         run_with_spinner_cmd <label> <command...>
_spinner_frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

run_with_spinner() {
    local label="$1"
    local pid="$2"
    local i=0 n=${#_spinner_frames[@]}
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${_C_CYAN}  [%s]${_C_RESET} %s" "${_spinner_frames[i]}" "$label"
        i=$(( (i + 1) % n ))
        sleep 0.15
    done
    printf "\r\033[K"
}

# 명령을 백그라운드로 실행하고 스피너를 표시한 후 exit code를 반환
# 사용법: run_with_spinner_cmd "레이블" cmd arg1 arg2 ...
# 반환: $?
run_with_spinner_cmd() {
    local label="$1"; shift
    "$@" &
    local pid=$!
    run_with_spinner "$label" "$pid"
    wait "$pid"
}

# 라벨 없이 커서 자리에서 제자리 회전만 하는 미니 스피너 (백스페이스 방식)
# echo -n "...진행 중" 뒤에 이어 붙여서 쓰는 용도. 2.install-core-tools.sh, 3.install-cli-tools.sh 등
# 다운로드/압축 해제처럼 짧은 메시지 뒤에 바로 붙는 스피너에 사용합니다.
# 사용법: cmd & show_spinner $!
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
