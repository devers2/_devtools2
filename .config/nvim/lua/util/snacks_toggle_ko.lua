-- ==============================================================================
-- Snacks 토글 이름 한글 사전 (<leader>u 계열 · <leader>wm · <leader>dpp 등)
--
-- - Snacks.toggle 은 which-key 설명을 상태에 따라 "켜기/끄기 + 이름"으로 바꿔 보여 주는데, 이름이 영어라
--   예전에는 whichkey.lua 에 고정된 한글 설명을 따로 적었습니다. 그러면 같은 키가 두 번 등록되어
--   :checkhealth which-key 중복 경고가 나고, 상태와 맞지 않거나(항상 "활성화") 틀린 설명(<leader>uc 를
--   "테마 변경"으로 표시 — 실제는 Conceal 토글)이 남았습니다.
-- - plugins/snacks.lua 가 토글을 만드는 함수(Snacks.toggle.new) 뒤에서 이 사전으로 이름만 바꿉니다.
--   id 는 영어 이름 기준 그대로라 Snacks.toggle.get("wrap") 같은 조회는 바뀌지 않습니다.
-- - 사전에 없는 토글(업데이트로 새로 생긴 것 등)은 영어 그대로 남습니다. 새 이름은 아래에 추가하면 됩니다.
-- ==============================================================================
return {
  ['Animations'] = '애니메이션',
  ['Auto Format (Buffer)'] = '자동 포맷 (현재 버퍼)',
  ['Auto Format (Global)'] = '자동 포맷 (전체)',
  ['Dark Background'] = '어두운 배경',
  ['Conceal Level'] = '문자 숨김 (Conceal)',
  ['Diagnostics'] = '진단 표시',
  ['Dimming'] = '주변 흐리게 (Dim)',
  ['Git Signs'] = 'Git 변경 표시',
  ['Indent Guides'] = '들여쓰기 가이드',
  ['Inlay Hints'] = '인레이 힌트',
  ['Line Numbers'] = '줄 번호',
  ['Mini Pairs'] = '괄호 자동 닫기 (Mini Pairs)',
  ['Profiler'] = '프로파일러',
  ['Profiler Highlights'] = '프로파일러 하이라이트',
  ['Relative Number'] = '상대 줄 번호',
  ['Render Markdown'] = '마크다운 렌더링',
  ['Smooth Scroll'] = '부드러운 스크롤',
  ['Tabline'] = '탭라인',
  ['Spelling'] = '맞춤법 검사',
  ['Treesitter Highlight'] = 'Treesitter 하이라이트',
  ['Wrap'] = '줄 바꿈',
  ['Zen Mode'] = '젠 모드',
  ['Zoom Mode'] = '줌 모드 (창 최대화)',
}
