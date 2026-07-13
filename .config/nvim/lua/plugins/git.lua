return {
  -- VSCode 수준의 강력한 Git Diff 화면을 제공하는 플러그인
  {
    'sindrets/diffview.nvim',
    cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewToggleFiles', 'DiffviewFocusFiles' },
    keys = {
      { '<leader>gq', '<cmd>DiffviewOpen<cr>', desc = 'Git Diffview 열기' },
      { '<leader>gQ', '<cmd>DiffviewClose<cr>', desc = 'Git Diffview 닫기' },
    },
  },
}
