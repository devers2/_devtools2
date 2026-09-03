-- 오류 메시지 가독성 향상 플러그인 설정
-- 1. Trouble.nvim: 전체 오류 목록을 하단 패널에 모아보기 (이미 lazyvim.json에서 활성화)
-- 2. tiny-inline-diagnostic.nvim: 코드 줄 바로 아래에 예쁜 오류 메시지 표시

return {
  -- tiny-inline-diagnostic 설정
  {
    'rachartier/tiny-inline-diagnostic.nvim',
    event = 'VeryLazy', -- 지연 로딩
    priority = 1000, -- 높은 우선순위
    config = function()
      require('tiny-inline-diagnostic').setup({
        -- 가독성을 위해 기본 가상 텍스트(오른쪽 끝에 뜨는 빨간 글씨)는 끔
        -- 이 플러그인이 훨씬 이쁘게 대신 보여줄 것임
        options = {
          -- 오류 메시지 앞에 표시할 아이콘
          signs = {
            left = '',
            right = '',
            diag = '󰮭',
            arrow = '  ',
            up_arrow = '  ',
            vertical = ' │',
            vertical_end = ' └',
          },
          -- 현재 커서가 있는 줄의 오류만 보여줄지 여부 (기본 false: 모든 줄 보임)
          -- 너무 시끄러운 게 싫다면 true로 변경 가능
          show_all_diags_on_cmdline = false,
        },
      })

      -- 순성 Neovim의 기본 인라인 가상 텍스트를 비활성화 (tiny-inline과 겹침 방지)
      vim.diagnostic.config({ virtual_text = false })
    end,
  },

  -- [iamcco/markdown-preview.nvim 비활성화]
  -- 버퍼 내부에서 실시간 렌더링하는 최신 render-markdown.nvim이 전담하므로,
  -- Node.js 백그라운드 프로세스를 띄우는 레거시 브라우저 프리뷰어는 비활성화하여 리소스 절약
  { 'iamcco/markdown-preview.nvim', enabled = false },
}
