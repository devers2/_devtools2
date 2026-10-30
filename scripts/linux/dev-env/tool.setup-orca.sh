#!/bin/bash
# ==============================================================================
# Linux용 Orca(멀티 에이전트 오케스트레이션 ADE) 설치 스크립트 (tool.setup-orca.sh)
#
# ------------------------------------------------------------------------------
# ⚠️ [Zed(tool.setup-zed.sh)와 달리 WSL2에서도 "건너뛰지 않고" 여기(리눅스 내부)에 설치하는 이유]
# Zed는 순수 에디터라 Windows 네이티브 앱이 WSL2의 파일을 UNC 경로로 열기만 하면 됩니다.
# 반면 Orca는 Claude Code/Codex/Antigravity 같은 CLI 에이전트 "프로세스"를 직접 실행(spawn)해야
# 하는 오케스트레이터입니다. 그 CLI들은 (npm i -g @anthropic-ai/claude-code 등으로) 전부
# 이 WSL2 내부에 설치되어 있습니다. Orca를 Windows 네이티브로만 설치하면 WSL2 안의 그
# 바이너리를 실행할 방법이 없습니다(공식 문서에 WSL 브릿지 기능 없음).
# [변경] 예전에는 Orca 공식 "Remote Orca Servers" 모드를 사용했습니다:
#   - 에이전트 실행부(orca serve)는 CLI가 실제로 있는 WSL2에 헤드리스로 두고,
#   - Windows에는 거기 페어링만 하는 가벼운 GUI 클라이언트를 설치(tool.setup-orca.ps1, 현재 삭제됨).
# 지금은 WSLg 로 Linux 판 Orca GUI 를 WSL2 안에서 직접 띄웁니다. 에이전트 CLI 와 같은 환경에서 실행되므로
# Windows 앱·페어링·상시 서버가 필요 없고 Linux 데스크톱과 설치·실행 방식이 같습니다(아래 "GUI 실행 래퍼" 주석 참고).
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
#   다시 받지 않습니다. 실행 중인 Orca 가 있어도 mv 교체는 안전합니다(기존 프로세스는 옛 파일을 계속 씀, 다시 열면 새 버전).
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
    # (Linux 판 Orca 도 실행 중 새 버전을 알려 주지만, 설치 스크립트 재실행 시에도 같은 규칙으로 최신 버전을 맞춥니다.
    #  예전 Windows 앱 + WSL 서버 방식에서는 Windows 앱만 스스로 업데이트되어 서버와 어긋나는 문제도 있었음)
    # 판단은 공용 함수 decide_app_action(_install-utils.sh, 앱 규칙)에 맡깁니다.
    # (최신 버전 확인 실패·이미 최신이면 건너뜀 / 버전 기록이 없으면 업데이트 제안 /
    #  무인 실행에서는 다른 도구들과 같은 규칙(기존 설치 유지)을 따르며 DT2_ORCA_UPDATE=y 로 강제 가능)
    decide_app_action "Orca" true "$_orca_cur" "$_orca_latest" "N" "DT2_ORCA" "(실행 중인 Orca 창은 닫았다가 다시 열어야 새 버전이 적용됨)"
    if [ "$DT2_APP_ACTION" = "update" ]; then
        if _orca_download "$_orca_latest"; then
            echo "   ✅ Orca 업데이트 완료 → $_orca_latest"
            _orca_updated=true
        fi
    fi
    echo "   ℹ️  아래 의존성·에이전트·실행 래퍼·바로가기 상태는 매번 다시 점검합니다."
else
    echo "   ℹ️  Orca는 여러 코딩 에이전트를 Git worktree로 격리해 병렬로 실행/조율하는"
    echo "      에이전트 오케스트레이션 도구입니다 (Claude Code, Codex, Antigravity 등 지원)."
    echo ""
    # 설치 여부 확인도 공용 함수 decide_app_action 사용 (DT2_ORCA_CHOICE=y|n 로 강제 가능, 기본값 N)
    decide_app_action "Orca" false "" "$_orca_latest" "N" "DT2_ORCA"
    _do_orca=false
    [ "$DT2_APP_ACTION" = "install" ] && _do_orca=true

    if [ "$_do_orca" = true ]; then
        if [ "$IS_WSL2" = true ]; then
            echo "   ⚠️  [WSL2 환경 감지] Orca 는 CLI 에이전트가 실제로 설치된 이 WSL2 내부에 설치하고,"
            echo "      WSLg 로 Windows 창에 띄웁니다 (Windows 앱·페어링 불필요)."
            echo ""
        fi
        if _orca_download "$_orca_latest"; then
            echo "   ✅ orca ($ARCH${_orca_latest:+, ${_orca_latest}}) 설치 완료 → $ORCA_APPIMAGE"
            _orca_proceed=true
        fi
    else
        # (건너뜀 안내는 decide_app_action 이 출력)
        :
    fi
fi

if [ "$_orca_proceed" = true ]; then
    # orca AppImage 실행에 필요한 의존성 (공식 헤드리스 서버 가이드 기준:
    # curl file jq xvfb zlib1g-dev). curl은 이미 이 저장소 전체가 의존하므로 생략.
    # xvfb(가상 화면)는 화면 없는 orca serve 전용이라, GUI 로 직접 실행하는 지금 방식에서는 설치하지 않습니다.
    # 이미 설치된 상태로 재실행돼도 전부 존재 여부부터 확인하고 스킵하므로 안전합니다.
    _ensure_pkg file file
    _ensure_pkg jq jq
    if ! dpkg -s libfuse2 >/dev/null 2>&1 && ! dpkg -s libfuse2t64 >/dev/null 2>&1; then
        dt2_sudo_auth || true   # 비밀번호 질문이 스피너에 가려지지 않도록 먼저 인증
        echo -n "   📦 필수 패키지 (libfuse2) 자동 설치 중..."
        (sudo apt-get update -qq >/dev/null 2>&1 || true; sudo apt-get install -y libfuse2t64 >/dev/null 2>&1 || sudo apt-get install -y libfuse2 >/dev/null 2>&1 || true) &
        _fuse_pid=$!
        show_spinner $_fuse_pid
        wait $_fuse_pid 2>/dev/null || true
        echo " 완료"
    fi
    if ! dpkg -s zlib1g-dev >/dev/null 2>&1; then
        dt2_sudo_auth || true
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
        dt2_sudo_auth || true
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
    #   이미 있는 파일은 여기서 소유자 전용으로 맞추고, 새로 생기는 파일은 실행 래퍼(orca-app)의 umask 077 이 막습니다.
    for _orca_cfg in "$HOME/.config/orca" "$HOME/.config/Orca" "$HOME/.orca"; do
        if [ -d "$_orca_cfg" ] && [ ! -L "$_orca_cfg" ]; then
            chmod -R go-rwx "$_orca_cfg" 2>/dev/null || true
        fi
    done

    # ── 바로 쓰기 위한 에이전트 CLI 점검/설치 ──
    # Orca 는 오케스트레이터일 뿐이라 claude/codex/agy 같은 에이전트 CLI 를 PATH 에서 찾아 실행합니다.
    # 하나도 없으면 Orca 를 띄워도 할 수 있는 일이 없으므로, 없는 것만 골라 설치 여부를 묻습니다.
    # - Claude Code: 공식 네이티브 설치 프로그램(~/.local/bin/claude, 자동 업데이트)
    # - Codex: npm 전역 설치(DevTools2 공용 npm prefix: $DEVTOOLS2/data/.npm-packages)
    # - Antigravity CLI(agy): Google 공식 설치 스크립트(~/.local/bin/agy). Google 이 2026-05-19 에 터미널 에이전트를
    #   Gemini CLI 에서 Antigravity CLI 로 전환했고, Gemini CLI 는 2026-06-18 부터 Google AI Pro·Ultra·무료 사용자
    #   요청을 받지 않습니다(google-gemini/gemini-cli Discussion #27274). 그래서 Gemini CLI 대신 설치합니다.
    #   (기존 Gemini CLI 확장은 'agy plugin import gemini' 로 옮길 수 있음)
    # 무인 실행에서는 묻지 않고 건너뜁니다. DT2_ORCA_AGENTS="claude,codex,antigravity" 로 지정할 수 있습니다(none=설치 안 함).
    # (예전 이름 "gemini" 를 넣어도 antigravity 로 처리)
    # [이미 설치된 에이전트 CLI 는 묻지 않고 최신으로 업데이트]
    #   에이전트 CLI 는 자주 업데이트되고 하위 호환이 좋은 편이며, Linux 에서는 사용자가 따로 업데이트하기 번거로워
    #   이 단계에서 각자의 공식 업데이트 명령을 실행합니다(새 버전이 있을 때만 바뀌고, 이미 최신이면 그대로).
    #   ● Claude Code: claude update / Antigravity: agy update / Codex: npm 레지스트리 최신과 비교 후 npm i -g @openai/codex@latest
    #   ● 업데이트에 실패해도 기존 설치는 그대로 두고 계속 진행합니다(시간 제한 180초).
    #   ● 건너뛰려면 DT2_ORCA_AGENTS_UPDATE=n
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
    if ! command -v npm >/dev/null 2>&1 && [ -f "$HOME/.config/devtools2/env.sh" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.config/devtools2/env.sh" >/dev/null 2>&1 || true
    fi
    for _npm_bin in \
        "$DEVTOOLS2/data/.npm-packages/lib/node_modules/.bin" \
        "$DEVTOOLS2/data/.npm-packages/bin"; do
        [ -d "$_npm_bin" ] && case ":$PATH:" in *":$_npm_bin:"*) ;; *) export PATH="$_npm_bin:$PATH" ;; esac
    done
    echo ""
    echo "   🤖 에이전트 CLI 점검 (Orca 가 실제로 실행할 대상)"
    _orca_agent_added=false
    _orca_agent_names=("claude" "codex" "agy")
    _orca_agent_labels=("Claude Code" "Codex" "Antigravity CLI (Google, Gemini CLI 후속)")
    _orca_agent_defaults=("N" "N" "N")
    # 설치된 에이전트 CLI 의 버전 문자열 (업데이트 전후 비교용)
    _orca_agent_ver() { "$1" --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1 || true; }
    # 설치된 에이전트 CLI 를 공식 업데이트 명령으로 최신화 (새 버전이 있을 때만 바뀜, 실패해도 계속)
    _orca_agent_update() {
        local cmd="$1" label="$2" before after latest
        before=$(_orca_agent_ver "$cmd")
        case "$cmd" in
            claude) timeout -k 5 180 claude update < /dev/null >/dev/null 2>&1 || true ;;
            agy)    timeout -k 5 180 agy update < /dev/null >/dev/null 2>&1 || true ;;
            codex)
                latest=$(timeout 30 npm view @openai/codex version 2>/dev/null || true)
                if [ -n "$latest" ] && [ "$latest" != "$before" ]; then
                    timeout -k 5 180 npm install -g --no-audit --no-fund "@openai/codex@latest" < /dev/null >/dev/null 2>&1 || true
                fi
                ;;
        esac
        hash -r
        after=$(_orca_agent_ver "$cmd")
        if [ -n "$after" ] && [ "$after" != "$before" ]; then
            echo "      ⬆️  $label: ${before:-?} → $after 업데이트 완료 ($(command -v "$cmd"))"
        else
            echo "      ✅ $label: 설치됨, 최신 버전 ${after:-${before:-?}} ($(command -v "$cmd"))"
        fi
    }
    for _i in "${!_orca_agent_names[@]}"; do
        _cmd="${_orca_agent_names[$_i]}"
        _label="${_orca_agent_labels[$_i]}"
        if command -v "$_cmd" >/dev/null 2>&1; then
            if [ "${DT2_ORCA_AGENTS_UPDATE:-y}" = "n" ]; then
                echo "      ✅ $_label: 설치됨 ($(command -v "$_cmd")) — 업데이트 건너뜀 (DT2_ORCA_AGENTS_UPDATE=n)"
            else
                _orca_agent_update "$_cmd" "$_label"
            fi
            continue
        fi
        _want=false
        if [ -n "${DT2_ORCA_AGENTS:-}" ]; then
            _agents_req=",${DT2_ORCA_AGENTS,,},"
            _agents_req="${_agents_req//,gemini,/,agy,}"; _agents_req="${_agents_req//,antigravity,/,agy,}"
            [[ "$_agents_req" == *",$_cmd,"* ]] && _want=true
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
            agy)
                _agy_installer=$(mktemp)
                if curl -fsSL --max-time 60 https://antigravity.google/cli/install.sh -o "$_agy_installer" && bash "$_agy_installer"; then
                    hash -r
                fi
                rm -f "$_agy_installer"
                ;;
        esac
        # npm 글로벌 설치 후 생성된 bin 디렉터리 PATH 재동기화
        for _npm_bin in \
            "$DEVTOOLS2/data/.npm-packages/lib/node_modules/.bin" \
            "$DEVTOOLS2/data/.npm-packages/bin"; do
            [ -d "$_npm_bin" ] && case ":$PATH:" in *":$_npm_bin:"*) ;; *) export PATH="$_npm_bin:$PATH" ;; esac
        done
        hash -r
        if command -v "$_cmd" >/dev/null 2>&1; then
            echo "      ✅ $_label 설치 완료 ($(command -v "$_cmd"))"
            _orca_agent_added=true   # 새 에이전트에도 스킬을 설치해야 하므로 아래 스킬 단계에서 install 실행
        else
            print_warn "$_label 설치에 실패했습니다. 나중에 직접 설치하세요(아래 안내 참고)."
        fi
    done

    # ── 권장 스킬 전역 설치 (베스트 에포트) ──
    # 공식 문서(onorca.dev/docs/cli/skills)가 헤드리스 호스트용으로 명시한 명령입니다.
    # ⚠️ 에이전트 CLI 를 먼저 설치한 뒤 실행해야 합니다: Orca 가 감지한 에이전트가 하나도 없으면
    #   "--agent 지정 필요"로 실패합니다(orca skills install --help).
    # ⚠️ Electron/Node 내부의 /bin/bash -ilc 환경변수 스캔 시 tty 경합(SIGTTIN/SIGTSTP)으로 일시정지(프리징)되는
    #   문제를 방지하기 위해 표준입력을 /dev/null 로 분리하고, -k 5 타임아웃을 둡니다.
    _detected_agents=0
    for _c in "${_orca_agent_names[@]}"; do
        command -v "$_c" >/dev/null 2>&1 && _detected_agents=$((_detected_agents + 1))
    done

    # ── 이미 설치되어 있으면 건너뜀 (예전에는 실행할 때마다 설치를 시도했음) ──
    #   ● 설치 여부는 Orca 의 "skills installed --json"(전역 설치 목록)으로 확인합니다.
    #   ● 다시 실행하는 경우: 둘 중 하나라도 없음 / 이번에 에이전트 CLI 를 새로 설치함(그 에이전트에도 설치 필요)
    #     → skills install,  Orca 가 이번에 업데이트됨 → skills update(이미 설치된 위치만 새 Orca 버전에 맞게 갱신)
    _orca_skills_have=""
    if [ "$_detected_agents" -gt 0 ]; then
        _orca_skills_have=$(timeout -k 5 30 "$ORCA_APPIMAGE" skills installed --json < /dev/null 2>/dev/null \
            | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(" ".join(s.get("name", "") for s in d.get("result", {}).get("skills", [])))
except Exception:
    pass' 2>/dev/null || true)
    fi
    _orca_skills_missing=false
    for _sk in orca-cli orchestration; do
        [[ " $_orca_skills_have " == *" $_sk "* ]] || _orca_skills_missing=true
    done

    echo ""
    if [ "$_detected_agents" -gt 0 ] && [ "$_orca_skills_missing" = false ] && [ "$_orca_agent_added" = false ]; then
        if [ "$_orca_updated" = true ]; then
            echo "   🧩 Orca 가 업데이트되어 권장 스킬(orca-cli, orchestration)을 새 버전에 맞게 갱신 중..."
            if timeout -k 5 30 "$ORCA_APPIMAGE" skills update --skill orca-cli --skill orchestration < /dev/null >/dev/null 2>&1; then
                echo "   ✅ 스킬 갱신 완료"
            else
                echo "   ⚠️  스킬 갱신을 건너뜁니다 (직접 실행: orca skills update --skill orca-cli --skill orchestration)."
            fi
        else
            echo "   ✅ 권장 스킬(orca-cli, orchestration) 이미 설치됨 — 건너뜀"
        fi
    elif [ "$_detected_agents" -gt 0 ]; then
        echo "   🧩 권장 스킬(orca-cli, orchestration) 설치 시도 중..."
        _skills_log=$(mktemp)
        if timeout -k 5 30 "$ORCA_APPIMAGE" skills install --skill orca-cli --skill orchestration < /dev/null >"$_skills_log" 2>&1; then
            echo "   ✅ 스킬 설치 완료"
        else
            echo "   ⚠️  스킬 설치를 건너뜁니다 (에이전트 연동 후 직접 실행 가능: orca skills install --skill orca-cli --skill orchestration)."
            tail -n 3 "$_skills_log" 2>/dev/null | sed 's/^/      │ /' || true
        fi
        rm -f "$_skills_log"
    else
        echo "   ℹ️  감지된 에이전트 CLI가 없어 스킬 설치를 건너뜁니다 (에이전트 로그인/설치 후: orca skills install --skill orca-cli --skill orchestration)."
    fi

    # ── GUI 앱 실행 환경 준비: WSLg 활성화 확인 · 한글 입력기 · 한글 UI 글꼴 (없을 때만) ──
    # Sublime Merge 설치와 같은 공용 함수(_install-utils.sh 의 ensure_gui_app_env)를 씁니다.
    # 예전에는 Sublime Merge 만 이 준비를 해서, Orca 만 설치하면 아래 래퍼의 wslg_ime_env_snippet 이
    # 기동할 fcitx5 가 없어 WSLg 창에서 한글을 입력할 수 없었습니다. 헤드리스 서버에서는 건너뜁니다.
    ensure_gui_app_env "Orca"

    # ── GUI 실행 래퍼 + 앱 바로가기 (Linux 데스크톱 / WSL2 WSLg 공통) ──
    # [WSL2 도 Linux 데스크톱과 같은 방식(GUI 직접 실행)으로 쓰는 이유]
    #   예전에는 WSL2 에 orca serve(헤드리스, systemd 상시 실행)를 두고 Windows Orca 앱이 WSL2 IP 로 페어링하는
    #   공식 "Remote Orca Servers" 방식이었습니다. WSLg 로 Linux 판 Orca GUI 를 Windows 창으로 직접 띄우면
    #   에이전트 CLI 가 있는 WSL2 안에서 그대로 실행되므로 Windows 앱·페어링·상시 서버(실측 약 840MB)가 필요 없고
    #   Linux 데스크톱과 구조가 같아집니다 (WSLg 실행·한국어 UI·에이전트 감지 실측 확인, Sublime Merge 와 같은 전환).
    #   단, 서버 방식과 달리 Orca 창을 닫으면 에이전트도 멈춥니다(Linux 데스크톱과 동일 — 창을 띄워 두고 사용).
    # [래퍼(orca-app)가 하는 일] — 예전 systemd 서비스 래퍼가 하던 일 중 GUI 실행에도 필요한 것을 그대로 옮김
    #   ● umask 077: WSL 에는 OS 키링이 없어 Orca 가 계정 토큰을 평문 파일로 저장하므로 새 파일을 소유자 전용으로 만듭니다
    #     (위 chmod 는 이미 있는 파일, 이 umask 는 새로 생기는 파일을 막음).
    #   ● 셸과 같은 env.sh(→ secrets.env 의 API 키 포함)를 직접 읽고 ~/.local/bin 을 PATH 앞에 붙입니다.
    #     .desktop·AutoHotkey 로 실행하면 ~/.bashrc 를 읽지 않아 Claude Code 네이티브 설치(~/.local/bin/claude)와
    #     Antigravity CLI(~/.local/bin/agy), Orca 가 설치하는 orca 명령을 찾지 못해 에이전트를 실행할 수 없기 때문입니다.
    #   ● WSL2: fcitx5 한글 입력기 환경 (_install-utils.sh 의 wslg_ime_env_snippet — Sublime Merge 래퍼와 공유)
    #   ● 예전 serve 래퍼의 LIBGL_ALWAYS_SOFTWARE=1 은 화면 없는 Xvfb 용이라 넣지 않습니다(WSLg 는 GPU 렌더링 가능).
    _orca_launcher="$ORCA_DIR/orca-app"
    cat > "$_orca_launcher" <<EOF
#!/bin/bash
# tool.setup-orca.sh 가 생성 — 직접 수정하면 다음 설치 때 덮어써집니다.
umask 077
[ -f "\$HOME/.config/devtools2/env.sh" ] && . "\$HOME/.config/devtools2/env.sh" >/dev/null 2>&1
[ -f "\$HOME/.config/devtools2/secrets.env" ] && . "\$HOME/.config/devtools2/secrets.env" >/dev/null 2>&1
case ":\$PATH:" in *":\$HOME/.local/bin:"*) ;; *) PATH="\$HOME/.local/bin:\$PATH" ;; esac
export PATH
$(wslg_ime_env_snippet)
exec "$ORCA_APPIMAGE" "\$@"
EOF
    chmod +x "$_orca_launcher"
    echo "   ✅ Orca 실행 래퍼 생성: $_orca_launcher (터미널에서 'orca-app' 으로 실행)"

    # 앱 바로가기: Linux 앱 메뉴 / WSL2 는 WSLg 가 Windows 시작 메뉴에 자동 노출 (Exec 는 위 래퍼)
    _orca_desktop_dir="$HOME/.local/share/applications"
    mkdir -p "$_orca_desktop_dir"
    cat > "$_orca_desktop_dir/orca.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Orca
Comment=멀티 에이전트 오케스트레이션 ADE (DevTools2)
Exec=$_orca_launcher %U
Terminal=false
Categories=Development;
StartupNotify=true
EOF
    echo "   ✅ 앱 바로가기 등록: $_orca_desktop_dir/orca.desktop"

    if [ "$_orca_updated" = true ]; then
        echo "   ℹ️  Orca 가 업데이트되었습니다. 실행 중인 Orca 창이 있다면 닫았다가 다시 열면 새 버전이 적용됩니다."
    fi

    # ── [정리] 예전 WSL2 헤드리스 서버(orca serve) + Windows 앱 페어링 방식 회수 ──
    # DevTools2 가 만든 것(서비스 설명 문구·래퍼 경로 일치)만 지웁니다. Orca 계정/설정(~/.config/Orca 등)은
    # GUI 가 같은 프로필을 그대로 쓰므로 유지합니다. 같은 프로필을 쓰는 서버가 떠 있으면 GUI 가 실행되지 않으므로
    # (단일 인스턴스, 종료 코드 3) 반드시 먼저 멈춥니다.
    if [ "$IS_WSL2" = true ]; then
        _orca_old_unit="$HOME/.config/systemd/user/orca-serve.service"
        _orca_cleaned=false
        if [ -f "$_orca_old_unit" ] && grep -q "Orca headless agent orchestration server" "$_orca_old_unit" 2>/dev/null; then
            systemctl --user disable --now orca-serve.service >/dev/null 2>&1 || true
            rm -f "$_orca_old_unit"
            systemctl --user daemon-reload >/dev/null 2>&1 || true
            _orca_cleaned=true
        fi
        # systemd 없이 수동으로 띄웠던 경우(예전 "systemctl 없음" 폴백)도 정리
        if pgrep -u "$(id -u)" -f "$ORCA_DIR/orca-serve-wrapper.sh" >/dev/null 2>&1 \
            || pgrep -u "$(id -u)" -f "serve --port 6768 --pairing-address" >/dev/null 2>&1; then
            pkill -u "$(id -u)" -f "$ORCA_DIR/orca-serve-wrapper.sh" >/dev/null 2>&1 || true
            pkill -u "$(id -u)" -f "serve --port 6768 --pairing-address" >/dev/null 2>&1 || true
            _orca_cleaned=true
        fi
        if [ -f "$ORCA_DIR/orca-serve-wrapper.sh" ] || [ -f "$DEVTOOLS2/data/orca-pairing-link.txt" ]; then
            rm -f "$ORCA_DIR/orca-serve-wrapper.sh" "$DEVTOOLS2/data/orca-pairing-link.txt"
            _orca_cleaned=true
        fi
        if [ "$_orca_cleaned" = true ]; then
            echo "   🧹 예전 헤드리스 서버(orca serve)·페어링 설정을 정리했습니다."
            echo "      Windows 의 Orca 데스크톱 앱은 더 이상 필요 없습니다 (Windows PowerShell): winget uninstall --id StablyAI.Orca"
        fi
        echo "   💬 [WSL2] WSLg 로 Linux 판 Orca 를 Windows 창으로 실행합니다: 'orca-app' 또는 Windows 시작 메뉴의 Orca"
    else
        echo "   💬 일반 데스크톱 GUI 앱으로 바로 실행할 수 있습니다: 'orca-app' 또는 앱 메뉴의 Orca"
    fi

    # ── 실제로 쓰려면 필요한 다음 단계 안내 ──
    # Orca는 오케스트레이터일 뿐, claude/codex/agy 등 실제 에이전트 CLI 바이너리는
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
    echo "     • Antigravity : agy      (처음 실행 시 로그인 / 미설치: curl -fsSL https://antigravity.google/cli/install.sh | bash)"
    echo "                   (Gemini CLI 의 후속 — 기존 Gemini CLI 확장 이전: agy plugin import gemini)"
    echo "     • OpenCode    : opencode.ai 설치 스크립트 →  opencode auth login"
    echo "     • Goose       : Block의 Goose CLI 설치    →  goose configure"
    echo ""
    echo "   🔐 API 키 방식이라면 키는 저장소 밖의 ~/.config/devtools2/secrets.env (권한 600)에만 넣으세요:"
    echo "        export ANTHROPIC_API_KEY='...'"
    echo "      셸·Neovim(CodeCompanion)·Orca(orca-app 래퍼)가 모두 이 파일을 읽습니다. 수정 후에는 Orca 를 다시 실행하세요."
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
