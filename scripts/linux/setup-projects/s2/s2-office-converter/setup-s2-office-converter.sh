#!/usr/bin/env bash
# ==============================================================================
# s2 오피스/한글 문서 변환기 설치 스크립트 (setup-s2-office-converter.sh)
# 위치: _devtools2/scripts/linux/setup-projects/s2/s2-office-converter/  (같은 폴더의 README.md 참고)
# ==============================================================================
#
# [실행 방법] s2-docflow 를 쓰는 앱과 같은 서버에서, sudo 를 쓸 수 있는 계정으로 실행합니다.
#             이 파일 하나만으로 동작하므로 저장소를 받을 필요 없이 GitHub 에서 바로 실행하면 됩니다.
#
#   주소: https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/setup-projects/s2/s2-office-converter/setup-s2-office-converter.sh
#
#   # 1) 운영 서버 (온라인) — 앱 실행 계정을 지정해 설치 (appuser 자리에 실제 계정 이름)
#   curl -fsSL https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/setup-projects/s2/s2-office-converter/setup-s2-office-converter.sh | bash -s -- --app-user appuser
#
#   # 2) 개발 PC, WSL (온라인) — 지금 로그인한 계정으로 설치
#   curl -fsSL https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/setup-projects/s2/s2-office-converter/setup-s2-office-converter.sh | bash
#
#   # 3) 폐쇄망 서버 — 인터넷 되는 PC에서 설치 파일 하나를 만들어 옮긴 뒤 실행
#   #    (인터넷 되는 PC, 서버와 같은 CPU 종류) 서버 배포판·버전을 --target 으로 지정
#   curl -fsSL <위 주소> | bash -s -- --export --target ubuntu:22.04
#   #    → setup-s2-office-converter-offline.sh 파일 하나가 생김 (스크립트 + 이미지 + Podman 설치 파일)
#   #    (폐쇄망 서버) 그 파일을 옮겨 실행
#   bash setup-s2-office-converter-offline.sh --app-user appuser
#
#   # 이미지 다시 만들기 / 제거
#   curl -fsSL <위 주소> | bash -s -- --app-user appuser --rebuild
#   curl -fsSL <위 주소> | bash -s -- --app-user appuser --uninstall
#
#   앱 실행 계정: 웹 애플리케이션(Java)을 실행하는 리눅스 계정입니다 (웹사이트 회원 계정이 아님).
#     확인: ps -eo user,cmd | grep -i java   → 첫 칸이 앱 실행 계정
#     rootless Podman 은 이미지를 계정별로 저장하므로, 그 계정에 설치해야 앱이 변환기를 쓸 수 있습니다.
#
#   - 처음 실행은 LibreOffice 를 받느라 몇 분 걸리며, sudo 비밀번호를 물을 수 있습니다.
#   - 여러 번 실행해도 안전합니다. 이미 설치된 것은 건너뛰고 빠진 것만 채웁니다.
#   - 설치가 끝나면 앱을 다시 시작할 필요 없이 S2OfficeConverter 가 s2-soffice 를 자동으로 찾습니다.
#   - 확인: sudo -u appuser s2-soffice --version, sudo -u appuser s2-chrome --version
#   - 웹 페이지 변환(Chromium)과 rhwp 한글 조판(s2-hwp)이 필요 없으면 --no-chrome (이미지 약 0.7GB 작아짐, 한글은 LibreOffice 로만 변환)
#
# [하는 일]
# S2DocumentMerger·S2OfficeConverter(s2-docflow)가 docx·xlsx·pptx·hwp·hwpx 등을 PDF 로 변환·병합할 수 있도록
# LibreOffice + H2Orestart(한글 확장) + 한글 폰트가 든 Podman 컨테이너 이미지를 만들고,
# 이를 호출하는 명령 s2-soffice 를 설치합니다. 웹 페이지(URL 로 받은 HTML)를 화면 그대로 PDF 로 만들도록
# Chromium 과 명령 s2-chrome 도 함께 설치합니다 (--no-chrome 으로 뺄 수 있음).
# Chromium 을 넣으면 한글 문서 전용 명령 s2-hwp 도 설치합니다: rhwp(HWP/HWPX 조판)가 그린 쪽을 Chromium 으로 인쇄해
# 쪽 나눔·그림·글꼴이 LibreOffice + H2Orestart 보다 원본에 가깝습니다. 앱은 s2-hwp 를 먼저 쓰고 실패하면 s2-soffice 로 변환합니다.
#
#   [앱] S2DocumentMerger ──(s2-soffice --headless --convert-to pdf ...)──▶ [Podman 컨테이너]
#                  ──(s2-chrome --print-to-pdf <pdf> <html>)────────▶  LibreOffice + H2Orestart + Chromium
#                  ──(s2-hwp --outdir <폴더> <파일.hwp>)─────────────▶  + Node.js·rhwp + 폰트
#
# 버전: H2Orestart·rhwp 의 버전 정책은 같은 폴더의 s2-office-converter-versions.toml(Git 관리)에 있습니다.
#   [track] 범위 안의 최신 버전을 설치하고, 이미 설치된 버전보다 새 버전이 있으면 업데이트할지 묻습니다 (기본 Y,
#   무인 실행은 유지, 강제: S2_CONVERTER_UPDATE=y|n). 되돌릴 때는 그 파일의 [track] 을 이전 버전으로 고정합니다.
#
# 옵션:
#   --app-user 계정    앱 실행 계정(웹 애플리케이션을 실행하는 리눅스 계정). 기본: 이 스크립트를 실행한 계정.
#                      --user 도 같은 뜻으로 받습니다.
#   --rebuild          이미지를 다시 만듭니다 (보안 업데이트 반영 등).
#   --no-chrome        Chromium(s2-chrome)과 rhwp(s2-hwp)를 빼고 설치합니다 (이미지 약 0.7GB 작아짐).
#                      (HTML-to-PDF 및 SVG 변환 기능이 비활성화됩니다)
#   --uninstall        s2-soffice·s2-chrome·s2-hwp 명령과 이미지를 제거합니다 (Podman 자체는 남김).
#   --export [파일]    폐쇄망용 설치 파일 하나를 만듭니다 (기본 ./setup-s2-office-converter-offline.sh).
#                      인터넷 되는 PC에서 실행. 이 스크립트 뒤에 변환기 이미지와 Podman 설치 파일을 붙인 파일로,
#                      서버에서 그대로 실행하면 인터넷 접속 없이 설치합니다 (옵션은 이 스크립트와 같음).
#   --target 배포판    --export 에서 서버의 배포판:버전 (예: ubuntu:22.04, ubuntu:24.04, debian:12, rockylinux:9, almalinux:9).
#                      기본: 이 PC 와 같음. 서버에 Podman 을 설치할 패키지를 이 배포판용으로 받습니다.
#
# 멱등성: 몇 번을 실행해도 같은 상태가 됩니다. 이미 있는 것은 건너뛰고 없는 것만 준비합니다.
#   - Podman: 없으면 설치 (온라인: apt/dnf, 폐쇄망: 설치 파일에 든 패키지)
#   - 대상 계정의 subuid/subgid: 없으면 추가 (rootless Podman 필요 조건)
#   - 이미지: 같은 버전(태그)이 있으면 건너뜀. 버전을 올리면(업데이트에 동의하면) 새로 만들고 이전 버전은 정리
#   - /usr/local/bin/s2-soffice, s2-chrome, s2-hwp: 내용이 다를 때만 교체 (--no-chrome 이면 s2-chrome·s2-hwp 제거)
#   - 마지막에 실제 변환으로 동작을 확인
#
# 라이선스: 이 스크립트는 LibreOffice(MPL 2.0), H2Orestart(MIT), rhwp(MIT), Node.js(MIT), qpdf(Apache 2.0), Chromium(BSD 3-Clause 등),
# 폰트(SIL OFL 1.1 등), Podman(Apache 2.0)을
# 각 배포처에서 받아 설치할 뿐, 재배포하지 않습니다. 각 소프트웨어는 자체 라이선스를 따릅니다.
# (폐쇄망 설치 파일을 다른 조직에 전달하면 그 안의 소프트웨어를 배포하는 것이 되므로 각 라이선스를 확인하십시오.)
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# 버전
# ------------------------------------------------------------------------------
# H2Orestart·rhwp 버전 정책과 이력은 같은 폴더의 s2-office-converter-versions.toml(Git 관리)에 있습니다.
# 버전을 올리거나 되돌릴 때는 그 파일의 [track] 을 바꿉니다 (그 파일 머리말 참고).
# 아래 기본값은 그 파일을 읽지 못할 때(파일도 없고 GitHub 접속도 안 될 때)만 씁니다.
DEFAULT_H2ORESTART_VERSION="0.8.0"
DEFAULT_RHWP_VERSION="0.8.7"
# 이미지 만드는 방법(아래 Containerfile)을 바꾸면 올립니다. 다음 실행 때 같은 구성 요소 버전으로 이미지를 다시 만듭니다.
IMAGE_REVISION="5"
BASE_IMAGE="docker.io/library/debian:trixie-slim"
IMAGE_NAME="localhost/s2-office-converter"
WRAPPER_PATH="/usr/local/bin/s2-soffice"
CHROME_WRAPPER_PATH="/usr/local/bin/s2-chrome"
HWP_WRAPPER_PATH="/usr/local/bin/s2-hwp"
SCRIPT_NAME="setup-s2-office-converter.sh"
SCRIPT_URL="https://raw.githubusercontent.com/devers2/_devtools2/${DT2_REF:-main}/scripts/linux/setup-projects/s2/s2-office-converter/${SCRIPT_NAME}"
VERSIONS_NAME="s2-office-converter-versions.toml"
VERSIONS_URL="${SCRIPT_URL%/*}/${VERSIONS_NAME}"
# Chosen in select_versions (install, export) or read from the bundle (offline) | select_versions 또는 설치 파일에서 정함
H2ORESTART_VERSION=""
H2ORESTART_SHA256=""
RHWP_VERSION=""
RHWP_INTEGRITY=""
IMAGE_ARCHIVE="s2-office-converter.tar"
OFFLINE_FILE="setup-s2-office-converter-offline.sh"
# Line between the script and the attached payload of an offline file | 폐쇄망 설치 파일에서 스크립트와 첨부 데이터의 경계 줄
PAYLOAD_MARKER="__S2_OFFICE_CONVERTER_PAYLOAD__"
# Large files go here rather than /tmp, which is often a small tmpfs | 큰 파일은 작은 tmpfs 인 경우가 많은 /tmp 대신 여기에
WORK_TMP="${TMPDIR:-/var/tmp}"

# ------------------------------------------------------------------------------
# 출력
# ------------------------------------------------------------------------------
info() { printf '▶ %s\n' "$*"; }
ok() { printf '✅ %s\n' "$*"; }
skip() { printf '⏭️  %s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*" >&2; }
fail() {
    printf '❌ %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
사용법: bash setup-s2-office-converter.sh [옵션]

  (옵션 없음)          지금 로그인한 계정용으로 온라인 설치
  --app-user 계정      앱 실행 계정(웹 애플리케이션을 실행하는 리눅스 계정)용으로 설치. --user 도 같은 뜻.
                       확인: ps -eo user,cmd | grep -i java (첫 칸)
  --rebuild            이미지를 다시 만듦 (보안 업데이트 반영 등)
  --no-chrome          Chromium(s2-chrome)과 rhwp(s2-hwp)를 빼고 설치 (이미지 약 0.7GB 작아짐, 한글은 LibreOffice 로만)
  --uninstall          s2-soffice·s2-chrome·s2-hwp 명령과 이미지를 제거 (Podman 은 남김)
  --export [파일]      폐쇄망용 설치 파일 하나 만들기 (기본 ./setup-s2-office-converter-offline.sh, 인터넷 되는 PC에서)
                       서버에서: bash setup-s2-office-converter-offline.sh --app-user 계정
  --target 배포판      --export 에서 서버 배포판:버전 (예: ubuntu:22.04, debian:12, rockylinux:9). 기본: 이 PC 와 같음
  --help               이 도움말

버전: s2-office-converter-versions.toml 의 [track] 범위 안 최신 버전을 설치합니다. 설치된 버전보다 새 버전이 있으면
      업데이트할지 묻습니다 (무인 실행은 유지). 묻지 않으려면 S2_CONVERTER_UPDATE=y (업데이트) 또는 n (유지).

자세한 안내: 같은 폴더의 README.md
USAGE
}

# ------------------------------------------------------------------------------
# 인자
# ------------------------------------------------------------------------------
TARGET_USER="${SUDO_USER:-$(id -un)}"
MODE="install"
REBUILD=false
WITH_CHROME=true
EXPORT_FILE=""
TARGET_DISTRO=""
while [ $# -gt 0 ]; do
    case "$1" in
    --app-user | --user)
        [ $# -ge 2 ] || fail "$1 다음에 앱 실행 계정 이름이 필요합니다."
        TARGET_USER="$2"
        shift 2
        ;;
    --app-user=* | --user=*)
        TARGET_USER="${1#*=}"
        shift
        ;;
    --rebuild)
        REBUILD=true
        shift
        ;;
    --uninstall)
        MODE="uninstall"
        shift
        ;;
    --no-chrome)
        WITH_CHROME=false
        shift
        ;;
    --export)
        MODE="export"
        if [ $# -ge 2 ] && [ "${2#--}" = "$2" ]; then
            EXPORT_FILE="$2"
            shift 2
        else
            shift
        fi
        ;;
    --export=*)
        MODE="export"
        EXPORT_FILE="${1#*=}"
        shift
        ;;
    --target)
        [ $# -ge 2 ] || fail "--target 다음에 배포판:버전이 필요합니다 (예: ubuntu:22.04)."
        TARGET_DISTRO="$2"
        shift 2
        ;;
    --target=*)
        TARGET_DISTRO="${1#*=}"
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *) fail "알 수 없는 옵션입니다: $1 (--help 참고)" ;;
    esac
done
if [ -n "$TARGET_DISTRO" ] && [ "$MODE" != "export" ]; then
    fail "--target 은 --export 와 함께 씁니다."
fi

# Image tag per content: recipe revision, component versions, with Chromium (and rhwp) or without
# | 이미지 태그는 내용별: 만드는 방법 리비전, 구성 요소 버전, Chromium(과 rhwp) 포함 여부
image_for() {
    if [ "$1" = true ]; then
        echo "${IMAGE_NAME}:${IMAGE_REVISION}-h2o${H2ORESTART_VERSION}-rhwp${RHWP_VERSION}-chrome"
    else
        echo "${IMAGE_NAME}:${IMAGE_REVISION}-h2o${H2ORESTART_VERSION}"
    fi
}
IMAGE=""

# An offline file is this script with the payload attached after a marker line: "<marker> <sha256 of payload>"
# | 폐쇄망 설치 파일은 이 스크립트 뒤에 경계 줄("<경계> <첨부 데이터 sha256>")과 첨부 데이터를 붙인 것
SELF=""
PAYLOAD_LINE=""
PAYLOAD_SHA256=""
if [ -f "${BASH_SOURCE[0]:-}" ]; then
    SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    marker_line="$(grep -anm1 "^${PAYLOAD_MARKER} [0-9a-f]\{64\}\$" "$SELF" || true)"
    if [ -n "$marker_line" ]; then
        PAYLOAD_LINE="${marker_line%%:*}"
        PAYLOAD_SHA256="${marker_line##* }"
    fi
fi
if [ -n "$PAYLOAD_LINE" ]; then
    case "$MODE" in
    install) MODE="offline" ;;
    export) fail "폐쇄망 설치 파일로는 --export 를 할 수 없습니다. 인터넷 되는 PC에서 원래 스크립트로 실행하십시오." ;;
    esac
fi

[ "$(uname -s)" = "Linux" ] || fail "리눅스에서만 실행할 수 있습니다."
ARCH="$(uname -m)"

# root 권한이 필요한 명령 (이미 root 면 그대로)
if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    command -v sudo >/dev/null 2>&1 || fail "sudo 가 필요합니다."
    SUDO=(sudo)
fi

# --export builds the image as the current user; the other modes install for the app account
# | --export 는 지금 계정으로 이미지를 만들고, 나머지는 앱 실행 계정에 설치
[ "$MODE" != "export" ] || TARGET_USER="$(id -un)"
id "$TARGET_USER" >/dev/null 2>&1 || fail "앱 실행 계정이 없습니다: $TARGET_USER (확인: ps -eo user,cmd | grep -i java)"
[ "$TARGET_USER" != "root" ] || fail "root 계정용으로는 만들지 않습니다. --app-user 로 앱을 실행하는 일반 계정을 지정하십시오."
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
# Rootless Podman keeps images under the account's home | rootless Podman 은 이미지를 계정 홈 아래에 저장
if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
    fail "앱 실행 계정($TARGET_USER)의 홈 폴더가 없습니다: ${TARGET_HOME:-(없음)}. Podman 이미지를 저장할 수 있도록 홈 폴더를 만들어 주십시오 (예: sudo mkdir -p /home/$TARGET_USER && sudo chown $TARGET_USER: /home/$TARGET_USER && sudo usermod -d /home/$TARGET_USER $TARGET_USER)."
fi

# 대상 계정으로 실행. 로그인 세션이 없는 서비스 계정도 동작하도록 런타임 경로와 cgroup 관리자를 지정
as_target() {
    local runtime_dir="/run/user/${TARGET_UID}"
    [ -d "$runtime_dir" ] || runtime_dir="/tmp/podman-run-${TARGET_UID}"
    if [ "$(id -un)" = "$TARGET_USER" ]; then
        mkdir -p "$runtime_dir"
        env XDG_RUNTIME_DIR="$runtime_dir" HOME="$TARGET_HOME" "$@"
    else
        run_as "$TARGET_USER" env XDG_RUNTIME_DIR="$runtime_dir" HOME="$TARGET_HOME" sh -c 'mkdir -p "$XDG_RUNTIME_DIR" && exec "$@"' sh "$@"
    fi
}

# 다른 계정으로 실행. root 면 runuser (sudo 가 없는 최소 설치 서버 대비), 아니면 sudo
run_as() {
    local user="$1"
    shift
    if [ "$(id -u)" -eq 0 ] && command -v runuser >/dev/null 2>&1; then
        runuser -u "$user" -- "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo -u "$user" -H "$@"
    else
        fail "다른 계정으로 실행하려면 sudo 또는 runuser 가 필요합니다."
    fi
}
podman_target() {
    as_target podman --cgroup-manager=cgroupfs --events-backend=file "$@"
}

# 임시 폴더 정리
CLEANUP_PATHS=()
cleanup() {
    local path
    for path in "${CLEANUP_PATHS[@]+"${CLEANUP_PATHS[@]}"}"; do
        rm -rf "$path" 2>/dev/null || "${SUDO[@]}" rm -rf "$path" 2>/dev/null || true
    done
}
trap cleanup EXIT

# /etc/os-release → "ubuntu:22.04" 형식
host_distro() {
    # shellcheck disable=SC1091
    (. /etc/os-release && printf '%s:%s' "${ID:-unknown}" "${VERSION_ID:-unknown}")
}

# 배포판 이름 → 패키지를 받을 컨테이너 이미지
distro_image() {
    local id="${1%%:*}" version="${1#*:}"
    case "$id" in
    ubuntu | debian) echo "docker.io/library/${id}:${version}" ;;
    rocky | rockylinux) echo "quay.io/rockylinux/rockylinux:${version}" ;;
    almalinux) echo "docker.io/library/almalinux:${version}" ;;
    rhel) echo "docker.io/library/almalinux:${version%%.*}" ;; # RHEL 과 바이너리 호환 (구독 없이 받기 위함)
    fedora) echo "registry.fedoraproject.org/fedora:${version}" ;;
    *) return 1 ;;
    esac
}
# 배포판 이름 → 패키지 관리자 계열
distro_family() {
    case "${1%%:*}" in
    ubuntu | debian) echo apt ;;
    rocky | rockylinux | almalinux | rhel | fedora | centos) echo dnf ;;
    *) return 1 ;;
    esac
}

# ==============================================================================
# 버전 정책 (s2-office-converter-versions.toml)
# ==============================================================================
# _devtools2 의 tool-versions.toml 과 같은 규칙:
#   ● [track] 범위 안의 최신 버전을 배포처에서 찾는다 (조회 실패 시 [versions] 첫 항목)
#   ● 처음 설치는 묻지 않고 그 버전으로, 이미 설치된 버전과 다르면 업데이트 여부를 묻는다 (기본 Y)
#   ● 무인 실행(터미널 없음)은 설치된 버전 유지. 강제: S2_CONVERTER_UPDATE=y|n
#   ● 범위 밖의 새 버전은 안내만 (올리려면 [track] 값을 바꿈)
#   ● 버전 파일은 읽기만 한다 (Git 작업 트리 보호). 새로 검증한 해시는 파일에 넣을 줄을 출력한다

VERSIONS_TOML=""
VERSIONS_SOURCE=""
load_versions() {
    local local_file=""
    [ -z "$SELF" ] || local_file="$(dirname "$SELF")/${VERSIONS_NAME}"
    if [ -n "$local_file" ] && [ -f "$local_file" ]; then
        VERSIONS_TOML="$(cat "$local_file")"
        VERSIONS_SOURCE="$local_file"
    elif VERSIONS_TOML="$(curl -fsSL --max-time 15 -H 'Cache-Control: no-cache' "$VERSIONS_URL" 2>/dev/null)" &&
        [ -n "$VERSIONS_TOML" ]; then
        VERSIONS_SOURCE="$VERSIONS_URL"
    else
        VERSIONS_TOML=""
        VERSIONS_SOURCE="(스크립트 기본값)"
        warn "버전 파일을 읽지 못해 스크립트 기본값을 씁니다: ${VERSIONS_NAME}"
    fi
}

# Value of "key = ..." inside one [section] | [섹션] 안의 "키 = 값"
toml_value() {
    local section="$1" key="$2"
    awk -v section="[$section]" -v key="$key" '
        /^\[/ { inside = ($0 == section); next }
        inside {
            line = $0
            sub(/[ \t]+#.*$/, "", line)
            k = line; sub(/[ \t]*=.*$/, "", k)
            if (k == key) { sub(/^[^=]*=[ \t]*/, "", line); print line; exit }
        }' <<<"$VERSIONS_TOML"
}
toml_track() { toml_value track "$1" | tr -d '"'; }
toml_fallback() { toml_value versions "$1" | grep -oE '"[^"]+"' | head -1 | tr -d '"' || true; }
toml_checksum() { toml_value checksums "\"$1@$2\"" | tr -d '"'; }

# Versions offered by the publisher, one per line (stable releases only) | 배포처의 버전 목록 (정식 릴리스만)
list_upstream() {
    case "$1" in
    h2orestart)
        curl -fsSL --max-time 20 "https://api.github.com/repos/ebandal/H2Orestart/releases?per_page=50" 2>/dev/null |
            grep -oE '"tag_name": *"v?[0-9][^"]*"' | sed -E 's/.*"v?([^"]*)"$/\1/' ;;
    rhwp)
        curl -fsSL --max-time 20 -H 'Accept: application/vnd.npm.install-v1+json' \
            "https://registry.npmjs.org/@rhwp/core" 2>/dev/null |
            grep -oE '"version":"[^"]+"' | sed -E 's/.*:"([^"]*)"$/\1/' ;;
    esac | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -uV || true
}

# Checksum published with a release | 배포처가 알려 주는 검증값
upstream_checksum() {
    local digests
    case "$1" in
    h2orestart)
        # A release has the single asset H2Orestart.oxt; more than one digest means an unexpected layout
        # | 릴리스 자산은 H2Orestart.oxt 하나. 검증값이 여럿이면 예상과 다른 구성이라 쓰지 않음
        digests="$(curl -fsSL --max-time 20 "https://api.github.com/repos/ebandal/H2Orestart/releases/tags/v$2" 2>/dev/null |
            grep -oE '"digest": *"sha256:[0-9a-f]{64}"' | grep -oE '[0-9a-f]{64}' || true)"
        [ "$(grep -c . <<<"$digests")" = 1 ] && echo "$digests" ;;
    rhwp)
        curl -fsSL --max-time 20 "https://registry.npmjs.org/@rhwp/core/$2" 2>/dev/null |
            grep -oE '"integrity":"sha512-[A-Za-z0-9+/=]+"' | head -1 | sed -E 's/.*:"([^"]*)"$/\1/' ;;
    esac
}

in_track() {
    local track="$1" version="$2"
    [ "$track" = latest ] || [ "$version" = "$track" ] || [ "${version#"$track".}" != "$version" ]
}
is_exact_track() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# Newest version within the track, or the fallback | track 범위 안 최신 버전 (없으면 폴백)
resolve_target() {
    local key="$1" default="$2" track list best top version
    # Without a versions file there is no policy: the script's default, never "latest" | 버전 파일이 없으면 정책도 없으므로 기본값
    if [ -z "$VERSIONS_TOML" ]; then
        echo "$default"
        return
    fi
    track="$(toml_track "$key")"
    track="${track:-latest}"
    if is_exact_track "$track"; then
        echo "$track"
        return
    fi
    list="$(list_upstream "$key")"
    best=""
    while IFS= read -r version; do
        [ -n "$version" ] && in_track "$track" "$version" && best="$version"
    done <<<"$list"
    top="$(tail -n 1 <<<"$list")"
    if [ -n "$top" ] && [ -n "$best" ] && [ "$top" != "$best" ]; then
        printf 'ℹ️  %s: track "%s" 밖에 새 버전 %s 이 있습니다. 올리려면 %s 의 [track] %s 값을 바꾸십시오.\n' \
            "$key" "$track" "$top" "$VERSIONS_NAME" "$key" >&2
    fi
    if [ -z "$best" ]; then
        best="$(toml_fallback "$key")"
        best="${best:-$default}"
        printf 'ℹ️  %s: 배포처에서 버전 목록을 받지 못해 %s 을 씁니다.\n' "$key" "$best" >&2
    fi
    echo "$best"
}

# Asks on the terminal even when the script itself arrives on stdin (curl | bash) | curl | bash 로 실행해도 터미널에서 물음
can_ask() { [ -z "${S2_CONVERTER_NONINTERACTIVE:-}" ] && { : </dev/tty; } 2>/dev/null; }
ask_yes() {
    local answer=""
    printf '%s [Y/n]: ' "$1" >/dev/tty
    read -r answer </dev/tty || answer=""
    case "${answer:-Y}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# The installed image: the one the s2-soffice command uses, if it still exists | 설치된 이미지 (s2-soffice 가 쓰는 것)
installed_image() {
    local image
    [ -f "$WRAPPER_PATH" ] || return 0
    image="$(sed -n 's/^IMAGE="\(.*\)"$/\1/p' "$WRAPPER_PATH" | head -1)"
    [ -n "$image" ] && podman_target image exists "$image" 2>/dev/null && echo "$image" || true
}
image_label() {
    podman_target image inspect --format "{{index .Labels \"$2\"}}" "$1" 2>/dev/null | sed 's/^<no value>$//' || true
}

# Installed or target version for one component | 구성 요소 하나의 버전 결정 (설치된 것 유지 또는 새 버전)
choose_version() {
    local name="$1" installed="$2" target="$3"
    if [ -z "$installed" ] || [ "$installed" = "$target" ]; then
        echo "$target"
        return
    fi
    local verb="업데이트"
    if [ "$(printf '%s\n%s\n' "$installed" "$target" | sort -V | tail -n 1)" = "$installed" ]; then
        # The track now names an older version: a rollback | track 이 더 낮은 버전을 가리킴: 되돌리기
        verb="되돌리기"
        printf 'ℹ️  %s: 버전 정책([track])이 설치된 %s 보다 낮은 %s 를 가리킵니다.\n' "$name" "$installed" "$target" >&2
    else
        printf 'ℹ️  %s 새 버전이 있습니다: %s → %s\n' "$name" "$installed" "$target" >&2
    fi
    case "${S2_CONVERTER_UPDATE:-}" in
    [Yy]*) echo "$target"; return ;;
    [Nn]*) printf '⏭️  %s %s 유지 (S2_CONVERTER_UPDATE)\n' "$name" "$installed" >&2; echo "$installed"; return ;;
    esac
    if ! can_ask; then
        printf '⏭️  무인 실행이라 %s %s 를 유지합니다 (S2_CONVERTER_UPDATE=y 로 %s).\n' "$name" "$installed" "$verb" >&2
        echo "$installed"
    elif ask_yes "   👉 ${name} 을(를) ${target} 로 바꿀까요? (${verb})"; then
        echo "$target"
    else
        printf '⏭️  %s %s 유지\n' "$name" "$installed" >&2
        echo "$installed"
    fi
}

# Checksum for a version into CHECKSUM: the versions file first, then the publisher. Not called through $(...), so
# fail stops the script and the new line is kept | 검증값을 CHECKSUM 에: 버전 파일 → 배포처. $(...) 로 부르지 않아야
# fail 이 스크립트를 멈추고 새 줄이 남음
CHECKSUM=""
checksum_for() {
    local key="$1" version="$2"
    CHECKSUM="$(toml_checksum "$key" "$version")"
    if [ -z "$CHECKSUM" ]; then
        CHECKSUM="$(upstream_checksum "$key" "$version")" || CHECKSUM=""
        [ -n "$CHECKSUM" ] || fail "${key} ${version} 의 검증값을 구하지 못했습니다 (${VERSIONS_NAME} 에도 없음). 네트워크를 확인하거나 [track] 을 검증된 버전으로 고정하십시오."
        NEW_CHECKSUM_LINES+=("\"${key}@${version}\" = \"${CHECKSUM}\"")
    fi
}

# Decides the component versions and the image tag | 구성 요소 버전과 이미지 태그 결정
NEW_CHECKSUM_LINES=()
select_versions() {
    info "구성 요소 버전 확인"
    load_versions
    local current="" current_h2o="" current_rhwp="" target_h2o target_rhwp=""
    current="$(installed_image)"
    if [ -n "$current" ]; then
        current_h2o="$(image_label "$current" s2.h2orestart.version)"
        current_rhwp="$(image_label "$current" s2.rhwp.version)"
    fi
    target_h2o="$(resolve_target h2orestart "$DEFAULT_H2ORESTART_VERSION")"
    H2ORESTART_VERSION="$(choose_version H2Orestart "$current_h2o" "$target_h2o")"
    if [ "$WITH_CHROME" = true ]; then
        target_rhwp="$(resolve_target rhwp "$DEFAULT_RHWP_VERSION")"
        RHWP_VERSION="$(choose_version rhwp "$current_rhwp" "$target_rhwp")"
    fi
    IMAGE="$(image_for "$WITH_CHROME")"
    # Checksums are needed only to build | 검증값은 이미지를 만들 때만 필요
    if [ "$REBUILD" = true ] || ! podman_target image exists "$IMAGE" 2>/dev/null; then
        checksum_for h2orestart "$H2ORESTART_VERSION"
        H2ORESTART_SHA256="$CHECKSUM"
        if [ "$WITH_CHROME" = true ]; then
            checksum_for rhwp "$RHWP_VERSION"
            RHWP_INTEGRITY="$CHECKSUM"
        fi
    fi
    ok "H2Orestart ${H2ORESTART_VERSION}${RHWP_VERSION:+, rhwp ${RHWP_VERSION}} (버전 정책: ${VERSIONS_SOURCE})"
}

# Lines to add to the versions file after verifying a new version | 새로 검증한 버전을 버전 파일에 넣을 줄 안내
print_new_checksums() {
    [ ${#NEW_CHECKSUM_LINES[@]} -gt 0 ] || return 0
    cat <<NOTE

📝 버전 파일에 없던 버전을 배포처의 검증값으로 설치했습니다. 실제 문서로 확인한 뒤 Git 으로 남기려면
   ${VERSIONS_NAME} 의 [versions] 배열 맨 앞에 버전을, [checksums] 에 아래 줄을 넣고 커밋하십시오:
NOTE
    printf '     %s\n' "${NEW_CHECKSUM_LINES[@]}"
}

# ==============================================================================
# 단계 함수
# ==============================================================================

# Podman (온라인 설치)
install_podman_online() {
    info "Podman 확인"
    if command -v podman >/dev/null 2>&1; then
        skip "Podman 이 이미 있습니다: $(podman --version)"
        return
    fi
    if command -v apt-get >/dev/null 2>&1; then
        "${SUDO[@]}" apt-get update -qq ||
            fail "패키지 목록을 받을 수 없습니다. 인터넷이 안 되는 서버라면 --export 로 만든 폐쇄망 설치 파일로 설치하십시오 (README.md 참고)."
        "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq podman uidmap slirp4netns >/dev/null
    elif command -v dnf >/dev/null 2>&1; then
        "${SUDO[@]}" dnf install -y -q podman shadow-utils ||
            fail "Podman 을 설치할 수 없습니다. 인터넷이 안 되는 서버라면 --export 로 만든 폐쇄망 설치 파일로 설치하십시오 (README.md 참고)."
    else
        fail "apt 또는 dnf 가 있는 배포판(Ubuntu, Debian, RHEL, Rocky 등)에서만 자동 설치할 수 있습니다. Podman 을 직접 설치한 뒤 다시 실행하십시오."
    fi
    ok "Podman 설치: $(podman --version)"
}

# rootless Podman 준비 (subuid/subgid)
ensure_subids() {
    info "계정 준비 ($TARGET_USER)"
    local pair file option start
    for pair in /etc/subuid:--add-subuids /etc/subgid:--add-subgids; do
        file="${pair%%:*}"
        option="${pair#*:}"
        if grep -q "^${TARGET_USER}:" "$file" 2>/dev/null || grep -q "^${TARGET_UID}:" "$file" 2>/dev/null; then
            skip "$file 에 $TARGET_USER 항목이 있습니다."
            continue
        fi
        # Use a range after the highest one in use | 사용 중인 가장 큰 범위 다음부터 할당
        start=$(awk -F: '{ end = $2 + $3; if (end > max) max = end } END { print (max > 100000 ? max : 100000) }' "$file" 2>/dev/null || echo 100000)
        "${SUDO[@]}" usermod "$option" "${start}-$((start + 65535))" "$TARGET_USER"
        ok "$file 에 $TARGET_USER 추가 (${start}-$((start + 65535)))"
    done
}

# Files that go into the image for s2-hwp | s2-hwp 용으로 이미지에 넣는 파일
write_hwp_files() {
    cat >"$1/s2-hwp-render.mjs" <<'RENDER'
// s2-hwp-render (s2-office-converter): HWP/HWPX -> HTML files of laid-out pages (rhwp SVG), for Chromium to print.
// Installed by setup-s2-office-converter.sh; do not edit inside the image.
// | rhwp 가 SVG 로 조판한 쪽을 Chromium 이 인쇄할 HTML 파일들로 모은다.
//
//   node s2-hwp-render.mjs <rhwp folder> <input .hwp|.hwpx> <output folder> [--chunk N] [--max-pages N]
//   node s2-hwp-render.mjs <rhwp folder> --version
//
// Writes <output folder>/part-0001.html, part-0002.html ... (at most N pages each, default 50) and prints one line
// "pages=<all> rendered=<written> parts=<files>". With --max-pages only the first N pages are written, followed by a
// notice page | 쪽을 N쪽씩(기본 50) part-0001.html ... 로 나눠 쓰고, --max-pages 면 앞 N쪽과 안내 쪽만 쓴다.
//
// Exit codes | 종료 코드: 0 ok, 2 usage, 3 password protected (암호 문서), 4 unreadable or empty (읽을 수 없음)
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const args = process.argv.slice(2);
const option = (name, fallback) => {
    const i = args.indexOf(name);
    if (i < 0) return fallback;
    const value = Number(args[i + 1]);
    args.splice(i, 2);
    if (!Number.isInteger(value) || value < 1) {
        console.error(`s2-hwp-render: ${name} needs a positive number`);
        process.exit(2);
    }
    return value;
};
const chunk = option('--chunk', 50);
const maxPages = option('--max-pages', 0);
const [pkg, input, output] = args;
if (!pkg || !input || (input !== '--version' && !output)) {
    console.error('usage: s2-hwp-render <rhwp folder> <input> <output folder> [--chunk N] [--max-pages N] | <rhwp folder> --version');
    process.exit(2);
}
const rhwp = await import(pathToFileURL(join(pkg, 'rhwp.js')).href);
rhwp.initSync({ module: readFileSync(join(pkg, 'rhwp_bg.wasm')) });
if (input === '--version') {
    console.log('rhwp ' + rhwp.version() + ' (Node.js ' + process.version + ')');
    process.exit(0);
}

let doc;
try {
    doc = new rhwp.HwpDocument(new Uint8Array(readFileSync(input)));
} catch (e) {
    const message = String(e?.message ?? e);
    console.error('s2-hwp-render: ' + message);
    process.exit(/password|암호|encrypt/i.test(message) ? 3 : 4);
}

// Each page is an SVG whose ids (clip paths, patterns) restart from the same names, so they are made unique per
// page before the pages share one HTML document | 쪽마다 id 가 같은 이름으로 다시 시작하므로 한 문서에 모으기 전에 쪽별로 바꿈
function scopeIds(svg, prefix) {
    const ids = new Set();
    for (const m of svg.matchAll(/\sid="([^"]+)"/g)) ids.add(m[1]);
    if (ids.size === 0) return svg;
    const esc = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const any = new RegExp('(\\sid="|url\\(#|href="#)(' + [...ids].map(esc).join('|') + ')(?=[")])', 'g');
    return svg.replace(any, (_, lead, id) => lead + prefix + id);
}

// Page size in CSS px (96 per inch), the unit of the SVG width and height | 쪽 크기 (CSS px, SVG 너비·높이 단위)
function size(svg) {
    const w = /<svg\b[^>]*?\swidth="([\d.]+)"/.exec(svg);
    const h = /<svg\b[^>]*?\sheight="([\d.]+)"/.exec(svg);
    return w && h ? [Number(w[1]), Number(h[1])] : [793.7, 1122.5];
}

function escapeHtml(text) {
    return text.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);
}

const count = doc.pageCount();
if (!count) {
    console.error('s2-hwp-render: no pages');
    process.exit(4);
}
const rendered = maxPages > 0 ? Math.min(count, maxPages) : count;
mkdirSync(output, { recursive: true });

let part = 0;
let pages = [];
let sizes = new Map(); // "WxH" -> named @page, so portrait and landscape pages keep their own size
let lastSize = [793.7, 1122.5];

function addPage(html, w, h) {
    const key = w.toFixed(2) + 'x' + h.toFixed(2);
    if (!sizes.has(key)) sizes.set(key, { name: 's' + sizes.size, w, h });
    pages.push('<div class="page ' + sizes.get(key).name + '">' + html + '</div>');
}

function flush() {
    if (pages.length === 0) return;
    part++;
    const css = [...sizes.values()]
        .map((s) => `@page ${s.name} { size: ${s.w}px ${s.h}px; margin: 0 }\n.${s.name} { page: ${s.name}; width: ${s.w}px; height: ${s.h}px }`)
        .join('\n');
    writeFileSync(join(output, 'part-' + String(part).padStart(4, '0') + '.html'), `<!doctype html>
<html><head><meta charset="utf-8">
<style>
@page { margin: 0 }
html, body { margin: 0; padding: 0 }
.page { overflow: hidden; break-after: page; position: relative }
.page:last-child { break-after: auto }
.page > svg { display: block }
.notice { position: absolute; left: 10%; right: 10%; top: 40%; font: 16px/1.6 'Nanum Gothic', 'Noto Sans CJK KR', sans-serif; text-align: center }
${css}
</style></head>
<body>
${pages.join('\n')}
</body></html>
`);
    pages = [];
    sizes = new Map();
}

for (let i = 0; i < rendered; i++) {
    const svg = scopeIds(doc.renderPageSvg(i).replace(/^<\?xml[^>]*>\s*/, ''), 'p' + i + '-');
    lastSize = size(svg);
    addPage(svg, lastSize[0], lastSize[1]);
    if (pages.length >= chunk) flush();
}
doc.free();
if (rendered < count) {
    // A page that says what was left out, the size of the last page | 생략 안내 쪽 (마지막 쪽과 같은 크기)
    const notice = `※ 변환 한도(${rendered.toLocaleString('en-US')}쪽)를 넘어 이하 ${(count - rendered).toLocaleString('en-US')}쪽은 PDF 에 넣지 않았습니다.<br>전체 내용은 원본 파일에서 확인하십시오. (전체 ${count.toLocaleString('en-US')}쪽)`;
    addPage('<div class="notice">' + escapeHtml(notice).replace(/&lt;br&gt;/g, '<br>') + '</div>', lastSize[0], lastSize[1]);
}
flush();
console.log(`pages=${count} rendered=${rendered} parts=${part}`);
RENDER
    cat >"$1/s2-hwp-convert.sh" <<'CONVERT'
#!/bin/sh
# s2-hwp-convert (s2-office-converter): HWP/HWPX -> PDF inside the container. rhwp lays the pages out as SVG, Chromium
# prints them in parts of S2_HWP_CHUNK pages (default 50) and qpdf joins the parts. Installed by
# setup-s2-office-converter.sh; do not edit inside the image.
# | 컨테이너 안에서 HWP/HWPX → PDF. rhwp 가 쪽을 SVG 로 조판하고, Chromium 이 S2_HWP_CHUNK 쪽씩(기본 50) 나눠 인쇄하고, qpdf 가 합친다.
#
#   s2-hwp-convert <input .hwp|.hwpx> <output .pdf> [--max-pages N]
#   s2-hwp-convert --version
#
# Printing in parts keeps Chromium's memory near 2 GB whatever the page count (a 381-page document printed at once
# took about 4 GB); the time stays proportional to the pages (about 7 per second). S2_HWP_PARALLEL prints that many
# parts at once: faster, with that much more memory | 나눠 인쇄하면 쪽 수와 상관없이 메모리가 약 2GB 안팎 (381쪽을 한 번에
# 인쇄하면 약 4GB). 시간은 쪽 수에 비례 (초당 약 7쪽). S2_HWP_PARALLEL 은 동시에 인쇄할 묶음 수 (빠르지만 메모리도 그만큼 더 씀)
#
# Exit codes are those of s2-hwp-render (2 usage, 3 password protected, 4 unreadable) or 1 when printing fails
# | 종료 코드: 2 사용법, 3 암호 문서, 4 읽을 수 없음, 1 인쇄 실패
set -eu
if [ "${1:-}" = "--version" ]; then
    exec node /opt/s2-hwp/s2-hwp-render.mjs /opt/rhwp --version
fi
[ $# -eq 2 ] || [ $# -eq 4 ] || {
    echo "사용법: s2-hwp-convert <입력 .hwp|.hwpx> <출력 .pdf> [--max-pages N]" >&2
    exit 2
}
input="$1"
output="$2"
limit=""
[ $# -eq 2 ] || limit="$3 $4"
work=/tmp/s2-hwp
mkdir -p "$work/html" "$work/pdf"
# shellcheck disable=SC2086 # limit is "--max-pages N" or empty | limit 은 "--max-pages N" 또는 빈 값
node /opt/s2-hwp/s2-hwp-render.mjs /opt/rhwp "$input" "$work/html" --chunk "${S2_HWP_CHUNK:-50}" $limit >"$work/render.txt"

# The pages have no scripts, so no time budget is needed; Chromium's own D-Bus noise goes to a file shown only on
# failure | 스크립트가 없는 쪽이라 대기 시간 불필요. Chromium 의 D-Bus 경고는 파일로 받아 실패할 때만 보여 줌
print_part() {
    part="$(basename "$1" .html)"
    chromium --headless --no-sandbox --disable-gpu --disable-dev-shm-usage --no-first-run --no-default-browser-check \
        --disable-extensions --disable-background-networking --disable-sync --disable-crash-reporter --mute-audio \
        --hide-scrollbars --no-pdf-header-footer --user-data-dir="$work/chrome-$part" \
        --print-to-pdf="$work/pdf/$part.pdf" "file://$1" >"$work/$part.log" 2>&1 || true
    [ -s "$work/pdf/$part.pdf" ] || {
        grep -v 'dbus' "$work/$part.log" | tail -20 >&2
        return 1
    }
}
parallel="${S2_HWP_PARALLEL:-1}"
if [ "$parallel" -gt 1 ] 2>/dev/null; then
    # POSIX sh has no exported functions: run each part through a small sh -c | POSIX sh 는 함수를 넘길 수 없어 sh -c 로 실행
    ls "$work"/html/part-*.html | xargs -P "$parallel" -I{} sh -c '
        part="$(basename "$1" .html)"
        chromium --headless --no-sandbox --disable-gpu --disable-dev-shm-usage --no-first-run --no-default-browser-check \
            --disable-extensions --disable-background-networking --disable-sync --disable-crash-reporter --mute-audio \
            --hide-scrollbars --no-pdf-header-footer --user-data-dir="'"$work"'/chrome-$part" \
            --print-to-pdf="'"$work"'/pdf/$part.pdf" "file://$1" >"'"$work"'/$part.log" 2>&1 || true
        [ -s "'"$work"'/pdf/$part.pdf" ] || { grep -v dbus "'"$work"'/$part.log" | tail -20 >&2; exit 1; }' sh {} || exit 1
else
    for html in "$work"/html/part-*.html; do
        print_part "$html" || exit 1
    done
fi

set -- "$work"/pdf/part-*.pdf
if [ $# -eq 1 ]; then
    mv -f "$1" "$output"
else
    qpdf --empty --pages "$@" -- "$output"
fi
[ -s "$output" ] || exit 1
cat "$work/render.txt"
CONVERT
}

# 변환기 이미지 빌드 (온라인)
build_image() {
    info "변환기 이미지 ($IMAGE)"
    if [ "$REBUILD" = false ] && podman_target image exists "$IMAGE" 2>/dev/null; then
        skip "이미지가 이미 있습니다 ($TARGET_USER)."
        remove_old_images
        return
    fi
    local build_dir chrome_packages="" rhwp_block=""
    build_dir="$(mktemp -d)"
    CLEANUP_PATHS+=("$build_dir")
    if [ "$WITH_CHROME" = true ]; then
        # Chromium prints web pages and the HWP pages rhwp lays out; Node.js runs rhwp (WebAssembly)
        # | Chromium 은 웹 페이지와 rhwp 가 그린 HWP 쪽을 인쇄하고, Node.js 는 rhwp(WebAssembly)를 실행
        chrome_packages="chromium nodejs qpdf"
        local rhwp_sha512
        rhwp_sha512="$(printf '%s' "${RHWP_INTEGRITY#sha512-}" | base64 -d | od -An -v -tx1 | tr -d ' \n')"
        [ ${#rhwp_sha512} -eq 128 ] || fail "rhwp ${RHWP_VERSION} 의 검증값 형식이 올바르지 않습니다: ${RHWP_INTEGRITY}"
        write_hwp_files "$build_dir"
        rhwp_block="
# rhwp (MIT, https://github.com/edwardkim/rhwp): HWP/HWPX layout to SVG for s2-hwp, verified by SHA-512 (npm integrity)
# | rhwp: s2-hwp 가 쓰는 HWP/HWPX 조판(SVG). npm integrity(SHA-512)로 검증
RUN curl -fsSL -o /tmp/rhwp.tgz https://registry.npmjs.org/@rhwp/core/-/core-${RHWP_VERSION}.tgz \\
 && echo \"${rhwp_sha512}  /tmp/rhwp.tgz\" | sha512sum -c - \\
 && mkdir -p /opt/rhwp \\
 && tar -xzf /tmp/rhwp.tgz -C /opt/rhwp --strip-components=1 --no-same-owner \\
 && chmod -R a+rX /opt/rhwp \\
 && find /tmp -mindepth 1 -delete
COPY s2-hwp-render.mjs s2-hwp-convert.sh /opt/s2-hwp/
RUN chmod 755 /opt/s2-hwp /opt/s2-hwp/s2-hwp-convert.sh && chmod 644 /opt/s2-hwp/s2-hwp-render.mjs
"
    fi
    cat >"$build_dir/Containerfile" <<CONTAINERFILE
FROM ${BASE_IMAGE}

# LibreOffice without GUI, Java for the H2Orestart extension, Korean/CJK fonts and metric-compatible fonts for MS Office
# documents (Calibri, Cambria, Arial, Times New Roman ...) | GUI 없는 LibreOffice, H2Orestart 용 Java, 한글·CJK 폰트,
# MS 오피스 문서 모양 유지를 위한 글자 폭 호환 폰트
RUN apt-get update \\
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \\
      libreoffice-writer-nogui libreoffice-calc-nogui libreoffice-impress-nogui libreoffice-java-common \\
      default-jre-headless \\
      fonts-nanum fonts-noto-cjk fonts-liberation2 fonts-crosextra-carlito fonts-crosextra-caladea \\
      ca-certificates curl coreutils ${chrome_packages} \\
 && rm -rf /var/lib/apt/lists/*

# H2Orestart (MIT, https://github.com/ebandal/H2Orestart): pinned version, verified by SHA-256
RUN curl -fsSL -o /tmp/H2Orestart.oxt \\
      https://github.com/ebandal/H2Orestart/releases/download/v${H2ORESTART_VERSION}/H2Orestart.oxt \\
 && echo "${H2ORESTART_SHA256}  /tmp/H2Orestart.oxt" | sha256sum -c - \\
 && HOME=/tmp unopkg add --shared /tmp/H2Orestart.oxt \\
 && unopkg list --shared | grep -qi h2o \\
 && find /tmp -mindepth 1 -delete
${rhwp_block}
# /tmp is HOME at run time and is copied into each container, so it must start empty (root-owned leftovers from the
# install above would block the converting account) | /tmp 는 실행 시 HOME 이고 컨테이너마다 복사되므로 비어 있어야 함
# (위 설치의 root 소유 잔여물이 있으면 변환 계정이 쓰지 못함)

LABEL org.opencontainers.image.title="s2-office-converter" \\
      org.opencontainers.image.description="LibreOffice + H2Orestart + rhwp + Korean fonts for s2-docflow" \\
      s2.image.revision="${IMAGE_REVISION}" \\
      s2.h2orestart.version="${H2ORESTART_VERSION}" \\
      s2.rhwp.version="${RHWP_VERSION}" \\
      s2.chromium="${WITH_CHROME}"

# Java ignores HOME and takes user.home from /etc/passwd (/root, read-only and not the converting account's). H2Orestart
# keeps its working files under user.home, and without a writable one it drops the pictures of HWP documents
# | Java 는 HOME 대신 /etc/passwd 의 홈(/root: 읽기 전용, 변환 계정 소유 아님)을 user.home 으로 쓴다. H2Orestart 는 작업
# 파일을 user.home 아래에 두므로, 쓸 수 없으면 HWP 문서의 그림이 빠진다
ENV HOME=/tmp LANG=C.UTF-8 JAVA_TOOL_OPTIONS=-Duser.home=/tmp
WORKDIR /work
CONTAINERFILE
    chmod 755 "$build_dir"
    chmod 644 "$build_dir/Containerfile"
    [ "$WITH_CHROME" = false ] || chmod 644 "$build_dir/s2-hwp-render.mjs" "$build_dir/s2-hwp-convert.sh"
    info "이미지를 만듭니다. 처음에는 LibreOffice 를 받느라 몇 분 걸립니다..."
    podman_target build --pull=newer -t "$IMAGE" "$build_dir"
    ok "이미지 생성: $IMAGE ($TARGET_USER)"
    remove_old_images
}

# 이전 버전 이미지 정리
remove_old_images() {
    local image old_images
    mapfile -t old_images < <(podman_target images --format '{{.Repository}}:{{.Tag}}' | grep "^${IMAGE_NAME}:" | grep -vx "$IMAGE" || true)
    for image in "${old_images[@]+"${old_images[@]}"}"; do
        podman_target rmi -f "$image" >/dev/null && ok "이전 이미지 정리: $image"
    done
}

# s2-soffice 명령
install_wrapper() {
    info "s2-soffice 명령 ($WRAPPER_PATH)"
    local wrapper_tmp
    wrapper_tmp="$(mktemp)"
    CLEANUP_PATHS+=("$wrapper_tmp")
    cat >"$wrapper_tmp" <<'WRAPPER'
#!/usr/bin/env bash
# s2-soffice: LibreOffice(soffice) 호환 변환 명령. Podman 컨테이너(s2-office-converter)에서 변환합니다.
# _devtools2/scripts/linux/setup-projects/s2/s2-office-converter/setup-s2-office-converter.sh 가 설치합니다.
# 직접 고치지 마십시오 (다시 실행하면 덮어씀).
#
# 지원하는 형식 (s2-docflow 가 쓰는 부분):
#   s2-soffice --headless --convert-to <형식[:필터]> [--infilter=<필터>] --outdir <출력 폴더> <입력 파일>
#   s2-soffice --version
#
# 환경 변수:
#   S2_SOFFICE_TIMEOUT  변환 제한 시간(초, 기본 180)
#   S2_SOFFICE_MEMORY   컨테이너 메모리 상한 (예: 1g, 지정할 때만. cgroup v2 위임이 있어야 함)
#   S2_SOFFICE_CPUS     컨테이너 CPU 상한 (예: 1.5, 지정할 때만)
set -euo pipefail

IMAGE="@IMAGE@"
TIMEOUT="${S2_SOFFICE_TIMEOUT:-180}"
# Optional resource limits; rootless accounts without cgroup delegation cannot use them, so they are opt-in
# | 선택 자원 상한. cgroup 위임이 없는 rootless 계정은 쓸 수 없으므로 지정할 때만 적용
limits=()
[ -z "${S2_SOFFICE_MEMORY:-}" ] || limits+=(--memory "$S2_SOFFICE_MEMORY" --memory-swap "$S2_SOFFICE_MEMORY")
[ -z "${S2_SOFFICE_CPUS:-}" ] || limits+=(--cpus "$S2_SOFFICE_CPUS")

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[ -d "$runtime_dir" ] && [ -w "$runtime_dir" ] || runtime_dir="/tmp/podman-run-$(id -u)"
mkdir -p "$runtime_dir"
export XDG_RUNTIME_DIR="$runtime_dir"
podman_cmd=(podman --cgroup-manager=cgroupfs --events-backend=file)

if [ "${1:-}" = "--version" ]; then
    exec "${podman_cmd[@]}" run --rm --network=none "$IMAGE" soffice --version
fi

convert_to=""
infilter=""
outdir=""
input=""
while [ $# -gt 0 ]; do
    case "$1" in
    --headless | --norestore | --nologo | --nodefault | --nolockcheck | --invisible) shift ;;
    -env:*) shift ;; # Each conversion runs in a fresh container, so no profile option is needed | 매번 새 컨테이너라 프로필 옵션 불필요
    --convert-to)
        convert_to="${2:?--convert-to 다음에 형식이 필요합니다}"
        shift 2
        ;;
    --outdir)
        outdir="${2:?--outdir 다음에 폴더가 필요합니다}"
        shift 2
        ;;
    --infilter=*)
        infilter="$1"
        shift
        ;;
    -*)
        echo "s2-soffice: 지원하지 않는 옵션입니다: $1" >&2
        exit 2
        ;;
    *)
        [ -z "$input" ] || {
            echo "s2-soffice: 입력 파일은 하나만 받습니다." >&2
            exit 2
        }
        input="$1"
        shift
        ;;
    esac
done
[ -n "$convert_to" ] && [ -n "$input" ] || {
    echo "사용법: s2-soffice --headless --convert-to pdf --outdir <폴더> <파일>" >&2
    exit 2
}
[ -f "$input" ] || {
    echo "s2-soffice: 입력 파일이 없습니다: $input" >&2
    exit 1
}
outdir="${outdir:-$(pwd)}"
mkdir -p "$outdir"

# Only a private copy is mounted, never the caller's folders | 호출자 폴더가 아닌 전용 사본만 컨테이너에 연결
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/in" "$work/out"
name="$(basename "$input")"
cp -- "$input" "$work/in/$name"

args=(soffice --headless --norestore --nolockcheck --convert-to "$convert_to" --outdir /work/out)
[ -z "$infilter" ] || args+=("$infilter")
args+=("/work/in/$name")

# No network, read-only root (/tmp stays writable), no capabilities, the caller's uid (results stay owned by the
# caller), time limit. Memory/CPU limits only when S2_SOFFICE_MEMORY/S2_SOFFICE_CPUS are set (cgroup delegation needed)
# | 네트워크 없음, 읽기 전용 루트(/tmp 는 쓰기 가능), 권한 없음, 호출자 uid(결과 파일 소유자 유지), 시간 제한.
# 메모리·CPU 상한은 S2_SOFFICE_MEMORY / S2_SOFFICE_CPUS 를 지정할 때만 (cgroup 위임 필요)
# Stop the container when the caller gives up (S2DocFlow sends SIGTERM on its time limit). Bash runs a trap only
# after a foreground command ends, so the container runs in the background and the script waits for it
# | 호출자가 포기하면(S2DocFlow 는 제한 시간에 SIGTERM) 컨테이너를 멈춘다. bash 는 전면 명령이 끝나야 trap 을 실행하므로
# 컨테이너는 백그라운드로 돌리고 기다린다
container="s2-soffice-$$-${RANDOM}"
trap '"${podman_cmd[@]}" kill "$container" >/dev/null 2>&1 || true; exit 143' TERM INT
"${podman_cmd[@]}" run --rm --name "$container" ${limits[@]+"${limits[@]}"} \
    --network=none --read-only \
    --cap-drop=ALL --security-opt=no-new-privileges \
    --userns=keep-id \
    -v "$work/in:/work/in:ro,Z" -v "$work/out:/work/out:rw,Z" \
    "$IMAGE" timeout --kill-after=5 "$TIMEOUT" "${args[@]}" &
wait "$!"

shopt -s nullglob
results=("$work/out/"*)
[ ${#results[@]} -gt 0 ] || {
    echo "s2-soffice: 변환 결과가 없습니다 (지원하지 않는 형식이거나 변환 필터가 없음): $name" >&2
    exit 1
}
for result in "${results[@]}"; do
    mv -f -- "$result" "$outdir/"
done
WRAPPER
    sed -i "s|@IMAGE@|${IMAGE}|" "$wrapper_tmp"
    if [ -f "$WRAPPER_PATH" ] && cmp -s "$wrapper_tmp" "$WRAPPER_PATH"; then
        skip "s2-soffice 가 최신입니다."
    else
        "${SUDO[@]}" install -m 0755 "$wrapper_tmp" "$WRAPPER_PATH"
        ok "설치: $WRAPPER_PATH"
    fi
}

# s2-chrome 명령 (웹 페이지 → PDF). --no-chrome 이면 제거
install_chrome_wrapper() {
    info "s2-chrome 명령 ($CHROME_WRAPPER_PATH)"
    if [ "$WITH_CHROME" = false ]; then
        if [ -f "$CHROME_WRAPPER_PATH" ]; then
            "${SUDO[@]}" rm -f "$CHROME_WRAPPER_PATH"
            ok "제거: $CHROME_WRAPPER_PATH (--no-chrome)"
        else
            skip "Chromium 없이 설치합니다 (--no-chrome)."
        fi
        return
    fi
    local wrapper_tmp
    wrapper_tmp="$(mktemp)"
    CLEANUP_PATHS+=("$wrapper_tmp")
    cat >"$wrapper_tmp" <<'WRAPPER'
#!/usr/bin/env bash
# s2-chrome: 이미지·CSS 를 모두 넣은 HTML 파일을 Chromium 으로 PDF 인쇄합니다. Podman 컨테이너(s2-office-converter)에서 실행합니다.
# _devtools2/scripts/linux/setup-projects/s2/s2-office-converter/setup-s2-office-converter.sh 가 설치합니다.
# 직접 고치지 마십시오 (다시 실행하면 덮어씀).
#
#   s2-chrome --print-to-pdf <출력 PDF> <입력 HTML>
#   s2-chrome --version
#
# 네트워크가 없는 컨테이너에서 실행하므로 페이지의 JavaScript 도 밖(내부망 포함)에 접속하지 못합니다.
# Chromium 자체 샌드박스는 rootless 컨테이너 안에서 쓸 수 없어 끄고(--no-sandbox), 컨테이너(네트워크 없음, 읽기 전용,
# 권한 없음, 호출자 uid)가 격리를 맡습니다.
#
# 환경 변수:
#   S2_CHROME_TIMEOUT  인쇄 제한 시간(초, 기본 60)
#   S2_CHROME_MEMORY   컨테이너 메모리 상한 (예: 1g, 지정할 때만. cgroup v2 위임이 있어야 함)
#   S2_CHROME_CPUS     컨테이너 CPU 상한 (예: 1.5, 지정할 때만)
set -euo pipefail

IMAGE="@IMAGE@"
TIMEOUT="${S2_CHROME_TIMEOUT:-60}"
limits=()
[ -z "${S2_CHROME_MEMORY:-}" ] || limits+=(--memory "$S2_CHROME_MEMORY" --memory-swap "$S2_CHROME_MEMORY")
[ -z "${S2_CHROME_CPUS:-}" ] || limits+=(--cpus "$S2_CHROME_CPUS")

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[ -d "$runtime_dir" ] && [ -w "$runtime_dir" ] || runtime_dir="/tmp/podman-run-$(id -u)"
mkdir -p "$runtime_dir"
export XDG_RUNTIME_DIR="$runtime_dir"
podman_cmd=(podman --cgroup-manager=cgroupfs --events-backend=file)

if [ "${1:-}" = "--version" ]; then
    exec "${podman_cmd[@]}" run --rm --network=none "$IMAGE" chromium --version
fi
if [ "${1:-}" != "--print-to-pdf" ] || [ $# -ne 3 ]; then
    echo "사용법: s2-chrome --print-to-pdf <출력 PDF> <입력 HTML>" >&2
    exit 2
fi
output="$2"
input="$3"
[ -f "$input" ] || {
    echo "s2-chrome: 입력 파일이 없습니다: $input" >&2
    exit 1
}

# Only a private copy is mounted | 전용 사본만 컨테이너에 연결
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/in" "$work/out"
cp -- "$input" "$work/in/page.html"

# Stop the container when the caller gives up (S2DocFlow sends SIGTERM on its time limit). Bash runs a trap only
# after a foreground command ends, so the container runs in the background and the script waits for it
# | 호출자가 포기하면(S2DocFlow 는 제한 시간에 SIGTERM) 컨테이너를 멈춘다. bash 는 전면 명령이 끝나야 trap 을 실행하므로
# 컨테이너는 백그라운드로 돌리고 기다린다
container="s2-chrome-$$-${RANDOM}"
trap '"${podman_cmd[@]}" kill "$container" >/dev/null 2>&1 || true; exit 143' TERM INT
"${podman_cmd[@]}" run --rm --name "$container" ${limits[@]+"${limits[@]}"} \
    --network=none --read-only \
    --cap-drop=ALL --security-opt=no-new-privileges \
    --userns=keep-id \
    -v "$work/in:/work/in:ro,Z" -v "$work/out:/work/out:rw,Z" \
    "$IMAGE" timeout --kill-after=5 "$TIMEOUT" chromium --headless --no-sandbox --disable-gpu \
    --disable-dev-shm-usage --no-first-run --no-default-browser-check --disable-extensions \
    --disable-background-networking --disable-sync --disable-crash-reporter --mute-audio --hide-scrollbars \
    --no-pdf-header-footer --user-data-dir=/tmp/chrome --virtual-time-budget=10000 \
    --print-to-pdf=/work/out/page.pdf file:///work/in/page.html >&2 &
wait "$!"

[ -s "$work/out/page.pdf" ] || {
    echo "s2-chrome: 인쇄 결과가 없습니다." >&2
    exit 1
}
mv -f -- "$work/out/page.pdf" "$output"
WRAPPER
    sed -i "s|@IMAGE@|${IMAGE}|" "$wrapper_tmp"
    if [ -f "$CHROME_WRAPPER_PATH" ] && cmp -s "$wrapper_tmp" "$CHROME_WRAPPER_PATH"; then
        skip "s2-chrome 이 최신입니다."
    else
        "${SUDO[@]}" install -m 0755 "$wrapper_tmp" "$CHROME_WRAPPER_PATH"
        ok "설치: $CHROME_WRAPPER_PATH"
    fi
}

# s2-hwp 명령 (한글 문서 → PDF, rhwp 조판 + Chromium 인쇄). --no-chrome 이면 제거
install_hwp_wrapper() {
    info "s2-hwp 명령 ($HWP_WRAPPER_PATH)"
    if [ "$WITH_CHROME" = false ]; then
        if [ -f "$HWP_WRAPPER_PATH" ]; then
            "${SUDO[@]}" rm -f "$HWP_WRAPPER_PATH"
            ok "제거: $HWP_WRAPPER_PATH (--no-chrome: 한글 문서는 LibreOffice + H2Orestart 로 변환)"
        else
            skip "Chromium 없이 설치하므로 s2-hwp 를 두지 않습니다 (한글 문서는 LibreOffice + H2Orestart 로 변환)."
        fi
        return
    fi
    local wrapper_tmp
    wrapper_tmp="$(mktemp)"
    CLEANUP_PATHS+=("$wrapper_tmp")
    cat >"$wrapper_tmp" <<'WRAPPER'
#!/usr/bin/env bash
# s2-hwp: 한글(HWP, HWPX) 문서를 PDF 로 변환합니다. Podman 컨테이너(s2-office-converter)에서 rhwp 로 쪽을 조판하고
# Chromium 으로 인쇄합니다. 한글 프로그램과 같은 쪽 나눔·글꼴 대체(나눔·Noto 명조/고딕)를 따르므로 LibreOffice +
# H2Orestart 보다 원본에 가깝습니다. s2-docflow 의 S2OfficeConverter 는 이 명령이 있으면 한글 문서에 먼저 쓰고,
# 실패하면 s2-soffice(LibreOffice)로 다시 변환합니다.
# _devtools2/scripts/linux/setup-projects/s2/s2-office-converter/setup-s2-office-converter.sh 가 설치합니다.
# 직접 고치지 마십시오 (다시 실행하면 덮어씀).
#
#   s2-hwp --outdir <출력 폴더> [--max-pages N] <입력 .hwp|.hwpx>    → <출력 폴더>/<입력 이름>.pdf
#     --max-pages N  앞 N쪽과 "이하 M쪽 생략" 안내 쪽만 만듦 (아주 큰 문서의 변환 시간을 묶어 둠)
#   s2-hwp --version
#
# 종료 코드: 0 성공, 2 사용법 오류, 3 암호가 걸린 문서, 4 읽을 수 없는 문서, 그 밖 변환 실패
#
# 환경 변수:
#   S2_HWP_TIMEOUT  변환 제한 시간(초, 기본 180)
#   S2_HWP_MEMORY   컨테이너 메모리 상한 (예: 1g, 지정할 때만. cgroup v2 위임이 있어야 함)
#   S2_HWP_CPUS     컨테이너 CPU 상한 (예: 1.5, 지정할 때만)
#   S2_HWP_CHUNK    한 번에 인쇄할 쪽 수 (기본 50). 쪽을 나눠 인쇄해 Chromium 메모리를 약 2GB 안팎으로 유지 (381쪽을 한 번에 인쇄하면 약 4GB)
#   S2_HWP_PARALLEL 동시에 인쇄할 묶음 수 (기본 1). 2~3 이면 큰 문서가 그만큼 빨라지지만 메모리도 그만큼 더 씀
set -euo pipefail

IMAGE="@IMAGE@"
TIMEOUT="${S2_HWP_TIMEOUT:-180}"
limits=()
[ -z "${S2_HWP_MEMORY:-}" ] || limits+=(--memory "$S2_HWP_MEMORY" --memory-swap "$S2_HWP_MEMORY")
[ -z "${S2_HWP_CPUS:-}" ] || limits+=(--cpus "$S2_HWP_CPUS")

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[ -d "$runtime_dir" ] && [ -w "$runtime_dir" ] || runtime_dir="/tmp/podman-run-$(id -u)"
mkdir -p "$runtime_dir"
export XDG_RUNTIME_DIR="$runtime_dir"
podman_cmd=(podman --cgroup-manager=cgroupfs --events-backend=file)

if [ "${1:-}" = "--version" ]; then
    exec "${podman_cmd[@]}" run --rm --network=none --read-only --userns=keep-id "$IMAGE" /opt/s2-hwp/s2-hwp-convert.sh --version
fi

outdir=""
input=""
max_pages=()
while [ $# -gt 0 ]; do
    case "$1" in
    --outdir)
        outdir="${2:?--outdir 다음에 폴더가 필요합니다}"
        shift 2
        ;;
    --max-pages)
        case "${2:-}" in
        '' | *[!0-9]* | 0)
            echo "s2-hwp: --max-pages 다음에 1 이상의 숫자가 필요합니다." >&2
            exit 2
            ;;
        esac
        max_pages=(--max-pages "$2")
        shift 2
        ;;
    -*)
        echo "s2-hwp: 지원하지 않는 옵션입니다: $1" >&2
        exit 2
        ;;
    *)
        [ -z "$input" ] || {
            echo "s2-hwp: 입력 파일은 하나만 받습니다." >&2
            exit 2
        }
        input="$1"
        shift
        ;;
    esac
done
[ -n "$input" ] || {
    echo "사용법: s2-hwp --outdir <폴더> <파일.hwp|hwpx>" >&2
    exit 2
}
[ -f "$input" ] || {
    echo "s2-hwp: 입력 파일이 없습니다: $input" >&2
    exit 1
}
name="$(basename "$input")"
case "${name##*.}" in
hwp | HWP | hwpx | HWPX) ;;
*)
    echo "s2-hwp: 한글 문서(.hwp, .hwpx)만 변환합니다: $name" >&2
    exit 2
    ;;
esac
outdir="${outdir:-$(pwd)}"
mkdir -p "$outdir"

# Only a private copy is mounted, never the caller's folders | 호출자 폴더가 아닌 전용 사본만 컨테이너에 연결
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/in" "$work/out"
extension="$(printf '%s' "${name##*.}" | tr 'A-Z' 'a-z')"
cp -- "$input" "$work/in/document.$extension"

# Same isolation as s2-soffice: no network, read-only root (/tmp stays writable), no capabilities, the caller's uid,
# time limit; stop the container when the caller gives up (SIGTERM) | s2-soffice 와 같은 격리. 호출자가 포기하면 컨테이너를 멈춤
container="s2-hwp-$$-${RANDOM}"
trap '"${podman_cmd[@]}" kill "$container" >/dev/null 2>&1 || true; exit 143' TERM INT
set +e
"${podman_cmd[@]}" run --rm --name "$container" ${limits[@]+"${limits[@]}"} \
    --network=none --read-only \
    --cap-drop=ALL --security-opt=no-new-privileges \
    --userns=keep-id \
    -v "$work/in:/work/in:ro,Z" -v "$work/out:/work/out:rw,Z" \
    -e S2_HWP_CHUNK="${S2_HWP_CHUNK:-50}" -e S2_HWP_PARALLEL="${S2_HWP_PARALLEL:-1}" \
    "$IMAGE" timeout --kill-after=5 "$TIMEOUT" /opt/s2-hwp/s2-hwp-convert.sh "/work/in/document.$extension" /work/out/document.pdf \
    ${max_pages[@]+"${max_pages[@]}"} &
wait "$!"
status=$?
set -e
[ "$status" -eq 0 ] || exit "$status"
[ -s "$work/out/document.pdf" ] || {
    echo "s2-hwp: 변환 결과가 없습니다: $name" >&2
    exit 1
}
mv -f -- "$work/out/document.pdf" "$outdir/${name%.*}.pdf"
WRAPPER
    sed -i "s|@IMAGE@|${IMAGE}|" "$wrapper_tmp"
    if [ -f "$HWP_WRAPPER_PATH" ] && cmp -s "$wrapper_tmp" "$HWP_WRAPPER_PATH"; then
        skip "s2-hwp 가 최신입니다."
    else
        "${SUDO[@]}" install -m 0755 "$wrapper_tmp" "$HWP_WRAPPER_PATH"
        ok "설치: $HWP_WRAPPER_PATH"
    fi
}

# 동작 확인 (대상 계정으로 실제 변환)
verify() {
    info "동작 확인 ($TARGET_USER)"
    local check_dir
    check_dir="$(as_target mktemp -d)"
    as_target sh -c 'printf "s2-office-converter 확인 한글 ABC\n" > "$1/check.txt"' sh "$check_dir"
    if as_target "$WRAPPER_PATH" --headless --convert-to pdf --outdir "$check_dir" "$check_dir/check.txt" >/dev/null 2>&1 &&
        as_target test -s "$check_dir/check.pdf"; then
        ok "변환 확인: 텍스트 → PDF"
    else
        as_target rm -rf "$check_dir"
        fail "변환 확인 실패. 'sudo -u $TARGET_USER $WRAPPER_PATH --headless --convert-to pdf --outdir /tmp <파일>' 로 오류를 확인하십시오."
    fi
    as_target rm -rf "$check_dir"
    # Capture first: with pipefail, grep -q quitting early would fail the pipeline through SIGPIPE
    # | 먼저 받아 둠: pipefail 에서 grep -q 가 일찍 끝나면 SIGPIPE 로 파이프라인이 실패함
    local extensions
    extensions="$(podman_target run --rm --network=none "$IMAGE" unopkg list --shared 2>/dev/null || true)"
    if grep -qi h2orestart <<<"$extensions"; then
        ok "한글(hwp, hwpx) 확장: H2Orestart ${H2ORESTART_VERSION}"
    else
        warn "H2Orestart 가 확인되지 않습니다. --rebuild 로 이미지를 다시 만드십시오."
    fi
    [ "$WITH_CHROME" = true ] || return 0
    local hwp_version
    if hwp_version="$(as_target "$HWP_WRAPPER_PATH" --version 2>/dev/null)" && [ -n "$hwp_version" ]; then
        ok "한글 문서 조판: ${hwp_version} (s2-hwp)"
    else
        fail "s2-hwp 확인 실패. 'sudo -u $TARGET_USER $HWP_WRAPPER_PATH --version' 으로 오류를 확인하십시오."
    fi
    local web_dir
    web_dir="$(as_target mktemp -d)"
    as_target sh -c 'printf "<!doctype html><meta charset=utf-8><div style=\"display:flex\"><p>s2-chrome 확인 한글</p></div>" > "$1/page.html"' sh "$web_dir"
    if as_target "$CHROME_WRAPPER_PATH" --print-to-pdf "$web_dir/page.pdf" "$web_dir/page.html" >/dev/null 2>&1 &&
        as_target test -s "$web_dir/page.pdf"; then
        ok "웹 페이지 확인: HTML → PDF ($(podman_target run --rm --network=none "$IMAGE" chromium --version 2>/dev/null | head -1))"
    else
        as_target rm -rf "$web_dir"
        fail "웹 페이지 변환 확인 실패. 'sudo -u $TARGET_USER $CHROME_WRAPPER_PATH --print-to-pdf /tmp/a.pdf <파일.html>' 로 오류를 확인하십시오."
    fi
    as_target rm -rf "$web_dir"
}

done_message() {
    cat <<DONE

🎉 완료. 계정 ${TARGET_USER} 로 실행하는 앱에서 S2OfficeConverter 가 s2-soffice 를 자동으로 찾습니다.
   예) S2DocumentMerger.merge(List.of(PdfSource.ofDocument(Path.of("보고서.hwp")), ...));
   확인) sudo -u ${TARGET_USER} ${WRAPPER_PATH} --version
DONE
    [ "$WITH_CHROME" = false ] || echo "   웹 페이지(URL 로 받은 HTML)는 s2-chrome 으로 화면 그대로 변환합니다. 확인) sudo -u ${TARGET_USER} ${CHROME_WRAPPER_PATH} --version"
    [ "$WITH_CHROME" = false ] || echo "   한글 문서(hwp, hwpx)는 s2-hwp(rhwp)로 먼저 변환하고, 실패하면 s2-soffice 로 변환합니다. 확인) sudo -u ${TARGET_USER} ${HWP_WRAPPER_PATH} --version"
    print_new_checksums
}

# ==============================================================================
# 모드
# ==============================================================================

mode_uninstall() {
    local path
    for path in "$WRAPPER_PATH" "$CHROME_WRAPPER_PATH" "$HWP_WRAPPER_PATH"; do
        if [ -f "$path" ]; then
            "${SUDO[@]}" rm -f "$path"
            ok "제거: $path"
        else
            skip "$(basename "$path") 가 없습니다."
        fi
    done
    if command -v podman >/dev/null 2>&1; then
        local image images
        mapfile -t images < <(podman_target images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "^${IMAGE_NAME}:" || true)
        for image in "${images[@]+"${images[@]}"}"; do
            podman_target rmi -f "$image" >/dev/null && ok "제거: $image ($TARGET_USER)"
        done
        [ ${#images[@]} -gt 0 ] || skip "이미지가 없습니다 ($TARGET_USER)."
    fi
}

mode_install() {
    install_podman_online
    ensure_subids
    select_versions
    build_image
    install_wrapper
    install_chrome_wrapper
    install_hwp_wrapper
    verify
    done_message
}

# 인터넷 되는 PC: 이 스크립트 + 이미지 + 서버용 Podman 패키지를 실행 파일 하나로
mode_export() {
    local out="${EXPORT_FILE:-./${OFFLINE_FILE}}"
    local target="${TARGET_DISTRO:-$(host_distro)}"
    local family distro_img
    family="$(distro_family "$target")" || fail "지원하지 않는 배포판입니다: $target (ubuntu, debian, rockylinux, almalinux, rhel, fedora)"
    distro_img="$(distro_image "$target")" || fail "지원하지 않는 배포판입니다: $target"
    [ -d "$(dirname "$out")" ] || fail "저장할 폴더가 없습니다: $(dirname "$out")"
    info "폐쇄망 설치 파일 만들기: $out (서버: $target, CPU: $ARCH)"

    install_podman_online
    ensure_subids
    select_versions
    build_image

    local stage
    stage="$(mktemp -d -p "$WORK_TMP" s2-office-converter-export.XXXXXX)"
    CLEANUP_PATHS+=("$stage")
    mkdir -p "$stage/payload/podman-packages"

    info "변환기 이미지 저장"
    podman_target save -o "$stage/payload/$IMAGE_ARCHIVE" "$IMAGE"
    ok "저장: $IMAGE ($(du -h "$stage/payload/$IMAGE_ARCHIVE" | cut -f1))"

    info "서버용 Podman 패키지 받기 ($target → $distro_img)"
    local helper_existed=false
    ! podman_target image exists "$distro_img" 2>/dev/null || helper_existed=true
    # Download inside a container of the server's distribution so dependencies match it
    # | 서버와 같은 배포판 컨테이너 안에서 받아야 의존성이 서버에 맞음
    if [ "$family" = apt ]; then
        podman_target run --rm -v "$stage/payload/podman-packages:/out:Z" "$distro_img" sh -c '
            set -e
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --download-only --no-install-recommends podman uidmap slirp4netns >/dev/null
            cp /var/cache/apt/archives/*.deb /out/'
    else
        podman_target run --rm -v "$stage/payload/podman-packages:/out:Z" "$distro_img" sh -c '
            set -e
            dnf install -y -q --downloadonly --downloaddir=/out podman shadow-utils'
    fi
    # Remove the download helper image unless it was already here | 받기용 이미지는 원래 없었으면 지움
    [ "$helper_existed" = true ] || podman_target rmi -f "$distro_img" >/dev/null 2>&1 || true
    ok "패키지: $(find "$stage/payload/podman-packages" -type f | wc -l)개 ($(du -sh "$stage/payload/podman-packages" | cut -f1))"

    cat >"$stage/payload/manifest.env" <<MANIFEST
# s2-office-converter 폐쇄망 설치 파일 정보 (설치할 때 확인합니다)
BUNDLE_TARGET=${target}
BUNDLE_ARCH=${ARCH}
BUNDLE_IMAGE=${IMAGE}
BUNDLE_CHROME=${WITH_CHROME}
BUNDLE_H2ORESTART=${H2ORESTART_VERSION}
BUNDLE_RHWP=${RHWP_VERSION}
BUNDLE_CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
MANIFEST

    # The script itself heads the file: a copy when run from a file, a download when streamed
    # | 파일 앞부분은 이 스크립트: 파일로 실행했으면 복사, 스트리밍 실행이면 다운로드
    if [ -n "$SELF" ]; then
        cp -f "$SELF" "$stage/script.sh"
    else
        curl -fsSL -o "$stage/script.sh" "$SCRIPT_URL"
    fi

    info "파일 하나로 묶기 (압축하느라 몇 분 걸릴 수 있습니다)"
    tar -czf "$stage/payload.tgz" -C "$stage/payload" .
    local sha
    sha="$(sha256sum "$stage/payload.tgz" | cut -d' ' -f1)"
    {
        cat "$stage/script.sh"
        printf '\n%s %s\n' "$PAYLOAD_MARKER" "$sha"
        cat "$stage/payload.tgz"
    } >"$out.part"
    chmod 755 "$out.part"
    mv -f "$out.part" "$out"

    cat <<DONE

🎉 폐쇄망 설치 파일을 만들었습니다: $out ($(du -h "$out" | cut -f1))
   이 파일 하나를 서버에 옮긴 뒤, 서버에서 실행하십시오:
     bash $(basename "$out") --app-user <앱 실행 계정>
   서버 조건: 배포판 ${target}, CPU ${ARCH}, ${WORK_TMP} 여유 공간 $(du -h "$stage/payload" -s | cut -f1) 이상
DONE
}

# 첨부 데이터 (경계 줄 다음부터 끝까지)
payload_stream() {
    tail -n +"$((PAYLOAD_LINE + 1))" "$SELF"
}

# 폐쇄망 서버: 이 파일에 붙은 이미지·패키지로 설치 (인터넷 접속 없음)
mode_offline() {
    info "설치 파일 확인: $SELF"
    [ "$(payload_stream | sha256sum | cut -d' ' -f1)" = "$PAYLOAD_SHA256" ] ||
        fail "설치 파일이 손상되었습니다 (체크섬 불일치). 파일을 다시 옮기십시오."
    ok "체크섬 확인"

    local dir
    dir="$(mktemp -d -p "$WORK_TMP" s2-office-converter.XXXXXX)"
    CLEANUP_PATHS+=("$dir")
    payload_stream | tar -xzf - -C "$dir" || fail "압축을 풀 수 없습니다. $WORK_TMP 의 여유 공간을 확인하십시오 (다른 위치: TMPDIR=<폴더> bash ...)."
    [ -f "$dir/manifest.env" ] && [ -f "$dir/$IMAGE_ARCHIVE" ] || fail "설치 파일의 내용이 올바르지 않습니다. --export 로 다시 만드십시오."

    local BUNDLE_TARGET="" BUNDLE_ARCH="" BUNDLE_IMAGE="" BUNDLE_CHROME="false" BUNDLE_H2ORESTART="" BUNDLE_RHWP=""
    # shellcheck disable=SC1091
    . "$dir/manifest.env"
    [ "$BUNDLE_ARCH" = "$ARCH" ] || fail "CPU 종류가 다릅니다: 설치 파일 $BUNDLE_ARCH, 이 서버 $ARCH. 서버와 같은 CPU 의 PC 에서 다시 만드십시오."
    IMAGE="$BUNDLE_IMAGE"
    WITH_CHROME="$BUNDLE_CHROME"
    H2ORESTART_VERSION="$BUNDLE_H2ORESTART"
    RHWP_VERSION="$BUNDLE_RHWP"

    info "Podman 확인"
    if command -v podman >/dev/null 2>&1; then
        skip "Podman 이 이미 있습니다: $(podman --version)"
    else
        local host
        host="$(host_distro)"
        [ "$host" = "$BUNDLE_TARGET" ] ||
            fail "Podman 패키지는 $BUNDLE_TARGET 용인데 이 서버는 $host 입니다. --target $host 로 설치 파일을 다시 만드십시오."
        shopt -s nullglob
        if [ "$(distro_family "$BUNDLE_TARGET")" = apt ]; then
            local debs=("$dir/podman-packages/"*.deb)
            [ ${#debs[@]} -gt 0 ] || fail "설치 파일에 Podman 패키지가 없습니다."
            # No --no-download: apt 2.7 then fails on local files ("Pathname to install is not absolute"). Every
            # dependency is in the file, so nothing is fetched | --no-download 를 쓰면 apt 2.7 이 로컬 파일에서 실패함. 의존성이
            # 모두 들어 있어 받을 것이 없음
            "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${debs[@]}" >/dev/null
        else
            local rpms=("$dir/podman-packages/"*.rpm)
            [ ${#rpms[@]} -gt 0 ] || fail "설치 파일에 Podman 패키지가 없습니다."
            "${SUDO[@]}" dnf install -y -q --disablerepo='*' "${rpms[@]}"
        fi
        shopt -u nullglob
        ok "Podman 설치 (설치 파일): $(podman --version)"
    fi

    ensure_subids

    info "변환기 이미지 ($IMAGE)"
    if [ "$REBUILD" = false ] && podman_target image exists "$IMAGE" 2>/dev/null; then
        skip "이미지가 이미 있습니다 ($TARGET_USER)."
        remove_old_images
    else
        # The app account must be able to read the extracted image | 앱 실행 계정이 풀어 놓은 이미지를 읽을 수 있어야 함
        chmod 755 "$dir"
        chmod 644 "$dir/$IMAGE_ARCHIVE"
        podman_target load -i "$dir/$IMAGE_ARCHIVE" >/dev/null
        ok "이미지 등록: $IMAGE ($TARGET_USER)"
        remove_old_images
    fi

    install_wrapper
    install_chrome_wrapper
    install_hwp_wrapper
    verify
    done_message
}

case "$MODE" in
install) mode_install ;;
uninstall) mode_uninstall ;;
export) mode_export ;;
offline) mode_offline ;;
esac
# An offline file carries binary data after this line, so the script must stop here
# | 폐쇄망 설치 파일은 이 뒤에 이진 데이터가 붙으므로 여기서 반드시 끝냄
exit 0
