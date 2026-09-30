#!/usr/bin/env bash
# ==============================================================================
# s2 오피스/한글 문서 변환기 설치 스크립트 (setup-s2-office-converter.sh)
# 위치: _devtools2/scripts/linux/setup-projects/s2/s2-office-converter/  (같은 폴더의 README.md 참고)
# ==============================================================================
#
# [실행 방법] s2-support 를 쓰는 앱과 같은 서버에서, sudo 를 쓸 수 있는 계정으로 실행합니다.
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
#   - 설치가 끝나면 앱을 다시 시작할 필요 없이 S2PdfUtil 이 s2-soffice 를 자동으로 찾습니다.
#   - 확인: sudo -u appuser s2-soffice --version, sudo -u appuser s2-chrome --version
#   - 웹 페이지 변환(Chromium)이 필요 없으면 --no-chrome (이미지 약 0.7GB 작아짐)
#
# [하는 일]
# S2PdfUtil(s2-support)이 docx·xlsx·pptx·hwp·hwpx 등을 PDF 로 변환·병합할 수 있도록
# LibreOffice + H2Orestart(한글 확장) + 한글 폰트가 든 Podman 컨테이너 이미지를 만들고,
# 이를 호출하는 명령 s2-soffice 를 설치합니다. 웹 페이지(URL 로 받은 HTML)를 화면 그대로 PDF 로 만들도록
# Chromium 과 명령 s2-chrome 도 함께 설치합니다 (--no-chrome 으로 뺄 수 있음).
#
#   [앱] S2PdfUtil ──(s2-soffice --headless --convert-to pdf ...)──▶ [Podman 컨테이너]
#                  ──(s2-chrome --print-to-pdf <pdf> <html>)────────▶  LibreOffice + H2Orestart + Chromium + 폰트
#
# 옵션:
#   --app-user 계정    앱 실행 계정(웹 애플리케이션을 실행하는 리눅스 계정). 기본: 이 스크립트를 실행한 계정.
#                      --user 도 같은 뜻으로 받습니다.
#   --rebuild          이미지를 다시 만듭니다 (보안 업데이트 반영 등).
#   --no-chrome        웹 페이지 변환용 Chromium(s2-chrome)을 빼고 설치합니다 (이미지 약 0.7GB 작아짐).
#                      없으면 S2PdfUtil 은 웹 페이지를 내장 렌더러(openhtmltopdf)로 변환합니다.
#   --uninstall        s2-soffice 명령과 이미지를 제거합니다 (Podman 자체는 남김).
#   --export [파일]    폐쇄망용 설치 파일 하나를 만듭니다 (기본 ./setup-s2-office-converter-offline.sh).
#                      인터넷 되는 PC에서 실행. 이 스크립트 뒤에 변환기 이미지와 Podman 설치 파일을 붙인 파일로,
#                      서버에서 그대로 실행하면 인터넷 접속 없이 설치합니다 (옵션은 이 스크립트와 같음).
#   --target 배포판    --export 에서 서버의 배포판:버전 (예: ubuntu:22.04, ubuntu:24.04, debian:12, rockylinux:9, almalinux:9).
#                      기본: 이 PC 와 같음. 서버에 Podman 을 설치할 패키지를 이 배포판용으로 받습니다.
#
# 멱등성: 몇 번을 실행해도 같은 상태가 됩니다. 이미 있는 것은 건너뛰고 없는 것만 준비합니다.
#   - Podman: 없으면 설치 (온라인: apt/dnf, 폐쇄망: 설치 파일에 든 패키지)
#   - 대상 계정의 subuid/subgid: 없으면 추가 (rootless Podman 필요 조건)
#   - 이미지: 같은 버전(태그)이 있으면 건너뜀. 버전을 올리면 새로 만들고 이전 버전은 정리
#   - /usr/local/bin/s2-soffice, s2-chrome: 내용이 다를 때만 교체 (--no-chrome 이면 s2-chrome 제거)
#   - 마지막에 실제 변환으로 동작을 확인
#
# 라이선스: 이 스크립트는 LibreOffice(MPL 2.0), H2Orestart(GPL 3.0), Chromium(BSD 3-Clause 등), 폰트(SIL OFL 1.1 등), Podman(Apache 2.0)을
# 각 배포처에서 받아 설치할 뿐, 재배포하지 않습니다. 각 소프트웨어는 자체 라이선스를 따릅니다.
# (폐쇄망 설치 파일을 다른 조직에 전달하면 그 안의 소프트웨어를 배포하는 것이 되므로 각 라이선스를 확인하십시오.)
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# 버전 고정 (올리면 다음 실행 때 이미지를 새로 만듦)
# ------------------------------------------------------------------------------
BASE_IMAGE="docker.io/library/debian:trixie-slim"
H2ORESTART_VERSION="0.7.14"
H2ORESTART_SHA256="cbea23bc37861361bbc534bc0675e5bc67b36f712072490f82a9bf410d7c04d8"
IMAGE_REVISION="2"
IMAGE_NAME="localhost/s2-office-converter"
WRAPPER_PATH="/usr/local/bin/s2-soffice"
CHROME_WRAPPER_PATH="/usr/local/bin/s2-chrome"
SCRIPT_NAME="setup-s2-office-converter.sh"
SCRIPT_URL="https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/setup-projects/s2/s2-office-converter/${SCRIPT_NAME}"
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
  --no-chrome          웹 페이지 변환용 Chromium(s2-chrome)을 빼고 설치 (이미지 약 0.7GB 작아짐)
  --uninstall          s2-soffice 명령과 이미지를 제거 (Podman 은 남김)
  --export [파일]      폐쇄망용 설치 파일 하나 만들기 (기본 ./setup-s2-office-converter-offline.sh, 인터넷 되는 PC에서)
                       서버에서: bash setup-s2-office-converter-offline.sh --app-user 계정
  --target 배포판      --export 에서 서버 배포판:버전 (예: ubuntu:22.04, debian:12, rockylinux:9). 기본: 이 PC 와 같음
  --help               이 도움말

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

# Image tag per content: with Chromium or without | 이미지 태그는 내용별 (Chromium 포함 여부)
image_for() {
    if [ "$1" = true ]; then
        echo "${IMAGE_NAME}:${IMAGE_REVISION}-h2o${H2ORESTART_VERSION}-chrome"
    else
        echo "${IMAGE_NAME}:${IMAGE_REVISION}-h2o${H2ORESTART_VERSION}"
    fi
}
IMAGE="$(image_for "$WITH_CHROME")"

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
        "${SUDO[@]}" -u "$TARGET_USER" -H env XDG_RUNTIME_DIR="$runtime_dir" sh -c 'mkdir -p "$XDG_RUNTIME_DIR" && exec "$@"' sh "$@"
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

# 변환기 이미지 빌드 (온라인)
build_image() {
    info "변환기 이미지 ($IMAGE)"
    if [ "$REBUILD" = false ] && podman_target image exists "$IMAGE" 2>/dev/null; then
        skip "이미지가 이미 있습니다 ($TARGET_USER)."
        remove_old_images
        return
    fi
    local build_dir chrome_packages=""
    [ "$WITH_CHROME" = false ] || chrome_packages="chromium"
    build_dir="$(mktemp -d)"
    CLEANUP_PATHS+=("$build_dir")
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

# H2Orestart (GPL 3.0, https://github.com/ebandal/H2Orestart): pinned version, verified by SHA-256
RUN curl -fsSL -o /tmp/H2Orestart.oxt \\
      https://github.com/ebandal/H2Orestart/releases/download/v${H2ORESTART_VERSION}/H2Orestart.oxt \\
 && echo "${H2ORESTART_SHA256}  /tmp/H2Orestart.oxt" | sha256sum -c - \\
 && HOME=/tmp unopkg add --shared /tmp/H2Orestart.oxt \\
 && unopkg list --shared | grep -qi h2o \\
 && find /tmp -mindepth 1 -delete

# /tmp is HOME at run time and is copied into each container, so it must start empty (root-owned leftovers from the
# install above would block the converting account) | /tmp 는 실행 시 HOME 이고 컨테이너마다 복사되므로 비어 있어야 함
# (위 설치의 root 소유 잔여물이 있으면 변환 계정이 쓰지 못함)

LABEL org.opencontainers.image.title="s2-office-converter" \\
      org.opencontainers.image.description="LibreOffice + H2Orestart + Korean fonts for s2-support S2PdfUtil" \\
      s2.h2orestart.version="${H2ORESTART_VERSION}" \\
      s2.chromium="${WITH_CHROME}"

ENV HOME=/tmp LANG=C.UTF-8
WORKDIR /work
CONTAINERFILE
    chmod 755 "$build_dir"
    chmod 644 "$build_dir/Containerfile"
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
# 지원하는 형식 (S2PdfUtil 이 쓰는 부분):
#   s2-soffice --headless --convert-to <형식[:필터]> [--infilter=<필터>] --outdir <출력 폴더> <입력 파일>
#   s2-soffice --version
#
# 환경 변수:
#   S2_SOFFICE_TIMEOUT  변환 제한 시간(초, 기본 180)
set -euo pipefail

IMAGE="@IMAGE@"
TIMEOUT="${S2_SOFFICE_TIMEOUT:-180}"

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
# caller), time limit. No cgroup limits: rootless service accounts often have no cgroup delegation
# | 네트워크 없음, 읽기 전용 루트(/tmp 는 쓰기 가능), 권한 없음, 호출자 uid(결과 파일 소유자 유지), 시간 제한.
# cgroup 제한은 쓰지 않음 (rootless 서비스 계정은 cgroup 위임이 없는 경우가 많음)
"${podman_cmd[@]}" run --rm \
    --network=none --read-only \
    --cap-drop=ALL --security-opt=no-new-privileges \
    --userns=keep-id \
    -v "$work/in:/work/in:ro,Z" -v "$work/out:/work/out:rw,Z" \
    "$IMAGE" timeout --kill-after=5 "$TIMEOUT" "${args[@]}"

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
set -euo pipefail

IMAGE="@IMAGE@"
TIMEOUT="${S2_CHROME_TIMEOUT:-60}"

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

"${podman_cmd[@]}" run --rm \
    --network=none --read-only \
    --cap-drop=ALL --security-opt=no-new-privileges \
    --userns=keep-id \
    -v "$work/in:/work/in:ro,Z" -v "$work/out:/work/out:rw,Z" \
    "$IMAGE" timeout --kill-after=5 "$TIMEOUT" chromium --headless --no-sandbox --disable-gpu \
    --disable-dev-shm-usage --no-first-run --no-default-browser-check --disable-extensions \
    --disable-background-networking --disable-sync --disable-crash-reporter --mute-audio --hide-scrollbars \
    --no-pdf-header-footer --user-data-dir=/tmp/chrome --virtual-time-budget=10000 \
    --print-to-pdf=/work/out/page.pdf file:///work/in/page.html >&2

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

🎉 완료. 계정 ${TARGET_USER} 로 실행하는 앱에서 S2PdfUtil 이 s2-soffice 를 자동으로 찾습니다.
   예) S2PdfUtil.merge(List.of(PdfSource.ofDocument(Path.of("보고서.hwp")), ...));
   확인) sudo -u ${TARGET_USER} ${WRAPPER_PATH} --version
DONE
    [ "$WITH_CHROME" = false ] || echo "   웹 페이지(URL 로 받은 HTML)는 s2-chrome 으로 화면 그대로 변환합니다. 확인) sudo -u ${TARGET_USER} ${CHROME_WRAPPER_PATH} --version"
}

# ==============================================================================
# 모드
# ==============================================================================

mode_uninstall() {
    local path
    for path in "$WRAPPER_PATH" "$CHROME_WRAPPER_PATH"; do
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
    build_image
    install_wrapper
    install_chrome_wrapper
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

    local BUNDLE_TARGET="" BUNDLE_ARCH="" BUNDLE_IMAGE="" BUNDLE_CHROME="false"
    # shellcheck disable=SC1091
    . "$dir/manifest.env"
    [ "$BUNDLE_ARCH" = "$ARCH" ] || fail "CPU 종류가 다릅니다: 설치 파일 $BUNDLE_ARCH, 이 서버 $ARCH. 서버와 같은 CPU 의 PC 에서 다시 만드십시오."
    IMAGE="$BUNDLE_IMAGE"
    WITH_CHROME="$BUNDLE_CHROME"

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
            "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-download "${debs[@]}" >/dev/null
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
