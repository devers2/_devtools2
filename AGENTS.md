# DevTools2 AI 에이전트 개발 및 검증 절대 원칙 (AGENTS.md)

이 문서는 `_devtools2` 저장소의 코드를 분석, 수정, 생성하는 모든 AI 에이전트가 준수해야 할 **절대 원칙 및 검증 가이드라인**입니다.

---

## 🚨 [CRITICAL RULE] 코드 수정 후 통합 테스트 필수 실행

스크립트(`.ps1`, `.sh`) 또는 설정 파일을 수정한 후에는 **사용자에게 답변하거나 커밋하기 전에 반드시 아래 통합 테스트 러너를 실행하여 전수 통과(100% PASS)를 검증**해야 합니다.

### 실행 명령어
```powershell
# Windows PowerShell / pwsh 공통 (가장 권장)
.\tests\run-all-tests.bat

# 또는 pwsh 직접 실행
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\run-all-tests.ps1
```

> ⚠️ 개별 임의 테스트로 대체하지 마십시오. 반드시 공식 테스트 러너를 실행하여 회귀 버그 및 파싱 오류를 사전 차단하십시오.

---

## 1. 인코딩 절대 원칙: UTF-8 NoBOM
- **저장소의 모든 텍스트 파일은 순수 UTF-8 NoBOM(Byte Order Mark 없음)이어야 합니다.**
- PowerShell 스크립트 작성/수정 시 UTF-8 BOM이 포함되지 않도록 주의하십시오.
- .NET 인코딩 처리 시 `[System.Text.UTF8Encoding]::new($false)`를 사용하십시오.

---

## 2. 100% 온라인 스트리밍 실행 모델 준수
- 서브스크립트는 GitHub 원격 raw URL(`https://raw.githubusercontent.com/devers2/_devtools2/${DT2_REF:-main}/...`)에서 직접 메모리 스트리밍(`bash <(curl ...)` 또는 `[scriptblock]::Create`)으로 실행됩니다.
- 로컬 파일에 의존하는 하드코딩 경로 분기(`IS_LOCAL` 등)를 임의로 추가하지 마십시오.

---

## 3. PowerShell 5.1 & PowerShell 7 양방향 호환성
- **`param()` 블록 최상단 배치**: `.ps1` 파일의 `param(...)` 블록 앞에는 주석 외의 어떤 실행문도 위치해서는 안 됩니다 (PS 5.1 NoBOM 파싱 에러 방지).
- **널 병합 연산자(`??`) 사용 금지**: Windows PowerShell 5.1 호환을 위해 삼항 연산자나 `if/else`를 사용하십시오.
- **문자열 변수 스코프 충돌 방지**: 쌍따옴표 문자열 내에서 변수 뒤에 콜론이 오는 경우 반드시 `${var}:` 형식을 사용하십시오.
- **`.Trim()` 호출 시 널 가드**: `$null` 대상의 `.Trim()` 호출 크래시를 방지하기 위해 `if (-not [string]::IsNullOrWhiteSpace($val))` 검증을 선행하십시오.

---

## 4. 보안 및 권한 격리 원칙
- **비밀번호 프로세스 인자 노출 금지**:
  - Bitwarden: `bw unlock --passwordenv BW_PASSWORD` 사용 (인자 노출 차단).
  - rclone: `printf '%s' "$pass" | rclone obscure -` (stdin 파이프 전달).
- **권한 최소화 및 격리**:
  - 공유 디렉터리: `2770` (others 접근 완전 차단).
  - 일반 파일: `o-rwx`.
  - 민감 자격증명(`rclone.conf`, SSH 키, `.bw_session*`, `.env*`): 소유자 전용 `600`, 디렉터리 `700`.
- **임시 권한 즉시 회수**:
  - 설치용 임시 `passwordless sudo`는 설치 종료 시 및 비정상 중단 시(`trap ... EXIT`) 100% 회수되어야 합니다.

---

## 5. 멱등성(Idempotency) 보장
- 스크립트를 몇 번을 재실행하더라도 동일한 정상 상태로 수렴해야 하며, 기존 사용자 설정(`.vscode/launch.json`, `.gradle/init.d/debug.gradle` 등)을 임의로 덮어쓰거나 삭제해서는 안 됩니다.
