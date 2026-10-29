-- ==============================================================================
-- diffview(-plus).nvim 키맵 설명(desc) 한글 사전
--
-- - diffview 는 다국어(i18n) 기능이 없지만, 기본 키맵 표(require('diffview.config').defaults.keymaps)의
--   각 항목이 { 모드, 키, 동작, { desc = "..." } } 형태라 setup 전에 desc 만 바꾸면
--   g? 도움말 창과 which-key 팝업에 한글 설명이 나옵니다(plugins/git.lua 의 diffview config 에서 적용).
-- - 사전에 없는 문구(업데이트로 새로 생긴 키 등)는 영어 그대로 남으므로 업데이트해도 깨지지 않습니다.
--   새 문구는 g? 에서 영어로 보이는 줄을 그대로 키로 추가하면 됩니다.
-- - 파일 목록의 "Changes", "Help: g?" 같은 화면 제목은 플러그인 코드에 직접 들어 있어 바꾸지 않습니다.
-- ==============================================================================
return {
  -- 파일 이동·열기
  ['Open the diff for the next file'] = '다음 파일 diff 열기',
  ['Open the diff for the previous file'] = '이전 파일 diff 열기',
  ['Open the diff for the first file'] = '첫 파일 diff 열기',
  ['Open the diff for the last file'] = '마지막 파일 diff 열기',
  ['Open the diff for the selected entry'] = '선택한 항목 diff 열기',
  ['Open the file in the previous tabpage'] = '이전 탭에서 파일 열기',
  ['Open the file in a new split'] = '새 분할 창에서 파일 열기',
  ['Open the file in a new tabpage'] = '새 탭에서 파일 열기',
  ['Open the file with default system application'] = '시스템 기본 앱으로 파일 열기',
  ['Open diffview in a new tab'] = '새 탭에서 diffview 열기',
  ['Open the entry under the cursor in a diffview'] = '커서 항목을 diffview 로 열기',
  ['Open a diffview comparing HEAD with the commit under the cursor'] = 'HEAD 와 커서의 커밋 비교 열기',

  -- 패널
  ['Bring focus to the file panel'] = '파일 패널로 이동',
  ['Toggle the file panel'] = '파일 패널 켜기/끄기',
  ['Close the panel'] = '패널 닫기',
  ['Bring the cursor to the next file entry'] = '다음 파일 항목으로',
  ['Bring the cursor to the previous file entry'] = '이전 파일 항목으로',
  ['Scroll the view down'] = '보기 아래로 스크롤',
  ['Scroll the view up'] = '보기 위로 스크롤',
  ["Toggle between 'list' and 'tree' views"] = "목록('list')/트리('tree') 보기 전환",
  ['Flatten empty subdirectories in tree listing style'] = '트리 보기에서 빈 하위 폴더 합치기',
  ['Update stats and entries in the file list'] = '파일 목록 통계·항목 새로고침',
  ['Cycle through available layouts'] = '레이아웃 순환 전환',
  ['Cycle available layouts'] = '레이아웃 순환 전환',

  -- 접기
  ['Expand fold'] = '접기 펼치기',
  ['Collapse fold'] = '접기',
  ['Toggle fold'] = '접기 전환',
  ['Expand all folds'] = '모든 접기 펼치기',
  ['Collapse all folds'] = '모두 접기',

  -- stage / 복원
  ['Stage / unstage the selected entry (jj: save & advance)'] = '선택 항목 stage/unstage (jj: 저장 후 다음)',
  ['Stage all entries'] = '전체 stage',
  ['Unstage all entries'] = '전체 unstage',
  ['Restore entry to the state on the left side'] = '항목을 왼쪽(이전) 상태로 되돌리기',
  ['Restore file to the state from the selected entry'] = '파일을 선택한 항목의 상태로 되돌리기',
  ['Obtain the diff hunk from the old-side version'] = '이전 쪽 hunk 가져오기',

  -- 여러 파일 선택·리뷰
  ['Toggle file selection for multi-file operations'] = '여러 파일 작업용 선택 전환',
  ['Clear all file selections'] = '파일 선택 모두 해제',
  ['Toggle hiding reviewed (selected) files'] = '리뷰한(선택한) 파일 숨기기 전환',

  -- 커밋 로그·이력
  ['Open the commit log panel'] = '커밋 로그 패널 열기',
  ['Open the commit log panel filtered to the file under the cursor'] = '커서 파일의 커밋 로그 열기',
  ['Close commit log'] = '커밋 로그 닫기',
  ['Show commit details'] = '커밋 상세 보기',
  ['Copy the commit hash of the entry under the cursor'] = '커서 항목의 커밋 해시 복사',

  -- 옵션·도움말
  ['Open the option panel'] = '옵션 패널 열기',
  ['Change the current option'] = '현재 옵션 바꾸기',
  ['Open the help panel'] = '도움말 열기',
  ['Close help menu'] = '도움말 닫기',

  -- 병합 충돌 (3-way / 4-way 병합 화면)
  ['Go to the next conflict'] = '다음 충돌로',
  ['Go to the previous conflict'] = '이전 충돌로',
  ['Jump to the next conflict marker'] = '다음 충돌 표시로',
  ['Jump to the previous conflict marker'] = '이전 충돌 표시로',
  ['Choose the OURS version of a conflict'] = '충돌: OURS(현재) 선택',
  ['Choose the THEIRS version of a conflict'] = '충돌: THEIRS(들어온 변경) 선택',
  ['Choose the BASE version of a conflict'] = '충돌: BASE(공통 조상) 선택',
  ['Choose all the versions of a conflict'] = '충돌: 모든 버전 유지',
  ['Delete the conflict region'] = '충돌 영역 삭제',
  ['Choose the OURS version of a conflict for the whole file'] = '파일 전체 충돌: OURS 선택',
  ['Choose the THEIRS version of a conflict for the whole file'] = '파일 전체 충돌: THEIRS 선택',
  ['Choose the BASE version of a conflict for the whole file'] = '파일 전체 충돌: BASE 선택',
  ['Choose all the versions of a conflict for the whole file'] = '파일 전체 충돌: 모든 버전 유지',
  ['Delete the conflict region for the whole file'] = '파일 전체 충돌 영역 삭제',
  ['Diffget the cursor hunk from OURS'] = '커서 hunk 를 OURS 에서 가져오기',
  ['Diffget the cursor hunk from THEIRS'] = '커서 hunk 를 THEIRS 에서 가져오기',
  ['Diffget the cursor hunk from BASE'] = '커서 hunk 를 BASE 에서 가져오기',
  ['Replace the MERGED buffer with the entire OURS side'] = '결과(MERGED)를 OURS 전체로 바꾸기',
  ['Replace the MERGED buffer with the entire THEIRS side'] = '결과(MERGED)를 THEIRS 전체로 바꾸기',
  ['Replace the MERGED buffer with the entire BASE side'] = '결과(MERGED)를 BASE 전체로 바꾸기',

  -- 인라인 diff
  ['Jump to the next inline-diff hunk'] = '다음 인라인 diff hunk 로',
  ['Jump to the previous inline-diff hunk'] = '이전 인라인 diff hunk 로',

  -- worktree
  ['Bring the cursor to the next worktree'] = '다음 worktree 로',
  ['Bring the cursor to the previous worktree'] = '이전 worktree 로',
  ['Open DiffView for the selected worktree'] = '선택한 worktree 의 DiffView 열기',
  ['Re-scan worktrees and stats'] = 'worktree·통계 다시 읽기',
}
