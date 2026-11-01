# shellcheck shell=bash
# ==============================================================================
# [명령 팔레트] 🖥️ 시스템 — 포트 · 프로세스 확인과 종료, 메모리 현황
# ==============================================================================
# command-palette 가 source 로 불러오는 파일입니다(단독 실행 X). 구조 설명은 command-palette 의
# "그룹 파일 불러오기" 주석을 보세요. 이 파일 = 1단계 메뉴 그룹 "🖥️ 시스템" (그룹 ID: system)

_MENU_SYSTEM=(
    "port_check	포트 확인 (Port Check)"
    "proc_check	프로세스 확인 (Process Check)"
    "proc_kill	프로세스 종료 (Process Kill)"
    "port_kill	포트로 프로세스 종료 (Port Kill)"
    "mem_status	메모리 사용 현황 (Memory · 많이 쓰는 프로세스)"
)

# ── 1단계 메뉴 등록 · 2단계 선택 ─────────────────────────────────────────────
cp_register_group system "🖥️ 시스템 ▸ 포트 · 프로세스 · 종료 · 메모리"
cp_group_system() {
    CHOICE_ID=$(_pick_leaf "🖥️ 시스템 > " "${_MENU_SYSTEM[@]}")
}

# ── 포트 확인 (Port Check) ───────────────────────────────────────────────────
cp_run_port_check() {
    prompt_text PORT "🔍 조회할 포트 번호 입력"
    if [[ -n "$PORT" ]]; then
        echo "📋 포트 $PORT 상태 및 프로세스 정보:"
        echo "─────────────────────────────────────────"
        if ! is_port_in_use "$PORT"; then
            echo "  (해당 포트를 사용하는 프로세스 없음)"
        else
            if $IS_MAC; then
                # macOS: lsof -i :PORT
                lsof -i :"$PORT" 2>/dev/null || echo "  (포트 $PORT 점유 중)"
            else
                # Linux / WSL2: 안전한 소켓 상태 + Java/Gradle 프로세스 정보 표시
                echo "  ✅ 포트 $PORT 가 활성화(LISTEN) 상태입니다."
                echo ""
                echo "  [관련 실행 중 프로세스 목록]"
                ps aux 2>/dev/null | grep -iE 'java|bootRun|gradle' | grep -v grep | head -5 | awk '{print "  PID: "$2"  |  명령어: "$11" "$12" "$13" "$14}'
            fi
        fi
        echo "─────────────────────────────────────────"
    fi
}

# ── 프로세스 확인 (Process Check) ────────────────────────────────────────────
cp_run_proc_check() {
    prompt_text KWD "🎯 검색할 프로세스 이름 키워드"
    if [[ -n "$KWD" ]]; then
        echo "📋 '$KWD' 관련 프로세스 목록:"
        echo "─────────────────────────────────────────"
        # Linux / macOS / WSL 공통: ps aux
        ps aux | grep -i "$KWD" | grep -v grep
        echo "─────────────────────────────────────────"
    fi
}

# ── 프로세스 종료 (Process Kill) ─────────────────────────────────────────────
cp_run_proc_kill() {
    # 다중 PID를 공백으로 구분하여 한 번에 종료 가능
    prompt_text PID_INPUT "💀 종료할 프로세스 PID 입력 (여러 개면 공백으로 구분, 예: 1234 5678)"
    if [[ -n "$PID_INPUT" ]]; then
        read -r -a PID_ARRAY <<<"$PID_INPUT"
        echo ""
        kill_pids "${PID_ARRAY[*]}"
    fi
}

# ── 포트로 프로세스 종료 (Port Kill) ─────────────────────────────────────────
cp_run_port_kill() {
    prompt_text PORT "🔌 종료할 포트 번호 입력"
    if [[ -z "$PORT" ]]; then
        echo "❌ 포트 번호를 입력하세요."
        exit 1
    fi

    if ! is_port_in_use "$PORT"; then
        echo "ℹ️  포트 $PORT 를 사용하는 프로세스가 없습니다."
        exit 0
    fi

    echo "📋 포트 $PORT 점유 프로세스 확인:"
    echo "─────────────────────────────────────────"
    target_pids=$(get_pids_by_port "$PORT")
    if [[ -n "$target_pids" ]]; then
        print_pids_info "$target_pids"
    else
        echo "  ⚠️ 포트 $PORT 가 현재 활성화(LISTEN)되어 있습니다."
    fi
    echo "─────────────────────────────────────────"
    echo ""
    if ! prompt_confirm "⚠️  위 포트 $PORT 점유 프로세스를 종료하시겠습니까?" "N"; then
        echo "❌ 취소되었습니다."
        exit 0
    fi

    echo ""
    echo "🔪 포트 $PORT 점유 프로세스 해제 중..."
    if [[ -n "$target_pids" ]]; then
        kill_pids "$target_pids"
    else
        # get_pids_by_port 로 PID를 직접 특정하지 못한 경우의 폴백
        if $IS_MAC; then
            mac_pids=$(lsof -nP -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null)
            [[ -n "$mac_pids" ]] && kill_pids "$mac_pids"
        elif command -v fuser &>/dev/null; then
            fuser -k -9 "$PORT/tcp" &>/dev/null || true
        fi
    fi

    sleep 0.5
    verify_port_released "$PORT" 3
}

# ── 메모리 사용 현황 (Memory) ─────────────────────────────────────────────────
# PC 가 느려지거나 멈출 때 무엇이 메모리를 쓰는지 한눈에 보기 위한 항목입니다.
#   ● 전체: Linux·WSL 은 free, macOS 는 top 의 PhysMem. WSL 의 전체 메모리는 .wslconfig 의 memory 상한입니다.
#   ● 개발 도구별: 이 사용자의 프로세스를 jdtls·Gradle 데몬·VS Code 서버 등으로 묶어 RSS 를 합칩니다
#     (RSS 합계라 여러 프로세스가 함께 쓰는 메모리는 중복으로 더해질 수 있어 대략적인 값입니다).
#   ● ps 출력을 먼저 변수에 받아 두고 나서 awk 로 묶습니다(awk 자신의 명령줄이 패턴에 걸리지 않게).
cp_run_mem_status() {
    echo "🧠 메모리 사용 현황"
    echo "─────────────────────────────────────────"
    if $IS_MAC; then
        top -l 1 -s 0 2>/dev/null | grep -E '^PhysMem' | sed 's/^/  /'
    else
        free -h 2>/dev/null | sed 's/^/  /'
        if $IS_WSL; then
            echo "  ℹ️  WSL 전체(total) = .wslconfig 의 memory 상한(없으면 PC 메모리의 절반). 남는 캐시는 WSL 이 Windows 로 차츰 돌려줍니다."
        fi
    fi
    _MEM_PS=$(ps -u "$(id -u)" -o pid=,rss=,args= 2>/dev/null)
    echo ""
    echo "📦 개발 도구별 사용량 (이 사용자의 프로세스, 대략)"
    printf '%s\n' "$_MEM_PS" | awk '{
        rss = $2; k = ""
        if ($0 ~ /org\.eclipse\.jdt\.ls|jdtls/) k = "☕ Java 언어 서버 (jdtls)"
        else if ($0 ~ /GradleDaemon/) k = "🐘 Gradle 데몬"
        else if ($0 ~ /KotlinCompileDaemon/) k = "🐘 Kotlin 컴파일 데몬"
        else if ($0 ~ /\.vscode-server/) k = "🧩 VS Code 서버 (확장 포함)"
        else if ($0 ~ /zed-remote-server|zed_remote_server/) k = "⚡ Zed 원격 서버"
        else if ($0 ~ /orca-linux|\/orca\/orca/) k = "🐋 Orca"
        else if ($0 ~ /(^|[ \/])nvim( |$)/) k = "📝 Neovim"
        else if ($0 ~ /(^|[ \/])java( |$)/) k = "☕ 기타 Java (앱 실행 등)"
        else if ($0 ~ /(^|[ \/])node( |$)/) k = "🟩 기타 Node.js"
        if (k == "") next
        s[k] += rss; n[k]++
    } END {
        for (k in s) printf "%d\t%s\t%d\n", s[k] / 1024, k, n[k]
    }' | sort -t$'\t' -k1,1nr | awk -F'\t' '{ printf "  %6d MB  %s (%d개)\n", $1, $2, $3; f = 1 } END { if (!f) print "  (해당 프로세스 없음)" }'
    echo ""
    echo "🔝 메모리를 많이 쓰는 프로세스 10개"
    printf '%s\n' "$_MEM_PS" | sort -k2,2nr | head -n 10 | awk '{
        pid = $1; mb = $2 / 1024; $1 = ""; $2 = ""; sub(/^ +/, "")
        printf "  PID %-8s %6d MB  %s\n", pid, mb, substr($0, 1, 90)
    }'
    echo "─────────────────────────────────────────"
    echo "💡 Gradle 데몬 정리: Gradle 프로젝트에서 Alt+C ▸ 🐘 Gradle ▸ 🧹 Gradle 데몬 · 종료: 🖥️ 시스템 ▸ 프로세스 종료"
    $IS_WSL && echo "💡 WSL 이 잡은 메모리를 한 번에 돌려받으려면 Windows 에서: wsl --shutdown (WSL 창이 모두 닫힘)"
}
