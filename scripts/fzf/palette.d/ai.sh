# shellcheck shell=bash
# ==============================================================================
# [명령 팔레트] 🤖 AI — AI 공통 설정(규칙·작업 노트) · Orca 열기 · 에이전트 스킬 가져오기 · 스킬 연결 상태
# ==============================================================================
# command-palette 가 source 로 불러오는 파일입니다(단독 실행 X). 구조 설명은 command-palette 의
# "그룹 파일 불러오기" 주석을 보세요. 이 파일 = 1단계 메뉴 그룹 "🤖 AI" (그룹 ID: ai)

# Orca 는 DevTools2 가 modules/orca 에 설치 (orca-app = WSLg 한글 입력 환경을 맞춘 실행 래퍼, orca = CLI)
_ORCA_DIR="${DEVTOOLS2:-/var/opt/_devtools2}/modules/orca"

# AI — Orca(설치돼 있을 때)와 에이전트 스킬(Claude·Codex·Antigravity 공용 — scripts/linux/cmd/agent-skills.sh)
#   ● Orca 는 편집기가 아니라 저장소(프로젝트)·워크트리·에이전트를 관리하는 앱이라 "🧰 외부 도구"와 나눠 이 그룹에 둡니다.
#     (modules/orca 는 Linux AppImage 라 WSL(WSLg)·Linux 데스크톱에서만)
#   ● 스킬 항목은 Orca 없이도 동작하므로(에이전트 폴더 ↔ 저장소 링크) Orca 가 없는 PC 에서도 보입니다.
#     Orca 공유 링크로 받은 스킬은 Orca 앱에서 "이 컴퓨터 · 전역"으로 설치하면 ~/.agents/skills 에 생기고,
#     "스킬 가져오기"로 저장소에 넣습니다(Orca CLI 에는 공유 링크로 설치하는 명령이 없어 설치는 앱 화면에서).
#   ● AI 공통 설정은 모든 에이전트가 쓰는 가장 기본 설정이라 맨 위에 둡니다(git 만 있으면 보임).
#     공용 작업 노트 저장소(github.com/devers2/agent-notes, 비공개)를 받거나 갱신한 뒤, 저장소의 scripts/setup.sh 로 에이전트별 설정
#     (Claude Code·Codex·Antigravity·Grok Build·Cursor 의 지시 블록 = 공통 규칙(언어·주석 보존 등) + 작업 노트 안내, hook, Codex hook 신뢰 기록)을 맞춥니다. 설정 로직은 노트 저장소가 가지고,
#     팔레트는 받기·로그인 안내·실행만 합니다(노트 쪽 설정이 바뀌어도 팔레트를 고칠 필요가 없게).
#     메뉴 이름은 저장소 유무와 상관없이 "설정" 하나 — 없으면 받고(clone) 있으면 업데이트(pull)한 뒤 설정하는 멱등 동작이라,
#     첫 설치·장비 추가·공통 규칙이나 노트 안내(블록)가 바뀐 뒤 반영 모두 이 항목 하나로 합니다.
_AGENT_SKILLS="$_CP_SCRIPT_DIR/../linux/cmd/agent-skills.sh"
_AGENT_NOTES_DIR="${AGENT_NOTES_DIR:-$HOME/agent-notes}"
_AGENT_NOTES_URL="https://github.com/devers2/agent-notes.git"
_MENU_AI=()
_AI_KW=()
if command -v git >/dev/null 2>&1; then
    _MENU_AI+=("agent_notes	AI 공통 설정 (규칙·작업 노트)")
    _AI_KW+=("공통 설정")
fi
if [ -x "$_ORCA_DIR/orca" ] && { $IS_WSL || $_HAS_DESKTOP; }; then
    if [ -n "$_GIT_ROOT" ]; then
        _MENU_AI+=("open_orca	Orca 열기 + 현재 저장소를 프로젝트로 추가")
    else
        _MENU_AI+=("open_orca	Orca 열기")
    fi
    _AI_KW+=("Orca")
fi
if [ -f "$_AGENT_SKILLS" ]; then
    _MENU_AI+=(
        "skills_import	스킬 가져오기 (에이전트 폴더 → DevTools2 저장소, Orca 에서 받은 스킬 등)"
        "skills_status	스킬 연결 상태 · 다시 연결 (Claude · Codex · Antigravity)"
    )
    _AI_KW+=("스킬 가져오기" "스킬 연결 상태")
fi


# ── 1단계 메뉴 등록 · 2단계 선택 ─────────────────────────────────────────────
[ "${#_MENU_AI[@]}" -gt 0 ] && cp_register_group ai "🤖 AI ▸ $(_cp_join_kw "${_AI_KW[@]}")"
cp_group_ai() {
    CHOICE_ID=$(_pick_leaf "🤖 AI > " "${_MENU_AI[@]}")
}

# ── [AI] AI 공통 설정 (규칙·작업 노트) — agent-notes 받기·업데이트 + 에이전트별 설정 ──────────
# 여러 AI·여러 장비가 함께 쓰는 공통 규칙·작업 노트 저장소를 이 PC 에 맞춥니다. 다시 실행해도 안전합니다(멱등).
#   ● 없으면 clone, 있으면 pull(--rebase --autostash — 작성 중인 노트는 보존)한 뒤 저장소의 scripts/setup.sh 를 실행합니다.
#     setup.sh 가 설치된 에이전트(Claude Code·Codex·Antigravity·Grok Build·Cursor)의 지시 블록·hook 을 맞추고,
#     git 계정·원격 접근을 점검합니다(기존 설정·다른 hook 은 그대로 둠).
#   ● 비공개 저장소라 GitHub 로그인이 필요합니다. 접근이 안 되면 PR 체크아웃과 같은 방식(Bitwarden 의 PAT)으로 로그인할지 묻고,
#     그래도 안 되면 gh auth login 을 안내합니다.
#   ● git user.name/email 이 없으면 커밋(노트 자동 push)이 실패하므로 먼저 물어 설정합니다.
cp_run_agent_notes() {
    if ! git ls-remote -q "$_AGENT_NOTES_URL" >/dev/null 2>&1; then
        echo "⚠️  agent-notes 저장소($_AGENT_NOTES_URL)에 접근할 수 없습니다(비공개 — GitHub 로그인 필요)."
        if declare -f bw_setup_github_auth >/dev/null 2>&1 && prompt_confirm "🔑 Bitwarden 에 저장된 PAT 로 로그인할까요?" "Y"; then
            bw_setup_github_auth || exit 1
        fi
        if ! git ls-remote -q "$_AGENT_NOTES_URL" >/dev/null 2>&1; then
            echo "❌ GitHub 로그인 후 다시 시도하세요: gh auth login (저장소가 아직 없다면 먼저 만들어야 합니다)"
            exit 1
        fi
    fi
    for _key in user.name user.email; do
        if [ -z "$(git config --global "$_key")" ]; then
            read -r -p "✏️  git $_key 를 입력하세요: " _val
            [ -z "$_val" ] && { echo "❌ git $_key 가 필요합니다."; exit 1; }
            git config --global "$_key" "$_val"
        fi
    done
    if [ -d "$_AGENT_NOTES_DIR/.git" ]; then
        echo "⏳ agent-notes 갱신: $_AGENT_NOTES_DIR"
        if ! git -C "$_AGENT_NOTES_DIR" pull --rebase --autostash; then
            git -C "$_AGENT_NOTES_DIR" rebase --abort >/dev/null 2>&1 || true
            echo "❌ pull 에 실패했습니다(충돌 가능). $_AGENT_NOTES_DIR 에서 git status 로 확인하세요."
            exit 1
        fi
    else
        echo "⏳ agent-notes 받기: $_AGENT_NOTES_URL → $_AGENT_NOTES_DIR"
        git clone "$_AGENT_NOTES_URL" "$_AGENT_NOTES_DIR" || exit 1
    fi
    echo ""
    bash "$_AGENT_NOTES_DIR/scripts/setup.sh"
}

# ── [AI] Orca (+ 현재 저장소를 프로젝트로 추가) ─────────────────────────────────
# Orca 는 폴더를 여는 편집기가 아니라 저장소(프로젝트)를 등록해 워크트리·에이전트를 관리하는 앱입니다.
#   ● Orca 가 안 떠 있으면 orca-app(WSLg 한글 입력 환경을 맞춘 래퍼)으로 띄우고, CLI 가 연결될 때까지 최대 60초 기다립니다
#     (CLI 는 앱이 떠 있어야 동작 — 안 떠 있으면 runtime_unavailable).
#   ● Git 저장소 안이면 저장소 루트를 Orca 프로젝트로 추가합니다(이미 등록돼 있으면 건너뜀).
#   ● CLI 는 tool.setup-orca.sh 와 같이 setsid + timeout 으로 부릅니다(터미널 입력을 기다리며 멈추는 것 방지).
cp_run_open_orca() {
    _orca_q() {
        local _secs="$1"
        shift
        setsid -w timeout -k 5 "$_secs" "$_ORCA_DIR/orca" "$@" --json </dev/null 2>/dev/null
    }
    # JSON 결과 해석: ok 면 "ok", 아니면 오류 메시지. 두 번째 인자(경로)를 주면 그 경로가 목록에 있을 때 "has"
    _orca_json() {
        python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("응답을 해석하지 못했습니다"); sys.exit()
if not d.get("ok"):
    e = d.get("error") or {}
    print(e.get("message") or e.get("code") or "알 수 없는 오류"); sys.exit()
want = os.path.realpath(sys.argv[1]) if len(sys.argv) > 1 else None
def walk(v):
    if isinstance(v, dict): return any(walk(x) for x in v.values())
    if isinstance(v, list): return any(walk(x) for x in v)
    return isinstance(v, str) and v.startswith("/") and os.path.realpath(v) == want
print("has" if want and walk(d.get("result", d)) else "ok")
' "$@"
    }
    _ORCA_STATE=$(_orca_q 20 repo list | _orca_json ${_GIT_ROOT:+"$_GIT_ROOT"})
    if [ "$_ORCA_STATE" != "ok" ] && [ "$_ORCA_STATE" != "has" ]; then
        echo "🐋 Orca 를 실행합니다..."
        _cp_detach "$_ORCA_DIR/orca-app"
        for _i in $(seq 1 60); do
            printf '\r   ⏳ Orca 연결 기다리는 중... %2d초' "$_i"
            sleep 1
            _ORCA_STATE=$(_orca_q 10 repo list | _orca_json ${_GIT_ROOT:+"$_GIT_ROOT"})
            [ "$_ORCA_STATE" = "ok" ] || [ "$_ORCA_STATE" = "has" ] && break
        done
        echo ""
        if [ "$_ORCA_STATE" != "ok" ] && [ "$_ORCA_STATE" != "has" ]; then
            echo "⚠️  60초 안에 Orca 에 연결하지 못했습니다: $_ORCA_STATE"
            echo "   Orca 창이 떴다면 잠시 뒤 다시 실행해 보세요."
            exit 1
        fi
        echo "✅ Orca 를 실행했습니다."
    else
        echo "ℹ️  Orca 가 이미 실행 중입니다."
    fi
    if [ -z "$_GIT_ROOT" ]; then
        echo "   (현재 폴더가 Git 저장소가 아니라 프로젝트 추가는 건너뜁니다)"
    elif [ "$_ORCA_STATE" = "has" ]; then
        echo "ℹ️  이미 Orca 에 등록된 프로젝트입니다: $_GIT_ROOT"
    else
        _ORCA_ADD=$(_orca_q 30 repo add --path "$_GIT_ROOT" | _orca_json)
        if [ "$_ORCA_ADD" = "ok" ]; then
            echo "✅ Orca 에 프로젝트를 추가했습니다: $_GIT_ROOT"
        else
            echo "❌ Orca 에 프로젝트를 추가하지 못했습니다: $_ORCA_ADD"
            exit 1
        fi
    fi
    echo "   Orca 창의 프로젝트 목록에서 고르세요."
}

# ── [AI] 연결 상태 · 다시 연결 ─────────────────────────────────────────────
# 저장소 스킬을 설치된 에이전트 폴더에 다시 연결(sync)한 뒤 상태를 보여 줍니다. 셸을 열 때도 자동으로 맞추지만,
# targets.conf 를 고쳤거나 에이전트를 막 설치한 직후 바로 반영할 때 씁니다.
cp_run_skills_status() {
    bash "$_AGENT_SKILLS" sync
    echo ""
    bash "$_AGENT_SKILLS" status
}

# ── [AI] 스킬 가져오기 ───────────────────────────────────────────────────
# 에이전트 폴더에만 있는 스킬(Orca 공유 링크로 받은 것 등)을 저장소로 옮기고 링크로 바꾼 뒤 커밋·푸시까지 안내합니다.
cp_run_skills_import() {
    bash "$_AGENT_SKILLS" import
}
