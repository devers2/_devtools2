-- ===========================================================================================
-- [기본 검증 번역 사전: Base Translation Dictionary]
-- ===========================================================================================
--
-- 📌 [역할 및 특징]
-- 1. Git 형상관리 대상:
--    - 이 파일은 Git에 커밋되어 팀원과 공유되거나 신규 환경에서도 기본 탑재되어 즉시 동작합니다.
--
-- 2. 1순위 최우선 번역 (0ms 즉시 반환):
--    - 런타임 동적 캐시나 온라인 번역기보다 항상 최우선으로 적용됩니다.
--    - 오번역 방지 필터에 의해 '자동 동적 번역에서 제외된 항목'(예: 콜론, 특수문자, 포트번호,
--      짧은 단어, 특정 DAP Launch 설정 등)도 여기에 명시적으로 등록하면 100% 한글화됩니다.
--
-- 3. 등록 형식 가이드:
--    - 기본 형식: ['영문 원본'] = { ko = '한글 설명' }
--    - 축약 형식: ['영문 원본'] = '한글 설명'
--
-- 4. 🚫 [절대 번역 금지 / 영문 원본 고정 (Ignore List)]:
--    - 특정 고유 명칭이나 플러그인 기능명을 영문 그대로 유지하고 싶을 때는 값을 `false`로 지정합니다.
--    - 온라인 번역 큐 전송 및 캐시 조회가 모두 완벽히 차단되어 100% 영문 원본으로 고정됩니다.
--    - 예시:
--        ['Toggle Copilot'] = false,       -- ➔ 무조건 영문 원본 고정 (번역 완전 제외)
--        ['Git blame line'] = false,       -- ➔ 무조건 영문 원본 고정
--
-- ===========================================================================================

local M = {
  -- ── 1. DAP 디버그 활성 세션 및 스레드 메뉴 (<leader>ds 등) ──
  ['Resume stopped thread'] = { ko = '멈춰있는 스레드 재개' },
  ['Disconnect (terminate = true)'] = { ko = '디버깅 및 서버 프로세스 강제 종료' },
  ['Disconnect (terminate = false)'] = { ko = '디버거 연결만 끊기 - 서버 계속 실행' },
  ['Restart session'] = { ko = '디버그 세션 재시작' },
  ['Terminate session'] = { ko = '디버그 세션 종료' },
  ['Pause a thread'] = { ko = '스레드 일시 정지' },
  ['Start additional session'] = { ko = '추가 디버그 세션 시작' },
  ['Do nothing'] = { ko = '아무 작업도 하지 않음 (취소)' },

  -- ── 2. LSP 코드 액션 (Code Actions) 및 리팩토링 메뉴 (<leader>ca 등) ──
  ['Organize imports'] = { ko = 'Import 구문 정리' },
  ['Extract method'] = { ko = '메서드 추출' },
  ['Extract local variable'] = { ko = '로컬 변수 추출' },
  ['Extract constant'] = { ko = '상수 추출' },
  ['Extract interface'] = { ko = '인터페이스 추출' },
  ['Add missing @Override annotation'] = { ko = '누락된 @Override 어노테이션 추가' },
  ['Generate Getters and Setters...'] = { ko = 'Getter / Setter 생성' },
  ['Generate Constructors...'] = { ko = '생성자(Constructor) 생성' },
  ['Generate hashCode() and equals()...'] = { ko = 'hashCode() 및 equals() 생성' },
  ['Generate toString()...'] = { ko = 'toString() 메서드 생성' },
  ['Surround with try/catch'] = { ko = 'try/catch 문으로 감싸기' },
  ['Rename file to match type'] = { ko = '타입 이름과 일치하도록 파일명 변경' },
  ['Assign parameter to new field'] = { ko = '매개변수를 새 필드에 할당' },
  ['Move type to new file'] = { ko = '타입을 새 파일로 이동' },
  ['Change type of'] = { ko = '타입 변경' },
  ['Create getter and setter for'] = { ko = 'Getter / Setter 생성' },
  -- ── 3. Java / Gradle LSP 진행 상태 및 핵심 알림 ──
  ['Starting Java Language Server'] = { ko = 'Java 언어 서버 시작 중' },
  ['Synchronize Gradle project goono-eln with workspace project'] = {
    ko = 'Gradle 프로젝트와 워크스페이스 동기화',
  },
  ['Synchronize Gradle project'] = { ko = 'Gradle 프로젝트 동기화' },
  ['Updating goono-eln configuration'] = { ko = 'goono-eln 빌드 구성 업데이트 중' },
  ['Updating project configuration'] = { ko = '프로젝트 빌드 구성 업데이트 중' },
  ['ServiceReady'] = { ko = '서비스 준비 완료' },
  ['OK'] = { ko = '완료' },
  ['Ready'] = { ko = '준비 완료' },
  ['Init...'] = { ko = '초기화 중...' },
  ['Building workspace'] = { ko = '워크스페이스 빌드 중' },
  ['Processing resources'] = { ko = '리소스 처리 중' },

  -- ── 4. Vim 시스템 에러 / 주요 알림 ──
  ["Cannot make changes, 'modifiable' is off"] = {
    ko = "수정할 수 없습니다 ('modifiable' 꺼짐)",
  },
  ['Pattern not found'] = { ko = '패턴을 찾을 수 없습니다' },
  ['No write since last change (add ! to override)'] = {
    ko = '마지막 변경 후 저장되지 않았습니다 (강제 실행: ! 추가)',
  },
  ['written'] = { ko = '저장되었습니다' },

  -- ── 5. 단어 사전 (translate_by_words 단어 합성용 단어 단위 항목) ──
  -- 템플릿 번역 시 개별 단어를 dict.lua에서 직접 조회하여 사용합니다.
  -- 전치사/접속사/관사는 init.lua의 _word_particles에서 별도 처리됩니다.
  ['Building'] = { ko = '빌드 중' },
  ['building'] = { ko = '빌드 중' },
  ['Cleaning'] = { ko = '정리' },
  ['cleaning'] = { ko = '정리' },
  ['output'] = { ko = '출력' },
  ['Output'] = { ko = '출력' },
  ['folder'] = { ko = '폴더' },
  ['Folder'] = { ko = '폴더' },
  ['workspace'] = { ko = '워크스페이스' },
  ['Workspace'] = { ko = '워크스페이스' },
  ['project'] = { ko = '프로젝트' },
  ['Project'] = { ko = '프로젝트' },
  ['projects'] = { ko = '프로젝트' },
  ['Projects'] = { ko = '프로젝트' },
  ['dependencies'] = { ko = '종속성' },
  ['Dependencies'] = { ko = '종속성' },
  ['configuration'] = { ko = '구성' },
  ['Configuration'] = { ko = '구성' },
  ['Diagnostics'] = { ko = '진단' },
  ['diagnostics'] = { ko = '진단' },
  ['Publish'] = { ko = '게시' },
  ['publish'] = { ko = '게시' },
  ['Resolve'] = { ko = '해결' },
  ['resolve'] = { ko = '해결' },
  ['Searching'] = { ko = '검색 중' },
  ['searching'] = { ko = '검색 중' },
  ['Search'] = { ko = '검색' },
  ['Analyze'] = { ko = '분석' },
  ['Analyzing'] = { ko = '분석 중' },
  ['Initialize'] = { ko = '초기화' },
  ['Initializing'] = { ko = '초기화 중' },
  ['Synchronize'] = { ko = '동기화' },
  ['Synchronizing'] = { ko = '동기화 중' },
  ['Importing'] = { ko = '가져오는 중' },
  ['Loading'] = { ko = '로드 중' },
  ['Detect'] = { ko = '감지' },
  ['Validate'] = { ko = '유효성 검사' },
  ['Validating'] = { ko = '유효성 검사 중' },
  ['Update'] = { ko = '업데이트' },
  ['Updating'] = { ko = '업데이트 중' },
  ['Fetch'] = { ko = '가져오기' },
  ['Fetching'] = { ko = '가져오는 중' },
  ['Run'] = { ko = '실행' },
  ['Running'] = { ko = '실행 중' },
  ['Start'] = { ko = '시작' },
  ['Starting'] = { ko = '시작 중' },
  ['Stop'] = { ko = '중지' },
  ['Stopping'] = { ko = '중지 중' },
  ['done'] = { ko = '완료' },
  ['Done'] = { ko = '완료' },
  ['task'] = { ko = '작업' },
  ['Task'] = { ko = '작업' },
  ['tasks'] = { ko = '작업' },
  ['installed'] = { ko = '설치된' },
  ['Installed'] = { ko = '설치된' },
  ['resources'] = { ko = '리소스' },
  ['Resources'] = { ko = '리소스' },
  ['sources'] = { ko = '소스' },
  ['Sources'] = { ko = '소스' },
  ['settings'] = { ko = '설정' },
  ['Settings'] = { ko = '설정' },
  ['files'] = { ko = '파일' },
  ['Files'] = { ko = '파일' },
  ['data'] = { ko = '데이터' },
  ['Data'] = { ko = '데이터' },
  ['error'] = { ko = '오류' },
  ['Error'] = { ko = '오류' },
  ['errors'] = { ko = '오류' },
  ['Errors'] = { ko = '오류' },
  ['warning'] = { ko = '경고' },
  ['Warning'] = { ko = '경고' },
  ['warnings'] = { ko = '경고' },
  ['Warnings'] = { ko = '경고' },
}

return M
