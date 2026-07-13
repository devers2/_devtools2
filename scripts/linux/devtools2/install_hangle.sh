#!/bin/bash
# [주의] 이 스크립트는 Fcitx5를 설치하고 환경 변수를 설정합니다.

echo ">>> 패키지 목록 업데이트 및 Fcitx5 설치 시작..."
sudo apt update
sudo apt install -y fcitx5 fcitx5-hangul im-config

echo ">>> 기본 입력기를 Fcitx5로 설정 중..."

# im-config를 비대화형 모드로 실행하여 fcitx5 지정
im-config -n fcitx5

echo ">>> .bashrc 파일 백업 생성 중..."
cp ~/.bashrc ~/.bashrc.bak

echo ">>> 환경 변수 등록 중..."

# 이미 설정이 되어 있는지 확인 후 중복 삽입 방지
if ! grep -q "GTK_IM_MODULE=fcitx" ~/.bashrc; then
    cat <<EOF >> ~/.bashrc

# Fcitx5 Input Method Settings
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx

EOF
    echo ">>> 환경 변수가 .bashrc에 등록되었습니다."
else
    echo ">>> 이미 환경 변수가 등록되어 있어 건너뜁니다."
fi

echo "-------------------------------------------------------"
echo "설치가 완료되었습니다."
echo "1. 시스템을 '재부팅'해야 모든 설정이 적용됩니다."
echo "2. 재부팅 후 'Fcitx5 Configuration' 앱에서 한글(Hangul)을 추가하세요."
echo "-------------------------------------------------------"
