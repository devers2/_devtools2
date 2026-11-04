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
#   # 고객사 보유 글꼴(맑은 고딕·휴먼명조 등) 폴더 연결 — 한 번 지정하면 다시 실행해도 유지
#   curl -fsSL <위 주소> | bash -s -- --app-user appuser --font-dir /opt/s2-fonts
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
#   - 글꼴은 이미지에 넣지 않습니다. 보유 글꼴은 --font-dir 로 연결하고, 폐쇄망 서버에는 글꼴 폴더를 따로 옮겨 지정합니다.
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
#   --server           변환 전용 서버(s2-docflow-server)를 systemd 서비스로 설치합니다. 다른 서버의 앱이 HTTP 로 변환을 맡기므로
#                      변환 용량을 서버 대수로 늘릴 수 있습니다 (docs/server.ko.md). 공유 비밀키는 처음 설치할 때 만들어
#                      /etc/s2-docflow/server.env 에 둡니다. --server-jar, --server-port, --server-bind, --java 로 정합니다.
#   --no-server        변환 서버 서비스만 제거합니다.
#   --font-dir 폴더    고객사 글꼴 폴더(맑은 고딕·휴먼명조 등 보유 글꼴). 이미지에 넣지 않고 변환할 때마다 읽기 전용으로 연결하므로
#                      글꼴을 바꿔도 이미지를 다시 만들 필요가 없고, 폐쇄망 설치 파일에도 들어가지 않습니다 (글꼴 라이선스 보호).
#                      한 번 지정하면 다시 실행해도 유지되며, --no-font-dir 로 뺍니다. 변환할 때 S2_FONT_DIR 로 바꿀 수도 있습니다.
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
#   - 고객사 글꼴 폴더(--font-dir): 지정하지 않으면 설치된 명령의 값을 그대로 유지 (--no-font-dir 로 뺌)
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
IMAGE_REVISION="6"
BASE_IMAGE="docker.io/library/debian:trixie-slim"
IMAGE_NAME="localhost/s2-office-converter"
WRAPPER_PATH="/usr/local/bin/s2-soffice"
CHROME_WRAPPER_PATH="/usr/local/bin/s2-chrome"
HWP_WRAPPER_PATH="/usr/local/bin/s2-hwp"
# Converter server (--server) | 변환 서버 (--server)
SERVER_SERVICE="s2-docflow-server"
SERVER_DIR="/opt/s2-docflow"
SERVER_JAR_PATH="${SERVER_DIR}/s2-docflow-server.jar"
SERVER_ENV_DIR="/etc/s2-docflow"
SERVER_ENV="${SERVER_ENV_DIR}/server.env"
# Share of this server for conversions (--dedicated, --share), read by the commands, the app and the server
# | 이 서버에서 변환에 쓰는 몫 (--dedicated, --share). 변환 명령·앱·변환 서버가 함께 읽음
CONVERTER_ENV="${SERVER_ENV_DIR}/converter.env"
SERVER_UNIT="/etc/systemd/system/${SERVER_SERVICE}.service"
SERVER_CACHE="/var/cache/s2-docflow"
SERVER_JAR_ARCHIVE="s2-docflow-server.jar"
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
  --font-dir 폴더      고객사 글꼴 폴더(맑은 고딕·휴먼명조 등 보유 글꼴)를 변환할 때 읽기 전용으로 연결 (다시 실행해도 유지)
  --no-font-dir        글꼴 폴더 연결을 뺌
  --server             변환 전용 서버(s2-docflow-server)를 systemd 서비스로 설치 (다른 서버의 앱이 HTTP 로 변환을 맡김)
    --server-jar 파일    서버 jar (s2-docflow 저장소에서 ./gradlew serverJar). 다시 실행할 때는 생략하면 설치된 jar 유지
    --server-port 포트   수신 포트 (기본 8090)        --server-bind 주소  수신 주소 (기본 0.0.0.0)
    --java 경로          java 실행 파일 (기본: PATH 의 java, Java 17 이상)
  --no-server          변환 서버 서비스만 제거 (변환기는 남김)
  --dedicated          이 서버를 변환 전용으로 씀 (CPU 전체, 메모리는 OS·서버 몫 3GB를 뺀 나머지)
  --share 퍼센트       앱과 함께 쓰는 서버에서 변환에 줄 몫 (10~90, 예: --share 40)
                       둘 다 없으면 처음 설치할 때 물어보고(무인 실행은 묻지 않음), 다시 실행하면 정한 값을 유지
  --warm               성능 우선: 끝난 컨테이너를 다음 변환에 다시 씀 (작은 문서 건당 0.3~0.5초 빠름, 격리는 한 단계 약함)
  --no-warm            변환마다 새 컨테이너 (기본, 격리 우선). 한 번 정하면 다시 실행해도 유지
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
FONT_DIR=""
FONT_DIR_SET=false
SERVER=false
NO_SERVER=false
SERVER_JAR=""
SERVER_PORT=""
SERVER_BIND=""
JAVA_BIN=""
EXPORT_FILE=""
TARGET_DISTRO=""
SHARE=""
WARM=""
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
    --server)
        SERVER=true
        shift
        ;;
    --no-server)
        NO_SERVER=true
        shift
        ;;
    --server-jar)
        [ $# -ge 2 ] || fail "--server-jar 다음에 jar 파일이 필요합니다."
        SERVER_JAR="$2"
        shift 2
        ;;
    --server-jar=*)
        SERVER_JAR="${1#*=}"
        shift
        ;;
    --server-port)
        [ $# -ge 2 ] || fail "--server-port 다음에 포트가 필요합니다."
        SERVER_PORT="$2"
        shift 2
        ;;
    --server-port=*)
        SERVER_PORT="${1#*=}"
        shift
        ;;
    --server-bind)
        [ $# -ge 2 ] || fail "--server-bind 다음에 주소가 필요합니다."
        SERVER_BIND="$2"
        shift 2
        ;;
    --server-bind=*)
        SERVER_BIND="${1#*=}"
        shift
        ;;
    --java)
        [ $# -ge 2 ] || fail "--java 다음에 java 실행 파일 경로가 필요합니다."
        JAVA_BIN="$2"
        shift 2
        ;;
    --java=*)
        JAVA_BIN="${1#*=}"
        shift
        ;;
    --font-dir)
        [ $# -ge 2 ] || fail "--font-dir 다음에 글꼴 폴더가 필요합니다."
        FONT_DIR="$2"
        FONT_DIR_SET=true
        shift 2
        ;;
    --font-dir=*)
        FONT_DIR="${1#*=}"
        FONT_DIR_SET=true
        shift
        ;;
    --no-font-dir)
        FONT_DIR=""
        FONT_DIR_SET=true
        shift
        ;;
    --no-chrome)
        WITH_CHROME=false
        shift
        ;;
    --dedicated)
        SHARE="dedicated"
        shift
        ;;
    --warm)
        WARM=1
        shift
        ;;
    --no-warm)
        WARM=0
        shift
        ;;
    --share)
        [ $# -ge 2 ] || fail "--share 다음에 퍼센트가 필요합니다 (예: --share 40)."
        SHARE="${2%\%}"
        shift 2
        ;;
    --share=*)
        SHARE="${1#*=}"
        SHARE="${SHARE%\%}"
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
case "$SHARE" in
"" | dedicated) ;;
*) [[ "$SHARE" =~ ^[0-9]+$ ]] && [ "$SHARE" -ge 10 ] && [ "$SHARE" -le 90 ] || fail "--share 는 10~90 사이 퍼센트입니다 (전용이면 --dedicated): $SHARE" ;;
esac
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
import { execFileSync } from 'node:child_process';
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

// Fonts the document asks for. rhwp writes each font-family as the document's font, its aliases (한양중고딕 → HY중고딕)
// and then a common fallback tail (Batang, Nanum Myeongjo, Noto ...); the font counts as present when it or one of
// its aliases is installed | 문서가 요구하는 글꼴. rhwp 의 font-family 는 문서 글꼴, 별칭(한양중고딕 → HY중고딕), 공통 대체 목록(바탕·나눔명조·
// Noto 등) 순서이며, 문서 글꼴이나 별칭 중 하나가 있으면 있는 것으로 본다
const FALLBACK_TAIL = new Set(['Batang', '바탕', 'Nanum Myeongjo', 'AppleMyungjo', 'Noto Serif KR', 'Noto Serif CJK KR', 'HCR Batang',
    'HCR Batang Ext', '함초롬바탕 확장', 'HCR Batang ExtB', '함초롬바탕 확장B', 'Source Han Serif K Old Hangul', 'Malgun Gothic',
    '맑은 고딕', 'Apple SD Gothic Neo', 'Noto Sans KR', 'Pretendard', 'Nanum Gothic', 'Noto Sans CJK KR', 'HCR Dotum', '함초롬돋움']);
const wanted = new Map(); // document font -> its aliases | 문서 글꼴 -> 별칭
for (let i = 0; i < rendered; i++) {
    const svg = scopeIds(doc.renderPageSvg(i).replace(/^<\?xml[^>]*>\s*/, ''), 'p' + i + '-');
    for (const m of svg.matchAll(/font-family="([^"]*)"/g)) {
        const names = m[1].replace(/&apos;|&#39;|&quot;/g, "'").split(',').map((n) => n.trim().replace(/^'|'$/g, '')).filter(Boolean);
        const first = names[0];
        if (!first || wanted.has(first) || /^(serif|sans-serif|monospace|cursive|fantasy)$/i.test(first)) continue;
        const aliases = [];
        for (const n of names.slice(1)) {
            if (FALLBACK_TAIL.has(n) || /^(serif|sans-serif|monospace)$/i.test(n)) break;
            aliases.push(n);
        }
        wanted.set(first, aliases);
    }
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
// Fonts asked for but not installed (customer fonts: setup --font-dir) | 요구했지만 없는 글꼴 (고객사 글꼴: 설치 --font-dir)
try {
    const installed = new Set(execFileSync('fc-list', [':', 'family'], { encoding: 'utf8' }).split(/[\n,]/).map((f) => f.trim()).filter(Boolean));
    const missing = [...wanted].filter(([font, aliases]) => !installed.has(font) && !aliases.some((a) => installed.has(a)))
        .map(([font]) => font).sort();
    console.log('missing-fonts=' + missing.join(','));
} catch {
    // fc-list unavailable: say nothing | fc-list 가 없으면 알리지 않음
}
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

# 래퍼의 자리 표시를 채움 (이미지, 글꼴 폴더)
fill_wrapper() {
    local escaped
    escaped="$(printf '%s' "$FONT_DIR" | sed 's/[|&\\]/\\&/g')"
    sed -i -e "s|@IMAGE@|${IMAGE}|" -e "s|@FONT_DIR@|${escaped}|" "$1"
    local runtime
    runtime="$(mktemp)"
    CLEANUP_PATHS+=("$runtime")
    write_runtime "$runtime"
    sed -i -e "/^@RUNTIME@\$/{r $runtime" -e 'd}' "$1"
}

# Container runtime shared by the three commands (reuses idle containers) | 세 명령이 함께 쓰는 컨테이너 실행 부분 (대기 컨테이너 재사용)
write_runtime() {
    cat >"$1" <<'RUNTIME'
# ---- Container runtime shared by s2-soffice, s2-chrome and s2-hwp ------------------------------------------------
# Each job runs in a container with no network, a read-only root, no capabilities and its own subordinate uids (see
# s2_auto_ids below). By default a
# fresh container is started for every job and removed after it (LibreOffice starts from a copy of a read-only profile
# prepared once per account, which saves about 0.65 s). Performance first: S2_CONVERTER_WARM=1 (or setup --warm)
# reuses idle containers of this account's pool (podman exec, about 0.3 s less per small document, more for Chromium).
# A pool container runs one job at a time; when the job ends, every process it left is killed and /tmp is emptied.
# Isolation is one step weaker than a fresh container: a job that broke out of its process through a kernel or
# container runtime flaw could affect the next job in the same container. A pool container is removed after
# S2_CONVERTER_IDLE_SECONDS without work (default 600), after S2_CONVERTER_WARM_USES jobs (default 200), or when a job
# times out or is cancelled; at most S2_CONVERTER_WARM_MAX (default: S2_DOCFLOW_PARALLELISM from converter.env, else
# the CPU count), and with resource limits (S2_*_MEMORY, S2_*_CPUS) a fresh container is always used.
# | 변환기 컨테이너 실행 (s2-soffice, s2-chrome, s2-hwp 공통). 네트워크 없음, 읽기 전용 루트, 권한 없음, 자기만의 하위 uid (아래 s2_auto_ids).
# 기본은 작업마다 새 컨테이너를 띄우고 끝나면 지운다 (LibreOffice 는 계정마다 한 번 만들어 둔 읽기 전용 프로필의 사본으로 시작해 약 0.65초 단축).
# 성능 우선: S2_CONVERTER_WARM=1 (또는 설치 --warm) 이면 이 계정의 대기 컨테이너를 다시 쓴다 (podman exec). 대기 컨테이너는 한 번에 작업
# 하나만 하고, 작업이 끝나면 남은 프로세스를 모두 끝내고 /tmp 를 비운다. 격리는 새 컨테이너보다 한 단계 약하다: 커널·컨테이너 런타임 취약점으로
# 프로세스를 벗어난 작업은 같은 컨테이너의 다음 작업에 영향을 줄 수 있다. S2_CONVERTER_IDLE_SECONDS(기본 600) 동안 일이 없거나,
# S2_CONVERTER_WARM_USES(기본 200)건을 처리했거나, 시간 초과·취소되면 지운다. 최대 S2_CONVERTER_WARM_MAX 개 (기본: converter.env 의
# S2_DOCFLOW_PARALLELISM, 없으면 CPU 수). 자원 상한(S2_*_MEMORY, S2_*_CPUS)을 지정하면 항상 새 컨테이너.
S2_SETTINGS_FILE="/etc/s2-docflow/converter.env"
s2_setting() {
    local value="${!1:-}"
    if [ -z "$value" ] && [ -r "$S2_SETTINGS_FILE" ]; then
        value="$(sed -n "s/^$1=\([0-9A-Za-z_.-]*\).*/\1/p" "$S2_SETTINGS_FILE" | tail -n 1)"
    fi
    printf '%s' "${value:-$2}"
}
s2_pool="$XDG_RUNTIME_DIR/s2-converter-pool/$(printf '%s|%s' "$IMAGE" "$FONT_DIR" | cksum | cut -d ' ' -f 1)"
s2_isolation=(--network=none --read-only --cap-drop=ALL --security-opt=no-new-privileges)
# Separate ids (default): the container runs as uid 1000 mapped to the account's subordinate ids (container ids
# 0-1023 -> subordinate ids 1-1024), so a process that broke out of it is not the caller's account and cannot touch
# the caller's files. Every container uses the same fixed range: Podman keeps one copy of the image per id mapping
# (about 1.6 GB once; a range per container, --userns=auto, made 63 copies, 89 GB, when measured). Falls back to the
# caller's uid (keep-id) when Podman cannot (probed once, kept in the pool folder) or with S2_CONVERTER_USERNS=keep-id
# | uid 분리(기본): 컨테이너를 계정의 하위 uid 로 매핑한 uid 1000 으로 돌려(컨테이너 0~1023 -> 하위 uid 1~1024), 컨테이너를 벗어난 프로세스도
# 호출자 계정이 아니라 호출자 파일에 닿지 못함. 모든 컨테이너가 같은 고정 범위를 씀: Podman 은 uid 매핑마다 이미지 사본을 하나씩 두므로(한 번 약
# 1.6GB. 컨테이너마다 범위를 주는 --userns=auto 는 실측 63벌, 89GB). Podman 이 못 하면(한 번 확인해 대기 폴더에 기록) 또는
# S2_CONVERTER_USERNS=keep-id 이면 호출자 uid(keep-id)로 실행
s2_auto_ids=(--uidmap 0:1:1024 --gidmap 0:1:1024 --user 1000:1000 -e HOME=/tmp)
s2_keep_ids=(--userns=keep-id)
s2_ids_mode() {
    local mode
    mode="$(s2_setting S2_CONVERTER_USERNS "")"
    if [ -z "$mode" ]; then
        mode="$(cat "$s2_pool/userns" 2>/dev/null)"
        if [ -z "$mode" ]; then
            mkdir -p "$s2_pool"
            if "${podman_cmd[@]}" run --rm "${s2_isolation[@]}" "${s2_auto_ids[@]}" "$IMAGE" true >/dev/null 2>&1; then
                mode=auto
            else
                mode=keep-id
            fi
            echo "$mode" >"$s2_pool/userns"
        fi
    fi
    printf '%s' "$mode"
}
# Only regular files leave the container: a symbolic link (for example a.pdf -> a file of the host) would make the
# caller read something else as the result | 결과는 일반 파일만 넘김: 심볼릭 링크(예: a.pdf -> 호스트의 파일)를 넘기면 호출자가 다른 파일을
# 결과로 읽게 됨
s2_results() {
    find "$1" -mindepth 1 ! -type f ! -type d -delete 2>/dev/null
    [ "$s2_ids" != auto ] || s2_own "$1"
}
# The container's own uid writes the results: copy them so the caller owns them (and can remove the folders)
# | 결과는 컨테이너의 uid 가 쓰므로 복사해 호출자 소유로 바꿈 (폴더도 지울 수 있게)
s2_own() {
    local item
    for item in "$1"/* "$1"/.[!.]*; do
        [ -e "$item" ] && [ ! -O "$item" ] || continue
        if [ -f "$item" ] && [ ! -L "$item" ]; then
            cp -- "$item" "$item.s2-own" && mv -f -- "$item.s2-own" "$item"
        else
            "${podman_cmd[@]}" unshare chown -R 0:0 -- "$item" >/dev/null 2>&1
        fi
    done
}
# Empties a folder, including what the container's uid left | 폴더를 비움 (컨테이너 uid 가 남긴 것 포함)
s2_wipe() {
    find "$1" -mindepth 1 -delete 2>/dev/null || "${podman_cmd[@]}" unshare find "$1" -mindepth 1 -delete >/dev/null 2>&1
}
# The container's uid reads the input and writes the output (the parent folder stays private to the caller)
# | 컨테이너 uid 가 입력을 읽고 결과를 쓸 수 있게 함 (상위 폴더는 호출자 전용 그대로)
s2_open() {
    chmod 755 "$1/in" && chmod -R a+rX "$1/in" && chmod 777 "$1/out"
}
# In the container: copy the prepared profile when mounted, run the job, then kill what it left and empty /tmp
# | 컨테이너 안: 준비된 프로필이 있으면 복사, 작업 실행, 남은 프로세스를 끝내고 /tmp 를 비움
s2_job='[ ! -d /opt/s2-profile ] || cp -a /opt/s2-profile /tmp/s2-profile; "$@"; rc=$?; kill -9 -1 2>/dev/null; find /tmp -mindepth 1 -delete 2>/dev/null; exit $rc'
# Main process of a pool container: exits after $0 seconds without a job (a "busy" mark older than an hour is stale)
# | 대기 컨테이너의 주 프로세스: 작업 없이 $0 초가 지나면 끝남 (한 시간 넘은 busy 표시는 무시)
s2_idle='trap "exit 0" TERM; while :; do sleep 5 & wait $!; now=$(date +%s); busy=$(stat -c %Y /work/state/busy 2>/dev/null || echo 0); [ $((now - busy)) -gt 3600 ] || continue; last=$(stat -c %Y /work/state/last 2>/dev/null || echo 0); [ $((now - last)) -lt "$0" ] || exit 0; done'

# LibreOffice profile made once per account and image (creating it took about 0.65 s of every conversion) from a fixed
# text file, with the same ids as the conversions (no second image copy), then copied so the caller owns it and every
# container can read it | 계정·이미지마다 한 번 만드는 LibreOffice 프로필 (만들기가 변환마다 약 0.65초를 차지했음). 고정된 텍스트 파일로,
# 변환과 같은 uid 로 만들고(이미지 사본을 하나 더 만들지 않음), 호출자 소유로 복사해 모든 컨테이너가 읽게 둠
s2_profile() {
    local dir="$s2_pool/profile"
    if [ ! -e "$dir/.s2-shared" ]; then
        mkdir -p "$s2_pool" || return 1
        (
            flock 9
            [ ! -e "$dir/.s2-shared" ] || exit 0
            # Made by an earlier version: only make it readable | 이전 버전이 만든 것: 읽을 수 있게만
            if [ -d "$dir/user" ]; then
                chmod -R a+rX "$dir" && touch "$dir/.s2-shared"
                exit 0
            fi
            local ids=("${s2_keep_ids[@]}")
            [ "${s2_ids:-}" != auto ] || ids=("${s2_auto_ids[@]}")
            s2_wipe "$s2_pool/profile.new"
            mkdir -p "$s2_pool/profile.new" && chmod 777 "$s2_pool/profile.new" || exit 1
            printf 's2\n' >"$s2_pool/profile.new/a.txt"
            "${podman_cmd[@]}" run --rm "${s2_isolation[@]}" "${ids[@]}" -v "$s2_pool/profile.new:/b:rw,Z" "$IMAGE" \
                sh -c 'soffice --headless --norestore --nolockcheck -env:UserInstallation=file:///b/p --convert-to pdf --outdir /b /b/a.txt; chmod -R a+rX /b/p' \
                >/dev/null 2>&1 || true
            if [ -d "$s2_pool/profile.new/p/user" ]; then
                s2_wipe "$s2_pool/profile.copy"
                rm -rf "$s2_pool/profile.copy" && cp -R "$s2_pool/profile.new/p" "$s2_pool/profile.copy" &&
                    chmod -R a+rX "$s2_pool/profile.copy" && touch "$s2_pool/profile.copy/.s2-shared" &&
                    rm -rf "$dir" && mv "$s2_pool/profile.copy" "$dir"
            fi
            s2_wipe "$s2_pool/profile.new"
            rm -rf "$s2_pool/profile.new"
        ) 9>"$s2_pool/profile.lock"
    fi
    [ -e "$dir/.s2-shared" ]
}

# s2_run [NAME=VALUE ...] -- command [args]: runs the command (time limit $TIMEOUT) with $work/in at /work/in (read-only)
# and $work/out at /work/out; returns its exit status | 명령을 실행하고($TIMEOUT 제한) 종료 코드를 돌려줌
s2_run() {
    local - rc envs=() ids=() attempt
    set +e
    while [ "$1" != "--" ]; do
        envs+=(-e "$1")
        shift
    done
    shift
    s2_ids="$(s2_ids_mode)"
    if [ "$(s2_setting S2_CONVERTER_WARM 0)" = 1 ] && [ ${#limits[@]} -eq 0 ] && command -v flock >/dev/null 2>&1; then
        s2_warm_run "$@"
        rc=$?
        [ "$rc" = 200 ] || return "$rc"
    fi
    local profile=()
    [ "${s2_kind:-}" != soffice ] || ! s2_profile || profile=(-v "$s2_pool/profile:/opt/s2-profile:ro,z")
    [ "$s2_ids" != auto ] || s2_open "$work"
    trap '"${podman_cmd[@]}" kill "$s2_container" >/dev/null 2>&1 || true; exit 143' TERM INT
    for attempt in "$s2_ids" keep-id; do
        if [ "$attempt" = auto ]; then ids=("${s2_auto_ids[@]}"); else ids=("${s2_keep_ids[@]}"); fi
        s2_container="s2-${s2_kind:-run}-$$-${RANDOM}"
        "${podman_cmd[@]}" run --rm --name "$s2_container" ${limits[@]+"${limits[@]}"} "${s2_isolation[@]}" "${ids[@]}" \
            -v "$work/in:/work/in:ro,Z" -v "$work/out:/work/out:rw,Z" \
            ${fonts[@]+"${fonts[@]}"} ${profile[@]+"${profile[@]}"} ${envs[@]+"${envs[@]}"} \
            "$IMAGE" sh -c "$s2_job" sh timeout --kill-after=5 "$TIMEOUT" "$@" &
        wait "$!"
        rc=$?
        # 125/126: Podman or the OCI runtime could not start it with separate ids: once more with the caller's uid
        # | 125/126: Podman·OCI 런타임이 uid 분리로 띄우지 못함 → 호출자 uid 로 한 번 더
        { [ "$rc" = 125 ] || [ "$rc" = 126 ]; } && [ "$attempt" = auto ] || break
    done
    trap - TERM INT
    s2_results "$work/out"
    return "$rc"
}

# Starts the pool container of a slot. Podman must not inherit the slot lock ({fd}>&-): the container would hold it
# for its whole life | 자리의 대기 컨테이너를 띄움. Podman 이 자리 잠금을 물려받으면 컨테이너가 사는 동안 잠겨 있으므로 넘기지 않음
s2_start() {
    local profile=() ids=("${s2_keep_ids[@]}")
    [ "$s2_ids" != auto ] || ids=("${s2_auto_ids[@]}")
    ! s2_profile || profile=(-v "$s2_pool/profile:/opt/s2-profile:ro,z")
    "${podman_cmd[@]}" rm -f -t 0 "$s2_container" >/dev/null 2>&1
    touch "$1/state/last"
    chmod 755 "$1/in" "$1/state" && chmod 777 "$1/out"
    "${podman_cmd[@]}" run -d --rm --name "$s2_container" --label s2-office-converter-pool=1 "${s2_isolation[@]}" "${ids[@]}" \
        -v "$1/in:/work/in:ro,Z" -v "$1/out:/work/out:rw,Z" -v "$1/state:/work/state:ro,Z" \
        ${fonts[@]+"${fonts[@]}"} ${profile[@]+"${profile[@]}"} \
        "$IMAGE" sh -c "$s2_idle" "$(s2_setting S2_CONVERTER_IDLE_SECONDS 600)" >/dev/null 2>&1 {fd}>&-
}

# Runs the job in a pool container; 200 means no container was free (the caller starts a fresh one)
# | 대기 컨테이너에서 실행. 200 이면 빈 컨테이너가 없음 (호출자가 새 컨테이너로 실행)
s2_warm_run() {
    local max dir slot="" fd="" pool_fd count=0 n rc=200 uses attempt
    max="$(s2_setting S2_CONVERTER_WARM_MAX "$(s2_setting S2_DOCFLOW_PARALLELISM "$(nproc 2>/dev/null || echo 4)")")"
    mkdir -p "$s2_pool" 2>/dev/null || return 200
    exec {pool_fd}>"$s2_pool/pool.lock" || return 200
    flock "$pool_fd"
    for dir in "$s2_pool"/slot-*; do
        [ -d "$dir" ] || continue
        count=$((count + 1))
        exec {fd}>"$dir/lock"
        if flock -n "$fd"; then
            slot="$dir"
            break
        fi
        exec {fd}>&-
        fd=""
    done
    if [ -z "$slot" ] && [ "$count" -lt "$max" ]; then
        n=1
        while [ -e "$s2_pool/slot-$n" ]; do n=$((n + 1)); done
        slot="$s2_pool/slot-$n"
        mkdir -p "$slot/in" "$slot/out" "$slot/state"
        exec {fd}>"$slot/lock"
        flock -n "$fd"
    fi
    exec {pool_fd}>&-
    [ -n "$slot" ] || return 200
    s2_container="s2-pool-${s2_pool##*/}-${slot##*/}"
    touch "$slot/state/busy"
    s2_wipe "$slot/in"
    s2_wipe "$slot/out"
    cp -a "$work/in/." "$slot/in/"
    [ "$s2_ids" != auto ] || chmod -R a+rX "$slot/in"
    trap '"${podman_cmd[@]}" rm -f -t 0 "$s2_container" >/dev/null 2>&1 || true; exit 143' TERM INT
    for attempt in 1 2; do
        "${podman_cmd[@]}" exec ${envs[@]+"${envs[@]}"} "$s2_container" sh -c "$s2_job" sh timeout --kill-after=5 "$TIMEOUT" "$@" {fd}>&- &
        wait "$!"
        rc=$?
        # 125: the container is not running (first use, or it went idle) | 컨테이너가 없음 (처음이거나 쉬다가 끝남)
        [ "$rc" = 125 ] && [ "$attempt" = 1 ] || break
        echo 0 >"$slot/uses"
        s2_start "$slot" || { rc=200; break; }
    done
    [ "$rc" != 125 ] || rc=200
    trap - TERM INT
    rm -f "$slot/state/busy"
    touch "$slot/state/last"
    if [ "$rc" != 200 ]; then
        # A copy across file systems (the pool lives in the runtime folder) leaves the results owned by the caller
        # | 다른 파일 시스템으로 옮기므로(대기 폴더는 런타임 폴더) 결과는 호출자 소유가 됨
        find "$slot/out" -mindepth 1 -maxdepth 1 -exec mv -f -t "$work/out/" -- {} +
        s2_results "$work/out"
        uses=$(($(cat "$slot/uses" 2>/dev/null || echo 0) + 1))
        echo "$uses" >"$slot/uses"
        # Remove after a timeout or cancellation, or when worn; the remover holds the slot until it is gone
        # | 시간 초과·취소 뒤나 많이 쓴 뒤에는 지움. 지우는 동안 그 자리는 잠김
        if [ "$rc" = 124 ] || [ "$rc" = 137 ] || [ "$rc" = 143 ] || [ "$uses" -ge "$(s2_setting S2_CONVERTER_WARM_USES 200)" ]; then
            echo 0 >"$slot/uses"
            ("${podman_cmd[@]}" rm -f -t 0 "$s2_container" >/dev/null 2>&1) </dev/null >/dev/null 2>&1 &
        fi
    fi
    s2_wipe "$slot/in"
    s2_wipe "$slot/out"
    exec {fd}>&-
    return "$rc"
}
# ---- end of the container runtime ---------------------------------------------------------------------------------
RUNTIME
}

# 고객사 글꼴 폴더 정하기: --font-dir > 설치된 래퍼의 값(다시 실행해도 유지) > 없음. --no-font-dir 이면 뺌
resolve_font_dir() {
    info "고객사 글꼴 폴더"
    if [ "$FONT_DIR_SET" = false ] && [ -f "$WRAPPER_PATH" ]; then
        FONT_DIR="$(sed -n 's/^FONT_DIR="\${S2_FONT_DIR-\(.*\)}"$/\1/p' "$WRAPPER_PATH" | head -1)"
    fi
    if [ -z "$FONT_DIR" ]; then
        skip "지정하지 않았습니다 (이미지에 든 나눔·Noto 글꼴로 대체). 지정: --font-dir <폴더>"
        return
    fi
    FONT_DIR="$(cd "$FONT_DIR" 2>/dev/null && pwd)" || fail "글꼴 폴더가 없습니다: $FONT_DIR"
    case "$FONT_DIR" in
    / | /usr | /usr/* | /etc | /etc/* | /bin | /sbin | /lib* | /var | /home | /root | /tmp)
        fail "글꼴만 둔 전용 폴더를 지정하십시오 (예: /opt/s2-fonts): $FONT_DIR" ;;
    esac
    local count
    count="$(find "$FONT_DIR" -type f \( -iname '*.ttf' -o -iname '*.ttc' -o -iname '*.otf' -o -iname '*.otc' \) 2>/dev/null | wc -l)"
    [ "$count" -gt 0 ] || fail "글꼴 파일(.ttf, .ttc, .otf)이 없습니다: $FONT_DIR"
    # Converters run under subordinate uids (uid separation) and read the fonts as "others"
    # | 변환기는 자기 uid(uid 분리)로 돌며 글꼴을 "그 밖의 사용자"로 읽음
    if [ -n "$(find "$FONT_DIR" \( -type f ! -perm -o+r \) -o \( -type d ! -perm -o+rx \) 2>/dev/null | head -1)" ]; then
        warn "글꼴 폴더에 다른 사용자가 읽을 수 없는 파일이 있어 변환기가 그 글꼴을 못 씁니다. 고치기: sudo chmod -R a+rX $FONT_DIR"
    fi
    # The app account must be able to read them | 앱 실행 계정이 읽을 수 있어야 함
    as_target test -r "$FONT_DIR" || fail "앱 실행 계정($TARGET_USER)이 읽을 수 없습니다: $FONT_DIR (예: sudo chmod -R a+rX $FONT_DIR)"
    ok "$FONT_DIR (글꼴 파일 ${count}개, 변환할 때 읽기 전용으로 연결)"
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
#   S2_CONVERTER_WARM   1 이면 대기 컨테이너를 다시 씀 (성능 우선, 격리는 한 단계 약함. 기본 0: 작업마다 새 컨테이너. 아래 "Container runtime" 부분)
#   S2_CONVERTER_USERNS keep-id 이면 앱 계정 uid 로 실행 (기본: 앱 계정이 아닌 하위 uid 로 실행하는 uid 분리)
set -euo pipefail

IMAGE="@IMAGE@"
# Customer fonts, mounted read-only (setup --font-dir; S2_FONT_DIR overrides) | 고객사 글꼴 폴더 (읽기 전용 연결)
FONT_DIR="${S2_FONT_DIR-@FONT_DIR@}"
fonts=()
[ -z "$FONT_DIR" ] || [ ! -d "$FONT_DIR" ] || fonts=(-v "$FONT_DIR:/usr/share/fonts/s2-custom:ro")
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
    -env:*) shift ;; # The wrapper gives each job its own profile in the container | 래퍼가 작업마다 컨테이너 안의 전용 프로필을 줌
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

args=(soffice --headless --norestore --nolockcheck -env:UserInstallation=file:///tmp/s2-profile --convert-to "$convert_to" --outdir /work/out)
[ -z "$infilter" ] || args+=("$infilter")
args+=("/work/in/$name")

# No network, read-only root (/tmp stays writable), no capabilities, separate subordinate uids (results are handed
# back owned by the caller), time limit. Memory/CPU limits only when S2_SOFFICE_MEMORY/S2_SOFFICE_CPUS are set (cgroup delegation needed)
# | 네트워크 없음, 읽기 전용 루트(/tmp 는 쓰기 가능), 권한 없음, 분리된 하위 uid(결과는 호출자 소유로 넘김), 시간 제한.
# 메모리·CPU 상한은 S2_SOFFICE_MEMORY / S2_SOFFICE_CPUS 를 지정할 때만 (cgroup 위임 필요)
@RUNTIME@
s2_kind=soffice
s2_run -- "${args[@]}"

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
    fill_wrapper "$wrapper_tmp"
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
# 권한 없음, 분리된 하위 uid)가 격리를 맡습니다.
#
# 환경 변수:
#   S2_CHROME_TIMEOUT  인쇄 제한 시간(초, 기본 60)
#   S2_CHROME_MEMORY   컨테이너 메모리 상한 (예: 1g, 지정할 때만. cgroup v2 위임이 있어야 함)
#   S2_CHROME_CPUS     컨테이너 CPU 상한 (예: 1.5, 지정할 때만)
#   S2_CONVERTER_WARM   1 이면 대기 컨테이너를 다시 씀 (성능 우선, 격리는 한 단계 약함. 기본 0: 작업마다 새 컨테이너. 아래 "Container runtime" 부분)
#   S2_CONVERTER_USERNS keep-id 이면 앱 계정 uid 로 실행 (기본: 앱 계정이 아닌 하위 uid 로 실행하는 uid 분리)
set -euo pipefail

IMAGE="@IMAGE@"
# Customer fonts, mounted read-only (setup --font-dir; S2_FONT_DIR overrides) | 고객사 글꼴 폴더 (읽기 전용 연결)
FONT_DIR="${S2_FONT_DIR-@FONT_DIR@}"
fonts=()
[ -z "$FONT_DIR" ] || [ ! -d "$FONT_DIR" ] || fonts=(-v "$FONT_DIR:/usr/share/fonts/s2-custom:ro")
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

@RUNTIME@
s2_kind=chrome
s2_run -- chromium --headless --no-sandbox --disable-gpu \
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
    fill_wrapper "$wrapper_tmp"
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
#   S2_CONVERTER_WARM   1 이면 대기 컨테이너를 다시 씀 (성능 우선, 격리는 한 단계 약함. 기본 0: 작업마다 새 컨테이너. 아래 "Container runtime" 부분)
#   S2_CONVERTER_USERNS keep-id 이면 앱 계정 uid 로 실행 (기본: 앱 계정이 아닌 하위 uid 로 실행하는 uid 분리)
set -euo pipefail

IMAGE="@IMAGE@"
# Customer fonts, mounted read-only (setup --font-dir; S2_FONT_DIR overrides) | 고객사 글꼴 폴더 (읽기 전용 연결)
FONT_DIR="${S2_FONT_DIR-@FONT_DIR@}"
fonts=()
[ -z "$FONT_DIR" ] || [ ! -d "$FONT_DIR" ] || fonts=(-v "$FONT_DIR:/usr/share/fonts/s2-custom:ro")
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
    exec "${podman_cmd[@]}" run --rm --network=none --read-only --userns=keep-id ${fonts[@]+"${fonts[@]}"} "$IMAGE" /opt/s2-hwp/s2-hwp-convert.sh --version
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

# Same isolation as s2-soffice: no network, read-only root (/tmp stays writable), no capabilities, separate uids,
# time limit; stop the container when the caller gives up (SIGTERM) | s2-soffice 와 같은 격리. 호출자가 포기하면 컨테이너를 멈춤
@RUNTIME@
s2_kind=hwp
set +e
s2_run S2_HWP_CHUNK="${S2_HWP_CHUNK:-50}" S2_HWP_PARALLEL="${S2_HWP_PARALLEL:-1}" -- /opt/s2-hwp/s2-hwp-convert.sh "/work/in/document.$extension" /work/out/document.pdf \
    ${max_pages[@]+"${max_pages[@]}"}
status=$?
set -e
[ "$status" -eq 0 ] || exit "$status"
[ -s "$work/out/document.pdf" ] || {
    echo "s2-hwp: 변환 결과가 없습니다: $name" >&2
    exit 1
}
mv -f -- "$work/out/document.pdf" "$outdir/${name%.*}.pdf"
WRAPPER
    fill_wrapper "$wrapper_tmp"
    if [ -f "$HWP_WRAPPER_PATH" ] && cmp -s "$wrapper_tmp" "$HWP_WRAPPER_PATH"; then
        skip "s2-hwp 가 최신입니다."
    else
        "${SUDO[@]}" install -m 0755 "$wrapper_tmp" "$HWP_WRAPPER_PATH"
        ok "설치: $HWP_WRAPPER_PATH"
    fi
}

# ==============================================================================
# 변환 몫과 규모 안내
# ==============================================================================

# Planning figures. Measured with 8 slots and small mixed documents: 0.43 conversions a second per slot (0.45-0.5 with
# --warm); planned at 0.2 per slot to leave room for larger documents and peaks. Users: 10 conversions not in the cache
# per user a day, an 8-hour day, the busiest moment 3 times the average, so users = conversions a second x 960
# | 계획 기준. 8자리·작은 문서 섞음 실측: 자리당 초당 0.43건(--warm 0.45~0.5건). 큰 문서와 몰림을 고려해 자리당 초당 0.2건으로 잡음.
# 사용자: 1인당 하루 캐시에 없는 변환 10건, 업무 8시간, 가장 몰릴 때 평균의 3배 → 사용자 수 = 초당 변환 수 x 960
PLAN_RATE_PER_SLOT_X100=20
USERS_PER_RATE=960
# Memory planned per concurrent conversion and kept for the OS and the server JVM on a dedicated server
# | 동시 변환 한 건에 잡는 메모리, 전용 서버에서 OS·서버 JVM 몫으로 남기는 메모리
MB_PER_SLOT=1024
DEDICATED_RESERVE_MB=3072
CAPACITY_SUMMARY=""

converter_env_value() {
    [ -r "$CONVERTER_ENV" ] || return 0
    sed -n "s/^$1=//p" "$CONVERTER_ENV" | head -1
}
ask_no() {
    local answer=""
    printf '%s [y/N]: ' "$1" >/dev/tty
    read -r answer </dev/tty || answer=""
    case "${answer:-N}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# Decides the share, writes converter.env and estimates the number of users | 몫을 정해 converter.env 를 쓰고 사용자 규모를 안내
configure_capacity() {
    info "변환에 쓰는 몫 (동시 변환 수·메모리)"
    local cores mem_mb conv_cores conv_mem slots rate_x100 users label answer warm
    warm="${WARM:-$(converter_env_value S2_CONVERTER_WARM)}"
    warm="${warm:-0}"
    cores="$(nproc 2>/dev/null || echo 2)"
    mem_mb="$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo 2>/dev/null || echo 4096)"
    if [ -z "$SHARE" ]; then
        SHARE="$(converter_env_value S2_CONVERTER_SHARE)"
        if [ -n "$SHARE" ]; then
            skip "설치된 값을 유지합니다 ($CONVERTER_ENV). 바꾸려면 --dedicated 또는 --share 퍼센트"
        elif can_ask; then
            if ask_no "이 서버를 문서 변환 전용으로 쓰나요? (앱은 다른 서버에서 실행)"; then
                SHARE="dedicated"
            else
                printf '앱과 함께 쓰는 서버입니다. 변환에 줄 몫(%%, 10~90) [50]: ' >/dev/tty
                read -r answer </dev/tty || answer=""
                answer="${answer%\%}"
                SHARE="${answer:-50}"
                [[ "$SHARE" =~ ^[0-9]+$ ]] && [ "$SHARE" -ge 10 ] && [ "$SHARE" -le 90 ] || fail "10~90 사이 숫자를 입력하십시오: $SHARE"
            fi
        else
            [ -z "$WARM" ] || fail "처음 설치할 때 --warm/--no-warm 은 --dedicated 또는 --share 퍼센트와 함께 씁니다."
            skip "정하지 않았습니다 (무인 실행). 앱 기본값: 동시 변환 min(CPU, 4), 메모리 예산 물리 메모리의 절반. 정하기: --dedicated 또는 --share 퍼센트"
            return 0
        fi
    fi
    if [ "$SHARE" = dedicated ]; then
        conv_cores="$cores"
        conv_mem=$((mem_mb - DEDICATED_RESERVE_MB))
        [ "$conv_mem" -ge 1024 ] || conv_mem=1024
        label="전용"
    else
        conv_cores=$((cores * SHARE / 100))
        conv_mem=$((mem_mb * SHARE / 100))
        [ "$conv_cores" -ge 1 ] || conv_cores=1
        label="${SHARE}% (앱과 함께 씀)"
    fi
    slots=$((conv_mem / MB_PER_SLOT))
    [ "$slots" -le "$conv_cores" ] || slots="$conv_cores"
    [ "$slots" -ge 1 ] || slots=1
    rate_x100=$((slots * PLAN_RATE_PER_SLOT_X100))
    users=$((rate_x100 * USERS_PER_RATE / 100 / 50 * 50))
    local env_tmp
    env_tmp="$(mktemp)"
    CLEANUP_PATHS+=("$env_tmp")
    cat >"$env_tmp" <<ENV
# 이 서버에서 문서 변환에 쓰는 몫. setup-s2-office-converter.sh 가 만듭니다 (바꾸기: --dedicated 또는 --share 퍼센트로 다시 실행).
# 변환 명령(대기 컨테이너 수), 앱의 S2DocFlow(동시 변환 수·메모리 예산), 변환 서버가 함께 읽습니다. 앱 코드나 server.env 의 값이 우선합니다.
# 서버: CPU ${cores}코어, 메모리 ${mem_mb}MB / 몫: ${label}
S2_CONVERTER_SHARE=${SHARE}
S2_DOCFLOW_PARALLELISM=${slots}
S2_DOCFLOW_MEMORY_MB=${conv_mem}
# 대기 컨테이너 재사용. 0: 변환마다 새 컨테이너 (기본, 격리 우선) / 1: 끝난 컨테이너를 다시 씀 (성능 우선, 격리는 한 단계 약함). 바꾸기: --warm / --no-warm
S2_CONVERTER_WARM=${warm}
ENV
    "${SUDO[@]}" mkdir -p "$SERVER_ENV_DIR"
    if [ -f "$CONVERTER_ENV" ] && "${SUDO[@]}" cmp -s "$env_tmp" "$CONVERTER_ENV"; then
        skip "$CONVERTER_ENV 가 최신입니다."
    else
        "${SUDO[@]}" install -m 0644 "$env_tmp" "$CONVERTER_ENV"
        ok "설정: $CONVERTER_ENV"
    fi
    CAPACITY_SUMMARY="몫 ${label}: 동시 변환 ${slots}건, 메모리 예산 ${conv_mem}MB (CPU ${cores}코어, 메모리 ${mem_mb}MB 중)"
    ok "$CAPACITY_SUMMARY"
    if [ "$warm" = 1 ]; then
        warn "대기 컨테이너를 다시 씁니다 (--warm, 성능 우선). 앞 작업이 남긴 프로세스와 /tmp 는 지우지만, 커널·컨테이너 런타임 취약점을 이용한 문서는 같은 컨테이너의 다음 작업에 영향을 줄 수 있습니다. 민감한 문서를 다루면 --no-warm"
        CAPACITY_SUMMARY="${CAPACITY_SUMMARY}, 대기 컨테이너 재사용 (성능 우선)"
    else
        CAPACITY_SUMMARY="${CAPACITY_SUMMARY}, 변환마다 새 컨테이너 (격리 우선. 성능 우선은 --warm)"
    fi
    CAPACITY_SUMMARY="${CAPACITY_SUMMARY}
     규모: 일반적인 사용이면 약 ${users}명까지 (1인당 하루 캐시에 없는 변환 10건, 업무 8시간, 가장 몰릴 때 평균의 3배,
           보통 문서 기준 초당 약 $((rate_x100 / 100)).$(printf '%02d' $((rate_x100 % 100)))건으로 계획). 업로드 때 미리 변환(prepare)·캐시가 잘 맞으면 더 많이.
           큰 HWP·엑셀이 많거나 동시에 몰리면 적게 잡고, 운영 중에는 통계(waiting, busyRejections)로 다시 맞춥니다."
    printf '   %s\n' "규모: 일반적인 사용이면 약 ${users}명까지 (자세한 가정은 완료 안내)"
}

# Separate ids: checks support and prepares the image for the fixed id range now (the first use copies the image for
# that mapping, about 1.6 GB and a few seconds), not on the first conversion
# | uid 분리: 지원 여부를 확인하고 고정 uid 범위용 이미지 준비를 지금 함 (처음 쓸 때 그 매핑용 이미지 사본을 만듦, 약 1.6GB·수 초)
prepare_ids() {
    info "uid 분리 (컨테이너를 앱 계정이 아닌 하위 uid 로 실행)"
    if [ "$(converter_env_value S2_CONVERTER_USERNS)" = keep-id ]; then
        skip "쓰지 않습니다 (S2_CONVERTER_USERNS=keep-id)."
        return 0
    fi
    if podman_target run --rm --network=none --read-only --uidmap 0:1:1024 --gidmap 0:1:1024 --user 1000:1000 "$IMAGE" true >/dev/null 2>&1; then
        ok "컨테이너를 앱 계정이 아닌 하위 uid 로 실행합니다 (이미지 사본 약 1.6GB 추가). 끄기: converter.env 에 S2_CONVERTER_USERNS=keep-id"
    else
        warn "이 서버의 Podman 이 uid 분리를 하지 못해 변환을 앱 계정 uid 로 실행합니다 (네트워크 없음·읽기 전용 등 다른 격리는 그대로). /etc/subuid·/etc/subgid 에 $TARGET_USER 의 범위(1025개 이상)가 있는지 확인하십시오."
    fi
}

# Removes this account's idle converter containers so the new commands and settings apply
# | 새 명령·설정이 적용되도록 이 계정의 대기 컨테이너를 지움
reset_pool() {
    command -v podman >/dev/null 2>&1 || return 0
    local ids
    ids="$(podman_target ps -aq --filter label=s2-office-converter-pool=1 2>/dev/null || true)"
    [ -n "$ids" ] || return 0
    # shellcheck disable=SC2086 # one id per word | id 를 단어별로 넘김
    podman_target rm -f -t 0 $ids >/dev/null 2>&1 || true
    ok "대기 컨테이너 정리 ($(wc -w <<<"$ids")개, 다음 변환부터 새 설정)"
}

# Forgets the commands' cached uid separation check, so the next conversion checks again
# | 변환 명령이 기억해 둔 uid 분리 확인 결과를 지워 다음 변환이 다시 확인하게 함
forget_ids_check() {
    as_target sh -c 'rm -f "$XDG_RUNTIME_DIR"/s2-converter-pool/*/userns' 2>/dev/null || true
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
    if [ -n "$FONT_DIR" ]; then
        local seen
        seen="$(podman_target run --rm --network=none -v "$FONT_DIR:/usr/share/fonts/s2-custom:ro" "$IMAGE" sh -c 'fc-list : file | grep -c /usr/share/fonts/s2-custom/' 2>/dev/null || echo 0)"
        if [ "${seen:-0}" -gt 0 ]; then
            ok "고객사 글꼴: ${seen}개 인식 ($FONT_DIR)"
        else
            warn "고객사 글꼴을 변환기가 인식하지 못했습니다: $FONT_DIR (파일 권한·형식을 확인하십시오)"
        fi
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

# ==============================================================================
# 변환 서버 (--server)
# ==============================================================================

# Java 17+ for the service | 서비스용 Java 17 이상
resolve_java() {
    local java="${JAVA_BIN:-}"
    if [ -z "$java" ]; then
        java="$(command -v java || true)"
    fi
    if [ -z "$java" ] && [ "$MODE" = "install" ]; then
        info "Java 설치 (변환 서버용)"
        if command -v apt-get >/dev/null 2>&1; then
            "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-21-jre-headless >/dev/null ||
                "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-17-jre-headless >/dev/null || true
        elif command -v dnf >/dev/null 2>&1; then
            "${SUDO[@]}" dnf install -y -q java-21-openjdk-headless || "${SUDO[@]}" dnf install -y -q java-17-openjdk-headless || true
        fi
        java="$(command -v java || true)"
    fi
    [ -n "$java" ] || fail "변환 서버에 Java 17 이상이 필요합니다. 설치한 뒤 다시 실행하거나 --java <경로> 로 지정하십시오."
    java="$(readlink -f "$java")"
    local major
    major="$("$java" -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -1)"
    [ "${major:-0}" -ge 17 ] || fail "Java 17 이상이 필요합니다: $java (버전 ${major:-알 수 없음})"
    as_target test -x "$java" || fail "앱 실행 계정($TARGET_USER)이 실행할 수 없는 java 입니다: $java (--java 로 다른 경로 지정)"
    JAVA_BIN="$java"
}

# A value of the installed env file | 설치된 설정 파일의 값
server_env_value() {
    "${SUDO[@]}" sed -n "s/^$1=//p" "$SERVER_ENV" 2>/dev/null | head -1
}

install_server() {
    info "변환 서버 ($SERVER_SERVICE)"
    [ -d /run/systemd/system ] || fail "systemd 가 없습니다. 서비스 대신 직접 실행하십시오: java -jar <s2-docflow-server.jar> (docs/server.ko.md)"
    command -v curl >/dev/null 2>&1 || fail "curl 이 필요합니다 (서버 상태 확인용)."
    resolve_java

    # The jar: given, bundled (offline) or already installed | jar: 지정한 것, 설치 파일에 든 것, 이미 설치된 것
    local jar="$SERVER_JAR" changed=false
    if [ -z "$jar" ] && [ -n "${OFFLINE_SERVER_JAR:-}" ]; then
        jar="$OFFLINE_SERVER_JAR"
    fi
    if [ -n "$jar" ]; then
        [ -f "$jar" ] || fail "서버 jar 가 없습니다: $jar"
        "$JAVA_BIN" -jar "$jar" --version >/dev/null 2>&1 || fail "실행할 수 없는 서버 jar 입니다: $jar"
        if [ -f "$SERVER_JAR_PATH" ] && cmp -s "$jar" "$SERVER_JAR_PATH"; then
            skip "서버 jar 가 같습니다."
        else
            "${SUDO[@]}" install -d -m 0755 "$SERVER_DIR"
            "${SUDO[@]}" install -m 0644 "$jar" "$SERVER_JAR_PATH"
            ok "설치: $SERVER_JAR_PATH ($("$JAVA_BIN" -jar "$SERVER_JAR_PATH" --version 2>/dev/null))"
            changed=true
        fi
    elif [ -f "$SERVER_JAR_PATH" ]; then
        skip "설치된 서버 jar 를 그대로 씁니다: $("$JAVA_BIN" -jar "$SERVER_JAR_PATH" --version 2>/dev/null)"
    else
        fail "서버 jar 를 --server-jar 로 지정하십시오 (s2-docflow 저장소에서 ./gradlew serverJar → build/libs/s2-docflow-server-<버전>.jar)."
    fi

    # Settings: created once with a new secret, kept on later runs | 설정: 처음에 새 비밀키로 만들고 이후에는 유지
    "${SUDO[@]}" install -d -m 0755 "$SERVER_ENV_DIR"
    if ! "${SUDO[@]}" test -f "$SERVER_ENV"; then
        local secret env_tmp
        secret="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"
        env_tmp="$(mktemp)"
        CLEANUP_PATHS+=("$env_tmp")
        cat >"$env_tmp" <<ENV
# s2-docflow 변환 서버 설정 (setup-s2-office-converter.sh --server 가 만듦. 고친 뒤: sudo systemctl restart ${SERVER_SERVICE})
# 설명: docs/server.ko.md (s2-docflow)
S2_DOCFLOW_BIND=${SERVER_BIND:-0.0.0.0}
S2_DOCFLOW_PORT=${SERVER_PORT:-8090}
# 앱과 같은 값으로 둡니다 (앱: S2_DOCFLOW_SECRET 또는 S2RemoteConverter.builder().secret(...))
S2_DOCFLOW_SECRET=${secret}
S2_DOCFLOW_CACHE_DIR=${SERVER_CACHE}
# S2_DOCFLOW_CACHE_MAX_MB=10240
# S2_DOCFLOW_CACHE_DAYS=30
# S2_DOCFLOW_PARALLELISM=6
# S2_DOCFLOW_MEMORY_MB=8192
# S2_DOCFLOW_QUEUE_SECONDS=120
# S2_DOCFLOW_MAX_MB=200
# 사이냅 호환 /mergePdf, /convert (쉼표 구분). 접근 IP 는 S2_DOCFLOW_ALLOW_IPS (기본 127.0.0.1,::1)
# S2_DOCFLOW_SYNAP_ROOTS=/data/docflow/files
# S2_DOCFLOW_SYNAP_HOSTS=
# S2_DOCFLOW_ALLOW_IPS=127.0.0.1,::1
ENV
        "${SUDO[@]}" install -m 0600 "$env_tmp" "$SERVER_ENV"
        ok "설정: $SERVER_ENV (공유 비밀키를 새로 만들었습니다. 앱에 같은 값을 설정: sudo grep SECRET $SERVER_ENV)"
        changed=true
    else
        local key value
        for key in BIND PORT; do
            value="$([ "$key" = BIND ] && echo "$SERVER_BIND" || echo "$SERVER_PORT")"
            if [ -n "$value" ] && [ "$(server_env_value "S2_DOCFLOW_$key")" != "$value" ]; then
                "${SUDO[@]}" sed -i "s|^S2_DOCFLOW_$key=.*|S2_DOCFLOW_$key=$value|" "$SERVER_ENV"
                changed=true
            fi
        done
        skip "설정을 그대로 씁니다: $SERVER_ENV (비밀키 유지)"
    fi
    "${SUDO[@]}" install -d -m 0750 -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" "$SERVER_CACHE"

    local unit_tmp
    unit_tmp="$(mktemp)"
    CLEANUP_PATHS+=("$unit_tmp")
    cat >"$unit_tmp" <<UNIT
# s2-docflow 변환 서버 (setup-s2-office-converter.sh --server 가 설치. 직접 고치지 마십시오)
[Unit]
Description=s2-docflow converter server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${TARGET_USER}
Environment=HOME=${TARGET_HOME}
Environment=PATH=/usr/local/bin:/usr/bin:/bin
EnvironmentFile=-${CONVERTER_ENV}
EnvironmentFile=${SERVER_ENV}
ExecStart=${JAVA_BIN} -jar ${SERVER_JAR_PATH}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
# Rootless Podman needs newuidmap (setuid), so NoNewPrivileges is not set | rootless Podman 이 setuid 인 newuidmap 을 쓰므로 NoNewPrivileges 는 두지 않음

[Install]
WantedBy=multi-user.target
UNIT
    if [ -f "$SERVER_UNIT" ] && cmp -s "$unit_tmp" "$SERVER_UNIT"; then
        skip "서비스 파일이 같습니다."
    else
        "${SUDO[@]}" install -m 0644 "$unit_tmp" "$SERVER_UNIT"
        "${SUDO[@]}" systemctl daemon-reload
        ok "설치: $SERVER_UNIT"
        changed=true
    fi
    "${SUDO[@]}" systemctl enable -q "$SERVER_SERVICE"
    if [ "$changed" = true ] || ! systemctl is-active -q "$SERVER_SERVICE"; then
        "${SUDO[@]}" systemctl restart "$SERVER_SERVICE"
    fi

    local port health="" i
    port="$(server_env_value S2_DOCFLOW_PORT)"
    for i in $(seq 1 60); do
        health="$(curl -fsS --max-time 2 "http://127.0.0.1:${port:-8090}/health" 2>/dev/null || true)"
        [ -z "$health" ] || break
        sleep 0.5
    done
    [ -n "$health" ] || fail "변환 서버가 응답하지 않습니다. 로그: sudo journalctl -u ${SERVER_SERVICE} -n 50"
    ok "변환 서버 동작: http://$(server_env_value S2_DOCFLOW_BIND):${port} — $health"
}

remove_server() {
    if [ -f "$SERVER_UNIT" ]; then
        "${SUDO[@]}" systemctl disable --now -q "$SERVER_SERVICE" 2>/dev/null || true
        "${SUDO[@]}" rm -f "$SERVER_UNIT"
        "${SUDO[@]}" systemctl daemon-reload
        ok "제거: $SERVER_UNIT"
    else
        skip "변환 서버 서비스가 없습니다."
    fi
    if [ -d "$SERVER_DIR" ]; then
        "${SUDO[@]}" rm -rf "$SERVER_DIR"
        ok "제거: $SERVER_DIR"
    fi
}

done_message() {
    cat <<DONE

🎉 완료. 계정 ${TARGET_USER} 로 실행하는 앱에서 S2OfficeConverter 가 s2-soffice 를 자동으로 찾습니다.
   예) S2DocumentMerger.merge(List.of(PdfSource.ofDocument(Path.of("보고서.hwp")), ...));
   확인) sudo -u ${TARGET_USER} ${WRAPPER_PATH} --version
DONE
    [ -z "$CAPACITY_SUMMARY" ] || echo "   ${CAPACITY_SUMMARY}"
    [ "$WITH_CHROME" = false ] || echo "   웹 페이지(URL 로 받은 HTML)는 s2-chrome 으로 화면 그대로 변환합니다. 확인) sudo -u ${TARGET_USER} ${CHROME_WRAPPER_PATH} --version"
    [ "$WITH_CHROME" = false ] || echo "   한글 문서(hwp, hwpx)는 s2-hwp(rhwp)로 먼저 변환하고, 실패하면 s2-soffice 로 변환합니다. 확인) sudo -u ${TARGET_USER} ${HWP_WRAPPER_PATH} --version"
    if [ "$SERVER" = true ]; then
        cat <<SERVER_DONE
   변환 서버: http://<이 서버>:$(server_env_value S2_DOCFLOW_PORT) (서비스 ${SERVER_SERVICE}, 로그: sudo journalctl -u ${SERVER_SERVICE} -f)
     앱 설정) S2_DOCFLOW_REMOTE=http://<이 서버>:$(server_env_value S2_DOCFLOW_PORT)  S2_DOCFLOW_SECRET=<sudo grep SECRET ${SERVER_ENV}>
SERVER_DONE
    fi
    print_new_checksums
}

# ==============================================================================
# 모드
# ==============================================================================

mode_uninstall() {
    remove_server
    reset_pool
    if [ -d "$SERVER_ENV_DIR" ] || [ -d "$SERVER_CACHE" ]; then
        "${SUDO[@]}" rm -rf "$SERVER_ENV_DIR" "$SERVER_CACHE"
        ok "제거: $SERVER_ENV_DIR, $SERVER_CACHE"
    fi
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
    resolve_font_dir
    install_wrapper
    install_chrome_wrapper
    install_hwp_wrapper
    configure_capacity
    reset_pool
    forget_ids_check
    prepare_ids
    verify
    [ "$SERVER" = false ] || install_server
    [ "$NO_SERVER" = false ] || remove_server
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

    if [ -n "$SERVER_JAR" ]; then
        [ -f "$SERVER_JAR" ] || fail "서버 jar 가 없습니다: $SERVER_JAR"
        cp -f "$SERVER_JAR" "$stage/payload/$SERVER_JAR_ARCHIVE"
        ok "변환 서버 jar 포함: $SERVER_JAR (서버에서 --server 로 설치)"
    fi

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
BUNDLE_SERVER_JAR=$([ -n "$SERVER_JAR" ] && echo true || echo false)
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

    resolve_font_dir
    install_wrapper
    install_chrome_wrapper
    install_hwp_wrapper
    configure_capacity
    reset_pool
    forget_ids_check
    prepare_ids
    verify
    if [ -f "$dir/$SERVER_JAR_ARCHIVE" ]; then
        OFFLINE_SERVER_JAR="$dir/$SERVER_JAR_ARCHIVE"
        chmod 644 "$OFFLINE_SERVER_JAR"
    fi
    [ "$SERVER" = false ] || install_server
    [ "$NO_SERVER" = false ] || remove_server
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
