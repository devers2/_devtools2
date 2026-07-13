#!/usr/bin/env bash
# DevTools2 사용자 그룹 추가 및 umask 설정 스크립트
# 사용법: sudo /var/opt/_devtools2/scripts/linux/devtools2/add-devtools2-user.sh <username> [<username> ...]
# 목적:
# - 지정한 사용자들을 'devers' 그룹에 추가
# - 각 사용자의 홈 디렉터리 ~/.profile에 umask 002 설정을 추가하여 그룹 쓰기 권한을 보장
# - 존재하지 않는 사용자가 주어지면 홈 디렉토리를 생성하여 기본 사용자로 추가함

set -euo pipefail

# 스크립트 위치 기준 상위의 상위의 상위 디렉토리를 DEVTOOLS2로 설정
# 리눅스에서 기본 전역 환경변수를 제외한 사용자 정의의 시스템 전역 환경 변수는 없음
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
DEVTOOLS2="${DEVTOOLS2:-$(readlink -f "$SCRIPT_DIR/../../..")}"

DEVTOOLS2_GROUP=devers

usage() {
  echo "사용법: sudo $0 <username> [<username> ...]"
  echo "예: sudo $0 alice bob"
  exit 1
}

if [ "$#" -lt 1 ]; then
  echo "[오류] 사용자 이름을 하나 이상 지정해야 합니다."
  usage
fi

# 스크립트는 관리자 권한으로 실행되어야 함
if [ "$(id -u)" -ne 0 ]; then
  echo "[오류] 이 스크립트는 관리자(root) 권한으로 실행되어야 합니다. sudo로 실행하세요."
  exit 1
fi

for USERNAME in "$@"; do
  printf '\n[진행] 사용자 처리: %s\n' "$USERNAME"

  # 1) 사용자 존재 여부 확인
  if id "$USERNAME" >/dev/null 2>&1; then
    echo "[확인] 사용자 '$USERNAME' 존재함"
  else
    echo "[작업] 사용자 '$USERNAME'가 존재하지 않습니다. 홈 디렉토리와 함께 새 사용자로 생성합니다."
    useradd -m -s /bin/bash "$USERNAME"
    echo "[완료] 사용자 '$USERNAME' 생성됨"
  fi

  # 2) 그룹 존재 여부 확인 및 생성(없으면)
  if getent group "$DEVTOOLS2_GROUP" >/dev/null 2>&1; then
    echo "[확인] 그룹 '$DEVTOOLS2_GROUP' 존재함"
  else
    echo "[작업] 그룹 '$DEVTOOLS2_GROUP'가 존재하지 않습니다. 그룹을 생성합니다..."
    groupadd "$DEVTOOLS2_GROUP"
    echo "[완료] 그룹 '$DEVTOOLS2_GROUP' 생성됨"
  fi

  # 3) 사용자를 그룹에 추가
  if id -nG "$USERNAME" | grep -qw "$DEVTOOLS2_GROUP"; then
    echo "[확인] '$USERNAME'는 이미 그룹 '$DEVTOOLS2_GROUP'에 속해 있습니다."
  else
    usermod -aG "$DEVTOOLS2_GROUP" "$USERNAME"
    echo "[완료] '$USERNAME'를 그룹 '$DEVTOOLS2_GROUP'에 추가했습니다."
  fi

  # 4) 사용자의 프로파일에 umask 설정 추가
  USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
  if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
    echo "[경고] 홈 디렉토리를 찾을 수 없습니다: $USER_HOME. 건너뜁니다."
    continue
  fi

  # 여러 쉘 초기화 파일에 umask 설정을 추가하여 사용자 환경( bash, zsh 등)에서 동작하도록 함
  UMASK_SNIPPET="# DevTools2: 그룹 공유 디렉토리와 협업을 위한 umask 설정\nif [ -d \"$DEVTOOLS2\" ]; then\n  umask 002\nfi"
  PROFILES=(".profile" ".bashrc" ".bash_profile" ".zshrc")

  for P in "${PROFILES[@]}"; do
    PROFILE_FILE="$USER_HOME/$P"
    # 파일이 없으면 생성
    if [ ! -f "$PROFILE_FILE" ]; then
      echo "[작업] $PROFILE_FILE 파일이 없습니다. 새로 생성합니다."
      touch "$PROFILE_FILE"
      chown "$USERNAME:$USERNAME" "$PROFILE_FILE"
      chmod 644 "$PROFILE_FILE"
    fi

    # 이미 스니펫이 있으면 건너뜀
    if grep -Fq "DevTools2: 그룹 공유 디렉토리와 협업을 위한 umask 설정" "$PROFILE_FILE" 2>/dev/null; then
      echo "[확인] $PROFILE_FILE에 이미 umask 설정이 있습니다."
    else
      echo "[작업] $PROFILE_FILE에 umask 설정을 추가합니다..."
      echo -e "\n$UMASK_SNIPPET\n" >>"$PROFILE_FILE"
      chown "$USERNAME:$USERNAME" "$PROFILE_FILE"
      echo "[완료] $PROFILE_FILE 업데이트됨"
    fi
  done

  # 5) 사용자의 변경된 그룹과 umask 적용 안내
  echo "[안내] 사용자가 변경된 그룹/umask를 바로 적용하려면 해당 사용자로 다시 로그인하세요"

done

# 최종 요약
cat <<EOF

[요약] 완료되었습니다.
- 처리된 사용자: $*
- 대상 그룹: $DEVTOOLS2_GROUP

EOF
