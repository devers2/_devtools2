#!/bin/bash

# =================================================================
# 프로그램명: jdk_switch.sh
# 기능: 상대 경로를 기반으로 JAVA_HOME 버전을 전환 (25, 21, 17, 8)
#       - bash: ~/.config/devtools2/local.sh 에 DT2_JAVA_HOME 로 저장 (env.sh 가 JAVA_HOME·PATH 생성)
#       - zsh: ~/.zshrc 의 JAVA_HOME 를 업데이트합니다.
#       - 기존 JAVA_HOME 설정이 존재하면 해당 라인을 수정하고, 없으면 추가합니다.
# 사용법: source jdk_switch.sh 25  (또는 21, 17, 8)
#         또는 . jdk_switch.sh 25
# =================================================================

# 1. 필수 인자(자바 버전) 확인
VERSION=$1
if [ -z "$VERSION" ]; then
    echo "[Error] 자바 버전을 입력해주세요 (25, 21, 17, 8)."
    echo "사용법: source jdk_switch.sh 25"
    return 1 2>/dev/null || exit 1
fi

# 2. 기준 경로 설정 (스크립트 실제 위치 추출)
# source로 실행될 때와 직접 실행될 때를 모두 고려
if [ -n "$BASH_SOURCE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
DEVTOOLS2="${DEVTOOLS2:-$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)}"

# 3. 버전별 폴더명 설정 (8버전은 jdk-1.8 사용, 그 외는 jdk-버전 형식)
FOLDER_NAME=""
if [ "$VERSION" = "8" ]; then
    FOLDER_NAME="jdk-1.8"
else
    FOLDER_NAME="jdk-$VERSION"
fi

# 4. 상대 경로를 사용하여 최종 절대 경로 계산
# scripts/linux/cmd -> ../../../modules/java/
TARGET_PATH="$(cd "$SCRIPT_DIR/../../../modules/java/$FOLDER_NAME" 2>/dev/null && pwd)"

if [ -z "$TARGET_PATH" ] || [ ! -d "$TARGET_PATH" ]; then
    echo "[Error] 해당 JDK 경로를 찾을 수 없습니다."
    echo "예상 경로: $SCRIPT_DIR/../../../modules/java/$FOLDER_NAME"
    return 1 2>/dev/null || exit 1
fi

# 5. 환경 변수 적용
echo "[정보] Java $VERSION (폴더: $FOLDER_NAME) 버전으로 전환을 시도합니다..."
echo "[정보] 경로: $TARGET_PATH"
if [ "$VERSION" = "8" ]; then
    echo "⚠️  [호환성 주의] Gradle 9 실행 불가 (JVM 17+ 필요)"
    echo "   JDK 8 환경에서는 Gradle 9 빌드가 실행되지 않으므로, Java 8 프로젝트는 Gradle 툴체인을 권장합니다."
fi

# 현재 세션에 즉시 적용
export JAVA_HOME="$TARGET_PATH"

# 기존 PATH에서 현재 JAVA_HOME/bin이 아닌 다른 DEVTOOLS2 Java 경로를 제거
# (이전 jdk_switch 실행으로 인해 여러 개가 있을 수 있으므로)
# 그리고 나서 새로운 JAVA_HOME/bin을 PATH 맨 앞에 추가
CURRENT_PATH_WITHOUT_OLD_JAVA_BIN=$(echo "$PATH" | sed -e "s|${DEVTOOLS2}/modules/java/jdk-[0-9.]*/bin:||g" -e "s|:${DEVTOOLS2}/modules/java/jdk-[0-9.]*/bin||g" -e "s|^${DEVTOOLS2}/modules/java/jdk-[0-9.]*/bin:||g")
export PATH="$JAVA_HOME/bin:$CURRENT_PATH_WITHOUT_OLD_JAVA_BIN"

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
    echo "[정보] 현재 셸에만 적용합니다 (DT2_SWITCH_NO_PERSIST=1, 기본 JDK 설정은 변경하지 않음)."
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

# bash: ~/.config/devtools2/local.sh 의 DT2_JAVA_HOME 에 저장합니다.
#   ~/.bashrc 맨 앞에서 읽는 env.sh 가 이 값으로 JAVA_HOME 와 PATH 를 함께 만들기 때문에,
#   ~/.bashrc 끝에 "export JAVA_HOME=" 만 덧붙이던 예전 방식(PATH 는 그대로라 java/python 명령과
#   JAVA_HOME 가 서로 다른 버전을 가리킴, 비대화형 셸에는 반영 안 됨)을 쓰지 않습니다.
if [ "$SHELL_RC" = "$HOME/.bashrc" ]; then
    _DT2_LOCAL_ENV="$HOME/.config/devtools2/local.sh"
    mkdir -p "$(dirname "$_DT2_LOCAL_ENV")"
    touch "$_DT2_LOCAL_ENV"
    if grep -q "^DT2_JAVA_HOME=" "$_DT2_LOCAL_ENV"; then
        sed -i "s|^DT2_JAVA_HOME=.*|DT2_JAVA_HOME=\"$TARGET_PATH\"|" "$_DT2_LOCAL_ENV"
    else
        echo "DT2_JAVA_HOME=\"$TARGET_PATH\"" >>"$_DT2_LOCAL_ENV"
    fi
    echo "[확인] $_DT2_LOCAL_ENV 에 JDK 선택(DT2_JAVA_HOME)을 저장했습니다. (새 셸·비대화형 셸 모두 적용)"
    # 예전 방식으로 ~/.bashrc 에 남은 "export JAVA_HOME=" 줄은 env.sh 의 값을 덮어써 PATH 와 어긋나게 하므로 제거
    if [ -f "$SHELL_RC" ] && grep -q "^export JAVA_HOME=" "$SHELL_RC"; then
        sed -i "/^export JAVA_HOME=/d" "$SHELL_RC"
        echo "[정리] $SHELL_RC 에 남아 있던 예전 'export JAVA_HOME=' 줄을 제거했습니다."
    fi
    # systemd 사용자 서비스용 environment.d 에도 반영 (파일이 있을 때만)
    _DT2_ENVD="$HOME/.config/environment.d/devtools2.conf"
    if [ -f "$_DT2_ENVD" ]; then
        _old_home=$(grep "^JAVA_HOME=" "$_DT2_ENVD" | head -1 | cut -d= -f2-)
        sed -i "s|^JAVA_HOME=.*|JAVA_HOME=$TARGET_PATH|" "$_DT2_ENVD"
        [ -n "$_old_home" ] && sed -i "s|$_old_home/bin|$TARGET_PATH/bin|g" "$_DT2_ENVD"
    fi
elif [ -f "$SHELL_RC" ]; then
    # 기존 'export JAVA_HOME=' 문자열로 시작하는 라인이 있는지 검사
    if grep -q "^export JAVA_HOME=" "$SHELL_RC"; then
        # 기존 설정이 존재하면 해당 라인을 새로운 TARGET_PATH 값으로 치환 (구분자로 | 사용)
        sed -i "s|^export JAVA_HOME=.*|export JAVA_HOME=\"$TARGET_PATH\"|" "$SHELL_RC"
        echo "[확인] $SHELL_RC 의 기존 JAVA_HOME 경로가 업데이트되었습니다."
    else
        # 기존 설정이 존재하지 않으면 파일 맨 끝에 새롭게 추가
        echo "export JAVA_HOME=\"$TARGET_PATH\"" >>"$SHELL_RC"
        echo "[확인] $SHELL_RC 에 새로운 JAVA_HOME이 추가되었습니다."
    fi
else
    echo "[경고] 쉘 설정 파일(.bashrc 또는 .zshrc)을 찾을 수 없어 영구 적용은 수동으로 진행해야 합니다."
fi
fi

echo "[완료] 현재 쉘에 Java $VERSION 버전이 적용되었습니다."
java -version
