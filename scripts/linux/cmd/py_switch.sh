#!/bin/bash

# =================================================================
# 프로그램명: py_switch.sh
# 기능: 상대 경로를 기반으로 PYTHON_HOME 버전을 전환 (314, 312)
#       - ~/.bashrc 또는 ~/.zshrc 등에 PYTHON_HOME 및 PATH를 업데이트합니다.
#       - 기존 PYTHON_HOME 설정이 존재하면 해당 라인을 수정하고, 없으면 추가합니다.
# 사용법: source py_switch.sh 314  (또는 312)
#         또는 . py_switch.sh 314
# =================================================================

# 1. 필수 인자(파이썬 버전) 확인
VERSION=$1
if [ -z "$VERSION" ]; then
    echo "[Error] 파이썬 버전을 입력해주세요 (314, 312)."
    echo "사용법: source py_switch.sh 314"
    return 1 2>/dev/null || exit 1
fi

# 2. 기준 경로 설정 (스크립트 실제 위치 추출)
# source로 실행될 때와 직접 실행될 때를 모두 고려
if [ -n "$BASH_SOURCE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# 3. 버전별 폴더명 설정 (python-버전 형식)
FOLDER_NAME="python-$VERSION"

# 4. 상대 경로를 사용하여 최종 절대 경로 계산
# scripts/linux/cmd -> ../../../modules/python/
TARGET_PATH="$(cd "$SCRIPT_DIR/../../../modules/python/$FOLDER_NAME" 2>/dev/null && pwd)"

# 만약 상대 경로 계산에 실패하거나 해당 폴더가 없으면 요청하신 고정 경로를 차선책으로 탐색
if [ -z "$TARGET_PATH" ] || [ ! -d "$TARGET_PATH" ]; then
    TARGET_PATH="/home/eseungsu/_devtools2/modules/python/$FOLDER_NAME"
fi

if [ ! -d "$TARGET_PATH" ]; then
    echo "[Error] 해당 파이썬 경로를 찾을 수 없습니다."
    echo "예상 경로: $SCRIPT_DIR/../../../modules/python/$FOLDER_NAME 또는 /home/eseungsu/_devtools2/modules/python/$FOLDER_NAME"
    return 1 2>/dev/null || exit 1
fi

# 5. 환경 변수 적용
echo "[정보] Python $VERSION (폴더: $FOLDER_NAME) 버전으로 전환을 시도합니다..."
echo "[정보] 경로: $TARGET_PATH"

# 현재 세션에 즉시 적용
export PYTHON_HOME="$TARGET_PATH"

# 기존 PATH에서 현재 PYTHON_HOME/bin이 아닌 다른 DEVTOOLS2 Python 경로를 제거
# (이전 py_switch 실행으로 인해 여러 개가 있을 수 있으므로)
# 그리고 나서 새로운 PYTHON_HOME/bin을 PATH 맨 앞에 추가
CURRENT_PATH_WITHOUT_OLD_PYTHON_BIN=$(echo "$PATH" | sed -e "s|[^:]*/modules/python/python-[0-9]*/bin:||g" -e "s|:[^:]*/modules/python/python-[0-9]*/bin||g" -e "s|^[^:]*/modules/python/python-[0-9]*/bin:||g")
export PATH="$PYTHON_HOME/bin:$CURRENT_PATH_WITHOUT_OLD_PYTHON_BIN"

# 6. 영구 적용 (사용자 홈의 설정 파일 업데이트)
SHELL_RC=""
if [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

if [ -f "$SHELL_RC" ]; then
    # 기존 'export PYTHON_HOME=' 문자열로 시작하는 라인이 있는지 검사
    if grep -q "^export PYTHON_HOME=" "$SHELL_RC"; then
        # 기존 설정이 존재하면 해당 라인을 새로운 TARGET_PATH 값으로 치환 (구분자로 | 사용)
        sed -i "s|^export PYTHON_HOME=.*|export PYTHON_HOME=\"$TARGET_PATH\"|" "$SHELL_RC"
        echo "[확인] $SHELL_RC 의 기존 PYTHON_HOME 경로가 업데이트되었습니다."
    else
        # 기존 설정이 존재하지 않으면 파일 맨 끝에 새롭게 추가
        echo "export PYTHON_HOME=\"$TARGET_PATH\"" >>"$SHELL_RC"
        echo "[확인] $SHELL_RC 에 새로운 PYTHON_HOME이 추가되었습니다."
    fi
else
    echo "[경고] 쉘 설정 파일(.bashrc 또는 .zshrc)을 찾을 수 없어 영구 적용은 수동으로 진행해야 합니다."
fi

echo "[완료] 현재 쉘에 Python $VERSION 버전이 적용되었습니다."
python3 --version 2>/dev/null || python --version
