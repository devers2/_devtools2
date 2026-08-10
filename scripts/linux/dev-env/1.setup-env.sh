#!/bin/bash
# ==============================================================================
# [환경 변수 설정 스크립트: 1.setup-env.sh]
# - ~/.bashrc 에 DEVTOOLS2, PATH, 도구별 HOME 변수 등 사용자 환경 변수 자동 주입
# - WSL2 환경 감지 시 Ghostty 관련 PATH 제외
# ==============================================================================

set -euo pipefail

# DEVTOOLS2 경로 결정:
#   1순위: 외부에서 이미 주입된 DEVTOOLS2 환경변수 (온라인 실행 시 마스터 스크립트가 주입)
#   2순위: 현재 스크립트($0) 위치 기준 상대 경로 계산 (로컬 실행 시)
#   3순위: 표준 설치 경로 /var/opt/_devtools2 (fallback)
if [ -z "${DEVTOOLS2:-}" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")
fi
# 유효한 DEVTOOLS2 폴더가 아니면 표준 경로를 기본값으로 사용
if [ ! -f "$DEVTOOLS2/scripts/linux/dev-env/1.setup-env.sh" ]; then
    DEVTOOLS2="/var/opt/_devtools2"
fi

# 공통 색상/스피너 헬퍼 로드 (온라인 전용)
_load_colors() {
    [ -n "${_COLORS_LOADED:-}" ] && return 0

    # 캐시 우회 헤더 포함 (run_remote_script와 동일) — CDN이 방금 푸시 전 구버전을
    # 서빙하면 "진입 스크립트는 최신인데 _colors.sh만 구버전"이 될 수 있으므로 필수.
    # curl의 실제 실패 사유(stderr)를 버리지 않고 그대로 보여줘야 나중에 원인 진단이 가능하다.
    # 고정된 /tmp/_colors_remote.sh 경로를 쓰면, 이 스크립트를 실행하는 사용자가 바뀔 때
    # (예: 0.init은 root로, 1.setup-env는 일반 사용자로) /tmp의 sticky bit 때문에 이전
    # 실행자가 만든 파일을 지금 사용자가 덮어쓰지 못해 curl이 쓰기 실패(exit 23)한다
    # (실측으로 재현 확인). mktemp로 매번 고유한 파일을 만들어 이 충돌을 없앤다.
    local _tmpfile _curl_err _curl_ec=0
    _tmpfile=$(mktemp) || { echo "[오류] 임시 파일 생성에 실패했습니다." >&2; exit 1; }
    _curl_err=$(curl -sSfL --max-time 5 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env/_colors.sh" -o "$_tmpfile" 2>&1) || _curl_ec=$?
    if [ "$_curl_ec" -eq 0 ]; then
        # shellcheck disable=SC1090
        if source "$_tmpfile" 2>/dev/null; then
            rm -f "$_tmpfile"
            _COLORS_LOADED=true
            return 0
        fi
        rm -f "$_tmpfile"
        echo "[오류] _colors.sh를 다운로드했지만 source 실행 중 오류가 발생했습니다." >&2
        exit 1
    fi

    rm -f "$_tmpfile"
    echo "[오류] _colors.sh를 온라인에서 불러오지 못했습니다 (curl 종료 코드: $_curl_ec)." >&2
    [ -n "$_curl_err" ] && echo "  curl: $_curl_err" >&2
    echo "  네트워크 연결을 확인하세요." >&2
    exit 1
}
_load_colors

# WSL2 환경 감지: /proc/version에 'microsoft' 문자열이 포함되어 있으면 WSL2로 판단한다.
IS_WSL2=false
if grep -qi 'microsoft' /proc/version 2>/dev/null; then
    IS_WSL2=true
    # /etc/wsl.conf Interop 설정 보장 (Windows .exe 실행 보장)
    if [ -w /etc/wsl.conf ] || [ "$(id -u)" -eq 0 ]; then
        grep -q "\[interop\]" /etc/wsl.conf 2>/dev/null || printf "\n[interop]\nenabled=true\nappendWindowsPath=true\n" >> /etc/wsl.conf
    fi
    # binfmt_misc WSLInterop 복구 (Exec format error 예방)
    if [ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ] && [ -w /proc/sys/fs/binfmt_misc/register ]; then
        echo ':WSLInterop:M::MZ::/init:' > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
    fi
fi

# --- [권한 체크] 시스템 설정 권한 확인
echo ""
print_sep
print_info "사용자 권한으로 실행 중 -> 사용자 환경 변수(~/.bashrc)에 추가합니다."
echo ""

# 새 환경 변수 블록을 임시 파일에 먼저 완전히 다 작성한 뒤, 마지막에 한 번에
# ~/.bashrc로 옮겨 붙인다. 이렇게 하면 중간에 쓰기가 실패(디스크 풀 등)해도
# 기존 ~/.bashrc의 DEVTOOLS2 블록이 삭제되지 않고 그대로 보존된다.
_DEVTOOLS2_ENV_TMP=$(mktemp)
trap 'rm -f "$_DEVTOOLS2_ENV_TMP"' EXIT

echo "# === DEVTOOLS2 환경 변수 시작 ===" >>"$_DEVTOOLS2_ENV_TMP"

print_subsep
print_step "[Step 1] HOME 변수 등록 및 시스템 PATH 최적화"
# DEVTOOLS2 변수는 스크립트 실행 시 동적으로 계산된 절대 경로를 주입한다.
echo "export DEVTOOLS2=\"$DEVTOOLS2\"" >>"$_DEVTOOLS2_ENV_TMP"
echo "" >>"$_DEVTOOLS2_ENV_TMP"

# --- [설정부] 각 도구의 물리적 경로 설정
# 환경 변수는 보안 문제로 심볼릭 링크가 아닌 실제 경로를 사용한다.

# [Git 포터블 버전을 사용하지 않는 이유]
# Git은 리눅스 시스템 패키지 매니저(apt) 및 보안 인증서(SSL/TLS)와의 의존성이 깊게 얽혀 있어
# 윈도우처럼 포터블 폴더를 복사해 쓰면 오류가 발생하기 쉽다. 따라서 리눅스 환경에서는 제외하고
# 시스템에 전역 설치된 패키지(sudo apt install git)를 기본으로 사용한다.

# 나머지 설정들을 .bashrc 파일에 주입한다.
# cat << 'EOF' 구문을 사용하면 내부의 $ 기호 등이 치환되지 않고 텍스트 그대로 들어간다.
cat <<'EOF' >>"$_DEVTOOLS2_ENV_TMP"
export NODE_HOME="$DEVTOOLS2/modules/nodejs/node-v24"
export NPM_CONFIG_USERCONFIG="$DEVTOOLS2/.config/nodejs/.npmrc"

EOF

# NODE_PATH 설정
# Windows: $DEVTOOLS2/data/.npm-packages/node_modules
# Linux: $DEVTOOLS2/data/.npm-packages/lib/node_modules
cat <<'EOF' >>"$_DEVTOOLS2_ENV_TMP"
export NPM_CONFIG_PREFIX="$DEVTOOLS2/data/.npm-packages"
export NODE_PATH="$NPM_CONFIG_PREFIX/lib/node_modules"

export JAVA_HOME="$DEVTOOLS2/modules/java/jdk-21"

export GRADLE_HOME="$DEVTOOLS2/modules/gradle/gradle-9"

export PYTHON_HOME="$DEVTOOLS2/modules/python/python-314"
export PYTHONUSERBASE="$DEVTOOLS2/data/python"
export PIP_CACHE_DIR="$DEVTOOLS2/data/.cache/pip"

export NEOVIM_HOME="$DEVTOOLS2/modules/neovim/nvim"
export NVIM_APPNAME="nvim"
export ZED_HOME="$DEVTOOLS2/modules/zed"
export RCLONE_CONFIG="$DEVTOOLS2/modules/rclone/.config/rclone.conf"

# 한글 파일명 및 문자 깨짐 방지 (UTF-8 로케일)
export LANG="ko_KR.UTF-8"
export LC_ALL="ko_KR.UTF-8"

EOF

# Ghostty 환경 변수는 WSL2가 아닌 네이티브 리눅스 환경에서만 등록한다.
if [ "$IS_WSL2" = false ]; then
    cat <<'EOF' >>"$_DEVTOOLS2_ENV_TMP"
export GHOSTTY_HOME="$DEVTOOLS2/modules/ghostty"

EOF
else
    print_warn "WSL2 환경 감지: GHOSTTY_HOME 환경 변수 등록을 건너뜁니다."
fi

# 시스템 PATH 최적화 및 중복 제거
# 변수 우선순위를 위해 기존 $PATH의 앞부분에 새로운 경로들을 추가한다.
# WSL2 여부에 따라 GHOSTTY_HOME 경로 포함 여부를 다르게 처리한다.
if [ "$IS_WSL2" = false ]; then
    print_info "네이티브 리눅스 환경: Ghostty PATH를 포함하여 등록합니다."
    cat <<'EOF' >>"$_DEVTOOLS2_ENV_TMP"
export PATH="\
$NODE_HOME/bin:\
$NPM_CONFIG_PREFIX/bin:\
$JAVA_HOME/bin:\
$GRADLE_HOME/bin:\
$PYTHON_HOME/bin:\
$PYTHONUSERBASE/bin:\
$NEOVIM_HOME/bin:\
$ZED_HOME/bin:\
$DEVTOOLS2/data/nvim/lazy-rocks/hererocks/bin:\
$DEVTOOLS2/data/nvim/mason/bin:\
$DEVTOOLS2/scripts/linux/cmd:\
$GHOSTTY_HOME:\
$DEVTOOLS2/modules/ripgrep:\
$DEVTOOLS2/modules/fd:\
$DEVTOOLS2/modules/fzf:\
$DEVTOOLS2/modules/lazygit:\
$DEVTOOLS2/modules/ast-grep:\
$DEVTOOLS2/modules/bitwarden:\
$DEVTOOLS2/modules/rclone:\
$PATH"

EOF
else
    WIN_USERPROFILE=""
    if command -v cmd.exe >/dev/null 2>&1; then
        _raw_win_home=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' || true)
        if [ -n "$_raw_win_home" ] && command -v wslpath >/dev/null 2>&1; then
            WIN_USERPROFILE=$(wslpath "$_raw_win_home" 2>/dev/null || true)
        fi
    fi
    cat <<EOF >>"$_DEVTOOLS2_ENV_TMP"
export PATH="\
\$NODE_HOME/bin:\
\$NPM_CONFIG_PREFIX/bin:\
\$JAVA_HOME/bin:\
\$GRADLE_HOME/bin:\
\$PYTHON_HOME/bin:\
\$PYTHONUSERBASE/bin:\
\$NEOVIM_HOME/bin:\
\$DEVTOOLS2/data/nvim/lazy-rocks/hererocks/bin:\
\$DEVTOOLS2/data/nvim/mason/bin:\
\$DEVTOOLS2/scripts/linux/cmd:\
\$DEVTOOLS2/modules/ripgrep:\
\$DEVTOOLS2/modules/fd:\
\$DEVTOOLS2/modules/fzf:\
\$DEVTOOLS2/modules/lazygit:\
\$DEVTOOLS2/modules/ast-grep:\
\$DEVTOOLS2/modules/bitwarden:\
\$DEVTOOLS2/modules/rclone:\
\$DEVTOOLS2/modules/win32yank:\
\$PATH"

# Windows-mounted NTFS 디렉터리 배경색 수정 (WSL2에서 WezTerm Kanagawa 테마 가독성 확보)
if [ -n "\${LS_COLORS:-}" ]; then
    LS_COLORS=\$(echo "\$LS_COLORS" | sed "s/ow=[^:]*:/ow=01;37;48;5;24:/g; s/tw=[^:]*:/tw=01;37;48;5;58:/g")
    export LS_COLORS
fi

# 윈도우 사용자 홈 환경 변수 추가
export userprofile="$WIN_USERPROFILE"

EOF
fi

echo "# === DEVTOOLS2 환경 변수 끝 ===" >>"$_DEVTOOLS2_ENV_TMP"
echo "" >>"$_DEVTOOLS2_ENV_TMP"

# 새 블록이 완전히 준비된 지금 시점에만 기존 블록을 지우고 한 번에 이어붙인다.
sed -i '/# === DEVTOOLS2 환경 변수 시작 ===/,/# === DEVTOOLS2 환경 변수 끝 ===/d' ~/.bashrc
cat "$_DEVTOOLS2_ENV_TMP" >>~/.bashrc
rm -f "$_DEVTOOLS2_ENV_TMP"
trap - EXIT
echo ""

print_subsep
print_step "[Step 2] 로그인 쉘 연동 설정 (~/.bash_profile)"
# Ubuntu(DGX) 등 특정 환경에서 SSH 접속 시 .bashrc가 자동 로드되지 않는 문제 해결.
PROFILE_FILES=("$HOME/.bash_profile" "$HOME/.profile")
SOURCE_STR='if [ -f ~/.bashrc ]; then . ~/.bashrc; fi'

for P_FILE in "${PROFILE_FILES[@]}"; do
    if [ -f "$P_FILE" ]; then
        if ! grep -qF ". ~/.bashrc" "$P_FILE" && ! grep -qF "bashrc" "$P_FILE"; then
            echo -e "\n# Load .bashrc for login shells\n$SOURCE_STR" >>"$P_FILE"
            echo "[성공] $P_FILE 에 .bashrc 로드 로직을 추가했습니다."
        fi
    else
        # .bash_profile이 아예 없는 환경(Ubuntu 등)에서는 새로 생성한다.
        if [[ "$P_FILE" == "$HOME/.bash_profile" ]]; then
            echo -e "# Load .bashrc for login shells\n$SOURCE_STR" >"$P_FILE"
            echo "[성공] $P_FILE 을 생성하고 .bashrc 로드 로직을 추가했습니다."
        fi
    fi
done
echo ""

print_subsep
print_step "[Step 3] 에디터(Neovim, Zed) 설정: 심볼릭 링크 생성 및 권한 검사"
echo ""
# 공통 심볼릭 링크 유틸리티 스크립트 — 로컬에 없으면 GitHub에서 직접 스트리밍 실행
_SYMLINK_RAW="https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/cmd/create-symbolic-link.sh"
CMD_SYMLINK="$DEVTOOLS2/scripts/linux/cmd/create-symbolic-link.sh"
if [ -f "$CMD_SYMLINK" ]; then
    chmod +x "$CMD_SYMLINK" 2>/dev/null || true
fi

_run_symlink() {
    local target="$1" link="$2"
    # 개별 심볼릭 링크 하나가 실패해도(권한 문제 등) set -e로 전체 스크립트가
    # 중단되지 않도록 경고만 출력하고 계속 진행한다 (이후 PATH/Gradle 설정 등은 계속 필요함).
    if [ -f "$CMD_SYMLINK" ]; then
        "$CMD_SYMLINK" "$target" "$link" || print_warn "심볼릭 링크 생성 실패: $link -> $target (건너뛰고 계속 진행합니다)"
    else
        # 온라인 모드: create-symbolic-link.sh 를 GitHub에서 직접 스트리밍 실행 (bash -s 이용으로 /dev/fd 이슈 회피)
        curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_SYMLINK_RAW" | bash -s -- "$target" "$link" || print_warn "심볼릭 링크 생성 실패: $link -> $target (건너뛰고 계속 진행합니다)"
    fi
}

# config 대상 디렉터리 결정
if [ -n "${XDG_CONFIG_HOME:-}" ]; then
    cfg_dir="$XDG_CONFIG_HOME"
else
    cfg_dir="$HOME/.config"
fi

mkdir -p "$cfg_dir" 2>/dev/null || true

# --- Neovim 설정 ---
mkdir -p "$DEVTOOLS2/.config/nvim" 2>/dev/null || true
_run_symlink "$DEVTOOLS2/.config/nvim" "$cfg_dir/nvim"

# --- Zed 설정 ---
mkdir -p "$DEVTOOLS2/.config/zed" 2>/dev/null || true
# 1) 일반 패키지 / Native 설치 경로
_run_symlink "$DEVTOOLS2/.config/zed" "$cfg_dir/zed"

# 2) Flatpak 설치 경로 대응
flatpak_zed_dir="$HOME/.var/app/dev.zed.Zed/config"
if [ -d "$HOME/.var/app/dev.zed.Zed" ]; then
    mkdir -p "$flatpak_zed_dir" 2>/dev/null || true
    _run_symlink "$DEVTOOLS2/.config/zed" "$flatpak_zed_dir/zed"
fi

# --- VSCode 설정 (settings.json, keybindings.json, tasks.json) ---
mkdir -p "$DEVTOOLS2/.config/vscode" 2>/dev/null || true
[ ! -f "$DEVTOOLS2/.config/vscode/settings.json" ] && touch "$DEVTOOLS2/.config/vscode/settings.json" 2>/dev/null || true
[ ! -f "$DEVTOOLS2/.config/vscode/keybindings.json" ] && touch "$DEVTOOLS2/.config/vscode/keybindings.json" 2>/dev/null || true
[ ! -f "$DEVTOOLS2/.config/vscode/tasks.json" ] && touch "$DEVTOOLS2/.config/vscode/tasks.json" 2>/dev/null || true

if grep -qi microsoft /proc/version 2>/dev/null; then
    vscode_server_user="$HOME/.vscode-server/data/Machine"
    mkdir -p "$vscode_server_user" 2>/dev/null || true
    _run_symlink "$DEVTOOLS2/.config/vscode/settings.json" "$vscode_server_user/settings.json"
    _run_symlink "$DEVTOOLS2/.config/vscode/keybindings.json" "$vscode_server_user/keybindings.json"
    _run_symlink "$DEVTOOLS2/.config/vscode/tasks.json" "$vscode_server_user/tasks.json"
else
    mkdir -p "$cfg_dir/Code/User" 2>/dev/null || true
    _run_symlink "$DEVTOOLS2/.config/vscode/settings.json" "$cfg_dir/Code/User/settings.json"
    _run_symlink "$DEVTOOLS2/.config/vscode/keybindings.json" "$cfg_dir/Code/User/keybindings.json"
    _run_symlink "$DEVTOOLS2/.config/vscode/tasks.json" "$cfg_dir/Code/User/tasks.json"
fi

# data 대상 디렉터리 결정
if [ -n "${XDG_DATA_HOME:-}" ]; then
    nvim_data_dir="$XDG_DATA_HOME"
else
    nvim_data_dir="$HOME/.local/share"
fi

mkdir -p "$nvim_data_dir" 2>/dev/null || true
mkdir -p "$DEVTOOLS2/data/nvim" 2>/dev/null || true

_run_symlink "$DEVTOOLS2/data/nvim" "$nvim_data_dir/nvim"

# 대상에 대한 보안/권한 검사 함수
check_target() {
    t="$1"
    name="$2"
    if [ -e "$t" ]; then
        owner=$(stat -c '%U' "$t" 2>/dev/null || echo "?")
        group=$(stat -c '%G' "$t" 2>/dev/null || echo "?")
        mode=$(stat -c '%a' "$t" 2>/dev/null || echo "????")
        echo "[검사] $name: $t 소유자:$owner:$group 권한:$mode"
        if [ "$owner" != "$(id -un)" ]; then
            echo "  [경고] $name 소유자가 현재 사용자($(id -un))와 다릅니다. 필요시 sudo chown -R $(id -un):$(id -gn) $t"
        fi
        ww=$(find "$t" -xdev -type f -perm /o+w -print -quit 2>/dev/null || true)
        if [ -n "$ww" ]; then
            echo "  [위험] $name에 world-writable 파일 존재: $ww"
        else
            echo "  [확인] $name에 world-writable 파일 없음"
        fi
    else
        echo "[검사] $name 대상이 존재하지 않습니다: $t"
    fi
}

check_target "$DEVTOOLS2/.config/nvim" "Neovim config"
check_target "$DEVTOOLS2/.config/zed" "Zed config"
check_target "$DEVTOOLS2/data/nvim" "Neovim data"

echo "[완료] 에디터(Neovim, Zed) 설정: 심볼릭 링크 생성 및 권한 검사 완료"
echo ""

print_subsep
print_step "[Step 4] 폰트 설치"
echo ""
mkdir -p ~/.local/share/fonts
if [ -d "$DEVTOOLS2/assets/fonts" ]; then
    \cp -r "$DEVTOOLS2/assets/fonts/." ~/.local/share/fonts/ 2>/dev/null || true
fi
# 폰트 캐시 갱신
if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -fv >/dev/null 2>&1 || true
fi
echo "[완료] 폰트 설치 완료!"
echo ""

print_subsep
print_step "[Step 5] 레거시 설정 파일 정리"
echo ""
if [ -f "$HOME/.npmrc" ] && [ ! -L "$HOME/.npmrc" ]; then
    rm -f "$HOME/.npmrc"
    echo "[성공] 사용자 홈의 구형 .npmrc를 제거했습니다."
else
    echo "[확인] 정리할 구형 .npmrc 파일이 없습니다."
fi
echo ""

echo "---------------------------------------------------------------------------"
print_subsep
print_step "[Step 6] Gradle/Maven 심볼릭 링크 생성 (용량 최적화)"
echo ""

# Gradle 의 사용자 설정은 홈 디렉토리에 유지하고 용량이 큰 Caches 와 Wrapper 는 공용 저장소로 링크를 생성한다.
mkdir -p "$DEVTOOLS2/data/.gradle/caches" "$DEVTOOLS2/data/.gradle/wrapper" "$DEVTOOLS2/data/.m2"

_run_symlink "$DEVTOOLS2/data/.gradle/caches" "$HOME/.gradle/caches"
_run_symlink "$DEVTOOLS2/data/.gradle/wrapper" "$HOME/.gradle/wrapper"

# Maven Repository 를 공용 저장소로 링크를 생성한다.
_run_symlink "$DEVTOOLS2/data/.m2" "$HOME/.m2"

# 개발도구 바로가기 링크
_run_symlink "$DEVTOOLS2" "$HOME/_devtools2"

echo ""

print_subsep
print_step "[Step 7] Gradle 사용자 전역 설정 (gradle.properties)"
echo ""

GRADLE_PROPS="$HOME/.gradle/gradle.properties"
mkdir -p "$HOME/.gradle"

# 비표준 경로(DEVTOOLS2)의 JDK를 Gradle이 인식할 수 있도록 사용자 전역 설정에 주입한다.
# - org.gradle.java.installations.paths : 툴체인 탐색 경로 (컴파일용 JDK 8 등 비표준 경로 명시 필수)
GRADLE_INSTALLS_VAL="$DEVTOOLS2/modules/java/jdk-1.8,$DEVTOOLS2/modules/java/jdk-17,$DEVTOOLS2/modules/java/jdk-21,$DEVTOOLS2/modules/java/jdk-25"

inject_gradle_property() {
    local prop_key="$1"
    local prop_val="$2"
    local file="$3"
    if grep -q "^${prop_key}=" "$file" 2>/dev/null; then
        local current_val
        current_val=$(grep "^${prop_key}=" "$file" | sed "s|^${prop_key}=||")
        if [ "$current_val" = "$prop_val" ]; then
            echo "[확인] $prop_key 이미 올바르게 설정되어 있습니다."
        else
            sed -i "s|^${prop_key}=.*|${prop_key}=${prop_val}|" "$file"
            echo "[갱신] $prop_key 값을 업데이트했습니다."
        fi
    else
        echo "" >>"$file"
        echo "${prop_key}=${prop_val}" >>"$file"
        echo "[추가] $prop_key 설정을 추가했습니다."
    fi
}

touch "$GRADLE_PROPS"
inject_gradle_property "org.gradle.java.installations.paths" "$GRADLE_INSTALLS_VAL" "$GRADLE_PROPS"

echo "[완료] Gradle 사용자 전역 설정 적용 완료!"
echo ""

print_subsep
print_done "모든 설정이 완료되었습니다! (~/.bashrc 변수에 등록됨)"
echo "현재 터미널에 즉시 적용하려면 아래 명령어를 직접 입력하세요:"
echo "    source ~/.bashrc"
echo ""
echo "설정 확인 명령어:"
echo "    echo \$DEVTOOLS2"
echo "    echo \$PATH"
print_sep
echo ""
