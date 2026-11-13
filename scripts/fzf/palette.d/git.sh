# shellcheck shell=bash
# ==============================================================================
# [명령 팔레트] 🌿 Git · 프로젝트 — lazygit · 브랜치 · PR · Clone · 프로젝트 설정
# ==============================================================================
# command-palette 가 source 로 불러오는 파일입니다(단독 실행 X). 구조 설명은 command-palette 의
# "그룹 파일 불러오기" 주석을 보세요. 이 파일 = 1단계 메뉴 그룹 "🌿 Git · 프로젝트" (그룹 ID: git)

# Git · 프로젝트 — lazygit·브랜치·PR 은 Git 저장소 안에서만, PR 은 gh 가 있을 때만
# 1단계 키워드(_GIT_KW)는 실제로 보이는 항목에서 만든다 — 저장소 밖에서 열면 lazygit·브랜치·PR 이 빠짐(AI·외부 도구 그룹과 같은 방식)
_MENU_GIT=()
_GIT_KW=()
if [ -n "$_GIT_ROOT" ]; then
    command -v lazygit >/dev/null 2>&1 && _MENU_GIT+=("git_lazygit	lazygit 열기 (커밋 · 스테이징 · 로그 화면)") && _GIT_KW+=("lazygit")
    _MENU_GIT+=("git_branch	브랜치 전환 · 새 브랜치 (로컬 · 원격)") && _GIT_KW+=("브랜치")
    command -v gh >/dev/null 2>&1 && _MENU_GIT+=("git_pr_checkout	PR 체크아웃 (GitHub Pull Request 받아서 전환)") && _GIT_KW+=("PR")
fi
_MENU_GIT+=(
    "git_clone	Git Clone (Bitwarden 인증 자동)"
    "project_setup	프로젝트 설정 (Git Clone & 초기화)"
)
_GIT_KW+=("Clone" "프로젝트 설정")


# ── 1단계 메뉴 등록 · 2단계 선택 ─────────────────────────────────────────────
cp_register_group git "🌿 Git · 프로젝트 ▸ $(_cp_join_kw "${_GIT_KW[@]}")"
cp_group_git() {
    CHOICE_ID=$(_pick_leaf "🌿 Git · 프로젝트 > " "${_MENU_GIT[@]}")
}

# ── [Project] 프로젝트 설정 (setup-projects/ 하위 스크립트 동적 탐색 실행) ────
# scripts/linux/setup-projects/ 아래(단, _common/ 제외) .sh 스크립트를 재귀적으로
# 찾아 목록으로 보여주고, 선택한 스크립트를 그대로 실행합니다. 프로젝트가 늘어나서
# s2/ 처럼 하위 디렉토리로 나뉘어도(1단계든 그 이상이든) 자동으로 인식됩니다.
cp_run_project_setup() {
    if [ -n "${DEVTOOLS2:-}" ]; then
        _SP_DIR="${DEVTOOLS2}/scripts/linux/setup-projects"
    else
        _SP_DIR="$(cd "$_CP_SCRIPT_DIR/../linux/setup-projects" && pwd)"
    fi

    if [ ! -d "$_SP_DIR" ]; then
        echo "❌ setup-projects 디렉토리를 찾을 수 없습니다: $_SP_DIR"
        exit 1
    fi

    _SP_SCRIPTS=()
    while IFS= read -r -d '' _f; do
        _SP_SCRIPTS+=("$_f")
    done < <(find "$_SP_DIR" -type f -name "*.sh" -not -path "*/_common/*" -print0 | sort -z)

    if [ ${#_SP_SCRIPTS[@]} -eq 0 ]; then
        echo "ℹ️  실행 가능한 프로젝트 설정 스크립트를 찾지 못했습니다: $_SP_DIR"
        exit 0
    fi

    # 표시용 라벨: setup-<이름>.sh → <이름>  (하위 폴더에 있으면 상대경로도 같이 표시)
    _SP_LABELS=()
    for _f in "${_SP_SCRIPTS[@]}"; do
        _rel="${_f#$_SP_DIR/}"
        _base="$(basename "$_f")"
        _name="${_base#setup-}"
        _name="${_name%.sh}"
        _SP_LABELS+=("${_name}  (${_rel})")
    done

    _SP_CHOICE=$(printf "%s\n" "${_SP_LABELS[@]}" | fzf --prompt="📦 설정할 프로젝트 선택 > " --height=40% --reverse)
    if [ -z "$_SP_CHOICE" ]; then
        exit 0
    fi

    _SP_TARGET=""
    for _i in "${!_SP_LABELS[@]}"; do
        if [ "${_SP_LABELS[$_i]}" = "$_SP_CHOICE" ]; then
            _SP_TARGET="${_SP_SCRIPTS[$_i]}"
            break
        fi
    done

    if [ -z "$_SP_TARGET" ]; then
        echo "❌ 선택한 스크립트를 찾을 수 없습니다."
        exit 1
    fi

    echo ""
    echo "🚀 실행: $_SP_TARGET"
    echo ""
    normalize_tty
    if bash "$_SP_TARGET"; then
        echo ""
        echo "✅ 프로젝트 설정 스크립트 실행 완료"
    else
        _SP_RC=$?
        echo ""
        echo "❌ 프로젝트 설정 스크립트가 오류로 종료되었습니다 (종료 코드: $_SP_RC)"
    fi
}

# ── [Git] Clone (Bitwarden 인증 자동) ────────────────────────────────────────
cp_run_git_clone() {

    # ── 0. git 설치 여부 확인 ─────────────────────────────────────────────────
    if ! command -v git &>/dev/null; then
        echo "❌ git이 설치되어 있지 않습니다."
        echo ""
        echo "   설치 방법:"
        if [[ -f /etc/debian_version ]] || [[ -f /etc/ubuntu-release ]]; then
            echo "   sudo apt update && sudo apt install -y git"
        elif [[ -f /etc/redhat-release ]] || [[ -f /etc/fedora-release ]]; then
            echo "   sudo dnf install -y git"
        else
            echo "   패키지 매니저로 git 을 설치해주세요."
        fi
        exit 1
    fi

    # ── 1. bw-lib 로드 확인 ───────────────────────────────────────────────────
    if ! declare -f bw_ensure_session &>/dev/null; then
        echo "❌ bw-lib 라이브러리를 찾을 수 없습니다."
        echo "   ${_CP_SCRIPT_DIR}/bw-lib 파일이 존재하는지 확인해주세요."
        exit 1
    fi

    # ── 2. Bitwarden 세션 확보 ────────────────────────────────────────────────
    echo "⏳ Bitwarden 상태 확인 중..."
    bw_ensure_session || exit 1

    # ── 3. clone 할 URL 입력 ──────────────────────────────────────────────────
    prompt_text _CLONE_URL "📋 Clone 할 저장소 URL 입력 (예: https://github.com/user/repo.git)"
    if [ -z "$_CLONE_URL" ]; then
        echo "❌ URL이 입력되지 않았습니다. 취소합니다."
        exit 0
    fi

    # ── 4. clone 대상 디렉토리 입력 ──────────────────────────────────────────
    _DEFAULT_DIR=$(basename "$_CLONE_URL" .git)
    prompt_text _CLONE_DIR "📁 Clone 경로" "./$_DEFAULT_DIR"
    _CLONE_DIR=${_CLONE_DIR:-"./$_DEFAULT_DIR"}

    echo ""
    echo "🚀 git clone 시작합니다..."
    echo "   URL       : $_CLONE_URL"
    echo "   대상 경로 : $_CLONE_DIR"
    echo ""

    # ── 4-1/5. PAT 인증에 사용할 Bitwarden 'GitHub' 항목 이름 프롬프트 + clone ────────
    # 항목명 프롬프트 → 아이템 조회(이름 불일치/중복 시 에러 처리) → PAT(사용자
    # 지정 필드 "PAT") 인증 → git config 설정 → 자격 증명 저장까지 전부
    # bw-lib의 bw_git_clone_interactive(→ bw_git_clone)가 전담합니다.
    bw_git_clone_interactive "$_CLONE_URL" "$_CLONE_DIR" || exit 1
}

# ── [Git] lazygit 열기 ───────────────────────────────────────────────────────
# 터미널 Git 화면(lazygit)을 저장소 루트 기준으로 엽니다(하위 폴더에서 Alt+C 를 눌러도 같은 저장소).
cp_run_git_lazygit() {
    lazygit -p "$_GIT_ROOT"
    exit $?
}

# ── [Git] 브랜치 전환 · 새 브랜치 ─────────────────────────────────────────────
# 로컬 브랜치와 (로컬에 없는) 원격 브랜치를 최근 커밋 순으로 보여 주고, 고르면 git switch 합니다.
#   ● 원격 브랜치를 고르면 같은 이름의 로컬 브랜치를 만들어 추적합니다(git switch --track origin/x).
#   ● 고치던 내용(커밋 안 한 변경)은 git 이 그대로 들고 전환하고, 충돌하면 git 이 전환을 멈추고 알려 줍니다
#     (임의로 stash 하지 않습니다 — 필요하면 lazygit 의 stash 사용).
#   ● 원격 목록이 오래됐으면 "🔄 원격 브랜치 새로 받기"(git fetch --all --prune) 후 다시 고릅니다.
cp_run_git_branch() {
    while true; do
        _GB_CUR=$(git -C "$_GIT_ROOT" branch --show-current 2>/dev/null)
        _GB_LOCALS=$(git -C "$_GIT_ROOT" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' ')
        _GB_ITEMS=$(
            printf '%s\t%s\n' "@new" "➕ 새 브랜치 만들기 (현재 위치${_GB_CUR:+: $_GB_CUR}에서)"
            printf '%s\t%s\n' "@fetch" "🔄 원격 브랜치 새로 받기 (git fetch --all --prune)"
            git -C "$_GIT_ROOT" for-each-ref --sort=-committerdate \
                --format='%(refname)%09%(refname:short)%09%(committerdate:relative)%09%(subject)' refs/heads refs/remotes |
                awk -F'\t' -v cur="$_GB_CUR" -v locals="$_GB_LOCALS" '
                    BEGIN { n = split(locals, a, " "); for (i = 1; i <= n; i++) L[a[i]] = 1 }
                    $1 ~ /\/HEAD$/ { next }
                    $1 ~ /^refs\/heads\// {
                        printf "L:%s\t%s %-40s %s · %s\n", $2, ($2 == cur ? "●" : "🌿"), $2, $3, substr($4, 1, 60); next
                    }
                    { short = $2; sub(/^[^\/]+\//, "", short); if ((short in L) || seen[short]++) next
                      printf "R:%s\t☁️  %-40s %s · %s (원격)\n", $2, $2, $3, substr($4, 1, 60) }'
        )
        _GB_SEL=$(printf '%s\n' "$_GB_ITEMS" | fzf --delimiter=$'\t' --with-nth=2 --prompt="🌿 전환할 브랜치 (현재: ${_GB_CUR:-분리된 HEAD}) > " --header="Esc: 취소 · ● 현재 브랜치 · ☁️ 원격에만 있는 브랜치" --height=60% --reverse --no-sort) || true
        [ -z "$_GB_SEL" ] && exit 0
        _GB_ID="${_GB_SEL%%$'\t'*}"
        case "$_GB_ID" in
        @fetch)
            echo "▶️ 실행 명령어: git fetch --all --prune"
            git -C "$_GIT_ROOT" fetch --all --prune || echo "⚠️  fetch 에 실패했습니다. 네트워크·로그인 상태를 확인하세요."
            echo ""
            continue
            ;;
        @new)
            prompt_text _GB_NEW "➕ 새 브랜치 이름 (예: feature/login)"
            [ -z "$_GB_NEW" ] && exit 0
            if ! git check-ref-format --branch "$_GB_NEW" >/dev/null 2>&1; then
                echo "❌ 브랜치 이름으로 쓸 수 없습니다: $_GB_NEW"
                exit 1
            fi
            echo "▶️ 실행 명령어: git switch -c $_GB_NEW"
            git -C "$_GIT_ROOT" switch -c "$_GB_NEW"
            exit $?
            ;;
        L:*)
            _GB_NAME="${_GB_ID#L:}"
            if [ "$_GB_NAME" = "$_GB_CUR" ]; then
                echo "ℹ️  이미 현재 브랜치입니다: $_GB_NAME"
                exit 0
            fi
            echo "▶️ 실행 명령어: git switch $_GB_NAME"
            git -C "$_GIT_ROOT" switch "$_GB_NAME"
            exit $?
            ;;
        R:*)
            _GB_NAME="${_GB_ID#R:}"
            echo "▶️ 실행 명령어: git switch --track $_GB_NAME"
            git -C "$_GIT_ROOT" switch --track "$_GB_NAME"
            exit $?
            ;;
        esac
    done
}

# ── [Git] PR 체크아웃 (GitHub) ────────────────────────────────────────────────
# 리뷰하거나 이어서 작업할 PR 을 목록에서 골라 gh pr checkout 합니다(PR 브랜치를 받아 전환, 포크 PR 포함).
#   ● gh 로그인이 안 되어 있으면 Git Clone 과 같은 방식(Bitwarden 의 PAT)으로 로그인할지 묻습니다.
cp_run_git_pr_checkout() {
    if ! gh auth status >/dev/null 2>&1; then
        echo "⚠️  GitHub CLI(gh) 가 로그인되어 있지 않습니다."
        if declare -f bw_setup_github_auth >/dev/null 2>&1 && prompt_confirm "🔑 Bitwarden 에 저장된 PAT 로 로그인할까요?" "Y"; then
            bw_setup_github_auth || exit 1
        fi
        if ! gh auth status >/dev/null 2>&1; then
            echo "❌ gh 로그인 후 다시 시도하세요: gh auth login"
            exit 1
        fi
    fi
    echo "⏳ 열린 PR 목록 가져오는 중..."
    if ! _PR_LIST=$(cd "$_GIT_ROOT" && gh pr list --limit 100 --json number,title,headRefName,author,isDraft \
        --template '{{range .}}{{.number}}{{"\t"}}#{{.number}} {{if .isDraft}}[초안] {{end}}{{.title}} ({{.headRefName}} · {{.author.login}}){{"\n"}}{{end}}' 2>&1); then
        echo "❌ PR 목록을 가져오지 못했습니다:"
        printf '%s\n' "$_PR_LIST" | tail -n 5 | sed 's/^/   │ /'
        exit 1
    fi
    if [ -z "$_PR_LIST" ]; then
        echo "ℹ️  열린 PR 이 없습니다."
        exit 0
    fi
    _PR_SEL=$(printf '%s\n' "$_PR_LIST" | fzf --delimiter=$'\t' --with-nth=2 --prompt="🔀 체크아웃할 PR > " --header="Esc: 취소" --height=60% --reverse --no-sort) || true
    [ -z "$_PR_SEL" ] && exit 0
    _PR_NUM="${_PR_SEL%%$'\t'*}"
    echo "▶️ 실행 명령어: gh pr checkout $_PR_NUM"
    (cd "$_GIT_ROOT" && gh pr checkout "$_PR_NUM")
    exit $?
}
