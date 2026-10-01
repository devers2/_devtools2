# s2-office-converter

s2-support 의 `S2OfficeConverter`·`S2PdfUtil` 이 **오피스·한글 문서(docx, xlsx, pptx, hwp, hwpx 등)를 PDF 로 변환·병합하거나
웹에디터용 HTML 로 가져오고**,
**웹 페이지(URL 로 받은 HTML)를 브라우저 화면 그대로 PDF 로** 만들 수 있도록 서버에 변환기를 설치하는 스크립트입니다.

```
[앱] S2PdfUtil ──(s2-soffice --headless --convert-to pdf ...)──▶ [Podman 컨테이너]
               ──(s2-chrome --print-to-pdf <pdf> <html>)────────▶  LibreOffice + H2Orestart(한글) + Chromium + 한글 폰트
```

- 변환기가 없어도 앱은 동작합니다. 오피스·한글이 아닌 소스(PDF, HTML, 이미지 등)는 그대로 병합되고,
  문서 소스만 `오피스·한글 문서를 변환하려면 s2-office-converter 설치가 필요합니다.` 오류가 납니다.
- 웹 페이지는 `s2-chrome` 이 있으면 Chromium 으로(flex·grid·JavaScript 까지 화면 그대로), 없거나 실패하면(크롬 문제, 제한 시간 초과 등)
  경고 로그를 남기고 내장 렌더러(openhtmltopdf)로 변환합니다. 웹 페이지 변환 때문에 병합이 실패하지는 않습니다.
- 설치 후 앱을 다시 시작할 필요 없이 `S2OfficeConverter`(와 이를 쓰는 `S2PdfUtil`)가 자동으로 찾습니다.

## 파일

| 파일 | 역할 |
|---|---|
| `setup-s2-office-converter.sh` | 설치 스크립트. 이 파일 하나로 온라인 설치, 폐쇄망 설치 파일 만들기(`--export`), 다시 만들기, 제거를 모두 합니다. |
| `README.md` | 이 안내문 |

스크립트는 다른 파일에 의존하지 않으므로 GitHub 에서 바로 실행하거나, 이 파일만 복사해 실행할 수 있습니다.

## 필요 조건

- 리눅스 (Ubuntu, Debian, RHEL, Rocky, AlmaLinux, Fedora), sudo 를 쓸 수 있는 계정
- 서버에 필요한 것은 Podman 뿐이며, 없으면 스크립트가 설치합니다. (LibreOffice, Java, 폰트는 컨테이너 안에 들어감)
- **앱 실행 계정**: 웹 애플리케이션(Java)을 실행하는 리눅스 계정 (웹사이트 회원 계정이 아님)
  - 확인: `ps -eo user,cmd | grep -i java` → 첫 칸
  - rootless Podman 은 이미지를 계정별로 저장하므로 **앱 실행 계정에 설치해야** 앱이 변환기를 쓸 수 있습니다.
  - 앱 실행 계정에 홈 폴더가 있어야 합니다 (이미지 저장 위치).

## 사용법

주소: `https://raw.githubusercontent.com/devers2/_devtools2/main/scripts/linux/setup-projects/s2/s2-office-converter/setup-s2-office-converter.sh`

### 1. 온라인 설치 (서버가 인터넷에 접속할 수 있을 때)

```sh
# 운영 서버: 앱 실행 계정을 지정 (appuser 자리에 실제 계정 이름)
curl -fsSL <주소> | bash -s -- --app-user appuser

# 개발 PC, WSL: 지금 로그인한 계정으로
curl -fsSL <주소> | bash
```

처음 실행은 LibreOffice 를 받느라 몇 분 걸립니다. 진행 순서:

1. Podman 확인 (없으면 설치)
2. 앱 실행 계정 준비 (rootless Podman 용 subuid/subgid)
3. 변환기 이미지 만들기 (LibreOffice + H2Orestart + Chromium + 한글·MS 호환 폰트, 약 1.6GB)
4. `/usr/local/bin/s2-soffice`, `/usr/local/bin/s2-chrome` 설치
5. 실제 변환으로 동작 확인 (문서, 한글 확장, 웹 페이지)

웹 페이지 변환이 필요 없으면 `--no-chrome` 을 붙입니다 (Chromium 을 빼서 이미지 약 0.9GB, `s2-chrome` 설치 안 함).

### 2. 폐쇄망 설치 (서버가 인터넷에 접속할 수 없을 때)

인터넷 되는 PC에서 **설치 파일 하나**를 만들어 서버로 옮긴 뒤 실행합니다.

**① 인터넷 되는 PC** (서버와 같은 CPU 종류, 예: 둘 다 x86_64) — 설치 파일 만들기

```sh
# --target 에 서버의 배포판:버전 (서버에서 확인: . /etc/os-release && echo "$ID:$VERSION_ID")
curl -fsSL <주소> | bash -s -- --export --target ubuntu:22.04
```

지금 폴더에 `setup-s2-office-converter-offline.sh` (수백 MB) 가 만들어집니다.
이 스크립트 뒤에 변환기 이미지와 서버 배포판용 Podman 설치 파일을 압축해 붙인 실행 파일입니다.
다른 이름·위치로 만들려면 `--export <파일 경로>`.

**② 그 파일 하나를 서버에 옮김** (USB, 파일 전송 등)

**③ 폐쇄망 서버** — 옮긴 파일을 실행 (인터넷 접속 없음)

```sh
bash setup-s2-office-converter-offline.sh --app-user appuser
```

- 손상 여부(체크섬), CPU 종류를 먼저 확인하고, 맞지 않으면 무엇을 다시 해야 하는지 알려 주고 멈춥니다.
- 서버에 Podman 이 없으면 파일에 든 패키지로 설치합니다 (이때 배포판도 맞아야 함). 이미 있으면 건너뜁니다.
- 설치 중에 `/var/tmp` 에 잠시 압축을 풀었다가 지웁니다. 공간이 부족하면 `TMPDIR=<폴더> bash setup-s2-office-converter-offline.sh ...`.
- 옵션은 원래 스크립트와 같습니다 (`--rebuild` 는 이미지를 다시 등록, `--uninstall` 은 제거).

`--target` 에 쓸 수 있는 배포판: `ubuntu:<버전>`, `debian:<버전>`, `rockylinux:<버전>`, `almalinux:<버전>`,
`rhel:<버전>` (AlmaLinux 패키지로 받음, 바이너리 호환), `fedora:<버전>`

### 3. 관리

```sh
# 확인
sudo -u appuser s2-soffice --version
sudo -u appuser s2-chrome --version

# 다시 만들기 (보안 업데이트 반영 등)
curl -fsSL <주소> | bash -s -- --app-user appuser --rebuild

# 제거 (s2-soffice, s2-chrome 과 이미지. Podman 은 남김)
curl -fsSL <주소> | bash -s -- --app-user appuser --uninstall
```

- 여러 번 실행해도 안전합니다. 이미 있는 것은 건너뛰고 빠진 것만 채웁니다.
- 변환기 버전(LibreOffice 이미지, H2Orestart)을 올리면 다음 실행 때 새 이미지를 만들고 이전 이미지는 정리합니다.
- 한 서버에서 여러 계정이 쓰면(예: 앱 계정과 배치 계정) 계정마다 한 번씩 실행합니다. `s2-soffice` 명령은 서버에 하나만 설치됩니다.

## 앱(S2OfficeConverter, S2PdfUtil)에서 찾는 순서

1. `S2OfficeConverter.setCommand(...)` 로 지정한 명령
2. 환경 변수 `S2_SOFFICE`
3. PATH 의 `s2-soffice`, 그다음 `soffice`, `libreoffice`
4. 고정 경로 `/usr/local/bin/s2-soffice` (cron 처럼 PATH 가 좁은 환경 대비), LibreOffice 기본 설치 경로

웹 페이지 변환(`s2-chrome`)은 `S2PdfUtil.setBrowserCommand(...)`, 환경 변수 `S2_CHROME`, PATH 의 `s2-chrome`,
`/usr/local/bin/s2-chrome` 순으로 찾습니다. 네트워크가 열린 일반 chrome/chromium 은 자동으로 쓰지 않습니다
(페이지의 JavaScript 가 내부망에 접속할 수 있기 때문).

```java
if (S2OfficeConverter.isAvailable()) {
    S2PdfUtil.merge(List.of(PdfSource.ofDocument(Path.of("계획서.docx")),
            PdfSource.ofDocument(uploadedStream, "보고서.hwp")));
}
```

## s2-chrome

이미지·CSS 를 모두 넣은 HTML 파일을 Chromium 으로 PDF 인쇄하는 명령입니다. `S2PdfUtil` 이 URL 로 받은 HTML 페이지를
변환할 때 씁니다 (페이지의 이미지·CSS 는 앱이 받아서 넣은 뒤 넘김).

- 네트워크가 없는 컨테이너에서 실행하므로 페이지의 JavaScript 도 밖(내부망 포함)에 접속하지 못합니다.
- Chromium 자체 샌드박스는 rootless 컨테이너 안에서 쓸 수 없어 끄고(`--no-sandbox`), 컨테이너(네트워크 없음, 읽기 전용 루트,
  권한 제거, 호출자 uid)가 격리를 맡습니다.
- 제한 시간: 기본 60초 (`S2_CHROME_TIMEOUT`). 앱 쪽 제한은 `S2PdfUtil.setBrowserTimeout`.

```sh
s2-chrome --print-to-pdf /tmp/out.pdf page.html
```

## s2-soffice

LibreOffice(`soffice`) 호환 명령입니다. 변환할 때마다 새 컨테이너에서 실행하며 다음을 지킵니다.

- 호출한 폴더가 아니라 **전용 사본**만 컨테이너에 연결
- 네트워크 차단, 읽기 전용 루트, 권한 제거, 호출자 uid (결과 파일 소유자 유지)
- 제한 시간: 기본 180초 (`S2_SOFFICE_TIMEOUT` 환경 변수로 변경)

```sh
s2-soffice --headless --convert-to pdf --outdir /tmp/out 보고서.hwp
```

## 문제 해결

| 증상 | 확인 |
|---|---|
| 앱에서 "s2-office-converter 설치가 필요합니다" | 앱 실행 계정으로 설치했는지 (`sudo -u <계정> s2-soffice --version`) |
| "앱 실행 계정의 홈 폴더가 없습니다" | 안내된 명령으로 홈 폴더를 만든 뒤 다시 실행 |
| 한글 문서만 변환 실패 | `--rebuild` 로 이미지를 다시 만듦 (H2Orestart 포함 여부는 마지막 확인 단계에 표시) |
| 변환 결과에서 글자 모양이 원본과 다름 | 원본 문서에 쓴 글꼴이 없어서입니다. 필요한 글꼴은 이미지에 추가해야 합니다 |
| 폐쇄망 설치 파일에서 CPU·배포판 불일치 | 안내대로 `--target` 을 맞춰 인터넷 PC 에서 다시 `--export` |
| 폐쇄망 설치 파일 "체크섬 불일치" | 옮기는 중 손상됨. 파일을 다시 옮김 |
| 변환이 느림 | 변환마다 컨테이너를 새로 띄워 한 건에 수 초 걸립니다 (설계상 격리를 우선함) |
| 웹 페이지가 화면과 다름 | `sudo -u <계정> s2-chrome --version` 으로 s2-chrome 이 동작하는지 확인. 앱 로그에 "브라우저 변환에 실패해 내장 렌더러로" 가 있으면 그 원인 확인 |
| 폐쇄망이라 Chromium 을 업데이트할 수 없음 | 그대로 써도 됩니다. 네트워크가 없는 컨테이너에서 이미 정리된 파일만 인쇄하므로 밖에서 공격받는 경로가 거의 없습니다. 업데이트는 인터넷 되는 PC 에서 `--export` 로 새 설치 파일을 만들어 옮깁니다 |

## 라이선스

이 스크립트는 LibreOffice(MPL 2.0), H2Orestart(GPL 3.0), Chromium(BSD 3-Clause 등), 폰트(SIL OFL 1.1 등), Podman(Apache 2.0)을 각 배포처에서 받아
설치할 뿐 재배포하지 않습니다. 각 소프트웨어는 자체 라이선스를 따릅니다. 폐쇄망 설치 파일을 다른 조직에 전달하면 그 안의
소프트웨어를 배포하는 것이 되므로 각 라이선스를 확인하십시오.
