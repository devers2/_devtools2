#!/usr/bin/env bash
# ==============================================================================
# aiplus 프로젝트 설정 스크립트
# ==============================================================================

set -e

# DEVTOOLS2 경로 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVTOOLS2="${DEVTOOLS2:-$(readlink -f "$SCRIPT_DIR/../..")}"

# bw-lib 로드
if [ -f "$DEVTOOLS2/scripts/fzf/bw-lib" ]; then
    source "$DEVTOOLS2/scripts/fzf/bw-lib"
else
    echo "❌ bw-lib 라이브러리를 찾을 수 없습니다: $DEVTOOLS2/scripts/fzf/bw-lib"
    exit 1
fi

TARGET_DIR="$HOME/workspaces/aiplus"
REPO_URL="https://github.com/Placelink-HUB/aiplus.git"
REMOTE_MOUNT_PATH="~/mount/aiplus"
LOCAL_MOUNT_PATH="$HOME/mount/aiplus"

echo "🚀 [aiplus] 프로젝트 설정을 시작합니다."
echo "   대상 경로: $TARGET_DIR"

# 1. Bitwarden 세션 확보
echo "⏳ Bitwarden 상태 확인 중..."
bw_ensure_session || exit 1

# 2. 깃 클론 (Bitwarden 인증 자동화)
if [ -d "$TARGET_DIR/.git" ]; then
    echo "ℹ️  이미 깃 저장소가 존재합니다. 클론 단계를 건너땁니다."
else
    GIT_ITEM_NAME="github.com-main"
    ALL_ITEMS_RAW=$(bw list items --search "$GIT_ITEM_NAME" --session "$BW_SESSION" 2>&1)
    
    PY_PARSER=$(mktemp /tmp/bw_git_XXXXXX.py)
    cat > "$PY_PARSER" <<'PYEOF'
import sys, json

target_name = sys.argv[1] if len(sys.argv) > 1 else ''
try:
    raw = sys.stdin.read()
    start = raw.find('[')
    end = raw.rfind(']')
    if start != -1 and end != -1 and start < end:
        items = json.loads(raw[start:end+1], strict=False)
        for item in items:
            if isinstance(item, dict) and str(item.get('name', '')).strip() == target_name:
                login = item.get('login') or {}
                username = (login.get('username') or '').strip()
                totp = (login.get('totp') or '').strip()
                print(f"{username}\t{totp}")
                sys.exit(0)
except Exception:
    pass
PYEOF

    PARSED=$(printf "%s" "$ALL_ITEMS_RAW" | python3 "$PY_PARSER" "$GIT_ITEM_NAME")
    rm -f "$PY_PARSER"

    if [ -z "$PARSED" ]; then
        echo "❌ Bitwarden에서 '${GIT_ITEM_NAME}' 항목을 찾을 수 없습니다."
        exit 1
    fi

    GIT_EMAIL=$(printf "%s" "$PARSED" | cut -f1)
    GIT_PAT=$(printf "%s" "$PARSED" | cut -f2)
    GIT_USERNAME=$(printf "%s" "$GIT_EMAIL" | cut -d'@' -f1)

    mkdir -p "$(dirname "$TARGET_DIR")"

    ASKPASS_SCRIPT=$(mktemp /tmp/bw_askpass_XXXXXX.sh)
    chmod 700 "$ASKPASS_SCRIPT"
    cat > "$ASKPASS_SCRIPT" <<ASKEOF
#!/usr/bin/env bash
case "\$1" in
  Username*) echo "${GIT_USERNAME}" ;;
  Password*) echo "${GIT_PAT}"      ;;
esac
ASKEOF

    echo "🚀 저장소 클론 중: $REPO_URL -> $TARGET_DIR"
    GIT_ASKPASS="$ASKPASS_SCRIPT" \
    GIT_TERMINAL_PROMPT=0 \
    git clone "$REPO_URL" "$TARGET_DIR"
    rm -f "$ASKPASS_SCRIPT"
    echo "✅ 깃 클론 완료!"
fi

# 3. RemoteServer 중 namupia@aiplus.im:222 대상 SFTP 마운트 설정
echo "⚙️  SFTP 마운트 설정 진행 중 (namupia@aiplus.im:222 -> $LOCAL_MOUNT_PATH)..."

RAW_SERVER_ITEMS=$(bw_get_items_by_folder_name "RemoteServer") || exit 1

PY_SERVER_PARSER=$(mktemp /tmp/bw_server_XXXXXX.py)
cat > "$PY_SERVER_PARSER" <<'PYEOF'
import sys, json, re

raw_all = sys.stdin.read()
chunks = raw_all.split('---ITEM_SPLIT---')

for chunk in chunks:
    chunk = chunk.strip()
    if not chunk:
        continue
    start_idx = chunk.find('[')
    end_idx = chunk.rfind(']')
    if start_idx != -1 and end_idx != -1 and start_idx < end_idx:
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

SERVER_INFO=$(printf "%s" "$RAW_SERVER_ITEMS" | python3 "$PY_SERVER_PARSER")
rm -f "$PY_SERVER_PARSER"

if [ -z "$SERVER_INFO" ]; then
    echo "❌ Bitwarden 'RemoteServer' 폴더에서 namupia@aiplus.im 서버 항목을 찾을 수 없습니다."
    exit 1
fi

ITEM_ID=$(echo "$SERVER_INFO" | cut -f1)
USERNAME=$(echo "$SERVER_INFO" | cut -f2)
RAW_URI=$(echo "$SERVER_INFO" | cut -f3)

if [[ "$RAW_URI" == *:* ]]; then
    ACTUAL_HOST="${RAW_URI%:*}"
    PORT="${RAW_URI##*:}"
else
    ACTUAL_HOST="$RAW_URI"
    PORT="22"
fi

SERVER_PASS=$(bw get password "$ITEM_ID" --session "$BW_SESSION" 2>/dev/null || echo "")

SERVICE_NAME="rclone-${USERNAME}@${ACTUAL_HOST}_${PORT}"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"

echo "📂 로컬 마운트 디렉토리 준비: $LOCAL_MOUNT_PATH"
mkdir -p "$LOCAL_MOUNT_PATH"

RCLONE_BIN=$(command -v rclone 2>/dev/null || echo "/usr/bin/rclone")
FUSERMOUNT_BIN=$(command -v fusermount 2>/dev/null || command -v fusermount3 2>/dev/null || echo "/usr/bin/fusermount")

if [ ! -x "$RCLONE_BIN" ]; then
    echo "❌ rclone이 설치되어 있지 않습니다."
    exit 1
fi

echo "⏳ Rclone SFTP 리모트 ($SERVICE_NAME) 생성 중..."
RCLONE_ARGS=(config create "$SERVICE_NAME" sftp host "$ACTUAL_HOST" user "$USERNAME" port "$PORT")
if [ -n "$SERVER_PASS" ]; then
    RCLONE_ARGS+=(pass "$SERVER_PASS")
fi

"$RCLONE_BIN" "${RCLONE_ARGS[@]}" >/dev/null 2>&1 || true

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

echo "🎉 [aiplus] 프로젝트 및 SFTP 마운트 설정이 완료되었습니다!"
