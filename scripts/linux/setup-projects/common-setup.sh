#!/usr/bin/env bash
# ==============================================================================
# DEVTOOLS2 setup-projects 공통 모듈 (common-setup.sh)
# ==============================================================================
# 개요:
#   프로젝트 설정(setup-projects) 스크립트에서 공통으로 재사용 가능한 모듈 함수들을 제공합니다.
#
# 사용 방법 (다른 스크립트에서 호출 시):
#   1. 모듈 불러오기:
#      if [ -f "$SCRIPT_DIR/common-setup.sh" ]; then
#          source "$SCRIPT_DIR/common-setup.sh"
#      fi
#
#   2. GitHub Packages 의존성 설정 함수 호출:
#      setup_gpr_gradle_properties "$TARGET_DIR" [BW_ITEM_NAME]
#      - $1: 대상 프로젝트 루트 경로 (필수, 기본값: $PWD)
#      - $2: Bitwarden 아이템 이름 (선택, 기본값: github.com-main)
# ==============================================================================

# ── GitHub Packages 의존성 관리 설정 (gpr.user / gpr.key) ───────────────────
# 기능:
#   - 대상 디렉토리에 Gradle 설정 파일(build.gradle, settings.gradle, build.gradle.kts, settings.gradle.kts) 존재 여부 확인
#   - ~/.gradle/gradle.properties 파일의 gpr.user 와 gpr.key 설정 상태 검증
#   - 누락되거나 불일치 시 대소문자 구분 없이 (y/n) 대화형 입력을 받아 gpr.user 및 gpr.key 자동 생성/수정
# 인수:
#   $1 = 대상 프로젝트 디렉토리 (기본값: 현재 디렉토리)
#   $2 = Bitwarden 아이템 이름 (선택, 기본값: github.com-main)
setup_gpr_gradle_properties() {
    local TARGET_DIR="${1:-$PWD}"
    local BW_ITEM="${2:-github.com-main}"

    if [ ! -d "$TARGET_DIR" ]; then
        return 0
    fi

    # 1. Gradle 빌드/설정 파일 존재 여부 확인
    local HAS_GRADLE=false
    for gfile in "build.gradle" "settings.gradle" "build.gradle.kts" "settings.gradle.kts"; do
        if [ -f "$TARGET_DIR/$gfile" ]; then
            HAS_GRADLE=true
            break
        fi
    done

    if [ "$HAS_GRADLE" = "false" ]; then
        return 0
    fi

    # 2. expected user.name 및 PAT 추출
    local EXPECTED_USER=""
    EXPECTED_USER=$(git config user.name 2>/dev/null || git config --global user.name 2>/dev/null || echo "")

    local EXPECTED_PAT=""
    local _EMAIL=""
    if [ -n "${BW_SESSION:-}" ] && command -v bw_find_item_by_name &>/dev/null; then
        local _ALL_ITEMS_RAW _PARSED
        _ALL_ITEMS_RAW=$(bw list items --search "$BW_ITEM" --session "$BW_SESSION" </dev/null 2>&1)
        _PARSED=$(bw_find_item_by_name "${_ALL_ITEMS_RAW}"$'\n---ITEM_SPLIT---\n' "$BW_ITEM" 2>/dev/null || true)
        if [ -n "$_PARSED" ]; then
            _EMAIL=$(printf "%s" "$_PARSED" | cut -f1)
            EXPECTED_PAT=$(printf "%s" "$_PARSED" | cut -f3) # totp 필드 = PAT
        fi
    fi

    if [ -z "$EXPECTED_USER" ] && [ -n "$_EMAIL" ]; then
        EXPECTED_USER=$(printf "%s" "$_EMAIL" | cut -d'@' -f1)
    fi

    # 3. ~/.gradle/gradle.properties 확인
    local GRADLE_PROPS_DIR="$HOME/.gradle"
    local GRADLE_PROPS_FILE="$GRADLE_PROPS_DIR/gradle.properties"

    local CURRENT_USER=""
    local CURRENT_KEY=""
    local FILE_EXISTS=false

    if [ -f "$GRADLE_PROPS_FILE" ]; then
        FILE_EXISTS=true
        CURRENT_USER=$(grep -E '^\s*gpr\.user\s*=' "$GRADLE_PROPS_FILE" 2>/dev/null | head -n 1 | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        CURRENT_KEY=$(grep -E '^\s*gpr\.key\s*=' "$GRADLE_PROPS_FILE" 2>/dev/null | head -n 1 | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    fi

    # 4. 검증 및 수정 필요 여부 판단
    local NEEDS_UPDATE=false

    if [ "$FILE_EXISTS" = "false" ]; then
        NEEDS_UPDATE=true
    elif [ -z "$CURRENT_USER" ] || [ "$CURRENT_USER" != "$EXPECTED_USER" ]; then
        NEEDS_UPDATE=true
    elif [ -z "$CURRENT_KEY" ] || [ "$CURRENT_KEY" != "$EXPECTED_PAT" ]; then
        NEEDS_UPDATE=true
    fi

    if [ "$NEEDS_UPDATE" = "false" ]; then
        echo "ℹ️  ~/.gradle/gradle.properties 의 gpr.user 및 gpr.key 설정이 최신 상태입니다."
        return 0
    fi

    # 5. 사용자 입력 요청 (기본값 없음, y/n 대소문자 구분 없이 재요청)
    echo ""
    echo "⚠️  Gradle 프로젝트가 감지되었으나, ~/.gradle/gradle.properties 에 gpr.user / gpr.key 설정이 없거나 일치하지 않습니다."
    if [ "$FILE_EXISTS" = "true" ]; then
        local MASKED_CUR_KEY=""
        if [ -n "$CURRENT_KEY" ]; then
            MASKED_CUR_KEY="${CURRENT_KEY:0:4}****"
        fi
        echo "   [현재 설정] gpr.user='${CURRENT_USER}', gpr.key='${MASKED_CUR_KEY}'"
    else
        echo "   [현재 설정] ~/.gradle/gradle.properties 파일 없음"
    fi
    local MASKED_EXP_KEY=""
    if [ -n "$EXPECTED_PAT" ]; then
        MASKED_EXP_KEY="${EXPECTED_PAT:0:4}****"
    fi
    echo "   [권장 설정] gpr.user='${EXPECTED_USER}', gpr.key='${MASKED_EXP_KEY}'"
    echo ""

    local USER_CHOICE=""
    while true; do
        read -rp "❓ GitHub Packages 의존성 관리를 위해 ~/.gradle/gradle.properties 에 gpr.user 및 gpr.key 를 설정하시겠습니까? (y/n): " USER_CHOICE
        USER_CHOICE=$(echo "$USER_CHOICE" | tr '[:upper:]' '[:lower:]' | xargs)
        if [ "$USER_CHOICE" = "y" ] || [ "$USER_CHOICE" = "n" ]; then
            break
        fi
        echo "❌ 잘못된 입력입니다. 'y' 또는 'n' (대소문자 구분 없음)을 반드시 입력해주세요."
    done

    if [ "$USER_CHOICE" = "n" ]; then
        echo "ℹ️  gpr.user 및 gpr.key 설정을 추가/수정하지 않고 다음 단계로 진행합니다."
        return 0
    fi

    # 6. 'y' 입력 시 파일 생성 및 gpr.user, gpr.key 추가/수정
    mkdir -p "$GRADLE_PROPS_DIR"
    touch "$GRADLE_PROPS_FILE"

    if [ -z "$EXPECTED_USER" ]; then
        read -rp "🔑 gpr.user 에 설정할 GitHub 계정명(user.name)을 입력하세요: " EXPECTED_USER
    fi
    if [ -z "$EXPECTED_PAT" ]; then
        read -rp "🔑 gpr.key 에 설정할 GitHub PAT(Personal Access Token)을 입력하세요: " EXPECTED_PAT
    fi

    python3 -c "
import sys, re

filepath = sys.argv[1]
user_val = sys.argv[2]
key_val = sys.argv[3]

try:
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
except Exception:
    lines = []

def update_or_append(lines, key, val):
    pattern = re.compile(r'^\s*' + re.escape(key) + r'\s*=')
    updated = False
    new_lines = []
    for line in lines:
        if pattern.match(line):
            new_lines.append(f'{key}={val}\n')
            updated = True
        else:
            new_lines.append(line)
    if not updated:
        if new_lines and not new_lines[-1].endswith('\n'):
            new_lines.append('\n')
        new_lines.append(f'{key}={val}\n')
    return new_lines

lines = update_or_append(lines, 'gpr.user', user_val)
lines = update_or_append(lines, 'gpr.key', key_val)

with open(filepath, 'w', encoding='utf-8') as f:
    f.writelines(lines)
" "$GRADLE_PROPS_FILE" "$EXPECTED_USER" "$EXPECTED_PAT"

    echo "✅ ~/.gradle/gradle.properties 에 gpr.user=${EXPECTED_USER} 및 gpr.key 설정 완료!"
}

# ── rclone SFTP 마운트 설정 (systemd user 서비스 등록 포함) ─────────────────
# 기능:
#   - Bitwarden RemoteServer 폴더에서 username@host 기준으로 서버 정보 자동 조회
#   - rclone SFTP 리모트 설정 생성 (기존 설정 재생성)
#   - WSL2 환경에서 systemd 미활성화 시 /etc/wsl.conf 자동 수정 후 재시작 안내
#   - systemd user 서비스 파일 생성 및 등록/시작
# 인수:
#   $1 = bw username   (예: namupia)
#   $2 = bw host       (예: aiplus.im)
#   $3 = port          (예: 222)
#   $4 = remote_path   (예: ~/mount/aiplus  — ~ 는 /home/<username> 으로 치환)
#   $5 = local_path    (예: ~/mount/aiplus  — ~ 는 $HOME 으로 치환)
# 의존성:
#   bw_get_items_by_folder_name, BW_SESSION (bw-lib 로드 필요)
#   DEVTOOLS2 환경변수
setup_rclone_sftp_mount() {
    local BW_USERNAME="$1"
    local BW_HOST="$2"
    local PORT="${3:-22}"
    local INPUT_REMOTE_PATH="${4:-~/}"
    local INPUT_LOCAL_PATH="${5:-$HOME/mount/$BW_USERNAME}"

    echo "⚙️  SFTP 마운트 설정 진행 중 (${BW_USERNAME}@${BW_HOST}:${PORT})..."

    # ── 1. WSL2 환경에서 systemd 활성화 여부 확인 및 자동 처리 ────────────────
    local IS_WSL2=false
    if grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL2=true
    fi

    if [ "$IS_WSL2" = true ]; then
        # systemd 실제 동작 여부 확인
        if ! systemctl --user status >/dev/null 2>&1; then
            echo ""
            echo "⚠️  WSL2에서 systemd가 활성화되어 있지 않습니다."
            echo "   rclone SFTP 마운트는 systemd user 서비스로 동작하므로 systemd가 필요합니다."
            echo ""

            # /etc/wsl.conf 에 [boot] systemd=true 자동 추가 (sudo 필요)
            local WSL_CONF="/etc/wsl.conf"
            local NEEDS_SYSTEMD=true
            if grep -q 'systemd\s*=\s*true' "$WSL_CONF" 2>/dev/null; then
                NEEDS_SYSTEMD=false
            fi

            if [ "$NEEDS_SYSTEMD" = true ]; then
                echo "⏳ /etc/wsl.conf 에 systemd 활성화 설정을 추가합니다... (sudo 필요)"
                if grep -q '\[boot\]' "$WSL_CONF" 2>/dev/null; then
                    # [boot] 섹션이 이미 있으면 그 아래에 systemd=true 삽입
                    sudo sed -i '/^\[boot\]/a systemd=true' "$WSL_CONF"
                else
                    # [boot] 섹션 자체가 없으면 파일 끝에 추가
                    printf '\n[boot]\nsystemd=true\n' | sudo tee -a "$WSL_CONF" > /dev/null
                fi
                echo "✅ /etc/wsl.conf 에 systemd=true 추가 완료!"
            else
                echo "ℹ️  /etc/wsl.conf 에는 이미 systemd=true 가 설정되어 있습니다."
                echo "   WSL 인스턴스가 아직 재시작되지 않아 systemd가 비활성 상태입니다."
            fi

            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "🔄  WSL 인스턴스를 재시작해야 systemd가 활성화됩니다."
            echo ""
            echo "   PowerShell 에서 아래 명령어를 실행하세요:"
            echo ""
            echo "     wsl --shutdown"
            echo ""
            echo "   재시작 후 이 스크립트를 다시 실행하면 SFTP 마운트가 자동 완료됩니다."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            return 2
        fi
    fi

    # ── 2. Bitwarden RemoteServer 폴더에서 서버 정보 조회 ─────────────────────
    local RAW_SERVER_ITEMS
    RAW_SERVER_ITEMS=$(bw_get_items_by_folder_name "RemoteServer") || return 1

    local _PY_SERVER
    _PY_SERVER=$(mktemp /tmp/bw_server_XXXXXX.py)
    cat > "$_PY_SERVER" <<'PYEOF'
import sys, json, re

bw_username = sys.argv[1]
bw_host = sys.argv[2]

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
            if username == bw_username and bw_host in clean_uri:
                item_id = item.get('id', '')
                print(f"{item_id}\t{username}\t{clean_uri}")
                sys.exit(0)
    except Exception:
        pass
PYEOF

    local SERVER_INFO
    SERVER_INFO=$(printf "%s" "$RAW_SERVER_ITEMS" | python3 "$_PY_SERVER" "$BW_USERNAME" "$BW_HOST")
    rm -f "$_PY_SERVER"

    if [ -z "$SERVER_INFO" ]; then
        echo "❌ Bitwarden 'RemoteServer' 폴더에서 ${BW_USERNAME}@${BW_HOST} 서버 항목을 찾을 수 없습니다."
        return 1
    fi

    local ITEM_ID ACTUAL_USERNAME RAW_URI ACTUAL_HOST ACTUAL_PORT
    ITEM_ID=$(echo "$SERVER_INFO" | cut -f1)
    ACTUAL_USERNAME=$(echo "$SERVER_INFO" | cut -f2)
    RAW_URI=$(echo "$SERVER_INFO" | cut -f3)

    if [[ "$RAW_URI" == *:* ]]; then
        ACTUAL_HOST="${RAW_URI%:*}"
        ACTUAL_PORT="${RAW_URI##*:}"
    else
        ACTUAL_HOST="$RAW_URI"
        ACTUAL_PORT="$PORT"
    fi

    local SERVER_PASS
    SERVER_PASS=$(bw get password "$ITEM_ID" --session "$BW_SESSION" 2>/dev/null || echo "")

    # ── 3. 경로 ~ 치환 ────────────────────────────────────────────────────────
    local REMOTE_MOUNT_PATH LOCAL_MOUNT_PATH
    REMOTE_MOUNT_PATH="${INPUT_REMOTE_PATH/#\~//home/$ACTUAL_USERNAME}"
    LOCAL_MOUNT_PATH="${INPUT_LOCAL_PATH/#\~/$HOME}"

    echo "   원격 마운트 경로 (서버): $REMOTE_MOUNT_PATH"
    echo "   로컬 마운트 경로 (로컬): $LOCAL_MOUNT_PATH"
    mkdir -p "$LOCAL_MOUNT_PATH"

    # ── 4. rclone 바이너리 확인 ───────────────────────────────────────────────
    local RCLONE_BIN FUSERMOUNT_BIN
    RCLONE_BIN=$(command -v rclone 2>/dev/null || echo "/usr/bin/rclone")
    FUSERMOUNT_BIN=$(command -v fusermount 2>/dev/null || command -v fusermount3 2>/dev/null || echo "/usr/bin/fusermount")

    if [ ! -x "$RCLONE_BIN" ]; then
        echo "❌ rclone이 설치되어 있지 않습니다."
        return 1
    fi

    # ── 5. rclone 리모트 설정 생성 ────────────────────────────────────────────
    local SERVICE_NAME="rclone-${ACTUAL_USERNAME}@${ACTUAL_HOST}_${ACTUAL_PORT}"

    # ── 6. rclone.conf 경로 결정 (포터블 개발 환경 우선)
    local RCLONE_CONF
    if [ -n "${DEVTOOLS2:-}" ]; then
        RCLONE_CONF="${DEVTOOLS2}/modules/rclone/.config/rclone.conf"
    else
        RCLONE_CONF="$HOME/.config/rclone/rclone.conf"
    fi
    # rclone.conf 디렉터리가 없으면 생성
    mkdir -p "$(dirname "$RCLONE_CONF")"

    if "$RCLONE_BIN" config show "$SERVICE_NAME" --config "$RCLONE_CONF" >/dev/null 2>&1; then
        echo "⚠️  기존 Rclone 리모트 ($SERVICE_NAME) 설정 삭제 후 재생성합니다..."
        "$RCLONE_BIN" config delete "$SERVICE_NAME" --config "$RCLONE_CONF" 2>/dev/null || true
    fi

    echo "⏳ Rclone SFTP 리모트 ($SERVICE_NAME) 설정 중..."
    local RCLONE_ARGS
    RCLONE_ARGS=(config create "$SERVICE_NAME" sftp host "$ACTUAL_HOST" user "$ACTUAL_USERNAME" port "$ACTUAL_PORT" --config "$RCLONE_CONF")
    if [ -n "$SERVER_PASS" ]; then
        # rclone pass 파라미터는 rclone obscure 로 난독화된 값을 요구함 (평문 불가)
        local OBSCURED_PASS
        OBSCURED_PASS=$("$RCLONE_BIN" obscure "$SERVER_PASS" 2>/dev/null || echo "")
        if [ -n "$OBSCURED_PASS" ]; then
            RCLONE_ARGS+=(pass "$OBSCURED_PASS")
        fi
    fi
    "$RCLONE_BIN" "${RCLONE_ARGS[@]}" >/dev/null 2>&1
    echo "✅ Rclone 리모트 설정 완료! (config: $RCLONE_CONF)"

    # ── 7. systemd user 서비스 파일 생성 및 등록 ─────────────────────────────
    local SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
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
    systemctl --user daemon-reload
    systemctl --user enable "${SERVICE_NAME}.service"
    systemctl --user restart "${SERVICE_NAME}.service"
    echo "✅ SFTP 마운트 서비스 시작 완료! (${LOCAL_MOUNT_PATH})"
    echo "   상태 확인: systemctl --user status ${SERVICE_NAME}.service"
}
