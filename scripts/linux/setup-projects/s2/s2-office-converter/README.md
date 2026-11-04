# s2-office-converter

s2-docflow 의 `S2OfficeConverter`·`S2DocumentMerger` 가 **오피스·한글 문서(docx, xlsx, pptx, hwp, hwpx 등)를 PDF 로 변환·병합하거나
웹에디터용 HTML 로 가져오고**,
**웹 페이지(URL 로 받은 HTML)를 브라우저 화면 그대로 PDF 로** 만들 수 있도록 서버에 변환기를 설치하는 스크립트입니다.

```
[앱] S2DocumentMerger ──(s2-soffice --headless --convert-to pdf ...)──▶ [Podman 컨테이너]
               ──(s2-chrome --print-to-pdf <pdf> <html>)────────▶  LibreOffice + H2Orestart(한글) + Chromium
               ──(s2-hwp --outdir <폴더> <파일.hwp>)─────────────▶  + Node.js·rhwp(한글 조판) + 한글 폰트
```

- 변환기가 없어도 앱은 동작합니다. 오피스·한글이 아닌 소스(PDF, HTML, 이미지 등)는 그대로 병합되고,
  문서 소스만 `오피스·한글 문서를 변환하려면 s2-office-converter 설치가 필요합니다.` 오류가 납니다.
- 웹 페이지 및 HTML은 `s2-chrome`이 설치되면 Chromium 헤드리스로(flex·grid·JavaScript까지 화면 그대로) 100% LGPL-Free로 인쇄됩니다.
- 한글 문서(hwp, hwpx)의 PDF 는 `s2-hwp`(rhwp 조판 + Chromium 인쇄)로 먼저 만들고, 실패하면 `s2-soffice`(LibreOffice + H2Orestart)로
  만듭니다. rhwp 는 한글 프로그램과 같은 쪽 나눔을 따르므로 쪽 수·그림·표가 원본에 가깝습니다 (아래 [s2-hwp](#s2-hwp)).
- 설치 후 앱을 다시 시작할 필요 없이 `S2OfficeConverter`(와 이를 쓰는 `S2DocumentMerger`)가 자동으로 찾습니다.

## 파일

| 파일 | 역할 |
|---|---|
| `setup-s2-office-converter.sh` | 설치 스크립트. 이 파일 하나로 온라인 설치, 폐쇄망 설치 파일 만들기(`--export`), 다시 만들기, 제거를 모두 합니다. |
| `s2-office-converter-versions.toml` | H2Orestart·rhwp **버전 정책과 이력** (Git 관리). 버전을 올리거나 되돌릴 때 이 파일의 `[track]` 을 바꿉니다. |
| `README.md` | 이 안내문 |
| `tests/setup-s2-office-converter.test.sh` | 설치 스크립트 시험 (sudo·네트워크 없이, s2-docflow 의 `./gradlew check` 가 실행. s2-docflow 저장소에만 있음) |

스크립트는 옆의 버전 파일을 읽고, GitHub 에서 바로 실행하면 같은 경로의 GitHub 원본을 읽습니다. 둘 다 읽지 못하면 스크립트에 적힌
기본 버전으로 설치하므로, 스크립트 파일 하나만 복사해 실행해도 동작합니다.

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
3. 구성 요소 버전 확인 ([버전 관리](#버전-관리))
4. 변환기 이미지 만들기 (LibreOffice + H2Orestart + Chromium + Node.js·rhwp + qpdf + 한글·MS 호환 무료 글꼴, 약 1.6GB)
5. 고객사 글꼴 폴더 확인 (`--font-dir` 를 지정했거나 이전에 지정한 경우)
6. `/usr/local/bin/s2-soffice`, `/usr/local/bin/s2-chrome`, `/usr/local/bin/s2-hwp` 설치
7. 변환에 쓰는 몫 정하기: 처음 설치할 때 **변환 전용 서버인지** 묻고, 아니면 **변환에 줄 몫(%)** 을 묻습니다. 그 값으로 동시 변환 수와 메모리
   예산을 정해 `/etc/s2-docflow/converter.env` 에 쓰고, **일반적인 사용 기준 몇 명까지 쓸 수 있는지** 알려 줍니다 ([변환 몫과 컨테이너 재사용](#변환-몫과-컨테이너-재사용))
8. uid 분리 준비: 컨테이너를 앱 계정이 아닌 하위 uid 로 실행할 수 있는지 확인하고 이미지를 준비 ([uid 분리](#uid-분리-기본))
9. 실제 변환으로 동작 확인 (문서, 한글 확장, 고객사 글꼴 인식 수, 한글 조판, 웹 페이지)

웹 페이지 변환이 필요 없으면 `--no-chrome` 을 붙입니다 (Chromium 을 빼서 이미지 약 0.9GB, `s2-chrome`·`s2-hwp` 설치 안 함 →
한글 문서는 LibreOffice + H2Orestart 로만 변환).

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
- 옵션과 진행은 원래 스크립트와 같습니다. 처음 설치할 때 **변환 전용인지·몫(%)을 묻고**(`--dedicated`·`--share 퍼센트`·`--warm` 도 그대로),
  uid 분리도 준비합니다. 같은 설치 파일을 다시 실행하면 건너뛰고, 새로 만든 설치 파일이면 이미지를 자동으로 바꿉니다 ([최신화](#최신화-보안-업데이트)).
  `--uninstall` 은 제거.
- 고객사 글꼴은 설치 파일에 들어가지 않습니다. 서버에 글꼴 폴더를 따로 옮긴 뒤 `--font-dir <폴더>` 를 붙여 실행합니다.

`--target` 에 쓸 수 있는 배포판: `ubuntu:<버전>`, `debian:<버전>`, `rockylinux:<버전>`, `almalinux:<버전>`,
`rhel:<버전>` (AlmaLinux 패키지로 받음, 바이너리 호환), `fedora:<버전>`

### 3. 관리

```sh
# 확인
sudo -u appuser s2-soffice --version
sudo -u appuser s2-chrome --version
sudo -u appuser s2-hwp --version

# 변환 몫 바꾸기 (전용 / 앱과 함께 쓰는 서버에서 40%). 묻지 않고 정하려면 처음 설치할 때도 이 옵션을 붙임
curl -fsSL <주소> | bash -s -- --app-user appuser --dedicated
curl -fsSL <주소> | bash -s -- --app-user appuser --share 40
# 성능 우선(컨테이너 재사용, 격리는 한 단계 약함) 켜기 / 끄기
curl -fsSL <주소> | bash -s -- --app-user appuser --warm
curl -fsSL <주소> | bash -s -- --app-user appuser --no-warm

# 고객사 글꼴 폴더 연결 / 빼기 (이미지는 다시 만들지 않음, 한 번 지정하면 유지)
curl -fsSL <주소> | bash -s -- --app-user appuser --font-dir /opt/s2-fonts
curl -fsSL <주소> | bash -s -- --app-user appuser --no-font-dir

# 다시 만들기 (보안 업데이트 반영 등)
curl -fsSL <주소> | bash -s -- --app-user appuser --rebuild

# 제거 (s2-soffice, s2-chrome, s2-hwp 와 이미지. Podman 은 남김)
curl -fsSL <주소> | bash -s -- --app-user appuser --uninstall
```

- 여러 번 실행해도 안전합니다. 이미 있는 것은 건너뛰고 빠진 것만 채웁니다.
- 구성 요소 버전을 바꾸면(업데이트에 동의하면) 새 이미지를 만들고 이전 이미지는 정리합니다.
- 한 서버에서 여러 계정이 쓰면(예: 앱 계정과 배치 계정) 계정마다 한 번씩 실행합니다. `s2-soffice` 명령은 서버에 하나만 설치됩니다.

### 최신화 (보안 업데이트)

변환기의 보안 업데이트는 **이미지 안**(LibreOffice·Chromium·Debian 패키지)과 **호스트**(커널·Podman·crun) 두 곳에 있습니다. 스크립트는 몇 번을
실행해도 안전하며(멱등), 이미지 쪽은 다음처럼 최신화합니다.

| 상황 | 하는 일 |
|---|---|
| 그냥 다시 실행 | 설치된 이미지를 유지. 다만 **만든 지 30일**(`S2_CONVERTER_MAX_AGE_DAYS`)이 지났으면 다시 만들지 묻습니다. 설정(몫·글꼴·`--warm`)은 그대로 |
| `--rebuild` | 바로 다시 만듦. 기반 이미지를 새로 받고(`--pull=newer`) **캐시 없이** 패키지를 새로 설치하므로 그날까지의 보안 업데이트가 들어갑니다 |
| 무인 실행 (cron 등) | 묻지 않음. `S2_CONVERTER_UPDATE=y` 면 30일이 지난 이미지를 다시 만들고 새 구성 요소 버전도 받음, `n` 이면 유지 |
| 다시 만든 뒤 | 이름 없이 남은 예전 이미지를 지우고, 대기 컨테이너를 정리하고, uid 분리용 준비를 다시 함. 서비스 재시작은 필요 없음 (변환마다 새 이미지로 컨테이너를 띄움) |

```sh
# 예: 매달 1일 새벽 3시에 자동으로 (root 의 crontab, 인터넷 되는 서버)
0 3 1 * * S2_CONVERTER_UPDATE=y bash /opt/s2/setup-s2-office-converter.sh --app-user appuser >>/var/log/s2-converter-update.log 2>&1
```

**폐쇄망 서버:** 인터넷 되는 PC에서 `--export --rebuild --target <배포판:버전>` 으로 설치 파일을 새로 만들어 서버에서 실행합니다. 서버의 이미지와
설치 파일의 이미지가 다르면(이미지 id 비교) **자동으로 바꾸고**, 같으면 건너뜁니다 (`--rebuild` 를 붙이지 않아도 됨). 서버에서 불러온 이미지가
30일이 지났으면 새 설치 파일을 만들라고 알려 줍니다. 설정(몫·글꼴·`--warm`·uid 분리)은 서버의 `/etc/s2-docflow/converter.env` 와 설치된 명령에서
그대로 이어집니다.

**호스트 패치는 스크립트가 하지 않습니다** (운영체제 정책의 몫). 컨테이너 탈출은 대부분 커널·crun·Podman 취약점이므로 자동 보안 업데이트를 켜 둡니다.

```sh
# Ubuntu/Debian
sudo apt-get install -y unattended-upgrades && sudo dpkg-reconfigure -plow unattended-upgrades
# RHEL/Rocky/Alma
sudo dnf install -y dnf-automatic && sudo sed -i 's/^upgrade_type.*/upgrade_type = security/; s/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf && sudo systemctl enable --now dnf-automatic.timer
```

폐쇄망 서버는 사내 저장소(미러)로 같은 방식의 정기 패치를 합니다. 커널 업데이트는 재부팅해야 적용됩니다.

### 버전 관리

H2Orestart 와 rhwp 는 `s2-office-converter-versions.toml` 의 정책을 따릅니다 (_devtools2 의 `tool-versions.toml` 과 같은 방식).

| 상황 | 동작 |
|---|---|
| 처음 설치 | 묻지 않고 `[track]` 범위 안의 최신 버전으로 설치 |
| 설치된 버전보다 새 버전이 범위 안에 있음 | 업데이트할지 묻습니다 (기본 Y). `curl ... \| bash` 로 실행해도 터미널에서 묻습니다 |
| 무인 실행 (터미널 없음, cron 등) | 설치된 버전 유지. 강제하려면 `S2_CONVERTER_UPDATE=y`(업데이트) 또는 `n`(유지) |
| 범위 밖의 새 버전 (예: track `0.8` 인데 0.9.0) | 안내만 합니다. 올리려면 `[track]` 값을 바꿈 |
| 버전 파일에 검증값이 없는 새 버전 | 배포처의 검증값(GitHub 릴리스 digest, npm integrity)으로 확인해 설치하고, 버전 파일에 넣을 줄을 출력 |

- **설치된 버전 확인:** 이미지 태그(`4-h2o0.8.0-rhwp0.8.7-chrome`)와 라벨에 남습니다.
  `podman image inspect <이미지> --format '{{json .Labels}}'`
- **새 버전 기록 (개발자):** 출력된 줄을 버전 파일에 넣고 실제 문서(특히 HWP)로 확인한 뒤 커밋합니다. 언제 무엇을 올렸는지 Git 이력에 남습니다.
- **롤백:** 문제가 생기면 `[track]` 을 이전 전체 버전(예: `h2orestart = "0.7.14"`)으로 고정하고 스크립트를 다시 실행해 되돌리기에 동의합니다
  (무인 실행이면 `S2_CONVERTER_UPDATE=y`).
- LibreOffice·Chromium·Node.js·폰트는 Debian 패키지라 이미지를 만들 때의 최신 보안 업데이트가 들어갑니다 (`--rebuild` 로 다시 반영).

## 변환 몫과 컨테이너 재사용

### 변환 몫 (`--dedicated`, `--share`)

| 선택 | 동시 변환 수 | 메모리 예산 |
|---|---|---|
| 전용 (`--dedicated`) | CPU 코어 수와 (메모리 − 3GB) ÷ 1GB 중 작은 값 | 메모리 − 3GB (운영체제·변환 서버 몫) |
| 앱과 함께 (`--share 퍼센트`, 10~90) | CPU × 몫과 (메모리 × 몫) ÷ 1GB 중 작은 값 | 메모리 × 몫 |

- 처음 설치할 때 둘 다 없으면 물어봅니다 (무인 실행은 묻지 않고 앱 기본값: 동시 min(CPU, 4), 메모리 예산 물리 메모리의 절반). 다시 실행하면
  정한 값을 유지하고, 바꾸려면 옵션을 붙여 다시 실행합니다.
- 결과는 `/etc/s2-docflow/converter.env` (`S2_DOCFLOW_PARALLELISM`, `S2_DOCFLOW_MEMORY_MB`) 에 쓰고, **변환 명령, 앱의
  S2DocFlow, 변환 서버(`--server`)가 함께 읽습니다.** 앱 코드(`setConversionParallelism`, `setMemoryBudget`)나 `server.env` 의 값이 우선합니다.
- 규모 안내: 자리 하나를 초당 0.2건으로 계획하고(실측 0.43~0.5건의 절반 이하, 큰 문서·여유 고려), 1인당 하루 캐시에 없는 변환 10건·업무
  8시간·가장 몰릴 때 평균의 3배로 사용자 수를 셉니다 (사용자 ≈ 동시 변환 수 × 190). 예: 전용 8코어·16GB → 동시 8건, 약 1,500명.
  업로드 때 미리 변환(`prepare`)·캐시 적중이 많으면 더 많이, 큰 HWP·시트가 많으면 적게 잡습니다.

### 컨테이너: 기본은 변환마다 새로, 성능 우선이면 재사용 (`--warm`)

**기본(격리 우선):** 변환마다 네트워크 없는 새 컨테이너를 띄우고 끝나면 지웁니다. LibreOffice 는 계정마다 한 번 만들어 둔 프로필(읽기 전용)의
사본으로 시작해, 예전보다 건당 약 0.6초 빨라졌습니다.

**성능 우선(선택, `--warm` 또는 `S2_CONVERTER_WARM=1`):** 끝난 컨테이너를 잠시 남겨 두었다가 다음 작업에 다시 씁니다 (`podman exec`).
LibreOffice·Chromium 은 상주시키지 않고 작업마다 새로 띄우며, 작업이 끝나면 그 작업이 남긴 프로세스를 모두 끝내고 `/tmp` 를 비웁니다.

| 작은 문서 1건 (8회 중앙값) | 예전 | 기본 (새 컨테이너) | 성능 우선 (`--warm`) |
|---|---|---|---|
| 문서 (LibreOffice) | 1.60초 | 1.00초 | 0.69초 |
| 웹 페이지 (Chromium) | 1.20초 | 1.05초 | 0.76초 |
| 한글 (rhwp) | 2.20초 | 2.07초 | 1.76초 |

동시 8건이 계속 몰릴 때는 변환 자체의 CPU 가 병목이라 차이가 작습니다 (초당 3.4건 → 3.6~4.1건, 문서 종류 섞음).

> ⚠️ **`--warm` 의 격리:** 같은 컨테이너가 여러 사용자의 문서를 차례로 처리합니다. 앞 작업이 남긴 프로세스와 `/tmp` 는 지우므로 보통의 문서·
> 보통의 공격(남은 파일, 떼어 낸 프로세스)은 다음 작업에 닿지 않지만(시험으로 확인), **커널이나 컨테이너 런타임의 취약점을 이용해 프로세스를 벗어난
> 문서는 같은 컨테이너의 다음 작업에 영향을 줄 수 있습니다.** 변환마다 새 컨테이너보다 한 단계 약한 격리입니다. 외부에서 받은 문서를 많이 다루거나
> 민감한 문서를 다루면 기본값(새 컨테이너)을 쓰고, 응답 시간이 중요하고 문서 출처를 믿을 수 있을 때 켭니다.

| 설정 (`converter.env` 또는 환경 변수) | 기본 | 뜻 |
|---|---|---|
| `S2_CONVERTER_WARM` | `0` | `1` 이면 컨테이너 재사용 (설치 `--warm` / `--no-warm`, 한 번 정하면 유지) |
| `S2_CONVERTER_IDLE_SECONDS` | `600` | 재사용 시: 이 시간 동안 일이 없으면 컨테이너가 스스로 끝남 |
| `S2_CONVERTER_WARM_MAX` | `S2_DOCFLOW_PARALLELISM`, 없으면 CPU 수 | 재사용 시: 최대 대기 컨테이너 수. 넘는 요청은 새 컨테이너로 처리 |
| `S2_CONVERTER_WARM_USES` | `200` | 재사용 시: 이만큼 쓴 컨테이너는 새로 바꿈 |

- 재사용 중 시간 초과(124)·취소(143)가 난 컨테이너는 바로 지웁니다. 컨테이너가 사라졌으면(쉬다가 끝남 등) 다음 요청이 새로 띄웁니다.
- 자원 상한(`S2_SOFFICE_MEMORY`·`S2_*_CPUS` 등)을 지정하면 그 명령은 항상 새 컨테이너를 씁니다 (상한이 컨테이너 단위이므로).
- 확인: `sudo -u appuser podman ps --filter label=s2-office-converter-pool=1`. 설치 스크립트를 다시 실행하면 대기 컨테이너를 정리해 새 설정을 적용합니다.
- 상태 파일: `$XDG_RUNTIME_DIR/s2-converter-pool/` (계정별 프로필·자리, 재부팅하면 사라지고 다시 만듦).
- 판단 근거와 런타임 보강 방법: s2-docflow 의 [AGENTS.md](../AGENTS.md) 6장.

### uid 분리 (기본)

변환 컨테이너는 **앱 실행 계정이 아닌 하위 uid** 로 돕니다 (컨테이너 안 uid 1000 → 호스트의 `/etc/subuid` 범위 안 uid, 예: 166536). 문서가
커널·컨테이너 런타임 취약점으로 컨테이너를 벗어나더라도 앱 계정이 아니므로 **앱 계정의 파일(설정, DB 비밀번호, 홈 폴더)에 닿지 못합니다.**

- 결과 파일은 래퍼가 앱 계정 소유로 바꿔 넘깁니다. 결과로는 **일반 파일만** 넘깁니다 (컨테이너가 만든 심볼릭 링크로 호스트의 다른 파일을 결과로
  읽게 하는 것을 막음. 이 차단은 uid 분리를 끈 경우에도 적용).
- 비용: 이 uid 매핑용 이미지 사본 약 1.6GB (한 번), 처음 쓸 때 수 초 (설치 스크립트가 미리 준비). 변환 속도는 같습니다 (문서 1.03초 / 끈 경우 0.98초).
- 모든 변환 컨테이너가 같은 고정 범위를 씁니다. 컨테이너마다 범위를 다르게 주는 방식(`--userns=auto`)은 범위마다 이미지 사본이 생겨 실측 63벌, 89GB 가
  되어 쓰지 않습니다.
- 필요 조건: `/etc/subuid`·`/etc/subgid` 에 앱 계정 범위 1025개 이상 (설치 스크립트가 65536개를 넣음). Podman 이 하지 못하면 자동으로 앱 계정 uid 로
  실행하고 설치 때 알려 줍니다.
- 고객사 글꼴 폴더는 **다른 사용자도 읽을 수 있어야** 합니다 (`sudo chmod -R a+rX <폴더>`, 설치 스크립트가 확인).
- 끄기: `/etc/s2-docflow/converter.env` 에 `S2_CONVERTER_USERNS=keep-id` (앱 계정 uid 로 실행).

## 앱(S2OfficeConverter, S2DocumentMerger)에서 찾는 순서

1. `S2OfficeConverter.setCommand(...)` 로 지정한 명령
2. 환경 변수 `S2_SOFFICE`
3. PATH 의 `s2-soffice`, 그다음 `soffice`, `libreoffice`
4. 고정 경로 `/usr/local/bin/s2-soffice` (cron 처럼 PATH 가 좁은 환경 대비), LibreOffice 기본 설치 경로

웹 페이지 변환(`s2-chrome`)은 `S2DocumentMerger.setBrowserCommand(...)`, 환경 변수 `S2_CHROME`, PATH 의 `s2-chrome`,
`/usr/local/bin/s2-chrome` 순으로 찾습니다. **주의:** 그래도 없으면 지금은 PATH 의 일반 chromium/chrome, 표준 설치 경로,
Playwright 캐시의 브라우저까지 찾아 `--no-sandbox` 로 직접 실행합니다. 이때는 컨테이너 격리가 없고 네트워크도 열려 있으므로
(페이지의 JavaScript 가 내부망에 접속할 수 있음) 운영 서버에는 반드시 `s2-chrome` 을 설치하고, 일반 브라우저 자동 사용은
`S2DocumentMerger.setSystemBrowserAllowed(false)` 또는 `-Ds2.docflow.systemBrowser=false`(환경 변수 `S2_SYSTEM_BROWSER=false`)로 끄십시오.

```java
if (S2OfficeConverter.isAvailable()) {
    S2DocumentMerger.merge(List.of(PdfSource.ofDocument(Path.of("계획서.docx")),
            PdfSource.ofDocument(uploadedStream, "보고서.hwp")));
}
```

## s2-chrome

이미지·CSS 를 모두 넣은 HTML 파일을 Chromium 으로 PDF 인쇄하는 명령입니다. `S2DocumentMerger` 가 HTML·텍스트·SVG·마크다운 소스와
URL 로 받은 웹 페이지를 변환할 때 씁니다 (페이지의 이미지·CSS 는 앱이 받아서 넣은 뒤 넘김).

- 네트워크가 없는 컨테이너에서 실행하므로 페이지의 JavaScript 도 밖(내부망 포함)에 접속하지 못합니다.
- Chromium 자체 샌드박스는 rootless 컨테이너 안에서 쓸 수 없어 끄고(`--no-sandbox`), 컨테이너(네트워크 없음, 읽기 전용 루트,
  권한 제거, 호출자 uid)가 격리를 맡습니다.
- 제한 시간: 기본 60초 (`S2_CHROME_TIMEOUT`). 앱 쪽 제한은 `S2DocumentMerger.setBrowserTimeout`.
- 앱이 제한 시간에 보내는 SIGTERM 을 받으면 실행 중인 컨테이너를 `podman kill` 로 멈추고 끝납니다.
- 자원 상한(선택): `S2_CHROME_MEMORY`(예: `1g`), `S2_CHROME_CPUS`(예: `1.5`). 지정할 때만 붙으며 cgroup v2 위임이 있어야 합니다.

```sh
s2-chrome --print-to-pdf /tmp/out.pdf page.html
```

## 변환 서버 (`--server`)

다른 서버의 앱이 HTTP 로 변환을 맡기는 변환 전용 서버(s2-docflow-server)를 systemd 서비스로 설치합니다. 변환기와 같은 계정으로 돕니다.

```sh
bash setup-s2-office-converter.sh --app-user s2conv --server --server-jar ./s2-docflow-server-1.0.0.jar [--server-port 8090] [--server-bind 0.0.0.0] [--java <경로>]
bash setup-s2-office-converter.sh --app-user s2conv --no-server     # 서버만 제거
```

| 항목 | 위치 |
|---|---|
| 서버 jar | `/opt/s2-docflow/s2-docflow-server.jar` (s2-docflow 저장소에서 `./gradlew serverJar`) |
| 설정 (공유 비밀키 포함, 권한 600) | `/etc/s2-docflow/server.env` — 처음 설치할 때 비밀키를 만들고 이후 유지 |
| 캐시 | `/var/cache/s2-docflow` |
| 서비스 | `s2-docflow-server` (`systemctl status`, `journalctl -u s2-docflow-server`) |

- Java 17 이상이 필요합니다 (없으면 apt/dnf 로 설치, 폐쇄망은 미리 설치). 폐쇄망 설치 파일은 `--export ... --server-jar <jar>` 로 jar 를 함께 담습니다.
- 다시 실행해도 안전합니다: `--server-jar` 를 빼면 설치된 jar, 설정·비밀키는 그대로이며 바뀐 것이 있을 때만 재시작합니다.
- `--uninstall` 은 서버 설정·캐시까지 지웁니다.
- 앱 설정·API·보안·증설: s2-docflow 의 [docs/server.ko.md](https://github.com/devers2/s2-docflow/blob/main/docs/server.ko.md)

## s2-hwp

한글 문서(hwp, hwpx)를 PDF 로 만드는 명령입니다. 컨테이너 안에서 [rhwp](https://github.com/edwardkim/rhwp)(MIT, Rust +
WebAssembly)가 쪽을 SVG 로 조판하고 Chromium 이 인쇄합니다.

- LibreOffice + H2Orestart 와 달리 한글 프로그램과 같은 쪽 나눔·표·그림 배치를 따르고, 원본 글꼴(함초롬바탕 등)이 없으면 이미지에 든
  나눔명조·Noto Serif/Sans CJK 로 대체합니다 (글꼴을 따로 설치할 필요 없음). 글자는 PDF 에서 선택·검색됩니다.
- `S2OfficeConverter` 는 이 명령이 있으면 한글 PDF 에 먼저 쓰고, 실패하면 `s2-soffice` 로 다시 변환합니다
  (`S2OfficeConverter.setHwpRenderer(...)` 또는 `-Ds2.docflow.hwpRenderer=auto|rhwp|libreoffice`).
- 격리, 제한 시간(기본 180초, `S2_HWP_TIMEOUT`), SIGTERM 처리, 자원 상한(`S2_HWP_MEMORY`, `S2_HWP_CPUS`)은 `s2-soffice` 와 같습니다.
- 종료 코드: 0 성공, 2 사용법 오류, 3 암호가 걸린 문서, 4 읽을 수 없는 문서.
- `--no-chrome` 으로 설치하면 두지 않습니다.
- **고객사 글꼴(글꼴 팩):** 설치할 때 `--font-dir /opt/s2-fonts` 처럼 보유 글꼴(맑은 고딕, 휴먼명조, HY 계열 등) 폴더를 지정하면
  세 변환기가 변환할 때마다 그 폴더를 읽기 전용으로 연결합니다. 이미지에 넣지 않으므로 글꼴을 추가·교체해도 이미지를 다시 만들 필요가 없고,
  폐쇄망 설치 파일에도 들어가지 않습니다 (글꼴 라이선스 보호. 폐쇄망 서버에는 글꼴 폴더를 따로 옮기고 `--font-dir` 로 지정). 한 번 지정하면
  다시 실행해도 유지되며 `--no-font-dir` 로 뺍니다. 문서가 쓰는 글꼴이 없으면 앱 로그에 "한글 문서가 쓰는 글꼴이 변환기에 없어 … 대체했습니다:
  [휴먼명조, …]" 가 한 번씩 남습니다 (배치는 같고 글자 모양만 대체). 측정: 35쪽 HWP 8.1초 → 8.4초.
- **큰 문서:** 쪽을 50쪽씩(`S2_HWP_CHUNK`) 나눠 인쇄하고 qpdf 로 합칩니다. Chromium 메모리가 쪽 수와 상관없이 약 2GB 안팎입니다 (381쪽을
  한 번에 인쇄하면 약 4GB). 시간은 쪽 수에 비례합니다 (초당 약 7~8쪽, 381쪽 48초).
  - `--max-pages N`: 앞 N쪽과 "이하 M쪽은 넣지 않았습니다 (전체 T쪽)" 안내 쪽만 만듭니다 (381쪽 문서 100쪽 한도 16초). 앱에서는
    `PdfExportOptions.hwpPageBudget(n)`.
  - `S2_HWP_PARALLEL=3`: 묶음 3개를 동시에 인쇄 (381쪽 26초). 메모리도 그만큼 더 씁니다.

```sh
s2-hwp --outdir /tmp/out 보고서.hwp                   # → /tmp/out/보고서.pdf
s2-hwp --outdir /tmp/out --max-pages 100 편람.hwp     # 앞 100쪽 + 생략 안내 쪽
```

## s2-soffice

LibreOffice(`soffice`) 호환 명령입니다. 변환할 때마다 새 컨테이너에서 실행하며 다음을 지킵니다.

- 호출한 폴더가 아니라 **전용 사본**만 컨테이너에 연결
- 네트워크 차단, 읽기 전용 루트, 권한 제거, 호출자 uid (결과 파일 소유자 유지)
- 제한 시간: 기본 180초 (`S2_SOFFICE_TIMEOUT` 환경 변수로 변경)
- 앱이 제한 시간에 보내는 SIGTERM 을 받으면 실행 중인 컨테이너를 `podman kill` 로 멈추고 끝납니다 (이전에는 컨테이너가 내부 제한 시간까지 남을 수 있었음).
  이미 설치한 서버는 스크립트를 다시 실행해야 새 래퍼가 깔립니다.
- 자원 상한(선택): `S2_SOFFICE_MEMORY`(예: `1g`), `S2_SOFFICE_CPUS`(예: `1.5`). 지정할 때만 붙으며 cgroup v2 위임이 있어야 합니다
  (위임이 없는 rootless 계정에서는 podman 이 거부하므로 기본으로 켜지 않음). 앱 실행 환경의 환경 변수로 넘깁니다.

```sh
s2-soffice --headless --convert-to pdf --outdir /tmp/out 보고서.hwp
```

## 문제 해결

| 증상 | 확인 |
|---|---|
| 앱에서 "s2-office-converter 설치가 필요합니다" | 앱 실행 계정으로 설치했는지 (`sudo -u <계정> s2-soffice --version`) |
| "앱 실행 계정의 홈 폴더가 없습니다" | 안내된 명령으로 홈 폴더를 만든 뒤 다시 실행 |
| 한글 문서의 그림이 빈 상자(파란 사각형)로 나옴 | 이미지 버전 3 이전에 설치한 경우입니다. 스크립트를 다시 실행하면 새 이미지로 바뀝니다 (H2Orestart 가 그림을 처리할 작업 폴더를 쓰지 못하던 문제) |
| 한글 문서만 변환 실패 | `--rebuild` 로 이미지를 다시 만듦 (H2Orestart·rhwp 확인 결과는 마지막 확인 단계에 표시) |
| 한글 문서의 쪽 수·배치가 원본과 다름 | `s2-hwp` 가 설치되었는지 확인 (`sudo -u <계정> s2-hwp --version`). 없으면 LibreOffice 로 변환됩니다. 앱 로그에 "rhwp 로 변환하지 못해" 가 있으면 그 문서는 rhwp 가 읽지 못한 것입니다 |
| 새 버전으로 올린 뒤 변환 결과가 나빠짐 | 버전 파일의 `[track]` 을 이전 버전으로 고정하고 스크립트를 다시 실행 ([버전 관리](#버전-관리)) |
| 변환 결과에서 글자 모양이 원본과 다름 | 원본 문서에 쓴 글꼴이 없어서입니다 (앱 로그의 "글꼴이 변환기에 없어" 목록). 보유 글꼴 폴더를 `--font-dir <폴더>` 로 지정해 다시 실행합니다 (이미지는 다시 만들지 않음) |
| 폐쇄망 설치 파일에서 CPU·배포판 불일치 | 안내대로 `--target` 을 맞춰 인터넷 PC 에서 다시 `--export` |
| 폐쇄망 설치 파일 "체크섬 불일치" | 옮기는 중 손상됨. 파일을 다시 옮김 |
| 변환이 느림 | 변환마다 컨테이너를 새로 띄워 한 건에 수 초 걸립니다 (설계상 격리를 우선함) |
| HTML·웹 페이지 변환이 "브라우저 엔진이 없습니다" 로 실패 | `sudo -u <계정> s2-chrome --version` 으로 s2-chrome 이 동작하는지 확인. 내장 렌더러로 대신 변환하는 기능은 없습니다 (HTML 은 Chromium 으로만 변환) |
| 폐쇄망이라 Chromium 을 업데이트할 수 없음 | 그대로 써도 됩니다. 네트워크가 없는 컨테이너에서 이미 정리된 파일만 인쇄하므로 밖에서 공격받는 경로가 거의 없습니다. 업데이트는 인터넷 되는 PC 에서 `--export` 로 새 설치 파일을 만들어 옮깁니다 |

## 라이선스

이 스크립트는 LibreOffice(MPL 2.0), H2Orestart(MIT), rhwp(MIT), Node.js(MIT), qpdf(Apache 2.0), Chromium(BSD 3-Clause 등), 폰트(SIL OFL 1.1 등),
Podman(Apache 2.0)을 각 배포처에서 받아
설치할 뿐 재배포하지 않습니다. 각 소프트웨어는 자체 라이선스를 따릅니다. 폐쇄망 설치 파일을 다른 조직에 전달하면 그 안의
소프트웨어를 배포하는 것이 되므로 각 라이선스를 확인하십시오.
