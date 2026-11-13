# shellcheck shell=bash
# ==============================================================================
# [명령 팔레트] 🔤 변환 — Base64 인코딩 · 복원
# ==============================================================================
# command-palette 가 source 로 불러오는 파일입니다(단독 실행 X). 구조 설명은 command-palette 의
# "그룹 파일 불러오기" 주석을 보세요. 이 파일 = 1단계 메뉴 그룹 "🔤 변환" (그룹 ID: convert)

_MENU_CONVERT=(
    "base64_encode	파일 → 텍스트 인코딩 (클립보드 복사)"
    "base64_decode	텍스트 → 파일 복원 (클립보드 붙여넣기)"
)


# ── 1단계 메뉴 등록 · 2단계 선택 ─────────────────────────────────────────────
cp_register_group convert "🔤 변환 ▸ Base64 인코딩 · 복원"
cp_group_convert() {
    CHOICE_ID=$(_pick_leaf "🔤 변환 > " "${_MENU_CONVERT[@]}")
}

# ── [Base64] 파일 → 텍스트 인코딩 ────────────────────────────────────────────
# Bitwarden 등에 파일 자체를 첨부할 수 없는 경우(무료 플랜) 파일을 Base64 문자열로
# 바꿔 텍스트로 보관하기 위한 범용 유틸리티입니다.
# 복원은 아래 "텍스트 → 파일 복원" 메뉴가 담당합니다.
cp_run_base64_encode() {
    prompt_text _B64_SRC "📄 인코딩할 파일 경로 입력 (상대/절대 경로)"
    if [ -z "$_B64_SRC" ]; then
        echo "❌ 경로가 입력되지 않았습니다."
        exit 1
    fi

    # ~ 확장 (read는 자동으로 tilde expansion을 하지 않음)
    _B64_SRC="${_B64_SRC/#\~/$HOME_DIR}"
    # 상대경로면 현재 작업 디렉토리(CWD) 기준으로 절대경로화
    if [[ "$_B64_SRC" != /* ]]; then
        _B64_SRC="$CWD/$_B64_SRC"
    fi

    if [ ! -f "$_B64_SRC" ]; then
        echo "❌ 파일을 찾을 수 없습니다: $_B64_SRC"
        exit 1
    fi

    _B64_OUT=$(base64 "$_B64_SRC" | tr -d '\n')
    _B64_SIZE=$(wc -c <"$_B64_SRC" | tr -d ' ')

    echo ""
    if printf '%s' "$_B64_OUT" | cp_copy_stdin_to_clipboard; then
        echo "✅ Base64로 인코딩하여 클립보드에 복사했습니다."
        echo "   원본 파일 : $_B64_SRC (${_B64_SIZE} bytes)"
        echo "   Bitwarden 항목의 '사용자 지정 필드' 값에 그대로 붙여넣으세요."
    else
        echo "⚠️  사용 가능한 클립보드 도구를 찾지 못해 아래에 직접 출력합니다."
        echo "   (clip.exe / wl-copy / xclip / xsel 중 하나가 필요합니다)"
        echo ""
        echo "$_B64_OUT"
    fi
    if [ "$_B64_SIZE" -gt 102400 ]; then
        echo ""
        echo "⚠️  파일이 다소 큽니다(${_B64_SIZE} bytes). Bitwarden 사용자 지정 필드에"
        echo "   저장/동기화가 원활하지 않을 수 있으니 저장 후 정상 동작을 확인해주세요."
    fi
}

# ── [Base64] 텍스트 → 파일 복원 ──────────────────────────────────────────────
cp_run_base64_decode() {
    prompt_text _B64_DST "📁 복원할 파일 경로 입력 (상대/절대 경로, 필수)"
    if [ -z "$_B64_DST" ]; then
        echo "❌ 경로가 입력되지 않았습니다."
        exit 1
    fi

    _B64_DST="${_B64_DST/#\~/$HOME_DIR}"
    if [[ "$_B64_DST" != /* ]]; then
        _B64_DST="$CWD/$_B64_DST"
    fi

    if [ -f "$_B64_DST" ]; then
        if ! prompt_confirm "⚠️  이미 파일이 존재합니다. 덮어쓰시겠습니까? ($_B64_DST)" "N"; then
            echo "❌ 취소되었습니다."
            exit 0
        fi
    fi

    _B64_IN=$(paste_from_clipboard)
    if [ $? -ne 0 ]; then
        echo "⚠️  사용 가능한 클립보드 도구를 찾지 못했습니다 (powershell.exe/wl-paste/xclip/xsel)."
        prompt_text _B64_IN "📋 Base64 문자열을 직접 붙여넣어주세요"
        if [ -z "$_B64_IN" ]; then
            echo "❌ Base64 문자열이 입력되지 않았습니다."
            exit 1
        fi
    elif [ -z "$_B64_IN" ]; then
        echo "❌ 클립보드가 비어있습니다. Bitwarden에서 Base64 값을 먼저 복사해주세요."
        exit 1
    else
        echo "ℹ️  클립보드에서 Base64 값을 읽었습니다. (길이: ${#_B64_IN}자)"
    fi

    mkdir -p "$(dirname "$_B64_DST")"

    # 같은 폴더의 임시 파일에 먼저 디코딩하고, 성공했을 때만 대상 파일과 교체합니다.
    # (대상에 바로 쓰고 실패 시 지우면, 덮어쓰기에 동의한 기존 파일까지 사라짐)
    _B64_TMP=$(mktemp "$(dirname "$_B64_DST")/.b64restore.XXXXXX")
    _B64_DECODE_OK=false
    if printf '%s' "$_B64_IN" | base64 -d >"$_B64_TMP" 2>/dev/null; then
        _B64_DECODE_OK=true
    fi

    if $_B64_DECODE_OK && mv -f "$_B64_TMP" "$_B64_DST"; then
        _B64_OUT_SIZE=$(wc -c <"$_B64_DST" | tr -d ' ')
        echo "✅ 파일을 복원했습니다: $_B64_DST (${_B64_OUT_SIZE} bytes)"
    else
        echo "❌ Base64 디코딩에 실패했습니다. 클립보드/입력 값이 올바른 Base64인지 확인해주세요. (기존 파일은 그대로 둡니다)"
        rm -f "$_B64_TMP"
        exit 1
    fi
}
