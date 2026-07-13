#!/usr/bin/env bash
# DevTools2 초기화 스크립트 (0.init-devtools2.sh)
# 사용법: sudo /path/to/0.init-devtools2.sh
#
# 목적:
# - Git 인증 정보 설정 (user.name / user.email / PAT 토큰)
# - /var/opt/_devtools2 에 저장소 클론
# - 운영 환경에서 여러 개발자가 DevTools2 디렉토리를 안전하게 공유할 수 있도록
#   그룹 소유권 및 퍼미션, SGID를 설정합니다.

set -euo pipefail

# 0) 스크립트 위치 기준 상위의 상위의 상위 디렉토리를 DEVTOOLS2로 고정 설정
# 리눅스에서 기본 전역 환경변수를 제외한 사용자 정의의 시스템 전역 환경 변수는 없음
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")

DEVTOOLS2_GROUP=devers

# 루트 권한 체크
if [ "$(id -u)" -ne 0 ]; then
    echo "[오류] 이 스크립트는 관리자(root) 권한으로 실행해야 합니다. sudo로 실행하세요."
    exit 1
fi

# 스크립트를 실제 호출한 사용자(관리자가 sudo로 실행한 경우 SUDO_USER를 우선 사용)
INVOKER="${SUDO_USER:-${USER:-root}}"
INVOKER_HOME=$(getent passwd "$INVOKER" | cut -d: -f6)

TARGET_DIR="/var/opt/_devtools2"
SHOULD_CLONE=false

# 1) 디렉터리 존재 여부 검사 및 신규 형상관리 추가 여부 확인
if [ -d "$TARGET_DIR" ]; then
    echo ""
    echo "==========================================================================="
    echo "[알림] 이미 개발도구 디렉터리($TARGET_DIR)가 존재합니다."
    read -r -p "💡 기존 디렉터리를 백업하고 새로운 형상관리(클론)를 추가하시겠습니까? (y/N): " choice </dev/tty
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
    if [ "$choice" = "y" ]; then
        SHOULD_CLONE=true
    fi
else
    # 디렉터리가 없으면 무조건 신규 클론 진행
    SHOULD_CLONE=true
fi

# 2) 신규 클론 진행을 위한 백업 및 준비
if [ "$SHOULD_CLONE" = true ]; then
    # 2-1) 기존 디렉터리 백업
    if [ -d "$TARGET_DIR" ]; then
        BACKUP_SUFFIX=$(date +"%Y%m%d_%H%M%S")
        BACKUP_DIR="${TARGET_DIR}_backup_${BACKUP_SUFFIX}"
        echo "[백업] 기존 디렉터리를 백업합니다: $TARGET_DIR -> $BACKUP_DIR"
        mv "$TARGET_DIR" "$BACKUP_DIR"
    fi

    # 2-2) 신규 클론 수행
    echo "[작업] DevTools2 포터블 개발 환경 클론 중..."

    # 디렉터리를 미리 만들고 소유권을 $INVOKER로 이전해 주어야
    # 일반 사용자 권한(sudo -u $INVOKER)으로 안전하게 쓰기(클론)가 가능합니다.
    mkdir -p "$TARGET_DIR"
    chown -R "$INVOKER" "$TARGET_DIR"

    # 공개 저장소이므로 토큰 인증 없이 호출자 권한으로 클론을 진행합니다.
    if ! sudo -u "$INVOKER" git clone https://github.com/devers2/_devtools2.git "$TARGET_DIR"; then
        echo "[오류] 깃 클론에 실패했습니다. 네트워크 상태나 저장소 URL을 확인해주세요."
        # 실패 시 롤백 (백업이 존재했다면 복구)
        if [ -d "${BACKUP_DIR:-}" ]; then
            echo "[복구] 클론 실패로 인해 백업본을 다시 원복합니다..."
            rm -rf "$TARGET_DIR"
            mv "$BACKUP_DIR" "$TARGET_DIR"
        fi
        exit 1
    fi
    echo "  ✅ 깃 클론 완료!"

    # 클론 완료 후 이 스크립트의 실행 경로 및 DEVTOOLS2 변수를 클론된 경로로 덮어씌움
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
        # Avoid forcing a su/login shell here — it can fail in some environments (no controlling TTY,
        # login hooks trying to access /dev/tty, etc.). Just inform the user how to apply the change.
        echo "[안내] 사용자 '$INVOKER'에 그룹 변경을 적용하려면 해당 사용자 세션에서 'newgrp $DEVTOOLS2_GROUP'을 실행하거나 재로그인하세요."
    fi
fi

# 3) 소유권 설정: INVOKER:GROUP
if [ ! -d "$DEVTOOLS2" ]; then
    echo "[오류] DEVTOOLS2 디렉토리를 찾을 수 없습니다: $DEVTOOLS2"
    exit 1
fi
echo "[작업] $DEVTOOLS2 및 하위 항목의 소유권을 $INVOKER:$DEVTOOLS2_GROUP 으로 설정합니다..."
chown -R "$INVOKER:$DEVTOOLS2_GROUP" "$DEVTOOLS2"

# 4) 디렉토리 권한(2775, SGID) 및 파일 권한(664) 설정
#   - SGID(2xxx)는 새로 생성되는 파일/디렉터리가 부모 디렉터리의 그룹을 상속하게 함
#   - 디렉터리: 2775 -> rwxrwsr-x (소유자 rwx, 그룹 rwx, others r-x, 디렉터리에 SGID 설정)
#   - 파일: 664 -> rw-rw-r-- (소유자 rw, 그룹 rw, others r)

echo "[작업] 디렉토리와 파일 퍼미션을 조정합니다 (디렉토리: 2775, 파일: group-writable 유지, 실행권한 보존)..."
find "$DEVTOOLS2" -type d -exec chmod 2775 {} +
# 파일: 읽기 권한을 모두에게 부여하고, 소유자/그룹에 쓰기 권한을 추가하여 실행 비트 보존
find "$DEVTOOLS2" -type f -exec chmod a+r,u+w,g+w {} +

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

  sudo $DEVTOOLS2/scripts/linux/devtools2/add-devtools2-user.sh <username> [<username> ...]

  예: sudo $DEVTOOLS2/scripts/linux/devtools2/add-devtools2-user.sh alice bob

  ❗중요: 다른 사용자를 그룹에 추가하려면 반드시 위 add-devtools2-user.sh 스크립트를 사용하세요. add-devtools2-user.sh는 사용자를 생성(필요 시), 그룹에 추가하고 각 사용자의 쉘 초기화 파일에 umask 002를 추가합니다.

완료되었습니다.
EOF
