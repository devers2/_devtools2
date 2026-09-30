#!/usr/bin/env bash
# ==============================================================================
# s2 오피스/한글 문서 변환기 설치 스크립트 (setup-s2-office-converter.sh)
# ==============================================================================
#
# [실행 방법] s2-support 를 쓰는 앱과 같은 서버에서, sudo 를 쓸 수 있는 계정으로 실행합니다.
#             이 파일 하나만으로 동작하므로 저장소를 받을 필요 없이 GitHub 에서 바로 실행하면 됩니다.
#
#   # 1) 온라인 실행 — 앱을 실행하는 계정(예: tomcat)용으로 설치 (권장)
#   curl -fsSL https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/setup-projects/s2/setup-s2-office-converter.sh | bash -s -- --user tomcat
#
#   # 2) 온라인 실행 — 지금 로그인한 계정용으로 설치 (개발 PC, WSL)
#   curl -fsSL https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/setup-projects/s2/setup-s2-office-converter.sh | bash
#
#   # 3) 받아서 실행 (내용을 먼저 확인하고 싶을 때)
#   curl -fsSL -o /tmp/setup-s2-office-converter.sh https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/setup-projects/s2/setup-s2-office-converter.sh
#   bash /tmp/setup-s2-office-converter.sh --user tomcat
#
#   # 이미지 다시 만들기 / 제거
#   curl -fsSL <위 주소> | bash -s -- --user tomcat --rebuild
#   curl -fsSL <위 주소> | bash -s -- --user tomcat --uninstall
#
#   - 처음 실행은 LibreOffice 를 받느라 몇 분 걸리며, sudo 비밀번호를 물을 수 있습니다.
#   - 여러 번 실행해도 안전합니다. 이미 설치된 것은 건너뛰고 빠진 것만 채웁니다.
#   - 설치가 끝나면 앱을 다시 시작할 필요 없이 S2PdfUtil 이 s2-soffice 를 자동으로 찾습니다.
#   - 확인: sudo -u tomcat s2-soffice --version
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
#   --user 계정  변환기를 사용할 계정(웹 애플리케이션을 실행하는 계정, 예: tomcat). 기본: 이 스크립트를 실행한 계정.
#                root 없는(rootless) Podman 은 이미지를 계정별로 저장하므로, 앱을 실행하는 계정으로 만들어야 합니다.
#   --rebuild    이미지를 다시 만듭니다 (보안 업데이트 반영 등).
#   --uninstall  s2-soffice 명령과 이미지를 제거합니다 (Podman 자체는 남김).
#
# 멱등성: 몇 번을 실행해도 같은 상태가 됩니다. 이미 있는 것은 건너뛰고 없는 것만 준비합니다.
#   - Podman: 없으면 설치 (apt 또는 dnf)
#   - 대상 계정의 subuid/subgid: 없으면 추가 (rootless Podman 필요 조건)
#   - 이미지: 같은 버전(태그)이 있으면 건너뜀. 버전을 올리면 새로 만듦
#   - /usr/local/bin/s2-soffice: 내용이 다를 때만 교체
#   - 마지막에 실제 변환으로 동작을 확인
#
# 라이선스: 이 스크립트는 LibreOffice(MPL 2.0), H2Orestart(GPL 3.0), 폰트(SIL OFL 1.1 등)를 각 배포처에서 받아
# 이 서버에 설치할 뿐, 재배포하지 않습니다. 각 소프트웨어는 자체 라이선스를 따릅니다.
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
사용법: bash setup-s2-office-converter.sh [--user 계정] [--rebuild] [--uninstall] [--help]

  --user 계정  변환기를 사용할 계정(웹 애플리케이션을 실행하는 계정, 예: tomcat). 기본: 이 스크립트를 실행한 계정.
               root 없는(rootless) Podman 은 이미지를 계정별로 저장하므로, 앱을 실행하는 계정으로 만들어야 합니다.
  --rebuild    이미지를 다시 만듭니다 (보안 업데이트 반영 등).
  --uninstall  s2-soffice 명령과 이미지를 제거합니다 (Podman 자체는 남김).
USAGE
}

# ------------------------------------------------------------------------------
# 인자
# ------------------------------------------------------------------------------
TARGET_USER="${SUDO_USER:-$(id -un)}"
REBUILD=false
UNINSTALL=false
while [ $# -gt 0 ]; do
    case "$1" in
    --user)
        [ $# -ge 2 ] || fail "--user 다음에 계정 이름이 필요합니다."
        TARGET_USER="$2"
        shift 2
        ;;
    --user=*)
        TARGET_USER="${1#--user=}"
        shift
        ;;
    --rebuild)
        REBUILD=true
        shift
        ;;
    --uninstall)
        UNINSTALL=true
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *) fail "알 수 없는 옵션입니다: $1 (--help 참고)" ;;
    esac
done

[ "$(uname -s)" = "Linux" ] || fail "리눅스에서만 실행할 수 있습니다."
id "$TARGET_USER" >/dev/null 2>&1 || fail "계정이 없습니다: $TARGET_USER"
[ "$TARGET_USER" != "root" ] || fail "root 계정용으로는 만들지 않습니다. --user 로 앱을 실행하는 일반 계정을 지정하십시오."

# root 권한이 필요한 명령 (이미 root 면 그대로)
if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    command -v sudo >/dev/null 2>&1 || fail "sudo 가 필요합니다."
    SUDO=(sudo)
fi

TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

# 대상 계정으로 podman 실행. 로그인 세션이 없는 서비스 계정도 동작하도록 런타임 경로와 cgroup 관리자를 지정
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

# ------------------------------------------------------------------------------
# 제거
# ------------------------------------------------------------------------------
if [ "$UNINSTALL" = true ]; then
    if [ -f "$WRAPPER_PATH" ]; then
        "${SUDO[@]}" rm -f "$WRAPPER_PATH"
        ok "제거: $WRAPPER_PATH"
    else
        skip "s2-soffice 가 없습니다."
    fi
    if command -v podman >/dev/null 2>&1; then
        mapfile -t images < <(podman_target images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "^${IMAGE_NAME}:" || true)
        for image in "${images[@]}"; do
            podman_target rmi -f "$image" >/dev/null && ok "제거: $image ($TARGET_USER)"
        done
        [ ${#images[@]} -gt 0 ] || skip "이미지가 없습니다 ($TARGET_USER)."
    fi
    exit 0
fi

# ------------------------------------------------------------------------------
# 1. Podman
# ------------------------------------------------------------------------------
info "1/5 Podman 확인"
if command -v podman >/dev/null 2>&1; then
    skip "Podman 이 이미 있습니다: $(podman --version)"
else
    if command -v apt-get >/dev/null 2>&1; then
        "${SUDO[@]}" apt-get update -qq
        "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq podman uidmap slirp4netns >/dev/null
    elif command -v dnf >/dev/null 2>&1; then
        "${SUDO[@]}" dnf install -y -q podman
    else
        fail "apt 또는 dnf 가 있는 배포판(Ubuntu, Debian, RHEL, Rocky 등)에서만 자동 설치할 수 있습니다. Podman 을 직접 설치한 뒤 다시 실행하십시오."
    fi
    ok "Podman 설치: $(podman --version)"
fi

# ------------------------------------------------------------------------------
# 2. rootless Podman 준비 (subuid/subgid)
# ------------------------------------------------------------------------------
info "2/5 계정 준비 ($TARGET_USER)"
ensure_subid() {
    local file="$1" option="$2"
    if grep -q "^${TARGET_USER}:" "$file" 2>/dev/null || grep -q "^${TARGET_UID}:" "$file" 2>/dev/null; then
        skip "$file 에 $TARGET_USER 항목이 있습니다."
        return
    fi
    # Use a range after the highest one in use | 사용 중인 가장 큰 범위 다음부터 할당
    local start
    start=$(awk -F: '{ end = $2 + $3; if (end > max) max = end } END { print (max > 100000 ? max : 100000) }' "$file" 2>/dev/null || echo 100000)
    "${SUDO[@]}" usermod "$option" "${start}-$((start + 65535))" "$TARGET_USER"
    ok "$file 에 $TARGET_USER 추가 (${start}-$((start + 65535)))"
}
ensure_subid /etc/subuid --add-subuids
ensure_subid /etc/subgid --add-subgids

# ------------------------------------------------------------------------------
# 3. 변환기 이미지
# ------------------------------------------------------------------------------
info "3/5 변환기 이미지 ($IMAGE)"
if [ "$REBUILD" = false ] && podman_target image exists "$IMAGE" 2>/dev/null; then
    skip "이미지가 이미 있습니다 ($TARGET_USER)."
else
    build_dir="$(mktemp -d)"
    trap 'rm -rf "$build_dir"' EXIT
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
    "${SUDO[@]}" chmod 755 "$build_dir"
    "${SUDO[@]}" chmod 644 "$build_dir/Containerfile"
    info "이미지를 만듭니다. 처음에는 LibreOffice 를 받느라 몇 분 걸립니다..."
    podman_target build --pull=newer -t "$IMAGE" "$build_dir"
    ok "이미지 생성: $IMAGE ($TARGET_USER)"
    # Remove older revisions of this image | 이 이미지의 이전 버전 정리
    mapfile -t old_images < <(podman_target images --format '{{.Repository}}:{{.Tag}}' | grep "^${IMAGE_NAME}:" | grep -vx "$IMAGE" || true)
    for image in "${old_images[@]}"; do
        podman_target rmi -f "$image" >/dev/null && ok "이전 이미지 정리: $image"
    done
fi

# ------------------------------------------------------------------------------
# 4. s2-soffice 명령
# ------------------------------------------------------------------------------
info "4/5 s2-soffice 명령 ($WRAPPER_PATH)"
wrapper_tmp="$(mktemp)"
cat >"$wrapper_tmp" <<'WRAPPER'
#!/usr/bin/env bash
# s2-soffice: LibreOffice(soffice) 호환 변환 명령. Podman 컨테이너(s2-office-converter)에서 변환합니다.
# setup-s2-office-converter.sh 가 설치합니다. 직접 고치지 마십시오 (다시 실행하면 덮어씀).
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
    rm -f "$wrapper_tmp"
else
    "${SUDO[@]}" install -m 0755 "$wrapper_tmp" "$WRAPPER_PATH"
    rm -f "$wrapper_tmp"
    ok "설치: $WRAPPER_PATH"
fi

# ------------------------------------------------------------------------------
# 5. 동작 확인 (대상 계정으로 실제 변환)
# ------------------------------------------------------------------------------
info "5/5 동작 확인 ($TARGET_USER)"
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

cat <<DONE

🎉 완료. 계정 ${TARGET_USER} 로 실행하는 앱에서 S2PdfUtil 이 s2-soffice 를 자동으로 찾습니다.
   예) S2PdfUtil.merge(List.of(PdfSource.ofDocument(Path.of("보고서.hwp")), ...));
   확인) sudo -u ${TARGET_USER} ${WRAPPER_PATH} --version
DONE
