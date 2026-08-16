#!/bin/bash
# [주의] 이 스크립트는 Fcitx5를 설치하고 환경 변수를 설정합니다.
#
# ⚠️ 포터블 원칙의 예외입니다(전체 목록/이유는 0.init-devtools2.sh 상단 메모 참고).
# fcitx5는 디스플레이 서버(X11/Wayland)의 입력기 프레임워크에 직접 등록되는 시스템 서비스라
# 바이너리 복사로는 개념적으로 동작할 수 없습니다(항상 대상 OS에 직접 설치 필요).

echo ">>> 패키지 목록 업데이트 및 Fcitx5 설치 시작..."
sudo apt update
# ⚠️ 종료코드를 확인하지 않으면 설치가 실패해도 아래에서 "설치가 완료되었습니다"가
# 그대로 출력됩니다(3.install-cli-tools.sh의 apt install 오류 처리 관례와 동일하게 맞춤).
if ! sudo apt install -y fcitx5 fcitx5-hangul im-config; then
    echo "❌ Fcitx5 패키지 설치에 실패했습니다. 위 오류 메시지를 확인해주세요." >&2
    exit 1
fi

echo ">>> 기본 입력기를 Fcitx5로 설정 중..."

# im-config를 비대화형 모드로 실행하여 fcitx5 지정
if ! im-config -n fcitx5; then
    echo "❌ im-config를 통한 Fcitx5 기본 입력기 설정에 실패했습니다." >&2
    exit 1
fi

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
