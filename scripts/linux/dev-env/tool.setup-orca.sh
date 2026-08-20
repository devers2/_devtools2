#!/bin/bash
# ==============================================================================
# Linux용 Orca(멀티 에이전트 오케스트레이션 ADE) 설치 스크립트 (tool.setup-orca.sh)
#
# ------------------------------------------------------------------------------
# ⚠️ [Zed(tool.setup-zed.sh)와 달리 WSL2에서도 "건너뛰지 않고" 여기(리눅스 내부)에 설치하는 이유]
# Zed는 순수 에디터라 Windows 네이티브 앱이 WSL2의 파일을 UNC 경로로 열기만 하면 됩니다.
# 반면 Orca는 Claude Code/Codex/Gemini 같은 CLI 에이전트 "프로세스"를 직접 실행(spawn)해야
# 하는 오케스트레이터입니다. 그 CLI들은 (npm i -g @anthropic-ai/claude-code 등으로) 전부
# 이 WSL2 내부에 설치되어 있습니다. Orca를 Windows 네이티브로만 설치하면 WSL2 안의 그
# 바이너리를 실행할 방법이 없습니다(공식 문서에 WSL 브릿지 기능 없음). 대신 Orca 공식
# "Remote Orca Servers" 모드를 사용합니다:
#   - 에이전트 실행부(orca serve)는 CLI가 실제로 있는 WSL2에 헤드리스로 두고,
#   - Windows에는 거기 페어링만 하는 가벼운 GUI 클라이언트를 설치합니다(tool.setup-orca.ps1).
# ------------------------------------------------------------------------------
# ⚠️ [AI / 개발자 필독 - 설계 절대 원칙]
# 100% 온라인 전용 스트리밍: 서브스크립트는 무조건 GitHub main 원격 raw URL에서
# 직접 스트리밍으로 실행됩니다. 순수 UTF-8 NoBOM으로 유지되어야 합니다.
# ------------------------------------------------------------------------------
# ==============================================================================

set -euo pipefail

if [ -z "${DEVTOOLS2:-}" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")
fi

if [ ! -d "$DEVTOOLS2" ]; then
    DEVTOOLS2="/var/opt/_devtools2"
fi

# 공통 색상/스피너 헬퍼 로드 (온라인 전용)
_load_colors() {
    [ -n "${_COLORS_LOADED:-}" ] && return 0
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
    exit 1
}
_load_colors

# 공통 설치 유틸리티 로드 (IS_WSL2, ARCH, IS_ARM64, _ensure_pkg 등)
_load_install_utils() {
    [ -n "${_INSTALL_UTILS_LOADED:-}" ] && return 0
    local _tmpfile _curl_err _curl_ec=0
    _tmpfile=$(mktemp) || { print_error "임시 파일 생성에 실패했습니다."; exit 1; }
    _curl_err=$(curl -sSfL --max-time 5 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/dev-env/_install-utils.sh" -o "$_tmpfile" 2>&1) || _curl_ec=$?
    if [ "$_curl_ec" -eq 0 ]; then
        # shellcheck disable=SC1090
        if source "$_tmpfile" 2>/dev/null; then
            rm -f "$_tmpfile"
            _INSTALL_UTILS_LOADED=true
            return 0
        fi
        rm -f "$_tmpfile"
        print_error "_install-utils.sh를 다운로드했지만 source 실행 중 오류가 발생했습니다."
        exit 1
    fi
    rm -f "$_tmpfile"
    print_error "_install-utils.sh를 온라인에서 불러오지 못했습니다 (curl 종료 코드: $_curl_ec)."
    [ -n "$_curl_err" ] && print_error "  curl: $_curl_err"
    exit 1
}
_load_install_utils

print_banner "🐋 Orca 설치 (tool.setup-orca.sh)"

ORCA_DIR="$DEVTOOLS2/modules/orca"
if [ "$IS_ARM64" = true ]; then
    ORCA_APPIMAGE_NAME="orca-linux-arm64.AppImage"
else
    ORCA_APPIMAGE_NAME="orca-linux.AppImage"
fi
ORCA_APPIMAGE="$ORCA_DIR/$ORCA_APPIMAGE_NAME"

_orca_proceed=false

if [ -f "$ORCA_APPIMAGE" ]; then
    echo "   ⏭️ [건너뜀] orca AppImage가 이미 존재합니다. (재설치하려면 삭제: sudo rm -rf '$ORCA_DIR')"
    echo "   ℹ️  이미 설치되어 있어도 아래 systemd/페어링 상태는 매번 다시 점검합니다"
    echo "      (예: systemd 활성화를 위해 WSL을 재시작하고 이 스크립트를 다시 실행한 경우)."
    _orca_proceed=true
else
    echo "   ℹ️  Orca는 여러 코딩 에이전트를 Git worktree로 격리해 병렬로 실행/조율하는"
    echo "      에이전트 오케스트레이션 도구입니다 (Claude Code, Codex, Gemini 등 지원)."
    echo ""
    printf "   👉 Orca를 설치하시겠습니까? [y/\033[1;32mN\033[0m]: "
    if [ -t 0 ]; then
        read -r _orca_choice
    else
        _orca_choice="N"
    fi
    echo ""
    case "${_orca_choice:-N}" in
        y|Y)
            if [ "$IS_WSL2" = true ]; then
                echo "   ⚠️  [WSL2 환경 감지] Orca 실행부(orca serve)는 CLI 에이전트가 실제로 설치된"
                echo "      이 WSL2 내부에 헤드리스로 설치합니다. Windows 쪽에는 여기 페어링만 하는"
                echo "      GUI 클라이언트가 별도로 설치됩니다(tool.setup-orca.ps1)."
                echo ""
            fi

            mkdir -p "$ORCA_DIR"
            echo -n "   📥 orca 다운로드 중..."
            curl -Ls "https://github.com/stablyai/orca/releases/latest/download/${ORCA_APPIMAGE_NAME}" -o "$ORCA_APPIMAGE" &
            show_spinner $!
            echo " 완료"
            chmod +x "$ORCA_APPIMAGE"
            echo "   ✅ orca ($ARCH) 설치 완료 → $ORCA_APPIMAGE"
            _orca_proceed=true
            ;;
        *)
            echo "   ⏭️ Orca 설치를 건너뜁니다."
            ;;
    esac
fi

if [ "$_orca_proceed" = true ]; then
    # orca AppImage 실행에 필요한 의존성 (공식 헤드리스 서버 가이드 기준:
    # curl file jq xvfb zlib1g-dev). curl은 이미 이 저장소 전체가 의존하므로 생략.
    # 이미 설치된 상태로 재실행돼도 전부 존재 여부부터 확인하고 스킵하므로 안전합니다.
    _ensure_pkg file file
    _ensure_pkg jq jq
    _ensure_pkg Xvfb xvfb
    if ! dpkg -s libfuse2 >/dev/null 2>&1 && ! dpkg -s libfuse2t64 >/dev/null 2>&1; then
        echo -n "   📦 필수 패키지 (libfuse2) 자동 설치 중..."
        sudo apt-get update -qq >/dev/null 2>&1 || true
        sudo apt-get install -y libfuse2t64 >/dev/null 2>&1 || sudo apt-get install -y libfuse2 >/dev/null 2>&1 || true
        echo " 완료"
    fi
    if ! dpkg -s zlib1g-dev >/dev/null 2>&1; then
        echo -n "   📦 필수 패키지 (zlib1g-dev) 자동 설치 중..."
        sudo apt-get update -qq >/dev/null 2>&1 || true
        sudo apt-get install -y zlib1g-dev >/dev/null 2>&1 || true
        echo " 완료"
    fi

    # PATH에서 'orca'라는 짧은 이름으로 바로 실행할 수 있도록 심볼릭 링크 생성
    # (상대 경로 링크라 $DEVTOOLS2가 통째로 이동해도 깨지지 않음). ln -sf라 재실행해도 안전.
    ln -sf "$ORCA_APPIMAGE_NAME" "$ORCA_DIR/orca"

    # 설정/상태 디렉터리 심볼릭 링크. Orca는 아래 세 곳을 모두 씁니다(공식 문서 확인):
    # 소문자 ~/.config/orca, Electron GUI용 대문자 ~/.config/Orca, 그리고 keybindings.json
    # 등 CLI 전역 설정용 ~/.orca. 안 쓰는 게 있어도 빈 심볼릭 링크라 해될 게 없어 셋 다 둡니다.
    _orca_symlink_script="$DEVTOOLS2/scripts/linux/cmd/create-symbolic-link.sh"
    _orca_link() {
        if [ -f "$_orca_symlink_script" ]; then
            "$_orca_symlink_script" "$1" "$2"
        else
            curl -sSfL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/cmd/create-symbolic-link.sh" \
                | bash -s -- "$1" "$2"
        fi
    }
    _orca_link "$DEVTOOLS2/.config/orca" "$HOME/.config/orca"
    _orca_link "$DEVTOOLS2/.config/Orca" "$HOME/.config/Orca"
    _orca_link "$DEVTOOLS2/.config/orca-home" "$HOME/.orca"

    # ── 권장 스킬 전역 설치 (베스트 에포트) ──
    # orca-cli/orchestration은 공식 문서가 일반적인 기본 조합으로 예시하는 스킬입니다.
    # CLI 에이전트(claude/codex 등)가 아직 없으면 그냥 아무것도 안 하고 넘어갑니다
    # (에이전트 설치 후 'orca skills install --all' 로 나중에 다시 돌리면 됩니다).
    # orca serve 데몬을 아직 띄우기 전에 실행합니다 — 같은 AppImage를 동시에 두 번
    # 띄웠을 때 생길 수 있는 Electron 단일 인스턴스 락 충돌 가능성을 애초에 피하기 위함.
    # timeout으로 감싸는 이유: 실패해도 무해해야 할 이 단계가 혹시라도 응답 없이 멈추면
    # (예: 디스플레이 요구) 전체 devtools2 설치가 그 자리에서 무한 대기하게 되기 때문.
    # 공식 문서(onorca.dev/docs/cli/skills)가 헤드리스 호스트(SSH/컨테이너/CI/orca serve)용으로
    # 정확히 명시한 명령입니다: "orca skills install --skill orca-cli --skill orchestration"
    # (--global 플래그는 문서 예시에 없어 임의로 추가하지 않음 — 헤드리스 CLI 래퍼는 애초에
    # 전역 스코프만 의미가 있어 기본값이 global인 것으로 보입니다).
    echo ""
    echo "   🧩 권장 스킬(orca-cli, orchestration) 설치 시도 중..."
    timeout 20 "$ORCA_DIR/orca" skills install --skill orca-cli --skill orchestration >/dev/null 2>&1 \
        && echo "   ✅ 스킬 설치 완료 (감지된 에이전트가 없었다면 지금은 조용히 아무 일도 안 했을 수 있음)" \
        || echo "   ⚠️  스킬 설치를 건너뜁니다(타임아웃 또는 미감지 — 에이전트 CLI 설치 후 'orca skills install --all'로 다시 시도 가능)"

    # ── WSL2: orca serve 헤드리스 자동 실행 등록 + 페어링 링크 자동 확보 ──
    # systemd가 이미 활성화돼 있으면 바로 등록하고, 아직이면 common-setup.sh의
    # setup_rclone_sftp_mount와 동일하게 wsl.conf 자동 설정 + 재시작 안내로 처리합니다.
    if [ "$IS_WSL2" = true ]; then
        echo ""

        # ⚠️ 127.0.0.1은 Orca 공식 문서가 "원격 클라이언트 페어링에 쓰지 말라"고 명시적으로
        # 경고하는 주소라 쓰지 않습니다. 대신 WSL2 자체 IP(Windows에서 직접 라우팅 가능)를
        # 매번 기동 시점에 새로 조회하는 래퍼 스크립트를 둡니다 — WSL2 IP는 재부팅마다
        # 바뀔 수 있어 systemd 유닛 파일에 고정 IP를 박아두면 재부팅 후 깨지기 때문입니다.
        # LIBGL_ALWAYS_SOFTWARE=1도 여기 직접 넣어둡니다 — systemd의 Environment= 줄에만
        # 있으면 "systemctl 없음" 폴백으로 이 파일을 수동 실행할 때는 안 먹기 때문입니다.
        cat > "$ORCA_DIR/orca-serve-wrapper.sh" <<EOF
#!/bin/bash
export LIBGL_ALWAYS_SOFTWARE=1
exec "$ORCA_APPIMAGE" serve --port 6768 --pairing-address "\$(hostname -I | awk '{print \$1}')"
EOF
        chmod +x "$ORCA_DIR/orca-serve-wrapper.sh"

        # ⚠️ command -v systemctl 만으로는 부족합니다 — Ubuntu는 systemd 패키지가
        # 기본 설치돼 있어 WSL2에서 systemd가 실제로 PID 1로 안 떠 있어도 systemctl
        # 바이너리 자체는 존재합니다. 실제 동작 여부는 'systemctl --user status'의
        # 종료 코드로 확인해야 합니다(common-setup.sh의 setup_rclone_sftp_mount와
        # 동일한 검증 방식 — 이 저장소에서 이미 검증된 패턴을 그대로 재사용).
        if systemctl --user status >/dev/null 2>&1; then
            echo "   ⚙️  systemd 사용자 서비스로 'orca serve' 자동 실행을 등록합니다..."
            mkdir -p "$HOME/.config/systemd/user"
            # 공식 헤드리스 가이드(docs/reference/headless-linux-server.md)의 systemd
            # 예시를 그대로 따릅니다: StartLimitIntervalSec/Burst로 재시작 폭주 방지,
            # RestartPreventExitStatus=3(= "이미 같은 userData 프로필을 쓰는 다른 인스턴스가
            # 떠 있음" — 재시작해봐야 성공할 수 없는 경우라 그냥 멈춤), KillMode=mixed로
            # 내부 Xvfb가 깨끗이 종료되도록 함.
            cat > "$HOME/.config/systemd/user/orca-serve.service" <<EOF
[Unit]
Description=Orca headless agent orchestration server
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
WorkingDirectory=%h
ExecStart=$ORCA_DIR/orca-serve-wrapper.sh
KillMode=mixed
Restart=on-failure
RestartPreventExitStatus=3
RestartSec=5

[Install]
WantedBy=default.target
EOF
            systemctl --user daemon-reload 2>/dev/null || true
            if systemctl --user enable --now orca-serve.service 2>/dev/null; then
                echo "   ✅ orca-serve.service 등록 및 실행 완료 (포트 6768)"

                # 페어링 링크 자동 확보 시도(베스트 에포트, 최대 20초 폴링). 헤드리스
                # 리눅스에서는 pairing 코드가 아예 출력되지 않는 알려진 미해결 버그가
                # 있어(stablyai/orca#9759) 안 나와도 정상입니다 — 그 경우 대체 안내를 출력합니다.
                _orca_pair_link=""
                for _i in 1 2 3 4 5 6 7 8 9 10; do
                    sleep 2
                    _orca_pair_link=$(journalctl --user -u orca-serve.service --no-pager -n 80 2>/dev/null | grep -oE 'orca://pair[^[:space:]]*' | tail -1)
                    [ -n "$_orca_pair_link" ] && break
                done
                mkdir -p "$DEVTOOLS2/data"
                if [ -n "$_orca_pair_link" ]; then
                    echo "$_orca_pair_link" > "$DEVTOOLS2/data/orca-pairing-link.txt"
                    echo "   🔗 페어링 링크 확보: $_orca_pair_link"
                    echo "      (Windows 쪽 tool.setup-orca.ps1 이 이 링크를 자동으로 읽어갑니다)"
                else
                    rm -f "$DEVTOOLS2/data/orca-pairing-link.txt"
                    echo "   ⚠️  페어링 링크를 자동으로 찾지 못했습니다(알려진 업스트림 버그일 수 있음:"
                    echo "      https://github.com/stablyai/orca/issues/9759 )."
                    echo "      필요하면 직접 확인: journalctl --user -u orca-serve.service --no-pager | grep orca://"
                fi
            else
                echo "   ⚠️  systemd --user 서비스 활성화 실패. 수동 실행: $ORCA_DIR/orca-serve-wrapper.sh &"
                echo "   💬 반복 실패로 재시작 제한(StartLimitBurst)에 걸린 경우:"
                echo "      systemctl --user reset-failed orca-serve.service 후 다시 시도하세요."
            fi
        else
            # common-setup.sh의 setup_rclone_sftp_mount와 동일한 절차: wsl.conf에
            # systemd=true를 자동으로 추가하고, WSL 재시작이 필요하다는 걸 명확히 안내합니다.
            echo "   ⚠️  WSL2에서 systemd가 활성화되어 있지 않습니다."
            echo "      orca serve 자동 실행은 systemd user 서비스로 동작하므로 systemd가 필요합니다."
            echo ""

            _WSL_CONF="/etc/wsl.conf"
            _NEEDS_SYSTEMD=true
            if grep -q 'systemd\s*=\s*true' "$_WSL_CONF" 2>/dev/null; then
                _NEEDS_SYSTEMD=false
            fi

            if [ "$_NEEDS_SYSTEMD" = true ]; then
                echo "   ⏳ /etc/wsl.conf 에 systemd 활성화 설정을 추가합니다... (sudo 필요)"
                if grep -q '\[boot\]' "$_WSL_CONF" 2>/dev/null; then
                    sudo sed -i '/^\[boot\]/a systemd=true' "$_WSL_CONF"
                else
                    printf '\n[boot]\nsystemd=true\n' | sudo tee -a "$_WSL_CONF" > /dev/null
                fi
                echo "   ✅ /etc/wsl.conf 에 systemd=true 추가 완료!"
            else
                echo "   ℹ️  /etc/wsl.conf 에는 이미 systemd=true 가 설정되어 있습니다."
                echo "      WSL 인스턴스가 아직 재시작되지 않아 systemd가 비활성 상태입니다."
            fi

            echo ""
            echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "   🔄  WSL 인스턴스를 재시작해야 systemd가 활성화됩니다."
            echo ""
            echo "      PowerShell 에서 아래 명령어를 실행하세요:"
            echo ""
            echo "        wsl --shutdown"
            echo ""
            echo "      재시작 후 이 설치 스크립트를 다시 실행하면 orca-serve.service 자동 등록이"
            echo "      이어서 완료됩니다(orca AppImage는 이미 설치돼 있어 다운로드는 다시 안 함)."
            echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "   💬 지금 당장 쓰려면 수동으로도 실행 가능합니다: $ORCA_DIR/orca-serve-wrapper.sh &"
        fi
        echo ""
        echo "   💬 Windows Orca 앱과의 페어링 안내는 tool.setup-orca.ps1 완료 화면에서 보여드립니다."
    else
        echo "   💬 일반 데스크톱 GUI 앱으로 바로 실행할 수 있습니다: $ORCA_APPIMAGE"
    fi

    # ── 실제로 쓰려면 필요한 다음 단계 안내 ──
    # Orca는 오케스트레이터일 뿐, claude/codex/gemini 등 실제 에이전트 CLI 바이너리는
    # 별도로 설치/로그인해야 함(Orca가 PATH에서 찾아 그대로 실행). codecompanion.lua에
    # 정리된 것과 동일한 CLI라서 이미 그쪽을 설정했다면 이 단계는 생략 가능.
    echo ""
    echo "   ---------------------------------------------------------------------"
    echo "   📋 실제로 사용하려면 (에이전트 CLI 설치 + 로그인, 1회만):"
    echo "   ---------------------------------------------------------------------"
    echo "   Orca는 오케스트레이터일 뿐이라, 아래 CLI들을 PATH에서 찾아 그대로 실행합니다."
    echo "   설치 + 로그인은 각 CLI 자체 방식으로 1회만 하면 됩니다:"
    echo ""
    echo "     • Claude Code : npm i -g @anthropic-ai/claude-code  →  claude  (최초 실행 시 로그인)"
    echo "     • Codex       : npm i -g @openai/codex             →  codex   (최초 실행 시 로그인)"
    echo "     • Gemini CLI  : npm i -g @google/gemini-cli        →  gemini  (최초 실행 시 로그인)"
    echo "     • OpenCode    : opencode.ai 설치 스크립트 →  opencode auth login"
    echo "     • Goose       : Block의 Goose CLI 설치    →  goose configure"
    echo ""
    echo "   ⚠️  ANTHROPIC_API_KEY 등을 .bashrc에 export해두신 게 있어도, orca serve가"
    echo "      systemd(또는 데스크톱 런처)로 뜬 경우엔 .bashrc를 거치지 않아 그 값을 못 봅니다"
    echo "      (WSL2 터미널에서 직접 치는 orca account add 같은 명령은 대화형 셸이라 문제없음)."
    echo "      orca serve 데몬에서도 보이게 하려면 아래처럼 등록해주세요(로그인마다 자동 반영):"
    echo "        mkdir -p ~/.config/environment.d"
    echo "        printf 'ANTHROPIC_API_KEY=%s\\n' \"\$ANTHROPIC_API_KEY\" >> ~/.config/environment.d/orca.conf"
    echo "      등록 후에는 'systemctl --user restart orca-serve.service'로 반영하거나 WSL2를"
    echo "      재시작하면 적용됩니다."
    echo ""
    echo "   Claude/Codex는 Orca 자체 계정 전환/사용량 추적 기능도 지원합니다(선택 사항):"
    echo "     orca account add --agent claude"
    echo "     orca account add --agent codex"
    echo "     orca account list"
    echo ""
    echo "   에이전트 CLI를 새로 설치했다면 스킬 인식을 갱신해주세요(위에서 자동 설치는 이미 됨):"
    echo "     orca skills install --all"
    echo ""
    echo "   설치 확인 후에는 Orca에서 바로 에이전트를 지정해 워크트리를 만들 수 있습니다:"
    echo "     orca worktree create --agent claude --prompt \"할 일\""
    echo "   ---------------------------------------------------------------------"
fi
echo ""
