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

# 만약 상대 경로 계산에 실패하거나 해당 폴더가 없으면 DEVTOOLS2 경로를 차선책으로 탐색
if [ -z "$TARGET_PATH" ] || [ ! -d "$TARGET_PATH" ]; then
    TARGET_PATH="$DEVTOOLS2/modules/python/$FOLDER_NAME"
fi

if [ ! -d "$TARGET_PATH" ]; then
    echo "[Error] 해당 파이썬 경로를 찾을 수 없습니다."
    echo "예상 경로: $SCRIPT_DIR/../../../modules/python/$FOLDER_NAME 또는 $DEVTOOLS2/modules/python/$FOLDER_NAME"
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
# ⚠️ $ZSH_VERSION/$BASH_VERSION은 "지금 이 스크립트를 실행 중인 셸"만 알려줍니다.
# command-palette(#!/usr/bin/env bash로 실행되는 별도 프로세스)를 통해 source될 경우
# 사용자의 로그인 셸이 zsh여도 이 스크립트 자신은 항상 bash 프로세스이므로 $BASH_VERSION만
# 잡혀 .bashrc에 잘못 기록되고 zsh 세션에는 영구 반영되지 않습니다. 로그인 셸을 정확히
# 반영하는 $SHELL(로그인 시 설정되어 하위 프로세스에도 상속됨)을 우선 사용합니다.
# DT2_SWITCH_NO_PERSIST=1 이면 현재 셸에만 적용하고 영구 저장(local.sh / .zshrc)은 건너뜁니다.
# (프로젝트 셋업 스크립트가 빌드에 필요한 버전으로 잠깐 전환할 때 사용자 기본값을 바꾸지 않기 위함)
SHELL_RC=""
if [ "${DT2_SWITCH_NO_PERSIST:-0}" = "1" ]; then
    echo "[정보] 현재 셸에만 적용합니다 (DT2_SWITCH_NO_PERSIST=1, 기본 Python 설정은 변경하지 않음)."
else
case "$SHELL" in
*/zsh) SHELL_RC="$HOME/.zshrc" ;;
*/bash) SHELL_RC="$HOME/.bashrc" ;;
*)
    # $SHELL이 없거나 인식할 수 없으면 현재 실행 중인 셸 기준으로 폴백
    if [ -n "$ZSH_VERSION" ]; then
        SHELL_RC="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        SHELL_RC="$HOME/.bashrc"
    fi
    ;;
esac

# bash: ~/.config/devtools2/local.sh 의 DT2_PYTHON_HOME 에 저장합니다.
#   ~/.bashrc 맨 앞에서 읽는 env.sh 가 이 값으로 PYTHON_HOME 와 PATH 를 함께 만들기 때문에,
#   ~/.bashrc 끝에 "export PYTHON_HOME=" 만 덧붙이던 예전 방식(PATH 는 그대로라 java/python 명령과
#   PYTHON_HOME 가 서로 다른 버전을 가리킴, 비대화형 셸에는 반영 안 됨)을 쓰지 않습니다.
if [ "$SHELL_RC" = "$HOME/.bashrc" ]; then
    _DT2_LOCAL_ENV="$HOME/.config/devtools2/local.sh"
    mkdir -p "$(dirname "$_DT2_LOCAL_ENV")"
    touch "$_DT2_LOCAL_ENV"
    if grep -q "^DT2_PYTHON_HOME=" "$_DT2_LOCAL_ENV"; then
        sed -i "s|^DT2_PYTHON_HOME=.*|DT2_PYTHON_HOME=\"$TARGET_PATH\"|" "$_DT2_LOCAL_ENV"
    else
        echo "DT2_PYTHON_HOME=\"$TARGET_PATH\"" >>"$_DT2_LOCAL_ENV"
    fi
    echo "[확인] $_DT2_LOCAL_ENV 에 Python 선택(DT2_PYTHON_HOME)을 저장했습니다. (새 셸·비대화형 셸 모두 적용)"
    # 예전 방식으로 ~/.bashrc 에 남은 "export PYTHON_HOME=" 줄은 env.sh 의 값을 덮어써 PATH 와 어긋나게 하므로 제거
    if [ -f "$SHELL_RC" ] && grep -q "^export PYTHON_HOME=" "$SHELL_RC"; then
        sed -i "/^export PYTHON_HOME=/d" "$SHELL_RC"
        echo "[정리] $SHELL_RC 에 남아 있던 예전 'export PYTHON_HOME=' 줄을 제거했습니다."
    fi
    # systemd 사용자 서비스용 environment.d 에도 반영 (파일이 있을 때만)
    _DT2_ENVD="$HOME/.config/environment.d/devtools2.conf"
    if [ -f "$_DT2_ENVD" ]; then
        _old_home=$(grep "^PYTHON_HOME=" "$_DT2_ENVD" | head -1 | cut -d= -f2-)
        sed -i "s|^PYTHON_HOME=.*|PYTHON_HOME=$TARGET_PATH|" "$_DT2_ENVD"
        [ -n "$_old_home" ] && sed -i "s|$_old_home/bin|$TARGET_PATH/bin|g" "$_DT2_ENVD"
    fi
elif [ -f "$SHELL_RC" ]; then
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
fi

echo "[완료] 현재 쉘에 Python $VERSION 버전이 적용되었습니다."
python3 --version 2>/dev/null || python --version
