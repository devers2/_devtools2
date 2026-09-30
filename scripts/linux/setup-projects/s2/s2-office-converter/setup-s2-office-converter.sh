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
#   # 3) 폐쇄망 서버 — 인터넷 되는 PC에서 묶음을 만들어 옮긴 뒤 설치
#   #    (인터넷 되는 PC, 서버와 같은 CPU 종류) 서버 배포판·버전을 --target 으로 지정
#   curl -fsSL <위 주소> | bash -s -- --export ./s2-office-converter-offline --target ubuntu:22.04
#   #    (폐쇄망 서버) 옮긴 폴더에서 실행
#   bash ./s2-office-converter-offline/setup-s2-office-converter.sh --import ./s2-office-converter-offline --app-user appuser
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
#   - 확인: sudo -u appuser s2-soffice --version
#
# [하는 일]
# S2PdfUtil(s2-support)이 docx·xlsx·pptx·hwp·hwpx 등을 PDF 로 변환·병합할 수 있도록
# LibreOffice + H2Orestart(한글 확장) + 한글 폰트가 든 Podman 컨테이너 이미지를 만들고,
# 이를 호출하는 명령 s2-soffice 를 설치합니다.
#
#   [앱] S2PdfUtil ──(s2-soffice --headless --convert-to pdf ...)──▶ [Podman 컨테이너]
#                                                                  LibreOffice + H2Orestart + 폰트
#
# 옵션:
#   --app-user 계정    앱 실행 계정(웹 애플리케이션을 실행하는 리눅스 계정). 기본: 이 스크립트를 실행한 계정.
#                      --user 도 같은 뜻으로 받습니다.
#   --rebuild          이미지를 다시 만듭니다 (보안 업데이트 반영 등).
#   --uninstall        s2-soffice 명령과 이미지를 제거합니다 (Podman 자체는 남김).
#   --export [폴더]    폐쇄망용 묶음을 만듭니다 (기본 ./s2-office-converter-offline). 인터넷 되는 PC에서 실행.
#   --target 배포판    --export 에서 서버의 배포판:버전 (예: ubuntu:22.04, ubuntu:24.04, debian:12, rockylinux:9, almalinux:9).
#                      기본: 이 PC 와 같음. 서버에 Podman 을 설치할 패키지를 이 배포판용으로 받습니다.
#   --import 폴더      --export 로 만든 묶음으로 설치합니다. 인터넷에 접속하지 않습니다.
#
# 멱등성: 몇 번을 실행해도 같은 상태가 됩니다. 이미 있는 것은 건너뛰고 없는 것만 준비합니다.
#   - Podman: 없으면 설치 (온라인: apt/dnf, 폐쇄망: 묶음의 패키지)
#   - 대상 계정의 subuid/subgid: 없으면 추가 (rootless Podman 필요 조건)
#   - 이미지: 같은 버전(태그)이 있으면 건너뜀. 버전을 올리면 새로 만들고 이전 버전은 정리
#   - /usr/local/bin/s2-soffice: 내용이 다를 때만 교체
#   - 마지막에 실제 변환으로 동작을 확인
#
# 라이선스: 이 스크립트는 LibreOffice(MPL 2.0), H2Orestart(GPL 3.0), 폰트(SIL OFL 1.1 등), Podman(Apache 2.0)을
# 각 배포처에서 받아 설치할 뿐, 재배포하지 않습니다. 각 소프트웨어는 자체 라이선스를 따릅니다.
# (폐쇄망 묶음을 다른 조직에 전달하면 그 안의 소프트웨어를 배포하는 것이 되므로 각 라이선스를 확인하십시오.)
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# 버전 고정 (올리면 다음 실행 때 이미지를 새로 만듦)
# ------------------------------------------------------------------------------
BASE_IMAGE="docker.io/library/debian:trixie-slim"
H2ORESTART_VERSION="0.7.14"
H2ORESTART_SHA256="cbea23bc37861361bbc534bc0675e5bc67b36f712072490f82a9bf410d7c04d8"
IMAGE_REVISION="1"
IMAGE_NAME="localhost/s2-office-converter"
IMAGE_TAG="${IMAGE_REVISION}-h2o${H2ORESTART_VERSION}"
IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
WRAPPER_PATH="/usr/local/bin/s2-soffice"
SCRIPT_NAME="setup-s2-office-converter.sh"
SCRIPT_URL="https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/setup-projects/s2/s2-office-converter/${SCRIPT_NAME}"
IMAGE_ARCHIVE="s2-office-converter.tar"

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
  --uninstall          s2-soffice 명령과 이미지를 제거 (Podman 은 남김)
  --export [폴더]      폐쇄망용 묶음 만들기 (기본 ./s2-office-converter-offline, 인터넷 되는 PC에서)
  --target 배포판      --export 에서 서버 배포판:버전 (예: ubuntu:22.04, debian:12, rockylinux:9). 기본: 이 PC 와 같음
  --import 폴더        묶음으로 설치 (폐쇄망 서버, 인터넷 접속 없음)
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
EXPORT_DIR=""
IMPORT_DIR=""
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
    --export)
        MODE="export"
        if [ $# -ge 2 ] && [ "${2#--}" = "$2" ]; then
            EXPORT_DIR="$2"
            shift 2
        else
            shift
        fi
        ;;
    --export=*)
        MODE="export"
        EXPORT_DIR="${1#*=}"
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
    --import)
        [ $# -ge 2 ] || fail "--import 다음에 묶음 폴더가 필요합니다."
        MODE="import"
        IMPORT_DIR="$2"
        shift 2
        ;;
    --import=*)
        MODE="import"
        IMPORT_DIR="${1#*=}"
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
            fail "패키지 목록을 받을 수 없습니다. 인터넷이 안 되는 서버라면 --export / --import 로 설치하십시오 (README.md 참고)."
        "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq podman uidmap slirp4netns >/dev/null
    elif command -v dnf >/dev/null 2>&1; then
        "${SUDO[@]}" dnf install -y -q podman shadow-utils ||
            fail "Podman 을 설치할 수 없습니다. 인터넷이 안 되는 서버라면 --export / --import 로 설치하십시오 (README.md 참고)."
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
        return
    fi
    local build_dir
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
      ca-certificates curl coreutils \\
 && rm -rf /var/lib/apt/lists/*

# H2Orestart (GPL 3.0, https://github.com/ebandal/H2Orestart): pinned version, verified by SHA-256
RUN curl -fsSL -o /tmp/H2Orestart.oxt \\
      https://github.com/ebandal/H2Orestart/releases/download/v${H2ORESTART_VERSION}/H2Orestart.oxt \\
 && echo "${H2ORESTART_SHA256}  /tmp/H2Orestart.oxt" | sha256sum -c - \\
 && HOME=/tmp unopkg add --shared /tmp/H2Orestart.oxt \\
 && unopkg list --shared | grep -qi h2o \\
 && rm -rf /tmp/H2Orestart.oxt /tmp/.config

LABEL org.opencontainers.image.title="s2-office-converter" \\
      org.opencontainers.image.description="LibreOffice + H2Orestart + Korean fonts for s2-support S2PdfUtil" \\
      s2.h2orestart.version="${H2ORESTART_VERSION}"

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
    if podman_target run --rm --network=none "$IMAGE" unopkg list --shared 2>/dev/null | grep -qi h2o; then
        ok "한글(hwp, hwpx) 확장: H2Orestart ${H2ORESTART_VERSION}"
    else
        warn "H2Orestart 가 확인되지 않습니다. --rebuild 로 이미지를 다시 만드십시오."
    fi
}

done_message() {
    cat <<DONE

🎉 완료. 계정 ${TARGET_USER} 로 실행하는 앱에서 S2PdfUtil 이 s2-soffice 를 자동으로 찾습니다.
   예) S2PdfUtil.merge(List.of(PdfSource.ofDocument(Path.of("보고서.hwp")), ...));
   확인) sudo -u ${TARGET_USER} ${WRAPPER_PATH} --version
DONE
}

# ==============================================================================
# 모드
# ==============================================================================

mode_uninstall() {
    if [ -f "$WRAPPER_PATH" ]; then
        "${SUDO[@]}" rm -f "$WRAPPER_PATH"
        ok "제거: $WRAPPER_PATH"
    else
        skip "s2-soffice 가 없습니다."
    fi
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
    verify
    done_message
}

# 인터넷 되는 PC: 이미지 + 서버용 Podman 패키지 + 이 스크립트를 한 폴더에
mode_export() {
    local dir="${EXPORT_DIR:-./s2-office-converter-offline}"
    local target="${TARGET_DISTRO:-$(host_distro)}"
    local family distro_img
    family="$(distro_family "$target")" || fail "지원하지 않는 배포판입니다: $target (ubuntu, debian, rockylinux, almalinux, rhel, fedora)"
    distro_img="$(distro_image "$target")" || fail "지원하지 않는 배포판입니다: $target"
    info "폐쇄망 묶음 만들기: $dir (서버: $target, CPU: $ARCH)"

    install_podman_online
    ensure_subids
    build_image

    mkdir -p "$dir/podman-packages"
    dir="$(cd "$dir" && pwd)"

    info "변환기 이미지 저장 ($IMAGE_ARCHIVE)"
    rm -f "$dir/$IMAGE_ARCHIVE"
    podman_target save -o "$dir/$IMAGE_ARCHIVE" "$IMAGE"
    ok "저장: $dir/$IMAGE_ARCHIVE ($(du -h "$dir/$IMAGE_ARCHIVE" | cut -f1))"

    info "서버용 Podman 패키지 받기 ($target → $distro_img)"
    rm -f "$dir/podman-packages/"*
    # Download inside a container of the server's distribution so dependencies match it
    # | 서버와 같은 배포판 컨테이너 안에서 받아야 의존성이 서버에 맞음
    if [ "$family" = apt ]; then
        podman_target run --rm -v "$dir/podman-packages:/out:Z" "$distro_img" sh -c '
            set -e
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --download-only --no-install-recommends podman uidmap slirp4netns >/dev/null
            cp /var/cache/apt/archives/*.deb /out/'
    else
        podman_target run --rm -v "$dir/podman-packages:/out:Z" "$distro_img" sh -c '
            set -e
            dnf install -y -q --downloadonly --downloaddir=/out podman shadow-utils'
    fi
    ok "패키지: $(find "$dir/podman-packages" -type f | wc -l)개 ($(du -sh "$dir/podman-packages" | cut -f1))"

    # The script itself goes into the bundle: a copy when run from a file, a download when streamed
    # | 스크립트 자신을 묶음에: 파일로 실행했으면 복사, 스트리밍 실행이면 다운로드
    if [ -f "${BASH_SOURCE[0]:-}" ]; then
        cp -f "${BASH_SOURCE[0]}" "$dir/$SCRIPT_NAME"
    else
        curl -fsSL -o "$dir/$SCRIPT_NAME" "$SCRIPT_URL"
    fi
    chmod 755 "$dir/$SCRIPT_NAME"

    cat >"$dir/manifest.env" <<MANIFEST
# s2-office-converter 폐쇄망 묶음 (--import 가 확인합니다)
BUNDLE_TARGET=${target}
BUNDLE_ARCH=${ARCH}
BUNDLE_IMAGE=${IMAGE}
BUNDLE_H2ORESTART=${H2ORESTART_VERSION}
BUNDLE_CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
MANIFEST
    (cd "$dir" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS)

    cat <<DONE

🎉 폐쇄망 묶음을 만들었습니다: $dir ($(du -sh "$dir" | cut -f1))
   이 폴더를 통째로 서버에 옮긴 뒤, 서버에서 실행하십시오:
     bash <옮긴 폴더>/$SCRIPT_NAME --import <옮긴 폴더> --app-user <앱 실행 계정>
   서버 조건: 배포판 ${target}, CPU ${ARCH}
DONE
}

# 폐쇄망 서버: 묶음으로 설치 (인터넷 접속 없음)
mode_import() {
    local dir="$IMPORT_DIR"
    [ -d "$dir" ] || fail "묶음 폴더가 없습니다: $dir"
    dir="$(cd "$dir" && pwd)"
    { [ -f "$dir/manifest.env" ] && [ -f "$dir/$IMAGE_ARCHIVE" ]; } || fail "--export 로 만든 묶음 폴더가 아닙니다: $dir"

    info "묶음 확인: $dir"
    (cd "$dir" && sha256sum -c --quiet SHA256SUMS) || fail "묶음 파일이 손상되었거나 바뀌었습니다 (SHA256SUMS 불일치). 다시 옮기십시오."
    ok "체크섬 확인"
    local BUNDLE_TARGET="" BUNDLE_ARCH="" BUNDLE_IMAGE=""
    # shellcheck disable=SC1091
    . "$dir/manifest.env"
    [ "$BUNDLE_ARCH" = "$ARCH" ] || fail "CPU 종류가 다릅니다: 묶음 $BUNDLE_ARCH, 이 서버 $ARCH. 서버와 같은 CPU 의 PC 에서 다시 만드십시오."
    [ "$BUNDLE_IMAGE" = "$IMAGE" ] || warn "묶음의 이미지($BUNDLE_IMAGE)와 이 스크립트의 버전($IMAGE)이 다릅니다. 묶음에 든 스크립트로 실행하십시오."
    IMAGE="$BUNDLE_IMAGE"

    info "Podman 확인"
    if command -v podman >/dev/null 2>&1; then
        skip "Podman 이 이미 있습니다: $(podman --version)"
    else
        local host
        host="$(host_distro)"
        [ "$host" = "$BUNDLE_TARGET" ] ||
            fail "Podman 패키지는 $BUNDLE_TARGET 용인데 이 서버는 $host 입니다. --target $host 로 묶음을 다시 만드십시오."
        shopt -s nullglob
        if [ "$(distro_family "$BUNDLE_TARGET")" = apt ]; then
            local debs=("$dir/podman-packages/"*.deb)
            [ ${#debs[@]} -gt 0 ] || fail "묶음에 Podman 패키지가 없습니다."
            "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-download "${debs[@]}" >/dev/null
        else
            local rpms=("$dir/podman-packages/"*.rpm)
            [ ${#rpms[@]} -gt 0 ] || fail "묶음에 Podman 패키지가 없습니다."
            "${SUDO[@]}" dnf install -y -q --disablerepo='*' "${rpms[@]}"
        fi
        shopt -u nullglob
        ok "Podman 설치 (묶음): $(podman --version)"
    fi

    ensure_subids

    info "변환기 이미지 ($IMAGE)"
    if [ "$REBUILD" = false ] && podman_target image exists "$IMAGE" 2>/dev/null; then
        skip "이미지가 이미 있습니다 ($TARGET_USER)."
    else
        # The app account may not be able to read the operator's folder | 앱 실행 계정은 관리자 폴더를 못 읽을 수 있음
        local shared
        shared="$(mktemp -d)"
        CLEANUP_PATHS+=("$shared")
        cp "$dir/$IMAGE_ARCHIVE" "$shared/"
        chmod 755 "$shared"
        chmod 644 "$shared/$IMAGE_ARCHIVE"
        podman_target load -i "$shared/$IMAGE_ARCHIVE" >/dev/null
        ok "이미지 등록: $IMAGE ($TARGET_USER)"
        remove_old_images
    fi

    install_wrapper
    verify
    done_message
}

case "$MODE" in
install) mode_install ;;
uninstall) mode_uninstall ;;
export) mode_export ;;
import) mode_import ;;
esac
