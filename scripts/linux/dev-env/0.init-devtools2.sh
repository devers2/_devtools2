#!/usr/bin/env bash
# DevTools2 초기화 스크립트 (0.init-devtools2.sh)
# 사용법: sudo /path/to/0.init-devtools2.sh
#
# 목적:
# - 시스템 필수 패키지 설치 및 한글 로케일 설정
# - /var/opt/_devtools2 에 공개 저장소 클론 (공개 저장소이므로 별도 인증 불필요)
# - 운영 환경에서 여러 개발자가 DevTools2 디렉토리를 안전하게 공유할 수 있도록
#   그룹 소유권 및 퍼미션, SGID를 설정합니다.
#
# =====================================================================================
# 📦 [포터블 관련 메모: 이 저장소는 100% 포터블이 아닙니다 — 재검토 시 참고]
# =====================================================================================
# "$DEVTOOLS2 폴더만 다른 PC로 복사 + 최소 스크립트로 환경변수만 추가" 방식의 완전 포터블은
# 안 됩니다. 데이터 계층(Neovim 플러그인/Mason 도구/트리시터 컴파일 파서, Gradle 캐시,
# Maven 저장소)은 전부 $DEVTOOLS2/data/* 안에 물리적으로 존재하고 XDG 표준 위치로는
# 심볼릭 링크만 나가 있어(1.setup-env.sh의 _run_symlink 호출부 참고) 이미 포터블 구조지만,
# 아래 apt/dpkg 설치 항목들은 $DEVTOOLS2 밖(/usr/*, dpkg DB)에 설치되어 폴더 복사로는
# 절대 따라오지 않습니다.
#
# [이 스크립트가 까는 것] unzip, tar, curl, wget, rsync, python3-pip, locales, language-pack-ko
#   - unzip/tar/curl/wget: 포터블 도구를 내려받는 데 필요한 부트스트랩(닭과 달걀 문제)
#   - python3-pip: 3.install-cli-tools.sh의 hererocks 설치용
#   - locales/language-pack-ko: glibc 로케일 데이터 — OS 전역 설정이라 폴더 복사 개념 자체가 안 맞음
#
# [다른 스크립트가 까는 것 — 전체 그림]
#   - 3.install-cli-tools.sh: build-essential/libreadline-dev(컴파일러 — 아래 참고),
#     git, trash-cli, xclip, wl-clipboard, sqlite3, libsqlite3-dev
#   - 4.setup-keyboard.sh: keyd (커널 input 레벨 통합 — 개념상 포터블화 불가능)
#   - install_hangle.sh: fcitx5, fcitx5-hangul, im-config (디스플레이 서버 입력기 통합 — 개념상 불가능)
#
# [구조적으로 회피 불가능한 것] nvim-treesitter의 :TSInstall/:TSUpdate와 hererocks(Lua/Luarocks
# 빌드)는 시스템 C 컴파일러(gcc/make, build-essential)로 소스를 직접 컴파일합니다. 컴파일
# 결과물(.so)은 $DEVTOOLS2/data/nvim 안에 남아 폴더 복사로 같이 옮겨지긴 하지만, 아키텍처나
# glibc 버전이 크게 다른 PC로 옮기면 깨질 수 있어 "아무 PC에나" 수준의 포터블은 보장 안 됩니다.
#
# [WSL2 한정으로 줄일 수 있는 부분] xclip/wl-clipboard는 실제로 이 환경에서 안 씁니다 —
# options.lua의 클립보드 설정이 WSL에서는 win32yank(포터블)나 PowerShell clip.exe를 우선
# 쓰고, xclip/wl-clipboard는 네이티브 리눅스(비-WSL) 전용 폴백이라 WSL2 전용으로 좁히면
# 이 apt 의존성 2개는 빼도 됩니다.
#
# [현실적인 최소선] 목적지 PC에 "apt-get install build-essential git curl wget tar unzip
# locales language-pack-ko sqlite3 libsqlite3-dev" 한 줄만 한 번 실행해주면(이미 devtools2로
# 셋업된 WSL이면 이마저 불필요), 그 뒤로는 $DEVTOOLS2 폴더 복사 + 1.setup-env.sh(심볼릭 링크
# 재생성)만으로 재현됩니다.
# =====================================================================================

set -euo pipefail

# 0) 스크립트 위치 기준 상위의 상위의 상위 디렉토리를 DEVTOOLS2로 고정 설정
# 리눅스에서 기본 전역 환경변수를 제외한 사용자 정의의 시스템 전역 환경 변수는 없음
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")

# 만약 스크립트가 리포지토리 외부(예: /tmp)에서 실행되었거나, 유효한 DEVTOOLS2 폴더가 아니면
# 표준 경로인 /var/opt/_devtools2 를 기본값으로 사용합니다.
if [ ! -f "$DEVTOOLS2/scripts/linux/dev-env/0.init-devtools2.sh" ]; then
    DEVTOOLS2="/var/opt/_devtools2"
fi

DEVTOOLS2_GROUP=devers

# 공통 색상/스피너 헬퍼 로드 (온라인 전용)
_load_colors() {
    [ -n "${_COLORS_LOADED:-}" ] && return 0

    # 캐시 우회 헤더 포함 (run_remote_script와 동일) — CDN이 방금 푸시 전 구버전을
    # 서빙하면 "진입 스크립트는 최신인데 _colors.sh만 구버전"이 될 수 있으므로 필수.
    # curl의 실제 실패 사유(stderr)를 버리지 않고 그대로 보여줘야 나중에 원인 진단이 가능하다.
    # 고정된 /tmp/_colors_remote.sh 경로를 쓰면, 이 스크립트를 실행하는 사용자가 바뀔 때
    # (예: 0.init은 root로, 1.setup-env는 일반 사용자로) /tmp의 sticky bit 때문에 이전
    # 실행자가 만든 파일을 지금 사용자가 덮어쓰지 못해 curl이 쓰기 실패(exit 23)한다
    # (실측으로 재현 확인). mktemp로 매번 고유한 파일을 만들어 이 충돌을 없앤다.
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
    echo "  네트워크 연결을 확인하세요." >&2
    exit 1
}
_load_colors

# 루트 권한 체크
if [ "$(id -u)" -ne 0 ]; then
    print_error "이 스크립트는 관리자(root) 권한으로 실행해야 합니다. sudo로 실행하세요."
    exit 1
fi

print_sep
print_step "[Step 0] 시스템 필수 패키지 설치 (unzip, tar, curl, wget, rsync, python3-pip)"
print_sep

# 만약 이전 패키지 작업이 락을 쥐고 멈춰있는 경우(WSL2 비정상 종료 등으로 stale 상태가 된
# 경우) 락 강제 해제 — 단, fuser로 실제로 쥐고 있는 프로세스가 없을 때만 지웁니다.
# unattended-upgrades 같은 진짜 실행 중인 apt/dpkg 프로세스와 경합해 dpkg 데이터베이스가
# 손상되는 걸 방지하기 위함(fuser가 없는 극단적 환경이면 기존처럼 무조건 삭제로 폴백).
for _lockfile in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock; do
    if [ -e "$_lockfile" ]; then
        if command -v fuser &>/dev/null; then
            fuser "$_lockfile" >/dev/null 2>&1 || rm -f "$_lockfile"
        else
            rm -f "$_lockfile"
        fi
    fi
done
dpkg --configure -a 2>/dev/null

# 한국 카카오 미러 서버 연결 가능 여부 확인 (스피너 표시, 최대 3초)
_use_kakao=false
curl -sf --max-time 3 http://mirror.kakao.com/ubuntu/ -o /dev/null 2>/dev/null &
_kakao_pid=$!
run_with_spinner "카카오 미러 서버 연결 확인 중..." "$_kakao_pid"
wait "$_kakao_pid" 2>/dev/null && _use_kakao=true || _use_kakao=false

_switch_mirror() {
    local from="$1" to="$2"
    [ -f /etc/apt/sources.list.d/ubuntu.sources ] && sed -i "s|$from|$to|g" /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null
    [ -f /etc/apt/sources.list ] && sed -i "s|$from|$to|g" /etc/apt/sources.list 2>/dev/null
}

if [ "$_use_kakao" = "true" ]; then
    print_info "카카오 고속 미러 서버 연결 확인 → mirror.kakao.com 으로 전환합니다."
    _switch_mirror "http://archive.ubuntu.com/ubuntu/"  "http://mirror.kakao.com/ubuntu/"
    _switch_mirror "http://security.ubuntu.com/ubuntu/" "http://mirror.kakao.com/ubuntu/"
else
    print_warn "카카오 미러 서버 연결 불가 → 기본 Ubuntu 서버(archive.ubuntu.com)를 사용합니다."
fi

print_info "apt 패키지 다운로드 및 설치 중 (locales, language-pack-ko 포함)..."
(apt-get update && apt-get install -y unzip tar curl wget rsync python3-pip locales language-pack-ko) > /tmp/_apt_install.log 2>&1 &
_apt_pid=$!
run_with_spinner "apt 설치/다운로드 진행 중..." "$_apt_pid"
APT_DIRECT_EXIT=0
wait "$_apt_pid" || APT_DIRECT_EXIT=$?

# apt가 카카오 미러 서버로 실패한 경우 → 원래 서버로 자동 복구 후 재시도
if [ "$APT_DIRECT_EXIT" -ne 0 ] && [ "$_use_kakao" = "true" ]; then
    print_warn "카카오 미러 서버 실패. 기본 Ubuntu 서버로 폴백 후 재시도합니다..."
    _switch_mirror "http://mirror.kakao.com/ubuntu/" "http://archive.ubuntu.com/ubuntu/"
    if command -v fuser &>/dev/null; then
        fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || rm -f /var/lib/apt/lists/lock 2>/dev/null
    else
        rm -f /var/lib/apt/lists/lock 2>/dev/null
    fi
    (apt-get update && apt-get install -y unzip tar curl wget rsync python3-pip locales language-pack-ko) > /tmp/_apt_install.log 2>&1 &
    _apt_pid=$!
    run_with_spinner "폴백 서버로 apt 재시도 중..." "$_apt_pid"
    APT_DIRECT_EXIT=0
    wait "$_apt_pid" || APT_DIRECT_EXIT=$?
fi

if [ "${APT_DIRECT_EXIT:-0}" -ne 0 ]; then
    print_error "패키지 설치에 실패했습니다. 로그:"
    cat /tmp/_apt_install.log >&2
    exit 1
fi
rm -f /tmp/_apt_install.log

# 한글 UTF-8 로케일 생성 및 시스템 전역 로케일 설정 (스피너 표시)
if command -v locale-gen >/dev/null 2>&1; then
    (locale-gen ko_KR.UTF-8 && update-locale LANG=ko_KR.UTF-8) >/tmp/_locale.log 2>&1 &
    _loc_pid=$!
    run_with_spinner "한글 로케일(ko_KR.UTF-8) 생성 및 설정 중..." "$_loc_pid"
    wait "$_loc_pid" 2>/dev/null || true
    rm -f /tmp/_locale.log 2>/dev/null
fi

print_done "필수 패키지 및 로케일 설치 완료!"

# 스크립트를 실제 호출한 사용자(관리자가 sudo로 실행한 경우 SUDO_USER를 우선 사용)
INVOKER="${SUDO_USER:-${USER:-root}}"
INVOKER_HOME=$(getent passwd "$INVOKER" | cut -d: -f6)

TARGET_DIR="/var/opt/_devtools2"

# 1) 디렉터리 존재 여부 및 Git 저장소 여부 검사
if [ -d "$TARGET_DIR" ] && [ -d "$TARGET_DIR/.git" ]; then
    # 이미 유효한 저장소가 있는 경우: 백업/재클론 없이 그대로 진행
    echo ""
    print_sep
    print_info "이미 유효한 Git 개발도구 저장소($TARGET_DIR)가 존재합니다."
    print_info "설치 스크립트는 멱등성이 보장되므로 그대로 이어서 진행합니다."
    print_info ""
    print_info "💡 저장소 파일(scripts/, assets/ 등)을 최신화하려면 아래 명령을 직접 실행하세요:"
    print_info "   cd $TARGET_DIR && git pull"
    print_sep
    echo ""
    DEVTOOLS2="$TARGET_DIR"
else
    # 디렉터리가 없거나 .git 저장소가 아니면 신규 클론 진행
    if [ -d "$TARGET_DIR" ] && [ -n "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
        # .git 없는 잔여 파일 정리
        print_warn "Git 저장소가 아닌 잔여 디렉터리를 제거합니다: $TARGET_DIR"
        rm -rf "$TARGET_DIR"
    fi

    echo "[작업] DevTools2 포터블 개발 환경 클론 중..."

    # 디렉터리를 미리 만들고 소유권을 $INVOKER로 이전해 주어야
    # 일반 사용자 권한(sudo -u $INVOKER)으로 안전하게 쓰기(클론)가 가능합니다.
    mkdir -p "$TARGET_DIR"
    chown -R "$INVOKER" "$TARGET_DIR"

    # 공개 저장소이므로 토큰 인증 없이 호출자 권한으로 클론을 진행합니다.
    if ! sudo -u "$INVOKER" git clone https://github.com/devers2/_devtools2.git "$TARGET_DIR"; then
        echo "[오류] 깃 클론에 실패했습니다. 네트워크 상태나 저장소 URL을 확인해주세요."
        exit 1
    fi
    echo "  ✅ 깃 클론 완료!"

    DEVTOOLS2="$TARGET_DIR"
fi

# 진행 정보 출력
echo "[정보] DEVTOOLS2 경로: $DEVTOOLS2"
echo "[정보] DEVTOOLS2 그룹: $DEVTOOLS2_GROUP"
echo "[정보] 호출자(소유자 예정): $INVOKER"

# 1) 그룹 생성 (이미 있으면 건너뜀)
if getent group "$DEVTOOLS2_GROUP" >/dev/null 2>&1; then
    echo "[확인] 그룹 '$DEVTOOLS2_GROUP'이 이미 존재합니다."
else
    echo "[작업] 그룹 '$DEVTOOLS2_GROUP'을 생성합니다..."
    groupadd "$DEVTOOLS2_GROUP"
    echo "[완료] 그룹 '$DEVTOOLS2_GROUP' 생성됨."
fi

# 2) 호출자를 그룹에 추가 (이미 속해있으면 건너뜀)
if id -nG "$INVOKER" | grep -qw "$DEVTOOLS2_GROUP"; then
    echo "[확인] 사용자 '$INVOKER'가 이미 그룹 '$DEVTOOLS2_GROUP'에 속해있습니다."
else
    echo "[작업] 사용자 '$INVOKER'을(를) 그룹 '$DEVTOOLS2_GROUP'에 추가합니다..."
    usermod -aG "$DEVTOOLS2_GROUP" "$INVOKER"
    echo "[완료] 사용자 '$INVOKER'이(가) 그룹 '$DEVTOOLS2_GROUP'에 추가되었습니다."

    # 현재 로그인 세션에서 그룹 변경을 즉시 적용하려 시도합니다.
    # 스크립트가 sudo로 실행된 경우 SUDO_USER로 그룹 변경된 사용자 세션으로 전환하여 newgrp를 실행합니다.
    if [ -n "${SUDO_USER:-}" ] && [ "$INVOKER" != "root" ]; then
        echo "[안내] 사용자 '$INVOKER'에 그룹 변경을 적용하려면 해당 사용자 세션에서 'newgrp $DEVTOOLS2_GROUP'을 실행하거나 재로그인하세요."
    fi
fi

# 필수 개발환경 디렉터리 사전 생성 (심볼릭 링크 대상 및 설정 보장)
mkdir -p "$DEVTOOLS2/.config/nvim" \
         "$DEVTOOLS2/.config/zed" \
         "$DEVTOOLS2/.config/vscode" \
         "$DEVTOOLS2/data/nvim" \
         "$DEVTOOLS2/data/.gradle/caches" \
         "$DEVTOOLS2/data/.gradle/wrapper" \
         "$DEVTOOLS2/data/.m2" \
         "$DEVTOOLS2/modules"

# VSCode 기본 설정 파일 사전 생성
[ ! -f "$DEVTOOLS2/.config/vscode/settings.json" ] && touch "$DEVTOOLS2/.config/vscode/settings.json"
[ ! -f "$DEVTOOLS2/.config/vscode/keybindings.json" ] && touch "$DEVTOOLS2/.config/vscode/keybindings.json"
[ ! -f "$DEVTOOLS2/.config/vscode/tasks.json" ] && touch "$DEVTOOLS2/.config/vscode/tasks.json"

# 3) 소유권 설정: INVOKER:GROUP
if [ ! -d "$DEVTOOLS2" ]; then
    echo "[오류] DEVTOOLS2 디렉토리를 찾을 수 없습니다: $DEVTOOLS2"
    exit 1
fi
echo "[작업] $DEVTOOLS2 및 하위 항목의 소유권을 $INVOKER:$DEVTOOLS2_GROUP 으로 설정합니다..."
chown -R "$INVOKER:$DEVTOOLS2_GROUP" "$DEVTOOLS2"

# 4) 디렉토리 권한(2775, SGID) 및 파일 권한(664) 설정
echo "[작업] 디렉토리와 파일 퍼미션을 조정합니다 (디렉토리: 2775, 파일: group-writable 유지, 실행권한 보존)..."
find "$DEVTOOLS2" -type d -exec chmod 2775 {} +
find "$DEVTOOLS2" -type f -exec chmod a+r,u+w,g+w {} +

# 4-1) 사용자에게 passwordless sudo 권한을 부여하여 후속 패키지 설치 단계에서 암호 입력을 생략함
if [ "$INVOKER" != "root" ]; then
    echo "[작업] 사용자 '$INVOKER'에게 passwordless sudo 설정을 부여합니다..."
    echo "$INVOKER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$INVOKER"
    chmod 0440 "/etc/sudoers.d/$INVOKER"
fi

# DEVTOOLS2와 DEVTOOLS2_GROUP은 이 스크립트 실행 시 고정(할당)되어 스크립트 내에서 사용됩니다.
# 시스템 전역으로 영구 등록하지는 않습니다. 각 사용자 세션에 환경변수를 영구히 추가하려면
# add-devtools2-user.sh를 사용하여 해당 사용자의 쉘 초기화 파일을 업데이트하세요.

# 5) 완료 및 사용자 추가 안내
cat <<EOF

[요약]
- 대상 디렉토리 : $DEVTOOLS2
- 소유자         : $INVOKER
- 그룹           : $DEVTOOLS2_GROUP

[안내 사항]
- 변경된 그룹을 적용하려면 현재 터미널을 종료하고 새로운 터미널에서 작업해주세요❗
- 다른 사용자를 그룹에 추가하려면 아래 명령을 사용하세요:

  sudo $DEVTOOLS2/scripts/linux/dev-env/add-devtools2-user.sh <username> [<username> ...]

  예: sudo $DEVTOOLS2/scripts/linux/dev-env/add-devtools2-user.sh alice bob

  ❗중요: 다른 사용자를 그룹에 추가하려면 반드시 위 add-devtools2-user.sh 스크립트를 사용하세요. add-devtools2-user.sh는 사용자를 생성(필요 시), 그룹에 추가하고 각 사용자의 쉘 초기화 파일에 umask 002를 추가합니다.

완료되었습니다.
EOF
