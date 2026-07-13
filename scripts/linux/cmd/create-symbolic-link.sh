#!/bin/bash
# ==============================================================================
# 사용법:
#   ./create-symbolic-link.sh <원본_폴더_경로> <생성할_바로가기_경로>
#
# 설명:
#   지정한 원본 폴더(Source)를 가리키는 심볼릭 링크(바로가기)를 생성합니다.
#   - 타겟이나 소스 디렉터리가 없으면 자동으로 생성합니다.
#   - 이미 대상 위치에 잘못된 타겟을 가리키는 링크가 있거나, 일반 파일/폴더가 있으면
#     안전을 위해 강제 삭제 후 올바른 심볼릭 링크로 교체(복구)합니다.
#   - 끊어진 링크(Broken Symlink) 방지를 보장하는 가장 안전한 심볼릭 링크 유틸리티입니다.
#
# 예시:
#   ./create-symbolic-link.sh "/home/user/data/my_target" "/home/user/my_link"
# ==============================================================================

if [ "$#" -ne 2 ]; then
    echo "사용법: $0 <원본_폴더_경로> <생성할_바로가기_경로>"
    exit 1
fi

source_dir="$1"
target_link="$2"

# 1. 소스 디렉터리 보장
mkdir -p "$source_dir"

# 2. 타겟 링크 부모 디렉터리 보장
mkdir -p "$(dirname "$target_link")"

if [ -L "$target_link" ]; then
    current_target=$(readlink -f "$target_link" 2>/dev/null || true)
    desired_target=$(readlink -f "$source_dir")

    if [ "$current_target" = "$desired_target" ]; then
        echo "[확인] $target_link 이미 올바른 심볼릭 링크입니다."
        exit 0 # 올바른 링크이므로 밑의 ln -s를 실행하지 않고 즉시 정상 종료
    else
        echo "[복구] $target_link 대상이 잘못되어 기존 링크 삭제 후 재연결합니다."
        rm -rf "$target_link"
    fi
elif [ -e "$target_link" ]; then
    bak="${target_link}.backup.$(date +%s)"
    mv "$target_link" "$bak"
    echo "[복구] $target_link 위치에 일반 디렉터리나 파일이 있어 백업($bak) 후 심볼릭 링크로 교체합니다."
fi

ln -s "$source_dir" "$target_link"
echo "[성공] $target_link -> $source_dir"
