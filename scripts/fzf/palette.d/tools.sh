# shellcheck shell=bash
# ==============================================================================
# [명령 팔레트] 🧰 외부 도구 — 탐색기 · VS Code · Zed 로 현재 폴더 열기 (설치된 것만)
# ==============================================================================
# command-palette 가 source 로 불러오는 파일입니다(단독 실행 X). 구조 설명은 command-palette 의
# "그룹 파일 불러오기" 주석을 보세요. 이 파일 = 1단계 메뉴 그룹 "🧰 외부 도구" (그룹 ID: tools)

# Zed CLI 이름: 공식 설치 스크립트·WSL(Windows Zed) 은 zed, 일부 배포판 패키지는 zeditor
_ZED_CMD=""
if command -v zed >/dev/null 2>&1; then _ZED_CMD="zed"; elif command -v zeditor >/dev/null 2>&1; then _ZED_CMD="zeditor"; fi

# 외부 도구 — 설치된 도구만 (파일 관리자: WSL 은 항상, Linux 는 데스크톱 환경 + xdg-open 이 있을 때)
#   1단계 그룹 문구도 실제로 있는 항목 이름만 이어 붙여 만듭니다(_TOOLS_KW — 예: "탐색기 · VS Code · Zed").
_MENU_TOOLS=()
_TOOLS_KW=()
if $IS_WSL; then
    command -v explorer.exe >/dev/null 2>&1 && _MENU_TOOLS+=("open_explorer	Windows 탐색기로 현재 폴더 열기") && _TOOLS_KW+=("탐색기")
elif $_HAS_DESKTOP && command -v xdg-open >/dev/null 2>&1; then
    _MENU_TOOLS+=("open_explorer	파일 관리자로 현재 폴더 열기") && _TOOLS_KW+=("파일 관리자")
fi
command -v code >/dev/null 2>&1 && _MENU_TOOLS+=("open_vscode	VS Code 로 현재 폴더 열기") && _TOOLS_KW+=("VS Code")
[ -n "$_ZED_CMD" ] && _MENU_TOOLS+=("open_zed	Zed 로 현재 폴더 열기") && _TOOLS_KW+=("Zed")


# ── 1단계 메뉴 등록 · 2단계 선택 ─────────────────────────────────────────────
[ "${#_MENU_TOOLS[@]}" -gt 0 ] && cp_register_group tools "🧰 외부 도구 ▸ $(_cp_join_kw "${_TOOLS_KW[@]}")"
cp_group_tools() {
    CHOICE_ID=$(_pick_leaf "🧰 외부 도구 > " "${_MENU_TOOLS[@]}")
}

# ── [외부 도구] 파일 관리자 (WSL: Windows 탐색기 · Linux: xdg-open) ──────────
cp_run_open_explorer() {
    if $IS_WSL; then
        # explorer.exe 는 성공해도 종료 코드 1 을 돌려주므로 결과를 보지 않습니다. 현재 폴더(.)를 넘겨야
        # \\wsl.localhost\<배포판>\... 경로로 열립니다(리눅스 절대 경로를 넘기면 Windows 경로로 해석됨).
        (cd "$CWD" && explorer.exe . >/dev/null 2>&1) || true
    else
        _cp_detach xdg-open "$CWD"
    fi
    echo "📂 현재 폴더를 열었습니다: $CWD"
}

# ── [외부 도구] VS Code ───────────────────────────────────────────────────────────
# WSL 에서는 Windows VS Code 의 code 명령이 WSL 원격 모드로 엽니다(필요하면 VS Code Server 를 자동 설치).
cp_run_open_vscode() {
    code "$CWD"
    echo "🧩 VS Code 로 열었습니다: $CWD"
}

# ── [외부 도구] Zed ──────────────────────────────────────────────────────────────
# WSL 의 zed 는 Windows Zed 가 넣어 준 스크립트로, WSL 을 감지해 zed.exe --wsl 사용자@배포판 으로 원격 열기를 합니다.
# Zed 가 아직 안 떠 있으면 그 명령이 Zed 가 닫힐 때까지 끝나지 않으므로 팔레트와 떼어 놓고 실행합니다.
cp_run_open_zed() {
    _cp_detach "$_ZED_CMD" "$CWD"
    echo "⚡ Zed 로 열었습니다: $CWD"
}
