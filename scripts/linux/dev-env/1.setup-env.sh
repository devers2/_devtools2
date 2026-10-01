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

# WSL2 환경 감지: /proc/version에 'microsoft' 문자열이 포함되어 있으면 WSL2로 판단한다.
IS_WSL2=false
if grep -qi 'microsoft' /proc/version 2>/dev/null; then
    IS_WSL2=true
    # /etc/wsl.conf Interop 설정 보장 (Windows .exe 실행 보장)
    if [ -w /etc/wsl.conf ] || [ "$(id -u)" -eq 0 ] || (command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null); then
        set_wsl_conf_key "interop" "enabled" "true" "/etc/wsl.conf"
        set_wsl_conf_key "interop" "appendWindowsPath" "true" "/etc/wsl.conf"
    fi
    # binfmt_misc WSLInterop 복구 (Exec format error 예방 — 공용 헬퍼)
    ensure_wsl_interop
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
# DEVTOOLS2 PATH 디렉터리 목록 (단일 원천)
# - env.sh(셸용)와 ~/.config/environment.d/devtools2.conf(systemd 사용자 서비스용)를 모두
#   이 목록 하나로 생성해 두 파일의 PATH 가 서로 어긋나지 않게 합니다.
# - 앞에 있을수록 우선순위가 높습니다. $DEVTOOLS2/$JAVA_HOME 등은 env.sh 안에서 해석됩니다.
_DT2_PATH_DIRS=(
    '$NODE_HOME/bin'
    '$NPM_CONFIG_PREFIX/bin'
    '$JAVA_HOME/bin'
    '$GRADLE_HOME/bin'
    '$PYTHON_HOME/bin'
    '$PYTHONUSERBASE/bin'
    '$NEOVIM_HOME/bin'
    '$DEVTOOLS2/data/nvim/lazy-rocks/hererocks/bin'
    '$DEVTOOLS2/data/nvim/mason/bin'
    '$DEVTOOLS2/scripts/linux/cmd'
    '$DEVTOOLS2/modules/ripgrep'
    '$DEVTOOLS2/modules/fd'
    '$DEVTOOLS2/modules/fzf'
    '$DEVTOOLS2/modules/lazygit'
    '$DEVTOOLS2/modules/ast-grep'
    '$DEVTOOLS2/modules/bitwarden'
    '$DEVTOOLS2/modules/rclone'
    '$DEVTOOLS2/modules/orca'
)

# 사용자별 로컬 설정(~/.config/devtools2/local.sh) 로더
# - jdk_switch.sh / py_switch.sh 가 고른 JDK·Python(DT2_JAVA_HOME / DT2_PYTHON_HOME)과
#   도구 설치 스크립트가 추가한 PATH(ensure_path_in_bashrc)가 여기에 저장됩니다.
# - env.sh 는 설치 스크립트가 매번 다시 만들지만 local.sh 는 건드리지 않으므로 선택이 유지됩니다.
cat <<'EOF' >>"$_DEVTOOLS2_ENV_TMP"
[ -f "$HOME/.config/devtools2/local.sh" ] && . "$HOME/.config/devtools2/local.sh"
# AI API 키 등 비밀 값 (저장소 밖, 소유자 전용 600 — 1.setup-env.sh 가 서식 파일을 만들어 둠)
[ -f "$HOME/.config/devtools2/secrets.env" ] && . "$HOME/.config/devtools2/secrets.env"

# PATH 앞에 디렉터리를 추가하되 이미 있으면 건너뜁니다(.profile 과 .bashrc 가 모두 이 파일을
# 읽거나, 셸 안에서 셸을 다시 띄워도 PATH 가 계속 길어지지 않도록).
_dt2_path_prepend() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1${PATH:+:$PATH}" ;;
    esac
}

export NODE_HOME="$DEVTOOLS2/modules/nodejs/node-v24"
export NPM_CONFIG_GLOBALCONFIG="$DEVTOOLS2/.config/nodejs/.npmrc"

EOF

# NODE_PATH 설정
# Windows: $DEVTOOLS2/data/.npm-packages/node_modules
# Linux: $DEVTOOLS2/data/.npm-packages/lib/node_modules
cat <<'EOF' >>"$_DEVTOOLS2_ENV_TMP"
export NPM_CONFIG_PREFIX="$DEVTOOLS2/data/.npm-packages"
export NODE_PATH="$NPM_CONFIG_PREFIX/lib/node_modules"

# jdk_switch.sh 로 고른 JDK(DT2_JAVA_HOME)가 있으면 그 값을, 없으면 기본 JDK 21 을 사용합니다.
if [ -n "${DT2_JAVA_HOME:-}" ] && [ -d "$DT2_JAVA_HOME" ]; then
    export JAVA_HOME="$DT2_JAVA_HOME"
else
    export JAVA_HOME="$DEVTOOLS2/modules/java/jdk-21"
fi

export GRADLE_HOME="$DEVTOOLS2/modules/gradle/gradle-9"

# py_switch.sh 로 고른 Python(DT2_PYTHON_HOME)이 있으면 그 값을, 없으면 기본 Python 3.14 를 사용합니다.
if [ -n "${DT2_PYTHON_HOME:-}" ] && [ -d "$DT2_PYTHON_HOME" ]; then
    export PYTHON_HOME="$DT2_PYTHON_HOME"
else
    export PYTHON_HOME="$DEVTOOLS2/modules/python/python-314"
fi
export PYTHONUSERBASE="$DEVTOOLS2/data/python"
export PIP_CACHE_DIR="$DEVTOOLS2/data/.cache/pip"

export NEOVIM_HOME="$DEVTOOLS2/modules/neovim/nvim"
export NVIM_APPNAME="nvim"
# rclone 설정(SFTP 비밀번호 포함)은 공유 트리가 아니라 사용자 홈에 둡니다(사용자별 격리, 600).
export RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf"
export PIP_CONFIG_FILE="$HOME/.pip/pip.conf"

# 한글 파일명 및 문자 깨짐 방지 (UTF-8 로케일 & Git gettext 한국어 활성화)
export LANG="ko_KR.UTF-8"
export LANGUAGE="ko_KR:ko"

EOF

# 시스템 코어 PATH (기본 공통 도구) — 목록의 뒤에서부터 앞에 붙여 목록 순서대로 우선순위가 정해집니다.
{
    echo "# 시스템 코어 PATH (기본 공통 도구, 중복 없이 앞에 추가)"
    for (( _i=${#_DT2_PATH_DIRS[@]}-1; _i>=0; _i-- )); do
        echo "_dt2_path_prepend \"${_DT2_PATH_DIRS[$_i]}\""
    done
    echo "export PATH"
    echo "unset -f _dt2_path_prepend"
    echo ""
} >>"$_DEVTOOLS2_ENV_TMP"

# WSL2 환경 추가 설정 (NTFS LS_COLORS 및 userprofile)
if [ "$IS_WSL2" = true ]; then
    WIN_USERPROFILE=""
    if command -v cmd.exe >/dev/null 2>&1; then
        _raw_win_home=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' || true)
        if [ -n "$_raw_win_home" ] && command -v wslpath >/dev/null 2>&1; then
            WIN_USERPROFILE=$(wslpath "$_raw_win_home" 2>/dev/null || true)
        fi
    fi
    cat <<EOF >>"$_DEVTOOLS2_ENV_TMP"
# Windows-mounted NTFS 디렉터리 배경색 수정 (WSL2에서 터미널 Kanagawa 테마 가독성 확보)
if [ -n "\${LS_COLORS:-}" ]; then
    LS_COLORS=\$(echo "\$LS_COLORS" | sed "s/ow=[^:]*:/ow=01;37;48;5;24:/g; s/tw=[^:]*:/tw=01;37;48;5;58:/g")
    export LS_COLORS
fi

# 윈도우 사용자 홈 환경 변수 추가
export userprofile="$WIN_USERPROFILE"

EOF
fi

# 환경별 추가 도구(Ghostty, Zed, win32yank) 경로를 env.sh에 직접 통합
if [ "$IS_WSL2" = false ]; then
    cat << 'EOF' >> "$_DEVTOOLS2_ENV_TMP"
case ":$PATH:" in *":$DEVTOOLS2/modules/ghostty:"*) ;; *) [ -d "$DEVTOOLS2/modules/ghostty" ] && export PATH="$DEVTOOLS2/modules/ghostty:$PATH" ;; esac
case ":$PATH:" in *":$DEVTOOLS2/modules/zed/bin:"*) ;; *) [ -d "$DEVTOOLS2/modules/zed/bin" ] && export PATH="$DEVTOOLS2/modules/zed/bin:$PATH" ;; esac
EOF
else
    cat << 'EOF' >> "$_DEVTOOLS2_ENV_TMP"
case ":$PATH:" in *":$DEVTOOLS2/modules/win32yank:"*) ;; *) [ -d "$DEVTOOLS2/modules/win32yank" ] && export PATH="$DEVTOOLS2/modules/win32yank:$PATH" ;; esac
EOF
fi

echo "# === DEVTOOLS2 환경 변수 끝 ===" >>"$_DEVTOOLS2_ENV_TMP"
echo "" >>"$_DEVTOOLS2_ENV_TMP"

# 1) ~/.config/devtools2/env.sh 독립 환경 파일 생성
mkdir -p "$HOME/.config/devtools2"
_TARGET_ENV="$HOME/.config/devtools2/env.sh"
cat "$_DEVTOOLS2_ENV_TMP" > "$_TARGET_ENV"
chmod 644 "$_TARGET_ENV"
rm -f "$_DEVTOOLS2_ENV_TMP"
trap - EXIT
print_done "독립 환경 설정 파일 생성 완료: $_TARGET_ENV"

# 1-1) AI API 키 등 비밀 값 전용 파일 (~/.config/devtools2/secrets.env)
# - 저장소(공개 GitHub) 밖에 두고 소유자만 읽을 수 있게(600) 만듭니다. env.sh 가 이 파일을 읽으므로
#   셸·Neovim(CodeCompanion)·orca serve(래퍼가 env.sh 를 읽음) 모두 같은 키를 씁니다.
# - 이미 있으면 내용은 건드리지 않고 권한만 600 으로 맞춥니다(멱등).
# - environment.d(systemd 전역 환경)에는 키를 넣지 않습니다: generate_environment_d 는 정해진 변수만 옮겨 적습니다.
_SECRETS_ENV="$HOME/.config/devtools2/secrets.env"
if [ ! -f "$_SECRETS_ENV" ]; then
    (umask 077 && cat > "$_SECRETS_ENV" <<'EOF'
# ==============================================================================
# DevTools2 비밀 값 (AI API 키 등) — 이 파일은 저장소 밖에 있고 소유자만 읽을 수 있습니다(600).
# env.sh 가 로그인할 때마다 읽습니다. 필요한 줄의 # 을 지우고 값을 채운 뒤 새 셸을 여세요.
# orca serve 에 반영하려면: systemctl --user restart orca-serve.service
# ⚠️ 키를 저장소 안(.config, scripts 등) 파일에 직접 적지 마세요(공개 저장소에 올라갈 수 있음).
# ==============================================================================
# export ANTHROPIC_API_KEY=''
# export OPENAI_API_KEY=''
# export GEMINI_API_KEY=''
# export GITHUB_TOKEN=''      # GitHub API 호출 한도 완화(설치 스크립트의 SHA256 조회 등)
EOF
    )
    print_done "비밀 값 파일 생성 완료(권한 600): $_SECRETS_ENV"
fi
chmod 600 "$_SECRETS_ENV" 2>/dev/null || true

# 1-2) 비밀 정보 커밋 차단 훅 활성화 (scripts/git-hooks/pre-commit)
# - 공개 저장소에 키·토큰·인증 파일이 실수로 커밋되지 않도록 커밋 직전에 검사합니다.
# - 사용자가 이미 다른 hooksPath 를 쓰고 있으면 덮어쓰지 않습니다(멱등, 기존 설정 보존).
if [ -d "$DEVTOOLS2/.git" ] && [ -f "$DEVTOOLS2/scripts/git-hooks/pre-commit" ]; then
    _cur_hooks=$(git -C "$DEVTOOLS2" config --get core.hooksPath 2>/dev/null || true)
    if [ -z "$_cur_hooks" ]; then
        if git -C "$DEVTOOLS2" config core.hooksPath scripts/git-hooks 2>/dev/null; then
            print_done "비밀 정보 커밋 차단 훅 활성화: $DEVTOOLS2/scripts/git-hooks/pre-commit"
        fi
    elif [ "$_cur_hooks" != "scripts/git-hooks" ]; then
        print_warn "git core.hooksPath 가 이미 '$_cur_hooks' 로 설정되어 있어 비밀 정보 차단 훅을 연결하지 않았습니다."
    fi
fi

# 2) systemd 사용자 서비스 및 데스크톱 앱 연동용 ~/.config/environment.d/devtools2.conf 생성
# environment.d 는 셸 문법을 쓸 수 없으므로(KEY=VALUE + ${VAR} 확장만 지원), 방금 만든 env.sh 를
# 깨끗한 bash 에서 실제로 실행해 나온 값을 그대로 옮겨 적습니다. 그래야 env.sh 와 PATH 목록,
# local.sh 의 JDK/Python 선택이 항상 같습니다.
mkdir -p "$HOME/.config/environment.d"
generate_environment_d() {
    env -i HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin" bash --noprofile --norc -c '
        . "$HOME/.config/devtools2/env.sh" >/dev/null 2>&1
        for k in DEVTOOLS2 NODE_HOME JAVA_HOME GRADLE_HOME PYTHON_HOME PYTHONUSERBASE NEOVIM_HOME \
                 NPM_CONFIG_GLOBALCONFIG NPM_CONFIG_PREFIX NODE_PATH RCLONE_CONFIG LANG; do
            printf "%s=%s\n" "$k" "${!k}"
        done
        # 기본 시스템 경로는 빼고 DEVTOOLS2 쪽 경로만 앞에 붙인 뒤 기존 PATH 를 이어 붙입니다.
        printf "PATH=%s\${PATH}\n" "${PATH%/usr/local/bin:/usr/bin:/bin}"
    ' > "$HOME/.config/environment.d/devtools2.conf"
}
generate_environment_d
chmod 644 "$HOME/.config/environment.d/devtools2.conf"
print_done "systemd 사용자 환경 설정 생성 완료: ~/.config/environment.d/devtools2.conf"

# 3) ~/.bashrc 정리 및 맨 위 로더 주입
# 기존에 ~/.bashrc 끝에 들어가 있던 거대 블록 삭제
sed -i '/# === DEVTOOLS2 환경 변수 시작 ===/,/# === DEVTOOLS2 환경 변수 끝 ===/d' ~/.bashrc 2>/dev/null || true

# 비대화형 가드([ -z "$PS1" ] && return 등)보다 앞선 파일 맨 처음에 로더 주입
_LOADER_LINE='[ -f "$HOME/.config/devtools2/env.sh" ] && . "$HOME/.config/devtools2/env.sh"'
if ! grep -qF "devtools2/env.sh" ~/.bashrc 2>/dev/null; then
    if [ -f ~/.bashrc ]; then
        _TMP_RC=$(mktemp)
        echo "# === DEVTOOLS2 환경 변수 로더 (대화형/비대화형 공통) ===" > "$_TMP_RC"
        echo "$_LOADER_LINE" >> "$_TMP_RC"
        echo "" >> "$_TMP_RC"
        cat ~/.bashrc >> "$_TMP_RC"
        mv -f "$_TMP_RC" ~/.bashrc
    else
        echo "# === DEVTOOLS2 환경 변수 로더 (대화형/비대화형 공통) ===" > ~/.bashrc
        echo "$_LOADER_LINE" >> ~/.bashrc
    fi
    print_done "~/.bashrc 맨 앞에 환경 로더를 등록했습니다 (비대화형 셸 지원)."
fi

print_subsep
print_step "[Step 2] 셸(readline) 단축키 바인딩 (~/.bashrc)"
# bind -x 는 대화형 bash 전용이므로 ~/.bashrc 에 idempotent 하게 주입한다.
# TUI(nvim, lazygit 등) 안에서 키 문자열이 그대로 새지 않고,
# VSCode·IntelliJ 내장 터미널을 포함한 모든 bash 세션에서 동작한다.
_BIND_BLOCK_START='# === DEVTOOLS2 readline 단축키 시작 ==='
_BIND_BLOCK_END='# === DEVTOOLS2 readline 단축키 끝 ==='

# 기존 블록 제거 후 재주입 (멱등성 보장)
sed -i "/$_BIND_BLOCK_START/,/$_BIND_BLOCK_END/d" ~/.bashrc 2>/dev/null || true

cat >> ~/.bashrc << 'BIND_EOF'
# === DEVTOOLS2 readline 단축키 시작 ===
# Alt+c : 명령 팔레트 (command-palette)
# Alt+h : 서버 관리자 (bw-server-manager)
# bind -x 는 대화형 bash 전용 — PS1 이 있을 때만(대화형 셸) 등록한다.
if [ -n "${PS1:-}" ]; then
    bind -x '"\ec": "$DEVTOOLS2/scripts/fzf/command-palette"' 2>/dev/null || true
    bind -x '"\eh": "$DEVTOOLS2/scripts/fzf/bw-server-manager"'  2>/dev/null || true
fi
# === DEVTOOLS2 readline 단축키 끝 ===
BIND_EOF

print_done "~/.bashrc 에 readline 단축키 바인딩을 등록했습니다 (Alt+c, Alt+h)."
echo ""

print_subsep
print_step "[Step 3] 로그인 쉘 연동 설정 (~/.profile)"
# 4) ~/.profile 연동
if [ -f "$HOME/.profile" ]; then
    if ! grep -qF "devtools2/env.sh" "$HOME/.profile" 2>/dev/null; then
        echo -e "\n# === DEVTOOLS2 환경 변수 로더 ===\n$_LOADER_LINE" >> "$HOME/.profile"
        print_done "~/.profile 에 환경 로더를 등록했습니다."
    fi
fi

# 5) ~/.bash_profile 정리 (.profile 가림 방지)
# Ubuntu 등에서는 ~/.bash_profile 이 존재하면 기본 ~/.profile (~/.local/bin PATH 등)을 읽지 않음.
if [ -f "$HOME/.bash_profile" ]; then
    if grep -qF "Load .bashrc for login shells" "$HOME/.bash_profile" 2>/dev/null; then
        rm -f "$HOME/.bash_profile"
        print_info "Ubuntu 기본 ~/.profile 을 우선하도록 자동 생성되었던 ~/.bash_profile 을 정리했습니다."
    else
        if ! grep -qF ". ~/.profile" "$HOME/.bash_profile" 2>/dev/null; then
            echo -e "\n# Load ~/.profile to preserve default PATH\n[ -f ~/.profile ] && . ~/.profile" >> "$HOME/.bash_profile"
        fi
    fi
fi

print_subsep
print_step "[Step 4] 에디터(Neovim, Zed) 설정: 심볼릭 링크 생성 및 권한 검사"
echo ""
# 공통 심볼릭 링크 유틸리티 스크립트 — 로컬에 없으면 GitHub에서 직접 스트리밍 실행
_SYMLINK_RAW="https://raw.githubusercontent.com/devers2/_devtools2/${DT2_REF:-main}/scripts/linux/cmd/create-symbolic-link.sh"
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

# --- Lazygit 설정 ---
mkdir -p "$DEVTOOLS2/.config/lazygit" 2>/dev/null || true
_run_symlink "$DEVTOOLS2/.config/lazygit" "$cfg_dir/lazygit"

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
print_step "[Step 5] 폰트 설치"
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
print_step "[Step 5-1] rclone 설정 파일을 사용자 홈으로 이전"
# 예전 위치($DEVTOOLS2/modules/rclone/.config/rclone.conf, 공유 트리)에 내 소유 설정이 있고
# 새 위치(~/.config/rclone/rclone.conf)에 아직 없으면 옮긴 뒤, 기존 systemd 마운트 유닛의
# --config= 경로가 계속 동작하도록 예전 위치에는 새 파일을 가리키는 심볼릭 링크를 남깁니다.
_RCLONE_NEW="$HOME/.config/rclone/rclone.conf"
_RCLONE_OLD="$DEVTOOLS2/modules/rclone/.config/rclone.conf"
mkdir -p "$(dirname "$_RCLONE_NEW")" && chmod 700 "$(dirname "$_RCLONE_NEW")" 2>/dev/null || true
if [ -f "$_RCLONE_OLD" ] && [ ! -L "$_RCLONE_OLD" ] && [ -O "$_RCLONE_OLD" ] && [ ! -e "$_RCLONE_NEW" ]; then
    if mv "$_RCLONE_OLD" "$_RCLONE_NEW" && chmod 600 "$_RCLONE_NEW"; then
        ln -s "$_RCLONE_NEW" "$_RCLONE_OLD" 2>/dev/null || true
        print_done "rclone.conf 를 사용자 홈으로 옮겼습니다: $_RCLONE_NEW"
        # 예전 위치에 있던 SSH 키 디렉터리도 함께 이전 (bw-server-manager 의 rclone 마운트용 키)
        if [ -d "$(dirname "$_RCLONE_OLD")/keys" ] && [ ! -e "$(dirname "$_RCLONE_NEW")/keys" ]; then
            mv "$(dirname "$_RCLONE_OLD")/keys" "$(dirname "$_RCLONE_NEW")/keys" 2>/dev/null \
                && sed -i "s|$(dirname "$_RCLONE_OLD")/keys/|$(dirname "$_RCLONE_NEW")/keys/|g" "$_RCLONE_NEW" 2>/dev/null || true
        fi
    else
        print_warn "rclone.conf 이전에 실패했습니다(기존 위치 유지): $_RCLONE_OLD"
    fi
elif [ -f "$_RCLONE_OLD" ] && [ ! -L "$_RCLONE_OLD" ] && [ -e "$_RCLONE_NEW" ]; then
    print_warn "rclone.conf 가 두 곳에 있습니다. 예전 공유 위치($_RCLONE_OLD)는 확인 후 지워 주세요."
fi
echo ""

print_subsep
print_step "[Step 6] 사용자 npmrc 권한 및 레거시 설정 검사"
echo ""
if [ -f "$HOME/.npmrc" ]; then
    chmod 600 "$HOME/.npmrc" 2>/dev/null || true
    echo "[안내] 사용자 홈의 .npmrc 권한을 소유자 전용(600)으로 안전하게 설정했습니다."
    echo "       (개인 npm 인증 토큰은 홈 디렉터리에 안전하게 보관됩니다)"
else
    echo "[확인] 사용자 홈에 .npmrc 파일이 없습니다. (글로벌 공용 설정 사용 중)"
fi
echo ""

echo "---------------------------------------------------------------------------"
print_subsep
print_step "[Step 7] Gradle/Maven 심볼릭 링크 생성 (용량 최적화)"
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
print_step "[Step 8] Gradle 사용자 전역 설정 (gradle.properties)"
echo ""

GRADLE_PROPS="$HOME/.gradle/gradle.properties"
mkdir -p "$HOME/.gradle"

# 비표준 경로(DEVTOOLS2)의 JDK를 Gradle이 인식할 수 있도록 사용자 전역 설정에 주입한다.
# - org.gradle.java.installations.paths : 툴체인 탐색 경로 (컴파일용 JDK 8 등 비표준 경로 명시 필수)
_detected_jdks=""
if [ -d "$DEVTOOLS2/modules/java" ]; then
    _detected_jdks=$(find "$DEVTOOLS2/modules/java" -mindepth 1 -maxdepth 1 -type d -name "jdk-*" 2>/dev/null | sort -V | paste -sd, - || true)
fi
if [ -n "$_detected_jdks" ]; then
    GRADLE_INSTALLS_VAL="$_detected_jdks"
else
    GRADLE_INSTALLS_VAL="$DEVTOOLS2/modules/java/jdk-1.8,$DEVTOOLS2/modules/java/jdk-17,$DEVTOOLS2/modules/java/jdk-21,$DEVTOOLS2/modules/java/jdk-25"
fi

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
echo "🌐 8. 패키지 매니저(pip, npm) 고속 미러 서버 연동 중..."
setup_pip_mirror
# npm은 이 스크립트 실행 시점(Step 3의 1/3)에 아직 설치되지 않았을 수 있고,
# setup_npm_mirror가 npm 미설치/서버 폴백 시 return 1을 반환하는 정상 케이스가 있어
# set -euo pipefail 환경에서 스크립트 전체가 종료되는 버그를 방지한다.
setup_npm_mirror || true
echo "[완료] pip 및 npm 미러 서버 설정 완료!"
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
