#!/usr/bin/env bash
# ==============================================================================
# aiplus 프로젝트 설정 스크립트
# ==============================================================================

set -e

# DEVTOOLS2 경로 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVTOOLS2="${DEVTOOLS2:-$(readlink -f "$SCRIPT_DIR/../..")}"

# bw-lib 로드 (bw_ensure_session / bw_git_clone / bw_get_items_by_folder_name 포함)
if [ -f "$DEVTOOLS2/scripts/fzf/bw-lib" ]; then
    source "$DEVTOOLS2/scripts/fzf/bw-lib"
else
    echo "❌ bw-lib 라이브러리를 찾을 수 없습니다: $DEVTOOLS2/scripts/fzf/bw-lib"
    exit 1
fi

TARGET_DIR="$HOME/workspaces/aiplus"
REPO_URL="https://github.com/Placelink-HUB/aiplus.git"
# 원격/로컬 경로 — ~ 치환은 USERNAME 확정 후 처리 (SFTP 설정 단계에서)
INPUT_REMOTE_MOUNT_PATH="~/mount/aiplus"
INPUT_LOCAL_MOUNT_PATH="~/mount/aiplus"

echo "🚀 [aiplus] 프로젝트 설정을 시작합니다."
echo "   대상 경로: $TARGET_DIR"

# ==============================================================================
# 1. Bitwarden 세션 확보 (bw-lib: bw_ensure_session)
# ==============================================================================
echo "⏳ Bitwarden 상태 확인 중..."
bw_ensure_session || exit 1

# ==============================================================================
# 2. 깃 클론 (bw-lib: bw_git_clone — Bitwarden PAT 인증 자동)
# ==============================================================================
if [ -d "$TARGET_DIR/.git" ]; then
    echo "ℹ️  이미 깃 저장소가 존재합니다. 클론 단계를 건너뜁니다."
else
    bw_git_clone "$REPO_URL" "$TARGET_DIR" || exit 1
fi

# ==============================================================================
# 3. SFTP 마운트 설정 (bw-lib: bw_get_items_by_folder_name 으로 서버 정보 조회)
#    대상 서버: namupia@aiplus.im:222
#    bw-server-manager 는 인터랙티브 스크립트라 직접 재사용 불가 → 동일 로직 인라인
# ==============================================================================
echo "⚙️  SFTP 마운트 설정 진행 중 (namupia@aiplus.im:222)..."

# bw-lib: RemoteServer 폴더의 모든 아이템 조회
RAW_SERVER_ITEMS=$(bw_get_items_by_folder_name "RemoteServer") || exit 1

# namupia@aiplus.im 서버 항목 파싱
# bw_find_item_by_name 은 이름(item.name) 기준이라 username+host 검색은 커스텀 Python 사용
_PY_SERVER=$(mktemp /tmp/bw_server_XXXXXX.py)
cat > "$_PY_SERVER" <<'PYEOF'
import sys, json, re

raw_all = sys.stdin.read()
chunks = raw_all.split('---ITEM_SPLIT---')

for chunk in chunks:
    chunk = chunk.strip()
    if not chunk:
        continue
    start_idx = chunk.find('[')
    end_idx = chunk.rfind(']')
    if start_idx == -1 or end_idx == -1 or start_idx >= end_idx:
        continue
    try:
        items = json.loads(chunk[start_idx:end_idx+1], strict=False)
        for item in items:
            if not isinstance(item, dict):
                continue
            login = item.get('login') or {}
            username = login.get('username') or ''
            uris = login.get('uris') or []
            raw_uri = ''
            if isinstance(uris, list) and len(uris) > 0 and isinstance(uris[0], dict):
                raw_uri = uris[0].get('uri') or ''
            clean_uri = re.sub(r'^[a-z]+://', '', raw_uri)
            if username == 'namupia' and 'aiplus.im' in clean_uri:
                item_id = item.get('id', '')
                print(f"{item_id}\t{username}\t{clean_uri}")
                sys.exit(0)
    except Exception:
        pass
PYEOF

SERVER_INFO=$(printf "%s" "$RAW_SERVER_ITEMS" | python3 "$_PY_SERVER")
rm -f "$_PY_SERVER"

if [ -z "$SERVER_INFO" ]; then
    echo "❌ Bitwarden 'RemoteServer' 폴더에서 namupia@aiplus.im 서버 항목을 찾을 수 없습니다."
    exit 1
fi

ITEM_ID=$(echo "$SERVER_INFO" | cut -f1)
USERNAME=$(echo "$SERVER_INFO" | cut -f2)
RAW_URI=$(echo "$SERVER_INFO"  | cut -f3)

if [[ "$RAW_URI" == *:* ]]; then
    ACTUAL_HOST="${RAW_URI%:*}"
    PORT="${RAW_URI##*:}"
else
    ACTUAL_HOST="$RAW_URI"
    PORT="22"
fi

# bw-lib의 BW_SESSION을 활용하여 비밀번호 조회
SERVER_PASS=$(bw get password "$ITEM_ID" --session "$BW_SESSION" 2>/dev/null || echo "")

SERVICE_NAME="rclone-${USERNAME}@${ACTUAL_HOST}_${PORT}"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"

# ~ 치환:
#   원격 경로의 ~ → 서버 접속 계정 홈 (/home/$USERNAME)
#   로컬 경로의 ~ → 현재 로컬 사용자 홈 ($HOME)
REMOTE_MOUNT_PATH="${INPUT_REMOTE_MOUNT_PATH/#\~//home/$USERNAME}"
LOCAL_MOUNT_PATH="${INPUT_LOCAL_MOUNT_PATH/#\~/$HOME}"

echo "   원격 마운트 경로 (서버): $REMOTE_MOUNT_PATH"
echo "   로컬 마운트 경로 (로컬): $LOCAL_MOUNT_PATH"

mkdir -p "$LOCAL_MOUNT_PATH"

RCLONE_BIN=$(command -v rclone 2>/dev/null || echo "/usr/bin/rclone")
FUSERMOUNT_BIN=$(command -v fusermount 2>/dev/null || command -v fusermount3 2>/dev/null || echo "/usr/bin/fusermount")

if [ ! -x "$RCLONE_BIN" ]; then
    echo "❌ rclone이 설치되어 있지 않습니다."
    exit 1
fi

# 기존 rclone 리모트 설정이 있으면 삭제 후 재생성 (잘못된 설정 방지)
if "$RCLONE_BIN" config show "$SERVICE_NAME" >/dev/null 2>&1; then
    echo "⚠️  기존 Rclone 리모트 ($SERVICE_NAME) 설정 삭제 후 재생성합니다..."
    "$RCLONE_BIN" config delete "$SERVICE_NAME" 2>/dev/null || true
fi

echo "⏳ Rclone SFTP 리모트 ($SERVICE_NAME) 설정 중..."
RCLONE_ARGS=(config create "$SERVICE_NAME" sftp host "$ACTUAL_HOST" user "$USERNAME" port "$PORT")
if [ -n "$SERVER_PASS" ]; then
    RCLONE_ARGS+=(pass "$SERVER_PASS")
fi
"$RCLONE_BIN" "${RCLONE_ARGS[@]}" >/dev/null 2>&1
echo "✅ Rclone 리모트 설정 완료!"

RCLONE_CONF="$HOME/.config/rclone/rclone.conf"
mkdir -p "$HOME/.config/systemd/user"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=rclone SFTP Mount for ${SERVICE_NAME}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${RCLONE_BIN} mount ${SERVICE_NAME}:${REMOTE_MOUNT_PATH} ${LOCAL_MOUNT_PATH} \\
    --vfs-cache-mode full \\
    --config=${RCLONE_CONF}
ExecStop=${FUSERMOUNT_BIN} -u ${LOCAL_MOUNT_PATH}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

echo "✅ systemd 서비스 파일 작성 완료: $SERVICE_FILE"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable "$SERVICE_NAME.service" 2>/dev/null || true
systemctl --user restart "$SERVICE_NAME.service" 2>/dev/null || true

# ==============================================================================
# 4. Python 가상환경(venv_math) 생성 및 패키지 설치
# ==============================================================================
SETUP_VENV_SCRIPT="$TARGET_DIR/setup-venv.sh"

if [ -f "$SETUP_VENV_SCRIPT" ]; then
    echo ""
    echo "⏳ [Step 4] Python 가상환경 설정을 시작합니다..."
    # source 로 호출 → 가상환경 activate 상태를 이 셸에도 유지
    source "$SETUP_VENV_SCRIPT" "$TARGET_DIR"
else
    echo "⚠️  setup-venv.sh 를 찾을 수 없습니다. 가상환경 설정을 건너뜁니다: $SETUP_VENV_SCRIPT"
fi

# ==============================================================================
# 5. VSCode 설정 파일 (.vscode/settings.json, .vscode/launch.json) 생성
# ==============================================================================
echo ""
echo "⏳ [Step 5] VSCode 설정 파일을 생성합니다..."

VSCODE_DIR="$TARGET_DIR/.vscode"
mkdir -p "$VSCODE_DIR"

# ── settings.json ─────────────────────────────────────────────────────────────
if [ -f "$VSCODE_DIR/settings.json" ]; then
    echo "ℹ️  .vscode/settings.json 이 이미 존재합니다. 덮어쓰지 않습니다."
else
    cat > "$VSCODE_DIR/settings.json" << 'SETTINGS_EOF'
{
  // venv_math 가상환경의 Python 인터프리터를 사용
  "python.defaultInterpreterPath": "${workspaceFolder}/venv_math/bin/python3",
  "python.terminal.activateEnvironment": true,
  "python.terminal.activateEnvInCurrentTerminal": true,

  // Pylance/Pyright 분석도 venv_math 기준으로
  "python.analysis.extraPaths": [
    "${workspaceFolder}"
  ]
}
SETTINGS_EOF
    echo "✅ .vscode/settings.json 생성 완료"
fi

# ── launch.json ───────────────────────────────────────────────────────────────
if [ -f "$VSCODE_DIR/launch.json" ]; then
    echo "ℹ️  .vscode/launch.json 이 이미 존재합니다. 덮어쓰지 않습니다."
else
    cat > "$VSCODE_DIR/launch.json" << 'LAUNCH_EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      // ──────────────────────────────────────────────────────────
      // [권장] uvicorn 직접 실행 (핫-리로드 + 브레이크포인트 동작)
      // ──────────────────────────────────────────────────────────
      "name": "▶ FastAPI (uvicorn, debug)",
      "type": "debugpy",
      "request": "launch",
      "module": "uvicorn",
      "args": [
        "main:app",
        "--host", "0.0.0.0",
        "--port", "8095",
        "--reload"
      ],
      "jinja": true,
      "python": "${workspaceFolder}/venv_math/bin/python3",
      "cwd": "${workspaceFolder}",
      "env": {
        "PYTHONPATH": "${workspaceFolder}"
      },
      "envFile": "${workspaceFolder}/.env",
      "console": "integratedTerminal"
    },
    {
      // ──────────────────────────────────────────────────────────
      // [참고용] gunicorn 실행 (start.sh 와 동일한 방식)
      // ※ gunicorn + UvicornWorker 조합에서는 브레이크포인트가
      //   제대로 동작하지 않을 수 있습니다.
      // ──────────────────────────────────────────────────────────
      "name": "▶ FastAPI (gunicorn, start.sh 방식)",
      "type": "debugpy",
      "request": "launch",
      "module": "gunicorn",
      "args": [
        "-w", "1",
        "-k", "uvicorn.workers.UvicornWorker",
        "-t", "600",
        "-b", "0.0.0.0:8095",
        "main:app",
        "--access-logfile", "-",
        "--error-logfile", "-"
      ],
      "python": "${workspaceFolder}/venv_math/bin/python3",
      "cwd": "${workspaceFolder}",
      "envFile": "${workspaceFolder}/.env",
      "console": "integratedTerminal"
    }
  ]
}
LAUNCH_EOF
    echo "✅ .vscode/launch.json 생성 완료"
fi

# ── pyrightconfig.json 보완 (venvPath / venv 명시) ────────────────────────────
PYRIGHT_CONFIG="$TARGET_DIR/pyrightconfig.json"
if [ ! -f "$PYRIGHT_CONFIG" ]; then
    cat > "$PYRIGHT_CONFIG" << 'PYRIGHT_EOF'
{
  "venvPath": ".",
  "venv": "venv_math"
}
PYRIGHT_EOF
    echo "✅ pyrightconfig.json 생성 완료"
else
    echo "ℹ️  pyrightconfig.json 이 이미 존재합니다. 건너뜁니다."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 [aiplus] 프로젝트 설정이 완료되었습니다!"
echo "   SFTP 서비스 상태 확인: systemctl --user status ${SERVICE_NAME}.service"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ==============================================================================
# 6. VSCode 필수 익스텐션 자동 설치
# ==============================================================================
echo ""
echo "⏳ [Step 6] VSCode 필수 익스텐션을 확인/설치합니다..."

VSCODE_BIN=""
for _bin in code code-insiders; do
    if command -v "$_bin" &>/dev/null; then
        VSCODE_BIN="$_bin"
        break
    fi
done

_REQUIRED_EXTENSIONS=(
    "ms-python.python"          # Python 언어 지원 (IntelliSense, 린터 등)
    "ms-python.debugpy"         # Python 디버거 (브레이크포인트 핵심)
    "ms-python.pylance"         # Pylance: 빠른 타입 체크 / 자동완성
)

if [ -z "$VSCODE_BIN" ]; then
    echo "⚠️  VSCode(code) 명령어를 찾을 수 없습니다. 익스텐션 설치를 건너뜁니다."
    echo "   → VSCode 가 설치되어 있지 않거나 PATH 에 등록되지 않았습니다."
    echo "   → https://code.visualstudio.com 에서 설치 후 아래 익스텐션을 수동으로 설치하세요:"
    for _ext in "${_REQUIRED_EXTENSIONS[@]}"; do
        echo "      • $_ext"
    done
else
    _INSTALLED_EXTS=$("$VSCODE_BIN" --list-extensions 2>/dev/null || echo "")
    for _ext in "${_REQUIRED_EXTENSIONS[@]}"; do
        if echo "$_INSTALLED_EXTS" | grep -qi "^${_ext}$"; then
            echo "   ✅ 이미 설치됨: $_ext"
        else
            echo "   📦 설치 중: $_ext ..."
            "$VSCODE_BIN" --install-extension "$_ext" --force 2>/dev/null && \
                echo "   ✅ 설치 완료: $_ext" || \
                echo "   ⚠️  설치 실패 (수동 설치 필요): $_ext"
        fi
    done
fi

# ==============================================================================
# 최종 안내 로그: VSCode 디버깅을 위해 추가로 해야 할 일
# ==============================================================================
PYTHON_INTERPRETER="$TARGET_DIR/venv_math/bin/python3.12"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 VSCode 디버깅을 위해 추가로 해야 할 일"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  [필수] ① VSCode 에서 프로젝트 폴더 열기"
echo "         → code $TARGET_DIR"
echo ""
echo "  [필수] ② Python 인터프리터 지정"
echo "         → Ctrl+Shift+P  →  'Python: Select Interpreter'  입력 후 선택"
echo "         → 목록에서 아래 경로를 선택하세요:"
echo "            $PYTHON_INTERPRETER"
echo "         ※ 목록에 없으면 'Enter interpreter path...' 로 직접 경로 입력"
echo ""
echo "  [선택] ③ VSCode 재시작 (인터프리터 변경 후 익스텐션이 갱신되도록)"
echo "         → Ctrl+Shift+P  →  'Developer: Reload Window'"
echo ""
echo "  [필수] ④ 디버그 실행"
echo "         → Ctrl+Shift+D  (실행 및 디버그 패널 열기)"
echo "         → 상단 드롭다운에서 '▶ FastAPI (uvicorn, debug)' 선택"
echo "         → F5 또는 ▶ 버튼 클릭"
echo ""
echo "  ─────────────────────────────────────────────────────────────────────────────"
echo "  💡 브레이크포인트 사용법"
echo "     → 소스 코드 좌측 줄번호 옆 클릭 → 빨간 점(●) 생성"
echo "     → F5 로 실행하면 해당 줄에서 자동 일시정지"
echo "     → F10: 한 줄씩 실행(Step Over)  F11: 함수 안으로(Step Into)"
echo "     → F5:  다음 브레이크포인트까지 계속 실행"
echo ""
echo "  ─────────────────────────────────────────────────────────────────────────────"
echo "  ⚠️  주의사항"
echo "     • '▶ FastAPI (gunicorn, start.sh 방식)' 구성은 운영 방식과 동일하지만"
echo "       멀티프로세스 구조로 인해 브레이크포인트가 제한적으로 동작합니다."
echo "     • 디버깅 중 서버는 8095 포트로 접근 가능합니다: http://localhost:8095"
echo "     • .env 파일의 환경변수는 디버그 실행 시 자동으로 로드됩니다."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

