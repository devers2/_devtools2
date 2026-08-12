#!/usr/bin/env bash
# ==============================================================================
# DEVTOOLS2 Maven Central 배포 설정 모듈 (maven-central-setup.sh)
# ==============================================================================
# 개요:
#   플러그인/의존성 jar 라이브러리 프로젝트가 Maven Central Portal에 배포할 수
#   있도록 ~/.gradle/gradle.properties 에 Maven Central Portal 인증 정보와
#   GPG 서명 정보를 설정합니다. 값은 모두 Bitwarden에서 조회하며, 필수 항목이
#   없으면 조용히 건너뜁니다(배포용 세팅은 선택 사항이라 강제하지 않음).
#
# 사용 방법 (다른 스크립트에서 호출 시):
#   1. common-setup.sh 를 먼저(또는 함께) 불러오기 ($DEVTOOLS2 기준 절대경로)
#      — _update_gradle_properties_section 을 common-setup.sh에서 가져다 씁니다:
#      source "$DEVTOOLS2/scripts/linux/setup-projects/_common/common-setup.sh"
#      source "$DEVTOOLS2/scripts/linux/setup-projects/_common/maven-central-setup.sh"
#
#   2. 함수 호출:
#      setup_maven_central_publishing "$TARGET_DIR"
#      - $1: 대상 프로젝트 디렉토리 (선택, 기본값: $PWD — gradle 프로젝트 여부 확인용)
#
# Bitwarden 항목 구조 (미리 만들어서 채워둬야 함):
#   • "Maven Central Portal" 항목의 사용자 지정 필드
#       centralUsername, centralPassword
#   • "GPG Signing" 항목의 사용자 지정 필드
#       signing.keyId, signing.password
#       signing.secretKeyRingBase64 (단일 필드) 또는
#       signing.secretKeyRingBase64_1 + signing.secretKeyRingBase64_2 (2분할, 둘 다 필수)
#       → command-palette의 "[Base64] 파일 → 텍스트 인코딩" 메뉴로 만든 값을 그대로
#         붙여넣으면 됩니다 (Bitwarden 필드 1개 5000자 한도를 넘으면 자동으로
#         _1/_2 두 파트로 나눠줍니다).
# ==============================================================================

# 내부 헬퍼: base64 문자열(파트 여러 개면 순서대로 이어붙인 뒤) 디코딩해 파일로 저장
# 인수: $1 = 대상 파일 경로, $2.. = base64 파트 값들 (순서대로 이어붙임)
# 반환: 0 = 성공, 1 = 실패(입력값 없음 또는 디코딩 실패 — 실패 시 대상 파일 제거)
_mc_decode_base64_to_file() {
    local _dst="$1"
    shift
    local _b64="" _part
    for _part in "$@"; do
        _b64="${_b64}${_part}"
    done
    if [ -z "$_b64" ]; then
        return 1
    fi

    mkdir -p "$(dirname "$_dst")"

    # macOS(BSD) base64는 -D, GNU base64는 -d를 사용 (플랫폼별 분기)
    local _is_mac=false
    [[ "$OSTYPE" == darwin* ]] && _is_mac=true

    if $_is_mac && printf '%s' "$_b64" | base64 -D >"$_dst" 2>/dev/null; then
        return 0
    elif printf '%s' "$_b64" | base64 -d >"$_dst" 2>/dev/null; then
        return 0
    fi
    rm -f "$_dst"
    return 1
}

# ── Maven Central 배포용 설정 (centralUsername/Password + GPG 서명) ─────────
# 기능:
#   - 대상 디렉토리에 Gradle 설정 파일 존재 여부 확인 (없으면 조용히 건너뜀)
#   - 대소문자 구분 없이 (y/n) 확인 후 진행 (기본값 N — Enter만 누르면 건너뜀)
#   - Bitwarden "Maven Central Portal"(centralUsername/centralPassword) +
#     "GPG Signing"(signing.keyId/signing.password/secretKeyRingBase64 또는 _1+_2)
#     두 항목의 필수값을 모두 조회
#     → 하나라도(항목 자체 또는 필드) 없으면 배포가 어차피 안 되므로 gradle.properties를
#       전혀 건드리지 않고 통째로 건너뜀 (부분 반영 없음)
#     → 둘 다 갖춰졌을 때만 ~/.gnupg/secring.gpg 복원 + gradle.properties 전체 반영
# 인수:
#   $1 = 대상 프로젝트 디렉토리 (기본값: 현재 디렉토리)
# 의존성: common-setup.sh(_update_gradle_properties_section), bw-lib(bw_get_fields)
setup_maven_central_publishing() {
    local TARGET_DIR="${1:-$PWD}"

    if [ ! -d "$TARGET_DIR" ]; then
        return 0
    fi

    # 1. Gradle 빌드/설정 파일 존재 여부 확인
    local HAS_GRADLE=false
    for gfile in "build.gradle" "settings.gradle" "build.gradle.kts" "settings.gradle.kts"; do
        if [ -f "$TARGET_DIR/$gfile" ]; then
            HAS_GRADLE=true
            break
        fi
    done
    if [ "$HAS_GRADLE" = "false" ]; then
        return 0
    fi

    # 2. 설정 여부 확인 (기본값 N)
    echo ""
    read -rp "❓ Maven 중앙 저장소(Central Portal) 배포용 설정을 하시겠습니까? [y/N]: " _MC_CHOICE
    _MC_CHOICE=$(echo "${_MC_CHOICE:-n}" | tr '[:upper:]' '[:lower:]' | xargs)
    if [ "$_MC_CHOICE" != "y" ]; then
        echo "ℹ️  Maven 중앙 저장소 배포용 설정을 건너뜁니다."
        return 0
    fi

    if ! command -v _update_gradle_properties_section &>/dev/null; then
        echo "❌ common-setup.sh 가 로드되지 않아 진행할 수 없습니다 (_update_gradle_properties_section 없음)." >&2
        return 1
    fi
    if ! command -v bw_get_fields &>/dev/null; then
        echo "❌ bw-lib 가 로드되지 않아 진행할 수 없습니다 (bw_get_fields 없음)." >&2
        return 1
    fi

    # Maven Central Portal 계정과 GPG 서명 정보 둘 다 있어야 실제로 배포가 되므로
    # (하나라도 없으면 어차피 publish가 실패함), 둘 다 필수값을 갖췄을 때만 반영하고
    # 하나라도 부족하면 아무것도 쓰지 않고 통째로 건너뜁니다(부분 반영 없음).

    # ── 1) Maven Central Portal 필드 조회 (centralUsername / centralPassword) ──
    echo "⏳ Bitwarden 'Maven Central Portal' 항목 조회 중..."
    local _CP_PARSED _CP_USER="" _CP_PASS="" _CP_OK=true
    _CP_PARSED=$(bw_get_fields "Maven Central Portal" "centralUsername" "centralPassword")
    if [ $? -ne 0 ]; then
        _CP_OK=false
    else
        _CP_USER=$(printf "%s" "$_CP_PARSED" | cut -f1)
        _CP_PASS=$(printf "%s" "$_CP_PARSED" | cut -f2)
        if [ -z "$_CP_USER" ] || [ -z "$_CP_PASS" ]; then
            _CP_OK=false
        fi
    fi

    # ── 2) GPG Signing 필드 조회 (signing.keyId / signing.password / 키링 base64) ──
    echo "⏳ Bitwarden 'GPG Signing' 항목 조회 중..."
    local _GPG_PARSED _KEY_ID="" _KEY_PASS="" _B64_SINGLE="" _B64_P1="" _B64_P2="" _GPG_OK=true
    local _HAS_KEYRING=false
    local -a _B64_PARTS=()
    _GPG_PARSED=$(bw_get_fields "GPG Signing" \
        "signing.keyId" "signing.password" \
        "signing.secretKeyRingBase64" "signing.secretKeyRingBase64_1" "signing.secretKeyRingBase64_2")
    if [ $? -ne 0 ]; then
        _GPG_OK=false
    else
        _KEY_ID=$(printf "%s" "$_GPG_PARSED" | cut -f1)
        _KEY_PASS=$(printf "%s" "$_GPG_PARSED" | cut -f2)
        _B64_SINGLE=$(printf "%s" "$_GPG_PARSED" | cut -f3)
        _B64_P1=$(printf "%s" "$_GPG_PARSED" | cut -f4)
        _B64_P2=$(printf "%s" "$_GPG_PARSED" | cut -f5)

        if [ -n "$_B64_SINGLE" ]; then
            _HAS_KEYRING=true
            _B64_PARTS=("$_B64_SINGLE")
        elif [ -n "$_B64_P1" ] && [ -n "$_B64_P2" ]; then
            _HAS_KEYRING=true
            _B64_PARTS=("$_B64_P1" "$_B64_P2")
        fi

        if [ -z "$_KEY_ID" ] || [ -z "$_KEY_PASS" ] || [ "$_HAS_KEYRING" = "false" ]; then
            _GPG_OK=false
        fi
    fi

    # ── 3) 필수값이 하나라도 부족하면 여기서 즉시 중단 (아직 아무 파일도 안 건드림) ──
    if [ "$_CP_OK" = "false" ] || [ "$_GPG_OK" = "false" ]; then
        echo ""
        echo "⚠️  Maven Central 배포에 필요한 값이 부족합니다. 어차피 배포가 안 되므로 설정을 전부 건너뜁니다."
        if [ "$_CP_OK" = "false" ]; then
            echo "   [Maven Central Portal] 항목 또는 centralUsername/centralPassword 필드가 없습니다."
        fi
        if [ "$_GPG_OK" = "false" ]; then
            echo "   [GPG Signing] 항목 또는 다음 필드가 없습니다:"
            [ -z "$_KEY_ID" ] && echo "      - signing.keyId"
            [ -z "$_KEY_PASS" ] && echo "      - signing.password"
            [ "$_HAS_KEYRING" = "false" ] && echo "      - signing.secretKeyRingBase64 (또는 _1 + _2 둘 다)"
        fi
        echo "   Bitwarden에 두 항목을 모두 채운 뒤 다시 실행해주세요."
        return 0
    fi

    # ── 4) GPG 키링 복원 시도 — 값은 있어도 디코딩이 실패할 수 있으므로 여기서도 검증 ──
    # ~ 는 Gradle이 자동으로 확장해주지 않고(properties 값을 그대로 File 경로로 해석)
    # 리터럴 "~"라는 이름의 디렉토리를 찾다가 실패하므로, 실제 홈 경로로 치환해서 저장합니다.
    # $HOME은 지금 로그인해서 이 스크립트를 실행 중인 계정 기준으로 셸이 채워주는 값이라,
    # 실행하는 사람이 바뀌면 그 사람의 홈 경로로 자동으로 달라집니다(하드코딩 아님).
    local _HOME_DIR="${HOME:-$USERPROFILE}"
    local _KEYRING_PATH="${_HOME_DIR}/.gnupg/secring.gpg"

    if ! _mc_decode_base64_to_file "$_KEYRING_PATH" "${_B64_PARTS[@]}"; then
        echo ""
        echo "❌ GPG 시크릿 키링 Base64 디코딩에 실패해 설정을 전부 건너뜁니다(배포 자체가 안 되므로)."
        echo "   Bitwarden의 signing.secretKeyRingBase64(_1/_2) 값이 올바른 Base64인지 확인해주세요."
        return 1
    fi
    local _KEYRING_SIZE
    _KEYRING_SIZE=$(wc -c <"$_KEYRING_PATH" | tr -d ' ')
    echo "✅ GPG 시크릿 키링 복원 완료: $_KEYRING_PATH (${_KEYRING_SIZE} bytes)"

    # ── 5) 여기까지 왔으면 둘 다 확실히 갖춰졌으므로 gradle.properties에 반영 ──
    local GRADLE_PROPS_DIR="$HOME/.gradle"
    local GRADLE_PROPS_FILE="$GRADLE_PROPS_DIR/gradle.properties"
    mkdir -p "$GRADLE_PROPS_DIR"
    touch "$GRADLE_PROPS_FILE"

    _update_gradle_properties_section "$GRADLE_PROPS_FILE" "Maven Central Portal" \
        "centralUsername=${_CP_USER}" \
        "centralPassword=${_CP_PASS}"
    echo "✅ centralUsername/centralPassword 설정 완료 (user: ${_CP_USER})"

    _update_gradle_properties_section "$GRADLE_PROPS_FILE" "GPG Signing" \
        "signing.keyId=${_KEY_ID}" \
        "signing.password=${_KEY_PASS}" \
        "signing.secretKeyRingFile=${_KEYRING_PATH}"
    echo "✅ signing.keyId/signing.password/signing.secretKeyRingFile 설정 완료 (keyId: ${_KEY_ID})"

    echo ""
    echo "🎉 Maven Central 배포용 설정이 모두 완료되었습니다. ($GRADLE_PROPS_FILE)"
}
