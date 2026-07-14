# devers2's Development Tool

- `Windows` + `WSL2` 자동 연동 설치

  ```powershell
  # 온라인 설치
  irm https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/windows/setup-devtools2-wsl.ps1 | iex

  # 설치 완료 후 배포판 확인
  wsl --list --verbose
  # 또는 줄여서
  wsl -l -v

  # 기본 배포판(Default Distro) 설정
  wsl --set-default <인스턴스이름>

  # 기본 배포판 진입
  wsl
  ```

- `Linux` 네이티브 환경 단독 설치

  ```sh
  curl -sSfL https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/setup-devtools2.sh -o /tmp/setup-devtools2.sh && bash /tmp/setup-devtools2.sh
  ```
