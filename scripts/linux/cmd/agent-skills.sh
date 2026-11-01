#!/bin/bash
# ==============================================================================
# [에이전트 스킬] DevTools2 저장소 하나로 여러 AI 에이전트의 스킬을 맞추는 도구
# ==============================================================================
# 사용법:
#   agent-skills.sh sync [--quiet]   저장소 스킬을 설치된 에이전트 폴더에 링크 (셸 시작·설치 스크립트가 호출)
#   agent-skills.sh status           에이전트별 연결 상태와 가져올 수 있는 스킬 표시
#   agent-skills.sh import           에이전트 폴더에 직접 설치된 스킬(Orca 공유 링크로 받은 것 등)을 저장소로 가져오기
#
# [설계 원칙 / Rationale]
#   ● 스킬 원본은 저장소의 .config/agents/skills/<스킬>/SKILL.md 한 곳에만 두고, 에이전트 폴더에는 스킬마다
#     심볼릭 링크만 겁니다(Neovim 설정을 ~/.config/nvim 에 링크하는 것과 같은 방식). 내용 수정은 git pull 만으로 반영되고,
#     새 스킬·삭제된 스킬·새로 설치한 에이전트는 셸을 열 때 sync --quiet 가 링크를 맞춥니다.
#   ● 폴더 전체가 아니라 스킬마다 링크하는 이유: 에이전트 폴더에는 Orca 가 설치한 스킬(~/.agents/skills 의 실제 폴더 +
#     에이전트별 링크)과 Claude 계정에서 동기화된 스킬(~/.claude/skills/synced)이 함께 있어, 폴더 전체를 저장소로 바꾸면
#     그 파일들이 저장소 안으로 섞여 들어옵니다. 이 스크립트는 저장소를 가리키는 링크만 만들고 지웁니다.
#   ● 에이전트별 스킬 폴더 (각 공식 문서 기준, 위치가 바뀌면 아래 _agent_dir 한 곳만 고침):
#       claude       ~/.claude/skills          (Claude Code)
#       codex        ~/.agents/skills          (Codex 사용자 범위 — developers.openai.com/codex/skills, 링크 따라감 명시)
#       antigravity  ~/.gemini/config/skills   (Antigravity 앱·agy CLI 공통 — antigravity.google/docs/skills)
#     Antigravity 문서에는 링크 지원 여부가 없지만, Orca 도 이 폴더에 심볼릭 링크로 스킬을 연결합니다(실측 확인).
#   ● 설치된 에이전트에만 연결합니다. 특정 에이전트에서 뺄 스킬은 저장소의 targets.conf 에 적습니다(SKILL.md 는
#     세 에이전트 공통 형식 그대로 — name·description 만 쓰고 에이전트 전용 항목은 넣지 않는 것을 권장).
#   ● 같은 이름의 다른 스킬(실제 폴더나 다른 곳을 가리키는 링크)이 이미 있으면 덮어쓰지 않고 충돌로 알립니다.
# ==============================================================================

shopt -s nullglob

_AS_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AS_REPO="${DEVTOOLS2:-$(cd "$_AS_SELF_DIR/../../.." && pwd)}"
REPO_SKILLS="$_AS_REPO/.config/agents/skills"
TARGETS_CONF="$REPO_SKILLS/targets.conf"
_AS_STATE_DIR="${HOME}/.devtools2"
_AS_CONFLICT_STAMP="$_AS_STATE_DIR/agent-skills.conflicts"
_AS_BACKUP_DIR="$_AS_STATE_DIR/skill-backups"

AGENTS=(claude codex antigravity)

_agent_dir() {
    case "$1" in
    claude) echo "$HOME/.claude/skills" ;;
    codex) echo "$HOME/.agents/skills" ;;
    antigravity) echo "$HOME/.gemini/config/skills" ;;
    esac
}

_agent_label() {
    case "$1" in
    claude) echo "Claude" ;;
    codex) echo "Codex" ;;
    antigravity) echo "Antigravity" ;;
    esac
}

# 설치 여부: 명령이 있거나 설정 폴더가 있으면 설치된 것으로 봅니다(앱만 쓰는 경우도 있어 폴더도 확인)
_agent_installed() {
    case "$1" in
    claude) command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ] ;;
    codex) command -v codex >/dev/null 2>&1 || [ -d "$HOME/.codex" ] ;;
    antigravity)
        command -v agy >/dev/null 2>&1 || command -v antigravity >/dev/null 2>&1 ||
            [ -d "$HOME/.gemini/config" ] || [ -d "$HOME/.gemini/antigravity" ] || [ -d "$HOME/.gemini/antigravity-cli" ]
        ;;
    esac
}

# 저장소의 스킬 이름 목록 (SKILL.md 가 있는 하위 폴더)
_repo_skills() {
    local _d
    for _d in "$REPO_SKILLS"/*/; do
        [ -f "${_d}SKILL.md" ] && basename "$_d"
    done
}

# targets.conf 읽기 — "스킬 = claude, codex" 형식. 적지 않은 스킬은 모든 에이전트.
declare -A _AS_TARGETS=()
_load_targets() {
    [ -f "$TARGETS_CONF" ] || return 0
    local _line _name _list
    while IFS= read -r _line || [ -n "$_line" ]; do
        _line="${_line%%#*}"
        [[ "$_line" == *=* ]] || continue
        _name="${_line%%=*}"
        _list="${_line#*=}"
        _name="${_name//[[:space:]]/}"
        _list="${_list//[[:space:]]/}"
        [ -n "$_name" ] && _AS_TARGETS["$_name"]=",${_list},"
    done <"$TARGETS_CONF"
}

_skill_allowed() {
    local _skill="$1" _agent="$2"
    [ -z "${_AS_TARGETS[$_skill]+x}" ] && return 0
    [[ "${_AS_TARGETS[$_skill]}" == *",${_agent},"* ]]
}

# ── sync ─────────────────────────────────────────────────────────────────────
# 출력용 전역: _AS_LINKED(새로 연결 수), _AS_REMOVED(정리 수), _AS_CONFLICTS(배열)
_do_sync() {
    local _verbose="$1" _agent _dir _skill _link _want _cur
    _AS_LINKED=0
    _AS_REMOVED=0
    _AS_CONFLICTS=()
    [ -d "$REPO_SKILLS" ] || return 0
    local _skills
    mapfile -t _skills < <(_repo_skills)
    for _agent in "${AGENTS[@]}"; do
        _agent_installed "$_agent" || continue
        _dir=$(_agent_dir "$_agent")
        mkdir -p "$_dir" 2>/dev/null || continue
        for _skill in "${_skills[@]}"; do
            _skill_allowed "$_skill" "$_agent" || continue
            _link="$_dir/$_skill"
            _want="$REPO_SKILLS/$_skill"
            if [ -L "$_link" ]; then
                _cur=$(readlink "$_link")
                [ "$_cur" = "$_want" ] && continue
                # 끊어진 링크, 예전 저장소 위치를 가리키는 링크, 결국 같은 스킬로 이어지는 링크(가져오기 후 Orca 의
                # ~/.claude/skills/x → ~/.agents/skills/x → 저장소 연결 등)는 저장소로 바로 연결하도록 고칩니다.
                if [ ! -e "$_link" ] || [[ "$_cur" == "$REPO_SKILLS/"* ]] || [ "$(readlink -f "$_link")" = "$(readlink -f "$_want")" ]; then
                    ln -sfn "$_want" "$_link" && _AS_LINKED=$((_AS_LINKED + 1))
                    [ "$_verbose" = true ] && echo "   🔗 $(_agent_label "$_agent"): $_skill (링크 고침)"
                else
                    _AS_CONFLICTS+=("$(_agent_label "$_agent"): $_skill — 다른 곳을 가리키는 링크가 이미 있음 ($_cur)")
                fi
            elif [ -e "$_link" ]; then
                _AS_CONFLICTS+=("$(_agent_label "$_agent"): $_skill — 같은 이름의 폴더가 이미 있음 ($_link)")
            else
                ln -s "$_want" "$_link" && _AS_LINKED=$((_AS_LINKED + 1))
                [ "$_verbose" = true ] && echo "   🔗 $(_agent_label "$_agent"): $_skill"
            fi
        done
        # 저장소를 가리키는 링크 중 스킬이 지워졌거나 targets.conf 에서 뺀 것 정리 (다른 링크·폴더는 건드리지 않음)
        for _link in "$_dir"/*; do
            [ -L "$_link" ] || continue
            _cur=$(readlink "$_link")
            [[ "$_cur" == "$REPO_SKILLS/"* ]] || continue
            _skill="${_cur#"$REPO_SKILLS"/}"
            if [ ! -f "$REPO_SKILLS/$_skill/SKILL.md" ] || ! _skill_allowed "$_skill" "$_agent" || [ "$(basename "$_link")" != "$_skill" ]; then
                rm -f "$_link" && _AS_REMOVED=$((_AS_REMOVED + 1))
                [ "$_verbose" = true ] && echo "   🧹 $(_agent_label "$_agent"): $(basename "$_link") (저장소에 없거나 이 에이전트에서 뺀 스킬)"
            fi
        done
    done
}

cmd_sync() {
    local _quiet=false
    [ "${1:-}" = "--quiet" ] && _quiet=true
    _load_targets
    if $_quiet; then
        _do_sync false
    else
        _do_sync true
    fi
    if [ "$_AS_LINKED" -gt 0 ] || [ "$_AS_REMOVED" -gt 0 ]; then
        echo "🧩 에이전트 스킬 링크를 맞췄습니다 (연결 ${_AS_LINKED} · 정리 ${_AS_REMOVED})"
    elif ! $_quiet; then
        echo "✅ 에이전트 스킬 링크가 이미 맞습니다."
    fi
    # 충돌: --quiet(셸 시작)에서는 내용이 바뀌었을 때만 한 번 알립니다(셸을 열 때마다 같은 경고가 반복되지 않게)
    local _sig=""
    [ "${#_AS_CONFLICTS[@]}" -gt 0 ] && _sig=$(printf '%s\n' "${_AS_CONFLICTS[@]}")
    if [ -n "$_sig" ]; then
        if ! $_quiet || [ "$(cat "$_AS_CONFLICT_STAMP" 2>/dev/null)" != "$_sig" ]; then
            echo "⚠️  같은 이름의 다른 스킬이 있어 연결하지 않았습니다 (덮어쓰지 않음):"
            printf '   • %s\n' "${_AS_CONFLICTS[@]}"
            echo "   → 저장소 스킬을 쓰려면 에이전트 폴더 쪽 스킬을 지우거나 옮기고, 둘 다 쓰려면 한쪽 폴더 이름을 바꾸세요."
            echo "     (에이전트 폴더 쪽이 다른 PC 에도 필요한 스킬이면, 이름을 바꾼 뒤 Alt+C ▸ 🧩 AI 스킬 ▸ 스킬 가져오기)"
        fi
    fi
    # 바뀐 경우에만 기록 (셸을 열 때마다 파일을 쓰지 않게)
    if [ "$(cat "$_AS_CONFLICT_STAMP" 2>/dev/null)" != "$_sig" ] && mkdir -p "$_AS_STATE_DIR" 2>/dev/null; then
        printf '%s' "$_sig" >"$_AS_CONFLICT_STAMP" 2>/dev/null || true
    fi
    return 0
}

# ── 가져오기 후보 ─────────────────────────────────────────────────────────────
# 에이전트 폴더에 "실제 폴더"로 있는 스킬(링크 아님) 중 저장소에 없는 것. 출력: 이름<TAB>경로
#   ● Orca 내장 스킬(orca-cli 등)은 Orca 가 업데이트를 관리하므로 뺍니다(orca skills list 로 이름 확인).
#   ● ~/.claude/skills/synced 처럼 SKILL.md 가 없는 폴더(Claude 계정 동기화 묶음)는 자연히 빠집니다.
_orca_bundled_names() {
    local _orca="$_AS_REPO/modules/orca/orca"
    [ -x "$_orca" ] && command -v setsid >/dev/null 2>&1 || return 0
    setsid -w timeout -k 3 20 "$_orca" skills list --json </dev/null 2>/dev/null |
        python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit()
for t in d.get("topics", d.get("result", {}).get("topics", [])) or []:
    print(t.get("name", ""))' 2>/dev/null
}

_import_candidates() {
    local _agent _dir _d _name _orca_names
    _orca_names=" $(_orca_bundled_names | tr '\n' ' ') "
    declare -A _seen=()
    for _agent in "${AGENTS[@]}"; do
        _dir=$(_agent_dir "$_agent")
        for _d in "$_dir"/*/; do
            _d="${_d%/}"
            [ -L "$_d" ] && continue
            [ -f "$_d/SKILL.md" ] || continue
            _name=$(basename "$_d")
            [ -e "$REPO_SKILLS/$_name" ] && continue
            [[ "$_orca_names" == *" $_name "* ]] && continue
            [ -n "${_seen[$_d]+x}" ] && continue
            _seen[$_d]=1
            printf '%s\t%s\n' "$_name" "$_d"
        done
    done
}

# ── status ───────────────────────────────────────────────────────────────────
cmd_status() {
    _load_targets
    local _skills _agent _dir _skill _link _mark
    mapfile -t _skills < <(_repo_skills)
    echo "🧩 에이전트 스킬 (저장소: ${REPO_SKILLS/#$HOME/\~})"
    echo "─────────────────────────────────────────"
    if [ "${#_skills[@]}" -eq 0 ]; then
        echo "  저장소에 스킬이 아직 없습니다. 스킬 폴더(<이름>/SKILL.md)를 만들거나 '스킬 가져오기'를 쓰세요."
    fi
    for _agent in "${AGENTS[@]}"; do
        _dir=$(_agent_dir "$_agent")
        if ! _agent_installed "$_agent"; then
            echo "  ➖ $(_agent_label "$_agent") — 설치되지 않음 (설치하면 셸을 열 때 자동 연결)"
            continue
        fi
        echo "  🤖 $(_agent_label "$_agent") — ${_dir/#$HOME/\~}"
        for _skill in "${_skills[@]}"; do
            _link="$_dir/$_skill"
            if ! _skill_allowed "$_skill" "$_agent"; then
                _mark="➖ targets.conf 에서 뺌"
            elif [ -L "$_link" ] && [ "$(readlink "$_link")" = "$REPO_SKILLS/$_skill" ]; then
                _mark="✅ 연결됨"
            elif [ -e "$_link" ] || [ -L "$_link" ]; then
                _mark="⚠️  같은 이름의 다른 스킬이 있음"
            else
                _mark="⏳ 아직 연결 안 됨 (다시 연결하면 연결)"
            fi
            printf '     %-28s %s\n' "$_skill" "$_mark"
        done
    done
    local _cand
    _cand=$(_import_candidates)
    echo "─────────────────────────────────────────"
    if [ -n "$_cand" ]; then
        echo "📥 저장소로 가져올 수 있는 스킬 (에이전트 폴더에만 있음):"
        printf '%s\n' "$_cand" | awk -F'\t' -v h="$HOME" '{ p = $2; sub("^" h, "~", p); printf "     %-28s %s\n", $1, p }'
    else
        echo "📥 저장소로 가져올 스킬 없음"
    fi
}

# ── import ───────────────────────────────────────────────────────────────────
# 에이전트 폴더의 스킬을 저장소로 옮기고, 원래 자리는 저장소를 가리키는 링크로 바꿉니다.
#   ● 원본 폴더는 지우지 않고 ~/.devtools2/skill-backups/ 로 옮겨 둡니다(되돌리기용).
#   ● 원래 자리에 링크를 두는 이유: Orca 는 ~/.agents/skills 에 실제 파일을 두고 다른 에이전트 폴더에서 그곳으로
#     링크하므로, 원래 자리가 사라지면 그 링크들이 끊어집니다. 이후 sync 가 에이전트별 링크를 저장소로 바로 연결합니다.
#   ● Orca 공유 링크로 받은 스킬: Orca 는 직접 바뀐 설치본(여기서는 링크로 바뀐 것)을 업데이트에서 건너뛰므로
#     (orca skills install --help: "Only copies Orca wrote and nobody changed are updated") 저장소 파일을 덮어쓰지 않습니다.
#   ● 저장소는 공개 저장소입니다(설치 스크립트를 raw.githubusercontent.com 에서 받는 구조). 다른 사람의 스킬은
#     만든 사람의 허락·라이선스를 확인하고, 스킬 안의 스크립트·명령을 확인한 뒤 커밋하도록 안내합니다.
#   ● 텍스트 파일의 UTF-8 BOM 은 저장소 원칙(UTF-8 NoBOM)에 맞춰 지웁니다.
_load_common() {
    command -v prompt_confirm >/dev/null 2>&1 && return 0
    local _c="$_AS_REPO/scripts/linux/dev-env/_common.sh"
    if [ -f "$_c" ]; then
        if [ -z "${DT2_TMP:-}" ]; then
            DT2_TMP="${HOME:-/tmp}/.devtools2/tmp"
            (umask 077; mkdir -p "$DT2_TMP") 2>/dev/null || DT2_TMP=""
        fi
        # shellcheck disable=SC1090
        source "$_c"
    fi
    if ! command -v prompt_confirm >/dev/null 2>&1; then
        # _common.sh 없이 단독 실행할 때의 최소 질문 함수
        prompt_confirm() {
            local _a=""
            read -r -p "$1 [${2:-N}]: " _a </dev/tty || true
            _a="${_a:-${2:-N}}"
            [[ "$_a" =~ ^[Yy] ]]
        }
    fi
}

_import_one() {
    local _name="$1" _src="$2" _dst="$REPO_SKILLS/$1" _files _scripts _bak _f
    echo ""
    echo "📦 $_name  (${_src/#$HOME/\~})"
    sed -n '1,/^---$/{/^name:\|^description:/p}' "$_src/SKILL.md" 2>/dev/null | sed -n '1,4p' | cut -c1-200 | sed 's/^/   /'
    _files=$(cd "$_src" && find . -type f | sed 's|^\./||' | sort)
    echo "   파일 $(printf '%s\n' "$_files" | grep -c .)개: $(printf '%s\n' "$_files" | head -n 8 | tr '\n' ' ')"
    _scripts=$(cd "$_src" && find . -type f \( -name '*.sh' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.ps1' -o -perm -u+x \) | sed 's|^\./||')
    if [ -n "$_scripts" ]; then
        echo "   ⚠️  에이전트가 실행할 수 있는 스크립트가 들어 있습니다 — 내용을 확인하세요: $(printf '%s\n' "$_scripts" | tr '\n' ' ')"
    fi
    prompt_confirm "📥 '$_name' 을(를) 저장소로 가져올까요?" "Y" || return 1
    mkdir -p "$REPO_SKILLS" || return 1
    if ! cp -a "$_src" "$_dst"; then
        echo "❌ 복사에 실패했습니다: $_dst"
        rm -rf "$_dst"
        return 1
    fi
    # UTF-8 BOM 제거 (텍스트 파일만 — NUL 바이트가 있으면 바이너리로 보고 건너뜀)
    while IFS= read -r -d '' _f; do
        grep -qP '\x00' "$_f" 2>/dev/null && continue
        if [ "$(head -c3 "$_f" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
            sed -i '1s/^\xEF\xBB\xBF//' "$_f"
        fi
    done < <(find "$_dst" -type f -print0)
    # 저장소 권한 원칙: 그룹 공유, others 접근 차단
    chmod -R g+rwX,o-rwx "$_dst" 2>/dev/null || true
    # 원본은 백업으로 옮기고 그 자리에 저장소 링크
    mkdir -p "$_AS_BACKUP_DIR" && chmod 700 "$_AS_BACKUP_DIR" 2>/dev/null
    _bak="$_AS_BACKUP_DIR/${_name}-$(date +%Y%m%d-%H%M%S)"
    if mv "$_src" "$_bak"; then
        ln -s "$_dst" "$_src"
        echo "✅ 가져왔습니다: ${_dst/#$HOME/\~}  (원본 백업: ${_bak/#$HOME/\~})"
    else
        echo "⚠️  원본을 백업 폴더로 옮기지 못해 그대로 두었습니다 (저장소에는 복사됨): $_src"
    fi
    _IMPORTED+=("$_name")
}

cmd_import() {
    _load_common
    local _cand _sel _line _name _path
    echo "🔍 가져올 수 있는 스킬 찾는 중... (에이전트 폴더에만 있고 저장소에 없는 스킬)"
    _cand=$(_import_candidates)
    if [ -z "$_cand" ]; then
        echo "ℹ️  가져올 스킬이 없습니다. (Orca 공유 링크로 받을 때는 Orca 앱에서 '이 컴퓨터 · 전역'으로 설치한 뒤 다시 실행하세요)"
        return 0
    fi
    if command -v fzf >/dev/null 2>&1; then
        _sel=$(printf '%s\n' "$_cand" | fzf --multi --delimiter=$'\t' --with-nth=1,2 \
            --prompt="📥 가져올 스킬 (Tab: 여러 개) > " --header="Esc: 취소 · 오른쪽: SKILL.md 미리보기" \
            --preview='sed -n "1,60p" {2}/SKILL.md' --preview-window=right:55%:wrap --height=70% --reverse) || true
    else
        _sel="$_cand"
    fi
    [ -z "$_sel" ] && return 0
    echo ""
    echo "⚠️  DevTools2 저장소는 공개 저장소입니다. 푸시하면 누구나 볼 수 있습니다."
    echo "   다른 사람이 만든 스킬은 만든 사람의 허락·라이선스를 확인하고 올려 주세요."
    _IMPORTED=()
    while IFS=$'\t' read -r _name _path; do
        [ -n "$_name" ] && _import_one "$_name" "$_path"
    done <<<"$_sel"
    [ "${#_IMPORTED[@]}" -eq 0 ] && return 0

    echo ""
    _load_targets
    _do_sync true
    echo ""
    if ! git -C "$_AS_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "ℹ️  $_AS_REPO 가 Git 저장소가 아니라 커밋은 건너뜁니다."
        return 0
    fi
    local _paths=()
    for _name in "${_IMPORTED[@]}"; do _paths+=(".config/agents/skills/$_name"); done
    git -C "$_AS_REPO" status --short -- "${_paths[@]}" | sed 's/^/   /'
    if prompt_confirm "💾 저장소에 커밋할까요? (${_IMPORTED[*]})" "Y"; then
        git -C "$_AS_REPO" add -- "${_paths[@]}" &&
            git -C "$_AS_REPO" commit -q -m "feat(skills): 에이전트 스킬 가져오기 — ${_IMPORTED[*]}" -- "${_paths[@]}" &&
            echo "✅ 커밋했습니다: $(git -C "$_AS_REPO" log --oneline -1)"
        # 푸시는 공개 저장소에 올라가는 되돌리기 어려운 작업이라 기본값을 N 으로 둡니다
        if prompt_confirm "🚀 원격 저장소로 푸시할까요? (공개 — 다른 PC 는 git pull 로 받음)" "N"; then
            git -C "$_AS_REPO" push && echo "✅ 푸시했습니다."
        else
            echo "ℹ️  나중에 푸시하려면: git -C $_AS_REPO push"
        fi
    else
        echo "ℹ️  저장소에 복사만 해 두었습니다. 커밋은 직접 해 주세요."
    fi
}

case "${1:-}" in
sync) shift; cmd_sync "$@" ;;
status) cmd_status ;;
import) cmd_import ;;
*)
    echo "사용법: $(basename "$0") sync [--quiet] | status | import"
    exit 1
    ;;
esac
