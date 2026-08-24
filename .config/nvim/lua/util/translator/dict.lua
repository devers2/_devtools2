-- [기본 검증 번역 사전: Base Translation Dictionary]
-- 이 파일은 Git 형상관리 대상(커밋 대상)이며, 신규 환경에서도 기본 탑재되어 즉시 동작합니다.
-- 사용자가 자주 사용하는 메뉴, 리팩토링 기능, 주요 알림을 직접 추가/수정할 수 있습니다.

local M = {
  -- ── 1. DAP 디버그 세션 및 스레드 메뉴 ──
  ['Disconnect (terminate = true)'] = { ko = '디버깅 및 서버 프로세스 강제 종료', priority = 1 },
  ['Disconnect (terminate = false)'] = { ko = '디버거 연결만 끊기 - 서버 계속 실행', priority = 2 },
  ['Restart session'] = { ko = '디버그 세션 재시작', priority = 3 },
  ['Terminate session'] = { ko = '디버그 세션 종료', priority = 4 },
  ['Pause a thread'] = { ko = '스레드 일시 정지', priority = 5 },
  ['Start additional session'] = { ko = '추가 디버그 세션 시작', priority = 6 },
  ['Do nothing'] = { ko = '아무 작업도 하지 않음 (취소)', priority = 7 },
  ['Resume stopped thread'] = { ko = '멈춰있는 스레드 재개', priority = 0 },

  -- ── 2. LSP 코드 액션 (Code Actions) 및 리팩토링 메뉴 ──
  ['Organize imports'] = { ko = 'Import 구문 정리', priority = 10 },
  ['Extract method'] = { ko = '메서드 추출', priority = 11 },
  ['Extract local variable'] = { ko = '로컬 변수 추출', priority = 12 },
  ['Extract constant'] = { ko = '상수 추출', priority = 13 },
  ['Extract interface'] = { ko = '인터페이스 추출', priority = 14 },
  ['Add missing @Override annotation'] = { ko = '누락된 @Override 어노테이션 추가', priority = 15 },
  ['Generate Getters and Setters...'] = { ko = 'Getter / Setter 생성', priority = 16 },
  ['Generate Constructors...'] = { ko = '생성자(Constructor) 생성', priority = 17 },
  ['Generate hashCode() and equals()...'] = { ko = 'hashCode() 및 equals() 생성', priority = 18 },
  ['Generate toString()...'] = { ko = 'toString() 메서드 생성', priority = 19 },
  ['Surround with try/catch'] = { ko = 'try/catch 문으로 감싸기', priority = 20 },
  ['Rename file to match type'] = { ko = '타입 이름과 일치하도록 파일명 변경', priority = 21 },
  ['Assign parameter to new field'] = { ko = '매개변수를 새 필드에 할당', priority = 22 },
  ['Move type to new file'] = { ko = '타입을 새 파일로 이동', priority = 23 },
  ['Change type of'] = { ko = '타입 변경', priority = 24 },
  ['Create getter and setter for'] = { ko = 'Getter / Setter 생성', priority = 25 },

  -- ── 3. Java / Gradle LSP 진행 상태 및 알림 ──
  ['Starting Java Language Server'] = { ko = 'Java 언어 서버 시작 중' },
  ['Synchronize Gradle project goono-eln with workspace project'] = { ko = 'Gradle 프로젝트와 워크스페이스 동기화' },
  ['Synchronize Gradle project'] = { ko = 'Gradle 프로젝트 동기화' },
  ['Updating goono-eln configuration'] = { ko = 'goono-eln 빌드 구성 업데이트 중' },
  ['Updating project configuration'] = { ko = '프로젝트 빌드 구성 업데이트 중' },
  ['ServiceReady'] = { ko = '서비스 준비 완료' },
  ['OK'] = { ko = '완료' },
  ['Ready'] = { ko = '준비 완료' },
  ['Init...'] = { ko = '초기화 중...' },
  ['Building'] = { ko = '빌드 중' },
  ['Building workspace'] = { ko = '워크스페이스 빌드 중' },
  ['Processing resources'] = { ko = '리소스 처리 중' },

  -- ── 4. Vim 시스템 에러 / 주요 알림 ──
  ["Cannot make changes, 'modifiable' is off"] = { ko = "수정할 수 없습니다 ('modifiable' 꺼짐)" },
  ['Pattern not found'] = { ko = '패턴을 찾을 수 없습니다' },
  ['No write since last change (add ! to override)'] = { ko = '마지막 변경 후 저장되지 않았습니다 (강제 실행: ! 추가)' },
  ['written'] = { ko = '저장되었습니다' },
}

return M
