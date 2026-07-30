#!/usr/bin/env bash
# ==============================================================================
# aiplus 프로젝트 설정 스크립트
# ==============================================================================

set -e

# DEVTOOLS2 경로 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVTOOLS2="${DEVTOOLS2:-$(readlink -f "$SCRIPT_DIR/../..")}"

# bw-lib 로드 (bw_ensure_session / bw_get_items_by_folder_name / bw_find_item_by_name 포함)
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
# 2. 깃 클론 (bw-lib: bw_find_item_by_name 으로 github.com-main PAT 조회)
# ==============================================================================
if [ -d "$TARGET_DIR/.git" ]; then
    echo "ℹ️  이미 깃 저장소가 존재합니다. 클론 단계를 건너뜁니다."
else
    GIT_ITEM_NAME="github.com-main"
    echo "⏳ Bitwarden에서 '${GIT_ITEM_NAME}' 계정 정보 조회 중..."

    # bw-lib의 bw_get_items_by_folder_name 대신 전체 검색 후 bw_find_item_by_name 활용
    _ALL_GIT_ITEMS=$(bw list items --search "$GIT_ITEM_NAME" --session "$BW_SESSION" </dev/null 2>&1)
    # bw_find_item_by_name 은 ---ITEM_SPLIT--- 구분 형식을 받으므로 단일 청크로 래핑
    _GIT_RAW_LIST="${_ALL_GIT_ITEMS}"$'\n---ITEM_SPLIT---\n'
    _GIT_PARSED=$(bw_find_item_by_name "$_GIT_RAW_LIST" "$GIT_ITEM_NAME")

    if [ -z "$_GIT_PARSED" ]; then
        echo "❌ Bitwarden에서 '${GIT_ITEM_NAME}' 항목을 찾을 수 없습니다."
        exit 1
    fi

    # bw_find_item_by_name 반환: username\tpassword\ttotp\tnotes
    # github.com-main 구조: username=이메일, totp=PAT 토큰
    GIT_EMAIL=$(printf "%s" "$_GIT_PARSED" | cut -f1)
    GIT_PAT=$(printf "%s"   "$_GIT_PARSED" | cut -f3)   # totp 필드 = PAT
    GIT_USERNAME=$(printf "%s" "$GIT_EMAIL" | cut -d'@' -f1)

    echo "✅ GitHub 계정 확인: $GIT_USERNAME ($GIT_EMAIL)"
    mkdir -p "$(dirname "$TARGET_DIR")"

    _ASKPASS=$(mktemp /tmp/bw_askpass_XXXXXX.sh)
    chmod 700 "$_ASKPASS"
    cat > "$_ASKPASS" <<ASKEOF
#!/usr/bin/env bash
case "\$1" in
  Username*) echo "${GIT_USERNAME}" ;;
  Password*) echo "${GIT_PAT}"      ;;
esac
ASKEOF

    echo "🚀 저장소 클론 중: $REPO_URL -> $TARGET_DIR"
    GIT_ASKPASS="$_ASKPASS" \
    GIT_TERMINAL_PROMPT=0 \
    git clone "$REPO_URL" "$TARGET_DIR"
    rm -f "$_ASKPASS"
    echo "✅ 깃 클론 완료!"
fi

# ==============================================================================
# 3. SFTP 마운트 설정 (bw-lib: bw_get_items_by_folder_name 으로 서버 정보 조회)
#    대상 서버: namupia@aiplus.im:222
# ==============================================================================
echo "⚙️  SFTP 마운트 설정 진행 중 (namupia@aiplus.im:222)..."

# bw-lib: RemoteServer 폴더의 모든 아이템 조회
RAW_SERVER_ITEMS=$(bw_get_items_by_folder_name "RemoteServer") || exit 1

# namupia@aiplus.im 서버 항목 파싱 (username+host 기준 탐색 — bw_find_item_by_name은 이름 기준이라 커스텀 사용)
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

# bw-lib의 BW_SESSION을 활용하여 비밀번호 조회 (bw-server-manager 와 동일한 방식)
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

echo ""
echo "🎉 [aiplus] 프로젝트 및 SFTP 마운트 설정이 완료되었습니다!"
echo "   서비스 상태 확인: systemctl --user status ${SERVICE_NAME}.service"
