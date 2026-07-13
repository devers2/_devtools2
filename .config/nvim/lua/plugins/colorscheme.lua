return {
  -- Kanagawa 테마 플러그인 설치
  {
    'rebelot/kanagawa.nvim',
    name = 'kanagawa',
    lazy = false, -- 에디터 시작 시 바로 로드되도록 설정
    priority = 1000, -- 다른 플러그인보다 먼저 로드
    config = function()
      require('kanagawa').setup({
        compile = true, -- 성능 최적화를 위해 컴파일 사용
        undercurl = true, -- 언더커 컬(물결선) 활성화
        commentStyle = { italic = true },
        functionStyle = {},
        keywordStyle = { italic = true },
        statementStyle = { bold = true },
        typeStyle = {},
        transparent = true, -- 배경 투명화 여부
        dimInactive = true, -- 포커스되지 않은 창 어둡게 하기
        terminalColors = true, -- 터미널 색상 적용
        colors = {
          theme = {
            all = {
              ui = {
                bg_gutter = 'none', -- 라인 넘버 부분 배경 제거
              },
            },
          },
        },
        theme = 'wave', -- 기본 테마 선택: "wave", "dragon", "lotus" 중 선택 가능
        overrides = function(colors)
          local theme = colors.theme
          return {
            WinSeparator = { fg = theme.ui.fg_dim, bold = true },
          }
        end,
      })

      -- 테마 적용 명령
      vim.cmd('colorscheme kanagawa')

      -- 기본 경계선 모양 설정 (두껍게)
      -- vim.opt.fillchars = {
      --   vert = '┃',
      --   horiz = '━',
      -- }
    end,
  },
}
