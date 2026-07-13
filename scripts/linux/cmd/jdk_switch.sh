#!/bin/bash

# =================================================================
# 프로그램명: jdk_switch.sh
# 기능: 상대 경로를 기반으로 JAVA_HOME 버전을 전환 (25, 21, 17, 8)
#       - ~/.bashrc 또는 ~/.zshrc 등에 JAVA_HOME을 업데이트합니다.
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

# 현재 세션에 즉시 적용
export JAVA_HOME="$TARGET_PATH"

# 기존 PATH에서 현재 JAVA_HOME/bin이 아닌 다른 DEVTOOLS2 Java 경로를 제거
# (이전 jdk_switch 실행으로 인해 여러 개가 있을 수 있으므로)
# 그리고 나서 새로운 JAVA_HOME/bin을 PATH 맨 앞에 추가
CURRENT_PATH_WITHOUT_OLD_JAVA_BIN=$(echo "$PATH" | sed -e "s|${DEVTOOLS2}/modules/java/jdk-[0-9.]*/bin:||g" -e "s|:${DEVTOOLS2}/modules/java/jdk-[0-9.]*/bin||g" -e "s|^${DEVTOOLS2}/modules/java/jdk-[0-9.]*/bin:||g")
export PATH="$JAVA_HOME/bin:$CURRENT_PATH_WITHOUT_OLD_JAVA_BIN"

# 6. 영구 적용 (사용자 홈의 설정 파일 업데이트)
SHELL_RC=""
if [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

if [ -f "$SHELL_RC" ]; then
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

echo "[완료] 현재 쉘에 Java $VERSION 버전이 적용되었습니다."
java -version
