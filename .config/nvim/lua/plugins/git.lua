return {
  -- VSCode 수준의 강력한 Git Diff 화면을 제공하는 플러그인
  {
    'sindrets/diffview.nvim',
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
    },
  },

  -- Git 3-Way 병합 충돌 시각화 및 원클릭 해결 플러그인 (VSCode/IntelliJ 스타일)
  -- co: 현재(Ours) 선택 | ct: 들어오는 변경(Theirs) 선택 | cb: 양쪽(Both) 유지 | c0: 모두 삭제
  -- [x: 이전 충돌로 이동 | ]x: 다음 충돌로 이동
  {
    'akinsho/git-conflict.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    opts = {
      default_mappings = true,
      default_commands = true,
      disable_diagnostics = false,
      list_opener = 'copen',
      highlights = {
        incoming = 'DiffAdd',
        current = 'DiffText',
      },
    },
  },
}
