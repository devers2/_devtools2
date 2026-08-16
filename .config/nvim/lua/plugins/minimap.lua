return {
  {
    'nvim-mini/mini.map',
    version = false,
    -- [성능] keys 없이는 lazy.lua의 기본값(lazy=false)이 적용되어 매 시작마다 무조건 로드됨.
    -- <leader>mm/<leader>mf를 처음 누를 때만 로드되도록 지연 트리거를 명시(setup() 자체는
    -- 가벼워 체감 영향은 작지만, 안 쓰는 세션에서도 매번 로드되는 건 불필요함).
    keys = {
      {
        '<leader>mm',
        function()
          require('mini.map').toggle()
        end,
        desc = 'Toggle Minimap',
      },
      {
        '<leader>mf',
        function()
          require('mini.map').toggle_focus()
        end,
        desc = 'Toggle Focus Minimap',
      },
    },
    config = function()
      local minimap = require('mini.map')

      minimap.setup({
        -- 미니맵에 표시할 데이터 소스
        integrations = {
          minimap.gen_integration.builtin_search(), -- 검색어 강조
          minimap.gen_integration.diff(), -- Git 변경점
          minimap.gen_integration.diagnostic(), -- 에러/경고
        },
        -- 미니맵 렌더링 스타일 (현재 커서 라인과 화면 영역 강조)
        symbols = {
          encode = minimap.gen_encode_symbols.dot('4x2'),
          scroll_line = '▶', -- 현재 커서 위치를 가리키는 화살표
          scroll_view = '┃', -- 현재 화면에 보이는 파일의 영역 표시
        },
        window = {
          focusable = true, -- 미니맵 포커스 허용
          side = 'right',
          width = 7, -- 너비
          winblend = 15, -- 투명도
        },
      })

      -- 단축키는 위쪽 keys 필드에서 지연 로드 트리거로 등록됨 (여기서 다시 set 하지 않음)

      -- 현재 위치 표시가 한눈에 잘 띄도록 밝은 색상 적용 (Kanagawa 테마 계열 매칭)
      vim.api.nvim_set_hl(0, 'MiniMapNormal', { fg = '#727169', bg = 'NONE' })
      vim.api.nvim_set_hl(0, 'MiniMapSymbolView', { fg = '#ff9e3b', bold = true }) -- 현재 화면 영역 (황색 강조)
      vim.api.nvim_set_hl(0, 'MiniMapSymbolLine', { fg = '#7e9cd8', bold = true }) -- 현재 커서 라인 (청색 화살표)
    end,
  },
}
