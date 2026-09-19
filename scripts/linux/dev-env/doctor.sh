#!/usr/bin/env bash
# ==============================================================================
# DevTools2 환경 상태 진단 도구 (doctor.sh)
#
# 목적:
#   - 환경 변수, PATH, 심볼릭 링크, 보안 권한, 도구 설치 버전을 한눈에 점검
#   - 설치 완료 단계 및 GitHub Actions CI에서 일관된 검증 자동화 도구로 사용
#
# 반환 코드:
#   0 : 모든 필수 항목 정상
#   1 : 1개 이상의 필수 항목 결함 발견
# ==============================================================================

set -u

# 색상 정의
_C_RESET="\033[0m"
_C_BOLD="\033[1m"
_C_GREEN="\033[32m"
_C_YELLOW="\033[33m"
_C_RED="\033[31m"
_C_CYAN="\033[36m"

pass_count=0
warn_count=0
fail_count=0

check_pass() {
    printf "  ${_C_GREEN}✓ [정상]${_C_RESET} %s\n" "$*"
    pass_count=$((pass_count + 1))
}

check_warn() {
    printf "  ${_C_YELLOW}⚠️  [경고]${_C_RESET} %s\n" "$*"
    warn_count=$((warn_count + 1))
}

check_fail() {
    printf "  ${_C_RED}❌ [오류]${_C_RESET} %s\n" "$*"
    fail_count=$((fail_count + 1))
}

print_section() {
    echo ""
    printf "${_C_BOLD}${_C_CYAN}── %s ──${_C_RESET}\n" "$*"
}

echo ""
echo "==========================================================================="
printf "  ${_C_BOLD}${_C_CYAN}🔍 DevTools2 종합 환경 진단 (doctor.sh)${_C_RESET}\n"
echo "==========================================================================="

# devtools2 환경 변수 로더가 존재하면 먼저 로드하여 진단 세션에 적용
if [ -f "$HOME/.config/devtools2/env.sh" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.config/devtools2/env.sh" 2>/dev/null || true
fi

# ── 1. 핵심 환경 변수 및 경로 진단 ──────────────────────────────────────────
print_section "1. 환경 변수 및 최상위 경로"

DEVTOOLS2="${DEVTOOLS2:-/var/opt/_devtools2}"
if [ -d "$DEVTOOLS2" ]; then
    check_pass "DEVTOOLS2 디렉터리 존재: $DEVTOOLS2"
else
    check_fail "DEVTOOLS2 디렉터리가 존재하지 않습니다: $DEVTOOLS2"
fi

for _var in JAVA_HOME NODE_HOME PYTHON_HOME NEOVIM_HOME; do
    _val="${!_var:-}"
    if [ -n "$_val" ]; then
        if [ -d "$_val" ]; then
            check_pass "$_var = $_val"
        else
            check_warn "$_var = $_val (디렉터리가 실제로 존재하지 않음)"
        fi
    else
        check_warn "$_var 환경변수가 현재 셸에 설정되어 있지 않습니다."
    fi
done

# PATH 내 DevTools2 경로 확인
if echo "$PATH" | grep -q "_devtools2"; then
    check_pass "PATH 환경 변수에 DevTools2 도구 경로가 포함되어 있습니다."
else
    check_warn "PATH 에 DevTools2 도구 경로가 누락되었습니다. (~/.bashrc 적용 필요)"
fi

# ── 2. 심볼릭 링크 무결성 진단 ──────────────────────────────────────────────
print_section "2. 설정 및 데이터 심볼릭 링크"

_links=(
    "$HOME/.config/nvim:$DEVTOOLS2/.config/nvim:Neovim 설정"
    "$HOME/.config/zed:$DEVTOOLS2/.config/zed:Zed 설정"
    "$HOME/.config/lazygit:$DEVTOOLS2/.config/lazygit:Lazygit 설정"
    "$HOME/.gradle/caches:$DEVTOOLS2/data/.gradle/caches:Gradle 캐시"
    "$HOME/.m2:$DEVTOOLS2/data/.m2:Maven 저장소"
)

# VS Code 설정 링크 검사
if [ -d "$HOME/.vscode-server/data/Machine" ]; then
    _links+=("$HOME/.vscode-server/data/Machine/settings.json:$DEVTOOLS2/.config/vscode/settings.json:VS Code Server 설정")
fi
if [ -d "$HOME/.config/Code/User" ]; then
    _links+=("$HOME/.config/Code/User/settings.json:$DEVTOOLS2/.config/vscode/settings.json:VS Code User 설정")
fi

for _entry in "${_links[@]}"; do
    _link=$(echo "$_entry" | cut -d: -f1)
    _target=$(echo "$_entry" | cut -d: -f2)
    _desc=$(echo "$_entry" | cut -d: -f3)

    if [ -L "$_link" ]; then
        _actual_target=$(readlink -f "$_link" 2>/dev/null || true)
        if [ -e "$_actual_target" ]; then
            check_pass "$_desc: $_link -> $_actual_target"
        else
            check_fail "$_desc: 깨진(dangling) 심볼릭 링크 발견! ($_link -> $_target)"
        fi
    elif [ -e "$_link" ]; then
        check_warn "$_desc: 심볼릭 링크가 아닌 일반 파일/디렉터리입니다: $_link"
    else
        check_warn "$_desc: 대상 링크가 아직 생성되지 않았습니다: $_link"
    fi
done

# ── 3. 보안 및 권한 진단 ──────────────────────────────────────────────────
print_section "3. 보안 및 권한 점검"

# 1) 잔존 sudoers 검사
_current_user="${USER:-$(id -un 2>/dev/null || true)}"
if [ -f "/etc/sudoers.d/$_current_user" ]; then
    check_fail "임시 passwordless sudo 설정이 회수되지 않고 남아있습니다: /etc/sudoers.d/$_current_user"
else
    check_pass "임시 sudoers 잔존 파일 없음 (/etc/sudoers.d/$_current_user 안전)"
fi

# 2) 비밀 파일 권한 검사 (rclone.conf, SSH 키, 토큰 등)
_sensitive_found=0
_sensitive_insecure=0

while IFS= read -r _file; do
    [ -z "$_file" ] && continue
    _sensitive_found=$((_sensitive_found + 1))
    _perm=$(stat -c "%a" "$_file" 2>/dev/null || echo "???")
    if [ "$_perm" = "600" ] || [ "$_perm" = "400" ]; then
        check_pass "보안 민감 파일 권한 안전 ($_perm): $_file"
    else
        check_fail "보안 민감 파일 권한 과다 ($_perm, 600 필수): $_file"
        _sensitive_insecure=$((_sensitive_insecure + 1))
    fi
done < <(find "$DEVTOOLS2" -type f \( -name "rclone.conf" -o -name "*.key" -o \( -name "*.pem" ! -name "cacert.pem" \) -o -name "id_rsa*" -o -name "id_ed25519*" -o -name ".bw_session*" \) 2>/dev/null || true)

if [ "$_sensitive_found" -eq 0 ]; then
    check_pass "보안 민감 파일 점검: 현재 저장소 트리에 노출된 비밀 파일 없음"
fi

# 3) others 쓰기 가능 파일(world-writable) 검사
_ww_files=$(find "$DEVTOOLS2" -xdev -type f -perm -002 2>/dev/null | head -5 || true)
if [ -n "$_ww_files" ]; then
    check_fail "World-writable(누구나 수정 가능) 파일 발견:\n$_ww_files"
else
    check_pass "World-writable 파일 없음"
fi

# ── 4. 핵심 도구 설치 및 버전 진단 ──────────────────────────────────────────
print_section "4. 핵심 도구 실행 및 버전"

_tools=(
    "git:git --version"
    "curl:curl --version | head -1"
    "tar:tar --version | head -1"
    "unzip:unzip -v | head -1"
    "node:node --version"
    "npm:npm --version"
    "python3:python3 --version"
    "pip:pip --version 2>/dev/null || python3 -m pip --version"
    "java:java --version | head -1"
    "gradle:gradle --version 2>/dev/null | grep -E '^Gradle ' || echo '미설치'"
    "nvim:nvim --version | head -1"
    "fzf:fzf --version"
    "rg:rg --version | head -1"
    "fd:fd --version 2>/dev/null || fdfind --version"
    "lazygit:lazygit --version | head -1"
)

for _entry in "${_tools[@]}"; do
    _cmd_name=$(echo "$_entry" | cut -d: -f1)
    _check_cmd=$(echo "$_entry" | cut -d: -f2)

    if command -v "$_cmd_name" >/dev/null 2>&1; then
        _ver_output=$(eval "$_check_cmd" 2>/dev/null || echo "실행 실패")
        check_pass "$_cmd_name: $_ver_output"
    else
        # DEVTOOLS2 modules 하위에 포터블로 존재하는지 재확인
        _found_mod=$(find "$DEVTOOLS2/modules" -maxdepth 3 -type f -name "$_cmd_name" -perm /111 2>/dev/null | head -1 || true)
        if [ -n "$_found_mod" ]; then
            _ver_output=$("$_found_mod" --version 2>/dev/null | head -1 || echo "버전 조회 불가")
            check_warn "$_cmd_name: 포터블 설치 확인됨($_found_mod) - PATH 미반영: $_ver_output"
        else
            check_warn "$_cmd_name: 도구가 설치되지 않았거나 PATH에서 찾을 수 없습니다."
        fi
    fi
done

# Adoptium 다중 JDK 설치 현황 점검
print_section "5. Adoptium 다중 JDK 설치 현황"
for _v in 8 17 21 25; do
    _dir="jdk-$_v"
    [ "$_v" = "8" ] && _dir="jdk-1.8"
    _jdk_bin="$DEVTOOLS2/modules/java/$_dir/bin/java"
    if [ -x "$_jdk_bin" ]; then
        _jver=$("$_jdk_bin" -version 2>&1 | head -1)
        check_pass "JDK $_v ($_dir): $_jver"
    else
        check_warn "JDK $_v ($_dir): 미설치 ($DEVTOOLS2/modules/java/$_dir)"
    fi
done

# ── 종합 결과 요약 ────────────────────────────────────────────────────────
echo ""
echo "==========================================================================="
printf "  ${_C_BOLD}진단 결과 요약: ${_C_GREEN}정상 %d${_C_RESET}, ${_C_YELLOW}경고 %d${_C_RESET}, ${_C_RED}오류 %d${_C_RESET}\n" \
    "$pass_count" "$warn_count" "$fail_count"
echo "==========================================================================="

if [ "$fail_count" -gt 0 ]; then
    printf "${_C_RED}❌ %d건의 결함이 발견되었습니다. 위 오류 메시지를 확인하세요.${_C_RESET}\n\n" "$fail_count"
    exit 1
else
    printf "${_C_GREEN}🎉 모든 필수 진단 항목을 통과했습니다.${_C_RESET}\n\n"
    exit 0
fi
