#!/bin/bash

# =================================================================
# DevTools2 CLI 유틸리티 도구 설치 스크립트 (3.install-cli-tools.sh)
# 대상: fzf, lazygit, ripgrep, fd, ast-grep,
#       apt 패키지(build-essential, libreadline-dev, git, trash-cli),
#       hererocks (Lua/Neovim 플러그인 관리용)
# 참고: 바자이트(불변 OS) 환경에서 distrobox 컨테이너를 통해 설치하던
#       apt 패키지 및 hererocks 설치를 이 스크립트로 통합하였습니다.
#       우분투 / WSL2 환경에서는 직접 apt 를 사용하므로 컨테이너가 불필요합니다.
# =================================================================

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

if [ -z "${DEVTOOLS2:-}" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    DEVTOOLS2=$(readlink -f "$SCRIPT_DIR/../../..")
fi

# 유효한 DEVTOOLS2 폴더가 아니면 표준 경로를 기본값으로 사용
if [ ! -f "$DEVTOOLS2/scripts/linux/devtools2/3.install-cli-tools.sh" ]; then
    DEVTOOLS2="/var/opt/_devtools2"
fi

# 바이너리가 설치될 modules 디렉토리 경로 설정
MODULES_DIR="$DEVTOOLS2/modules"

# 경로 생성
# 각 도구별로 독립된 폴더를 생성하여 관리를 용이하게 합니다.
mkdir -p "$MODULES_DIR/fzf" "$MODULES_DIR/lazygit" "$MODULES_DIR/ripgrep" "$MODULES_DIR/fd" "$MODULES_DIR/ast-grep" "$MODULES_DIR/bitwarden"

show_spinner() {
    local pid=$1
    local delay=0.15
    local spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinner#?}
        printf " [%c] " "$spinner"
        spinner=$temp${spinner%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

echo ""
echo "==========================================================================="
echo "🚀 도구 설치를 시작합니다..."
echo "📍 최상위 경로: $DEVTOOLS2"
echo "📍 설치 폴더: $MODULES_DIR"
if [ "$IS_WSL2" = true ]; then echo "📍 환경: WSL2 감지됨"; fi

# 1. fzf 설치 - v0.71.0
# 터미널용 퍼지 파인더 (목록 검색 도구)
echo -n "📦 fzf 설치 중..."
if [ "$IS_ARM64" = true ]; then
    URL='https://github.com/junegunn/fzf/releases/download/v0.71.0/fzf-0.71.0-linux_arm64.tar.gz'
else
    URL='https://github.com/junegunn/fzf/releases/download/v0.71.0/fzf-0.71.0-linux_amd64.tar.gz'
fi
curl -sL "$URL" | tar xz -C "$MODULES_DIR/fzf" &
show_spinner $!
echo " 완료"

# 2. lazygit 설치 - v0.42.0
# 터미널 UI 기반 Git 관리 도구
echo -n "📦 lazygit 설치 중..."
if [ "$IS_ARM64" = true ]; then
    URL='https://github.com/jesseduffield/lazygit/releases/download/v0.61.1/lazygit_0.61.1_Linux_arm64.tar.gz'
else
    URL='https://github.com/jesseduffield/lazygit/releases/download/v0.61.1/lazygit_0.61.1_Linux_x86_64.tar.gz'
fi
curl -sL "$URL" | tar xz -C "$MODULES_DIR/lazygit" &
show_spinner $!
echo " 완료"

# 3. ripgrep (rg) 설치 - v15.0.0
# 코드 내 문자열 초고속 검색 도구
echo -n "📦 ripgrep 설치 중..."
if [ "$IS_ARM64" = true ]; then
    URL='https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-aarch64-unknown-linux-gnu.tar.gz'
else
    URL='https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-x86_64-unknown-linux-musl.tar.gz'
fi
curl -sL "$URL" | tar xz -C "$MODULES_DIR/ripgrep" --strip-components=1 &
show_spinner $!
echo " 완료"

# 4. fd-find (fd) 설치 - v11.0.0
# 파일 이름 초고속 검색 도구 (find 대용)
echo -n "📦 fd-find 설치 중..."
if [ "$IS_ARM64" = true ]; then
    URL='https://github.com/sharkdp/fd/releases/download/v10.4.2/fd-v10.4.2-aarch64-unknown-linux-musl.tar.gz'
else
    URL='https://github.com/sharkdp/fd/releases/download/v10.4.2/fd-v10.4.2-x86_64-unknown-linux-musl.tar.gz'
fi
curl -sL "$URL" | tar xz -C "$MODULES_DIR/fd" --strip-components=1 &
show_spinner $!
echo " 완료"

# 5. ast-grep (sg) 설치 - v0.42.1
# 추상 구문 트리(AST) 기반의 구조적 코드 검색 도구 (Java 소스 분석 최적화)
echo -n "📦 ast-grep 설치 중..."
if [ "$IS_ARM64" = true ]; then
    URL='https://github.com/ast-grep/ast-grep/releases/latest/download/app-aarch64-unknown-linux-gnu.zip'
else
    URL='https://github.com/ast-grep/ast-grep/releases/latest/download/app-x86_64-unknown-linux-gnu.zip'
fi
(curl -sL "$URL" -o /tmp/ast-grep.zip && unzip -qo /tmp/ast-grep.zip -d "$MODULES_DIR/ast-grep" && rm -f /tmp/ast-grep.zip) &
show_spinner $!
echo " 완료"

# 6. Bitwarden CLI (bw) 설치
# 안전한 서버 로그인 연동 및 패스워드 매니저 CLI
echo -n "📦 Bitwarden CLI 설치 중..."
if [ "$IS_ARM64" = true ]; then
    # ARM64용은 최신 GitHub 클라이언트 릴리즈 주소를 직접 이용
    URL="https://github.com/bitwarden/clients/releases/download/cli-v2024.4.1/bw-linux-2024.4.1.zip"
else
    # x86_64용 공식 다이렉트 다운로드 주소
    URL="https://vault.bitwarden.com/download/?app=cli&platform=linux"
fi
(curl -sL "$URL" -o /tmp/bw.zip && unzip -qo /tmp/bw.zip -d "$MODULES_DIR/bitwarden" && rm -f /tmp/bw.zip) &
show_spinner $!
echo " 완료"

# 실행 권한 부여 및 검증
echo "🔐 실행 권한 부여 및 검증 중..."
for cmd in "$MODULES_DIR/ripgrep/rg" "$MODULES_DIR/fd/fd" "$MODULES_DIR/fzf/fzf" "$MODULES_DIR/lazygit/lazygit" "$MODULES_DIR/ast-grep/sg" "$MODULES_DIR/bitwarden/bw"; do
    if [ -s "$cmd" ]; then
        chmod +x "$cmd"
    else
        echo "⚠️  경고: $cmd 파일이 비어있거나 다운로드에 실패했습니다."
    fi
done

echo "✅ 모든 바이너리 도구($ARCH) 설치가 완료되었습니다!"
echo ""

echo "---------------------------------------------------------------------------"
echo -n "   - apt 패키지 인덱스 업데이트 중..."
sudo apt-get update -qq &
show_spinner $!
echo " 완료"

echo -n "   - apt 패키지(build-essential, libreadline-dev, git, trash-cli) 설치 중..."
sudo apt-get install -y build-essential libreadline-dev git trash-cli -qq &
show_spinner $!
echo " 완료"
echo "✅ apt 패키지 설치 완료"
echo ""

echo "---------------------------------------------------------------------------"
echo "💎 7. hererocks 설치 및 Lua 환경 구성 중... (Neovim 플러그인 관리용)"
echo ""
pip install --user --break-system-packages hererocks 2>/dev/null || pip install --user hererocks

HEREROCKS_DIR="$DEVTOOLS2/data/nvim/lazy-rocks/hererocks"
mkdir -p "$HEREROCKS_DIR"
cd "$HEREROCKS_DIR"

# 임시 PATH 추가 (pip로 설치된 hererocks 바이너리를 현재 셸 환경에 즉시 연동)
export PATH="$HOME/.local/bin:$PATH"

echo -n "   ⚙️ hererocks 구성 중 (Lua 5.1 / Luarocks 최신)..."
hererocks . -l 5.1 -r latest &
show_spinner $!
echo " 완료"
echo "✅ hererocks / Lua 환경 구성 완료"
echo ""

echo "==========================================================================="
echo "🎉 모든 도구 설치가 완료되었습니다!"
echo ""
echo "설정 확인 명령어:"
echo "    hererocks --version"
echo "    ls -F \"$DEVTOOLS2/data/nvim/lazy-rocks/hererocks/bin/\""
echo "==========================================================================="
echo ""
