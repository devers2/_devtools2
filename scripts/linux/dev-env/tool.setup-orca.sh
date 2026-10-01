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

if [ -f "$_SCRIPT_DIR/_install-utils.sh" ]; then
    # shellcheck disable=SC1091
    source "$_SCRIPT_DIR/_install-utils.sh"
elif [ -f "${DEVTOOLS2:-}/scripts/linux/dev-env/_install-utils.sh" ]; then
    # shellcheck disable=SC1091
    source "$DEVTOOLS2/scripts/linux/dev-env/_install-utils.sh"
else
    # shellcheck disable=SC1090
    source <(curl -sSfL --max-time 10 -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' "$_GH_RAW/_install-utils.sh") || { print_error "_install-utils.sh 로드 실패 - 네트워크 연결을 확인하세요."; exit 1; }
fi

print_banner "🐋 Orca 설치 (tool.setup-orca.sh)"

ORCA_DIR="$DEVTOOLS2/modules/orca"
if [ "$IS_ARM64" = true ]; then
    ORCA_APPIMAGE_NAME="orca-linux-arm64.AppImage"
else
    ORCA_APPIMAGE_NAME="orca-linux.AppImage"
fi
ORCA_APPIMAGE="$ORCA_DIR/$ORCA_APPIMAGE_NAME"

_orca_proceed=false
_orca_updated=false
ORCA_VERSION_FILE="$ORCA_DIR/.version"

# 최신 릴리스 태그(예: v1.4.218)를 받아 SHA256 검증 후 원자적으로 설치하고 버전을 기록합니다.
# ⚠️ 임시 파일로 받아 검증한 뒤 옮기는 safe_download_binary 를 씁니다. 대상 경로에 바로 받으면
#   다운로드가 중간에 끊겼을 때 깨진 AppImage 가 남고, 다음 실행부터는 "이미 존재"로 판정되어
#   다시 받지 않습니다. 실행 중인 orca serve 가 있어도 mv 교체는 안전합니다(기존 프로세스는 옛 파일을 계속 씀).
# 인수: $1 = 설치할 태그(빈 값이면 latest 로 받되 체크섬 검증은 생략)
_orca_download() {
    local tag="$1" url sha=""
    url="https://github.com/stablyai/orca/releases/latest/download/${ORCA_APPIMAGE_NAME}"
    if [ -n "$tag" ]; then
        url="https://github.com/stablyai/orca/releases/download/${tag}/${ORCA_APPIMAGE_NAME}"
        sha=$(github_asset_sha256 "stablyai/orca" "$tag" "$ORCA_APPIMAGE_NAME")
    fi
    [ -z "$sha" ] && print_warn "Orca SHA256 을 조회하지 못해 체크섬 검증 없이 다운로드합니다."
    mkdir -p "$ORCA_DIR"
    if safe_download_binary "$url" "$ORCA_APPIMAGE" 755 "$sha" "Orca AppImage${tag:+ ${tag}}"; then
        if [ -n "$tag" ]; then
            echo "$tag" > "$ORCA_VERSION_FILE"
        else
            rm -f "$ORCA_VERSION_FILE"
        fi
        return 0
    fi
    print_error "Orca AppImage 다운로드 실패 (기존 파일이 있었다면 그대로 유지됩니다)"
    return 1
}

_orca_latest=$(fetch_latest_github "stablyai/orca")

if [ -f "$ORCA_APPIMAGE" ]; then
    _orca_proceed=true
    _orca_cur=""
    [ -f "$ORCA_VERSION_FILE" ] && _orca_cur=$(head -n1 "$ORCA_VERSION_FILE" 2>/dev/null | tr -d '[:space:]')

    # ── 이미 설치됨: 새 버전이 있으면 업데이트 여부를 묻습니다 ──
    # (Windows Orca 앱은 스스로 업데이트되므로, WSL 쪽 서버만 옛 버전에 머물면 페어링·기능이 어긋날 수 있음)
    if [ -z "$_orca_latest" ]; then
        echo "   ℹ️  Orca 가 설치되어 있습니다(${_orca_cur:-버전 기록 없음}). 최신 버전 확인에 실패해 업데이트 확인은 건너뜁니다."
    elif [ "$_orca_cur" = "$_orca_latest" ]; then
        echo "   ✅ Orca 가 최신 버전입니다 ($_orca_cur)."
    else
        echo "   🆕 Orca 새 버전이 있습니다: ${_orca_cur:-알 수 없음(버전 기록 없음)} → $_orca_latest"
        _do_update=false
        if [ -n "${DT2_ORCA_UPDATE:-}" ]; then
            [ "${DT2_ORCA_UPDATE,,}" = "y" ] && _do_update=true
        elif dt2_is_noninteractive; then
            # 무인 실행에서는 다른 도구들과 같은 규칙(기존 설치 유지)을 따릅니다.
            echo "   ⏭️  비대화형 실행이라 업데이트를 건너뜁니다 (DT2_ORCA_UPDATE=y 로 강제 가능)."
        elif prompt_confirm "👉 Orca 를 $_orca_latest 로 업데이트할까요? (실행 중인 orca serve 가 재시작되어 진행 중 세션이 끊길 수 있음)" "Y"; then
            _do_update=true
        fi
        if [ "$_do_update" = true ]; then
            if _orca_download "$_orca_latest"; then
                echo "   ✅ Orca 업데이트 완료 → $_orca_latest"
                _orca_updated=true
            fi
        else
            echo "   ⏭️  Orca 업데이트를 건너뜁니다 (현재 버전 유지)."
        fi
    fi
    echo "   ℹ️  아래 의존성·에이전트·systemd·페어링 상태는 매번 다시 점검합니다."
else
    echo "   ℹ️  Orca는 여러 코딩 에이전트를 Git worktree로 격리해 병렬로 실행/조율하는"
    echo "      에이전트 오케스트레이션 도구입니다 (Claude Code, Codex, Gemini 등 지원)."
    echo ""
    _do_orca=false
    if [ -n "${DT2_ORCA_CHOICE:-}" ]; then
        [ "${DT2_ORCA_CHOICE,,}" = "y" ] && _do_orca=true
    elif prompt_confirm "👉 Orca를 설치하시겠습니까?" "N"; then
        _do_orca=true
    fi

    if [ "$_do_orca" = true ]; then
        if [ "$IS_WSL2" = true ]; then
            echo "   ⚠️  [WSL2 환경 감지] Orca 실행부(orca serve)는 CLI 에이전트가 실제로 설치된"
            echo "      이 WSL2 내부에 헤드리스로 설치합니다. Windows 쪽에는 여기 페어링만 하는"
            echo "      GUI 클라이언트가 별도로 설치됩니다(tool.setup-orca.ps1)."
            echo ""
        fi
        if _orca_download "$_orca_latest"; then
            echo "   ✅ orca ($ARCH${_orca_latest:+, ${_orca_latest}}) 설치 완료 → $ORCA_APPIMAGE"
            _orca_proceed=true
        fi
    else
        echo "   ⏭️ Orca 설치를 건너뜁니다."
    fi
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
        (sudo apt-get update -qq >/dev/null 2>&1 || true; sudo apt-get install -y libfuse2t64 >/dev/null 2>&1 || sudo apt-get install -y libfuse2 >/dev/null 2>&1 || true) &
        _fuse_pid=$!
        show_spinner $_fuse_pid
        wait $_fuse_pid 2>/dev/null || true
        echo " 완료"
    fi
    if ! dpkg -s zlib1g-dev >/dev/null 2>&1; then
        echo -n "   📦 필수 패키지 (zlib1g-dev) 자동 설치 중..."
        (sudo apt-get update -qq >/dev/null 2>&1 || true; sudo apt-get install -y zlib1g-dev >/dev/null 2>&1 || true) &
        _zlib_pid=$!
        show_spinner $_zlib_pid
        wait $_zlib_pid 2>/dev/null || true
        echo " 완료"
    fi

    # Orca(Electron) 실행 파일이 직접 링크하는 시스템 라이브러리.
    # ⚠️ 최소 설치 Ubuntu(WSL rootfs 포함)에는 libnss3·libnspr4·libasound2 등이 없어 AppImage 가
    #   "error while loading shared libraries: libnspr4.so" 로 바로 종료됩니다(실측: orca-ide 의 NEEDED 목록 기준).
    #   "a|b" 는 Ubuntu 24.04(t64 이름) / 22.04 이전 이름 순서로 시도합니다.
    _orca_runtime_pkgs=(
        "libnss3" "libnspr4" "libasound2t64|libasound2" "libgtk-3-0t64|libgtk-3-0" "libgbm1"
        "libatk1.0-0t64|libatk1.0-0" "libatk-bridge2.0-0t64|libatk-bridge2.0-0" "libcups2t64|libcups2"
        "libxcomposite1" "libxdamage1" "libxrandr2" "libxkbcommon0" "libpango-1.0-0" "libcairo2"
    )
    _orca_missing_pkgs=()
    for _spec in "${_orca_runtime_pkgs[@]}"; do
        _have=false
        IFS='|' read -ra _alts <<< "$_spec"
        for _alt in "${_alts[@]}"; do
            dpkg -s "$_alt" >/dev/null 2>&1 && { _have=true; break; }
        done
        [ "$_have" = false ] && _orca_missing_pkgs+=("$_spec")
    done
    if [ "${#_orca_missing_pkgs[@]}" -gt 0 ]; then
        echo -n "   📦 Orca 실행 라이브러리 (${#_orca_missing_pkgs[@]}개) 자동 설치 중..."
        (
            sudo apt-get update -qq >/dev/null 2>&1 || true
            for _spec in "${_orca_missing_pkgs[@]}"; do
                IFS='|' read -ra _alts <<< "$_spec"
                for _alt in "${_alts[@]}"; do
                    sudo apt-get install -y "$_alt" >/dev/null 2>&1 && break
                done
            done
        ) &
        _libs_pid=$!
        show_spinner $_libs_pid
        wait $_libs_pid 2>/dev/null || true
        _still_missing=()
        for _spec in "${_orca_missing_pkgs[@]}"; do
            _have=false
            IFS='|' read -ra _alts <<< "$_spec"
            for _alt in "${_alts[@]}"; do
                dpkg -s "$_alt" >/dev/null 2>&1 && { _have=true; break; }
            done
            [ "$_have" = false ] && _still_missing+=("${_alts[0]}")
        done
        if [ "${#_still_missing[@]}" -eq 0 ]; then
            echo " 완료"
        else
            echo " 일부 실패"
            print_warn "설치하지 못한 라이브러리: ${_still_missing[*]} (sudo apt-get install -y ${_still_missing[*]})"
        fi
    fi

    # 실제로 실행되는지 확인 (라이브러리 누락·FUSE 문제를 설치 단계에서 바로 드러냄)
    if timeout 60 "$ORCA_APPIMAGE" --help >/dev/null 2>&1; then
        echo "   ✅ Orca 실행 확인 완료"
    else
        print_warn "Orca 실행 확인에 실패했습니다. 원인 확인: $ORCA_APPIMAGE --help"
        print_warn "  (공유 라이브러리 오류라면 위 라이브러리 설치가 실패한 것입니다: sudo apt-get install -y libnss3 libnspr4)"
    fi

    # PATH에서 'orca'라는 짧은 이름으로 바로 실행할 수 있도록 심볼릭 링크 생성
    # (상대 경로 링크라 $DEVTOOLS2가 통째로 이동해도 깨지지 않음). ln -sf라 재실행해도 안전.
    ln -sf "$ORCA_APPIMAGE_NAME" "$ORCA_DIR/orca"

    # 설정/상태 디렉터리(~/.config/orca, ~/.config/Orca, ~/.orca)는 공유 저장소로 링크하지 않고
    # Orca 기본 위치(사용자 홈)에 둡니다.
    # ⚠️ 이 폴더들에는 Orca 계정 정보와 Electron 사용자 데이터(쿠키·토큰)가 저장됩니다.
    #    예전처럼 $DEVTOOLS2/.config 아래로 링크하면 .config/.gitignore 의 "!*"(전부 추적) 때문에
    #    git 추적 대상이 되어 공개 저장소에 커밋될 위험이 있고, 다중 사용자 서버에서는 그룹원이 읽을 수 있습니다.
    for _orca_cfg in "$HOME/.config/orca" "$HOME/.config/Orca" "$HOME/.orca"; do
        if [ -L "$_orca_cfg" ] && [[ "$(readlink -f "$_orca_cfg" 2>/dev/null)" == "$DEVTOOLS2/"* ]]; then
            print_warn "Orca 데이터가 공유 저장소로 링크되어 있습니다: $_orca_cfg -> $(readlink -f "$_orca_cfg")"
            print_warn "  계정 정보 보호를 위해 링크를 지우고 내용을 사용자 홈으로 옮기는 것을 권장합니다."
        fi
    done

    # ⚠️ WSL 에는 OS 키링이 없어 Orca 가 계정 토큰을 암호화하지 않고 평문 파일로 저장합니다(실측 로그:
    #   "The OS keyring is unavailable, so secrets are stored unencrypted"). 또 ~/.orca/agent-hooks 의
    #   스크립트는 Claude/Codex 가 실행하는데 그룹 공유 umask(002)에서는 그룹 쓰기 권한으로 만들어집니다.
    #   이미 있는 파일은 여기서 소유자 전용으로 맞추고, 새로 생기는 파일은 서비스의 UMask=0077 이 막습니다.
    for _orca_cfg in "$HOME/.config/orca" "$HOME/.config/Orca" "$HOME/.orca"; do
        if [ -d "$_orca_cfg" ] && [ ! -L "$_orca_cfg" ]; then
            chmod -R go-rwx "$_orca_cfg" 2>/dev/null || true
        fi
    done

    # ── 바로 쓰기 위한 에이전트 CLI 점검/설치 ──
    # Orca 는 오케스트레이터일 뿐이라 claude/codex/gemini 같은 에이전트 CLI 를 PATH 에서 찾아 실행합니다.
    # 하나도 없으면 Orca 를 띄워도 할 수 있는 일이 없으므로, 없는 것만 골라 설치 여부를 묻습니다.
    # - Claude Code: 공식 네이티브 설치 프로그램(~/.local/bin/claude, 자동 업데이트)
    # - Codex / Gemini CLI: npm 전역 설치(DevTools2 공용 npm prefix: $DEVTOOLS2/data/.npm-packages)
    # 무인 실행에서는 묻지 않고 건너뜁니다. DT2_ORCA_AGENTS="claude,codex,gemini" 로 지정할 수 있습니다(none=설치 안 함).
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
    if ! command -v npm >/dev/null 2>&1 && [ -f "$HOME/.config/devtools2/env.sh" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.config/devtools2/env.sh" >/dev/null 2>&1 || true
    fi
    echo ""
    echo "   🤖 에이전트 CLI 점검 (Orca 가 실제로 실행할 대상)"
    _orca_agent_names=("claude" "codex" "gemini")
    _orca_agent_labels=("Claude Code" "Codex" "Gemini CLI")
    _orca_agent_defaults=("Y" "N" "N")
    for _i in "${!_orca_agent_names[@]}"; do
        _cmd="${_orca_agent_names[$_i]}"
        _label="${_orca_agent_labels[$_i]}"
        if command -v "$_cmd" >/dev/null 2>&1; then
            echo "      ✅ $_label: 설치됨 ($(command -v "$_cmd"))"
            continue
        fi
        _want=false
        if [ -n "${DT2_ORCA_AGENTS:-}" ]; then
            [[ ",${DT2_ORCA_AGENTS,,}," == *",$_cmd,"* ]] && _want=true
        elif dt2_is_noninteractive; then
            echo "      ⬜ $_label: 미설치 (비대화형 실행이라 건너뜀)"
            continue
        elif prompt_confirm "      👉 $_label 이(가) 없습니다. 설치하시겠습니까?" "${_orca_agent_defaults[$_i]}"; then
            _want=true
        fi
        [ "$_want" = true ] || { echo "      ⬜ $_label: 미설치 (건너뜀)"; continue; }

        case "$_cmd" in
            claude)
                _claude_installer=$(mktemp)
                if curl -fsSL --max-time 60 https://claude.ai/install.sh -o "$_claude_installer" && bash "$_claude_installer"; then
                    hash -r
                fi
                rm -f "$_claude_installer"
                ;;
            codex) { command -v npm >/dev/null 2>&1 && npm install -g --no-audit --no-fund @openai/codex; } || true ;;
            gemini) { command -v npm >/dev/null 2>&1 && npm install -g --no-audit --no-fund @google/gemini-cli; } || true ;;
        esac
        hash -r
        if command -v "$_cmd" >/dev/null 2>&1; then
            echo "      ✅ $_label 설치 완료 ($(command -v "$_cmd"))"
        else
            print_warn "$_label 설치에 실패했습니다. 나중에 직접 설치하세요(아래 안내 참고)."
        fi
    done

    # ── 권장 스킬 전역 설치 (베스트 에포트) ──
    # 공식 문서(onorca.dev/docs/cli/skills)가 헤드리스 호스트용으로 명시한 명령입니다.
    # ⚠️ 에이전트 CLI 를 먼저 설치한 뒤 실행해야 합니다: Orca 가 감지한 에이전트가 하나도 없으면
    #   "--agent 지정 필요"로 실패합니다(orca skills install --help). 내부적으로 npx 를 써서 첫 실행은
    #   패키지를 내려받으므로 넉넉한 timeout 을 둡니다(무한 대기로 전체 설치가 멈추지 않게).
    # orca serve 를 (재)시작하기 전에 실행해 같은 AppImage 의 단일 인스턴스 락 충돌을 피합니다.
    echo ""
    echo "   🧩 권장 스킬(orca-cli, orchestration) 설치 시도 중..."
    _skills_log=$(mktemp)
    if timeout 180 "$ORCA_APPIMAGE" skills install --skill orca-cli --skill orchestration >"$_skills_log" 2>&1; then
        echo "   ✅ 스킬 설치 완료"
    else
        echo "   ⚠️  스킬 설치를 건너뜁니다(에이전트 CLI 미감지 또는 네트워크 문제)."
        echo "      에이전트 CLI 설치 후 다시 시도: orca skills install --skill orca-cli --skill orchestration"
        tail -n 3 "$_skills_log" 2>/dev/null | sed 's/^/      │ /'
    fi
    rm -f "$_skills_log"

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
        # ⚠️ systemd 사용자 서비스는 ~/.bashrc 를 읽지 않고, environment.d 의 PATH 에는 ~/.local/bin 이 없습니다.
        #   그러면 Claude Code 네이티브 설치(~/.local/bin/claude)와 Orca 가 설치하는 orca 명령을 서비스에서
        #   찾지 못해 에이전트를 실행할 수 없습니다. 그래서 래퍼가 셸과 같은 env.sh(→ secrets.env 의 API 키 포함)를
        #   직접 읽고 ~/.local/bin 을 PATH 앞에 붙입니다.
        # ⚠️ umask 077: WSL 에는 OS 키링이 없어 Orca 가 계정 토큰을 평문 파일로 저장하므로 새 파일을 소유자 전용으로 만듭니다.
        _orca_wrapper_new=$(cat <<EOF
#!/bin/bash
# tool.setup-orca.sh 가 생성 — 직접 수정하면 다음 설치 때 덮어써집니다.
umask 077
[ -f "\$HOME/.config/devtools2/env.sh" ] && . "\$HOME/.config/devtools2/env.sh" >/dev/null 2>&1
[ -f "\$HOME/.config/devtools2/secrets.env" ] && . "\$HOME/.config/devtools2/secrets.env" >/dev/null 2>&1
case ":\$PATH:" in *":\$HOME/.local/bin:"*) ;; *) PATH="\$HOME/.local/bin:\$PATH" ;; esac
export PATH
export LIBGL_ALWAYS_SOFTWARE=1
exec "$ORCA_APPIMAGE" serve --port 6768 --pairing-address "\$(hostname -I | awk '{print \$1}')"
EOF
)
        _orca_cfg_changed=false
        if [ "$(cat "$ORCA_DIR/orca-serve-wrapper.sh" 2>/dev/null)" != "$_orca_wrapper_new" ]; then
            printf '%s\n' "$_orca_wrapper_new" > "$ORCA_DIR/orca-serve-wrapper.sh"
            _orca_cfg_changed=true
        fi
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
            _orca_unit_new=$(cat <<EOF
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
UMask=0077
KillMode=mixed
Restart=on-failure
RestartPreventExitStatus=3
RestartSec=5

[Install]
WantedBy=default.target
EOF
)
            _orca_unit_file="$HOME/.config/systemd/user/orca-serve.service"
            if [ "$(cat "$_orca_unit_file" 2>/dev/null)" != "$_orca_unit_new" ]; then
                printf '%s\n' "$_orca_unit_new" > "$_orca_unit_file"
                _orca_cfg_changed=true
            fi
            systemctl --user daemon-reload 2>/dev/null || true
            # 이번 실행에서 (재)시작한 경우 그 이후 로그에서만 페어링 링크를 찾습니다(재시작 전 옛 링크 방지).
            _orca_was_active=false
            systemctl --user is-active --quiet orca-serve.service 2>/dev/null && _orca_was_active=true
            _orca_since=$(date '+%Y-%m-%d %H:%M:%S')
            if systemctl --user enable --now orca-serve.service 2>/dev/null; then
                # 이미 실행 중이었다면 enable --now 는 재시작하지 않으므로, 업데이트했거나
                # 래퍼/유닛 설정이 바뀐 경우에만 재시작해 새 버전·설정을 반영합니다.
                if [ "$_orca_updated" = true ] || [ "$_orca_cfg_changed" = true ]; then
                    echo "   🔄 새 버전/설정 반영을 위해 orca-serve 를 재시작합니다..."
                    systemctl --user restart orca-serve.service 2>/dev/null || true
                fi
                echo "   ✅ orca-serve.service 등록 및 실행 완료 (포트 6768)"

                # 페어링 링크 자동 확보 시도(베스트 에포트, 최대 20초 폴링). 헤드리스
                # 리눅스에서는 pairing 코드가 아예 출력되지 않는 알려진 미해결 버그가
                # 있어(stablyai/orca#9759) 안 나와도 정상입니다 — 그 경우 대체 안내를 출력합니다.
                _orca_pair_link=""
                for _i in 1 2 3 4 5 6 7 8 9 10; do
                    sleep 2
                    if [ "$_orca_was_active" = true ] && [ "$_orca_updated" != true ] && [ "$_orca_cfg_changed" != true ]; then
                        _orca_pair_link=$(journalctl --user -u orca-serve.service --no-pager -n 200 2>/dev/null | grep -oE 'orca://pair[^[:space:]]*' | tail -1)
                    else
                        _orca_pair_link=$(journalctl --user -u orca-serve.service --no-pager --since "$_orca_since" 2>/dev/null | grep -oE 'orca://pair[^[:space:]]*' | tail -1)
                    fi
                    [ -n "$_orca_pair_link" ] && break
                done
                mkdir -p "$DEVTOOLS2/data"
                if [ -n "$_orca_pair_link" ]; then
                    # 페어링 링크에는 접속 토큰이 들어 있어 소유자 전용(600)으로 저장합니다
                    # (공유 폴더 data/ 의 기본 권한이면 같은 그룹 사용자가 읽고 내 orca serve 에 페어링할 수 있음).
                    (umask 077 && echo "$_orca_pair_link" > "$DEVTOOLS2/data/orca-pairing-link.txt")
                    chmod 600 "$DEVTOOLS2/data/orca-pairing-link.txt" 2>/dev/null || true
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
            # 줄 맨 앞 기준으로 검사합니다(앵커 없이 검사하면 "# systemd=true" 같은 주석 줄도
            # "이미 설정됨"으로 판정되어 실제로는 systemd 를 켜지 않고 넘어감 — 실측).
            if grep -qE '^\s*systemd\s*=\s*true' "$_WSL_CONF" 2>/dev/null; then
                _NEEDS_SYSTEMD=false
            fi

            if [ "$_NEEDS_SYSTEMD" = true ]; then
                echo "   ⏳ /etc/wsl.conf 에 systemd 활성화 설정을 안전하게 병합합니다... (sudo 필요)"
                if set_wsl_conf_key "boot" "systemd" "true" "$_WSL_CONF" \
                    && grep -qE '^\s*systemd\s*=\s*true' "$_WSL_CONF" 2>/dev/null; then
                    echo "   ✅ /etc/wsl.conf 에 systemd=true 추가 완료!"
                else
                    print_warn "/etc/wsl.conf 를 수정하지 못했습니다(sudo 권한 필요). 직접 추가하세요: sudo nano /etc/wsl.conf → [boot] systemd=true"
                fi
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
    echo "   📋 바로 사용하기 (에이전트 로그인, 1회만):"
    echo "   ---------------------------------------------------------------------"
    echo "   Orca는 오케스트레이터일 뿐이라, 위에서 점검한 에이전트 CLI를 PATH에서 찾아 그대로 실행합니다."
    echo "   각 CLI를 한 번 실행해 로그인하세요(구독 계정 로그인 또는 API 키 중 하나):"
    echo ""
    echo "     • Claude Code : claude   (처음 실행 시 로그인 / 미설치: curl -fsSL https://claude.ai/install.sh | bash)"
    echo "     • Codex       : codex    (처음 실행 시 로그인 / 미설치: npm i -g @openai/codex)"
    echo "     • Gemini CLI  : gemini   (처음 실행 시 로그인 / 미설치: npm i -g @google/gemini-cli)"
    echo "     • OpenCode    : opencode.ai 설치 스크립트 →  opencode auth login"
    echo "     • Goose       : Block의 Goose CLI 설치    →  goose configure"
    echo ""
    echo "   🔐 API 키 방식이라면 키는 저장소 밖의 ~/.config/devtools2/secrets.env (권한 600)에만 넣으세요:"
    echo "        export ANTHROPIC_API_KEY='...'"
    echo "      셸·Neovim(CodeCompanion)·orca serve 가 모두 이 파일을 읽습니다. 수정 후 orca serve 반영:"
    echo "        systemctl --user restart orca-serve.service"
    echo "      ⚠️ 키를 저장소 안 파일(.config, scripts 등)에 적지 마세요 — 공개 GitHub 저장소입니다."
    echo "         (커밋 직전에 scripts/git-hooks/pre-commit 이 키·인증 파일을 검사해 막습니다)"
    echo ""
    echo "   Claude/Codex는 Orca 자체 계정 전환/사용량 추적 기능도 지원합니다(선택 사항):"
    echo "     orca account add --agent claude"
    echo "     orca account add --agent codex"
    echo "     orca account list"
    echo ""
    echo "   에이전트 CLI를 나중에 새로 설치했다면 스킬을 다시 설치해주세요:"
    echo "     orca skills install --skill orca-cli --skill orchestration"
    echo ""
    echo "   준비가 끝나면 Orca에서 에이전트를 지정해 워크트리를 만들 수 있습니다:"
    echo "     orca worktree create --name 작업이름 --agent claude --prompt \"할 일\""
    echo "   ---------------------------------------------------------------------"
fi
echo ""
