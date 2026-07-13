#!/bin/bash

# =================================================================
# DevTools2 핵심 포터블 도구 설치 스크립트 (2.install-core-tools.sh)
# 대상: Java(8/17/21/25), Gradle, Python, Node.js, Neovim, Ghostty
# =================================================================

# 로그 설정: data/logs 폴더에 실행 시점별로 기록
LOG_DIR="$DEVTOOLS2/data/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy_$(date +%Y%m%d_%H%M%S).log"

# 아키텍처 확인
ARCH=$(uname -m)
IS_ARM64=false
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    IS_ARM64=true
fi

# WSL2 환경 감지: /proc/version에 'microsoft' 문자열이 포함되어 있으면 WSL2로 판단한다.
IS_WSL2=false
if grep -qi 'microsoft' /proc/version 2>/dev/null; then
    IS_WSL2=true
fi

# 아키텍처에 따라 적절한 URL을 선택하여 다운로드 및 압축 해제 함수
install_tool() {
    local X64_URL="$1"
    local ARM_URL="$2"
    local TARGET_DIR="$3"
    local DOWNLOAD_URL
    local FILE_NAME

    # 아키텍처에 맞는 URL 선택
    if [ "$IS_ARM64" = true ]; then
        DOWNLOAD_URL="$ARM_URL"
    else
        DOWNLOAD_URL="$X64_URL"
    fi

    FILE_NAME=$(basename "$DOWNLOAD_URL")

    # 다운로드 및 압축 해제
    wget -q "$DOWNLOAD_URL"
    tar -xf "$FILE_NAME"

    # 폴더 이름 정리 (패턴 매칭으로 이동 후 정리)
    # 압축 해제된 폴더가 무엇이든 TARGET_DIR로 변경
    local EXTRACTED_DIR=$(tar -tf "$FILE_NAME" | head -1 | cut -f1 -d"/")
    mv "$EXTRACTED_DIR" "$TARGET_DIR"

    rm "$FILE_NAME"
    echo "   ✅ $TARGET_DIR ($ARCH) 설치 완료"
}

# 모든 표준 출력(stdout)과 표준 에러(stderr)를 터미널과 로그 파일에 동시에 기록
exec > >(tee -i "$LOG_FILE") 2>&1

# 오류 발생 시 즉시 중단 설정
set -e

echo ""
echo "==========================================================================="
echo "🚀 DevTools2 포터블 개발 환경 설치를 시작합니다..."
echo ""
echo "📍 최상위 경로: $DEVTOOLS2"
echo "📝 로그 파일: $LOG_FILE"
echo ""

echo "---------------------------------------------------------------------------"
# 1. JAVA 포터블 설치
echo "☕ 1. JAVA 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/java"
cd "$DEVTOOLS2/modules/java"

# JDK 1.8
if [ -d "$DEVTOOLS2/modules/java/jdk-1.8" ]; then
    echo "   ⏭️ [건너뜀] JDK 1.8 설치 디렉토리 jdk-1.8이 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/java/jdk-1.8'"
else
    echo "   📦 JDK 1.8 다운로드 및 압축 해제..."
    install_tool \
        'https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u482-b08/OpenJDK8U-jdk_x64_linux_hotspot_8u482b08.tar.gz' \
        'https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u482-b08/OpenJDK8U-jdk_aarch64_linux_hotspot_8u482b08.tar.gz' \
        'jdk-1.8'
fi

# JDK 17
if [ -d "$DEVTOOLS2/modules/java/jdk-17" ]; then
    echo "   ⏭️ [건너뜀] JDK 17 설치 디렉토리 jdk-17이 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/java/jdk-17'"
else
    echo "   📦 JDK 17 다운로드 및 압축 해제..."
    install_tool \
        'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.18%2B8/OpenJDK17U-jdk_x64_linux_hotspot_17.0.18_8.tar.gz' \
        'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.18%2B8/OpenJDK17U-jdk_aarch64_linux_hotspot_17.0.18_8.tar.gz' \
        'jdk-17'
fi

# JDK 21
if [ -d "$DEVTOOLS2/modules/java/jdk-21" ]; then
    echo "   ⏭️ [건너뜀] JDK 21 설치 디렉토리 jdk-21이 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/java/jdk-21'"
else
    echo "   📦 JDK 21 다운로드 및 압축 해제..."
    install_tool \
        'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.10%2B7/OpenJDK21U-jdk_x64_linux_hotspot_21.0.10_7.tar.gz' \
        'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.10%2B7/OpenJDK21U-jdk_aarch64_linux_hotspot_21.0.10_7.tar.gz' \
        'jdk-21'
fi

# JDK 25
if [ -d "$DEVTOOLS2/modules/java/jdk-25" ]; then
    echo "   ⏭️ [건너뜀] JDK 25 설치 디렉토리 jdk-25이 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/java/jdk-25'"
else
    echo "   📦 JDK 25 다운로드 및 압축 해제..."
    install_tool \
        'https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.2%2B10/OpenJDK25U-jdk_x64_linux_hotspot_25.0.2_10.tar.gz' \
        'https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.2%2B10/OpenJDK25U-jdk_aarch64_linux_hotspot_25.0.2_10.tar.gz' \
        'jdk-25'
fi

echo "✅ JAVA 설치 완료 ($ARCH)"
echo ""

echo "---------------------------------------------------------------------------"
# 2. Gradle 포터블 설치
echo "🐘 2. Gradle 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/gradle"
cd "$DEVTOOLS2/modules/gradle"

if [ -d "$DEVTOOLS2/modules/gradle/gradle-9" ]; then
    echo "   ⏭️ [건너뜀] gradle-9 디렉토리가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/gradle/gradle-9'"
else
    wget -q https://services.gradle.org/distributions/gradle-9.4.1-bin.zip
    unzip -q gradle-9.4.1-bin.zip
    mv gradle-9.4.1 gradle-9
    rm gradle-9.4.1-bin.zip
fi

echo "✅ Gradle 설치 완료"
echo ""

echo "---------------------------------------------------------------------------"
# 3. Python 포터블 설치
echo "🐍 3. Python 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/python"
cd "$DEVTOOLS2/modules/python"

if [ -d "$DEVTOOLS2/modules/python/python-314" ]; then
    echo "   ⏭️ [건너뜀] python-314 디렉토리가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/python/python-314'"
else
    install_tool \
        'https://github.com/indygreg/python-build-standalone/releases/download/20260414/cpython-3.14.4+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz' \
        'https://github.com/indygreg/python-build-standalone/releases/download/20260414/cpython-3.14.4+20260414-aarch64-unknown-linux-gnu-install_only.tar.gz' \
        'python-314'
fi

if [ -d "$DEVTOOLS2/modules/python/python-312" ]; then
    echo "   ⏭️ [건너뜀] python-312 디렉토리가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/python/python-312'"
else
    install_tool \
        'https://github.com/astral-sh/python-build-standalone/releases/download/20260414/cpython-3.12.13+20260414-x86_64-unknown-linux-gnu-install_only.tar.gz' \
        'https://github.com/astral-sh/python-build-standalone/releases/download/20260414/cpython-3.12.13+20260414-aarch64-unknown-linux-gnu-install_only.tar.gz' \
        'python-312'
fi

echo "✅ Python 설치 완료 ($ARCH)"
echo ""

echo "---------------------------------------------------------------------------"
# 4. Node.js 포터블 설치
echo "🟢 4. Node.js 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/nodejs"
cd "$DEVTOOLS2/modules/nodejs"

if [ -d "$DEVTOOLS2/modules/nodejs/node-v24" ]; then
    echo "   ⏭️ [건너뜀] node-v24 디렉토리가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -rf '$DEVTOOLS2/modules/nodejs/node-v24'"
else
    install_tool \
        'https://nodejs.org/dist/v24.15.0/node-v24.15.0-linux-x64.tar.xz' \
        'https://nodejs.org/dist/v24.15.0/node-v24.15.0-linux-arm64.tar.xz' \
        'node-v24'
fi

# 전역 패키지 저장소 생성 및 복구
mkdir -p "$DEVTOOLS2/data/.npm-packages"
cd "$DEVTOOLS2/data/.npm-packages"

if [ -f "package.json" ]; then
    echo "   📦 글로벌 npm 패키지 복구 중..."
    npm install
fi

# rsync를 사용하여 기존 node_modules 내용을 lib/node_modules로 강제 통합(덮어쓰기) 후 기존 디렉토리 삭제
# Windows 글로벌 패키지 경로: .npm-packages/node_modules
# Linux 글로벌 패키지 경로: .npm-packages/lib/node_modules
echo "   📂 npm 패키지 구조 정리 중..."
mkdir -p lib/node_modules
if [ -d "node_modules" ]; then
    rsync -avq --remove-source-files node_modules/ lib/node_modules/
    find node_modules -type d -empty -delete 2>/dev/null
fi
echo "✅ Node.js 설치 완료 ($ARCH)"
echo ""

echo "---------------------------------------------------------------------------"
# 5. Neovim 포터블 설치
echo "💤 5. Neovim 포터블 설치 중..."
mkdir -p "$DEVTOOLS2/modules/neovim"
cd "$DEVTOOLS2/modules/neovim"

if [ -d "$DEVTOOLS2/modules/neovim/nvim" ]; then
    # 사용자에게 선택 입력 요청
    read -p "   ⚠️  neovim 디렉토리가 이미 존재합니다. 삭제하고 새로 설치하시겠습니까? (y/n): " choice

    case "$choice" in
    y | Y)
        echo "   🗑️  기존 디렉토리 삭제 중..."
        rm -rf "$DEVTOOLS2/modules/neovim/nvim"
        echo "   📦 Neovim stable 다운로드 및 압축 해제..."
        install_tool \
            'https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz' \
            'https://github.com/neovim/neovim/releases/download/stable/nvim-linux-arm64.tar.gz' \
            'nvim'
        ;;
    *)
        echo "   ⏭️ [건너뜀] neovim 디렉토리가 이미 존재합니다."
        ;;
    esac
else
    echo "   📦 Neovim stable 다운로드 및 압축 해제..."
    install_tool \
        'https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz' \
        'https://github.com/neovim/neovim/releases/download/stable/nvim-linux-arm64.tar.gz' \
        'nvim'
fi

echo "✅ Neovim 설치 완료 ($ARCH)"
echo ""

echo "---------------------------------------------------------------------------"
# 6. Ghostty 포터블 설치: https://ghostty.org/
echo "💚 6. Ghostty 포터블 설치 단계"
echo ""

if [ "$IS_WSL2" = true ]; then
    echo "   ⚠️  [WSL2 환경 감지] Ghostty는 WSL2에서 지원되지 않으므로 설치를 건너뜁니다."
    echo "   💬 Windows 네이티브 환경에서 Ghostty를 설치해주세요: https://ghostty.org/"
else
    echo "💚 6. Ghostty 포터블 설치 중..."
    mkdir -p "$DEVTOOLS2/modules/ghostty"
    cd "$DEVTOOLS2/modules/ghostty"

    if [ -f "$DEVTOOLS2/modules/ghostty/ghostty" ]; then
        echo "   ⏭️ [건너뜀] ghostty AppImage가 이미 존재합니다. 새로 설치하려면 삭제하세요: sudo rm -f '$DEVTOOLS2/modules/ghostty/ghostty'"
    else
        echo "   📦 Ghostty AppImage 다운로드 중..."
        curl -Ls "https://github.com/pkgforge-dev/ghostty-appimage/releases/download/v1.3.1/Ghostty-1.3.1-$ARCH.AppImage" -o ghostty
        chmod +x ghostty

        # 설정 파일 경로 심볼릭 링크 생성
        "$DEVTOOLS2/scripts/linux/cmd/create-symbolic-link.sh" "$DEVTOOLS2/.config/ghostty" "$HOME/.config/ghostty"
    fi

    echo "✅ Ghostty 설치 완료"
fi
echo ""

echo "---------------------------------------------------------------------------"
echo "🔍 설치 완료: JDK 설치 검증"
echo ""

# 설치된 JDK 확인
echo "[정보] 실제 설치된 JDK 디렉토리:"
INSTALLED_JDKS=""
for jdk_dir in "$DEVTOOLS2/modules/java/jdk-"*; do
    if [ -d "$jdk_dir" ]; then
        if [ -z "$INSTALLED_JDKS" ]; then
            INSTALLED_JDKS="$jdk_dir"
        else
            INSTALLED_JDKS="$INSTALLED_JDKS,$jdk_dir"
        fi
        echo "  ✓ $(basename "$jdk_dir")"
    fi
done

echo ""
echo "[정보] Gradle용 설정값 (1.setup-dev-env.sh에서 사용됨):"
echo "  org.gradle.java.installations.paths=$INSTALLED_JDKS"
echo ""

echo "---------------------------------------------------------------------------"
echo "🎉 모든 포터블 도구 설치가 완료되었습니다!"
echo ""
echo "==========================================================================="
echo ""
