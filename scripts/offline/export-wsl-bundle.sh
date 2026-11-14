#!/usr/bin/env bash
# ==============================================================================
# DevTools2 개발 환경 내보내기 (오프라인 PC 설치용) — WSL (export-wsl-bundle.sh)
# ==============================================================================
#
# ■ 목적:
#   지금 PC 의 DevTools2 개발 환경(WSL 배포판 + Windows 쪽 단축키·글꼴·터미널·VS Code·Zed)을 폴더 하나로 묶어,
#   인터넷이 없는 PC 에서 묶음 안의 "DevTools2 개발 환경 가져오기.cmd" 하나만 실행하면 같은 환경이 구성되게 합니다.
#   실행: 명령 팔레트(Alt + C) → 🖥️ 시스템 → 개발 환경 내보내기 (오프라인 PC 설치용) (WSL 에서만 보임)
#
# ■ 왜 설치 스크립트를 다시 돌리지 않고 배포판을 통째로 옮기나:
#   설치 스크립트는 GitHub 에서 받아 실행하는 온라인 전용 구조이고(AGENTS.md 2번), JDK·Node·Mason 도구 등도 실행 중에
#   인터넷에서 받습니다. apt 패키지(/usr)는 $DEVTOOLS2 만 복사해서는 옮겨지지 않습니다. 그래서 실행 중인 배포판의
#   파일 시스템을 tar 로 묶어(wsl --import 가 그대로 받는 rootfs 형식) 통째로 옮깁니다.
#
# ■ 묶음 구성 (<저장 위치>/devtools2-offline-<날짜>/):
#   DevTools2 개발 환경 가져오기.cmd  ← 오프라인 PC 에서 이것만 실행 (관리자 권한으로 다시 실행해 가져오기 스크립트를 띄움)
#   import-devtools2-offline.ps1  ← 가져오기 본체 (scripts/offline/ 의 같은 파일)
#   devtools2-rootfs.tar.gz       ← WSL 배포판 (wsl --import 가 gzip 을 내용으로 판별해 바로 가져옴)
#   windows/                      ← autohotkey/ fonts/ terminal/ vscode/ zed/ wsl/(WSL 설치 파일) wslconfig.txt
#   manifest.txt · 읽어보기.txt
#
# ■ 인증 정보는 기본으로 빼고 묶습니다 (오프라인 PC 에서는 쓸 수 없고, 묶음을 옮기다 잃어버려도 안전하도록).
#   "인증 정보를 모두 넣을까요?"에 Y 로 답하면 아래 항목도 그대로 넣습니다(오프라인 PC 가 사내망이라 그 안의 서버·저장소에
#   쓸 때 등). N(기본)이면 SSH 개인 키만 따로 넣을지 묻습니다:
#   GitHub 토큰(.git-credentials, gh), Bitwarden 데이터·세션, AI API 키(secrets.env), rclone 접속 정보, SSH 개인 키(선택),
#   ~/.gradle/gradle.properties 의 비밀 값(GitHub Packages 토큰, Maven Central 비밀번호, GPG 서명 정보) —
#   gradle.properties 는 통째로 빼지 않고 비밀 값만 지운 사본을 넣습니다(JDK 경로 org.gradle.java.installations.paths 가
#   없으면 Gradle 이 Java 8 툴체인을 못 찾아 빌드 실패). git 사용자 이름·이메일은 비밀이 아니고 커밋에 필요해 남깁니다.
#   그 밖에 함께 빼는 것: AI 도구 로그인(Claude ~/.claude/.credentials.json·~/.claude.json, Codex ~/.codex/auth.json,
#   Gemini ~/.gemini/oauth_creds.json), GPG 키링(~/.gnupg), ~/.npmrc·~/.netrc·~/.docker/config.json·~/.aws·~/.kube,
#   셸·REPL 입력 기록(~/.bash_history 등 — 명령줄에 친 비밀 값이 남을 수 있음), <password> 가 든 Maven settings.xml,
#   SSH 는 config·known_hosts·*.pub·authorized_keys 만 남기고 나머지 파일(이름과 무관하게 개인 키로 봄),
#   다른 사용자의 홈과 /root 의 내용(폴더 자체는 남김 — 다중 사용자 서버에서 남의 인증 정보가 섞이지 않도록).
#   ⚠️ /etc/shadow(계정 비밀번호 해시)는 빼면 가져온 배포판에서 sudo 가 동작하지 않아 그대로 들어갑니다 → 읽어보기에 안내.
#
# ■ 같이 옮기지 않는 것: ~/.cache(jdtls 색인 등 다시 만들어짐), 로그, apt 내려받기 캐시, /tmp·/mnt 등 시스템 폴더,
#   (선택) ~/workspaces 프로젝트 소스
#
# ■ 이 스크립트는 명령 팔레트처럼 $DEVTOOLS2 로컬 파일로 실행됩니다(설치 스크립트가 아님 — AGENTS.md 2번 대상 아님).
#   오프라인 PC 에서 실행되는 가져오기 스크립트만 AGENTS.md 의 "오프라인 PC 개발 환경 가져오기 예외"에 해당합니다.
# ==============================================================================

set -u

DEVTOOLS2="${DEVTOOLS2:-/var/opt/_devtools2}"
# shellcheck disable=SC1091
source "$DEVTOOLS2/scripts/linux/dev-env/_common.sh" || { echo "❌ 공통 함수를 불러오지 못했습니다: $DEVTOOLS2/scripts/linux/dev-env/_common.sh"; exit 1; }

if ! grep -qi microsoft /proc/version 2>/dev/null; then
    print_error "WSL 에서만 실행할 수 있습니다. (리눅스 네이티브용 내보내기는 아직 지원하지 않음)"
    exit 1
fi

DISTRO="${WSL_DISTRO_NAME:-devtools2}"
ME="$(id -un)"
HOME_REL="${HOME#/}"   # home/<사용자> (tar 안의 경로)
WIN_HOME="$(get_win_userprofile 2>/dev/null || true)"
if [ -z "$WIN_HOME" ] || [ ! -d "$WIN_HOME" ]; then
    print_error "Windows 사용자 폴더를 찾지 못했습니다 (Windows 연동이 꺼져 있으면 WSL 을 다시 시작하세요)."
    exit 1
fi
WIN_LOCAL="$WIN_HOME/AppData/Local"
WIN_ROAMING="$WIN_HOME/AppData/Roaming"

echo ""
print_step "📦 DevTools2 개발 환경 내보내기 — 오프라인 PC 설치용 (배포판: $DISTRO)"
echo "   인터넷이 없는 PC 에서 묶음 안의 'DevTools2 개발 환경 가져오기.cmd' 하나로 같은 개발 환경을 구성합니다."
echo ""

# ── 1. 옵션 ──────────────────────────────────────────────────────────────────
DEFAULT_DEST="${DT2_OFFLINE_DEST:-$WIN_HOME/devtools2-offline}"   # DT2_OFFLINE_DEST 로 기본 저장 위치 변경 가능
prompt_text DEST_BASE "💾 묶음을 저장할 폴더 (WSL 경로, Windows 드라이브는 /mnt/<드라이브>/...)" "$DEFAULT_DEST"
DEST_BASE="${DEST_BASE:-$DEFAULT_DEST}"
INCLUDE_WS=false
if [ -d "$HOME/workspaces" ]; then
    _ws_size=$(du -sh "$HOME/workspaces" 2>/dev/null | cut -f1)
    prompt_confirm "📁 프로젝트 소스(~/workspaces, ${_ws_size})도 함께 넣을까요?" "N" && INCLUDE_WS=true
fi
INCLUDE_CRED=false
KEEP_SSH=false
echo "   ℹ️  인증 정보: GitHub 토큰·gh, Bitwarden, AI API 키(secrets.env), AI 도구 로그인(Claude·Codex·Gemini), rclone 접속 정보,"
echo "      SSH 개인 키, GPG 키링, gradle.properties 의 토큰·비밀번호, npm·Docker·클라우드 자격 증명, 셸 입력 기록,"
echo "      다른 사용자 홈·/root 의 내용 — 오프라인에서는 쓸 수 없어 기본으로 뺍니다."
if prompt_confirm "🔐 인증 정보를 모두 함께 넣을까요? (사내망 서버·저장소를 쓸 때만)" "N"; then
    INCLUDE_CRED=true
    KEEP_SSH=true
    print_warn "인증 정보가 묶음에 들어갑니다. 묶음 파일을 옮기고 보관할 때 주의하세요."
elif find "$HOME/.ssh" -mindepth 1 -maxdepth 1 ! -name config ! -name 'known_hosts*' ! -name authorized_keys ! -name '*.pub' 2>/dev/null | grep -q .; then
    echo "   ℹ️  오프라인 PC 가 사내망이고 그 안의 Git·개발 서버에 SSH 로 접속한다면 SSH 키만 남길 수 있습니다."
    prompt_confirm "🔑 SSH 개인 키(~/.ssh 의 config·known_hosts·*.pub 외 파일)만 함께 넣을까요? (기본: 빼기)" "N" && KEEP_SSH=true
fi

STAMP="$(date +%Y%m%d-%H%M)"
OUT="$DEST_BASE/devtools2-offline-$STAMP"
mkdir -p "$OUT/windows" || { print_error "저장 폴더를 만들지 못했습니다: $OUT"; exit 1; }

# 용량 안내 (배포판 사용량 기준 — 압축하면 대략 절반 이하)
_used_kb=$(df -k --output=used / | tail -1 | tr -d ' ')
_free_kb=$(df -k --output=avail "$OUT" | tail -1 | tr -d ' ')
echo "   배포판 사용량 약 $((_used_kb / 1024 / 1024))GB, 저장 위치 남은 공간 약 $((_free_kb / 1024 / 1024))GB"
if [ "$_free_kb" -lt $((_used_kb / 2)) ]; then
    print_warn "저장 위치 공간이 부족할 수 있습니다 (압축 후 크기는 사용량의 절반 안팎)."
    prompt_confirm "계속할까요?" "N" || exit 1
fi

print_info "배포판 전체를 읽으려면 관리자(sudo) 권한이 필요합니다."
sudo -v || { print_error "sudo 인증에 실패했습니다."; exit 1; }

# ── 2. 인증 정보 정리본 (gradle.properties 는 비밀 값만 지운 사본) ─────────────
# ⚠️ mktemp 가 실패해 STAGE 가 비면 아래 "> $STAGE/$HOME_REL/.gradle/gradle.properties" 가 실제 ~/.gradle/gradle.properties 를
#    가리켜 읽기 전에 잘려 비워지므로 반드시 중단합니다.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/dt2-offline-XXXXXX")" && [ -n "$STAGE" ] && [ -d "$STAGE" ] || { print_error "임시 폴더를 만들지 못했습니다."; exit 1; }
trap 'sudo rm -rf "$STAGE" 2>/dev/null' EXIT
OVERLAY=()
if ! $INCLUDE_CRED && [ -f "$HOME/.gradle/gradle.properties" ]; then
    mkdir -p "$STAGE/$HOME_REL/.gradle"
    # 비밀 키: gpr.*(GitHub Packages), centralUsername/centralPassword(Maven Central), signing.*(GPG) — 주석·빈 줄·그 밖의 값은 유지
    #   + 이름에 password·passwd·secret·token·apikey·credential 이 든 키(systemProp.*.proxyPassword, ossrhPassword 등)도 지웁니다(대소문자 무시).
    grep -viE '^[[:space:]]*(gpr\.(user|key)|centralUsername|centralPassword|signing\.[A-Za-z0-9_.]+|[^#=[:space:]]*(password|passwd|secret|token|apikey|api_key|credential)[^=[:space:]]*)[[:space:]]*=' \
        "$HOME/.gradle/gradle.properties" > "$STAGE/$HOME_REL/.gradle/gradle.properties"
    chmod 600 "$STAGE/$HOME_REL/.gradle/gradle.properties"
    OVERLAY+=("$HOME_REL/.gradle/gradle.properties")
fi

# ── 3. 배포판 묶기 (rootfs tar.gz) ───────────────────────────────────────────
EXCLUDES=(
    ./proc ./sys ./dev ./run ./tmp ./mnt ./lost+found ./init ./swapfile
    ./var/tmp ./var/cache/apt/archives ./var/log/journal
    "./root/.cache" "./$HOME_REL/.cache"
    "./$HOME_REL/.vscode-server/data/logs" "./$HOME_REL/.local/state/nvim/*.log"
    "./var/opt/_devtools2/data/logs"
)
# 인증 정보 (모두 넣기를 고르지 않았을 때)
if ! $INCLUDE_CRED; then
    EXCLUDES+=(
        "./$HOME_REL/.git-credentials" "./$HOME_REL/.config/gh/hosts.yml"
        "./$HOME_REL/.config/Bitwarden CLI" "./$HOME_REL/.bw_session*"
        "./$HOME_REL/.config/devtools2/secrets.env" "./$HOME_REL/.config/rclone/rclone.conf"
        "./$HOME_REL/.config/rclone/keys"
        "./$HOME_REL/.gradle/gradle.properties"
        # AI 도구 로그인 정보
        "./$HOME_REL/.claude/.credentials.json" "./$HOME_REL/.claude.json" "./$HOME_REL/.claude.json.backup*"
        "./$HOME_REL/.codex/auth.json" "./$HOME_REL/.gemini/oauth_creds.json" "./$HOME_REL/.gemini/google_accounts.json"
        # GPG 키링(Maven Central 서명 키 포함), 패키지·클라우드 자격 증명
        "./$HOME_REL/.gnupg" "./$HOME_REL/.npmrc" "./$HOME_REL/.netrc"
        "./$HOME_REL/.docker/config.json" "./$HOME_REL/.aws" "./$HOME_REL/.kube"
        "./$HOME_REL/.m2/settings-security.xml" "./var/opt/_devtools2/data/.m2/settings-security.xml"
        # 셸·REPL 입력 기록 (명령줄에 친 토큰·비밀번호가 남을 수 있음)
        "./$HOME_REL/.bash_history" "./$HOME_REL/.zsh_history" "./$HOME_REL/.python_history"
        "./$HOME_REL/.node_repl_history" "./$HOME_REL/.psql_history" "./$HOME_REL/.mysql_history"
        # /root 의 내용 (폴더 자체는 남김)
        "./root/*"
    )
    # Maven settings.xml 은 미러 설정만 있을 수도 있어 <password> 가 있을 때만 뺍니다 (~/.m2 는 data/.m2 로 가는 링크일 수 있음)
    _m2_settings="$(readlink -f "$HOME/.m2/settings.xml" 2>/dev/null)"
    if [ -n "$_m2_settings" ] && [ -f "$_m2_settings" ] && grep -q '<password>' "$_m2_settings" 2>/dev/null; then
        EXCLUDES+=(".${_m2_settings}")
    fi
    # 다른 사용자의 홈 내용 (다중 사용자 — add-devtools2-user.sh). 계정·폴더는 남기고 내용만 뺍니다.
    for _h in /home/*; do
        [ -d "$_h" ] || continue
        [ "$(readlink -f "$_h")" = "$(readlink -f "$HOME")" ] && continue
        EXCLUDES+=(".${_h}/*")
    done
fi
# SSH: 이름(id_*·*.pem)이 아니라 "공개해도 되는 파일만 남기는" 방식으로 거릅니다 — github_ed25519 같은 이름의 개인 키도 빠지게.
_SSH_PRIVATE=()
if [ -d "$HOME/.ssh" ]; then
    for _f in "$HOME"/.ssh/* "$HOME"/.ssh/.[!.]*; do
        [ -e "$_f" ] || [ -L "$_f" ] || continue
        case "$(basename "$_f")" in
            config|known_hosts|known_hosts.old|authorized_keys|*.pub) ;;
            *) _SSH_PRIVATE+=("$_f") ;;
        esac
    done
fi
if ! $KEEP_SSH; then
    for _f in "${_SSH_PRIVATE[@]}"; do EXCLUDES+=(".${_f}"); done
fi
$INCLUDE_WS || EXCLUDES+=("./$HOME_REL/workspaces")
# 저장 위치가 배포판 안이면(예: ~/backup) 자기 자신을 묶지 않게
case "$OUT" in /mnt/*) ;; *) EXCLUDES+=(".${OUT}") ;; esac

TAR_ARGS=(--create --gzip --numeric-owner --preserve-permissions --xattrs --acls --one-file-system --anchored
          --warning=no-file-changed --warning=no-file-removed --warning=no-socket)
for e in "${EXCLUDES[@]}"; do TAR_ARGS+=("--exclude=$e"); done
ROOTFS="$OUT/devtools2-rootfs.tar.gz"

# [진행률] tar 가 읽은 양 / 예상 전체 양(배포판 사용량 - 빼는 큰 폴더)으로 퍼센트를 표시합니다.
#   GNU tar 의 --checkpoint 는 레코드(기본 10KiB)마다 세므로 25,000 레코드(약 250MB)마다 진행 표시 스크립트를 부릅니다.
#   예상 양은 대략값이라(압축 전 크기 기준, 시스템 폴더 일부 포함) 끝날 때 100% 에 못 미치거나 조금 넘을 수 있습니다.
_skip_kb=$(du -sk "$HOME/.cache" 2>/dev/null | cut -f1)
# ⚠️ "$(du … | cut -f1 || echo 0)" 의 || 는 cut 의 종료 코드를 봐서 실행되지 않습니다 → ~/workspaces 가 없으면
#    빈 값이 산술식에 들어가 "산술 문법 오류" 로 스크립트가 중단됐습니다. 값을 먼저 받아 기본값을 붙입니다.
if ! $INCLUDE_WS; then
    _ws_kb=$(du -sk "$HOME/workspaces" 2>/dev/null | cut -f1)
    _skip_kb=$(( ${_skip_kb:-0} + ${_ws_kb:-0} ))
fi
EST_BYTES=$(( (_used_kb - ${_skip_kb:-0}) * 1024 ))
cat > "$STAGE/progress.sh" <<'PROG'
#!/bin/sh
# tar --checkpoint-action=exec 로 불림: TAR_CHECKPOINT(레코드 수) × 10240 = 읽은 바이트
read_b=$(( ${TAR_CHECKPOINT:-0} * 10240 ))
pct=$(( read_b * 100 / ${DT2_EST_BYTES:-1} )); [ "$pct" -gt 99 ] && pct=99
out_sz=$(du -h "$DT2_ROOTFS" 2>/dev/null | cut -f1)
msg=$(awk -v p="$pct" -v r="$read_b" -v t="${DT2_EST_BYTES:-0}" -v o="${out_sz:-0}" \
    'BEGIN { printf "\r   진행: %3d%%  (읽음 %.1f / 약 %.1f GB, 압축 파일 %s)   ", p, r / 1073741824, t / 1073741824, o }')
{ printf '%s' "$msg" > /dev/tty; } 2>/dev/null || printf '%s' "$msg" >&2
PROG
chmod 755 "$STAGE/progress.sh"

print_step "🗜️  배포판 묶는 중 (수십 분 걸릴 수 있습니다)..."
# 첫 번째 -C / 묶음은 "./경로"(--anchored 제외 대상), 두 번째 -C $STAGE 묶음은 "home/..."(제외 패턴과 겹치지 않음)
sudo env DT2_EST_BYTES="$EST_BYTES" DT2_ROOTFS="$ROOTFS" \
    tar "${TAR_ARGS[@]}" --checkpoint=25000 --checkpoint-action="exec=$STAGE/progress.sh" \
    --file="$ROOTFS" -C / . -C "$STAGE" "${OVERLAY[@]}"
_tar_rc=$?
echo ""
# GNU tar: 1 = 읽는 중 바뀐 파일이 있음(실행 중인 배포판이라 정상), 2 이상 = 오류
if [ "$_tar_rc" -gt 1 ]; then
    print_error "배포판 묶기에 실패했습니다 (tar 종료 코드 $_tar_rc)."
    exit 1
fi
sudo chown "$(id -u):$(id -g)" "$ROOTFS" 2>/dev/null
chmod 600 "$ROOTFS" 2>/dev/null || true   # /etc/shadow 가 들어 있으므로 (Windows 드라이브(/mnt)에서는 효과 없을 수 있음)
print_done "배포판: $(du -h "$ROOTFS" | cut -f1)"

# ── 4. Windows 쪽 파일 ───────────────────────────────────────────────────────
W="$OUT/windows"
copy_dir() {   # copy_dir <원본> <대상> <설명>
    if [ -d "$1" ]; then
        mkdir -p "$2"
        # rsync 전체 진행률(--info=progress2). Windows 드라이브(/mnt/*)는 리눅스 권한·소유자를 못 쓰므로 -rlt 만 (내용·링크·시간)
        if command -v rsync >/dev/null 2>&1; then
            echo "   $3 복사 중..."
            rsync -rlt --info=progress2 --no-inc-recursive "$1/" "$2/" 2>/dev/null
            echo ""
        else
            cp -a "$1/." "$2/" 2>/dev/null
        fi
        print_done "$3 ($(du -sh "$2" 2>/dev/null | cut -f1))"
    else
        print_warn "$3 — 없음, 건너뜀 ($1)"
    fi
}
print_step "🪟 Windows 쪽 파일 모으는 중..."
copy_dir "$WIN_LOCAL/_devtools2/modules/autohotkey" "$W/autohotkey" "AutoHotkey (포터블 + 단축키 스크립트)"
mkdir -p "$W/fonts" && cp -a "$DEVTOOLS2"/assets/fonts/*.ttf "$W/fonts/" 2>/dev/null && print_done "글꼴 ($(ls "$W/fonts" | wc -l)개)"
_wt=$(ls -d "$WIN_LOCAL"/Packages/Microsoft.WindowsTerminal_*/LocalState 2>/dev/null | head -1)
if [ -n "$_wt" ] && [ -f "$_wt/settings.json" ]; then
    mkdir -p "$W/terminal" && cp "$_wt/settings.json" "$W/terminal/settings.json" && print_done "Windows Terminal 설정"
else
    print_warn "Windows Terminal 설정 — 없음, 건너뜀"
fi
copy_dir "$WIN_LOCAL/Programs/Microsoft VS Code" "$W/vscode/app" "VS Code 프로그램"
copy_dir "$WIN_HOME/.vscode/extensions" "$W/vscode/extensions" "VS Code 확장 (Windows 쪽)"
mkdir -p "$W/vscode/user" && cp "$WIN_ROAMING/Code/User/"*.json "$W/vscode/user/" 2>/dev/null
copy_dir "$WIN_LOCAL/Programs/Zed" "$W/zed/app" "Zed 프로그램"
copy_dir "$WIN_LOCAL/Zed/extensions" "$W/zed/extensions" "Zed 확장 (Windows 쪽)"
mkdir -p "$W/zed/config" && cp "$WIN_ROAMING/Zed/settings.json" "$WIN_ROAMING/Zed/keymap.json" "$W/zed/config/" 2>/dev/null
# .wslconfig: memory 는 PC 마다 다르므로 빼고 넣음 (가져오기에서 그 PC 메모리로 계산)
if [ -f "$WIN_HOME/.wslconfig" ]; then
    grep -viE '^[[:space:]]*memory[[:space:]]*=' "$WIN_HOME/.wslconfig" | tr -d '\r' > "$W/wslconfig.txt"
    print_done ".wslconfig (memory 제외)"
fi

# WSL 설치 파일: 지금 PC 와 같은 버전 (오프라인 PC 에 WSL 이 없거나 오래된 경우용)
_wsl_ver=$(wsl.exe --version 2>/dev/null | tr -d '\0\r' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -n "$_wsl_ver" ]; then
    _tag="${_wsl_ver%.*}"
    _arch=x64; [ "$(uname -m)" = "aarch64" ] && _arch=arm64
    mkdir -p "$W/wsl"
    echo "   WSL 설치 파일 받는 중 (wsl.${_wsl_ver}.${_arch}.msi)..."
    if curl -fL --progress-bar --max-time 1800 -o "$W/wsl/wsl.${_wsl_ver}.${_arch}.msi" \
        "https://github.com/microsoft/WSL/releases/download/${_tag}/wsl.${_wsl_ver}.${_arch}.msi"; then
        print_done "WSL 설치 파일 (${_wsl_ver})"
    else
        rm -f "$W/wsl/wsl.${_wsl_ver}.${_arch}.msi"
        print_warn "WSL 설치 파일을 받지 못했습니다. 오프라인 PC 에 WSL 이 없다면 https://github.com/microsoft/WSL/releases 에서 wsl.${_wsl_ver}.${_arch}.msi 를 받아 windows/wsl/ 에 넣으세요."
    fi
fi

# ── 5. 가져오기 스크립트 · 안내 ──────────────────────────────────────────────
cp "$DEVTOOLS2/scripts/offline/import-devtools2-offline.ps1" "$OUT/"
# .cmd 는 CRLF 여야 cmd.exe 가 바르게 읽음
sed 's/\r$//; s/$/\r/' "$DEVTOOLS2/scripts/offline/import-launcher.cmd" > "$OUT/DevTools2 개발 환경 가져오기.cmd"
{
    echo "DevTools2 offline bundle"
    echo "created=$(date '+%Y-%m-%d %H:%M')"
    echo "distro=$DISTRO"
    echo "user=$ME"
    echo "devtools2_commit=$(git -C "$DEVTOOLS2" rev-parse --short HEAD 2>/dev/null)"
    echo "wsl_version=${_wsl_ver:-unknown}"
    echo "include_workspaces=$INCLUDE_WS"
    echo "include_credentials=$INCLUDE_CRED"
    echo "include_ssh_keys=$KEEP_SSH"
} > "$OUT/manifest.txt"
cat > "$OUT/읽어보기.txt" <<EOF
DevTools2 개발 환경 내보내기 — 오프라인 PC 설치용 ($(date '+%Y-%m-%d'))

[오프라인 PC 에서]
1. 이 폴더를 통째로 오프라인 PC 에 복사합니다 (개발자 드라이브가 있으면 그곳 권장).
2. "DevTools2 개발 환경 가져오기.cmd" 를 더블클릭합니다 (관리자 권한 확인 창이 뜹니다).
3. 안내에 따라 진행합니다. WSL 기능을 처음 켜는 PC 는 재부팅 후 "DevTools2 개발 환경 가져오기.cmd" 를 한 번 더 실행합니다.

[구성되는 것]
- WSL 배포판 "$DISTRO" (사용자 $ME) — Neovim·JDK·Node·Python·Sublime Merge·Orca 등 WSL 안의 모든 것
- AutoHotkey 단축키 (Ctrl+Alt+T 터미널, Ctrl+Alt+G Sublime Merge, CapsLock 리매핑, 한/영 자동 전환)
- 글꼴, Windows Terminal 설정, VS Code, Zed (지금 PC 와 같은 버전·확장·설정)
- .wslconfig (네트워크 설정 + 그 PC 메모리에 맞춘 WSL 메모리 상한)

[빠진 것]
$( if $INCLUDE_CRED; then echo "- (인증 정보는 함께 넣었습니다 — 묶음 보관에 주의)"; else echo "- 인증 정보 (GitHub·Bitwarden·AI API 키·AI 도구 로그인·rclone·GPG 키링·npm/Docker/클라우드 자격 증명·셸 입력 기록$( $KEEP_SSH || echo '·SSH 개인 키'), 다른 사용자 홈·/root 의 내용) — 오프라인에서는 쓸 수 없음"; fi )

[보관 주의]
- devtools2-rootfs.tar.gz 에는 배포판의 /etc/shadow(계정 비밀번호 해시)가 들어 있습니다 (빼면 가져온 배포판에서 sudo 가 동작하지 않음).
  인증 정보를 빼고 묶었더라도 이 묶음은 남에게 넘기거나 공유 폴더에 두지 마세요.
$( $INCLUDE_WS || echo "- 프로젝트 소스(~/workspaces)")

[오프라인에서 안 되는 것]
- 설치·업데이트 스크립트, 처음 쓰는 언어의 도구 자동 설치, Gradle·npm·pip 새 의존성 받기
EOF

echo ""
print_done "개발 환경을 내보냈습니다: $OUT ($(du -sh "$OUT" | cut -f1))"
echo "   오프라인 PC 에 폴더를 통째로 복사한 뒤 'DevTools2 개발 환경 가져오기.cmd' 를 실행하세요."
