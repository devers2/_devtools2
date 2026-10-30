return {
  -- VSCode 수준의 강력한 Git Diff 화면을 제공하는 플러그인
  -- (원본 sindrets/diffview.nvim 은 2024-08 이후 업데이트가 멈춰, 버그 수정이 계속되는 포크 diffview-plus 로 교체.
  --  모듈 이름(require('diffview'))·명령(:Diffview*)·키맵이 원본과 같아 설정을 그대로 씁니다.
  --  [되돌리기] 문제가 있으면 아래 저장소 이름만 'sindrets/diffview.nvim' 으로 바꾸고 :Lazy sync)
  -- 역할: 파일 이력(:DiffviewFileHistory)·3-way 병합 화면. 변경 내용 읽기는 아래 codediff.nvim 이 주력입니다.
  {
    'dlyongemallo/diffview-plus.nvim',
    cmd = {
      'DiffviewOpen',
      'DiffviewClose',
      'DiffviewToggleFiles',
      'DiffviewFocusFiles',
      'DiffviewFileHistory',
      'DiffviewLog',
      'DiffviewRefresh',
    },
    keys = {
      { '<leader>gq', '<cmd>DiffviewOpen<cr>', desc = 'Git Diffview 열기' },
      { '<leader>gQ', '<cmd>DiffviewClose<cr>', desc = 'Git Diffview 닫기' },
      { '<leader>gH', '<cmd>DiffviewFileHistory %<cr>', desc = 'Git 현재 파일 이력 (Diffview)' },
    },
    -- 키맵 설명 한글화: setup 전에 기본 키맵 표의 desc 를 util/diffview_ko.lua 사전으로 바꿉니다
    -- (g? 도움말·which-key 에 한글 표시, 사전에 없는 문구는 영어 유지 — lazygit 의 한국어 UI 와 맞춤)
    config = function(_, opts)
      local ok_ko, ko = pcall(require, 'util.diffview_ko')
      local ok_cfg, cfg = pcall(require, 'diffview.config')
      if ok_ko and ok_cfg and type(cfg.defaults) == 'table' and type(cfg.defaults.keymaps) == 'table' then
        for _, maps in pairs(cfg.defaults.keymaps) do
          if type(maps) == 'table' then
            for _, m in ipairs(maps) do
              local o = type(m) == 'table' and m[4] or nil
              if type(o) == 'table' and type(o.desc) == 'string' and ko[o.desc] then
                o.desc = ko[o.desc]
              end
            end
          end
        end
      end
      require('diffview').setup(opts or {})
    end,
  },

  -- VSCode 와 같은 diff 알고리즘으로 줄 + 글자 단위 두 겹 강조를 보여 주는 변경 리뷰 화면 (diff 읽기 주력)
  -- - 왼쪽 탐색기(변경 파일 목록) + 좌우 비교, 파일·hunk 단위 stage/unstage/discard, 병합 충돌 해결(블록·파일 단위)
  -- - 저장소가 바뀌면 화면이 따라 갱신되어, 에이전트가 작업하는 동안 변경을 바로 확인할 수 있습니다.
  -- - diff 계산 라이브러리(C)는 처음 실행할 때 GitHub 릴리스에서 미리 빌드된 파일을 자동으로 받습니다(컴파일러 불필요).
  --   받지 못한 경우 :CodeDiff install! 로 다시 받습니다.
  -- - [되돌리기] 이 블록을 지우거나 enabled = false 로 두면 끝입니다. lazygit(<leader>gg)·diffview 와 독립적입니다.
  -- 사용 예: :CodeDiff (작업 트리 변경) / :CodeDiff main (main 과 비교) / :CodeDiff main... (분기 이후 변경)
  --         :CodeDiff file HEAD (현재 파일 vs HEAD) / :CodeDiff history / :CodeDiff pr 512
  {
    'esmuellert/codediff.nvim',
    cmd = 'CodeDiff',
    -- [병합 충돌 해결] 예전 git-conflict.nvim(2024-12 이후 업데이트 없음)을 대신합니다.
    --   <leader>gx : 충돌·변경 파일 목록(탐색기의 "Merge Changes" 그룹에서 충돌 파일 선택)
    --   <leader>gm : 현재 파일의 충돌을 3-way 화면(Theirs │ Ours, 아래 Result)으로 열기
    --   충돌 화면 안에서만 동작하는 단축키(다른 곳의 <leader>c… 와 겹치지 않음):
    --     <leader>co 현재(Ours) · <leader>ct 들어온 변경(Theirs) · <leader>cb 둘 다 · <leader>cx 둘 다 버림(base)
    --     대문자(<leader>cO/cT/cB/cX)는 파일 전체 · ]x / [x 다음/이전 충돌 · 결과 창에서 2do / 3do (vimdiff 식)
    --   해결 후 :w 로 저장 → git add (또는 lazygit) 로 마무리
    keys = {
      { '<leader>gv', '<cmd>CodeDiff<cr>', desc = 'Git 변경 리뷰 (CodeDiff)' },
      { '<leader>gV', '<cmd>CodeDiff file HEAD<cr>', desc = 'Git 현재 파일 vs HEAD (CodeDiff)' },
      { '<leader>gx', '<cmd>CodeDiff<cr>', desc = 'Git 충돌·변경 목록 (CodeDiff)' },
      { '<leader>gm', '<cmd>CodeDiff merge %<cr>', desc = 'Git 현재 파일 충돌 해결 (CodeDiff)' },
    },
    opts = {},
  },
}
