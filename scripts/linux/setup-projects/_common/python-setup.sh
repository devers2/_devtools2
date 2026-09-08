#!/usr/bin/env bash
# ==============================================================================
# DEVTOOLS2 setup-projects Python / FastAPI 공통 모듈 (python-setup.sh)
# ==============================================================================
# [목적]
#   Python 및 FastAPI 프로젝트의 초기 개발 환경 구성을 표준화합니다.
#   신규 프로젝트 스크립트 작성 시 단 한 번의 함수 호출(setup_python_fastapi_project)로
#   필요 Python 버전 자동 전환(py_switch.sh), Bitwarden 세션 확인, Git 저장소 클론,
#   (선택) rclone SFTP 원격 디렉토리 마운트, Python 가상환경(venv) 생성 및 의존성 패키지 설치,
#   .vscode(settings.json, launch.json), pyrightconfig.json 생성, IDE 필수 Python 확장 설치까지의
#   전 과정을 자동화합니다.
#
# [사용 방법]
#   source "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"
#
#   setup_python_fastapi_project \
#       --target-dir "$HOME/workspaces/my-org/my-api" \
#       --repo-url "https://github.com/my-org/my-api.git" \
#       [선택 옵션들...]
#
# [옵션 상세 안내]
#   ■ 필수 옵션:
#     --target-dir <경로>        : 프로젝트를 클론하고 설정할 로컬 작업 디렉토리 경로
#     --repo-url <URL>           : 대상 Git 저장소 주소 (Bitwarden PAT 자동 인증 클론)
#
#   ■ 일반 선택 옵션:
#     --python-version <버전>    : 요구되는 Python 버전 (기본값: 312, "312" 또는 "3.12")
#                                  (현재 활성 버전과 다를 경우 py_switch.sh로 자동 전환)
#     --venv-name <이름>         : 가상환경 디렉토리명 (기본값: .venv, 예: venv_math)
#     --setup-venv-script <경로> : 프로젝트 전용 venv 생성 스크립트 (기본값: <target-dir>/setup-venv.sh)
#     --module <모듈:앱>         : FastAPI 실행 모듈 (기본값: main:app)
#     --port <포트번호>          : 로컬 디버깅 및 서버 포트 (기본값: 8095)
#     --worker-script <스크립트> : 백그라운드 워커 스크립트 파일명 (선택, 예: handwriting_matching_worker.py)
#     --enable-gunicorn <bool>   : launch.json에 gunicorn 디버그 설정 포함 여부 (기본값: false)
#     --app-name <이름>          : 콘솔 안내용 앱 명칭 (기본값: 대상 폴더명)
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

# VSCode Python 개발 필수 익스텐션 목록
VSCODE_PYTHON_EXTENSIONS=(
    "ms-python.python"
    "ms-python.debugpy"
    "ms-python.pylance"
)

# ── 1. Python 버전 확인 및 py_switch.sh 자동 전환 ─────────────────────────────
# 인수:
#   $1 = REQUIRED_PY_VERSION (선택, 기본값: 312 / 예: "312" 또는 "3.12")
ensure_python_version() {
    local RAW_VER="${1:-312}"
    local REQUIRED_PY_VERSION
    REQUIRED_PY_VERSION=$(echo "$RAW_VER" | tr -d '.')

    local _CURRENT_PY_VER
    _CURRENT_PY_VER=$(python3 --version 2>&1 | grep -oP '3\.\d+' | head -1 | tr -d '.')

    if [ "$_CURRENT_PY_VER" != "$REQUIRED_PY_VERSION" ]; then
        echo "⚠️  현재 Python 버전: $(python3 --version 2>&1)  →  Python ${REQUIRED_PY_VERSION}로 자동 전환합니다..."
        local DEVTOOLS2_PATH="${DEVTOOLS2:-$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../../../..")}"
        local _PY_SWITCH_SCRIPT="$DEVTOOLS2_PATH/scripts/linux/cmd/py_switch.sh"

        if [ -f "$_PY_SWITCH_SCRIPT" ]; then
            local _SAVED_SCRIPT_DIR="${SCRIPT_DIR:-}"
            # ⚠️ set -e 상태에서 py_switch.sh 내부의 `return 1`이 스크립트를 조기 종료시키지 않도록 if로 감쌈
            if ! source "$_PY_SWITCH_SCRIPT" "$REQUIRED_PY_VERSION"; then
                echo "❌ Python ${REQUIRED_PY_VERSION} 전환에 실패했습니다. py_switch.sh 스크립트를 확인해주세요."
                return 1
            fi
            # py_switch.sh 를 source 하면 SCRIPT_DIR 가 cmd/ 로 변경될 수 있으므로 원복
            if [ -n "$_SAVED_SCRIPT_DIR" ]; then
                SCRIPT_DIR="$_SAVED_SCRIPT_DIR"
            fi
            echo "✅ Python 전환 완료: $(python3 --version 2>&1)"
        else
            echo "❌ py_switch.sh를 찾을 수 없습니다: $_PY_SWITCH_SCRIPT"
            echo "   Python ${REQUIRED_PY_VERSION}가 활성화된 상태에서 다시 실행해주세요."
            return 1
        fi
    fi
}

# ── 2. Python 가상환경(venv) 구성 ─────────────────────────────────────────────
# 인수:
#   $1 = TARGET_DIR        (필수)
#   $2 = VENV_NAME         (선택, 기본값: .venv)
#   $3 = SETUP_SCRIPT      (선택, 프로젝트 내 커스텀 setup-venv.sh 경로)
#   $4 = REQUIREMENTS_FILE (선택, 기본값: <target-dir>/requirements.txt)
#                           경로가 다르거나 파일명이 다른 경우 절대경로 또는 상대경로로 지정
#                           예: "$TARGET_DIR/requirements/base.txt"
setup_venv_python() {
    local TARGET_DIR="$1"
    local VENV_NAME="${2:-.venv}"
    local SETUP_SCRIPT="${3:-$TARGET_DIR/setup-venv.sh}"
    local REQUIREMENTS_FILE="${4:-$TARGET_DIR/requirements.txt}"

    if [ -z "$TARGET_DIR" ]; then
        echo "❌ setup_venv_python: TARGET_DIR가 지정되지 않았습니다."
        return 1
    fi

    echo ""
    echo "⏳ Python 가상환경 설정을 진행합니다 ($VENV_NAME)..."

    if [ -f "$SETUP_SCRIPT" ]; then
        # 프로젝트 전용 스크립트가 있으면 venv 생성 및 의존성 설치를 모두 위임
        echo "ℹ️  프로젝트 전용 가상환경 스크립트를 실행합니다: $SETUP_SCRIPT"
        # shellcheck disable=SC1090
        source "$SETUP_SCRIPT" "$TARGET_DIR"
    else
        # venv 생성 (없을 때만)
        if [ ! -d "$TARGET_DIR/$VENV_NAME" ]; then
            echo "📦 Python 가상환경을 생성합니다: $TARGET_DIR/$VENV_NAME"
            python3 -m venv "$TARGET_DIR/$VENV_NAME"
        else
            echo "ℹ️  가상환경 디렉토리가 이미 존재합니다: $TARGET_DIR/$VENV_NAME"
        fi

        # requirements 파일 동기화 (venv 존재 여부와 무관하게 항상 실행)
        # pip은 이미 설치된 패키지를 skip하므로 재실행해도 안전하며 멱등성이 보장됩니다.
        if [ -f "$REQUIREMENTS_FILE" ]; then
            echo "📦 패키지 동기화 중... ($REQUIREMENTS_FILE)"
            "$TARGET_DIR/$VENV_NAME/bin/pip" install --upgrade pip -q
            "$TARGET_DIR/$VENV_NAME/bin/pip" install -r "$REQUIREMENTS_FILE"
        fi

        echo "✅ 가상환경 설정 완료!"
    fi
}

# ── 3. .vscode/settings.json 생성 (Python 인터프리터 및 분석 경로) ───────────
setup_vscode_python_settings() {
    local TARGET_DIR="$1"
    local VENV_NAME="${2:-.venv}"

    local VSCODE_DIR="$TARGET_DIR/.vscode"
    mkdir -p "$VSCODE_DIR"

    if [ -f "$VSCODE_DIR/settings.json" ]; then
        echo "ℹ️  .vscode/settings.json 이 이미 존재합니다. 덮어쓰지 않습니다."
        return 0
    fi

    cat > "$VSCODE_DIR/settings.json" <<EOF
{
  "python.defaultInterpreterPath": "\${workspaceFolder}/${VENV_NAME}/bin/python3",
  "python.terminal.activateEnvironment": true,
  "python.terminal.activateEnvInCurrentTerminal": true,
  "python.analysis.extraPaths": [
    "\${workspaceFolder}"
  ]
}
EOF
    echo "✅ .vscode/settings.json 생성 완료"
}

# ── 4. .vscode/launch.json 생성 (DAP 디버그 런치 설정 - IDE 공통) ──────────
# 이 파일은 VS Code 전용이 아닌 DAP(Debug Adapter Protocol) 표준 형식으로,
# Neovim(nvim-dap), VS Code, Cursor 등 DAP를 지원하는 모든 IDE에서 공통으로 사용됩니다.
# 디렉토리명(.vscode/)은 관례상 유지하지만, 특정 에디터에 종속되지 않습니다.
#
# 인수:
#   $1 = TARGET_DIR      (필수)
#   $2 = APP_NAME        (필수, 예: aiplus)
#   $3 = MODULE          (선택, 기본값: main:app)
#   $4 = PORT            (선택, 기본값: 8000)
#   $5 = VENV_NAME       (선택, 기본값: .venv)
#   $6 = WORKER_SCRIPT   (선택, 예: handwriting_matching_worker.py)
#   $7 = ENABLE_GUNICORN (선택, 기본값: false)
setup_vscode_python_launch() {
    local TARGET_DIR="$1"
    local APP_NAME="$2"
    local MODULE="${3:-main:app}"
    local PORT="${4:-8000}"
    local VENV_NAME="${5:-.venv}"
    local WORKER_SCRIPT="${6:-}"
    local ENABLE_GUNICORN="${7:-false}"
    local OVERWRITE="${8:-false}"

    local CONFIGS_JSON
    CONFIGS_JSON=$(python3 -c "
import json, sys

module = sys.argv[1]
port = sys.argv[2]
venv_name = sys.argv[3]
worker_script = sys.argv[4]
enable_gunicorn = sys.argv[5].lower() == 'true'

python_path = f'\${{workspaceFolder}}/{venv_name}/bin/python3'

configs = [
    {
        'name': '▶ FastAPI (uvicorn, debug)',
        'type': 'debugpy',
        'request': 'launch',
        'module': 'uvicorn',
        'args': [module, '--host', '0.0.0.0', '--port', str(port), '--reload'],
        'jinja': True,
        'python': python_path,
        'cwd': '\${workspaceFolder}',
        'env': {'PYTHONPATH': '\${workspaceFolder}'},
        'envFile': '\${workspaceFolder}/.env',
        'console': 'integratedTerminal'
    }
]

if enable_gunicorn:
    configs.append({
        'name': '▶ FastAPI (gunicorn, start.sh 방식)',
        'type': 'debugpy',
        'request': 'launch',
        'module': 'gunicorn',
        'args': [
            '-w', '1',
            '-k', 'uvicorn.workers.UvicornWorker',
            '-t', '600',
            '-b', f'0.0.0.0:{port}',
            module,
            '--access-logfile', '-',
            '--error-logfile', '-'
        ],
        'python': python_path,
        'cwd': '\${workspaceFolder}',
        'env': {'PYTHONPATH': '\${workspaceFolder}'},
        'envFile': '\${workspaceFolder}/.env',
        'console': 'integratedTerminal'
    })

if worker_script:
    clean_worker = worker_script.strip().lstrip('/')
    worker_name = clean_worker.split('/')[-1]
    configs.append({
        'name': f'▶ Worker ({worker_name})',
        'type': 'debugpy',
        'request': 'launch',
        'program': f'\${{workspaceFolder}}/{clean_worker}',
        'python': python_path,
        'cwd': '\${workspaceFolder}',
        'env': {'PYTHONPATH': '\${workspaceFolder}'},
        'envFile': '\${workspaceFolder}/.env',
        'console': 'integratedTerminal'
    })

print(json.dumps(configs))
" "$MODULE" "$PORT" "$VENV_NAME" "$WORKER_SCRIPT" "$ENABLE_GUNICORN")

    setup_vscode_launch_json "$TARGET_DIR" "$CONFIGS_JSON" "$OVERWRITE"
}

# 하위 호환성 래퍼 함수 (기존 파라미터 규격 유지)
setup_vscode_python_launch_fastapi() {
    local TARGET_DIR="$1"
    local APP_NAME="$2"
    local MODULE="${3:-main:app}"
    local PORT="${4:-8000}"
    local VENV_NAME="${5:-.venv}"
    local ENABLE_GUNICORN="${6:-true}"
    setup_vscode_python_launch "$TARGET_DIR" "$APP_NAME" "$MODULE" "$PORT" "$VENV_NAME" "" "$ENABLE_GUNICORN"
}

# ── 5. pyrightconfig.json 생성 ────────────────────────────────────────────────
setup_pyright_config() {
    local TARGET_DIR="$1"
    local VENV_NAME="${2:-.venv}"

    local PYRIGHT_CONFIG="$TARGET_DIR/pyrightconfig.json"
    if [ ! -f "$PYRIGHT_CONFIG" ]; then
        cat > "$PYRIGHT_CONFIG" <<EOF
{
  "venvPath": ".",
  "venv": "${VENV_NAME}"
}
EOF
        echo "✅ pyrightconfig.json 생성 완료"
    else
        echo "ℹ️  pyrightconfig.json 이 이미 존재합니다. 건너뜁니다."
    fi
}

# ── 6. 에디터별 디버깅 가이드 배너 출력 ──────────────────────────────────────
print_python_debugging_guide() {
    local TARGET_DIR="$1"
    local VENV_NAME="${2:-.venv}"
    local PORT="${3:-8000}"
    local APP_NAME="${4:-FastAPI}"

    local PYTHON_INTERPRETER
    if [ -f "$TARGET_DIR/$VENV_NAME/bin/python3" ]; then
        PYTHON_INTERPRETER="$(readlink -f "$TARGET_DIR/$VENV_NAME/bin/python3")"
    else
        PYTHON_INTERPRETER="$TARGET_DIR/$VENV_NAME/bin/python3"
    fi

    echo ""
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│  💻  VS Code / Cursor 디버깅 방법 ($APP_NAME)                                │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  [필수] ① 프로젝트 폴더 열기: code $TARGET_DIR"
    echo "  [필수] ② Python 인터프리터 지정: Ctrl+Shift+P → 'Python: Select Interpreter'"
    echo "         → 선택 경로: $PYTHON_INTERPRETER"
    echo "  [필수] ③ 디버그 실행: Ctrl+Shift+D → '▶ FastAPI (uvicorn, debug)' 선택 후 F5"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    echo "  💡 브레이크포인트: 줄번호 왼쪽 클릭 (●) → F10: Step Over │ F11: Step Into │ F5: Continue"
    echo "     디버깅 주소: http://localhost:$PORT  │  .env 환경변수 자동 로드됨"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│  📝  Neovim 디버깅 방법 (nvim-dap + .vscode/launch.json)                    │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  [필수] ① 가상환경 활성화 후 nvim 실행:"
    echo "         → cd $TARGET_DIR"
    echo "         → source $VENV_NAME/bin/activate"
    echo "         → nvim ."
    echo "  [필수] ② 브레이크포인트 설정: <leader> d b"
    echo "  [필수] ③ 디버그 시작: <leader> d d  (.vscode/launch.json 자동 읽음)"
    echo "         → 포트 $PORT 로 실행 시작 알림이 표시됩니다"
    echo "  [필수] ④ 스텝 실행: <leader> d e (Over) │ <leader> d i (Into) │ <leader> d c (Continue)"
    echo "  [선택] ⑤ UI 확인: <leader> d v (DAP View) │ <leader> d r (REPL)"
    echo "  [필수] ⑥ 디버그 종료: <leader> d t (Terminate)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📁 프로젝트 위치: $TARGET_DIR"
}

# ── 7. Python FastAPI 프로젝트 원클릭 표준 설정 함수 ─────────────────────────
# 사용 가능한 명명 옵션:
#   --target-dir        : 프로젝트 로컬 경로 (필수)
#   --repo-url          : Git 저장소 주소 (필수)
#   --python-version    : 필요 Python 버전 (선택, 기본값: 312)
#   --venv-name         : 가상환경 폴더명 (선택, 기본값: .venv)
#   --setup-venv-script : 전용 가상환경 스크립트 경로 (선택, 있으면 의존성 설치를 위임)
#   --requirements-file : 의존성 파일 경로 (선택, 기본값: <target-dir>/requirements.txt)
#                         경로나 파일명이 다른 경우 지정 (예: --requirements-file "$HOME/workspaces/myapp/requirements/base.txt")
#   --module            : FastAPI 앱 모듈 (선택, 기본값: main:app)
#   --port              : 실행 포트 (선택, 기본값: 8000) → launch.json args에 반영됨
#   --worker-script     : 백그라운드 워커 스크립트 파일명 (선택, 예: handwriting_matching_worker.py)
#   --enable-gunicorn   : gunicorn 디버그 설정 포함 여부 (선택, 기본값: false)
#   --sftp-user         : SFTP 접속 계정 (선택)
#   --sftp-host         : SFTP 접속 호스트 (선택)
#   --sftp-port         : SFTP 포트 (선택, 기본값: 22)
#   --sftp-remote-path  : SFTP 원격 마운트 경로 (선택)
#   --sftp-local-path   : SFTP 로컬 마운트 경로 (선택)
#   --app-name          : 앱 이름 (선택, 기본값: 폴더명)
setup_python_fastapi_project() {
    local TARGET_DIR=""
    local REPO_URL=""
    local PYTHON_VERSION="312"
    local VENV_NAME=".venv"
    local SETUP_VENV_SCRIPT=""
    local REQUIREMENTS_FILE=""
    local MODULE="main:app"
    local PORT="8000"
    local WORKER_SCRIPT=""
    local ENABLE_GUNICORN="false"
    local SFTP_SPEC=""
    local SFTP_USER=""
    local SFTP_HOST=""
    local SFTP_PORT="22"
    local SFTP_REMOTE_PATH=""
    local SFTP_LOCAL_PATH=""
    local APP_NAME=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --target-dir)        TARGET_DIR="$2"; shift 2 ;;
            --repo-url)          REPO_URL="$2"; shift 2 ;;
            --python-version)    PYTHON_VERSION="$2"; shift 2 ;;
            --venv-name)         VENV_NAME="$2"; shift 2 ;;
            --setup-venv-script) SETUP_VENV_SCRIPT="$2"; shift 2 ;;
            --requirements-file) REQUIREMENTS_FILE="$2"; shift 2 ;;
            --module)            MODULE="$2"; shift 2 ;;
            --port)              PORT="$2"; shift 2 ;;
            --worker-script|--worker) WORKER_SCRIPT="$2"; shift 2 ;;
            --enable-gunicorn)   ENABLE_GUNICORN="$2"; shift 2 ;;
            --sftp)              SFTP_SPEC="$2"; shift 2 ;;
            --sftp-user)         SFTP_USER="$2"; shift 2 ;;
            --sftp-host)         SFTP_HOST="$2"; shift 2 ;;
            --sftp-port)         SFTP_PORT="$2"; shift 2 ;;
            --sftp-remote-path)  SFTP_REMOTE_PATH="$2"; shift 2 ;;
            --sftp-local-path)   SFTP_LOCAL_PATH="$2"; shift 2 ;;
            --app-name)          APP_NAME="$2"; shift 2 ;;
            *) echo "⚠️  알 수 없는 옵션 무시: $1"; shift ;;
        esac
    done

    if [ -z "$TARGET_DIR" ] || [ -z "$REPO_URL" ]; then
        echo "❌ setup_python_fastapi_project: --target-dir 및 --repo-url 은 필수 인자입니다."
        return 1
    fi

    [ -z "$APP_NAME" ] && APP_NAME="$(basename "$TARGET_DIR")"
    [ -z "$SETUP_VENV_SCRIPT" ] && SETUP_VENV_SCRIPT="$TARGET_DIR/setup-venv.sh"
    [ -z "$REQUIREMENTS_FILE" ] && REQUIREMENTS_FILE="$TARGET_DIR/requirements.txt"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 [$APP_NAME] Python FastAPI 프로젝트 설정을 시작합니다."
    echo "   대상 경로 : $TARGET_DIR"
    echo "   저장소 URL: $REPO_URL"
    echo "   Python    : $PYTHON_VERSION"
    echo "   가상환경  : $VENV_NAME"
    echo "   실행 포트 : $PORT ($MODULE)"
    [ -n "$WORKER_SCRIPT" ] && echo "   워커      : $WORKER_SCRIPT"
    [ -n "$SFTP_SPEC" ] && echo "   SFTP 마운트: $SFTP_SPEC"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 1. Python 버전 확인 및 자동 전환
    ensure_python_version "$PYTHON_VERSION" || return 1

    # 2. Bitwarden 세션 확인 및 Git Clone
    ensure_project_repo "$REPO_URL" "$TARGET_DIR" || return 1

    # 3. SFTP 마운트 설정 (선택, SFTP 옵션 지정 시)
    if [ -n "$SFTP_SPEC" ] || [ -n "$SFTP_USER" ]; then
        handle_sftp_mount_options "$SFTP_SPEC" "$SFTP_USER" "$SFTP_HOST" "$SFTP_PORT" "$SFTP_REMOTE_PATH" "$SFTP_LOCAL_PATH" "$APP_NAME" || {
            local _exit_code=$?
            if [ "$_exit_code" -eq 2 ]; then
                return 0
            fi
        }
    fi

    # 4. Python 가상환경 설정 및 의존성 동기화
    setup_venv_python "$TARGET_DIR" "$VENV_NAME" "$SETUP_VENV_SCRIPT" "$REQUIREMENTS_FILE"

    # 5. .vscode 및 pyright 설정 파일 생성
    echo ""
    echo "⏳ VSCode 설정 파일 및 pyrightconfig.json 생성 중..."
    setup_vscode_python_settings "$TARGET_DIR" "$VENV_NAME"
    setup_vscode_python_launch "$TARGET_DIR" "$APP_NAME" "$MODULE" "$PORT" "$VENV_NAME" "$WORKER_SCRIPT" "$ENABLE_GUNICORN"
    setup_pyright_config "$TARGET_DIR" "$VENV_NAME"

    # 6. VSCode 필수 확장 프로그램 검사/설치
    install_vscode_extensions "${VSCODE_PYTHON_EXTENSIONS[@]}"

    # 7. 디버깅 가이드 안내
    print_python_debugging_guide "$TARGET_DIR" "$VENV_NAME" "$PORT" "$APP_NAME"
}
