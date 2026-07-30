#!/usr/bin/env bash
# ==============================================================================
# Goono-ELN 프로젝트 설정 스크립트
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

TARGET_DIR="$HOME/workspaces/goono/Goono_ELN"
REPO_URL="https://github.com/redwit-dev/Goono-ELN.git"

echo "🚀 [Goono-ELN] 프로젝트 설정을 시작합니다."
echo "   대상 경로: $TARGET_DIR"

# 1. 깃 클론 (Bitwarden 인증 자동화)
if [ -d "$TARGET_DIR/.git" ]; then
    echo "ℹ️  이미 깃 저장소가 존재합니다. 클론 단계를 건너땁니다."
else
    echo "⏳ Bitwarden 인증 및 깃 클론 준비 중..."
    bw_ensure_session || exit 1

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

# 2. .nvim.lua 파일 생성
echo "⚙️  .nvim.lua 설정 파일 생성 중..."
cat > "$TARGET_DIR/.nvim.lua" <<'EOF'
PROJECT_ROOT = "./"
JDK_VERSION = 21
MAIN_CLASS = "so.goono.GoonoELNApplication"
EOF
echo "✅ .nvim.lua 생성 완료!"

# 3. command-palette 이전 실행 설정 저장 (~/.ghostty/state.properties)
echo "⚙️  Ghostty / command-palette 이전 실행 프로필 저장 중..."
GHOSTTY_DIR="$HOME/.ghostty"
mkdir -p "$GHOSTTY_DIR"
STATE_FILE="$GHOSTTY_DIR/state.properties"

NORM_CWD=$(echo "$TARGET_DIR" | tr '\\' '/' | sed 's/\/$//')
PROJ_KEY=$(echo -n "$NORM_CWD" | md5sum | awk '{print $1}')
FULL_KEY="${PROJ_KEY}.gradle_run.profile"
TARGET_VAL="0_DEVELOP,0_LOCAL,s2"

touch "$STATE_FILE"
TMP_STATE=$(mktemp)
grep -v "^${FULL_KEY}=" "$STATE_FILE" > "$TMP_STATE" 2>/dev/null || true
echo "${FULL_KEY}=${TARGET_VAL}" >> "$TMP_STATE"
mv "$TMP_STATE" "$STATE_FILE"
echo "✅ 실행 프로필 저장 완료 ($STATE_FILE)"
echo "   Key: $FULL_KEY"
echo "   Value: $TARGET_VAL"

# 4. .vscode 설정 생성 (settings.json, launch.json)
echo "⚙️  .vscode 설정 파일 생성 중..."
mkdir -p "$TARGET_DIR/.vscode"

cat > "$TARGET_DIR/.vscode/settings.json" <<'EOF'
{
  "java.configuration.runtimes": [
    {
      "name": "JavaSE-21",
      "path": "/var/opt/_devtools2/modules/java/jdk-21",
      "default": true
    }
  ],
  "java.import.gradle.java.home": "/var/opt/_devtools2/modules/java/jdk-21"
}
EOF

cat > "$TARGET_DIR/.vscode/launch.json" <<'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "java",
      "name": "GoonoELNApplication",
      "request": "launch",
      "mainClass": "so.goono.GoonoELNApplication",
      "projectName": "goono-eln",
      "vmArgs": ["-Dfile.encoding=UTF-8", "-Dspring.profiles.active=0_DEVVELOP,0_LOCAL,s2"]
    }
  ]
}
EOF
echo "✅ .vscode/settings.json 및 .vscode/launch.json 생성 완료!"

echo "🎉 [Goono-ELN] 프로젝트 설정이 성공적으로 완료되었습니다!"
